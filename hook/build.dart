import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

/// The GitHub release tag that hosts the prebuilt binaries. This tracks the
/// native crate, not the package version: bump it only when the Rust sources
/// under `native/` change and a new release carries the rebuilt binaries.
///
/// v0.2.0 adds the `tk_token_to_id` and `tk_id_to_token` symbols, so the
/// binaries under this tag must be the rebuilt ones or a prebuilt install will
/// fail to resolve them.
///
/// v0.5.0 changes `tk_encode`, `tk_encode_offsets` and `tk_token_to_id` to take
/// an explicit `(pointer, length)` instead of a NUL-terminated string, so the
/// binaries under this tag are ABI-incompatible with the older Dart bindings:
/// the tag must move in lockstep with the package that ships those bindings.
/// `v0.4.0` already exists as a release cut before this change, so it still
/// serves the old, NUL-terminated signatures; reusing that tag here would
/// silently hand the new bindings a binary that reads the wrong argument as
/// `out_len` and crashes.
///
/// v0.6.0 keeps every signature and the `tokenizers` crate version of v0.5.0.
/// It returns the error value instead of aborting when the crate panics, and
/// links the macOS binaries with room for a longer install name.
const _version = '0.6.0';

/// SHA-256 over the crate sources the binaries under [_version] were built
/// from, in the order `test/prebuilt_tag_test.dart` hashes them. Public
/// because that test is the only reader: the hook itself never needs it.
///
/// The comment above says to bump the tag whenever `native/` changes, and 0.5.0
/// shipped anyway with the tag left behind — every prebuilt install segfaulted
/// on the first call for two days. A note cannot fail; this can. Change the
/// crate and the test goes red until the tag moves and a release carries the
/// rebuilt binaries.
const nativeSourcesDigest =
    '6975ce4b6dcb14bff54ad2b2bb06fcb42775bb854208d2f07e36a8b2f40ca638';
const _releaseRoot =
    'https://github.com/Yusufihsangorgel/tokenizers/releases/download';

/// SHA-256 of every prebuilt binary the hook can download, keyed by the path
/// of the asset under the release download URL.
///
/// The tag in each key is written out by hand. After [_version] moves, the
/// hook has no hash for any asset under the new tag and builds from source on
/// the targets that have a prebuilt until the hashes of the new release are
/// added here.
/// `test/prebuilt_checksum_test.dart` fails for as long as one is missing.
const prebuiltSha256 = <String, String>{
  'v0.5.0/libtokenizers_ffi-linux-x64.so':
      'f5704a92ea236eb14ddc37d5c9dbbf2caac1cf9eba074ea7b28e9a1afd49a1f8',
  'v0.5.0/libtokenizers_ffi-macos-arm64.dylib':
      'c456934340acd5b11ae421f7635182cae02d29b013ebbfaea70ef6d92f6ba96c',
  'v0.5.0/libtokenizers_ffi-macos-x64.dylib':
      'd2481a24ffacfa72c7dddfe5ff84621cbdfff1b220a2180249b2e2a07f868a6d',
  'v0.5.0/tokenizers_ffi-windows-x64.dll':
      'bb3c5d7d5ab2e72f366759fabd4062f49b088b43ad7b35228ba38bd4b9355432',
};

/// Provides the `tokenizers_ffi` native library for `dart:ffi`'s `@Native`
/// lookups. It prefers a prebuilt binary from the GitHub release so consumers
/// need no toolchain, and falls back to building the Rust crate with cargo.
/// A downloaded prebuilt has to match its pinned SHA-256 or the build stops.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final crateDir = input.packageRoot.resolve('native/tokenizers_ffi/');

    final library = await provideLibrary(
      os,
      arch,
      input.outputDirectory,
      sourceBuild: ({required reason}) => _cargoBuild(
        crateDir,
        _localLibraryName(os),
        os,
        arch,
        reason: reason,
      ),
    );

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );
    output.dependencies.addAll([
      crateDir.resolve('src/lib.rs'),
      crateDir.resolve('Cargo.toml'),
      crateDir.resolve('Cargo.lock'),
      crateDir.resolve('build.rs'),
    ]);
  });
}

/// Why the hook builds the library from source instead of using a prebuilt.
enum SourceBuildReason {
  /// No prebuilt is published for the target.
  noPrebuilt,

  /// [prebuiltSha256] has no hash for the target's asset under the current
  /// release tag. The release is not out yet, or its hashes are not recorded.
  unpinned,

