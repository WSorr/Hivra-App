# Hivra Protocol v1.0 — Full Specification

Version: 1.0
Date: 2026-03-16

Hive Integrated Value & Relationship Architecture

---

## 0. Preamble

This document is the single source of truth for the architecture and implementation of the Hivra protocol. It defines a strict layered architecture, domain invariants, data formats, and participant roles.

Hivra is a local-first personal runtime for user-owned Capsules. A Capsule can operate independently, keep its own ledger, run WASM drones, and optionally establish trusted links with other Capsules through invitations.

These trusted links form a **Core Trust Layer**, not a social network. They are internal ledger facts used for safe capsule-to-capsule interaction and pair-scoped consensus. There is no global discovery, no people search, no public social graph, and no global network statistics.

Chat, trading, staking, AI, and other user-facing capabilities are drones/plugins, not Core. Core remains minimal: Capsule, Ledger, Invitations, Trust Layer facts, Pair Consensus inputs, and deterministic domain transitions.

The key architectural rule in this revision is strict layer isolation: Core knows nothing about transport, cryptography, time, or RNG. All external dependencies are injected through the Engine.

### 0.1 Product Axis

All implementation and architecture changes MUST preserve the canonical Hivra
product axis defined in `product-axis.md`:

> A user-owned Capsule turns explicit intent and authenticated input into
> reproducible local truth through one deterministic capability path, while
> every external effect follows one durable, idempotent lifecycle.

Confirmed Core state follows the truth lane. Network, storage, crypto,
exchange, and provider work follows the effect lane. A production workflow MUST
NOT create a third path, a second capability owner, a second projection truth,
or a parallel effect lifecycle.

Implementation work MUST also follow the novelty-before-pattern protocol in
`docs/architecture-execution-discipline.md`: define the cross-module invariant
first, inspect existing seams, design the smallest new contract, then run
adversarial and regression passes. Existing patterns are compatibility
constraints, not default architecture for new behavior.

### 0.2 Person-First Runtime

Hivra defines a **Person-First Runtime (PFR)**. PFR is an architectural model in
which the primary durable execution context belongs to the person and survives
the installation, replacement, or removal of any individual application or
drone.

Within this model:

- `person` means the enduring architectural owner;
- `user` means a role assigned to that person within an application boundary;
- `Capsule` means the persistent, recoverable execution context of the PFR;
- applications and drones are capability consumers, not owners of Capsule
  identity, Ledger truth, cryptographic authority, recovery, or transport
  sessions.

PFR is not a second runtime layer, a new Core entity, or a separate execution
path. It names the architecture formed by the existing Capsule, Core
projection, capability, effect-lifecycle, adapter, secure-storage, and recovery
contracts. Operational state remains outside the Ledger unless this
specification defines it as a Core fact, and private keys remain inside their
declared secure cryptographic boundary.

### 0.3 Cryptographic Agility

The permanent invariant is:

> Domain identity, authority, and Capsule continuity MUST NOT depend on a
> specific cryptographic algorithm, public-key size, or signature size.
> Algorithms belong to crypto/platform adapters; protocol proofs are
> versioned, suite-tagged, and length-delimited.

`CapsuleId` is conceptually separate from any public key. A key authorizes a
Capsule under a versioned protocol rule; it is not the enduring domain identity
itself. The maintained 1.x runtime still uses fixed-size Ed25519 root keys and
signatures and, in several compatibility structures, aliases Capsule identity
to root-key bytes. That is registered compatibility debt, not the target 2.0
contract and not permission to introduce a second identity path in 1.x.

Future algorithm-neutral protocol values have this conceptual shape:

```text
KeyDescriptor {
  version,
  suite_id,
  key_id,
  key_bytes: length-delimited bytes
}

SignatureProof {
  version,
  suite_id,
  key_id,
  signature_bytes: length-delimited bytes
}
```

`suite_id` selects a reviewed cryptographic suite and role. `key_id` binds a
proof to one key descriptor without assuming that the key bytes are 32 bytes.
Unknown versions, suites, roles, malformed lengths, or unbound key IDs fail
closed.

Migration is controlled and hybrid, not an instantaneous replacement of
Ed25519:

1. An existing Capsule appends one migration checkpoint authorized by its
   currently active root key and bound to the exact accumulated Ledger head.
2. The checkpoint contains the new key descriptor and mutual binding proofs:
   the old key authorizes the new key, and the new key proves possession and
   binds itself to the same Capsule, role, checkpoint, and history commitment.
3. During the declared hybrid epoch, validation follows one canonical proof
   policy and requires the configured classical and post-quantum evidence. It
   MUST NOT fork into a second Core or Ledger path.
4. Existing Ledger events are never rewritten or re-signed. The checkpoint
   anchors the complete prior history and governs only subsequent proofs.
5. A later protocol version MAY permit new Capsules to use hybrid genesis, but
   only after deterministic genesis vectors, recovery, downgrade, and suite
   lifecycle rules are normative.

Root signing, transport signing, and transport encryption are distinct roles.
They may adopt suites on different schedules. Nostr remains a replaceable
transport adapter; its secp256k1 routing/signing identity MUST NOT become
`CapsuleId` or Capsule root authority.

Confidential transports require a future hybrid KEM envelope that combines the
current classical mechanism with a reviewed post-quantum KEM and binds both to
the same sender, recipient, protocol version, suite set, and ciphertext. This
is intended to reduce harvest-now/decrypt-later exposure. It is architecture
work only: the maintained 1.x runtime does not implement or claim
post-quantum confidentiality.

A future Capsule Effect Proof uses the same versioned `KeyDescriptor` and
`SignatureProof` model. It binds Capsule, capability, operation, payload or
result commitment, role, and verification context so an independent verifier
can validate Capsule authorization without trusting the provider receipt,
transport adapter, or Hivra process that produced the effect.

---

## 1. Philosophy and Fundamental Principles

### 1.1 Core Values

1. No global discovery — only manual add by public key.
2. Trusted links are built on real-world invitations, not search.
3. Starters are unique identifiers, not economic tokens. They cannot be transferred.
4. Transport is an abstraction layer. Nostr now, but Matrix, BLE, and others can be added.
5. Reputation is local only (for relay scoring).
6. Trust is more important than convenience — the user controls all critical actions.

### 1.2 Determinism Principles

The system guarantees:

- Same input → same output (binary).
- Full state recovery from the ledger.
- No hidden sources of non-determinism.
- Full layer isolation.

---

## 2. Layered Architecture (Dependency Rule)

### 2.1 Dependency Rule

Dependencies are allowed only downward. Inner layers do not know about outer layers.

```
UI (Flutter)
    ↓
Transport Adapters (Nostr, Matrix, BLE...)
    ↓
Engine (orchestrator, time, RNG, cryptography)
    ↓
Core (domain logic, agnostic)
```

Forbidden:

- Core does not know about Engine.
- Core does not know about Transport.
- Engine does not know about UI.
- Transport does not know about Core.
- Violating this rule is an architectural error.

Crate-level dependency contract (enforced by review scripts):

- `hivra-core` has no dependency on engine/adapters/platform/UI crates.
- `hivra-engine` depends on `hivra-core` and does not depend on transport/ffi/UI crates.
- `hivra-transport` does not depend on `hivra-core`, `hivra-engine`, or `hivra-ffi`.
- `hivra-ffi` is the boundary crate that composes `core + engine + adapters + keystore`.

### 2.2 Separation of Responsibilities

Layer | Responsible For | Knows Nothing About
--- | --- | ---
UI | Rendering, user input | Domain logic, transport
Transport | Byte transfer, network adaptation | Core entities/invariants, business meaning, cryptography policy
Engine | Orchestration, dependency injection, signature validation | Detailed event structure (only bytes)
Core | Domain invariants, events, projections | Time, RNG, I/O, JSON, cryptography

### 2.3 Structural Minimality Contract (Anti-Sprawl)

To prevent architecture drift into duplicated "modules for modules", implementation MUST stay within this explicit skeleton:

1. UI Projection Layer (screens/widgets, user intent dispatch)
2. Application Use-Case Layer (intent orchestration, policy, error mapping)
3. Domain Core Layer (invariants, event transitions, deterministic logic)
4. Ledger Layer (append-only storage + projection reconstruction)
5. Transport Layer (providers/adapters only)
6. Plugin Host Layer (WASM runtime with capability gates)

Rules:

- A new module MUST map to one of these six layers.
- A domain fact, effect lifecycle, or projection rule MUST have exactly one
  owner module. A new module MUST replace or narrow the prior owner; it MUST
  NOT coexist as a parallel orchestration path.
- UI MUST NOT contain domain orchestration logic.
- Application MUST treat ledger-derived projection as the only domain truth.
- Plugin host MUST extend capabilities without changing dependency direction.
- Every effect path MUST have one capsule binding, one queue/lifecycle owner,
  and one result-application route. Timeout, retry, refresh, or screen changes
  MUST NOT create a competing route.

### 2.4 Flutter Boundary Direction

Inside Flutter/application code, dependencies are also strictly downward:

