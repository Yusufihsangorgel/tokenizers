import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// The build hook downloads prebuilt binaries from a GitHub release whose tag
/// is hardcoded as `_version`. When the Rust crate changes the C ABI, that tag
/// has to move to a release carrying the rebuilt binaries — otherwise every
/// install that takes the prebuilt path gets a library whose signatures no
/// longer match the Dart bindings, and it segfaults on the first call.
///
/// That is not hypothetical: 0.5.0 changed three functions to take an explicit
/// `(pointer, length)` and left the tag at `v0.4.0`. It was live and crashing
/// for two days. The hook already carried a comment saying to bump the tag; a
/// comment cannot fail a build, so this does.
void main() {
  test('the prebuilt release tag matches the crate the binaries came from', () {
    const sources = [
      'native/tokenizers_ffi/Cargo.toml',
      'native/tokenizers_ffi/Cargo.lock',
      'native/tokenizers_ffi/src/lib.rs',
    ];

    final input = <int>[];
    for (final path in sources) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '$path is hashed into the digest but is missing; if the crate '
            'was reorganised, update both this list and the digest',
      );
      // Hash the text with normalised line endings. Git checks these files
      // out as CRLF on Windows, so hashing raw bytes made the digest
      // platform-dependent and the guard fired on every Windows CI run — a
      // check that cries wolf is a check people learn to ignore.
      input
        ..addAll(utf8.encode(path))
        ..addAll(utf8.encode(file.readAsStringSync().replaceAll('\r\n', '\n')));
    }
    final actual = sha256.convert(input).toString();

    final hook = File('hook/build.dart').readAsStringSync();
    final digest = RegExp(
      r"nativeSourcesDigest\s*=\s*\n?\s*'([0-9a-f]{64})'",
    ).firstMatch(hook);
    final tag = RegExp(r"_version\s*=\s*'([^']+)'").firstMatch(hook);
    expect(digest, isNotNull, reason: 'hook/build.dart has no digest constant');
    expect(tag, isNotNull, reason: 'hook/build.dart has no _version constant');

    expect(
      actual,
      digest!.group(1),
      reason:
          'The crate under native/ has changed since the binaries on '
          'release v${tag!.group(1)} were built. Publishing now would hand '
          'every prebuilt install a stale library. Cut a release with the '
          'rebuilt binaries, point _version at its tag, and set '
          "_nativeSourcesDigest to '$actual'.",
    );
  });
}
