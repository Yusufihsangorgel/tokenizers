# Package engineering rules: hf_tokenizers

Rules-Version: hf_tokenizers/fdd53ca785a75f48f11fc6f47fb122695bd3d2d5030dd2e1fe8b393b503d3249
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: eeb67b9
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD eeb67b9 (1.2.2). A cdylib sits on top of the HuggingFace `tokenizers` Rust crate (native/tokenizers_ffi; lib.rs 223 lines, 9 extern C functions, null-checked). The Dart side is one file: `lib/hf_tokenizers.dart` (488 lines) serves as both the public entry point and the implementation. It contains `_allocUtf8`, `TokenOffset`, and `Tokenizer`. `Tokenizer` carries FFI resource management, encode/decode, and the token budget algorithms (truncateToTokens, chunkByTokens) in one class. `lib/src/bindings.dart` binds with `@DefaultAsset`. The hook differs from the C/C++ siblings: it downloads a prebuilt binary from a GitHub release tagged with a fixed `_version`; if that fails it runs `cargo build --release` for the host; it rejects android/iOS. The downloaded binary is not integrity-checked. There is no panic barrier on the Rust side. CI performs no format or fatal-infos check.

## Layers and responsibilities
- lib/hf_tokenizers.dart: Tokenizer (loading, encode/decode, vocabulary queries, budget algorithms, close), TokenOffset, `_allocUtf8`, `_maxTokenId`.
- lib/src/bindings.dart: `@DefaultAsset`, 11 `@Native` + `tkFreePtr`.
- native/tokenizers_ffi/: Cargo.toml, Cargo.lock, src/lib.rs (extern C, null checks, free functions for owned returns), examples/count_bench.rs.
- hook/build.dart: Prebuilt download (`_version`), cargo fallback, error messages, `nativeSourcesDigest`.
- test/: tokenizers_test, token_budget_test, prebuilt_tag_test, fixtures/bert-base-uncased.json.
- tool/, example/: ffi_smoke, measurement and figure scripts; a RAG example using rag_kit.
- AGENTS.md, llms.txt, MOBILE-FEASIBILITY.md: User contracts; a mobile feasibility spike report (2026-08-29).

## Public API and dependency direction
Tokenizer.fromBytes(Uint8List), Tokenizer.fromFile(String); vocabSize, tokenToId(String) -> int?, idToToken(int) -> String?, count(text, {addSpecialTokens=true}), encode(text, {addSpecialTokens=true}) -> List<int>, encodeWithOffsets -> List<TokenOffset>, decode(ids, {skipSpecialTokens=true}), truncateToTokens(text, maxTokens, {addSpecialTokens}), chunkByTokens(text, maxTokens, {overlapTokens=0, addSpecialTokens}), close. TokenOffset(id, start, end): UTF-8 byte offsets, ==/hashCode. There is no separate export list. The library file itself is the boundary. `nativeSourcesDigest` is public in hook/build.dart but only tests read it.

hf_tokenizers.dart -> src/bindings.dart, package:ffi, dart:io, dart:convert. bindings -> dart:ffi, package:ffi -> (asset) Rust cdylib -> tokenizers crate. hook -> code_assets/hooks, dart:io (HttpClient, Process). test/prebuilt_tag_test.dart -> native/ sources (crypto dev dependency). No cycle. The budget algorithms depend only on encode/encodeWithOffsets and do not touch FFI directly.

## Error, state and platform contracts
- Text passes as (pointer, length). `_allocUtf8` allocates at least 1 byte. U+0000 is preserved (hf_tokenizers.dart:18-32).
- uint32 bound validation uses `_maxTokenId` (34-36, 147-149, 243-254).
- Finalizable + NativeFinalizer(tkFreePtr) + idempotent close + `_ensureOpen()` -> StateError (88-95, 474-487).
- Errors: FormatException (tokenizer.json), StateError (closed or native null), ArgumentError.value (id, budget).
- Budget algorithms: special tokens are subtracted from the budget. Every chunk is re-encoded and verified. A loop that makes no progress raises ArgumentError (302-322, 401-470).
- Prebuilt tag plus source digest: `_version` and `nativeSourcesDigest` live in the hook. test/prebuilt_tag_test.dart fails on drift (hook/build.dart:6-34).
- The hook error message names the first cause: download or toolchain (hook/build.dart:187-205).
- Rust: every pointer is null-checked. Errors surface as null or false returns (lib.rs:18-220).
- `.pubignore` publishes only the `screenshots:` images.
- Dartdoc cites the measurement tool (`tool/measure_count.dart`, 167-170).
- Global state is only const/final (_maxTokenId, NativeFinalizer, tkFreePtr).
- Documentation layout: AGENTS.md targets users (Purpose/Usage/Contracts/Mistakes/Layout).

