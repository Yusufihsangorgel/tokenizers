# Mobile feasibility: can `hf_tokenizers` build for Android and iOS?

**Date:** 2026-08-29
**Scope:** this repository as it exists today (`hf_tokenizers` 1.1.0, native crate `tokenizers_ffi` over HuggingFace `tokenizers` 0.20, `hook/build.dart`).
**Method:** read this repo and the locked `hooks`/`code_assets` sources, fetch current Dart/Flutter/Rust toolchain docs, and run cargo cross-builds. No `lib/` or `hook/` files were changed.

Claim labels used throughout:

- **verified-with-citation** — quoted from this repo, a locked pub package, official docs, or a command that was run for this spike.
- **inferred** — follows from those facts but was not observed directly.
- **could-not-determine** — looked, and the evidence is missing or contradictory.

---

## Verdict

**Reachable with significant work. Not blocked upstream.**

Dart/Flutter build hooks already know about Android and iOS. They already hand a hook the target OS, architecture, Android NDK API level, iOS device-vs-simulator SDK, and a C compiler/linker/archiver. They already bundle a `DynamicLoadingBundled` dynamic library into an APK or an iOS framework. That path has been stable since Dart 3.10 / Flutter 3.38.

What this package lacks is engineering, not a missing SDK capability:

1. `hook/build.dart` **refuses** `OS.android` and `OS.iOS` on purpose.
2. There are **no mobile prebuilts** on the GitHub release the hook downloads.
3. A **source** mobile build has to pass `--target` and an NDK/iOS clang into cargo. Today's hook runs `cargo build --release` with neither.
4. The HuggingFace crate pulls in **Oniguruma C** (`onig` / `onig_sys`). A naive `cargo build --target aarch64-apple-ios` **failed to link** on this machine. The same crate **linked** once cargo was given the iOS SDK clang and a matching min version — exactly the kind of env a hook can set from `CodeConfig`.

**Do not treat this as a server-side niche and stop planning around mobile.** The Dart/Flutter side of "ship a Rust `.so` / `.dylib` to a phone through a build hook" is open. The remaining work is this package's hook, CI, and Oniguruma cross-compile flags.

**Do not treat it as a weekend either.** A vertical slice (Android arm64 + iOS arm64 prebuilts, hook download, one Flutter smoke app) is weeks. Production-quality (all ABIs, simulator, source fallback, CI, device tests, install-name/framework naming) is closer to one to two engineer-months.

Web remains blocked: `dart:ffi` does not run in a browser. That is a separate question from Android/iOS.

**Confidence: 80%.** High that hooks and Flutter bundling work for mobile dynamic libraries. High that this crate can produce an iOS dylib (observed). Medium-high that Android works once NDK clang is on `PATH` (the failure mode without an NDK is exactly "need `aarch64-linux-android-clang`"; third parties have compiled `tokenizers` + `onig` that way). The remaining 20% is "we did not run this crate through `flutter build apk` / `flutter build ios` on a device."

---

## 1. How this package builds native code today

**verified-with-citation** (`hook/build.dart`, `native/tokenizers_ffi/Cargo.toml`, `.github/workflows/ci.yml`, `pubspec.yaml`).

The published package is Dart. The tokenizer is Rust. The join is a C ABI (`tk_from_bytes`, `tk_encode`, …) loaded through `dart:ffi` `@Native` against the asset id `package:hf_tokenizers/src/bindings.dart`.

`native/tokenizers_ffi/Cargo.toml` already declares both crate types the mobile toolchains want:

```toml
[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
tokenizers = { version = "0.20", default-features = false, features = ["onig"] }
```

`hook/build.dart` is a `package:hooks` build hook. For each invocation it:

1. Reads `input.config.code.targetOS` and `input.config.code.targetArchitecture`.
2. Tries to download a prebuilt named for four desktop pairs only: macOS arm64/x64, Linux x64, Windows x64, from GitHub release `v0.5.0`.
3. Otherwise runs `cargo build --release` in `native/tokenizers_ffi/` with **no `--target`**, so cargo builds the **host**.
4. Emits a `CodeAsset` with `linkMode: DynamicLoadingBundled()`.