```
Screens/Widgets
    ↓
Application Use Cases / Facades
    ↓
FFI Boundary Services
    ↓
Rust Core + Engine + Transport
```

Forbidden inside Flutter:

- direct FFI calls from widgets
- duplicated projection logic in multiple screens
- cross-screen orchestration coupling
- feature-graph construction inside generic capsule/runtime services
- lateral concrete-service dependencies when a lower-layer contract exists

Composition rule: concrete feature graphs are assembled only at the application
composition root or a feature-module facade. Generic runtime services expose
neutral capsule/runtime primitives and MUST NOT become feature service locators.

---

## 3. Core (Domain Layer)

### 3.1 General Rules

Core is the innermost layer. It:

- Contains entities, invariants, events, and state transition rules.
- Performs only deterministic computation.
- Does not use system time, RNG, or I/O.
- Does not know JSON or any serialization formats except binary.
- Does not know cryptography — keys and signatures are just bytes.

Core operates only on:

- Bytes.
- Pure data structures.
- Input parameters passed from Engine.

### 3.2 Core Primitives

The following types describe the maintained 1.x wire and in-memory
compatibility boundary. Their fixed sizes MUST NOT be treated as the target
2.0 identity/proof contract:

```rust
/// Public key — 32 bytes.
/// Core DOES NOT KNOW which curve is used (secp256k1, ed25519...).
pub struct PubKey([u8; 32]);

/// Private key — 32 bytes. NEVER passed into Core.
pub struct PrivKey([u8; 32]);

/// Signature — 64 bytes. Core does not verify signatures.
pub struct Signature([u8; 64]);

/// Starter ID — 32 bytes.
pub struct StarterId([u8; 32]);
```

### 3.2.1 Capsule Root Identity

Each capsule has one canonical root identity.

- The maintained 1.x root-signing suite is `ed25519`; this is a compatibility
  suite, not the permanent definition of `CapsuleId`.
- This identity is transport-agnostic.
- Transport-specific keys MUST be derived from the same recovery seed using explicit domain separation.
- A transport key MUST NOT replace the canonical capsule identity in the architecture.

Examples:

- capsule root identity: `ed25519`
- Nostr transport identity: derived `secp256k1`
- Matrix transport identity: derived `ed25519` using a transport-specific derivation label

UI, documentation, and cross-capsule semantics should refer to capsule identity at the root-identity layer unless a transport-specific key is explicitly required.

For 2.0 contract design, `CapsuleId` remains stable while one or more
role-specific `KeyDescriptor` values authorize it. No production 1.x code may
pretend that this target model is already implemented.

### 3.3 Core Entities

#### 3.3.1 Capsule

Capsule is the persistent, recoverable execution context of a person in Hivra.
It is not an account owned by an application. Its canonical identity and
Ledger continuity remain stable across replaceable application, drone, and
transport integrations.

```rust
struct Capsule {
    pubkey: PubKey,           // 32 bytes, identifier
    network: Network,          // Neste in the supported 1.x runtime
    ledger: Ledger,            // append-only event log
    // Slots are a projection from the ledger, not stored directly
}
```

Capsule birth mode and runtime role are independent concepts:

- `Genesis` birth creates the initial five local starters.
- `Proto` birth starts without local starters and gains them through accepted
  invitation lineage.
- `Leaf` / future `Relay` describe runtime behavior and MUST NOT determine
  starter birth.

The persisted 1.x `CapsuleCreated.capsule_type` byte is a legacy field currently
used as the Genesis/Proto birth marker despite the Rust enum names
`Relay`/`Leaf`. This naming collision is implementation debt, not protocol
meaning. It MUST be separated into explicit `birth_mode` and `runtime_role`
contracts before Relay is implemented.

#### 3.3.2 Starter

Starter is a unique non-fungible identifier.

```rust
struct Starter {
    id: StarterId,             // 32 bytes
    owner: PubKey,             // creator (immutable)
    kind: StarterKind,          // Juice, Spark, Seed, Pulse, Kick
    network: Network,
    origin_invitation: Option<[u8; 32]>, // invitation origin
    created_at: Timestamp,      // creation time (from Engine)
    state: StarterState,        // Active | Burned
}
```

Rules:

- Starter cannot be transferred to another owner.
- Type never changes.
- Created only via StarterCreated.
- Burned only via StarterBurned.

#### 3.3.3 Slot

Slot is a position (0..4) for your starter.

- Slot holds only your starter.
- Type is not bound to position (Juice can be in any slot).
- Slot can be locked (during invitation).

Lock is derived from the ledger:

```rust
fn is_locked(starter_id: StarterId, ledger: &Ledger) -> bool {
    // Locked if there is InvitationSent and no finalizing event
}
```

#### 3.3.4 Ledger

Signed event protocol v4:

- Every Core ledger event is signed by a capsule root key.
- Nostr `npub` is a transport routing identity, not a Core event signer.
- Transported Core events carry an explicit root-signature proof. A Core
  message without this proof is not eligible for ledger projection.
- Ledger import verifies both the hash chain and every Ed25519 event signature
  before replacing runtime state.
- Protocol v3 and earlier unsigned test ledgers are intentionally incompatible
  with protocol v4. Before the first stable release, those test capsules must
  be recreated or have their trusted links re-established from the root phrase.
- New protocol v4 runtime state MUST NOT be initialized with legacy Nostr owner
  identity. Nostr keys are transport keys only.

Ledger is the single source of truth for Core domain facts and their
deterministic projections. It is not the storage authority for operational or
private application state such as transport retry records, contact-card
routing caches, pair-attestation evidence, plugin installation records, drone
journals, or credentials.

- Core domain state is recovered by replaying ledger events.
- Starter-slot lifecycle projection is owned exclusively by Core. UI and
  application services MUST consume the version-matched Core capsule-state
  projection and MUST NOT independently replay starter lifecycle events to
  derive active slots.
- Inactive-capsule summaries MAY cache that Core capsule-state projection next
  to the ledger. A cached projection is valid only when both its event version
  and ledger hash match the stored ledger; otherwise starter state fails closed
  until Core refreshes the snapshot.
- Events are append-only; deletion or overwrite is forbidden.
- Protocol v4 signatures authenticate the canonical event identity
  `SHA256(version || kind || payload)` under `event.signer`.
- `timestamp` and ledger position are not part of that signed identity in v4.
- `last_hash` is a deterministic 64-bit replay checksum, not a cryptographic
  history commitment. Cryptographic sequence/metadata commitment is an active
  protocol-hardening debt and MUST NOT be claimed by UI or release material.
- The approved v5 replacement contract is
  `docs/architecture/continuous-ledger-protocol-v5.md`. Until that protocol is
  implemented, v4 remains the normative runtime format and legacy imports MUST
  retain their stated security limitations.

### 3.1.1 Canonical Domain Projection Contract

Core MUST be the sole interpreter of normative domain-event lifecycle
semantics. Replaying the same valid ledger through the same protocol version
MUST produce one canonical domain state. Application code, UI, consensus, and
drones MUST NOT independently walk raw events to decide whether a starter,
invitation, relationship, or other Core fact is currently active.

Core exposes scoped read models derived from that one replay result:

- `CurrentView` contains only effective current state after terminal and
  superseding events. Normal user-facing screens consume this view and do not
  surface obsolete injuries after recovery unless the user opens history.
- `PairView` contains only current facts and immutable lineage required for the
  selected pair. Pair consensus hashes this view; unrelated Capsule events and
  superseded pair episodes do not enter the active commitment.
- `HistoryView` contains the complete typed chronology for one explicitly
  selected subject and is used only for inspection, explanation, and audit.

These are views of one canonical state machine, not three event interpreters.
If a required view is missing, the lower Core projection contract MUST be
extended; Flutter or a drone MUST NOT introduce a temporary replay policy.
Inspector-only raw decoding MAY display evidence, but MUST NOT authorize an
action, compute consensus, or feed current domain state.

The current Core/FFI PairView contract is `hivra.pair_view` version `1`. It
contains pair identities, deduplicated active relationship facts, finalized
invitation count for diagnostics, and deterministic pair blockers. The host
maps this typed view into pair snapshot schema v3 and owns hashing, signatures,
attestation exchange, and verification; it does not replay domain events.

The current Core/FFI HistoryView contract is `hivra.history_view` version `1`.
It accepts one explicit invitation, starter, or relationship subject and
returns the complete matching typed chronology in ledger order. Core owns
payload validation, subject aliases, event membership, and summary facts. The
host may localize time and prose and hash an advisory projection, but it does
not inspect raw event kinds, payload layouts, or lifecycle offsets.

All persisted projection caches are disposable materialized views. They MUST
be bound to ledger identity, protocol version, event version, and ledger hash;
a missing or mismatched binding fails closed and triggers Core replay. Cached
projection data MUST never be imported as a domain fact or used to mutate the
ledger.

#### 3.3.5 Relationship

Relationship is a Core Trust Layer fact of mutual recognition between two capsules.

It is not a social-network feature, not a discovery record, and not a public graph edge. It is ledger-derived internal state used by Pair Consensus and by drones that need trusted interaction with another Capsule.

