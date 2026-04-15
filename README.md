# Hivra Protocol

Hivra is an infrastructure for relationships, not a social network. No likes, no followers, no algorithmic feeds. Only you, your 5 unique starters, and people you trust.

Hivra is best understood as a personal capsule computer:

- not a global shared world computer
- not an account inside someone else's network
- but a local-first runtime for your own capsule state, history, recovery, and relationships

The capsule is the center of truth. Transport adapters move messages, but they do not define identity or replace local truth.

## Architecture

This repository implements Hivra v1.0.0 specification:

- **Core** — Pure domain logic (deterministic, no I/O, no crypto knowledge)
- **Engine** — Orchestration layer (time, RNG, crypto provider)
- **Transport** — Abstract transport layer (Nostr, Matrix, BLE)
- **Platform** — OS-specific implementations (SecureKeyStore)
- **Flutter UI** — Cross-platform interface

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

- [Hivra Protocol Specification](docs/specification.md)
- [Hivra Conceptual Model](docs/hivra-conceptual-model.md)
- [Docs Map](docs/README.md)

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

- Each capsule has its own seed stored in Keychain.
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

## Building

### Prerequisites

- Rust 1.75+
- Flutter 3.22+
- Android SDK (API 36) for Android builds
- Xcode 15+ for macOS builds

### Build

```bash
# Build all Rust crates
cargo build --release

# Build Flutter for current dev target (macOS)
cd flutter
flutter build macos
```

For current local development, use macOS target only (`flutter run -d macos`).

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