It then **throws** if the target OS is Android or iOS:

```dart
if (os == OS.android || os == OS.iOS) {
  throw Exception(
    'hf_tokenizers has no prebuilt binary for $os and cannot cross-compile '
    'it from source: the build hook builds for the host only. ...',
  );
}
```

That throw is policy in this repo, not a Dart SDK error. The same file already pattern-matches `OS.android` and `OS.iOS`, so the hook API is exposing those values.

`pubspec.yaml` declares `platforms: { linux, macos, windows }` only. CHANGELOG 0.5.1 says that was to stop pub.dev tagging Android/iOS from static analysis.

CI (`.github/workflows/ci.yml`) already cross-compiles **desktop** with `cargo build --release --target` (macOS x64 from a macOS runner, etc.). The release matrix has no Android or iOS triples.

Locked hook packages in `pubspec.lock`: `hooks` 2.1.0, `code_assets` 1.2.1. Current pub.dev at time of writing is `hooks` 2.2.0 and `code_assets` 2.0.0; the mobile types used below exist in the locked 1.2.1 sources.

---

## 2. What Dart native-assets / build hooks support for Android and iOS

**verified-with-citation** (official docs, API docs, locked `code_assets` 1.2.1 source).

Hooks are **stable** as of Dart 3.10 (released 2025-11-12):

- Dart changelog: <https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md> (3.10.0, "Support for **hooks** -- formerly know as *native assets* -- are now stable.")
- User guide: <https://dart.dev/tools/hooks> (page last updated 2026-07-15, "reflects Dart 3.13.0")
- Flutter FFI + hooks: <https://docs.flutter.dev/platform-integration/bind-native-code> (updated 2026-06-08, "Since Flutter 3.38, the recommended way… `flutter create --template=package_ffi`")
- Tracking issue, marked fixed, comment that it is stable since Flutter 3.38 / Dart 3.10: <https://github.com/flutter/flutter/issues/129757>

What a hook is given about the **target** (not the host), from locked `code_assets-1.2.1`:

| Input | Meaning |
| --- | --- |
| `CodeConfig.targetOS` | Includes `OS.android` and `OS.iOS` as first-class values (`os.dart`). |
| `CodeConfig.targetArchitecture` | `arm`, `arm64`, `ia32`, `x64`, `riscv64`, … |
| `CodeConfig.android.targetNdkApi` | Minimum Android API the binary must run on. |
| `CodeConfig.iOS.targetSdk` | `IOSSdk.iPhoneOS` or `IOSSdk.iPhoneSimulator`. |
| `CodeConfig.iOS.targetVersion` | Minimum iOS version. |
| `CodeConfig.cCompiler` | `compiler`, `linker`, `archiver` URIs. On a Flutter Android/iOS build this is the NDK/Xcode clang the SDK already found. |
| `CodeConfig.linkModePreference` | `dynamic` / `static` / `preferDynamic` / `preferStatic`. |

The Dart team documents default **host → target** cross-compile pairs in `OS.osCrossCompilationDefault` (`code_assets-1.2.1/lib/src/code_assets/os.dart`):

```
macOS → macOS, iOS, Android
linux → linux, Android
windows → windows, Android
```

iOS from Linux/Windows is **not** in that set. That matches Xcode: iOS binaries are produced on macOS.