```rust
struct Relationship {
    peer: PubKey,               // relationship peer
    own_starter_id: StarterId,   // own starter
    peer_starter_id: StarterId,  // peer starter
    kind: StarterKind,           // type (Juice/Spark/...)
    established_at: Timestamp,
}
```

Relationship is active if:

- There is RelationshipEstablished.
- There is no local RelationshipBroken.

### 3.6 Multiple Capsule Management

Users can have multiple independent capsules.

Storage:

- Each capsule has its own seed in platform secure storage.
- On macOS, canonical mutable runtime data is stored under
  `~/Library/Application Support/Hivra`. This includes capsule ledgers and
  index, contact cards, plugin runtime/catalog data, delivery state, logs, and
  disposable caches. Runtime state MUST NOT use `~/Documents/Hivra` as its
  canonical location because cloud synchronization may offload or partially
  hydrate user documents.
- `~/Documents/Hivra` is a user-visible boundary for explicit backups and
  exports only. It is not a runtime authority and MUST NOT be scanned on every
  launch to recreate missing canonical state.
- A build that moves canonical storage MUST perform a one-time copy, verify the
  copied bytes, and persist a migration marker before using the new location.
  A migration conflict or unavailable source fails closed. The old source MAY
  remain as a rollback copy, but MUST NOT be read again as runtime truth after
  migration succeeds.
- On macOS, per-capsule seeds are stored in Keychain. Runtime activation uses a
  process-local active seed cache; selecting or bootstrapping a capsule MUST NOT
  rewrite a global active-seed Keychain pointer or persist a second native copy
  of the seed. The legacy native Keychain layout is read-only recovery input;
  Flutter secure storage is the single per-capsule persistence authority.
- Recovery seeds MUST NOT be persisted in plaintext files. If platform secure
  storage is unavailable, seed persistence fails closed.
- User-visible Capsule backup exports MUST use the versioned authenticated
  `hivra.capsule_backup` v2 envelope. The maintained 1.x suite derives a
  domain-separated export key from the Capsule seed with HKDF-SHA256 and a
  fresh 32-byte salt, then encrypts the complete v1 recovery payload with
  AES-256-GCM and a fresh 12-byte nonce. The schema, version, and suite id are
  authenticated associated data; Ledger bytes and Capsule metadata remain
  inside the ciphertext.
- `CapsuleBackupCodec` is the sole backup wire-format owner and
  `CapsulePersistenceService` is the sole backup filesystem writer. Screens
  MUST NOT serialize, encrypt, decrypt, or persist backup payloads directly.
- An envelope recognized as v2 MUST fail closed on an unsupported suite,
  malformed field, wrong seed, or authentication failure. It MUST NOT fall
  back to v1 or raw-Ledger parsing after v2 recognition.
- Plaintext `capsule-backup.v1.json` remains an internal per-Capsule recovery
  snapshot and read-only import compatibility format. New user-visible exports
  MUST NOT emit v1 or raw Ledger JSON.
- Temporary files created for a system share sheet MUST have one lifecycle
  owner and MUST be deleted in `finally` after success, cancellation, export
  failure, or share failure. A temporary share path MUST NOT be retained as a
  user-visible saved-backup location.
- Android OS Auto Backup, cloud restore, and device-to-device extraction MUST
  NOT copy Hivra private runtime state. The application manifest and both
  legacy and Android 12+ extraction rules MUST exclude every private storage
  domain. An explicit authenticated `hivra.capsule_backup` v2 envelope plus
  matching seed is the only supported cross-install Capsule recovery path.
  Android secure storage MUST derive its filesystem boundary from the active
  process `Context.filesDir`; adapters MUST NOT assume owner user `0`.
- Legacy plaintext seed files MAY be consumed only for one-time migration:
  every valid entry is written to secure storage, verified by read-back, and
  the plaintext file is deleted before normal use continues.
- Capsule metadata stored under "capsule_metadata".

Selector screen:

- Shown on launch if at least one capsule exists.
- Displays public key, network, starter count.
- Allows creating a new capsule.
- Missing or unreadable canonical storage MUST NOT be interpreted as a new
  installation. The selector shows an explicit recovery state with Retry,
  Import Backup, Recover from Seed, and a separately de-emphasized Create New
  Capsule action.
- Seed recovery restores Capsule identity. Ledger history requires a verified
  backup or independently available transport history; the UI MUST state this
  distinction before recovery.
- On macOS, Settings MUST expose an `Open local data folder` action so the
  canonical runtime can be inspected without requiring users to reveal or
  manually navigate the hidden `~/Library` directory.

Switching:

- Selecting a capsule loads its seed and ledger.
- Previous capsule is unloaded from memory.
- Capsule selection MUST preserve the storage/runtime boundary:
  persistent per-capsule seed storage is a secure-storage concern, while active
  runtime seed selection is process-local and non-authoritative.

Diagnostics:

- All inference in Hivra MUST enter through the single host-owned Capsule AI
  Runtime contract defined by `architecture/capsule-ai-runtime.md`.
- A screen, drone, or feature service MUST NOT construct a provider adapter,
  read an inference credential, or own a parallel AI scheduler directly.
- Capsule AI Runtime MUST remain outside Core. It MUST NOT append ledger facts,
  mutate Capsule state, execute effects, approve operations, or grant host
  capabilities.
- Inference requests MUST preserve active Capsule and requesting-capability
  scope through disclosure, provider execution, validation, and completion.
- WASM drones MAY request bounded inference only through a declared host
  capability and drone-owned proposal schema. They MUST NOT receive provider
  credentials or generic AI tools.
- The configured provider MAY be unlocked into host process memory by an
  explicit user action. A locked automatic cycle MUST stop before inference,
  MUST NOT open an operating-system credential prompt, and MUST NOT consume its
  pending input checkpoint.
- Closing the application MUST clear the process-memory AI lease. Hivra 1.x
  does not promise app-closed AI execution.
- During incremental 1.x convergence, the existing named Analyst, Developer,
  history-advisor, and Moltbook AI services are legacy implementation paths.
  They MUST NOT be copied or extended with another provider/session/scheduler
  path. A change that touches their provider dispatch MUST migrate that path to
  Capsule AI Runtime and delete or seal the replaced entrypoint.

- Capsule Analyst is the canonical user-facing local diagnostic surface.
- Capsule Analyst MAY summarize bootstrap state, filesystem traces, ledger
  projection, invitations, relationships, outbox, consensus, and plugin state.
- Capsule Analyst MUST be deterministic for the same local files and runtime
  inputs.
- Capsule Analyst MUST NOT upload recovery seed, ledger contents, transport
  secrets, or plugin credentials to any AI/provider service.
- Capsule Analyst MAY provide an optional scoped AI analysis over a user-selected,
  redacted diagnostic snapshot.
- Scoped AI chat MUST show an outbound preview before provider submission,
  including selected sections, payload size, and snapshot hash.
- Scoped AI chat MUST store provider API keys only in platform secure storage
  and MUST NOT create plaintext fallback files.
- Scoped AI chat output is advisory only. It MUST NOT mutate ledger, runtime,
  plugin registry, transport outbox, contact cards, or capsule credentials.
- Scoped AI chat MUST NOT receive repository access in this phase. Repository
  inspection belongs to a later explicit developer-mode boundary.
- Plugin Auditor MAY inspect installed plugin package metadata, declared
  capabilities, ABI, entry export, package kind, package size, and package
  digest.
- Plugin Auditor MUST be read-only: it MUST NOT mutate plugin registry,
  catalogs, package files, ledger, transport outbox, or credentials.
- Plugin Auditor MUST NOT grant capabilities. Unsupported or missing
  capabilities are findings, not authorization inputs.
- Developer Workspace Preview MAY scan explicit local repository paths supplied
  by the developer.
- Developer Workspace UI MUST be behind an explicit Developer Mode boundary
  that is disabled by default and visually distinct from user-facing Capsule
  Diagnostics.
- Developer Workspace Preview MUST be read-only and MUST expose only
  allowlisted file paths, file sizes, hashes, skip counts, and denylist
  findings.
- Developer Workspace Preview MUST skip secret-like files, build/cache
  directories, symlinks, binaries, oversized files, and unknown top-level paths.
- Developer Workspace Preview MUST NOT upload source contents, clone remote
  repositories, execute scripts/hooks, or mutate repositories.
- Developer Workspace selected context MAY include contents of explicit
  user-selected allowlisted files after a fresh preview hash check.
- Developer Workspace selected context MUST reject files changed after preview
  and MUST label source/log/manifest contents as untrusted prompt input.
- Developer Workspace selected context MUST remain a local preview until a
  separate explicit provider submission step is implemented.
- Hivra Engineer Advisory Ask MAY send a selected developer context, redacted
  capsule summary, and user question to an AI provider after outbound preview.
- Hivra Engineer output is advisory only. It MUST NOT write files, apply
  patches, run scripts, commit, push, tag, release, mutate ledger, or mutate
  plugin registry.
- Hivra Engineer payload MUST include no-mutation constraints and MUST treat
  selected source/log/manifest text as untrusted data.
