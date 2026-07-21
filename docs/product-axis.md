# Hivra Product Axis

Status: canonical product and architecture evaluation contract for Hivra 1.x
and the design of Hivra 2.0. If this document conflicts with the normative
protocol rules in `specification.md`, the specification wins and both documents
must be reconciled in the same change.

## 1. Axis Statement

Hivra advances along one product axis:

> A user-owned Capsule turns explicit intent and authenticated input into
> reproducible local truth through one deterministic capability path, while
> every external effect follows one durable, idempotent lifecycle.

The Capsule must remain useful alone. Trusted links are optional. Drones extend
what the Capsule can do without becoming owners of Capsule identity, Core truth,
keys, transport sessions, or recovery.

This axis is stricter than a feature list. A feature is useful to Hivra only when
it improves Capsule autonomy, truth integrity, safe capability extension, or
reliable interaction without creating a second owner or a second path.

## 2. Two Canonical Lanes

Every production workflow maps to one or both lanes. A third lane is an
architectural defect.

### 2.1 Truth lane

```text
authenticated input or explicit user/drone intent
  -> capability command
  -> sole capability owner validates and decides
  -> signed Core fact is appended to the Capsule ledger
  -> sole projection owner replays the ledger
  -> UI and capability consumers render the projection
```

Only confirmed Core facts use this lane. Capsule birth, starters, invitations,
relationships, and other normative Core transitions belong here.

The sole projection owner is the Core domain projector. One replay produces
scoped `CurrentView`, `PairView`, and `HistoryView` read models. UI, consensus,
and drones consume these contracts; they do not reinterpret raw domain events.
Projection caches are disposable and valid only while their ledger/protocol
binding matches.

### 2.2 Effect lane

```text
capability decision
  -> effect request with capsule scope and stable operation id
  -> sole durable lifecycle owner
  -> capability port
  -> storage, crypto, transport, exchange, or provider adapter
  -> receipt or failure evidence
  -> originating capability reconciles the result
```

An adapter receipt is evidence, not Core truth. Operational journals, contact
cards, pair attestations, plugin state, exchange state, and credentials remain
outside the ledger unless the normative specification promotes a result into a
Core fact.

Timeout, retry, restart, refresh, capsule switching, and background execution
must re-enter the same operation. They must not create another effect path.

## 3. Permanent Product Invariants

1. **User ownership:** identity, recovery authority, and confirmed Capsule
   history remain controlled by the user-owned Capsule.
2. **Solo usefulness:** a Capsule can start, replay, recover, and run solo drones
   without relationships or network availability.
3. **Local-first truth:** persisted local truth is projected before remote
   receive work begins.
4. **One owner:** every command, fact, projection, and effect lifecycle has one
   named capability owner and one public contract.
5. **Replay equality:** the same valid history and explicit inputs produce the
   same projection and deterministic decision hashes.
6. **Effect idempotence:** one user or drone intent cannot become two external
   effects because of timeout, retry, restart, or UI lifecycle.
7. **Capability isolation:** drones receive only declared host capabilities and
   cannot reach keys, raw transport sessions, arbitrary storage, or Core mutation.
8. **Network isolation:** network scope is explicit. Neste state cannot be
   reused by a future Hood runtime or any other network scope.
9. **Failure visibility:** corruption, unavailable evidence, or degraded
   transport fails closed and remains visible; it is not converted into empty
   or successful state.
10. **Replacement with deletion:** a new path replaces, seals, or narrows the
    old path in the same migration unit.

## 4. Predictable Extension Rules

### New drone

A drone owns its contract semantics and private state. It declares its scope
(`solo`, `market_scan`, or `pair_scoped`) and host capabilities. It may request
effects through host APIs but cannot create a parallel Core or transport path.

### New transport

A transport implements the existing delivery port. It authenticates and moves
envelopes but does not interpret invitations, chat, consensus, trading, or
other domain meaning. Adding a transport must not change Core projections.

### New Core capability

A Core capability requires a named owner, canonical commands and facts,
deterministic replay rules, signed protocol representation, migration vectors,
and one projection owner before implementation begins.

### New network

A network is a complete namespace, not a UI toggle. Ledger, slots, operational
stores, drone state, delivery queues, contact data, and consensus evidence must
be isolated by network scope.

### New adapter or provider

An adapter implements a capability port and keeps native DTOs inside the
adapter boundary. Provider output is input or evidence; it cannot silently
become a deterministic decision or Core fact.

## 5. Pre-Implementation Capability Closure

No material function enters implementation until it has a written closure
proof. The proof demonstrates that the complete workflow can be implemented
without importing another capability's internals, duplicating policy, or
creating pass-through DTOs.

### 5.1 Required closure trace

The proposed function must provide one end-to-end trace:

```text
entrypoint
  -> capability command
  -> sole decision owner
  -> owned fact/projection and/or owned effect request
  -> declared port
  -> adapter
  -> evidence/reconciliation
  -> caller-visible result
```

For every arrow, the proof names the public contract and dependency direction.
If an arrow requires a concrete sibling service, screen state, adapter-native
type, or another capability's private store, the proposal is not closed.

### 5.2 Input and state inventory

Every required value is classified before coding:

- Core value or signed fact;
- capability command input;
- ledger-derived projection;
- operational evidence;
- private drone state;
- adapter-native wire value;
- external nondeterministic input such as clock, network, market, or provider
  output.

The inventory names who creates, validates, persists, versions, and deletes
each value. An unowned value means the function is not ready.

