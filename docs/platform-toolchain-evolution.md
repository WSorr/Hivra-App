# Hivra Platform Toolchain Evolution

Status: active release-engineering contract for Hivra 1.x and the later Hivra
2.0 program.

This document owns the evolution of the build and platform toolchain. It is not
an application architecture migration and it does not authorize a protocol,
ledger, FFI, or product-behavior change.

## 1. Purpose and Boundary

Hivra runs one Rust domain/runtime through a stable C ABI consumed by the
Flutter application on macOS and Android. The bridge remains `dart:ffi` plus
the explicit `hivra-ffi` C surface. Hivra does not plan a bridge-framework
migration in either 1.x or 2.0.

Toolchain evolution is a separate release-engineering lane:

```text
Flutter/Dart + Android build stack + Rust/NDK + macOS/Xcode
  -> build the same checked-in Hivra source and C ABI
  -> package a platform artifact
  -> verify the same capsule truth and user-visible behavior
```

An SDK update may change compilation, packaging, native loading, security
prompts, storage behavior, or platform lifecycle. It therefore requires the
same explicit owner, evidence, and rollback discipline as a runtime adapter
change. It must not be smuggled into feature work or a release candidate.

## 2. Current Verified Baseline

Audit date: 2026-08-03.

The baseline below is the currently exercised development environment. It is a
compatibility matrix, not permission to distribute a manually built artifact.
Release scripts remain the authority for embedded app version and packaging.

| Surface | Verified baseline | Hivra ownership |
| --- | --- | --- |
| Flutter | 3.41.2 stable | App shell and platform embedding |
| Dart | 3.11.0 | Flutter application code |
| Rust / Cargo | 1.93.0 | Core, engine, adapters, FFI, WASM runtime |
| Rust Android targets | `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android` | Android FFI artifacts |
| Android SDK | platform 36.1 / build tools 36.1.0 | Android build environment |
| App SDK contract | compile 36, target 36, min 24 | `flutter/android/app/build.gradle.kts` via Flutter defaults |
| Android Gradle Plugin | 8.13.2 | Android build graph |
| Gradle wrapper | 8.13 | Android build graph |
| Kotlin plugin | 2.2.20 | Android embedding and keystore bridge |
| JDK | Android Studio JBR 21 resolved through Flutter | Canonical Android build execution environment; plain shell Gradle JDK selection is noncanonical diagnostic evidence |
| Android NDK | 28.2.13676358 | `cargo ndk` Rust FFI build |
| Xcode | 26.6 | macOS packaging and native loading |
| CocoaPods | 1.16.2 | macOS Flutter plugins |

Observed host evidence:

- macOS `26.5.2` on Apple Silicon;
- Flutter doctor resolves JBR `21.0.9` and Android SDK `36.1.0`;
- `./gradlew --version` from a plain shell resolves OpenJDK `17.0.18`;
- Xcode `26.6` is selected and can package macOS, but simulator-runtime
  discovery remains unhealthy;
- the connected Android device runs Android 16 / API 36;
- all required Android Rust targets plus `wasm32-unknown-unknown` are installed.

The exercised baseline is now represented by one checked-in, non-secret
contract:

1. `toolchains/hivra-baseline.conf` records the complete supported version
   matrix without local paths, credentials, or signing identities.
2. `rust-toolchain.toml` selects Rust `1.93.0`, the minimal profile, `rustfmt`,
   and every required repository target.
3. `tools/toolchain/verify_environment.sh --static` validates repository-owned
   pins and build configuration; `--full` additionally resolves and validates
   the complete local macOS and Android environment.
4. `--self-test` proves that a mismatched version fails closed and reports both
   expected and actual values.
5. Flutter-resolved JBR 21 is the canonical Gradle JDK. A direct shell Gradle
   invocation may resolve a different host JDK, but it is diagnostic evidence,
   not a second supported build authority.

Local Flutter and Android SDK paths correctly remain untracked. The full
verifier resolves them from `flutter/android/local.properties` and rejects a
missing path or package mismatch before release packaging. Simulator-runtime
discovery remains an explicit warning because it does not affect the macOS or
Android T0 artifact contract; it cannot support a future iOS evidence claim.

### Upstream Currency Snapshot

Currency is not adoption. This snapshot records available stable versions so
that “current” does not silently become “approved”.