- Developer Remote Repository Cache MAY clone explicit public repository URLs
  only into a Hivra-controlled developer cache. It MUST reject SSH/local/file
  URLs, disable git prompts/hooks/submodule recursion, record the resolved
  commit, and mark unpinned or mutable refs as dangerous.
- Remote repository cache contents MUST remain developer-selected evidence.
  AI providers and plugins MUST NOT receive broad repository/network access
  through this cache.
- Plugin Auditor MAY inspect installed plugin package metadata and explicit
  selected plugin source snippets. It is read-only and MUST NOT install
  plugins, grant capabilities, mutate registry, or treat source text as
  trusted instructions.
- Plugin Scaffolder Draft Mode MAY create draft plugin skeleton files only
  inside an explicit `hivra-plugins` repository boundary. It MUST NOT build,
  install, catalog, sign, commit, push, tag, release, or overwrite existing
  drafts.
- Patch Proposal Mode MAY parse and preview AI-proposed unified diffs. It MUST
  NOT apply patches, write files, run scripts, commit, push, tag, or release.
- AI Review Gate Integration MUST mark advisory, patch, plugin audit, and
  release-readiness outputs as unverified until the user runs the required
  Hivra gates. AI output MUST NOT override review gates, release gates, or
  manual smoke.
- Every AI-enabled drone or external capability MUST follow
  `docs/architecture/ai-proposal-boundary.md`: inference produces untrusted
  bounded proposals only; deterministic capability policy remains executable
  without AI authority; external writes use the existing durable effect
  lifecycle.
- Inference output MUST NOT select capabilities, adapter origins/endpoints,
  credentials, operation ids, approval states, retry states, or receipts.
- Prompt instructions are defense in depth only. Exact schemas, dependency
  isolation, capability-scoped ports, deterministic policy, and effect
  reconciliation are the mandatory enforcement boundary.

---

## 4. Engine (Orchestrator)

### 4.1 Role of Engine

Engine is the single orchestration point. It:

- Injects dependencies (time, RNG, cryptography).
- Manages TimeSource and RandomSource.
- Calls CryptoProvider.
- Manages transport.
- Contains no domain invariants.

### 4.2 External Dependency Interfaces

```rust
pub trait TimeSource {
    fn now(&self) -> Timestamp;
}

pub trait RandomSource {
    fn fill_bytes(&self, buf: &mut [u8]);
}

pub trait CryptoProvider {
    /// Verify signature
    fn verify(&self, msg: &[u8], pubkey: &[u8; 32], sig: &[u8; 64]) -> Result<(), Error>;

    /// Sign message
    fn sign(&self, msg: &[u8], privkey: &[u8; 32]) -> Result<[u8; 64], Error>;

    /// (Optional) ECDH for encryption
    fn ecdh(&self, privkey: &[u8; 32], pubkey: &[u8; 32]) -> Result<[u8; 32], Error>;
}
```

### 4.3 Incoming Event Validation

```rust
fn validate_incoming_event(
    &self,
    raw_bytes: &[u8],
    pubkey: &PubKey,
    signature: &Signature,
) -> Result<ValidatedEvent, Error> {
    // 1. Crypto verification (CryptoProvider)
    self.crypto.verify(raw_bytes, pubkey.as_bytes(), signature.as_bytes())?;

    // 2. Deserialize into domain event (binary format)
    let event: DomainEvent = bincode::deserialize(raw_bytes)?;

    // 3. Structural validation (domain rules)
    event.validate_structure()?;

    Ok(ValidatedEvent::from(event))
}
```

---

## 5. Transport Layer

### 5.1 Principles

- Transport only transfers bytes.
- Does not interpret payload.
- Does not perform business logic.
- Does not generate time.
- Does not create keys.

### 5.2 Supported Transports

- Nostr (built-in, secp256k1)
- Matrix (planned host adapter, ed25519)
- BLE (planned host adapter)
- Local network (planned host adapter)

Each transport provides:

1. Transport implementation (send/receive bytes).
2. CryptoProvider implementation (for its curve).

Transport adapters are host-level system adapters, not WASM drones. A drone can request delivery through the host boundary, but it MUST NOT receive direct network, keychain, relay, or transport-session access. This keeps effectful delivery below the application boundary while preserving deterministic plugin execution.

### 5.2.1 Durable Delivery Outbox

Transport delivery MAY use a capsule-scoped durable outbox file to retry
effectful sends across screen switches, restarts, relay timeouts, and transient
network failures.

In v1, this file is a **delivery recovery index** over engine-owned pending
events, not an independent event journal. A fully reliable event queue requires
a stable domain-event identifier, recipient, payload digest, and matching
per-event adapter receipt; it MUST NOT be claimed before those fields exist.

Mandatory constraints:

1. The outbox is not ledger truth.
2. The outbox MUST live under the capsule storage boundary and be deleted with
   that capsule.
3. The outbox MAY track retry intent, attempt counters, backoff, and last
   transport error.
4. The outbox MUST NOT create invitation, relationship, consensus, or drone
   state by itself.
5. UI projections MUST still be rebuilt from ledger events.
6. Delivered/terminal domain state MUST be derived from ledger append and
   replay policy, not from an outbox item status.
7. Retry timing, receipt reconciliation, and capsule-scoped pump lifetime MUST
   have one application-level owner. Screens, invitation use-cases, and drones
   MUST NOT each create independent retry loops.

Transport adapters MAY return adapter-level delivery receipts. A receipt means
only that the adapter accepted or published a signed envelope (for example, a
relay accepted a Nostr event). It MUST NOT be interpreted as proof that the peer
capsule received, validated, or appended the domain event. Peer state is
confirmed only by ledger events and deterministic replay/projection policy.

### 5.2.2 Transport Health Policy

All host receive paths share one application-level, capsule-scoped transport
health policy above transport adapters and below UI. Invitations, relationship
notifications, chat, trading signals, and pair attestations MUST use this one
decision surface; relationship notifications remain part of the canonical
domain-event receive route rather than introducing a second worker.

Consecutive transport timeouts MAY increase a bounded cooldown that suppresses
passive polling. One explicit user action MAY bypass the current cooldown for
one receive attempt; it MUST NOT disable cooldown globally or turn a screen
into an independent retry loop. A successful transport result clears the
degraded state deterministically. UI MAY project the capsule-scoped degraded
status and remaining cooldown, but Core, Ledger projection, relationship truth,
and pair consensus MUST NOT read transport-health state as authority.

### 5.2.3 WASM Plugin Host Contract

WASM plugin execution is allowed only through a host boundary with explicit capabilities.

Mandatory constraints:

1. Plugin runtime is sandboxed.
2. Plugin registry/storage is isolated from capsule ledger storage.
3. Plugins MUST NOT append ledger events directly.
4. Plugins MUST NOT bypass Engine validation or Core invariants.
5. Pair-scoped plugin execution MUST be blocked when consensus guard is not signable.
6. Plugin host inputs/outputs MUST be deterministic for identical inputs.
7. Current external packages use semantic ABI `hivra_host_abi_v2` with the
   exact exports `hivra_alloc_v1`, `hivra_evaluate_v1`, and
   `hivra_dealloc_v1`; the contract version and export suffix do not imply ABI
   v1.
8. The runtime rejects imports and enforces package, module, archive, input,
   output, and fuel bounds before accepting semantic output.
9. Plugin-owned deterministic semantics execute in WASM. Host fallback is a
   compatibility path only where explicitly allowed and MUST NOT mirror or
   replace semantics for contracts that require an external package.

### 5.2.3 Identity Separation Rule

Transport adapters operate on transport-specific keys only.

They MUST NOT redefine or replace the canonical capsule root identity.

The existence of a Nostr public key, Matrix public key, or any other transport
key does not change Capsule domain identity or root authority. In maintained
1.x, root authority uses Ed25519. In the target agile contract, `CapsuleId` is
independent of every transport key and root-signing suite.

### 5.3 Unified Delivery Envelope

Transport moves one stable `DeliveryEnvelope v1` and returns one
`DeliveryReceipt`. It is not a chat model and it contains no
invitation-, relationship-, consensus- or drone-specific fields.

`kind` selects the receiving domain protocol. `payload` is opaque to the
transport adapter. `correlation_id` is a generic request/reply key; an
invitation may use its invitation id there, but that does not make it a
transport concept. Domain validation, replay policy and ledger projection
remain owned by the receiving Core module or WASM drone.

```rust
struct DeliveryEnvelope {
    schema_version: u16,
    from: PubKey,
    to: PubKey,
    kind: u32,              // receiving domain protocol
    payload: Vec<u8>,       // opaque domain bytes
    timestamp: u64,
    correlation_id: Option<[u8; 32]>,
    domain_event: Option<DomainEventProof>, // only for signed Core facts
}
```

The only shared delivery DTOs are `DeliveryEnvelope` and `DeliveryReceipt`.
No pass-through DTO may be added merely to mirror a domain payload across
Core, adapters, host and drone layers.