## Package rules
### hf_tokenizers/TK-01 [MUST]
The public surface is defined in lib/hf_tokenizers.dart (Tokenizer, TokenOffset); lib/src/bindings.dart is not exported, and new helpers stay library-private (`_`).
Reason: Private names are the only guard against leakage because there is no separate show list.
Evidence: lib/hf_tokenizers.dart:16, 25, 36
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-02 [MUST]
Text going to native passes as an explicit (pointer, length) pair through `_allocUtf8`; no new NUL-terminated interface is added.
Reason: In 0.5.0 the NUL-terminated interface truncated text at U+0000; the ABI changed for that reason.
Evidence: lib/hf_tokenizers.dart:18-32; hook/build.dart:14-21
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-03 [MUST]
Token ids are validated against the native uint32 bound: decode rejects out-of-range values with `ArgumentError.value(id, 'ids[i]', ...)`, and idToToken returns null.
Reason: An out-of-range value wraps to another valid id in the FFI and resolves the wrong token.
Evidence: lib/hf_tokenizers.dart:34-36, 147-149, 243-254; test/tokenizers_test.dart:176-178
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-04 [MUST]
Error contract: invalid tokenizer.json -> FormatException; a closed tokenizer or a native null return -> StateError; parameter -> ArgumentError.value.
Reason: Three classes pinned by tests.
Evidence: lib/hf_tokenizers.dart:100-109, 184, 218, 259, 295-322, 372-425, 485-487; test/tokenizers_test.dart:193-207
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-05 [MUST]
Tokenizer lifecycle: close() is idempotent, the NativeFinalizer is detached; every public method that touches native goes through `_ensureOpen()`.
Reason: Access to a closed handle becomes a native use-after-free.
Evidence: lib/hf_tokenizers.dart:88-95, 117, 126, 148, 179, 205, 244, 474-487
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-06 [MUST]
When the C ABI in the Rust crate changes, the `_version` tag in hook/build.dart changes together with a new binary release and `nativeSourcesDigest` is updated; test/prebuilt_tag_test.dart enforces this.
Reason: When the 0.5.0 tag was left stale, prebuilt installations segfaulted on the first call for two days (measured incident).
Evidence: hook/build.dart:6-34; test/prebuilt_tag_test.dart:7-23
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-07 [MUST]
Every extern C function in Rust checks every pointer parameter for null and reports the error with a null or false return; an owned return has a matching `tk_free_*` function.
Reason: The Dart side converts null to StateError; ownership must be symmetric.
Evidence: native/tokenizers_ffi/src/lib.rs:18, 31, 54, 94, 138, 152, 169, 191, 201-222
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-08 [MUST]
The hook falls back to building from source when no prebuilt exists or the download fails. The failure message names the first cause (download or toolchain); android/iOS is rejected with an explicit message.
Reason: The hook cannot compile anything outside the host; an early and explicit error instead of producing a wrong binary.
Evidence: hook/build.dart:53-76, 138-150, 187-205
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-09 [MUST]
The budget APIs subtract the special tokens the model adds from the budget, verify the result fits by re-encoding it, and reject a loop that makes no progress with ArgumentError.
Reason: Tokenization depends on concatenation (WordPiece continuation pieces); counting alone is not enough.
Evidence: lib/hf_tokenizers.dart:302-322, 401-425, 443-461; test/token_budget_test.dart:20, 94
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-10 [MUST]
TokenOffset offsets are UTF-8 byte offsets and are not converted to String indexes; an API that changes this meaning takes a separate name.
Reason: This is the unit the crate reports; converting to a substring gives wrong text outside ASCII.
Evidence: lib/hf_tokenizers.dart:38-54
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-11 [SHOULD]
`.pubignore` stays a superset of `.gitignore`; from doc/ only the `screenshots:` images are published, and native/tokenizers_ffi/target/ is not published.
Reason: .pubignore shadows .gitignore.
Evidence: .pubignore
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-12 [SHOULD]
`platforms:` stays linux/macos/windows; mobile support is not added before published prebuilts exist and the conditions in MOBILE-FEASIBILITY.md are met.
Reason: The hook cannot produce binaries for mobile.
Evidence: pubspec.yaml:25-28; hook/build.dart:143-150
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-13 [MUST]
Package level holds only const/final fields; no mutable global state is added.
Reason: The current code follows this.
Evidence: lib/hf_tokenizers.dart:36, 94; lib/src/bindings.dart:87
Evidence role: current-pattern
Existing violation: none

### hf_tokenizers/TK-14 [MUST]
A new native operation follows this skeleton: a `#[no_mangle]` extern C function in Rust (null-checked, with a free for owned returns), a declaration in bindings, and in Dart `_ensureOpen()` + `_allocUtf8` + Dart and native releases in try/finally. If the ABI changes, TK-06 applies.
Reason: The current extension point.
Evidence: native/tokenizers_ffi/src/lib.rs:29-34, 201-222; lib/hf_tokenizers.dart:125-136
Evidence role: current-pattern
Existing violation: hf_tokenizers-D005

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:31.
- Working directory: repository root; command: dart analyze; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:32.
- Working directory: repository root; command: dart test; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:33.
- Working directory: native/tokenizers_ffi; command: cargo build --release --target ${{ matrix.target }}; conditions: ci.yml job binaries; evidence: .github/workflows/ci.yml:66.
- Working directory: repository root; command: cp "native/tokenizers_ffi/target/${{ matrix.target }}/release/${{ matrix.lib }}" "${{ matrix.asset }}"; conditions: ci.yml job binaries; evidence: .github/workflows/ci.yml:69.
Not verified by the survey:
- `dart analyze`/`dart test` were not run (read-only scope); CI status (no network).
- Whether the CI tests use the prebuilt binary or a source build was not measured (the hook tries the download first).
- Rust panic behavior and the CI toolchain version were not exercised.
- Whether `calloc(0)` returns null on the supported platforms was not measured. In practice glibc, macOS, and Windows may not return null.
- MOBILE-FEASIBILITY.md was not read in full. No explicit plan or issue link for mobile support was found.
- The currency of the tokenizers crate version in Cargo.lock (no network).