| Surface | Stable available on audit date | Decision |
| --- | --- | --- |
| Flutter / Dart | Flutter 3.44.8 / Dart 3.12.2 | Candidate for T1 after T0; not adopted |
| Rust / Cargo | Rust 1.97.1 | Separate post-T0 toolchain unit; not adopted |
| Android NDK | r29 available; r28.2 remains Flutter 3.41.2 default | Keep r28.2 baseline until a dedicated compatibility pass |
| AGP / Gradle | AGP 8.13.2 with Gradle 8.13 is an official compatible pair for API 36.1 | Keep baseline; AGP 9 remains a separate migration |
| Xcode | Xcode 26.6 | Current exercised baseline; repair simulator discovery separately if iOS evidence is required |

Primary audit sources:

- Flutter stable archive and release notes:
  `https://docs.flutter.dev/install/archive` and
  `https://docs.flutter.dev/release/release-notes`;
- Rust release channel: `https://blog.rust-lang.org/releases/` plus the local
  `rustup check` result;
- AGP 8.13 compatibility:
  `https://developer.android.com/build/releases/agp-8-13-0-release-notes`;
- Gradle Java compatibility:
  `https://docs.gradle.org/current/userguide/compatibility.html`;
- Android NDK history:
  `https://developer.android.com/ndk/downloads/revision_history`;
- Xcode 26.6 release notes:
  `https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes`.

`flutter pub outdated` also reports dependency drift. Patch-compatible updates
and major constraint changes are not toolchain T0 work: each must be selected
under the capability owner it can affect, with focused regression and platform
evidence. In particular, secure storage, connectivity, scanning, sharing, and
archive changes must not be bundled into an SDK update.

The native library contract is deliberately stable across these tools:

- macOS package contains universal `arm64 + x86_64` `libhivra_ffi.dylib`;
- Android package contains `arm64-v8a`, `armeabi-v7a`, and `x86_64`
  `libhivra_ffi.so`;
- the Dart layer loads only checked-in C symbols from `hivra-ffi`;
- no Flutter, Android, Rust, or Xcode upgrade may introduce a second bridge,
  a second ledger path, or a platform-specific Core implementation.

## 3. Invariants

1. **One source, two verified artifacts.** macOS and Android package the same
   source commit, protocol version, plugin-host ABI, and release build version.
2. **ABI stability.** Toolchain work does not change a public FFI symbol,
   memory ownership rule, or wire representation unless a separate FFI contract
   change has passed the product-axis and protocol gates.
3. **No hidden version authority.** `local.properties`, IDE defaults, build
   caches, and a manually launched app are not release-version authority.
   Release scripts derive and embed the version from the requested release tag.
4. **Platform parity before publication.** An update is not accepted because it
   compiles. It must package, install, cold-start, restore, receive, and
   exercise the affected platform behavior from the exact artifact.
5. **No opportunistic major migration.** Flutter, AGP, Kotlin, Gradle, JDK,
   NDK, Rust, or Xcode upgrades happen in dedicated toolchain units. They do
   not ride alongside invitation, ledger, trading, plugin, or UI changes.

## 4. Toolchain Evolution Units

Each unit has exactly one primary purpose and one owner: Release Engineering.
It may update lock/configuration files and platform build scripts, but it may
not change product semantics.

### T0: Baseline and reproducibility

Goal:
- make the verified matrix visible and reject an accidental environment drift.

Required work:
- add a checked-in toolchain verification command for Flutter/Dart, Rust/Cargo,
  Android SDK/NDK, AGP/Gradle/Kotlin, JDK, and Xcode;
- pin the Rust toolchain and required targets in repository configuration;
- keep secrets, local SDK paths, signing identities, and `local.properties`
  outside Git;
- add CI coverage where a runner can validate the non-secret subset.

Exit evidence:
- clean checkout reports a precise missing/mismatched prerequisite;
- macOS and Android release scripts still package the expected universal/ABI
  native libraries;
- no generated artifact or local machine path enters Git.

Completion evidence (2026-08-03):

- verifier self-test, static verification, and full local verification passed;
- `flutter analyze`, all `737` Flutter tests, `cargo test --workspace`, and
  `tools/review/review_all.sh` passed;
