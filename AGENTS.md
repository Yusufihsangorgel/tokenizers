# AGENTS.md

This repository is `tokenizers`; the published package is `hf_tokenizers`.

## Purpose

`hf_tokenizers` binds HuggingFace's Rust `tokenizers` crate over FFI so Dart can encode text to the token ids a model was trained on, given that model's `tokenizer.json` (HuggingFace publishes the file next to the weights; this checkout's BERT copy is `test/fixtures/bert-base-uncased.json`). Android, iOS, and the web are unsupported: `hook/build.dart` refuses mobile because it cannot cross-compile and no mobile prebuilts exist, and `dart:ffi` does not run in a browser; the Linux prebuilt needs glibc ≥ 2.34, so Alpine (musl) and Debian 11 will not load it.

A character heuristic is not a count: `example/context_budget.dart`'s 285-character prompt is 72 tokens by `length / 4` and 78 by `encode`. A Dart reimplementation that lowercases words and looks them up in the same JSON maps naïve, café, and São to `[UNK]` id 100 (`example/parity.dart`).

## Usage

Shortest path that actually counts tokens, from `example/hf_tokenizers_example.dart`. `count` is the number to compare to a context window; `encode` when you need the ids.

```dart
import 'package:hf_tokenizers/hf_tokenizers.dart';

void main() {
  final tk = Tokenizer.fromFile('test/fixtures/bert-base-uncased.json');
  print(tk.count('hello world')); // 4
  final ids = tk.encode('hello world'); // [101, 7592, 2088, 102]
  tk.close();
}
```

In another package: `dart pub add hf_tokenizers`, then pass that model's `tokenizer.json` into `Tokenizer.fromFile`, or the bytes into `Tokenizer.fromBytes` for a bundled asset. Do not use this BERT fixture against a different model. The file lives next to the weights on the Hub; `vocab.txt` / `merges.txt` are not a substitute. It carries the model's licence (the Hub licence is on the repository), so shipping it inside an app is redistributing that work — see the README section. Do not vendor another `tokenizer.json` into this repository.

## Contracts

**`TokenOffset.start` and `TokenOffset.end` are UTF-8 byte offsets**, not Dart `String` indices. They come from `Tokenizer.encodeWithOffsets`. `String.substring` counts UTF-16 units. Convert by slicing the encoded bytes:

```dart
import 'dart:convert';
import 'package:hf_tokenizers/hf_tokenizers.dart';

String piece(String text, TokenOffset t) {
  final bytes = utf8.encode(text);
  return utf8.decode(bytes.sublist(t.start, t.end));
}
```

`'The naïve café in São Paulo'` is 27 UTF-16 units and 30 bytes; its last content token is `[25, 30)`. Special tokens (`[CLS]`, `[SEP]`) have `start == end`. If a caller needs UTF-16 indices for `source.substring`, map bytes as in `example/rag_chunking.dart`.

**Reuse one `Tokenizer`.** `fromFile` / `fromBytes` construct native state; tests keep a single instance for the group.

**`Tokenizer.close`** frees that handle. Optional: a `NativeFinalizer` also releases it. After `close`, further calls throw.

**`Tokenizer.encode` and `Tokenizer.count` default `addSpecialTokens: true`.** For this BERT fixture that prepends `[CLS]` (101) and appends `[SEP]` (102): `'hello world'` is 4 tokens, `''` encodes to `[101, 102]`. Content-only count: `count(text, addSpecialTokens: false)`. `count` is `encode().length`, not a faster path: the crate's `encode_fast` skip is lost in the tokenize work on this fixture. `truncateToTokens` and `chunkByTokens` use the same default, so a budget of 512 leaves 510 for text; a budget of 1 or 2 is rejected.

## Mistakes

Slicing the string with those offsets. On the sentence above:

```dart
const text = 'The naïve café in São Paulo';
text.substring(25, 30);
```

```
RangeError (end): Invalid value: Not in inclusive range 25..27: 30
```

The ASCII first span `[0, 3)` still returns `The`, so tests on English hide it. Fix: `piece` above.

Missing path:

```
PathNotFoundException: Cannot open file, path = 'no-such-tokenizer.json' (OS Error: No such file or directory, errno = 2)
```

Bytes that are not a tokenizer, including ordinary JSON:

```
FormatException: Not a valid tokenizer.json
```

Fix: the model's `tokenizer.json`, not `vocab.txt` or `merges.txt`.

After `close`:

```
Bad state: Tokenizer has been closed
```

`truncateToTokens(text, 1)` with defaults:

```
Invalid argument (maxTokens): leaves no room for text: the model adds 2 special token(s), so even an empty string encodes to 2: 1
```

`chunkByTokens(text, 2)`:

```
Invalid argument (maxTokens): leaves no room for text after 2 special token(s): 2
```

Use `addSpecialTokens: false`, or a budget ≥ 3 on this fixture.

Mobile build (`hook/build.dart`):

```
hf_tokenizers has no prebuilt binary for $os and cannot cross-compile it from source: the build hook builds for the host only.
```

## Layout

- `lib/hf_tokenizers.dart` — `Tokenizer`, `TokenOffset`
- `lib/src/bindings.dart` — FFI
- `native/tokenizers_ffi/` — Rust cdylib over crate `tokenizers` 0.20 (`cargo build --release`)
- `hook/build.dart` — prebuilt from GitHub release `v0.5.0`, else cargo on the host
- `test/fixtures/bert-base-uncased.json` — vocab 30522
- `example/` — `hf_tokenizers_example.dart`, `parity.dart`, `context_budget.dart`, `rag_chunking.dart`
- `tool/measure_count.dart` — wall time of `count` against `encode().length`
- `native/tokenizers_ffi/examples/count_bench.rs` — crate `encode` vs `encode_fast`
- `test/` — `dart test`

```
dart analyze
dart test
```

Changing `native/` requires bumping `_version` and `nativeSourcesDigest` in `hook/build.dart` (see `test/prebuilt_tag_test.dart`). Prebuilts: macOS arm64/x64, Linux x64, Windows x64.