### 5.3 Contract and DTO rule

- One capability contract carries semantic values through application layers.
- Adapter wire DTOs remain private to the adapter and are mapped once at the
  declared port.
- UI view models remain private to presentation and contain no domain policy.
- A pass-through DTO that copies another contract only to cross a service or
  directory boundary is forbidden.
- A shared type is allowed only when it is a genuine shared value with the same
  invariants and lifecycle, not merely the same fields.
- A mapper owns a semantic boundary. A mapper that changes only names without
  changing representation, trust, or ownership is evidence of a missing
  contract or an unnecessary layer.

### 5.4 Feasibility verdict

Every proposal receives exactly one verdict:

- `READY`: the owner, contracts, ports, persistence, lifecycle, migration, and
  verification path are closed.
- `NEEDS_CONTRACT`: the capability is valid, but its public contract or port is
  insufficient. Extend that one boundary before feature work.
- `NEEDS_PROTOCOL`: persisted or cross-capsule semantics require a versioned
  protocol, migration vectors, or a new capability owner.
- `REJECTED`: the function requires duplicate truth, hidden coupling, an upward
  dependency, unsafe authority, or an unbounded effect path.

`NEEDS_CONTRACT` and `NEEDS_PROTOCOL` proposals do not start behind temporary
facades or fallback DTOs. The missing architecture is designed first.

### 5.5 Architecture runway

Known feature families have these default closure expectations:

| Feature family | Expected owner and path | Current verdict |
| --- | --- | --- |
| Solo WASM drone | Drone contract -> capability-scoped host API -> declared effect ports | `READY` when capabilities already exist |
| Pair-scoped drone | Drone contract -> explicit peer -> verified Pair Consensus guard -> effect port | `READY` for existing pair semantics |
| Group contract/DAO | Drone-owned group semantics plus versioned quorum and membership evidence | `NEEDS_PROTOCOL`; Pair Consensus composition is not assumed sufficient |
| New transport | Runtime Delivery port -> authenticated adapter; no Core projection changes | `NEEDS_CONTRACT` until the reliable delivery port is event-scoped |
| Distributed backup | Recovery owner -> encrypted shard/envelope port -> consented peers -> deterministic restore proof | `NEEDS_PROTOCOL`; must not reuse invitation/chat internals |
| AI advisory | Redacted snapshot -> inference port -> untrusted advisory result | `READY`; result has no mutation authority |
| AI-initiated action | AI proposal -> deterministic capability command -> normal guard/effect lane | `NEEDS_CONTRACT`; direct AI execution is `REJECTED` |
| Staking drone | Drone policy -> wallet/exchange capability port -> risk and tracking lifecycle | `NEEDS_CONTRACT`; no key or raw wallet access |
| Relay runtime role | Capsule role contract -> scoped storage/delivery ports -> explicit resource policy | `NEEDS_PROTOCOL` |
| Hood network | Fully namespaced identity/history/state/effects from creation onward | `NEEDS_PROTOCOL` and Hivra 2.0 only |

This table is a runway, not authorization. Each concrete proposal still needs
its own closure trace and scorecard.

## 6. Change Scorecard

Every material feature, refactor, protocol change, and reliability fix must
answer these questions before implementation and again during review:

| Check | Required evidence |
| --- | --- |
| Axis gain | Which invariant becomes stronger or which measured risk is removed? |
| Feasibility | What is the closure verdict and complete contract trace? |
| Capability owner | Who solely owns the command, facts, projection, and effects? |
| Lane mapping | Where does the change enter the truth lane and/or effect lane? |
| Canonical contract | Which public contract is added or changed? |
| Deterministic inputs | Are clock, randomness, network, and provider values explicit? |
| Durable identity | What stable operation/event id survives retry and restart? |
| Failure mode | Does failure stay visible and fail closed without losing truth? |
| Isolation | Can another Capsule, network, drone, or screen contaminate this state? |
| Removal delta | Which old path, owner, DTO, branch, or file is removed or sealed? |
| Verification | Which replay, restart, concurrency, migration, and platform tests prove it? |

A change fails architectural review if any required answer is unknown or its
closure verdict is not `READY`. A change
that adds files and dependencies but cannot name a removal or measurable axis
gain is deferred rather than merged.

## 7. Comparable Improvement Evidence

Changes are compared against the previous stable baseline using these signals:

- number of callable intent paths per workflow;
- number of owners per fact, projection, and effect lifecycle;
- replay/golden-vector equality;
- duplicate external effects after timeout/retry/restart tests;
- operational-store lost-update and corruption-recovery tests;
- dependency edges and concrete adapter imports;
- public contracts added and retired;
- files and branches added, removed, or narrowed;
- macOS/Android behavioral parity;
- time to project local state before network work;
- user-visible unresolved/degraded operations instead of silent empty state.

The target is not the smallest file count. The target is lower ambiguity,
fewer paths, stronger replay, and predictable extension. A large cohesive owner
is preferable to many microfiles sharing one lifecycle.

## 8. Version Use

### Hivra 1.x

Use the axis to select security, correctness, recovery, delivery, and narrowly
deleting refactors. Do not add speculative 2.0 paths or parallel contracts.

### Hivra 2.0

Use the same axis to design capability ownership, signed history continuity,
durable effect ports, generated architecture evidence, and strangler migrations
that delete replaced 1.x paths.

The product may gain many drones, transports, adapters, and future network
scopes. The axis, two lanes, and permanent invariants do not change with them.