Hooks run in a **semi-hermetic** environment. Most env vars are stripped. These **are** passed through (`hooks-2.1.0` `build()` docs and <https://dart.dev/tools/hooks>):

- `PATH`, `HOME`, `USERPROFILE`
- `LIBCLANG_PATH` (bindgen / clang-sys)
- `ANDROID_HOME`, `ANDROID_NDK`, `ANDROID_NDK_HOME`, `ANDROID_NDK_LATEST_HOME`, `ANDROID_NDK_ROOT`

A hook **can** `Process.run` cargo (this package already does) and **can** set whatever child env it wants. It cannot install Xcode or the NDK.

**Link mode that works today:** `DynamicLoadingBundled`. Flutter copies the file into the app. On Apple platforms it wraps the dylib as a **framework** and rewrites install names to `@rpath/<name>.framework/<name>` ([flutter/flutter#153054](https://github.com/flutter/flutter/pull/153054); docs at <https://docs.flutter.dev/platform-integration/bind-native-code> "Dynamic library naming guidelines").

**Link mode that does not work:** `StaticLinking`. The class exists. The docs still say:

> Not yet supported in the Dart and Flutter SDK.
> `TODO(https://github.com/dart-lang/sdk/issues/49418)`

That is true in both locked `code_assets` 1.2.1 and current 2.0.0 API docs: <https://pub.dev/documentation/code_assets/latest/code_assets/StaticLinking-class.html>. Tracker: <https://github.com/dart-lang/sdk/issues/49418>.

iOS **does not require a static library** for the hooks path. The old CocoaPods/`cargo lipo` world wanted a `.a`. The hooks world wants a `.dylib` that Flutter turns into a framework. This crate already emits both.

Flutter invokes the hook **once per architecture**, and on iOS **once per SDK** (device vs simulator). The output **filename must be the same** across those invocations (`libtokenizers_ffi.dylib`, not `libtokenizers_ffi_arm64.dylib`). Architecture-specific files go in `input.outputDirectory` (unique per invocation).

This machine had Flutter 3.41.2 / Dart 3.11.0, which is after the 3.38 / 3.10 stable cut. **verified-with-citation** (`flutter --version`, `dart --version`).

---

## 3. Android: what cross-compiling this crate would take

### Target triples

**verified-with-citation** (NDK docs, `native_toolchain_c` 0.19.3, `native_toolchain_rust` source).

| Dart `OS` + `Architecture` | Rust triple | NDK clang prefix | ABI |
| --- | --- | --- | --- |
| android + arm64 | `aarch64-linux-android` | `aarch64-linux-android{api}-clang` | arm64-v8a |
| android + arm | `armv7-linux-androideabi` | `armv7a-linux-androideabi{api}-clang` | armeabi-v7a |
| android + x64 | `x86_64-linux-android` | `x86_64-linux-android{api}-clang` | x86_64 |
| android + ia32 | `i686-linux-android` | `i686-linux-android{api}-clang` | x86 (rarely needed) |

NDK clang target docs: <https://developer.android.com/ndk/guides/other_build_systems>

`native_toolchain_c` uses the same mapping (`run_cbuilder.dart` `androidNdkClangTargetFlags`) and floors the API at **21** (35 for riscv64), matching AGP: <https://github.com/dart-lang/native/issues/171>.

### Tooling: cargo-ndk is optional

**verified-with-citation.**

You do **not** need the `cargo-ndk` binary inside the hook. You need the **same env it would set**:

- `CC_<triple>` / `CXX_<triple>` → NDK clang / clang++
- `AR_<triple>` → `llvm-ar`
- `CARGO_TARGET_<TRIPLE>_LINKER` → NDK clang
- `BINDGEN_EXTRA_CLANG_ARGS_<triple>` if bindgen runs (this crate's `onig_sys` 69.9.3 does **not** depend on bindgen; it uses `cc` + `pkg-config` only — `Cargo.lock`)

`native_toolchain_rust` does exactly that from `CodeConfig.cCompiler` ([`build_environment.dart`](https://raw.githubusercontent.com/GregoryConrad/native_toolchain_rust/main/native_toolchain_rust/lib/src/build_environment.dart)). It currently pins the NDK clang wrappers to API **35** (`aarch64-linux-android35-clang`) and notes NDK ≥ 27.

`cargo-ndk` is a convenience for humans and Gradle. A hook that already has `cCompiler.compiler` pointing at NDK clang can set those vars itself. Flutter's Android asset target constructs `AndroidCodeConfig(targetNdkApi: …)` and a `CCompilerConfig` from the NDK.

### What the hook can and cannot do

**Can (verified-with-citation):**

- See `targetOS == android`, architecture, `targetNdkApi`.
- Read NDK location from `cCompiler` and/or `ANDROID_*` env (allow-listed).
- `Process.run('cargo', ['build', '--release', '--target', triple], environment: …)`.
- Emit `CodeAsset(..., linkMode: DynamicLoadingBundled(), file: libtokenizers_ffi.so)`.
- Download a CI-built `.so` instead of compiling (same as today's desktop path).

**Cannot (verified-with-citation):**

- Install the Android SDK/NDK.
- Cross-compile if `cCompiler` is missing **and** no NDK is on the machine.

### Empirical: this crate, this machine

**verified-with-citation** (cargo run for this spike).

This environment had **no** `ANDROID_HOME` / `ANDROID_NDK_*` and **no** default `~/Library/Android/sdk`. After installing a throwaway rustup in `/tmp`:

```
cargo build --release --target aarch64-linux-android
```

failed in `onig_sys` 69.9.3:

```
failed to find tool "aarch64-linux-android-clang": No such file or directory
```

That is the NDK clang the hook is supposed to pass in. It is **not** a Dart limitation.

**inferred:** with Flutter's NDK clang on `CC_aarch64_linux_android` and `CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER`, `onig_sys` would compile. Third-party write-up of `tokenizers` 0.19.1 + `onig` for four Android ABIs using exactly those `.cargo/config.toml` linker lines: <https://proandroiddev.com/from-python-to-android-hf-sentence-transformers-embeddings-1ecea0ce94d8>. Reference Android JNI app: <https://github.com/jawrainey/hfta>. C++ binding used on iOS and Android: <https://github.com/mlc-ai/tokenizers-cpp>.

**could-not-determine:** an in-hook Android build of **this** `tokenizers_ffi` crate, because no NDK was present. Compiling `tokenizers` **on-device** in Termux has hit Android API-level C library issues ([huggingface/tokenizers#1902](https://github.com/huggingface/tokenizers/issues/1902)); NDK cross-compile with `--target=aarch64-linux-android{api}` is a different setup. Treat Oniguruma + old API levels as a **risk to budget for**, not as proof of an upstream block.

`esaxx_fast` (C++) is **off** in this crate (`default-features = false`, only `onig`). That avoids `libc++_shared.so`. If a future feature pulls C++, Flutter documents bundling it via `package:android_libcpp_shared`: <https://docs.flutter.dev/platform-integration/bind-native-code>.

---

## 4. iOS: static library vs dylib, and what the hook must do

### Target triples

**verified-with-citation** (`native_toolchain_rust` `config_mapping.dart`, `native_toolchain_c` `appleClangIosTargetFlags`).

| Dart | Rust triple |
| --- | --- |
| iOS + arm64 + `iPhoneOS` | `aarch64-apple-ios` |
| iOS + arm64 + `iPhoneSimulator` | `aarch64-apple-ios-sim` |
| iOS + x64 (simulator) | `x86_64-apple-ios` |

Must be built on **macOS with Xcode**. `xcrun --sdk iphoneos` / `iphonesimulator` were available on this machine.

### Is a static library required?

**No, not for build hooks. verified-with-citation.**

- Flutter + hooks: dylib → framework. Docs: <https://docs.flutter.dev/platform-integration/bind-native-code>
- Older Flutter C-interop page still describes `.framework` for dynamic libraries: <https://docs.flutter.dev/platform-integration/ios/c-interop>
- `StaticLinking` is **not implemented** in the Dart/Flutter SDK ([sdk#49418](https://github.com/dart-lang/sdk/issues/49418)).
- This crate already has `crate-type = ["cdylib", "staticlib"]`. Keep both: `native_toolchain_rust` **requires** both strings in `Cargo.toml`. Prefer emitting `DynamicLoadingBundled` until static lands.

If someone later wanted a `.a` for a CocoaPods plugin template, that is a **different** integration. Hooks do not need it.

### Empirical: this crate on iOS

**verified-with-citation** (cargo runs for this spike, rustc 1.98.0, throwaway toolchain in `/tmp`).

**Naive** (what today's hook would do if it only added `--target`):

```
cargo build --release --target aarch64-apple-ios
```

Rust and `onig_sys` **compiled**. The **cdylib link failed**:

```
Undefined symbols for architecture arm64:
  "___chkstk_darwin", referenced from:
      _match_at in libonig_sys-….rlib[…]regexec.o
ld: symbol(s) not found for architecture arm64
```

`cc` linked with `-target arm64-apple-ios10.0.0` (rustc's default). Oniguruma's C objects were built for the current iOS SDK (warning: "built for newer 'iOS' version (26.5) than being linked (10.0)"). `___chkstk_darwin` is a compiler-rt stack probe the C objects called and the iOS 10 link did not provide.

**With hook-shaped env** (iOS SDK clang, min version 13, matching rustc):

```
IPHONEOS_DEPLOYMENT_TARGET=13.0
CC_aarch64_apple_ios=<xcrun iphoneos clang>
CFLAGS_aarch64_apple_ios="-isysroot <sdk> -miphoneos-version-min=13.0 -target arm64-apple-ios13.0"
CARGO_TARGET_AARCH64_APPLE_IOS_LINKER=<same clang>
```

```
Finished `release` profile [optimized] target(s) in 1m 02s
libtokenizers_ffi.dylib   3.5M
libtokenizers_ffi.a        10M
```

Exported symbols (all current C ABI entry points):

`tk_from_bytes`, `tk_encode`, `tk_encode_offsets`, `tk_decode`, `tk_vocab_size`, `tk_token_to_id`, `tk_id_to_token`, `tk_free`, `tk_free_ids`, `tk_free_string`.

`otool -L` on the dylib: `libSystem.B.dylib`, `libiconv.2.dylib` (both iOS system libraries). The **install name** was an absolute temp path. Flutter's native-assets copy step rewrites that to `@rpath/…framework/…`. The hook should still use a stable filename (`libtokenizers_ffi.dylib`) and leave the rewrite to Flutter.

**Simulator** `aarch64-apple-ios-sim` with the simulator SDK clang: **success**, 3.5M dylib.

So: iOS is reachable **from a hook that sets SDK + min version**. It is **not** reachable from `cargo build --target` with no extra env. That is work in `hook/build.dart` (or adopting `native_toolchain_rust`), not an SDK ticket.

`CodeConfig.iOS.targetVersion` is the value to put in `-miphoneos-version-min` / `IPHONEOS_DEPLOYMENT_TARGET`. Do not let rustc default to iOS 10.

---

## 5. Published Dart packages that already ship Rust to mobile through hooks

**Partial yes.**

### Toolchains (published, Android + iOS tagged)

| Package | What it is | URL |
| --- | --- | --- |
| `native_toolchain_rust` 1.0.6 | Cargo + rustup from a `hook/build.dart`. Maps Dart OS/arch/iOS SDK → Rust triples. Sets NDK clang env. Requires `crate-type = ["staticlib", "cdylib"]` and a pinned `rust-toolchain.toml` listing those targets. | <https://pub.dev/packages/native_toolchain_rust> · source <https://github.com/GregoryConrad/native_toolchain_rust> |
| `flutter_rust_bridge_hooks` 2.13.0 | Thin wrapper around that, published 2026-08-23. Platforms: Android, iOS, Linux, macOS, Windows. | <https://pub.dev/packages/flutter_rust_bridge_hooks> · docs <https://cjycode.com/flutter_rust_bridge/manual/integrate/native-assets> |
| `build_rust_binaries` 0.1.0 | CDN/prebuilt + local cargo; claims Android NDK `.cargo/config.toml` generation. | <https://pub.dev/packages/build_rust_binaries> |

`native_toolchain_rust` is **days-to-weeks old** at 1.0.x (1.0.6 published ~2026-08-19). FRB's native-assets backend is equally new (`--integration-backend native-assets`, codegen ≥ 2.13.0-beta.2). This path exists; it is not a years-old commodity.

### Libraries that *use* those toolchains on mobile

pub.dev `dependency:native_toolchain_rust` returned essentially a stale mirror package.

pub.dev `dependency:flutter_rust_bridge_hooks`:

- `velopack_flutter` — **Linux/macOS/Windows only**
- `apollovm_wasm` — tags Android/iOS; WASM runtime, not a tokenizer analogue

**Finding:** I could **not** find a widely used published Dart **library** (sqlite3-shaped: you `pub add` it and a Flutter Android/iOS app just works) that already ships a **non-trivial Rust** crate to phones via hooks. Generated FRB *apps* are not that. Absence of a peer is itself a signal: you would be early, not first-on-the-planet (the toolchain exists) but first-in-class for a tokenizer.

### Closest analogue (C, not Rust) — this is the pattern to copy

**verified-with-citation:** `package:sqlite3` 3.5.2 declares Android and iOS, uses `hooks` + `code_assets` + `native_toolchain_c`, prefers GitHub-release **prebuilts** with sha256, falls back to compiling C. Docs: its `doc/hook.md`. That is this package's desktop model, extended to mobile.

C proof that **hooks + DynamicLoadingBundled work on phones**: sqlite3 and `package_ffi` templates. Rust proof that **the same protocol accepts a cargo-built dylib**: `native_toolchain_rust` / FRB hooks. End-to-end proof for **this** crate on a phone: not done.

---

## 6. Cost estimate

| Band | What it means here |
| --- | --- |
| Reachable now | Flip a flag, existing hook works. **No.** The hook throws, CI has no mobile assets, naive iOS cargo link fails. |
| **Reachable with significant work** | **This is the band.** SDK supports it. Crate can be built for iOS with env the hook can set. Android is the same idea plus NDK, not observed here. |
| Blocked upstream | A missing Dart/Flutter capability with no workaround. **Static linking** is blocked ([sdk#49418](https://github.com/dart-lang/sdk/issues/49418)) but **not required**. Web/FFI is blocked and out of scope. |

### Work if we invest

Two complementary tracks. Do **both**, in the same shape as desktop: prebuilt first, cargo fallback second.

**Track A — prebuilts (best consumer UX, matches today)**

1. Extend `.github/workflows/ci.yml`:
   - Ubuntu + NDK: `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`
   - macOS + Xcode: `aarch64-apple-ios`, `aarch64-apple-ios-sim`, optionally `x86_64-apple-ios`
2. Pass NDK clang / iOS SDK env (the flags that made iOS link). Pin `IPHONEOS_DEPLOYMENT_TARGET` to Flutter's `targetVersion`.
3. Upload `libtokenizers_ffi-android-arm64.so`, `libtokenizers_ffi-ios-arm64.dylib`, etc. Keep **one logical filename** inside the hook (`libtokenizers_ffi.so` / `.dylib`).
4. Teach `_prebuiltAssetName` those pairs. Stop throwing on `OS.android` / `OS.iOS`.
5. Declare `platforms: android` and `ios` in `pubspec.yaml` only after a real `flutter build`.

**Track B — source fallback in the hook**

1. Map `(os, arch, iOS.targetSdk)` → rustc triple (copy `native_toolchain_rust`'s `config_mapping.dart`, or depend on that package).
2. For Android: from `cCompiler` and `android.targetNdkApi`, set `CC_*`, `CFLAGS_*`, `CARGO_TARGET_*_LINKER`.
3. For iOS: from `cCompiler` / `xcrun` and `iOS.targetVersion`, set `IPHONEOS_DEPLOYMENT_TARGET`, `CC_*`, `CFLAGS_*` with `-isysroot` and `-miphoneos-version-min`. **Do not** call cargo with only `--target`.
4. `cargo build --release --target <triple>`.
5. Consumers who miss the prebuilt then need rustup **and** NDK or Xcode. That is worse than desktop, so keep prebuilts as the default.

**Do not skip the iOS min-version / SDK clang step.** This spike's first iOS build failed without it.

### Calendar cost (inferred)

| Slice | Effort |
| --- | --- |
| Android arm64 + iOS arm64 prebuilts, hook download, one example Flutter app | ~1–2 engineer-weeks |
| All ABIs, simulator, source fallback, CI, naming/install-name, docs | ~4–8 engineer-weeks |
| Device/emulator encode tests, size work, NDK API edge cases, Oniguruma surprises | extra, do not schedule as zero |

Release dylib size on iOS arm64 was **3.5 MB** (LTO, opt-level 3). **inferred:** Android `.so` in the same ballpark. Fine for on-device AI next to a model; not invisible.

### Risks that are not "blocked" but are real

- **Oniguruma** is C. Android without NDK clang does not build. iOS without SDK clang + min version does not **link**. Budget a day or two if an NDK version trips `onig_sys`.
- **`tokenizers` 0.20** cannot swap `onig` for `fancy-regex` except via the `unstable_wasm` feature. A later crate version, or a fork of the regex cfg ([huggingface/tokenizers#1509](https://github.com/huggingface/tokenizers/issues/1509)), is a fallback if Oniguruma stays painful.
- **iOS only from macOS.** Android from Linux/macOS/Windows.
- **Flutter version:** consumers need Dart ≥ 3.10 / Flutter ≥ 3.38. This package already has `sdk: ^3.10.0`.
- **`native_toolchain_rust` is new.** Using it is faster to write and younger to trust. Hand-rolling from `CodeConfig` (like this hook already does for desktop cargo) is more conservative.
- **No device run** in this spike. **could-not-determine:** load + `encode` inside a Flutter APK/IPA.

### What would make this "blocked upstream"

If the answer depended on **static** linking into the Dart AOT snapshot, it would be blocked on [sdk#49418](https://github.com/dart-lang/sdk/issues/49418). It does not.

If the answer depended on `dart:ffi` in Chrome, it would be blocked. That is web, not mobile.

---

## 7. Implications for the package's future

Mobile on-device AI is a reason to keep investing **if** someone will fund the hook + CI work above. The Dart platform will not do that work for this crate, but it will accept the binaries.

A honest public line, until that work ships, remains: desktop/server via prebuilt or host cargo; Android/iOS fail at build with the current message.

A honest internal line: **that failure is self-imposed.** The same hook already sees `OS.android` / `OS.iOS`. iOS dylibs of this crate were produced on this machine. Android is waiting on NDK clang, which Flutter already injects into hooks.

---

## Appendix: commands run for this spike

Throwaway rustc 1.98.0 under `/tmp/hf-tokenizers-spike-*` (not committed, not installed into the login home). Crate sources untouched.

| Command | Result |
| --- | --- |
| `cargo build --release --target aarch64-apple-ios` | Fail: `___chkstk_darwin` at cdylib link |
| Same + iOS SDK clang, `IPHONEOS_DEPLOYMENT_TARGET=13.0`, matching `CFLAGS_*` | **Pass.** 3.5M dylib, 10M `.a`, all `tk_*` exported |
| `cargo build --release --target aarch64-apple-ios-sim` + simulator SDK clang | **Pass.** 3.5M dylib |
| `cargo build --release --target aarch64-linux-android` (no NDK) | Fail: `onig_sys` cannot find `aarch64-linux-android-clang` |
| `xcrun --sdk iphoneos/--sdk iphonesimulator --show-sdk-path` | Present |
| Android SDK/NDK env and default macOS SDK path | Absent |

---

## Appendix: primary URLs

- <https://dart.dev/tools/hooks>
- <https://docs.flutter.dev/platform-integration/bind-native-code>
- <https://pub.dev/packages/hooks>
- <https://pub.dev/packages/code_assets>
- <https://pub.dev/documentation/code_assets/latest/code_assets/StaticLinking-class.html>
- <https://github.com/dart-lang/sdk/issues/49418>
- <https://github.com/flutter/flutter/issues/129757>
- <https://developer.android.com/ndk/guides/other_build_systems>
- <https://pub.dev/packages/native_toolchain_rust>
- <https://github.com/GregoryConrad/native_toolchain_rust>
- <https://cjycode.com/flutter_rust_bridge/manual/integrate/native-assets>
- <https://github.com/bbqsrc/cargo-ndk>