The Flutter delivery outbox is a recovery index, not a second domain queue.
Every retryable obligation MUST be bound to one valid immutable
`delivery_reference`, and adapter publication evidence MUST carry the exact
matching `correlation_id`. Delivery outbox schema v5 retains any pending or
legacy retry-exhausted aggregate record without that reference as explicit
`quarantined` diagnostic evidence. Quarantined records are never due, never
bind receipts, and MUST NOT trigger a ledger-wide reconstruction or batch
replay. This migration changes only recovery eligibility; Ledger/Core truth is
not rewritten.

Before a decoded envelope reaches any receiving domain, one transport-neutral
ingress guard MUST enforce:

- `schema_version == 1`;
- `to` equals the active transport endpoint that authenticated/decrypted the
  envelope;
- opaque `payload` length is at most 262144 bytes.

The mounted adapter MUST authenticate its wire signer against envelope `from`
before this common guard runs. A deterministic malformed or rejected wire
event MUST participate in adapter event-id deduplication so an overlapping
receive cursor cannot make the same hostile event consume work forever.

Rate limiting MUST NOT silently discard a valid authenticated envelope after a
relay cursor has advanced past it. A future sender-class rate limit therefore
requires a bounded durable quarantine/deferred-inbox contract before it can be
enabled in production.

One Capsule transport endpoint owns one mounted Nostr session regardless of
whether the caller requests a default or quick operation. Those profiles alter
only receive/publish time budgets; they MUST NOT create independent relay
pools, seen sets, or cursor maps. Before sender throttling can ship, receive
must additionally expose an acknowledged ingress handoff: an authenticated
envelope becomes cursor/seen-terminal only after canonical routing consumes it
or the Capsule-scoped quarantine durably accepts it. Full quarantine capacity
must produce visible backpressure, never silent eviction or a second receive
route.

### 5.4 Nostr Adapter

The maintained Nostr adapter carries the canonical `DeliveryEnvelope v1` in
one signed regular application event:

```text
DeliveryEnvelope v1 JSON
  -> NIP-44 v2 authenticated encryption for one recipient
  -> Nostr kind 9444 with exactly one matching `p` tag
  -> NIP-01 event id and Schnorr signature
```

The adapter MUST verify the outer NIP-01 event id and signature before
decryption. It MUST then authenticate the NIP-44 v2 payload, decode the same
transport-neutral `DeliveryEnvelope v1`, require `DeliveryEnvelope.from` to
equal the outer event signer, and apply the common ingress guard. The sole
recipient in the outer `p` tag, the NIP-44 ECDH recipient, and
`DeliveryEnvelope.to` MUST all identify the active local Nostr endpoint.

Wire-format downgrade is forbidden. Kind `9444` is decoded only as NIP-44 v2;
an authentication or version failure MUST fail closed and MUST NOT fall back to
NIP-04. New sends, retries, and outbox recovery MUST emit only kind `9444`.

For rolling compatibility with retained pre-migration relay history, the
maintained 1.x receiver MAY decode a signed kind `4` event through one isolated
read-only NIP-04 path. That path MUST apply the same exact-recipient,
outer-signature, sender-binding, envelope-schema, payload-size, replay, and
domain idempotence checks. It MUST NOT send NIP-04, translate an old event into
a new outbound event, or become a second transport route. Removal of this
read-only decoder requires an explicit compatibility decision after supported
peers no longer depend on pre-migration kind `4` history.

NIP-44 authenticates the confidential payload but does not provide forward
secrecy or post-compromise security. Hivra therefore treats it as the current
adapter wire envelope, not as a replacement for Capsule root signatures,
Ledger truth, domain replay protection, or delivery correlation.

NIP-44 is also not the target post-quantum confidentiality contract. A future
hybrid KEM envelope MUST be layered behind the same transport delivery port,
must bind the classical and post-quantum encapsulations to one recipient and
one ciphertext, and must not introduce a Nostr-specific Core path.

### 5.5 Acknowledged Ingress Handoff

The normative lifecycle is defined in
`docs/architecture/transport-delivery-lifecycle.md`. A transport adapter MUST
preserve stable adapter event identity and relay observation provenance until
the application-runtime ingress owner returns one resolve-once disposition.
An authenticated envelope becomes acknowledged/seen and cursor-terminal only
after canonical consumption or durable Capsule/network-scoped quarantine.

Retryable routing, persistence, timeout, panic, and capacity failures MUST
leave the affected relay cursor prefix uncommitted and MUST expose
backpressure. Adapter-invalid wire input may be permanently rejected only by
deterministic pre-domain validation. Cursor state is a fetch optimization, not
domain truth or receipt evidence.

Quarantined input re-enters the same canonical FFI ingress router with its
original adapter event id. It MUST NOT call a capability handler directly,
append Ledger facts, or create a second transport route. The maintained 1.x
runtime implements this repository and recovery behind the acknowledged
handoff. This does not authorize sender-rate limiting; policy activation
requires its own later pass and evidence.

The maintained 1.x Nostr implementation now mounts this handoff: one pending
batch retains event ids and relay provenance, the FFI router returns exact
dispositions, and relay cursor/seen commit occurs only during resolution.
Retry items remain pending and are presented again; a stale-session rebuild is
not permitted during resolution. The generic aggregate Nostr receive method is
sealed so it cannot bypass acknowledgement. The repository is mounted at this
same FFI boundary and does not add a sender limiter or new Core path.

### 5.6 Inbound Quarantine and Sender Policy

The normative repository and policy contract is defined in
`docs/architecture/transport-delivery-lifecycle.md`. One
`CapsuleInboundQuarantineRepository` owns encrypted retained envelopes under
the `(Capsule, network, transport endpoint)` scope. It is application/platform
state and MUST NOT reuse the delivery outbox, capability inboxes, Ledger, or an
adapter-local store.

Schema v1 is keyed by adapter event id and is bounded to `256` records,
`32 MiB` encrypted bytes, and `32` records per authenticated sender per scope.
Payload retention is `72 hours`; metadata-only terminal tombstones are bounded
to `30 days`, `1024` records, and `1 MiB`. Capacity, encryption, integrity,
index, or tombstone failure returns ingress `retry` and cannot evict another
retained envelope silently.

`SenderIngressPolicyV1` is charged only after authenticated sender/recipient
binding and neutral envelope guards. It uses a per-scope/per-sender bucket with
burst `8` and one refill per `15 seconds`. Stable event identity prevents
double charging. Relationship state, message kind, UI, relay, IP address, and
plugin identity provide no bypass. A throttled event becomes terminal only
after atomic quarantine commit; otherwise its relay prefix remains
unacknowledged.

The maintained v1 implementation persists bucket checkpoints and exact recent
charge evidence in the same authenticated-encrypted repository snapshot.
Evidence retention is `8 days`, with at most `65536` event ids and `8 MiB` per
scope and at most `40960` ids per sender. The repository supports at most
`1024` sender states. Any state/evidence capacity failure returns `retry`
instead of forgetting a charge, granting a bypass, or advancing a relay
cursor.

Quarantine recovery decrypts one eligible record and re-enters the same FFI
ingress router with the original event id. It cannot append Core directly or
create another scheduler/receive route. Storage encryption uses a distinct
Capsule-scoped platform key role; root, transport-signing, and transport-
encryption keys are not reused. The maintained implementation persists one
authenticated-encrypted snapshot plus independently authenticated envelope
ciphertexts through the platform crypto boundary, performs bounded recovery
before new relay fetch, and removes the Capsule-scoped subtree through the
existing deletion lifecycle. `SenderIngressPolicyV1` is activated at this same
FFI boundary. Pass-15 snapshots migrate without rewriting quarantine records;
restart preserves bucket/checkpoint and exact charge evidence; acknowledged
replay and quarantine recovery do not consume another permit. No second
transport, capability, scheduler, or Core path is introduced.

```rust
// NostrTransport uses NostrCryptoProvider (secp256k1)
pub struct NostrCryptoProvider {
    secp: Secp256k1,
}

impl CryptoProvider for NostrCryptoProvider {
    fn verify(&self, msg: &[u8], pubkey: &[u8; 32], sig: &[u8; 64]) -> Result<()> {
        // Interpret bytes as secp256k1 x-only pubkey
        let pubkey = XOnlyPublicKey::from_slice(pubkey)?;
        let sig = schnorr::Signature::from_slice(sig)?;
        self.secp.verify_schnorr(&sig, msg, &pubkey)?;
        Ok(())
    }
}
```

---

## 6. Cryptographic Layer (CryptoProvider)

### 6.1 Architectural Position

Crypto providers are implemented by role-specific crypto/platform adapters and
are orchestrated through Engine ports, not Core. Root signing, transport
signing, transport encryption/KEM, and independent effect-proof verification
remain distinct roles even when an implementation library supports more than
one of them.

### 6.2 Why Core Knows Nothing About Crypto

- Core owns domain identity, proof role, protocol version, and deterministic
  proof-selection rules, not algorithm implementations.
- Crypto/platform adapters interpret `suite_id` and the length-delimited key or
  signature bytes selected by the protocol.
