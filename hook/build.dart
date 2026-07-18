import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// The GitHub release tag that hosts the prebuilt binaries. This tracks the
/// native crate, not the package version: bump it only when the Rust sources
/// under `native/` change and a new release carries the rebuilt binaries.
const _version = '0.1.0';
const _releaseBase =
    'https://github.com/Yusufihsangorgel/tokenizers/releases/download/v$_version';

/// Provides the `tokenizers_ffi` native library for `dart:ffi`'s `@Native`
/// lookups. It prefers a prebuilt binary from the GitHub release so consumers
/// need no toolchain, and falls back to building the Rust crate with cargo.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final crateDir = input.packageRoot.resolve('native/tokenizers_ffi/');
    final localName = _localLibraryName(os);

    Uri? library;

    // 1) Prebuilt binary from the release: no toolchain required.
    final asset = _prebuiltAssetName(os, arch);
    if (asset != null) {
      final dest = input.outputDirectory.resolve(localName);
      if (await _download('$_releaseBase/$asset', dest)) library = dest;
    }

    // 2) Build from source with cargo (needs a Rust toolchain).
    library ??= await _cargoBuild(crateDir, localName);

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
    ]);
  });
}

String _localLibraryName(OS os) => switch (os) {
      OS.macOS => 'libtokenizers_ffi.dylib',
      OS.windows => 'tokenizers_ffi.dll',
      _ => 'libtokenizers_ffi.so',
    };

/// The release asset name for a target, or null if no prebuilt is published.
String? _prebuiltAssetName(OS os, Architecture arch) {
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

Future<bool> _download(String url, Uri dest) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) return false;
    final file = File.fromUri(dest);
    await file.parent.create(recursive: true);
    await response.pipe(file.openWrite());
    return true;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<Uri> _cargoBuild(Uri crateDir, String localName) async {
  final result = await Process.run(
    _resolveCargo(),
    ['build', '--release'],
    workingDirectory: crateDir.toFilePath(),
    environment: _envWithCargoBin(),
  );
  if (result.exitCode != 0) {
    throw Exception(
      'No prebuilt binary for this platform, and building from source failed '
      '(exit ${result.exitCode}). Install a Rust toolchain from '
      'https://rustup.rs, or use a platform with a published prebuilt.\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return crateDir.resolve('target/release/$localName');
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
