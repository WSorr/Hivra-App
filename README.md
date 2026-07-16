# Hivra

Hivra is a local-first runtime for user-owned Capsules.

A Capsule is a persistent digital extension of a user. It can operate independently, keep its own ledger, run WASM drones, and optionally establish trusted links with other Capsules through invitations.

Hivra is best understood as a personal capsule computer:

- not a global shared world computer
- not an account inside someone else's network
- not a social network, public graph, or discovery product
- but a local-first runtime for your own capsule state, history, recovery, drones, and optional trusted links

The capsule is the center of truth. Transport adapters move messages, but they do not define identity or replace local truth.

Trusted links form a **Core Trust Layer**, not a social network. They are internal trust facts created only through real-world invitations. There is no global discovery, no people search, and no public network map.

Applications normally own their own user relationships. Hivra moves trusted interaction state into the user-owned Capsule, so WASM drones can reuse the same Trust Layer instead of rebuilding isolated contact systems.

## Current Development State

Hivra has two deliberately separate development lines:

- **Hivra 1.x** is the only maintained, tested, and releasable runtime. Current
  work is focused on integrity, reliable delivery, deterministic recovery,
  platform parity, and removal of proven architectural debt.
- **Hivra 2.0** is a design-and-proof program. It is currently inventorying
  capability owners, contracts, facts, projections, effects, and dependency
  edges. It does not introduce a second production runtime into 1.x.

The short current-stage board is
[Hivra Development Control](docs/development-control.md). The detailed work
history and active remediation program remain in the
[Roadmap](docs/roadmap.md).

## Architecture

This repository implements the current Hivra 1.x runtime:

- **Core** — deterministic domain facts, transitions, replay, and projections;
  no platform or network I/O.
- **Engine** — domain use-case orchestration through explicit clock, randomness,
  and cryptographic contracts.
- **Adapters** — cryptography and transport implementations. Nostr is the
  currently mounted transport.
- **Platform** — FFI composition, secure key storage, and the WASM runtime.
- **Plugin Host** — capability-gated host APIs for external WASM drones.
- **Flutter App Shell** — local projection and explicit user-action surfaces
  for macOS and Android.

Chat, trading, staking, AI, and other user-facing features are drones, not Core. Core stays minimal: Capsule, Ledger, Invitations, Trust Layer, Pair Consensus, and the runtime contracts required for safe drone execution.

Transport adapters are not WASM drones. They are host-level system adapters that move signed capsule envelopes through external networks. WASM drones can request delivery through host APIs, but they do not get direct network, keychain, relay, or transport-session access.

### Repository Layout

- `core/` — deterministic Hivra domain.
- `engine/` — use-case orchestration over Core contracts.
- `adapters/` — transport and cryptographic adapter implementations.
- `platform/` — FFI, key storage, and WASM runtime composition.
- `flutter/` — application shell, projections, platform integration, and tests.
- `docs/` — canonical specification, architecture, roadmap, and checklists.
- `tools/review/` — deterministic architecture, dependency, documentation, and
  security gates.
- `tools/release/` — guarded macOS, Android, and GitHub release workflows.

Drone source packages are developed and released separately from the host
application. This repository owns the Capsule runtime, plugin host contracts,
installation boundary, and runtime integration; it must not absorb plugin
business logic back into the application.

### Compile-Time Dependency Contract

- `hivra-core` is dependency-free from engine/adapters/platform/UI crates.
- `hivra-engine` depends on `hivra-core`.
- `hivra-transport` is adapter-only and does **not** depend on `hivra-core` or `hivra-engine`.
- `hivra-ffi` is the boundary crate that composes `core + engine + adapters + keystore`.

### Consensus Execution Contract

- Pairwise consensus is computed on demand by a dedicated Consensus Processor.
- It is not continuously recomputed in UI/background flows.
- Trigger points: smart-contract precondition checks and explicit user-requested checks.
- Pair-scoped smart contracts execute only when participants derive and sign the same canonical consensus hash.