- Maintained 1.x Core/Engine/FFI/Flutter still expose `[u8; 32]`, `[u8; 64]`,
  `pubkey32`, and `signature64` at explicit compatibility boundaries. These
  shapes are architecture debt and MUST NOT spread into new production files.
- Hashes and deterministic IDs may remain fixed-size when their protocol
  definition requires it; a fixed hash length is not permission to encode a
  public-key or signature suite implicitly.

### 6.3 Example Implementations

- NostrCryptoProvider: secp256k1 (Schnorr signatures)
- Root Ed25519 provider: maintained 1.x Capsule root signing
- MatrixCryptoProvider: transport-scoped ed25519
- MockCryptoProvider: tests (always succeeds)

### 6.4 Capsule Effect Proof

`CapsuleEffectProof` is the target independently verifiable authorization
envelope for an external effect. It is not a provider receipt and is not a Core
fact merely because verification succeeds.

The proof binds at least:

- proof schema version and verification context;
- `CapsuleId`, capability id, operation id, and effect role;
- canonical request or result commitment;
- one or more suite-tagged `SignatureProof` values and their `key_id` bindings;
- the applicable migration or hybrid-policy checkpoint.

Verification selects suites through the same crypto adapter boundary and fails
closed on unknown suites, malformed lengths, missing role evidence, downgrade,
or a proof that is not bound to the canonical effect commitment. Classical and
post-quantum verification MUST compose in one result path; they do not create
parallel effect lifecycles.

---

## 7. Events (Domain Events)

All state changes happen through signed events.

### 7.1 Base Fields

```rust
struct Event {
    version: u8,        // protocol version (4)
    kind: EventKind,     // event type
    payload: Vec<u8>,    // type-specific fields (binary)
    timestamp: u64,      // from Engine
    signature: Signature,// capsule owner signature
    signer: PubKey,      // root key used to verify signature
}
```

Canonical event identity and signature message:

```text
SHA256(version || kind || payload)
```

`timestamp`, `signature`, and `signer` are serialized event fields but are not
included in the protocol-v4 event identity.

### 7.2 Event Types

Event | Fields
--- | ---
CapsuleCreated | owner_pubkey, capsule birth mode, network
InvitationSent | invitation_id, starter_id, to_pubkey, sender_root_pubkey? (optional root provenance carried with invitation lineage)
InvitationReceived | invitation_id, starter_id, to_pubkey, sender_root_pubkey? (local materialization of received lineage)
InvitationAccepted | invitation_id, from_pubkey, created_starter_id (recipient starter used for the relationship; if accept created a new invited starter, this is that starter ID), accepter_root_pubkey? (optional until root-aware lineage becomes canonical)
InvitationRejected | invitation_id, reason (EmptySlot | Other)
InvitationExpired | invitation_id
StarterCreated | starter_id, nonce, kind, network
StarterBurned | starter_id, reason
RelationshipEstablished | peer_pubkey, own_starter_id, peer_starter_id, kind, invitation_id, sender_pubkey, sender_starter_type, sender_starter_id, peer_root_pubkey?, sender_root_pubkey? (optional root-aware pair anchor fields)
RelationshipBroken | peer_pubkey, own_starter_id, peer_root_pubkey? (optional root-aware pair anchor field)

Event layers are intentionally distinct:

- Transit/history events:
  - `InvitationSent`
  - `InvitationReceived` when materialized locally
- Terminal response events:
  - `InvitationAccepted`
  - `InvitationRejected`
  - `InvitationExpired`
- Local anatomy events:
  - `StarterCreated`
  - `StarterBurned`
- Pairwise truth anchors:
  - `RelationshipEstablished`
  - `RelationshipBroken`

These layers MUST NOT be treated as interchangeable. Invitation history records intent and response, starter events record local capsule anatomy, and relationship events anchor pairwise truth used for relationship management and future pair-scoped consensus checks.

### 7.3 Binary Payload Compatibility Matrix

To preserve deterministic replay across upgrades, payload parsers MUST accept legacy and root-augmented variants listed below.

Event | Allowed payload lengths | Notes
--- | --- | ---
InvitationSent / InvitationReceived | 96, 97, 128, 129, 161, 225 bytes | `97/129` include starter-kind hint byte; `128/129` include `sender_root_pubkey` at bytes `[96..128]`; `161` carries root provenance, starter-kind hint at byte `128`, and sender Nostr transport key at bytes `[129..161]`; `225` additionally carries the 64-byte Ed25519 signature of the canonical public contact card at bytes `[161..225]`. Receivers MUST verify this signature against the sender root before storing the reconstructed v2 card. Legacy payloads remain valid but can only produce an unsigned v1 card.
InvitationAccepted | 96, 128 bytes | `128` includes `accepter_root_pubkey` at bytes `[96..128]`
RelationshipEstablished | 194, 226, 258 bytes | `226` adds `peer_root_pubkey`; `258` adds both `peer_root_pubkey` and `sender_root_pubkey`
RelationshipBroken | 64, 96 bytes | `96` adds `peer_root_pubkey`

Root-aware fields are lineage/pairwise provenance facts. They are not transport routing fields.

---

## 8. Mechanics

### 8.1 Invitations (Full Flow)

Phase 1: Initiation (A → B)

1. A selects starter of type X (slot must be free).
2. Starter is locked (cannot be used in other invitations).
3. A creates InvitationSent in its ledger.
4. Engine signs and sends via transport.

Phase 2: Receive (B)

B receives invitation. Check:

1. Is there already a starter of type X?
2. Is there any empty slot?

Situation | B Action | Result
--- | --- | ---
No own X + empty slot + Accept | Create next local starter lineage instance of type X + InvitationAccepted + RelationshipEstablished | Relationship uses the local X active after acceptance
Own X exists + empty slot + Accept | Create next local lineage instance for one missing starter type + InvitationAccepted + RelationshipEstablished | Relationship uses existing X; additional local capacity is restored
Own X exists + no empty slot + Accept | InvitationAccepted + RelationshipEstablished | Relationship uses existing X; no new starter is created
No own X + no empty slot + Accept | Accept is impossible | No acceptance without capacity for invited type
Empty slot + Reject | InvitationRejected(EmptySlot) | A's starter is burned
Slot occupied + Reject | InvitationRejected(Other) | A's starter is unlocked
Timeout (24h) | - | A's starter unlocked

Burn and slot identity rules:

- `StarterBurned` finalizes the current active lifecycle of that starter identity.
- Burned starter IDs are terminal and MUST NOT be reactivated.
- A slot can be accepted again, but it MUST create the next linear starter generation with a new `starter_id`.
- Repeated reject/accept cycles operate over successive starter generations, not over revived IDs.

### 8.1.1 Acceptance Provenance

When an invitation is accepted, the receiver does not merely acknowledge acceptance.

The receiver MUST also communicate the recipient-side starter reference that now anchors the relationship on the receiver side.

At minimum, relationship history MUST preserve:

- `sender_pubkey`

To support future root-scoped pairwise consensus, invitation lineage SHOULD also preserve root identity once known:

- `InvitationSent.sender_root_pubkey` so incoming invitation lineage can carry sender-root provenance
- `InvitationAccepted.accepter_root_pubkey` so the sender can anchor the accepting capsule at root level

Root-lineage trust rule:

- `InvitationAccepted.accepter_root_pubkey` MUST influence peer-root anchoring only when `InvitationAccepted` has a valid remote signer.
- Unsigned `InvitationAccepted` rows are invalid in protocol v4 and MUST be
  rejected before ledger projection or import.

These fields are lineage provenance, not delivery routing. Transport delivery may remain transport-key based even when root provenance is preserved in ledger history.
- `invitation_id`
- `sender_starter_type`
- `sender_starter_id`

This provenance is required so that both ledgers can reconstruct how the relationship was formed.

### 8.1.2 Starter Identity vs Provenance

A recipient-side starter identity remains local to the receiving capsule and MUST be deterministic from local capsule state plus acceptance-lineage inputs.

The model is linear per slot:

- each lifecycle episode has a unique `starter_id`;
- burning ends that episode permanently;
- next activation in that slot creates the next generation with a new `starter_id`.

Cross-capsule lineage MUST remain recoverable from ledger history rather than by reviving prior IDs.
Acceptance lineage MUST preserve at least:

- `invitation_id`
- `sender_pubkey`
- `sender_starter_type`
- `sender_starter_id`
- `sender_root_pubkey` when available

For `starter_v2` lineage, recipient-side starter derivation MUST include:

- local recovery seed
- target local slot
- `invitation_id`
- inviter anchor (`sender_root_pubkey` when available, otherwise sender transport key)

The sender MUST record the newly created or selected recipient-side starter as a remote starter reference in relationship history.

This does NOT create a sender-local starter entity owned by the recipient.
It creates a relationship-level reference to a remote starter entity owned by the recipient capsule.

### 8.1.3 Invitation Ingress and Projection Contract

Incoming invitation handling MUST be layered and deterministic:

1. Transport ingress validates delivery envelope only (addressing/routing, basic dedupe by event payload/signer).
2. Domain ingress gate validates ledger semantics before append:
   - `InvitationAccepted`, `InvitationRejected`, and `InvitationExpired` MUST resolve an existing invitation lifecycle in local ledger context.
   - Terminal events without a matching invitation offer MUST be discarded as orphan terminal deliveries.
