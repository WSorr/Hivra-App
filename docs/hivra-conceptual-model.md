# Hivra Conceptual Model

This document explains Hivra in product language. It does not define protocol
fields, event transitions, storage schemas, or release state. Those belong to
`specification.md` and the focused architecture contracts.

## 1. Person-First Runtime

Conventional applications create their own account, contacts, permissions,
history, and continuity. The person exists as a record inside each application
and starts again when the application changes.

Hivra reverses that ownership. A **Person-First Runtime (PFR)** gives the person
a persistent local execution context before any individual application. Hivra
calls that context a **Capsule**.

A Capsule can operate alone. It owns its recovery path, keeps authenticated
history, runs replaceable WASM drones, and may establish optional trusted links
with other Capsules. Chat, trading, AI, staking, and public agents are tools
around the Capsule rather than owners of the person.

**Applications are temporary. The person's runtime is not.**

## 2. Product Boundary

Hivra is not a social network, global account directory, public graph, or
hosted shared computer.

- There is no global discovery or people search.
- A relationship begins through an explicit invitation between Capsules.
- Relationships are private trust facts, not likes, follows, or public edges.
- A Capsule does not need a relationship to run solo drones.
- External services and transports are replaceable adapters.
- External effects require explicit bounded authority and durable receipts.

The permanent engineering direction is defined in `product-axis.md`:
authenticated input becomes reproducible local truth through one owner, while
every external effect follows one idempotent lifecycle.

## 3. Capsule

A Capsule is a persistent, recoverable runtime context. It is not an
application account and not merely a public key.

Conceptually it owns:

- a canonical root identity;
- recovery authority;
- a local signed Ledger;
- five Starter slots;
- optional trusted relationships;
- isolated drone state and permissions;
- transport-independent addressing information.

Multiple Capsules on one device remain independent. They have different
recovery material, Ledgers, relationships, plugin state, credentials, and
active UI context. Switching the visible Capsule must never switch background
truth or leak state between them.

The root identity is transport-agnostic. Nostr and future transports use their
own endpoint keys and routing details without replacing Capsule identity.

## 4. Ledger and Projections

The Ledger is the append-only signed history of Capsule domain facts. Current
screens do not become truth stores: they display canonical projections derived
from the Ledger or from the dedicated owner of operational state.

Not every local record is a Ledger fact. Delivery queues, routing caches,
pair-attestation evidence, plugin state, external-effect journals, and secrets
have dedicated stores because they represent operations or private capability
state rather than Capsule domain history.

This distinction gives the user two useful views:

- **current state:** what exists and can be acted on now;
- **history:** how that state was reached.

A repaired relationship should look healthy in the primary UI even though its
earlier break remains available in history. Past facts are not erased, but they
do not masquerade as current actionable state.

## 5. Starters and Slots

A Capsule has exactly five Starter slots. Starter type names are `Juice`,
`Spark`, `Seed`, `Pulse`, and `Kick`; the names do not grant different
functions or economic value.

A Starter is a unique lifecycle instance used to establish trusted links. It
is not transferable, mineable, or a token. One active Starter can support more
than one relationship, so five Starters do not limit a Capsule to five peers.

A slot is capacity for the Capsule's own Starter lineage. When one lifecycle is
permanently burned, its identifier is never reused. A later accepted invitation
may create a new generation in that slot with a new identifier while preserving
lineage history.

The exact acceptance, rejection, cancellation, burn, and generation rules are
normative only in `specification.md`.

## 6. Invitations and Relationships

An invitation is an explicit proposal from one Capsule to establish a trusted
link through a Starter. The sender's Starter remains locked until the pair
reaches a terminal response or the sender cancels.

Acceptance may create a missing local Starter generation and establishes the
relationship in each Capsule's own Ledger. Rejection can burn the sender's
specific active Starter lifecycle only in the protocol-defined empty-slot
case. Breaking a relationship does not burn its Starters.

