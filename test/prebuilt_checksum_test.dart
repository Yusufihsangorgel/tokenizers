import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

/// The build hook downloads a native library and loads it into the process.
/// These tests serve the download from a local server and check that only
/// the pinned bytes get through.
void main() {
  const asset = 'libtokenizers_ffi-macos-arm64.dylib';
  final library = List<int>.generate(4096, (i) => (i * 31) & 0xff);
  final pinned = {hook.prebuiltPath(asset): sha256.convert(library).toString()};

  late HttpServer server;
  late Directory dir;
  late Uri dest;
  // The bytes the server answers with, or null for a 404.
  List<int>? served;
  var requests = 0;

  setUp(() async {
    served = library;
    requests = 0;
    dir = await Directory.systemTemp.createTemp('prebuilt_checksum_');
    dest = dir.uri.resolve('libtokenizers_ffi.dylib');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests++;
      final body = served;
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(body);
      }
      request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  String root() => 'http://${server.address.host}:${server.port}';

  // A library an earlier build left behind.
  void leaveStaleFile() => File.fromUri(dest).writeAsBytesSync([1, 2, 3]);

  test('a download with the pinned hash is kept', () async {
    final fetched = await hook.fetchPrebuilt(
      asset,
      dest,
      releaseRoot: root(),
      pins: pinned,
    );

    expect(fetched, isTrue);
    expect(File.fromUri(dest).readAsBytesSync(), library);
  });

  test('one flipped byte fails the build and writes nothing', () async {
    leaveStaleFile();
    final tampered = [...library];
    tampered[1000] ^= 0x01;
    served = tampered;

    await expectLater(
      hook.fetchPrebuilt(asset, dest, releaseRoot: root(), pins: pinned),
      throwsA(
        isA<Exception>().having(
          (e) => '$e',
          'message',
          allOf(
            contains('does not match the SHA-256 pinned'),
            contains(sha256.convert(library).toString()),
            contains(sha256.convert(tampered).toString()),
          ),
        ),
      ),
    );
    expect(File.fromUri(dest).existsSync(), isFalse);
  });

  test('an asset with no pinned hash fails before any request', () async {
    await expectLater(
      hook.fetchPrebuilt(asset, dest, releaseRoot: root(), pins: const {}),
      throwsA(
        isA<Exception>().having(
          (e) => '$e',
          'message',
          contains(
            'pins no SHA-256 for the prebuilt ${hook.prebuiltPath(asset)}',
          ),
        ),
      ),
    );
    expect(requests, 0);
    expect(File.fromUri(dest).existsSync(), isFalse);
  });

  test('a 404 returns false and removes a stale file', () async {
    leaveStaleFile();
    served = null;

    final fetched = await hook.fetchPrebuilt(
      asset,
      dest,
      releaseRoot: root(),
      pins: pinned,
    );

    expect(fetched, isFalse);
    expect(File.fromUri(dest).existsSync(), isFalse);
  });

  group('a server that breaks off', () {
    late ServerSocket raw;
    late Future<void> Function(Socket) answer;
    final open = <Socket>[];

    setUp(() async {
      raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      raw.listen((socket) {
        open.add(socket);
        socket.listen((_) {}, onError: (Object _) {});
        answer(socket);
      });
    });

    tearDown(() async {
      for (final socket in open) {
        socket.destroy();
      }
      open.clear();
      await raw.close();
    });

    String rawRoot() => 'http://127.0.0.1:${raw.port}';
    String headers() =>
        'HTTP/1.1 200 OK\r\nContent-Length: ${library.length}\r\n'
        'Connection: close\r\n\r\n';

    test('a body cut short of its Content-Length returns false', () async {
      answer = (socket) async {
        socket
          ..write(headers())
          ..add(library.sublist(0, 1000));
        await socket.flush();
        await socket.close();
      };

      final fetched = await hook.fetchPrebuilt(
        asset,
        dest,
        releaseRoot: rawRoot(),
        pins: pinned,
      );

      expect(fetched, isFalse);
      expect(File.fromUri(dest).existsSync(), isFalse);
    });

    test('a server that goes silent times out and returns false', () async {
      final silences = {
        'before the headers': (Socket socket) async {},
        'inside the body': (Socket socket) async {
          socket
            ..write(headers())
            ..add(library.sublist(0, 10));
          await socket.flush();
        },
      };
      for (final MapEntry(key: moment, value: silence) in silences.entries) {
        answer = silence;
        final fetched = await hook
            .fetchPrebuilt(
              asset,
              dest,
              releaseRoot: rawRoot(),
              pins: pinned,
              timeout: const Duration(milliseconds: 200),
            )
            .timeout(const Duration(seconds: 10));

        expect(fetched, isFalse, reason: 'silent $moment');
        expect(
          File.fromUri(dest).existsSync(),
          isFalse,
          reason: 'silent $moment',
        );
      }
    });
  });

  group('provideLibrary', () {
    // What the source build was told about the download, once per call.
    final sourceBuilds = <bool>[];
    Future<Uri> sourceBuild({required bool downloadFailed}) async {
      sourceBuilds.add(downloadFailed);
      return dir.uri.resolve('from-source');
    }

    setUp(sourceBuilds.clear);

    Future<Uri> provide(OS os, Architecture arch) => hook.provideLibrary(
      os,
      arch,
      dir.uri,
      sourceBuild: sourceBuild,
      releaseRoot: root(),
      pins: pinned,
    );

    test('a hash mismatch stops the build with no source build', () async {
      served = [...library]..[0] ^= 0x01;

      await expectLater(
        provide(OS.macOS, Architecture.arm64),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('does not match the SHA-256 pinned'),
          ),
        ),
      );
      expect(sourceBuilds, isEmpty);
    });

    test('the pinned prebuilt is used', () async {
      expect(await provide(OS.macOS, Architecture.arm64), dest);
      expect(sourceBuilds, isEmpty);
    });

    test('a failed download falls back to the source build', () async {
      served = null;

      expect(
        await provide(OS.macOS, Architecture.arm64),
        dir.uri.resolve('from-source'),
      );
      expect(sourceBuilds, [true]);
    });

    test('a target with no prebuilt goes to the source build', () async {
      expect(
        await provide(OS.linux, Architecture.arm64),
        dir.uri.resolve('from-source'),
      );
      expect(sourceBuilds, [false]);
      expect(requests, 0);
    });
  });

  test('every prebuilt the hook can download has a pinned hash', () {
    final paths = {
      for (final os in OS.values)
        for (final arch in Architecture.values)
          if (hook.prebuiltAssetName(os, arch) case final name?)
            hook.prebuiltPath(name),
    };

    expect(paths, hasLength(4));
    expect(
      hook.prebuiltSha256.keys.toSet(),
      paths,
      reason:
          'The map prebuiltSha256 in hook/build.dart has to pin exactly the '
          'assets the hook downloads, under the current release tag. After '
          'moving the tag, download each asset of the new release and record '
          'its SHA-256.',
    );
    for (final hash in hook.prebuiltSha256.values) {
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
  });
}