3. Only accepted ingress events are appended to ledger.
4. Invitation projection is rebuilt from ledger events by `invitation_id` using
   first-valid-terminal semantics, with one sender-sovereignty exception:
   - the invitation offer MUST already exist in local ledger order;
   - the first valid `InvitationAccepted`, `InvitationRejected`, or
     `InvitationExpired` event changes `pending` to its terminal state;
   - later terminal events for the same invitation are ignored for state and
     effects, regardless of their kind or embedded timestamp, except a valid
     sender revoke;
   - `InvitationExpired` signed by the original sender of an incoming offer is
     a sender revoke. It MAY supersede a recipient-local optimistic
     `InvitationAccepted` when the sender had not recorded that acceptance.
     The revoke MUST match the exact `invitation_id` and the original offer
     signer; an expiry signed by any other identity is ignored;
   - a terminal event before its offer is orphan history and MUST NOT become
     applicable merely because an offer appears later;
   - when the winning terminal is `Rejected` or `Expired`, a
     `RelationshipEstablished` row tied to that invitation lineage MUST NOT
     project an active relationship. A relationship row may arrive before its
     accepted terminal during asynchronous delivery, but remains blocked while
     the invitation is pending. If a sender revoke arrives after an optimistic
     acceptance, its lineage-created starter remains auditable in the ledger
     but MUST NOT occupy an active starter slot.
5. UI action queues MUST be projection-driven:
   - actionable incoming queue: incoming invitations with `pending` status only
   - actionable outgoing queue: outgoing invitations with `pending` status only
   - terminal invitations (`accepted`/`rejected`/`expired`) belong to history views, not actionable queues

The application MAY keep local transient UX flags (loading/spinner), but those flags MUST NOT become a second truth source for invitation lifecycle state.

### 8.2 Burn Rule (Critical)

A starter is burned ONLY at the sender and only when ALL conditions are met:

1. Recipient has no starter of the invited type and has an empty slot.
2. Recipient explicitly rejects the invitation.
3. Recipient confirmed the burn warning.
4. Sender's starter is burned.

### 8.3 Relationships

- Established automatically on successful acceptance.
- Recorded in both ledgers.
- Relationship history MUST preserve both local and remote starter references.
- Relationship history MUST preserve invitation provenance sufficient to reconstruct which sender starter originated the relationship.
- When available, relationship history SHOULD preserve root-aware pair anchor fields (`peer_root_pubkey`, `sender_root_pubkey`) so pairwise consensus can remain root-scoped across transport adapters.
- Either side can break at any time (RelationshipBroken).
- Starters are not burned on break.

Relationship break is a pair-scoped state machine, not a counter of
`RelationshipBroken` rows:

1. `active`: the latest lifecycle episode is established and has no applicable
   break.
2. `locally_broken`: the local owner signed a break; local relationship truth
   changes immediately and delivery acknowledgment is not required for local
   sovereignty.
3. `pending_remote_break`: a valid remote-signed break notification was
   received; the relationship remains visible locally but pair-scoped execution
   is blocked until the local user confirms it.
4. `confirmed_broken`: local confirmation appends the local-signed break for
   that episode and acknowledges convergence to the initiator.

A later valid `RelationshipEstablished` starts a new lifecycle episode and
supersedes older break-delivery retries for the same relationship key. A replay
from an older episode MUST NOT break the new episode. Local-finalized break has
precedence over a duplicate remote-pending notification from the same episode.

### 8.3.1 Explainable Capsule History

User-facing relationship, invitation, and starter cards MAY open a shared
history detail surface. That surface MUST be a deterministic, read-only
projection of the active Capsule ledger and MUST NOT maintain an independent
history store.

The projection subject is typed and scoped by immutable ledger identity:

- relationship history by peer transport/root identity;
- invitation history by `invitation_id`;
- starter history by `starter_id`.

The same ledger and subject MUST produce the same ordered event set and
projection hash. Events concerning unrelated peers, invitations, or starters
MUST NOT enter the selected history.

An optional inference provider MAY explain this projection in human language.
AI explanation is advisory only: the provider receives a user-approved,
redacted event summary without raw payloads, signatures, seeds, private keys,
or credentials. Provider output MUST NOT mutate ledger truth, authorize an
action, affect consensus, or become a persisted domain fact.

### 8.4 Pairwise Consensus Computation Mode

Pairwise consensus is an execution-time operation, not a permanent UI/runtime background process.

Rules:

1. Pairwise consensus MUST be computed on demand only.
2. Valid triggers for recomputation are:
   - smart-contract execution precondition checks
   - explicit user-requested consensus checks
3. Consensus derivation MUST read only canonical ledger-derived projections.
4. A dedicated Consensus Processor module MUST provide at least:
   - `preview` (derive canonical projection and hash)
   - `signable` (derive the hash to be signed)
   - `verify` (check signature set and hash equality)
5. Pair-scoped smart-contract execution MUST be blocked when consensus state is `mismatch` or unresolved for required participants.
6. Consensus logic MUST NOT be embedded in invitation form policy or screen-local UI orchestration.

For a signable pair snapshot, the projection MUST contain only facts scoped to
the two selected root identities. Active relationship bindings are symmetric
pair facts. Terminal invitation history remains available for ledger/UI
diagnostics, but MUST NOT alter the signed pair snapshot: historical delivery
may be asymmetric after the relationship has been established. A pending
invitation or an unconfirmed remote break for the selected pair MUST still
block signing.

Pair snapshot schema v3 commits current active relationship state, not the
delivery episode that produced it. Each active relationship entry contains
only `relationship_kind` and the sorted `starter_pair`; `invitation_id` remains
ledger lineage and MUST NOT enter the canonical pair snapshot. Repeated
establishment rows with the same relationship kind and sorted starter pair
MUST collapse to one active relationship fact before hashing.

#### 8.4.1 Pair Attestation Protocol

Local `signable(peer_hex)` proves only that one Capsule can derive an
unblocked pair snapshot. It is not two-party consensus and MUST NOT by itself
authorize a `pair_scoped` drone effect.

The two-party protocol is host-owned and on demand:

1. Both Capsules independently derive the same canonical pair snapshot hash.
2. Each root identity signs a domain-separated attestation commitment that
   binds protocol version, sorted pair roots, and snapshot hash.
3. Attestations travel through the generic transport adapter boundary. They
   are not Core domain events and do not enter the Capsule ledger.
4. A capsule-scoped attestation store retains only verified evidence. Evidence
   is keyed by pair roots and snapshot hash, so any pair-state change makes old
   evidence inapplicable without mutable invalidation rules.
5. Pair execution is authorized only when exactly the two expected root
   identities have valid Ed25519 signatures over the same commitment.
6. Missing transport, missing peer attestation, malformed participants,
   unavailable signature verification, hash mismatch, or invalid signatures
   fail closed with deterministic blocker codes.

Dependency direction remains:

`drone -> host guard -> consensus orchestration -> processor/models`, with
transport and root-signing implemented only by host adapters below the
orchestration boundary. UI may request synchronization and display evidence,
but cannot create, approve, or cache consensus truth.

### 8.5 Drone Consensus Guard Standard

Every WASM drone method MUST declare one execution scope:

- `solo`: the method uses only the local Capsule state and does not require a peer.
- `market_scan`: the method reads public/external data and may rank opportunities, but does not mutate a pair-scoped contract.
- `pair_scoped`: the method acts with, for, or toward a specific peer Capsule.

Rules:

1. `pair_scoped` methods MUST require an explicit `peer_hex` root identity.
2. `pair_scoped` methods MUST call the shared Consensus Guard boundary before
   execution. The guard MUST first derive local
   `ConsensusRuntimeService.signable(peer_hex)` over ledger-derived events and
   then require verified two-root attestation evidence for that exact pair and
   snapshot hash. Local signability alone is never authorization.
3. A method MUST NOT treat "any signable peer" as permission for a different,
   missing, or unresolved peer.
4. A method MUST NOT use UI-selected peer lists, contact cards, transport
   mappings, or plugin-local memory as consensus truth. Those inputs may help
   route or display, but not authorize execution.
5. `market_scan` and diagnostic flows MAY bypass pair consensus only when they
   do not send peer-scoped commands, do not broadcast pair-scoped intent, and do
   not create exchange/transport effects on behalf of a peer.
6. Host and plugin outputs MUST include deterministic blocker codes when pair
   consensus is absent, unresolved, pending, broken, or peer selection is missing.

---

## 9. Invariants (DO NOT VIOLATE)

1. Each capsule has exactly 5 slots.
2. Starter cannot change owner.
3. Starter cannot change type.
4. Starter can only be Active or Burned.
5. Ledger is the single source of truth for Core domain facts.
6. Core domain state fully recovers from ledger.
7. All Core domain state changes occur via signed events.
8. Core does not call time, RNG, or crypto.
9. Private key is never passed into Core.
10. UI renders projections and dispatches intents; it does not own domain orchestration.
11. Application logic cannot create a second truth beside ledger-derived state.
12. Plugin execution cannot bypass consensus guard requirements for pair-scoped actions.
13. New architecture modules require explicit non-overlapping ownership.
14. Starter-slot state is projected once in Core; upper layers may render it but MUST NOT reimplement its transition rules.