A **Relationship** is a private Trust Layer fact of mutual recognition. Drones
may use the Trust Layer when their capability needs a trusted peer:

- Chat can restrict delivery to trusted Capsules.
- A collaborative contract can require pair evidence.
- Trading can operate solo and does not require consensus unless the user
  explicitly chooses collaborative behavior.
- Staking or local AI may ignore relationships entirely.

The Trust Layer is reusable infrastructure, not the product itself.

## 7. Pair Consensus

Pair Consensus answers a narrow question: do two Capsules possess compatible,
authenticated evidence for the pair-scoped state required by one operation?

It is computed from canonical pair-scoped views, not by comparing whole
Ledgers. Events involving unrelated Capsules must not affect the result.
Consensus is checked on demand for capabilities that declare it as a
precondition; it is not a universal requirement for every drone.

Pair Consensus is not global consensus and does not by itself define groups,
voting, multisignature, or DAO semantics. Those require explicit higher-level
contracts rather than hidden Core expansion.

## 8. Drones

Drones are isolated WASM extensions that provide user-facing capabilities.
They consume bounded host capabilities instead of receiving direct access to
keys, filesystems, networks, provider credentials, or Ledger mutation.

The Capsule owns intent and authority. A drone may compute a proposal; the host
validates policy and grants only the exact capability required for an effect.
The external adapter performs the effect and returns evidence to its one
durable lifecycle owner.

This keeps inference, trading strategy, chat behavior, staking logic, and
external social agents replaceable without changing Core identity or history.

## 9. Transport

Transport is a neutral rail for authenticated Capsule envelopes, closer to a
banking message network than to a social application.

Nostr is the current built-in host adapter. Adapter-specific relay sessions,
cursor behavior, acknowledgements, retries, and protocol formats remain behind
the transport boundary. Core receives authenticated Hivra inputs and does not
decide truth from transport-specific metadata.

WASM drones can request bounded delivery through host capabilities but cannot
open transport sessions or access transport keys. Spam protection,
deduplication, payload limits, sender policy, and quarantine occur before
domain materialization.

## 10. Networks and Roles

Hivra 1.x uses the `Neste` network and the implemented runtime roles described
in `specification.md`.

`Genesis` and `Proto` describe how Starter history begins; they are not runtime
roles. A future `Relay` role or experimental `Hood` network cannot be inferred
from birth mode. Any additional network must isolate Ledger, slots, operational
stores, drone state, delivery state, and consensus evidence from every other
network.

## 11. User Journeys

### Start alone

The user creates or restores a Capsule, sees its current state, and can install
solo drones without creating any relationship.

### Establish trust

Two people exchange Capsule cards out of band. One sends an invitation, the
other reviews and accepts it, and both Capsules eventually project the same
trusted relationship from their own authenticated history.

### Work through a drone

The user opens a drone, supplies or approves bounded intent, reviews relevant
state, and authorizes an exact effect when required. The effect remains
traceable and recoverable after timeout or restart.

### Recover

The recovery phrase restores Capsule identity. A backup restores the richer
local history and operational state included by its explicit format. External
service credentials are separate and are never silently reconstructed from the
Capsule seed.

## 12. Glossary

| Term | Meaning |
| --- | --- |
| Person-First Runtime | User-owned runtime that precedes individual apps |
| Capsule | Persistent local identity, history, recovery, and capability context |
| Ledger | Append-only signed domain history |
| Projection | Canonical current or historical view derived by its owner |
| Starter | Unique local lifecycle instance used in trusted-link creation |
| Slot | One of five positions for local Starter lineage |
| Invitation | Explicit proposal to establish a trusted relationship |
| Relationship | Private Trust Layer fact between Capsules |
| Pair Consensus | Authenticated agreement over one pair-scoped view |
| Drone | Isolated WASM extension using bounded host capabilities |
| Transport | Replaceable host adapter for authenticated envelope delivery |
| External effect | Durable provider action performed under bounded authority |
