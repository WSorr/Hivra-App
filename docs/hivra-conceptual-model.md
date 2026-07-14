# Hivra Conceptual Model

Hive Integrated Value & Relationship Architecture

Version: 1.0.0
Status: Final
Date: 2026-02-20

---

## Documentation and Comment Language Requirements

### 1. Documentation Language

All user-facing documentation, README files, API docs, guides, and examples published in open repositories or shipped with the product MUST be written in ENGLISH.

This includes (but is not limited to):

- README.md in the root and in every crate
- API docs (/// comments generating rustdoc)
- Code examples in examples/
- Commit messages
- Pull Request descriptions
- Wiki pages (if used)

### 2. Code Comment Language

All comments in production code MUST be in ENGLISH.

```rust
// Correct:
/// Returns the current timestamp from the time source.
pub fn now(&self) -> Timestamp {
    self.time.now()
}

// Incorrect:
/// Возвращает текущую метку времени из источника времени.
pub fn now(&self) -> Timestamp {
    self.time.now()
}
```

### 3. Exceptions

Only the following are exceptions:

- Internal team documents (like this one)
- Temporary development comments (TODO, FIXME) — must be translated or removed before release
- Specific terms without adequate translation

### 4. Rationale

1. Global audience: code and documentation are read by developers worldwide
2. Open Source: English is the standard for open source
3. Tooling: Rust ecosystem (rustdoc, crates.io) is oriented around English
4. Onboarding: new non-Russian-speaking developers must be able to contribute

### 5. Enforcement

Commits containing non-English documentation or comments (in production-bound files) must not pass review and must be corrected.

---

## 0. Introduction

Hivra is a local-first runtime for user-owned Capsules.

A Capsule is a persistent digital extension of a user. It can exist and work alone: it keeps its own ledger, owns its recovery path, runs WASM drones, and does not require relationships to be useful.

Hivra is not a global shared computer. It is closer to a pocket capsule computer:

- a personal runtime for local-first truth
- a capsule-owned history and recovery model
- a Core Trust Layer built from optional trusted links, not discovery

The important architectural point is that capsule state is primary. Transport exists to exchange messages between capsules, but capsule identity, ledger truth, and recovery must remain owned by the capsule itself.

The permanent product axis is therefore simple: a user-owned Capsule turns
explicit intent and authenticated input into reproducible local truth through
one deterministic capability path, while every external effect follows one
durable, idempotent lifecycle. New drones and transports extend the edges of
this system; they do not change who owns Capsule truth.

Trusted links are not the product and Hivra is not a social network. There are no likes, followers, algorithmic feeds, global discovery, people search, or public network maps. Trusted links are internal trust facts created through real-world invitations and reused by drones when they need safe interaction with other Capsules.

Applications normally own user relationships. Hivra moves trusted relationships into the user-owned Capsule. A Chat Drone can use the Trust Layer to know which Capsules can communicate; a Trading Drone can use it for trusted counterparties; an AI Drone can use it for shared context; a Staking Drone may work alone and not use it at all.

Metaphor: Imagine you have 5 unique slippers. Each has its own distinct pattern (Juice, Spark, Seed, Pulse, Kick). You cannot give your slipper away — it always stays with you. But you can invite someone so they create their own slipper with the same pattern. When you both have slippers with the same pattern, a relationship forms.

If you invite someone who does not have that slipper and they refuse to create it — your slipper is destroyed. Forever.

---

## 1. Fundamental Principles (DO NOT VIOLATE)

1. No global discovery — only manual add via pubkey
2. Trusted links are created through invitations, not search
3. Relay is a future optional runtime role, independent from capsule birth
4. Starters are unique identifiers, not economic tokens
5. Starter names are just names (Juice/Spark/Seed/Pulse/Kick), not functions
6. Transport is an abstraction layer (currently Nostr, others can be added)
7. Reputation is local only (for relay scoring)
8. No VPS (except seed, but we do not host them)
9. Trust is more important than convenience
10. Starter always stays with the creator

---

## 2. Entities

### 2.1 Capsule

Capsule is you. An application instance, your identity.

What a capsule has:

- Canonical capsule root public key — the primary identity
- 5 slots — exactly five, no more, no less
- Birth mode — Genesis (five initial starters) or Proto (starts empty)
- Runtime role — Leaf today; Relay is planned independently from birth mode
- Trusted peers — list of capsules allowed to store your messages (Relay only)
- Ledger — local signed log of all events
- Network — Neste in 1.x; Hood may be introduced in 2.0+ only with fully
  isolated state

Identity model:

- A capsule has one canonical root identity.
- The canonical root identity is transport-agnostic.
- Transport adapters derive their own transport-specific keys from the same seed.
- A transport key must not replace the capsule identity in the product model.

Capsule states on first launch:

- No capsules → user creates the first (Proto or Genesis)
- Capsules exist → show capsule selector

Managing multiple capsules:

- Capsules are independent (different seed, different ledger)
- Switch at any time
- Create new capsule from selector

### 2.2 Starter

Starter is a unique, non-fungible asset. Your DNA in the network.

Properties:

- ID — 32 bytes, globally unique
- Type — Juice, Spark, Seed, Pulse, Kick (just names)
- Owner — creator (always one, never changes)
- Origin — who invited you
- Network — Neste or Hood
- Creation time

Rules:

- Starter cannot be transferred
- Type never changes
- Starter can only be burned (when recipient rejects with empty slot)

### 2.3 Slot

Slot is a place for your starter.

Characteristics:

- Exactly 5 slots per capsule (indices 0-4)
- Slot holds ONLY your starter
- Type is not bound to position (Juice can be in any slot)
- Slot can be locked (during invitation)

### 2.4 Ledger (Local Register)

Ledger is the heart of Core domain truth. Capsule birth, starters,
invitations, and relationship facts are recorded here and reconstructed by
replay. Operational delivery state, contact-card routing caches,
pair-attestation evidence, plugin records, private drone journals, and secrets
remain in their dedicated stores and are not ledger facts.

What it stores:

- All signed events (who, when, with whom)
- Current relationship projection (built from events)

Event types:

- InvitationSent — invitation sent
- InvitationAccepted — invitation accepted
- InvitationRejected — invitation rejected
- RelationshipEstablished — relationship created
- RelationshipBroken — relationship broken

### 2.5 Relationship

Relationship is an internal Trust Layer fact of mutual recognition between two capsules.

It is not a social-network edge and not a public graph entry. It is a ledger-derived trust fact that drones may consume through the Trust Layer API when they need pair-scoped safety.

Properties:

- Peer (pubkey)
- Starter type (which type the relationship is based on)
- Peer starter ID
- Own starter ID
- Timestamp

Important: One starter can participate in multiple relationships. 5 starters != 5 relationships.

### 2.6 Birth Modes and Runtime Roles

Genesis and Proto describe how starter history begins:

- Genesis starts with five locally generated starters.
- Proto starts empty and obtains starter generations through accepted
  invitation lineage.

Leaf and Relay describe runtime behavior. They do not alter starter birth.

Leaf — regular capsule:

- Can send invitations (if free starters exist)
- Can accept invitations
- Can reject invitations
- Can break relationships

Relay — planned role, not implemented in the current runtime:

- Same as Leaf
- Can store messages for trusted peers
- Can relay (battery-aware)

### 2.7 Trusted Peers

List of capsules allowed to store your messages.

How to add: manual only (QR, NFC, manual pubkey)

What it enables: Relay stores messages for the peer

What it does NOT enable: auto-accept invitations, starter access

### 2.8 Networks

Hivra 1.x supports Neste. Hood is a 2.0+ experimental-network design target,
not a second active state inside the current Capsule. When implemented, the
networks are fully isolated universes:

Network | Purpose
--- | ---
Neste | Main, production
Hood | Test, sandbox

Rules:

- Full isolation (events from Neste do not affect Hood)
- Each network-scoped Capsule state has an independent ledger, slots,
  operational stores, drone state, delivery queues, and consensus evidence
- Same type in different networks = different starters
- Cross-network transport events are rejected before projection

---

## 3. Mechanics

### 3.1 Invitations (Full Flow)

Phase 1: Initiation (A → B)

1. A selects their starter of type X
2. Starter is locked (cannot be used in other invitations)
3. A creates InvitationSent in their ledger
4. Invitation is delivered to B via transport layer

Phase 2: Receive and Decide (B)

B receives invitation and checks:

1. Do they already have a starter of type X?
2. Is there any empty slot?

Case A: No own X + empty slot + ACCEPT

- B activates local starter of type X in an empty slot as the next slot lineage instance (new lifecycle ID)
- B creates InvitationAccepted
- B creates RelationshipEstablished with A
- A receives confirmation, unlocks their starter
- A creates RelationshipEstablished with B
- Result: relationship established using B's active local X

Case B: Empty slot + REJECT (BURN)

- UI warns: "Starter A will be destroyed"
- B confirms rejection
- B creates InvitationRejected with reason EmptySlot
- A receives, DELETES their starter (burned)
- Result: A lost starter, no relationship

Case C: Own X exists + empty slot + ACCEPT

- B keeps using their existing X for the relationship
- B activates one missing starter type in the empty slot as the next slot lineage instance (new lifecycle ID)
- B creates InvitationAccepted
- B creates RelationshipEstablished
- A receives, unlocks their starter
- A creates RelationshipEstablished
- Result: relationship established on existing X, and B fills one missing type

Case D: Own X exists + no empty slot + ACCEPT

- B creates InvitationAccepted
- B creates RelationshipEstablished
- A receives, unlocks their starter
- A creates RelationshipEstablished
- Result: relationship established, no new starter created

Case E: Slot occupied + REJECT

- B creates InvitationRejected with reason Other
- A receives, unlocks their starter
- Result: no relationship

Case F: No response yet

- A keeps the starter locked while waiting for a pair-terminal response
- A may explicitly cancel the invitation to unlock the starter
- No local clock timeout creates a pair-terminal ledger fact

### 3.2 Burn Rule (CRITICAL)

A starter is burned ONLY when ALL conditions are met:

1. Recipient has no starter of that type and has an empty slot
2. Recipient explicitly rejects the invitation
3. Recipient confirmed the burn warning

Burn invariants:

- Burn applies to the current active lifecycle, not to slot capacity.
- A burned starter ID is terminal and is never reactivated.
- The slot remains available for future accepts, but each new activation creates the next linear starter generation with a new ID.
- Lineage ancestry (invitation and inviter provenance) is preserved in ledger history, not by reusing burned IDs.

### 3.3 Relationships

Establishing:

- Happens automatically on successful acceptance
- Recorded in both ledgers

Breaking:

- Either side can break at any time
- RelationshipBroken recorded in ledger
- Starters are NOT burned on break

### 3.4 Relay (planned, not implemented in the current runtime)

Relay conditions:

1. Relay role enabled in settings
2. Recipient is in trusted_peers
3. Battery > 20%
4. Free space available

Process:

1. A sends message to B
2. Relay V (trusted by B) stores message
3. B comes online
4. Relay V forwards message
5. Relay V deletes stored message

Relay retention is transport policy, not capsule truth.

Relay off: all stored foreign messages are deleted immediately

### 3.5 Local Reputation (planned, not implemented in the current runtime)

Only for rating relay reliability. Local only.

Signals:

- How many times relay delivered
- How many times relay failed

Used for: UI hints only, no protocol influence

---

## 4. Exceptional Cases

Scenario | Outcome
--- | ---
Invitation received, no own type, empty slot, accepted | New starter for B, relationship, starter A unlocked
Invitation received, own type exists, empty slot, accepted | Relationship established on existing type, one missing starter created, starter A unlocked
Invitation received, own type exists, no empty slot, accepted | Relationship established on existing type, starter A unlocked
Invitation received, empty slot, rejected | STARTER A BURNED
Invitation received, slot occupied, rejected | Starter A unlocked, no relationship
Recipient offline | Relay may retain or drop the message according to transport policy
No response | Starter remains locked until accept/reject arrives or sender explicitly cancels
Relay turned off | All stored messages deleted
Relationship broken | Relationship removed, starters remain
Invite with locked starter | Error: starter busy

---

## 5. Transport Layer (Extensibility)

Hivra currently ships with Nostr as the main transport, but the architecture allows others:

Supported host transport adapters:

- Nostr (built-in)
- Matrix (planned host adapter)
- Bluetooth LE (planned host adapter, mesh)
- Local network (planned host adapter, offline enclaves)

How it works:

- Capsule can use one or multiple transports
- Message is broadcast to all recipient transports
- Recipient accepts the first delivered

Boundary:

- transport adapters are not WASM drones
- transport adapters perform effectful delivery work: network, relay, retry, and transport-specific routing
- WASM drones may ask the host to deliver deterministic envelopes, but never receive direct network or keychain access

Guarantees:

- Ledger does not know which transport delivered the event
- Determinism is preserved

---

## 6. Current Limitations (Not Implemented)

- Friend-based recovery (planned for v4.x)
- Kick mechanic (forced break)
- Multisignatures
- Temporary starters
- Group capsules
- Economy and tokens

---

## 7. Glossary

Term | Definition
--- | ---
Capsule | App instance, your identity
Starter | Unique non-fungible asset
Slot | Place for your starter (exactly 5)
Ledger | Local signed log of events
Relationship | Fact of mutual recognition
Relay | Android capsule storing others' messages
Trusted peer | Capsule allowed to store messages
Neste | Main network
Hood | Test network
Burning | Destroying a starter after empty-slot rejection

---

End of document 1