---

## 10. Data Formats and Serialization

### 10.1 Rules

- All structures are encoded only in binary.
- Allowed formats: bincode (recommended), postcard.
- JSON is forbidden inside Core.
- Encoding: little-endian, fixed-length integers.

### 10.2 Identifiers

All IDs are computed deterministically:

```rust
// Starter ID
SHA256(owner_pubkey || network || kind || creation_nonce)

// Event ID
SHA256(version || kind || payload_bytes)
```

- Event ID is never computed from JSON, base64, or transport representation.
- Starter ID MUST NOT be copied/reused from peer starter identity.
- Starter ID MAY include invitation provenance in deterministic lineage derivation (`starter_v2`) while remaining a local capsule-owned identity.

### 10.3 Identity Derivation Rule

Maintained 1.x derivation follows this compatibility order:

1. recovery seed phrase
2. Capsule root-signing key (`ed25519`)
3. transport-specific derived keys

Transport-specific keys MUST be treated as adapter-level identities, not as the canonical capsule identity.

Target 2.0 contracts separate `CapsuleId` from each role-specific
`KeyDescriptor`. A migration checkpoint or hybrid genesis binds the applicable
root-signing descriptors to the Capsule without changing its domain identity.
Recovery derivation, hardware-backed generation, and imported keys may evolve
independently only when they produce the same canonical descriptor and
checkpoint semantics.

### 10.4 Legacy Identity Note

Older test capsules may expose the Nostr transport key as the capsule public key.
This is a legacy test format, not the intended architecture. Protocol v4 runtime
state rejects new legacy-owner initialization.

The maintained 1.x architecture is:

- root authority on `ed25519`
- transport-specific keys derived afterward for Nostr, Matrix, and future adapters

The target agile architecture is:

- stable `CapsuleId` independent of key algorithm and byte length;
- versioned, suite-tagged, length-delimited key descriptors and signature
  proofs;
- append-only hybrid migration checkpoints that bind old authority, new
  authority, and the exact accumulated Ledger head;
- no rewrite or re-signing of historical events;
- independently migratable root-signing, transport-signing, and
  transport-encryption roles.

Any migration or refactor in this area must preserve:

- seed compatibility
- ledger ownership consistency
- capsule identity stability across upgrades
- one canonical Ledger and verification path across suite migration

---

## 11. Runtime Roles

Birth mode (`Genesis` or `Proto`) is not a runtime role.

### 11.1 Leaf (Regular Capsule)

- Can send/accept invitations.
- Can reject invitations.
- Can break relationships.

### 11.2 Relay (Planned Forwarder Role)

- Relay is not implemented in the supported 1.x runtime.
- When implemented, it remains a role independent from Genesis/Proto birth.
- It has the same Core capabilities as Leaf.
- Can store messages for trusted peers.
- Requires battery > 20% and free space.
- Retention max 24 hours.
- Relay retention expiry is not capsule consensus and MUST NOT synthesize `InvitationExpired`.
- Turning off Relay deletes all stored messages.

### 11.3 Trusted Peers

List of capsules allowed to store messages.

- Add: manual only (QR, NFC, manual pubkey).
- Relay stores messages only for trusted peers.

---

## 12. Networks

The supported 1.x runtime operates Capsules in Neste only.

Hood is reserved for a future 2.0+ experimental runtime. When Hood is
implemented, it forms a fully isolated universe rather than a UI mode over the
same Capsule state:

Network | Purpose
--- | ---
Neste | Main, production
Hood | Test, sandbox

Rules:

- Full isolation (events from Neste do not affect Hood).
- A network-scoped Capsule state has its own ledger, slots, operational stores,
  plugin/drone state, delivery queues, and consensus evidence.
- Same type in different networks = different starters.
- A transport envelope MUST carry an authenticated network scope and MUST be
  rejected before domain projection when it targets another network.
- No 1.x UI toggle may claim to activate Hood before those isolation boundaries
  exist.

---

## 13. Current Limitations (Not Implemented)

- Android Relay forwarding runtime and foreign-message retention policy
- Local Reputation runtime
- Hood experimental runtime and its fully isolated storage, identity-routing,
  transport, plugin-state, and consensus boundaries
- Friend-based recovery (planned for v4.x)
- Kick mechanic (forced break)
- Multisignatures
- Temporary starters
- Group capsules
- Economy and tokens
- Post-quantum root signing, hybrid genesis, migration checkpoints, hybrid KEM
  transport envelopes, and suite-tagged Capsule Effect Proof runtime

---

## 14. Glossary

Term | Definition
--- | ---
Person-First Runtime (PFR) | Local-first architecture whose persistent execution context belongs to the person rather than an application
Capsule | Persistent, recoverable execution context of a person in Hivra
CapsuleId | Stable domain identifier of a Capsule; conceptually independent of every public key and signature suite
KeyDescriptor | Versioned, suite-tagged, key-id-bound, length-delimited public-key description for one cryptographic role
SignatureProof | Versioned, suite-tagged, key-id-bound, length-delimited signature evidence
Capsule Effect Proof | Independently verifiable suite-tagged Capsule authorization evidence for one canonical external-effect commitment
Starter | Unique non-fungible identifier
Slot | Place for your starter (exactly 5)
Ledger | Local signed log of events
Relationship | Fact of mutual recognition
Relay | Android capsule storing others' messages
Trusted peer | Capsule allowed to store messages
Neste | Main network
Hood | Test network
Burning | Destroying a starter after empty-slot rejection
CryptoProvider | Role-specific cryptography interface implemented by crypto/platform adapters and orchestrated through Engine

---

## 15. Status and Readiness

Hivra Protocol v1.0 is the normative protocol contract for the maintained 1.x
runtime. The implementation exists and is released as a test line, but this
document is not a claim that the product is security-audit certified or that
every target architecture migration is complete.

The current status is:

- Core/Engine dependency isolation is enforced by automated review gates.
- Ledger-first state, signed Core events, deterministic slot projection, and
  pair-attestation guard rules are normative v1 behavior.
- Ed25519 root signing, secp256k1 Nostr signing, NIP-44 transport encryption,
  and fixed-size key/signature FFI shapes remain the maintained 1.x
  compatibility baseline; this is not a claim of post-quantum runtime support.
- Crypto agility is a 2.0 contract and migration program. Runtime work cannot
  begin until suite registry, descriptor/proof encoding, hybrid checkpoint,
  downgrade, recovery, and golden-vector contracts are closed.
- Canonical invitation and relationship projection convergence remains an
  active implementation debt tracked in `docs/roadmap.md`; until it is closed,
  Flutter projection services are compatibility implementations and MUST NOT
  become additional truth owners.
- Cryptographic history continuity, event-scoped delivery records, and other
  listed hardening items remain roadmap work.
- Release readiness is determined by the guarded release workflow and the
  platform signoff checklists, not by this status section alone.

---

## 16. UI Screen Contract (Screen Standard and Content)

### 16.1 Scope

Contract is mandatory for:

- Capsule Selector screen
- Main screen and all its tabs
- Starters, Invitations, Relationships, Settings screens
- All future top-level capsule state screens

### 16.2 Source of Truth

1. All capsule metrics in UI MUST be computed from ledger/state projection.
2. Hardcoded counters in headers are FORBIDDEN.
3. Fallback mode is allowed only when ledger export is unavailable and must be explicit and deterministic.

### 16.3 Global Top-Level Screen Structure

Each top-level screen MUST include:

1. AppBar with screen title.
2. Capsule header:
   - network badge (`NESTE` or `HOOD`)
   - capsule public key (visually shortened)
   - counters: `Starters`, `Relationships`, `Pending`
   - ledger metadata: `version`, short `hash`
3. Content area.
4. Bottom navigation with fixed order:
   - Starters
   - Invitations
   - Relationships
   - Settings

### 16.4 Terminology (Required)

UI must use only domain terms:

- Capsule
- Starter
- Invitation
- Relationship
- Ledger
- Network (`NESTE` / `HOOD`)

### 16.5 Visual Consistency

1. Network color fixed:
   - `NESTE` -> green palette
   - `HOOD` -> orange palette
2. Counter colors fixed:
   - Starters -> blue
   - Relationships -> green
   - Pending -> orange
3. Public keys and hashes displayed in monospace.
4. Empty-state pattern: icon + title + explanation + primary action.

### 16.6 Minimum Data Per Screen

Capsule Selector row MUST show:

- network
- short public key
- starters / relationships / pending
- ledger version / hash
- last active marker

Main header MUST show:

- network
- short public key
- starters / relationships / pending
- ledger version / hash

### 16.7 Change Rule

Any PR that changes screen structure, labels, metrics, or visual tokens must:

1. Keep this contract unchanged, or
2. Update this section in the same PR with justification.

UI changes that violate the contract do not pass review.
