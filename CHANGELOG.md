## 0.1.1

- Rename the example to `example/hf_tokenizers_example.dart` so it is found
  under the package's published name.
- Shorten the pubspec description so it fits pub.dev's 180-character guideline.

## 0.1.0

- Initial release.
- `Tokenizer.fromFile` / `Tokenizer.fromBytes`: load any HuggingFace
  `tokenizer.json`, backed by the Rust `tokenizers` crate over FFI.
- `encode` / `decode`: byte-exact token ids and round-trip text.
- `vocabSize`, prompt native cleanup via `close()` plus a finalizer.
- Platform: macOS (arm64) in this release; other platforms to follow as the
  build hook gains prebuilt/CI coverage.