## Specification Documents

- [Product Axis](docs/product-axis.md)
- [Hivra Protocol Specification](docs/specification.md)
- [Hivra Conceptual Model](docs/hivra-conceptual-model.md)
- [Current Development Control](docs/development-control.md)
- [Engineering Roadmap](docs/roadmap.md)
- [Hivra 2.0 Architecture Blueprint](docs/architecture-v2-blueprint.md)
- [Docs Map](docs/README.md)

Authority order matters: the 1.x specification is normative for current
runtime behavior; the 2.0 blueprint is design-only until a migration unit is
explicitly approved.

## Identity and Key Derivation

- One capsule is backed by one recovery seed phrase (BIP39).
- The canonical capsule root identity is `ed25519`.
- Transport keys are derived deterministically from the same seed using domain-separated labels.
- Capsule identity and transport identity are different layers.
- Different transports may use different curves while sharing the same recovery phrase:
  - Nostr: secp256k1
  - Other adapters (for example Matrix): ed25519
- UI-facing capsule identity should represent the capsule root identity layer, not a transport-specific public key.
- Recovery requires only the seed phrase and derivation version compatibility.

## Capsule Lifecycle in UI

### First Launch States

- **No capsules**: the user creates the first capsule (`Proto` or `Genesis`).
- **Existing capsules**: the app opens the capsule selection screen.

### Multi-Capsule Management

Users can own multiple independent capsules.

- Capsules are independent (`seed` and `ledger` are isolated per capsule).
- Capsule switching is available at any time.
- New capsule creation is available from the capsule selection UI.

### Capsule Storage

- Each capsule has its own seed stored in platform secure storage.
- On macOS, per-capsule seeds are persisted in Keychain, while the currently
  active runtime seed is process-local memory state. Capsule switching MUST NOT
  rewrite a global "active seed" Keychain entry.
- Capsule metadata is stored under a separate key: `capsule_metadata`.

### Capsule Selection Screen

Shown on app launch when at least one capsule exists.

- Displays capsule public key.
- Displays active network.
- Displays starter count.
- Allows creating a new capsule.

### Switching Capsules

- On selection, the app loads the selected capsule seed and ledger.
- The previously active capsule is unloaded from memory.
- Runtime diagnostics are available through Capsule Analyst in Settings.
  Capsule Analyst is local-only and must not upload seed, ledger, or
  transport material.

## Building

### Prerequisites

- A current Rust toolchain compatible with the workspace `edition = "2021"`.
- Flutter with Dart `>=3.7.0 <4.0.0`.
- Android SDK (API 36) for Android builds
- Xcode 15+ for macOS builds

The manifests and platform tooling are the version authority; this README does
not pin a second, easily stale SDK matrix.

### Development Verification

```bash
# From the repository root
cargo test --workspace
tools/review/review_all.sh

cd flutter
flutter analyze
flutter test
```

For a focused local macOS build:

```bash
cd flutter
flutter build macos --release
```

Android and macOS are both supported release targets. Platform behavior must be
smoke-tested from fresh release artifacts before publication; a successful
debug run is not release evidence.

### Guarded Releases

Do not publish artifacts with raw Flutter or GitHub commands. The approved
workflow is owned by `tools/release/`:

```bash
tools/release/macos_release.sh --version <tag> --channel <test|public>
tools/release/android_release.sh --version <tag> --channel <test|public>
tools/release/publish_github_release.sh --version <tag> --channel <test|public>
```

These commands enforce version rules, automated preflight, artifact checks,
manual platform sign-off, and checksum publication. See the release checklists
under `docs/checklists/` before choosing a tag.

### Cleanup Local Build Artifacts

Before release packaging, you can clear local build caches and stale dist artifacts:

```bash
tools/cleanup/clean_local_artifacts.sh
```

Safe preview without deletion:

```bash
tools/cleanup/clean_local_artifacts.sh --dry-run
```

## License

MIT