  /// The pinned prebuilt could not be downloaded.
  downloadFailed,
}

/// The library for the target, either the checked prebuilt in
/// [outputDirectory] or what [sourceBuild] produces.
///
/// A prebuilt that fails its hash check throws out of here. The source build
/// runs when no prebuilt is published for the target, when [pins] has no hash
/// for it under the current tag, or when the download fails. It needs a Rust
/// toolchain and a host that matches the target, because this hook does not
/// cross-compile. Tests pass [releaseRoot] and [pins] to serve their own
/// bytes.
Future<Uri> provideLibrary(
  OS os,
  Architecture arch,
  Uri outputDirectory, {
  required Future<Uri> Function({required SourceBuildReason reason})
  sourceBuild,
  String releaseRoot = _releaseRoot,
  Map<String, String> pins = prebuiltSha256,
}) async {
  final asset = prebuiltAssetName(os, arch);
  if (asset == null) {
    return sourceBuild(reason: SourceBuildReason.noPrebuilt);
  }
  // The tag moves before its release exists, and the hashes of the release
  // binaries can only be recorded after that. Until then the sources under
  // native/ are the only library that matches the bindings, and nothing is
  // downloaded without a hash to check it against.
  if (!pins.containsKey(prebuiltPath(asset))) {
    return sourceBuild(reason: SourceBuildReason.unpinned);
  }
  // The prebuilt binary from the release needs no toolchain.
  final dest = outputDirectory.resolve(_localLibraryName(os));
  if (await fetchPrebuilt(asset, dest, releaseRoot: releaseRoot, pins: pins)) {
    return dest;
  }
  // A prebuilt is published for this target but could not be fetched. The
  // machine may be offline, behind a proxy or rate-limited by GitHub. If the
  // source build also fails, its message names the real first cause and does
  // not blame the toolchain.
  return sourceBuild(reason: SourceBuildReason.downloadFailed);
}

String _localLibraryName(OS os) => switch (os) {
  OS.macOS => 'libtokenizers_ffi.dylib',
  OS.windows => 'tokenizers_ffi.dll',
  _ => 'libtokenizers_ffi.so',
};

/// The release asset name for a target, or null if no prebuilt is published.
String? prebuiltAssetName(OS os, Architecture arch) {
  final platform = switch ((os, arch)) {
    (OS.macOS, Architecture.arm64) => 'macos-arm64',
    (OS.macOS, Architecture.x64) => 'macos-x64',
    (OS.linux, Architecture.x64) => 'linux-x64',
    (OS.windows, Architecture.x64) => 'windows-x64',
    _ => null,
  };
  if (platform == null) return null;
  return os == OS.windows
      ? 'tokenizers_ffi-$platform.dll'
      : 'libtokenizers_ffi-$platform.${os == OS.macOS ? 'dylib' : 'so'}';
}

/// The path of [asset] under the release download URL. It is also the key of
/// the asset in [prebuiltSha256].
String prebuiltPath(String asset) => 'v$_version/$asset';

/// How long the download waits to connect, and then for each next piece of
/// the response.
const _downloadTimeout = Duration(seconds: 30);

/// Downloads the prebuilt [asset] and writes it to [dest] if its SHA-256
/// matches the pin.
///
/// Any file already at [dest] is deleted first. Returns false when the
/// download fails or times out, which leaves the source build to run. Throws
/// before any request when [pins] has no hash for [asset]. Throws without
/// writing anything when the downloaded bytes hash to anything else. Tests
/// pass [releaseRoot], [pins] and a short [timeout].
Future<bool> fetchPrebuilt(
  String asset,
  Uri dest, {
  String releaseRoot = _releaseRoot,
  Map<String, String> pins = prebuiltSha256,
  Duration timeout = _downloadTimeout,
}) async {
  final path = prebuiltPath(asset);
  final expected = pins[path];
  if (expected == null) {
    throw Exception(
      'hf_tokenizers pins no SHA-256 for the prebuilt $path and will not '
      'load an unchecked binary. Add the hash of that release asset to '
      'prebuiltSha256 in hook/build.dart.',
    );
  }

  final url = '$releaseRoot/$path';
  final file = File.fromUri(dest);
  // A library left by an earlier build is never used unchecked.
  if (file.existsSync()) file.deleteSync();
  final bytes = await _download(url, timeout);
  if (bytes == null) return false;
  final actual = sha256.convert(bytes).toString();
  if (actual != expected) {
    throw Exception(
      'The prebuilt binary $url does not match the SHA-256 pinned in '
      'hook/build.dart. Expected $expected, got $actual. Nothing was '
      'written and the build stopped. A changed release asset or a proxy '
      'that rewrites downloads can cause this. Report it at '
      'https://github.com/Yusufihsangorgel/tokenizers/issues.',
    );
  }
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return true;
}

