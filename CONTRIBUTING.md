# Contributing to hf_tokenizers

## Support

One maintainer looks after this package, best effort. There is no promised
response time and no release schedule.

## Bug reports

A good bug report contains:

* The hf_tokenizers version your app resolves, from `pubspec.lock`.
* The full output of `dart --version`.
* The operating system it ran on and how the code ran (Dart VM, compiled executable, or a Flutter app).
* A minimal reproduction, the smallest code that shows the problem.

## Setup

Install the Dart SDK. This package needs:

* Dart SDK `^3.10.0`

## Checks

Run these in the repository root. CI runs the same three commands:

```
dart pub get
dart analyze
dart test
```

## Golden files

The golden test in `test/golden_test.dart` runs the corpus in
`test/golden/corpus.json` through the Dart API. It compares the result byte
for byte with `test/golden/bert-base-uncased.jsonl`, which the Rust
`tokenizers` crate wrote for the same corpus. The generator in `tool/golden`
needs a Rust toolchain. Regenerate the file after changing the corpus. Run
these from the repository root.

```
cargo run --locked --manifest-path tool/golden/Cargo.toml -- test/fixtures/bert-base-uncased.json test/golden/corpus.json test/golden/bert-base-uncased.jsonl
dart test test/golden_test.dart
```

The generator has to build against the crate versions the library locks. A
second test fails when a package both lock files share resolves to different
versions. After a change to `native/tokenizers_ffi/Cargo.lock`, copy it over
`tool/golden/Cargo.lock`, set the same `tokenizers` requirement in
`tool/golden/Cargo.toml`, and run the command above once without `--locked`.
Cargo then swaps the root package entry. Review the diff of the golden file.
Any change in it is a change in what the crate returns, and the CHANGELOG
should say so.

## Prebuilt hashes

The build hook pins the SHA-256 of every release asset it downloads, in
`prebuiltSha256` in `hook/build.dart`. The hashes only exist once the release
does, and a new release goes in this order.

1. Change `native/`, move `_version` to the new tag and update
   `nativeSourcesDigest`. Publish the GitHub release for that tag. The
   `binaries` job in CI builds the four assets and attaches them.
2. CI is red from here on. The test in `test/prebuilt_checksum_test.dart`
   fails while any asset the hook can download has no hash under the new tag,
   and a build that takes the prebuilt path stops with a missing-hash error.
3. Download each asset of the release and record its hash under the new tag.

   ```
   tag=v0.6.0
   for a in libtokenizers_ffi-linux-x64.so libtokenizers_ffi-macos-arm64.dylib libtokenizers_ffi-macos-x64.dylib tokenizers_ffi-windows-x64.dll; do
     curl -fsSLO "https://github.com/Yusufihsangorgel/tokenizers/releases/download/$tag/$a"
     shasum -a 256 "$a"
   done
   ```

4. CI is green again. Publish the package only after this step.

## Pull requests

* One change per pull request.
* Add an entry to `CHANGELOG.md`.
* Link the issue, for example `Fixes #12`.
