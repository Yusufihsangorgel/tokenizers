# hf_tokenizers

Run a model on device, count tokens against a context window, or chunk text for
retrieval, and you need the tokenizer the model was trained with. A
reimplementation that is nearly right hands back ids the model never saw, and
nothing downstream complains.

![A terminal run of the example: a vocabulary of 30522 loads, "hello world"
encodes to four ids and decodes back, and a 38-token document is split into
12-token chunks on token boundaries rather than characters](https://raw.githubusercontent.com/Yusufihsangorgel/hf_tokenizers/main/doc/demo.gif)

![Terminal output of the example: a vocabulary of 30522, hello world encoded to four ids and decoded back, then a 38-token document cut into 12-token chunks.](https://raw.githubusercontent.com/Yusufihsangorgel/tokenizers/main/doc/demo.gif)

## Why this instead of what you already have

**Instead of lowercasing and looking words up.** `example/parity.dart` runs
both approaches against the real `test/fixtures/bert-base-uncased.json`.
Encoding "The naïve café in São Paulo", this package reproduces the file's
reference ids exactly. The shortcut turns `naïve`, `café`, and `São` all into
id 100, the vocabulary's `[UNK]`, so three of six words collapse into one
token that nothing downstream can separate again. The reason is in the file:
its normalizer is `BertNormalizer` with `lowercase=true`, and it strips
accents too. The three words that survived were the ASCII ones, which is how
this shortcut passes a test suite and still breaks on the first accented name
a user types.

**Instead of `dart_sentencepiece_tokenizer`.** It carries a "🤗 Hugging Face
Compatible" badge and offers to load a HuggingFace `tokenizer.json`
(README lines 6 and 20), but its offsets are a different unit. It accumulates
`piece.length`, which is Dart's UTF-16 code-unit count, into
`offset: (charPos, charPos + pieceLen)`
(`lib/src/sentencepiece/sentencepiece_tokenizer.dart:273-286`), and its own
README calls them "Character offsets" (line 65). This package reports UTF-8
byte offsets, matching what the Rust crate returns (`TokenOffset`,
`lib/hf_tokenizers.dart:55`). On any text with multi-byte characters the two
disagree, so a span from one cannot be used to slice for the other.

**Reach for it when**

- You count tokens against a real vocabulary for context budgeting or cost.
- You chunk documents for RAG and the boundaries must land on token boundaries.
- You highlight or extract spans and need offsets that index the original bytes.

**Skip it** if an approximate count over ASCII English is all you need: a
characters-over-four estimate costs nothing, while this package wants a
`tokenizer.json` and a native build on Linux, macOS, or Windows.

This package reimplements nothing. It binds the Rust `tokenizers` crate that
HuggingFace itself ships, through a thin C ABI, and reads any model's
`tokenizer.json`.

```
dart pub add hf_tokenizers
```

```dart
import 'package:hf_tokenizers/hf_tokenizers.dart';

final tk = Tokenizer.fromFile('bert-base-uncased/tokenizer.json');

tk.encode('The naïve café in São Paulo', addSpecialTokens: false);
// [1996, 15743, 7668, 1999, 7509, 9094]
```

![Six words tokenized twice. The hf_tokenizers row carries the ids tokenizer.json assigns; the lowercase-and-look-up row loses naïve, café and São to the unknown-token id.](https://raw.githubusercontent.com/Yusufihsangorgel/tokenizers/main/doc/parity.png)

Both rows above come out of the same `tokenizer.json`. The top one is this
package. The bottom one is the shortest thing that looks correct: lowercase the
text, then look each word up in the vocabulary. That file declares a normalizer
which strips accents before any lookup happens, and half the sentence depends on
it. `tool/parity_shot.dart` draws the picture from the fixture in this
repository, and it re-checks every id on the top row against the vocabulary
table parsed straight out of the JSON, so the numbers are measured rather than
typed in.

`dart run example/parity.dart` prints those two rows in a terminal and checks
the top one against the ids above.

## Use it

```dart
final ids = tk.encode('hello world');   // [101, 7592, 2088, 102]  (bert)
final text = tk.decode(ids);            // "hello world"
print(tk.vocabSize);                    // 30522
print(tk.count('hello world'));         // 4

tk.close(); // optional; a finalizer also frees the native tokenizer
```

`encode` adds the model's special tokens by default (BERT's `[CLS]`/`[SEP]`, and
so on); pass `addSpecialTokens: false` to skip them. `count` is the same number
as `encode(text).length` for callers who do not need the ids. `Tokenizer.fromBytes`
takes the `tokenizer.json` bytes directly, for assets loaded at runtime.

```
dart run example/hf_tokenizers_example.dart
```

## Where the tokenizer.json comes from

This package does not ship one. HuggingFace publishes the file next to the
weights, and `Tokenizer.fromFile` wants that file. The BERT copy in
`test/fixtures/` is for the tests in this repository; it is not a tokenizer
for some other model, and it is not licensed as this package is.

### What a model repository actually contains

Checked against three public Hub trees (2026-08-29):

| File | `google-bert/bert-base-uncased` | `openai-community/gpt2` | `meta-llama/Meta-Llama-3-8B` |
| ---- | ------------------------------- | ----------------------- | ---------------------------- |
| `tokenizer.json` | yes (466062 bytes) | yes | yes |
| `tokenizer_config.json` | yes (48 bytes: `do_lower_case`, `model_max_length`) | yes | yes |
| `vocab.txt` | yes (WordPiece) | — | — |
| `vocab.json` / `merges.txt` | — | yes (BPE) | — |
| `special_tokens_map.json` | — | — | yes |
| weights (`*.safetensors`, …) | yes | yes | yes |
| `LICENSE` | yes (Apache 2.0) | no file; card is `mit` | yes (Llama 3 Community) |
| `USE_POLICY.md` | — | — | yes |

`tokenizer.json` is the serialized HuggingFace `tokenizers` pipeline this
package loads: normalizer, pre-tokenizer, model, post-processor, decoder, added
tokens. `tokenizer_config.json` is for `transformers`. `vocab.txt` and
`merges.txt` are what a slow Python tokenizer reads. Passing any of those, or
ordinary JSON, to `fromFile` throws `FormatException: Not a valid tokenizer.json`.

Llama 3 also ships `original/` with the conversion inputs. The Hub card for
that repo is `license: llama3` and `gated: manual`: the files are listed, but
downloading them requires accepting the licence on the Hub.

### How to fetch one

One file, not the weights:

```
curl -L https://huggingface.co/google-bert/bert-base-uncased/resolve/main/tokenizer.json -o tokenizer.json
```

or, with the Hub CLI:

```
hf download google-bert/bert-base-uncased tokenizer.json
```

Point `Tokenizer.fromFile` at that path. `Tokenizer.fromBytes` takes the same
bytes from an asset. The Hub documents both the CLI and `hf_hub_download` in
[Downloading models](https://huggingface.co/docs/hub/en/models-downloading).

A gated repo will not serve the file until you have accepted its licence and
pass a token.

### The file carries the model's licence

The Hub puts a licence on the *repository*, not on each file. Hugging Face's
own docs: "You are able to add a license to any repo that you create on the
Hugging Face Hub to let other users know about the permissions that you want
to attribute to your code or data. […] Remember to seek out and respect a
project’s license if you’re considering using their code or data."
([Licenses](https://huggingface.co/docs/hub/en/repositories-licenses))

Shipping `tokenizer.json` inside an app is redistributing that work. What the
terms actually say depends on the repo. Two that people actually ship:

**Apache License 2.0**, which is what
[`google-bert/bert-base-uncased`](https://huggingface.co/google-bert/bert-base-uncased)
declares on the model card (`License: apache-2.0`) and in the `LICENSE` file
in the repo (Apache License, Version 2.0, January 2004). Section 2 grants a
copyright licence "to reproduce, prepare Derivative Works of, publicly display,
publicly perform, sublicense, and distribute the Work". Section 4 allows
reproduction and distribution "in any medium, with or without modifications"
provided you (1) give recipients a copy of the licence, (2) mark modified
files as changed, (3) retain copyright, patent, trademark, and attribution
notices, and (4) if the Work includes a `NOTICE` file, include a readable copy
of its attribution notices. That tree has a `LICENSE` and no `NOTICE`. Section
6 does not grant trademark rights except as needed to describe origin. This
repository's BERT fixture is that file.

**Llama 3 Community License**, which is what
[`meta-llama/Meta-Llama-3-8B`](https://huggingface.co/meta-llama/Meta-Llama-3-8B)
declares (`license: llama3`). The agreement defines "Llama Materials" as Meta
Llama 3 and its documentation, "including machine-learning model code, trained
model weights, inference-enabling code" and related elements
([`LICENSE`](https://github.com/meta-llama/llama3/blob/main/LICENSE) in
`meta-llama/llama3`). `tokenizer.json` is part of that distribution. If you
distribute the Llama Materials or a product that uses them, you must (A)
provide a copy of the Agreement with those materials, and (B) prominently
display "Built with Meta Llama 3" on a related website, UI, about page, or
product documentation (section 1.b.i). Copies must keep the attribution notice
in a Notice file (1.b.iii). Use must follow the Acceptable Use Policy
(1.b.iv). Section 1.b.v forbids using the Llama Materials or their outputs
"to improve any other large language model". Section 2 is a snapshot, not a
running cap: if, on the 18 April 2024 release date, the products or services
made available by or for the licensee (or affiliates) had more than 700 million
monthly active users in the preceding calendar month, those rights are not
granted unless Meta separately licenses them.

This package's MIT licence covers the Dart API and the Rust binding. It does
not relicense a `tokenizer.json` you load. Do not add another tokenizer file
to this repository; the BERT fixture is already here, under Apache-2.0.

## Single tokens

To look a token up without encoding a whole string, use `tokenToId` and its
inverse `idToToken`. Both return null when the token or id is not in the
vocabulary.

```dart
tk.tokenToId('[CLS]');   // 101
tk.tokenToId('hello');   // 7592
tk.idToToken(101);       // "[CLS]"
tk.idToToken(7592);      // "hello"
```

`idToToken` returns the raw token, keeping the sub-word markers the model uses.
That is the difference from `decode`, which detokenizes back to plain text:

```dart
final ids = tk.encode('tokenization', addSpecialTokens: false);
ids.map(tk.idToToken).toList();  // ["token", "##ization"]  (## kept)
tk.decode(ids);                  // "tokenization"          (## resolved)
```

## Offsets: map tokens back to the text

`encodeWithOffsets` returns each token together with the `[start, end)` span of
the input it came from, which is what token-accurate chunking, span
highlighting, and entity extraction need.

```dart
final text = 'hello world';
final bytes = utf8.encode(text);
for (final t in tk.encodeWithOffsets(text, addSpecialTokens: false)) {
  print(utf8.decode(bytes.sublist(t.start, t.end))); // "hello", then "world"
}
```

The offsets are **UTF-8 byte** offsets, which is what the underlying crate
reports. They are not UTF-16 indices. Slice `utf8.encode(text)` rather than
calling `text.substring`, or the math goes wrong on any non-ASCII input.

![Two rulers over the sentence "The naïve café in São Paulo": the string index ends at 26 while the byte offset ends at 29, pulling one further ahead at each accented character. Below them the six token spans are read twice, and five of the six substring readings return different text while the last throws RangeError.](https://raw.githubusercontent.com/Yusufihsangorgel/tokenizers/main/doc/offsets.png)

That sentence is 27 UTF-16 units and 30 bytes. Read its six spans with
`substring` and five hand back different text while the sixth reaches past the
end and throws, which leaves the crash as the only one a test would notice.
`dart run tool/offsets_figure.dart` draws the picture by running both readings
and keeping whatever each one returned.

Special tokens like `[CLS]` come back with an empty span (`start == end`).

## Token budgets

Context windows and embedding endpoints are measured in tokens. Dart strings are
measured in UTF-16 units, and the usual "about four characters per token" guess
either wastes budget or overshoots it. These two cut where the tokenizer says.

```dart
// The longest prefix that fits, cut on a token boundary.
final head = tk.truncateToTokens(document, 512);

// Or split the whole document into pieces that each fit an embedding model's
// input limit, with a little context repeated across the seams.
for (final chunk in tk.chunkByTokens(document, 256, overlapTokens: 32)) {
  await embed(chunk);
}
```

Both count what the model counts. BERT adds `[CLS]` and `[SEP]`, so a budget of
512 leaves 510 for text, and a budget smaller than the markers themselves is
rejected rather than quietly answered with an empty string that would still
encode to two tokens. Cuts land on token boundaries, which are UTF-8
boundaries. No character is split. With no overlap the pieces concatenate back
to the original text, whitespace included.

`chunkByTokens` re-encodes every piece instead of trusting the count it already
has, because tokenization is context-dependent: `##ization` is one token inside
`internationalization` and two when the same bytes begin a chunk. The
[Example tab](https://pub.dev/packages/hf_tokenizers/example) has the diagram.

### Feeding a retrieval pipeline

`chunkByTokens` returns strings. A retrieval pipeline usually also wants to know
*where* each chunk came from, to highlight the passage it cited.
`example/rag_chunking.dart` builds that: a `Chunker` for
[`rag_kit`](https://pub.dev/packages/rag_kit) on top of `encodeWithOffsets`,
carrying both the exact token count and a real range in the source.

The interesting part is the conversion. `TokenOffset` is in UTF-8 bytes and
`rag_kit`'s `Chunk` promises `source.substring(start, end) == text`, which is
UTF-16. The two agree on ASCII and diverge the moment the text is not. The
example maps between them and then *asserts* the contract, because that is the
mistake worth catching once rather than in production.

Run it to see why a character budget cannot be tuned: on one mixed
English-and-Japanese paragraph, the chunks came out between **2.2 and 4.8
characters per token**.

## What it supports

Whatever the `tokenizer.json` declares. Because it is the real Rust library, the
full pipeline is applied exactly: normalizers, pre-tokenizers, the model itself
(BPE, byte-level BPE, WordPiece, Unigram), and post-processors. Load a GPT-2,
BERT, Llama, or sentence-transformers tokenizer, and the ids match Python.

## Correctness

The test suite loads a real `bert-base-uncased` `tokenizer.json` and asserts the
ids against known-good values from HuggingFace, including WordPiece splitting
and a decode round-trip. Token ids that match the reference are the whole point.
They are checked, never assumed.

## Platforms

The native library loads one of two ways: a prebuilt binary fetched from the
GitHub release (no toolchain needed), or a source build with `cargo` as a
fallback. The source build compiles for the host, which means it needs a Rust
toolchain and a host that matches the target.

| Target                        | How it loads            | Needs a toolchain |
| ----------------------------- | ----------------------- | ----------------- |
| macOS arm64, macOS x64        | prebuilt                | no                |
| Linux x64 (glibc ≥ 2.34)      | prebuilt                | no                |
| Windows x64                   | prebuilt                | no                |
| Any of the above, offline     | source build (fallback) | yes (Rust)        |
| Linux arm64                   | source build            | yes (Rust)        |
| **Android, iOS**              | **not supported yet**   | —                 |

The prebuilt Linux binary needs glibc 2.34 or newer. That floor was measured
rather than assumed: the released `.so` references no glibc symbol above
`GLIBC_2.34`, and links nothing beyond `libc.so.6` and `libgcc_s.so.1`. What it
means for the distributions people actually deploy on:

| Distribution | glibc | Prebuilt |
| ------------ | ----- | -------- |
| Ubuntu 24.04 | 2.39  | loads    |
| Debian 12    | 2.36  | loads    |
| Ubuntu 22.04 | 2.35  | loads    |
| Debian 11    | 2.31  | fails    |
| Alpine       | musl  | fails    |

On Debian 11 the loader reports `version 'GLIBC_2.34' not found`. Alpine fails
for a different reason: it ships musl and has no `libc.so.6`, so the load stops
at the missing library rather than at a version. Check yours with
`ldd --version`.

The source build does not rescue this. The hook falls back to `cargo` only when
the prebuilt cannot be *downloaded*; a download that succeeds is used as-is, and
on an older distribution the failure then surfaces when the library is loaded
rather than at build time. Installing Rust does not change that on its own.
Lowering the floor means rebuilding the release binaries against an older glibc.

Android and iOS need cross-compiled prebuilts, which are not published yet.
Adding the package to a mobile Flutter target fails at build time with a message
that says exactly that, rather than a confusing toolchain error. This is a
server-side and desktop package today. The `sdk:flutter` tag covers Flutter
**desktop** apps only.

## When to use something else

The tables above name three places this package does not go: a phone, Alpine,
and a Linux older than glibc 2.34. The web is a fourth, because FFI does not run
there. A native library also costs a download and a build hook that a pure-Dart
package does not.

[`dart_sentencepiece_tokenizer`](https://pub.dev/packages/dart_sentencepiece_tokenizer)
is the pure-Dart option, and today it is the more widely used of the two. It has
no dependencies, ships Android and iOS, and reads `tokenizer.json` as well as
SentencePiece's own `.model` file. Its loader handles the BPE and Unigram
algorithms that Gemma and Llama ship. Hand it `bert-base-uncased/tokenizer.json`
and version 1.3.2 stops with `FormatException: Missing model type`: BERT leaves
`model.type` out of that file, and the loader has no WordPiece branch to fall
back on. WordPiece is what BERT and the sentence-transformers embedding models
use.

That is the line. Reach for this package when the model is BERT-shaped, or when
matching the reference pipeline exactly is the requirement. Reach for that one
when the target is a phone.

## License

MIT. The bound library is HuggingFace's `tokenizers` crate (Apache-2.0). A
`tokenizer.json` you load is not this licence; see [Where the tokenizer.json
comes from](#where-the-tokenizerjson-comes-from).