/// The body of a 200 response to [url], or null on any other outcome.
///
/// The connection, the response headers and every later piece of the body
/// each have [timeout] to arrive. A stalled server returns null.
Future<Uint8List?> _download(String url, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return null;
    final body = BytesBuilder(copy: false);
    await response.timeout(timeout).forEach(body.add);
    return body.takeBytes();
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<Uri> _cargoBuild(
  Uri crateDir,
  String localName,
  OS os,
  Architecture arch, {
  required SourceBuildReason reason,
}) async {
  // `cargo build` compiles for the host. This hook passes no `--target`, so it
  // can only produce a library for the platform it runs on. A build targeting
  // Android or iOS from a desktop host would emit the wrong binary (or none),
  // so refuse it up front with a message that says what is missing rather than
  // failing obscurely deeper in.
  if (os == OS.android || os == OS.iOS) {
    throw Exception(
      'hf_tokenizers has no prebuilt binary for $os and cannot cross-compile '
      'it from source: the build hook builds for the host only. $os support '
      'needs a prebuilt in the GitHub release, which is not published yet. '
      'Track it at https://github.com/Yusufihsangorgel/tokenizers.',
    );
  }

  final ProcessResult result;
  try {
    result = await Process.run(
      _resolveCargo(),
      ['build', '--release'],
      workingDirectory: crateDir.toFilePath(),
      environment: _envWithCargoBin(),
    );
  } on ProcessException catch (error) {
    // cargo is not on PATH: Process.run throws rather than returning a
    // non-zero exit, so without this the hook crashes with a raw
    // ProcessException instead of telling the user what to install.
    throw Exception(
      _sourceBuildMessage(
        os,
        arch,
        'no Rust toolchain was found (${error.message})',
        reason: reason,
      ),
    );
  }
  if (result.exitCode != 0) {
    throw Exception(
      _sourceBuildMessage(
        os,
        arch,
        'the source build failed (exit ${result.exitCode})\n'
        '${result.stdout}\n${result.stderr}',
        reason: reason,
      ),
    );
  }
  return crateDir.resolve('target/release/$localName');
}

/// A build-failure message that names the real first cause. A prebuilt exists
/// for the desktop targets, so the usual reason a source build runs at all is
/// that the download failed; say so, rather than pointing at the toolchain.
String _sourceBuildMessage(
  OS os,
  Architecture arch,
  String detail, {
  required SourceBuildReason reason,
}) {
  final lead = switch (reason) {
    SourceBuildReason.downloadFailed =>
      'The prebuilt binary for $os $arch could not be downloaded '
          '(offline, proxied, or rate-limited?), and the source-build '
          'fallback then failed',
    SourceBuildReason.unpinned =>
      'This hf_tokenizers checkout pins no prebuilt binary for $os $arch '
          'under release v$_version yet, and the source-build fallback failed',
    SourceBuildReason.noPrebuilt =>
      'No prebuilt binary is published for $os $arch, and the source-build '
          'fallback failed',
  };
  final otherwise = reason == SourceBuildReason.unpinned
      ? 'or depend on a published version of hf_tokenizers, which pins the '
            'prebuilt binaries of its release.'
      : 'or build on a target with a published prebuilt (macOS arm64/x64, '
            'Linux x64, Windows x64).';
  return '$lead: $detail\n'
      'Install a Rust toolchain from https://rustup.rs, $otherwise';
}

/// `Process.run` does not inherit the login shell's PATH, so rustup's default
/// `~/.cargo/bin` location is checked too.
String _resolveCargo() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  final exe = Platform.isWindows ? 'cargo.exe' : 'cargo';
  for (final candidate in [
    env['CARGO'],
    if (home != null) '$home/.cargo/bin/$exe',
  ]) {
    if (candidate != null && File(candidate).existsSync()) return candidate;
  }
  return exe;
}

Map<String, String> _envWithCargoBin() {
  final env = Map<String, String>.from(Platform.environment);
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home != null) {
    final sep = Platform.isWindows ? ';' : ':';
    env['PATH'] = '$home/.cargo/bin$sep${env['PATH'] ?? ''}';
  }
  return env;
}
