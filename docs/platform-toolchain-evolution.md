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

The baseline below is the currently exercised development environment. It is a
compatibility matrix, not permission to distribute a manually built artifact.
Release scripts remain the authority for embedded app version and packaging.

| Surface | Verified baseline | Hivra ownership |
| --- | --- | --- |
| Flutter | 3.41.2 stable | App shell and platform embedding |
| Dart | 3.11.0 | Flutter application code |
| Rust / Cargo | 1.93.0 | Core, engine, adapters, FFI, WASM runtime |
| Rust Android targets | `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android` | Android FFI artifacts |
| Android SDK | platform/build tools 36.1 | Android build environment |
| App SDK contract | compile 36, target 36, min 24 | `flutter/android/app/build.gradle.kts` via Flutter defaults |
| Android Gradle Plugin | 8.13.2 | Android build graph |
| Gradle wrapper | 8.13 | Android build graph |
| Kotlin plugin | 2.2.20 | Android embedding and keystore bridge |
| JDK | Android Studio JBR 21 | Android build execution |
| Android NDK | 28.2.13676358 | `cargo ndk` Rust FFI build |
| Xcode | 26.6 | macOS packaging and native loading |
| CocoaPods | 1.16.2 | macOS Flutter plugins |

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

Status: planned; this is the next platform-evolution unit.

### T1: Flutter/Dart stable update

Goal:
- update Flutter and Dart only after T0 locks the prior baseline.

Current candidate:
- Flutter 3.44.x / Dart 3.12.x is newer than the verified 3.41.2 / 3.11.0
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

The final record belongs in the release evidence for a released update and in
`docs/roadmap.md` while the unit remains active.

## 6. Relationship to 1.x and 2.0

- Toolchain work is allowed in 1.x only as a dedicated reliability/release
  change. It does not change Capsule facts, Core semantics, or delivery policy.
- V2-0 inventories the toolchain boundary as part of its composition-root and
  dependency map, but it does not replace the bridge.
- 2.0 may redesign capability contracts above the existing C ABI only when a
  specific migration proves a stronger public boundary and deletes the old
  callable path. No such bridge migration is currently planned.
