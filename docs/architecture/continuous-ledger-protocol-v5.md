# Cryptographically Continuous Ledger Protocol v5

Status: normative design contract for `12.3 / pass 3`. Core and Engine now
have the v5 commitment path; the production FFI/persistence format remains v4
until P3-B/P3-C switch append, import, and storage together.

## 1. Problem and Goal

Protocol v4 signs a domain event identity but does not sign its timestamp,
signer metadata, local ledger position, or the preceding ledger history.
`last_hash` is only a replay checksum. A file attacker can recompute it, and
v4 therefore MUST NOT be described as cryptographically continuous history.

Protocol v5 makes two separate statements explicit:

1. **Domain provenance:** a Capsule root signed this immutable domain event.
2. **Local history acceptance:** this Capsule root accepted that verified event
   at this exact position after this exact preceding local history.

The local ledger remains the only source of truth. A transport delivery,
operational retry record, cache, or peer attestation never becomes an
alternative ledger.

## 2. Ownership and Boundary

| Responsibility | Sole owner |
| --- | --- |
| Canonical event and entry byte commitments | `hivra-core` |
| Event/entry construction and root signing | `hivra-engine` through injected key/crypto ports |
| Seed access, import migration, JSON/FFI conversion | `hivra-ffi` |
| Persistence and atomic file replacement | Flutter storage boundary |
| Rendering current/history/pair views | Flutter projection consumers only |

Core remains deterministic and has no cryptography, clock, I/O, JSON, or
transport dependency. Engine signs Core-provided commitment bytes. FFI is not
allowed to invent a second ledger hash or lifecycle rule.

## 3. v5 Data Model

### 3.1 Domain event

```text
domain_event_id = SHA256(
  "hivra/domain-event/v5" ||
  event_version || kind || payload_length || payload ||
  issued_at_ms || signer_root
)
domain_signature = Ed25519(root_private_key, domain_event_id)
```

`issued_at_ms` and `signer_root` are immutable, signed fields in v5. An
incoming event is never re-timestamped or re-signed by its recipient.

### 3.2 Local ledger entry

```text
entry_commitment = SHA256(
  "hivra/ledger-entry/v5" ||
  ledger_owner_root || sequence_u64_be || previous_entry_commitment ||
  domain_event_id
)
entry_signature = Ed25519(ledger_owner_private_key, entry_commitment)
```

Each v5 entry stores:

```text
ledger_owner_root: [u8; 32]
sequence: u64
previous_entry_commitment: [u8; 32]
domain_event: signed v5 domain event
entry_signature: [u8; 64]
```

`Event` is stored once as the canonical domain-fact sequence in `Ledger`.
The v5 receipt contains only `sequence`, `previous_entry_commitment`, and the
local signature; `LedgerEntryV5` is reconstructed for verification. A second
event collection or a parallel `LedgerV5` owner is forbidden.

For the first v5 entry, `previous_entry_commitment` is the documented genesis
anchor. The entry owner is always the local ledger owner, including when the
embedded domain event was authored by a peer. Thus a recipient confirms only
that it accepted a valid peer event into its local truth; it does not forge the
peer's domain signature.

## 4. Verification Rules

Import MUST fail closed when any one of these conditions fails:

1. ledger owner does not match the active root identity;
2. sequence is not exactly contiguous from zero;
3. an entry previous commitment does not equal the preceding computed entry
   commitment;
4. a domain-event commitment does not match its serialized fields;
5. the domain signature does not verify against its immutable signer root;
6. the entry signature does not verify against the ledger owner root;
7. duplicate domain-event identity appears where the Core replay policy does
   not explicitly permit another lifecycle episode;
8. Core domain validation rejects the chronological event sequence.

Projection order is v5 entry sequence. `issued_at_ms` remains signed evidence,
not an ordering authority. This prevents a clock change or a delivered peer
event from reordering local history.

A self-contained chain detects field mutation, insertion, reordering, and
deletion of any non-tail entry. It cannot prove that the newest valid entries
were not truncated from the end of the only local copy: the remaining prefix is
still a valid history. Tail-loss detection requires a separately trusted
checkpoint (for example an explicitly versioned backup or a peer-attested head)
and is not silently claimed by v5. Such checkpointing is a later capability,
not a reason to make transport or backup state another ledger truth.

## 5. v4 Compatibility and Migration

Existing v4 ledgers remain importable only through an explicit legacy reader:

- validate the v4 checksum, signature policy, birth anchor, and current replay
  invariants exactly as v4 defines them;
- classify the result as `legacy_v4`, not cryptographically continuous;
- compute `legacy_snapshot_commitment = SHA256("hivra/legacy-v4-snapshot/v1" ||
  canonical_v4_ledger_bytes)`;
- when the active owner root is available, create one owner-signed v5
  `LegacyMigrationAnchor` entry that commits to that exact immutable v4
  snapshot; all later v5 entries chain from it;
- retain the v4 event history for audit and projection, but never rewrite it or
  claim that its old ordering metadata became signed retroactively;
- if root signing is unavailable, load the ledger read-only and fail closed for
  any new Core mutation until migration can be completed.

The migration anchor protects all *future* history and makes the precise legacy
snapshot auditable. It cannot repair a v4 file that was altered before the
owner signed that anchor; release and recovery material must say this plainly.

Fresh Capsules create only v5 entries. A v5 export MUST declare its format
explicitly. A v4 export/import fixture remains supported only for migration
tests until a separately approved major-version retirement decision.

## 6. Implementation Units and Exit Evidence

### P3-A: Core commitments and vectors

- introduce v5 event/entry types without changing the v4 runtime path;
- add deterministic golden vectors for domain IDs, entry commitments, genesis,
  second entry, and migration anchor;
- test field mutation, sequence swap, insertion, deletion, and previous-link
  substitution failures.

**Current evidence:** Core owns the sole `Ledger` event collection and derives
v5 entries from its local receipts; Engine signs and verifies both commitment
layers. The runtime has not switched new capsule creation or persistence to
v5 yet.

### P3-B: Engine and FFI append/import

- make Engine construct/sign domain events and local entries through one path;
- preserve incoming peer events exactly, then append an owner-signed local
  entry;
- reject invalid v5 chains and v5 signature failures before runtime replacement;
- retain an explicit read-only v4 import/migration route.

### P3-C: Persistence and release evidence

- evolve JSON/backups atomically with a declared v5 format;
- prove restart, export/import, restore, and cross-platform projection parity;
- run adversarial import vectors and focused macOS/Android smoke before a
  release candidate.

Pass 3 is complete only after P3-A through P3-C land with the old mutable v4
append path removed or sealed for new state.

## 7. Non-Goals

- This protocol does not make remote peers share one global ledger.
- It does not alter Pair Consensus scope or treat transport receipts as facts.
- It does not add a Flutter reducer, a second FFI bridge, or a plugin-specific
  ledger format.
- It does not silently upgrade or discard a user ledger.
