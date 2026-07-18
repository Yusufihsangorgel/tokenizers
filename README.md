![tokenizers: byte-exact tokenization for Dart over FFI](https://raw.githubusercontent.com/Yusufihsangorgel/tokenizers/main/doc/banner.png)

# tokenizers

HuggingFace tokenizers for Dart, over FFI. Load any model's `tokenizer.json`
and get token ids that are byte-exact with the reference implementation.

![tokenizers: byte-exact encode and decode in Dart, backed by the Rust tokenizers crate](https://raw.githubusercontent.com/Yusufihsangorgel/tokenizers/main/doc/demo.gif)

If you run a model on device, or count tokens, or chunk text for retrieval, you
need the same tokenizer the model was trained with. The pure-Dart
reimplementations on pub.dev each cover one algorithm, and they drift from the
reference vocabulary in the corners, so your ids stop matching the model and the
output quietly degrades. This package does not reimplement anything: it binds
the Rust `tokenizers` crate that HuggingFace itself ships, through a thin C ABI.

```
dart pub add tokenizers
```

## Use it

```dart
import 'package:tokenizers/tokenizers.dart';

final tk = Tokenizer.fromFile('assets/tokenizer.json');

final ids = tk.encode('hello world');   // [101, 7592, 2088, 102]  (bert)
final text = tk.decode(ids);            // "hello world"
print(tk.vocabSize);                    // 30522

tk.close(); // optional; a finalizer also frees the native tokenizer
```

`encode` adds the model's special tokens by default (BERT's `[CLS]`/`[SEP]`,
and so on); pass `addSpecialTokens: false` to skip them. `Tokenizer.fromBytes`
takes the `tokenizer.json` bytes directly, for assets loaded at runtime.

## What it supports

Whatever the `tokenizer.json` declares. Because it is the real Rust library, the
full pipeline is applied exactly: normalizers, pre-tokenizers, the model itself
(BPE, byte-level BPE, WordPiece, Unigram), and post-processors. Load a GPT-2,
BERT, Llama, or sentence-transformers tokenizer, and the ids match Python.

## Correctness

The test suite loads a real `bert-base-uncased` `tokenizer.json` and asserts the
ids against known-good values from HuggingFace, including WordPiece splitting and
a decode round-trip. Token ids that match the reference are the whole point, so
they are checked, not assumed.

## Status and platforms

This is `0.1.0`. It is proven on macOS (arm64): the Rust crate builds and the
ids are byte-exact. Building from source needs a Rust toolchain; a pub build hook
that runs `cargo` and bundles the library is in progress, and prebuilt binaries
plus Linux and Windows coverage follow. The platform table will stay honest about
what is verified.

## License

MIT. The bound library is HuggingFace's `tokenizers` crate (Apache-2.0).