## Existing debt
The complete register is docs/engineering/debt.json.
- hf_tokenizers-D001 | medium | hook/build.dart:114-129 (56-58; 24-34) | security (supply chain)
  Fix: Pin a SHA-256 for every release asset (produced by the CI binaries job), verify after download, fall back to a source build on mismatch; add a test.
  Closure: Every release asset carries a pinned SHA-256 produced by the CI binaries job and the hook verifies it after download. A mismatch triggers the source-build fallback and a test covers that path.
- hf_tokenizers-D002 | medium | native/tokenizers_ffi/src/lib.rs (9 extern C functions, no catch_unwind) | FFI safety
  Fix: Wrap every body with `std::panic::catch_unwind`, return null or false on panic (the Dart side already converts to StateError); publish with a `_version` and digest update.
  Closure: Every extern C body in native/tokenizers_ffi/src/lib.rs is wrapped in std::panic::catch_unwind and returns null or false on panic. The change ships with an updated _version tag and nativeSourcesDigest.
- hf_tokenizers-D003 | small | hook/build.dart:154-158, 184 | hook hygiene
  Fix: Build under `input.outputDirectoryShared` with `--target-dir`.
  Closure: cargo build runs with --target-dir under input.outputDirectoryShared and the package directory in the pub cache stays unmodified.
- hf_tokenizers-D004 | small | hook/build.dart:124-125 | broad catch
  Fix: Narrow it to `IOException`/`HttpException` or write a comment naming the reason.
  Closure: The catch in _download is narrowed to IOException or HttpException or carries a comment naming the accepted failure reasons.
- hf_tokenizers-D005 | small | lib/hf_tokenizers.dart:101-104, 152-153, 185-186, 221-228, 255-256, 260-261 | resource cleanup
  Fix: Nested try/finally.
  Closure: fromBytes, idToToken, encode, encodeWithOffsets and decode release native memory inside nested try/finally blocks.
- hf_tokenizers-D006 | small | lib/hf_tokenizers.dart:101, 255 (<-> 27) | inconsistency
  Fix: The same guard + empty-input tests.
  Closure: fromBytes and decode allocate at least one byte on empty input, matching _allocUtf8. Empty-input tests cover both entry points.
- hf_tokenizers-D007 | small | .github/workflows/ci.yml:16-17, 31-33 | CI gap
  Fix: Add the format and --fatal-infos steps; move the write permission to the binaries job only.
  Closure: The CI workflow runs a format check and dart analyze with --fatal-infos. Only the binaries job holds the write permission.
- hf_tokenizers-D008 | small | test/hook_test.dart (missing); hook/build.dart:43 | missing test
  Fix: A hook_test.dart based on the siblings' testBuildHook; a test of the code-asset-free path without network.
  Closure: test/hook_test.dart runs the hook without code assets and without network and covers the download and source fallback branches.
- hf_tokenizers-D009 | small | hook/build.dart:86-89 <-> test/prebuilt_tag_test.dart:19-23 | inconsistency
  Fix: Add `crateDir.resolve('Cargo.lock')`.
  Closure: hook/build.dart lists crateDir.resolve('Cargo.lock') among its dependency inputs and a lockfile change invalidates the hook cache.
- hf_tokenizers-D010 | medium | lib/hf_tokenizers.dart:268-472 | single responsibility
  Fix: Enter it in the debt register. Move the algorithms into `lib/src/token_budget.dart`, depending only on encode/encodeWithOffsets and preserving the public signatures; the methods delegate.
  Closure: The budget and chunking algorithms live in lib/src/token_budget.dart behind private helpers and depend only on encode and encodeWithOffsets. The public signatures are unchanged and test/token_budget_test.dart passes.
- hf_tokenizers-D011 | small | hook/build.dart:147-148; MOBILE-FEASIBILITY.md | untracked follow-up
  Fix: Link it to a specific issue; update the report or add it to .pubignore.
  Closure: The android and iOS rejection message links a specific issue. MOBILE-FEASIBILITY.md is current or excluded from the published archive through .pubignore.
- hf_tokenizers-D012 | small | analysis_options.yaml:1-6 | analysis strictness
  Fix: Complete the image_ffi settings.
  Closure: analysis_options.yaml enables strict-inference and public_member_api_docs together with the other image_ffi settings and dart analyze reports no new diagnostics.