- fresh release build `100000327` packaged a universal macOS
  `libhivra_ffi.dylib` with `x86_64 + arm64` and Android
  `libhivra_ffi.so` for `arm64-v8a`, `armeabi-v7a`, and `x86_64`;
- the macOS library SHA-256 was
  `7b0bbba8f5e97d5369197be27a335b2d3c69e4db78cd86dc4d5d728928a84210`;
- the Android APK SHA-256 was
  `e9b778bb7cde5dc0fe01265a44af820450d6eb462461bdd11ab3946247b5be80`;
- both fresh artifacts cold-started without fatal startup evidence, and the
  smoke processes were stopped afterward.

Status: completed. T1 is not activated automatically by T0 completion.

Post-AI-4 reverification (2026-08-04):

- full local verification matched every checked-in T0 version and Rust target;
- Flutter-resolved JDK 21 remains the sole Android build authority;
- direct `./gradlew` JDK selection remains noncanonical diagnostic evidence;
- simulator-runtime discovery remains unhealthy but outside the maintained
  macOS/Android T0 packaging claim;
- no T1, Rust, Android-stack, Xcode, or CocoaPods update was selected.

### T1: Flutter/Dart stable update

Goal:
- update Flutter and Dart only after T0 locks the prior baseline.

Current candidate:
- Flutter 3.44.8 / Dart 3.12.2 is newer than the verified 3.41.2 / 3.11.0
  baseline. It is not adopted by default.

Required evidence:
- `flutter analyze`, full Flutter tests, Rust tests, and review gates;
- release packages built with the candidate toolchain for both macOS and
  Android;
- cold start, secure-storage access, capsule selection, restore, invitation,
  chat, plugin install, and trading-drone smoke from those packages;
- explicit comparison of generated platform files and a documented rollback to
  the prior baseline.

Status: deferred until T0 is complete and the active 1.x integrity pass is not
in flight.

### T2: Android build-stack update

Goal:
- update one compatible Android build-stack set at a time: AGP, Gradle,
  Kotlin, JDK, NDK, or Android SDK.

Rules:
- AGP, Gradle, and Kotlin are treated as a compatibility set, never as three
  unrelated dependency bumps;
- Android API behavior changes require an Android 16 targeted-behavior smoke on
  a physical device or emulator before publication;
- AGP 9 is a separate migration proposal, because Flutter requires the
  built-in Kotlin transition for AGP 9+. It is not a routine patch update;
- public Android distribution remains blocked until the artifact is signed by
  a dedicated release/upload key. Debug signing is allowed only for the
  explicit `test` channel.

Status: deferred. The current AGP 8.13.2 / Gradle 8.13 / Kotlin 2.2.20 / NDK
28.2 set is internally compatible and supports API 36.1.

### T3: macOS/Xcode update

Goal:
- update Xcode, macOS deployment settings, or CocoaPods without breaking
  universal FFI packaging, Keychain access, signing, or notarization.

Rules:
- verify both Apple Silicon and Intel native slices after every Xcode update;
- run real Keychain cold-start/reopen smoke, not only an unsigned local launch;
- missing simulator runtimes are not a macOS release blocker, but block any
  future iOS test claim until repaired.

Status: monitoring. Xcode 26.6 packages macOS today; simulator runtime
discovery is currently unhealthy.

## 5. Required Upgrade Record

Before an evolution unit changes code, record:

1. old and proposed matrix versions;
2. compatibility source and known platform behavior changes;
3. exact build/package commands;
4. affected release checklists and manual smoke cases;
5. rollback command or pinned prior version;
6. whether ABI, artifact layout, signing, storage, or startup behavior changed;
7. source commit and resulting artifact hashes.

The final record belongs in the release evidence for a released update. While
the unit is active, its outcome and exit evidence belong in the implementation
PR and the short board in `docs/development-control.md`.

## 6. Relationship to 1.x and 2.0

- Toolchain work is allowed in 1.x only as a dedicated reliability/release
  change. It does not change Capsule facts, Core semantics, or delivery policy.
- V2-0 inventories the toolchain boundary as part of its composition-root and
  dependency map, but it does not replace the bridge.
- 2.0 may redesign capability contracts above the existing C ABI only when a
  specific migration proves a stronger public boundary and deletes the old
  callable path. No such bridge migration is currently planned.
