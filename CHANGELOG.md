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
