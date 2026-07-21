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

- The canonical capsule root identity curve is `ed25519`.
- This identity is transport-agnostic.
- Transport-specific keys MUST be derived from the same recovery seed using explicit domain separation.
- A transport key MUST NOT replace the canonical capsule identity in the architecture.

Examples:

- capsule root identity: `ed25519`
- Nostr transport identity: derived `secp256k1`
- Matrix transport identity: derived `ed25519` using a transport-specific derivation label

UI, documentation, and cross-capsule semantics should refer to capsule identity at the root-identity layer unless a transport-specific key is explicitly required.

### 3.3 Core Entities

#### 3.3.1 Capsule

Capsule is an application instance, the user identity.

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
- Events are append-only; deletion or overwrite is forbidden.
- Protocol v4 signatures authenticate the canonical event identity
  `SHA256(version || kind || payload)` under `event.signer`.
- `timestamp` and ledger position are not part of that signed identity in v4.
- `last_hash` is a deterministic 64-bit replay checksum, not a cryptographic
  history commitment. Cryptographic sequence/metadata commitment is an active
  protocol-hardening debt and MUST NOT be claimed by UI or release material.

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
- On macOS, per-capsule seeds are stored in Keychain. Runtime activation uses a
  process-local active seed cache; selecting or bootstrapping a capsule MUST NOT
  rewrite a global active-seed Keychain pointer or persist a second native copy
  of the seed. The legacy native Keychain layout is read-only recovery input;
  Flutter secure storage is the single per-capsule persistence authority.
- Recovery seeds MUST NOT be persisted in plaintext files. If platform secure
  storage is unavailable, seed persistence fails closed.
- Legacy plaintext seed files MAY be consumed only for one-time migration:
  every valid entry is written to secure storage, verified by read-back, and
  the plaintext file is deleted before normal use continues.
- Capsule metadata stored under "capsule_metadata".

Selector screen:

- Shown on launch if at least one capsule exists.
- Displays public key, network, starter count.
- Allows creating a new capsule.

Switching:

- Selecting a capsule loads its seed and ledger.
- Previous capsule is unloaded from memory.
- Capsule selection MUST preserve the storage/runtime boundary:
  persistent per-capsule seed storage is a secure-storage concern, while active
  runtime seed selection is process-local and non-authoritative.

Diagnostics:

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

### 5.2.2 WASM Plugin Host Contract

WASM plugin execution is allowed only through a host boundary with explicit capabilities.

Mandatory constraints:

1. Plugin runtime is sandboxed.
2. Plugin registry/storage is isolated from capsule ledger storage.
3. Plugins MUST NOT append ledger events directly.
4. Plugins MUST NOT bypass Engine validation or Core invariants.
5. Pair-scoped plugin execution MUST be blocked when consensus guard is not signable.
6. Plugin host inputs/outputs MUST be deterministic for identical inputs.

### 5.2.3 Identity Separation Rule

Transport adapters operate on transport-specific keys only.

They MUST NOT redefine or replace the canonical capsule root identity.

The existence of a Nostr public key, Matrix public key, or any other transport key does not change the fact that capsule identity is rooted in the canonical `ed25519` identity layer.

### 5.3 Unified Message Format

```rust
struct Message {
    from: PubKey,
    to: PubKey,
    kind: u32,              // event type (Invitation, Relationship...)
    payload: Vec<u8>,       // serialized event
    timestamp: u64,
    invitation_id: Option<[u8; 32]>,
    transport_hints: Vec<Hint>,
}
```

### 5.4 Nostr Adapter (Example)

```
Core bytes → base64 → Nostr content
```

After NIP-04 decryption, the adapter MUST require the embedded
`Message.from` key to equal the public key that signed the outer Nostr event.
Self-declared sender identity inside encrypted JSON is never authoritative.

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

CryptoProvider is implemented per transport. It lives in Engine, NOT in Core.

### 6.2 Why Core Knows Nothing About Crypto

- Core operates on raw bytes ([u8; 32], [u8; 64]).
- Interpreting those bytes as public keys or signatures happens only in CryptoProvider.
- This enables any curve (secp256k1, ed25519, ...) without changing Core.

### 6.3 Example Implementations

- NostrCryptoProvider: secp256k1 (Schnorr signatures)
- MatrixCryptoProvider: ed25519
- MockCryptoProvider: tests (always succeeds)

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
InvitationSent / InvitationReceived | 96, 97, 128, 129, 161 bytes | `97/129` include starter-kind hint byte; `128/129` include `sender_root_pubkey` at bytes `[96..128]`; `161` carries root provenance, starter-kind hint at byte `128`, and sender Nostr transport key at bytes `[129..161]`
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

Identity derivation must follow this order:

1. recovery seed phrase
2. canonical capsule root identity (`ed25519`)
3. transport-specific derived keys

Transport-specific keys MUST be treated as adapter-level identities, not as the canonical capsule identity.

### 10.4 Legacy Identity Note

Older test capsules may expose the Nostr transport key as the capsule public key.
This is a legacy test format, not the intended architecture. Protocol v4 runtime
state rejects new legacy-owner initialization.

The target architecture is:

- canonical capsule identity on `ed25519`
- transport-specific keys derived afterward for Nostr, Matrix, and future adapters

Any migration or refactor in this area must preserve:

- seed compatibility
- ledger ownership consistency
- capsule identity stability across upgrades

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

---

## 14. Glossary

Term | Definition
--- | ---
Capsule | App instance, user identity
Starter | Unique non-fungible identifier
Slot | Place for your starter (exactly 5)
Ledger | Local signed log of events
Relationship | Fact of mutual recognition
Relay | Android capsule storing others' messages
Trusted peer | Capsule allowed to store messages
Neste | Main network
Hood | Test network
Burning | Destroying a starter after empty-slot rejection
CryptoProvider | Cryptography interface in Engine (transport-specific)

---

## 15. Status and Readiness

Hivra Protocol in this revision is:

- Architecturally clean (strict downward dependencies)
- Logically consistent
- Deterministic (Core has no external dependencies)
- Transport-agnostic (Core is crypto-agnostic)
- Ready for formal audit
- Ready for implementation: Rust Core + Flutter UI

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
