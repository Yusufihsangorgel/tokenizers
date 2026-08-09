## 1.0.3

- The package page now opens on evidence rather than a banner. One sentence is
  tokenized twice out of one `tokenizer.json`: this package on the top row, and
  on the bottom the shortcut that looks correct, lowercase plus a straight
  vocabulary lookup. The normalizer in that file strips accents before any
  lookup happens, and skipping it sends 3 of the 6 words to `[UNK]`.
  `tool/parity_shot.dart` draws the picture from the test fixture at run time
  and re-checks every id on the top row against the vocabulary table it parses
  out of the JSON itself. If the library and the file ever disagreed, the tool
  would fail instead of drawing.
- A new README section, "When to use something else", names the places this
  package does not go (phones, the web, Alpine, glibc older than 2.34) and says
  what to reach for there. The boundary is measured too:
  [`dart_sentencepiece_tokenizer`](https://pub.dev/packages/dart_sentencepiece_tokenizer)
  1.3.2 handles BPE and Unigram, and on `bert-base-uncased/tokenizer.json` it
  stops with `FormatException: Missing model type`. BERT leaves `model.type`
  out of that file, and the loader has no WordPiece branch to fall back on.
- The README now shows the command that runs the example, and the recording was
  re-taken to cover the full run: a 30522-token vocabulary, a round trip
  through encode and decode, then a 38-token document cut into 12-token chunks.
  `example/README.md` gained the companion piece: why `chunkByTokens`
  re-encodes every chunk instead of trusting the count it already has.
- The published archive now carries only the two images the `screenshots:`
  field names. The README loads its artwork from GitHub, and the other six
  files under `doc/` were dead weight in every download. The 1.0.2 archive was
  508 KB; this one is 334 KB.
- Both images now sit in the `screenshots:` field, the parity picture first.
  The demo caption that 1.0.2 shipped carried a literal line break inside the
  string, a leftover from a folded YAML block; both captions are single-line
  strings now.
- Docs and packaging only; nothing under `lib/` changed.

## 1.0.2

- **Add `example/rag_chunking.dart`: a token-counting `Chunker` for rag_kit.**
  `chunkByTokens` hands back strings, which is enough to respect a model's
  limit but not enough to say where a chunk came from — a retrieval pipeline
  that cites a passage needs the range. This builds one on `encodeWithOffsets`
  and carries both the token count and a real span.
  - The part worth reading is the conversion. `TokenOffset` is in **UTF-8
    bytes** and rag_kit's `Chunk` promises `source.substring(start, end) ==
    text`, which is UTF-16. On ASCII they agree and the bug hides; one Japanese
    sentence and the byte offset runs past the end of the Dart string. The
    example maps between them and then asserts the contract on every chunk.
  - It also measures the thing that makes token counting worth the trouble: on
    one mixed English-and-Japanese paragraph with a 24-token budget, the chunks
    ranged from 2.2 to 4.8 characters per token. A single character budget
    cannot be correct across that.
  - `rag_kit` is a dev dependency for this file only. It is pure Dart with no
    runtime dependencies, so consumers of this package are unaffected.

## 1.0.1

- **Document the glibc floor on the prebuilt Linux binary.** The platform table
  read "Linux x64 — prebuilt, no toolchain needed" with nothing qualifying it,
  and on an older distribution that is wrong. The released `.so` references
  `GLIBC_2.34`, so on Debian 11, which ships 2.31, the loader refuses it with
  `version 'GLIBC_2.34' not found`. Installing Rust does not route around it:
  the `cargo` fallback runs only when the prebuilt cannot be *downloaded*, and
  a download that succeeds is used as it is, so the failure lands at load
  rather than at build. The README now gives the floor, quotes what the loader
  says, and lists which distributions clear it — Ubuntu 22.04 and newer and
  Debian 12 do, Debian 11 does not, and Alpine fails earlier still because musl
  provides no `libc.so.6`. Docs only; the binary is unchanged.
- `lints` moves from 5 to 6 in the dev dependencies. Nothing new fired, so no
  source changed.

## 1.0.0

First stable release. The API below is what 1.0 freezes.

- **Fix `chunkByTokens` handing back pieces over the budget.** It counted the
  tokens of the whole text and assumed a slice of those bytes would re-encode
  to the same count. Tokenization is context-dependent, so it does not: with
  bert-base-uncased, `##ization` is one token inside `internationalization` but
  re-encodes as `i` + `##zation` when the same bytes lead a piece, and the
  piece came back one token over the limit it exists to enforce. Each piece is
  now re-encoded and shrunk until it fits. The one case left is a budget so
  small that a single token of the input already exceeds it alone — about three
  with BERT, with nothing left to split — and that is now documented.
- **Fix a hang and a crash in `chunkByTokens`.** The guard compared
  `overlapTokens` against `maxTokens`, but a chunk's real room is `maxTokens`
  less the special tokens the model adds. An overlap between the two passed the
  guard: at equality the cursor stopped advancing and the call looped forever
  appending pieces, and one above it stepped backwards and threw `RangeError`.
  With BERT's two specials, `chunkByTokens(text, 5, overlapTokens: 3)` hung and
  `chunkByTokens(text, 3, overlapTokens: 2)` threw. Both now raise
  `ArgumentError` naming the room actually available.
- **Fix `decode` silently returning the wrong text.** Token ids cross to the
  native side as `uint32`, so an id outside that range was truncated into a
  different, valid id: `decode([1 << 40])` came back as `[PAD]`. Out-of-range
  ids now throw `ArgumentError` instead of decoding to something plausible.
- **Fix `idToToken` breaking its own contract.** It documents "null if it is
  not in the vocabulary", but the same truncation made `idToToken(1 << 32)` and
  `idToToken(1 << 40)` return the token for id 0. They return null now.
- `TokenOffset` gets `==` and `hashCode`, so offsets compare by value.
- `Tokenizer` and `TokenOffset` are `final`. Both were already unsafe to
  subclass — `Tokenizer` owns a native handle and a finalizer — and this is the
  release to say so.
- Add a test that hashes the Rust crate and compares it against a digest stored
  next to the prebuilt release tag in the build hook. 0.5.0 changed the native
  ABI, left the tag on the previous release, and shipped a segfault to every
  prebuilt install for two days; the hook already carried a comment saying to
  bump the tag, and a comment cannot fail a build. This can.

## 0.5.1

- Fix a crash: the build hook's prebuilt-binary tag was left at `v0.4.0` after
  0.5.0 changed the native ABI (`tk_encode`, `tk_encode_offsets` and
  `tk_token_to_id` moved from a NUL-terminated string to an explicit
  `(pointer, length)` pair). `v0.4.0` still serves the old signatures, so any
  install that took the prebuilt path silently got an ABI-mismatched binary:
  the new bindings' extra length argument landed in the slot the old binary
  reads as an output pointer, and it segfaulted on the first real call. The
  hook now tracks `v0.5.0`, the tag that actually carries the rebuilt
  binaries.
- Declare `platforms: {linux, macos, windows}` in `pubspec.yaml`. The build
  hook has never produced a binary for Android or iOS (it throws there
  rather than attempting a host build that cannot target them), but with no
  platform declaration pub.dev's tagger inferred support for all five
  platforms from static analysis alone. The badge now matches what the hook
  actually builds.

## 0.5.0

- Fix a truncation bug: text containing a U+0000 byte was silently cut at the
  first NUL, so `encode`, `encodeWithOffsets`, `tokenToId` and the chunking
  built on them returned wrong counts on any document with an embedded NUL. The
  FFI now passes an explicit byte length instead of relying on NUL termination,
  so the whole input reaches the tokenizer and the ids stay byte-exact with the
  reference. This changes the native ABI, so the build hook now tracks release
  `v0.5.0` of the prebuilt binaries; a clean rebuild picks it up automatically.

## 0.4.5

- The build hook no longer crashes with a raw `ProcessException` when there is
  no prebuilt for the target and no Rust toolchain to fall back on. A missing
  `cargo` now produces a message that names the platform and points at
  rustup, and it distinguishes "no prebuilt exists for this target" from "the
  prebuilt could not be downloaded" so the reported cause is the real one.
- Android and iOS builds now fail immediately with a clear message instead of
  attempting a host build that cannot produce a mobile binary. The hook builds
  for the host only, so cross-compiled targets need a published prebuilt, which
  is not there yet. The README carries an honest platform table: prebuilt on
  macOS/Linux-x64/Windows-x64, source build elsewhere, mobile not supported yet.

## 0.4.4

- Widen the native-toolchain constraints so the package can be installed in a
  Flutter app at all. `hooks` 2.1.0 and `native_toolchain_c` 0.19.3 raised their
  `meta` floor to ^1.19.0, and Flutter's SDK pins `meta` to 1.17.0, so
  `flutter pub add` failed at version solving with "flutter from sdk is
  incompatible". Allowing `hooks >=2.0.2` and `native_toolchain_c >=0.19.2`
  lets the solver pick a version that works with the pinned `meta`, while a
  pure-Dart project still resolves to the newest. No API or behaviour change.

## 0.4.3

- Shorten the screenshot description. pub.dev accepts up to 200 characters but
  scores only those under 160, so the previous release published cleanly and
  quietly gave up the documentation points it was meant to earn.

## 0.4.2

- Declare the recording in `pubspec.yaml` so pub.dev renders it on the package
  page. It was already in the repository and the README, but pub.dev shows only
  what the `screenshots:` field points at.

## 0.4.1

- `example/context_budget.dart`: the three things a token budget needs, each
  checked in the output rather than described. It counts a prompt against the
  rule of thumb everyone reaches for (a quarter of a token per character, which
  undercounts this prompt by 8%, and undercounting is the direction that gets a
  request rejected), truncates to a budget and re-encodes the result to show it
  fits, and chunks with overlap and counts how many pieces came out over
  budget. Takes a `tokenizer.json` path so it can be pointed at the model you
  actually call.
- `example/README.md` explains what to take from that output, and why byte-exact
  ids are the foundation under it: a context budget does not degrade
  gracefully, it is fine until the request is refused.
- The original example no longer presents its hand-written chunking loop as the
  way to split a document. `chunkByTokens` has done that since 0.4.0, including
  the whitespace between token spans and the special tokens the model adds; the
  loop stays as the primitive to reach for when you need a window rule of your
  own.

## 0.4.0

- Add `truncateToTokens` and `chunkByTokens`. Context windows and embedding
  limits are counted in tokens while Dart strings are counted in UTF-16 units,
  so callers were left to slice byte offsets by hand; both of these cut where
  the tokenizer says. Cuts land on token boundaries, which are UTF-8
  boundaries, and with no overlap the chunks concatenate back to the input,
  whitespace between tokens included.
- Both reserve budget for the special tokens the model appends, not just the
  ones that happen to appear in the window being kept, so a truncated string
  re-encodes within the budget rather than one token over. A budget smaller
  than the markers themselves is rejected: with BERT's `[CLS]` and `[SEP]`,
  even an empty string encodes to two, so answering with one would break the
  budget the call exists to enforce.

## 0.3.0

- Add `encodeWithOffsets`, which returns each token as a `TokenOffset` carrying
  its id and the `[start, end)` **UTF-8 byte** span of the input it came from.
  This is what token-accurate chunking, span highlighting, and named-entity
  extraction need. Offsets are byte offsets (not UTF-16), so slice `utf8.encode`
  of the input rather than calling `String.substring`; special tokens carry an
  empty span. `encode` is unchanged for the id-only path.
- This adds one native symbol (`tk_encode_offsets`), so the prebuilt binaries
  are rebuilt for this release. The build hook downloads the matching binaries
  automatically; nothing to install.

## 0.2.0

- Add `tokenToId` and `idToToken` for single-token lookup in either direction.
  Both return null when the token or id is not in the vocabulary. `idToToken`
  keeps sub-word markers (such as WordPiece's `##`), so it differs from a
  `decode` of one id.
- This adds two native symbols (`tk_token_to_id`, `tk_id_to_token`), so the
  prebuilt binaries are rebuilt for this release. The build hook downloads the
  matching binaries automatically; nothing to install.

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
