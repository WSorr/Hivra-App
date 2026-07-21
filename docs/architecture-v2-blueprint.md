# Hivra 2.0 Architecture Blueprint

Status: design-only draft. This document does not change the normative Hivra
1.x protocol or authorize a 1.x runtime migration.

## 1. Objective

Hivra 2.0 is a controlled architecture program, not a feature release. Its
purpose is to preserve the useful behavior proven in 1.x while removing the
conditions that allowed application entropy to grow:

- several classes participating in one workflow without one visible owner;
- DTOs moved into neutral-looking files without a real contract boundary;
- screens and generic runtime services accumulating feature composition;
- retries, refreshes, and background workers becoming competing effect paths;
- new wrappers being added while old paths remain callable;
- plugin business behavior leaking into the host application.

The target is a codebase whose module map can be derived from its declared
owners and dependencies, and whose review gates reject architectural drift
before it reaches a release.

The permanent evaluation axis is `product-axis.md`. Hivra 2.0 may replace
contracts and implementations, but it must preserve the same truth lane,
effect lane, user-ownership invariants, and comparable change scorecard.

## 2. Parallel Version Contract

Hivra 1.x and 2.0 have different responsibilities.

### 1.x: maintained product line

Allowed:

- security and correctness fixes;
- deterministic replay, persistence, transport, and projection fixes;
- narrowly scoped refactors that remove code or close a proven boundary;
- release and migration preparation;
- tests and gates that protect existing behavior.

Not allowed:

- speculative protocol-v2 fields or events;
- broad directory reshuffles without a measured reduction in coupling;
- parallel APIs introduced only to prepare for 2.0;
- breaking persisted-ledger, plugin-host, or FFI contracts.

### 2.0: design and proof line

Allowed before implementation begins:

- capability ownership map;
- contract and event schemas;
- dependency graph and forbidden-edge rules;
- migration fixtures and compatibility decisions;
- small isolated proofs that do not become a second production path.

No 2.0 component replaces a 1.x component until its owner, contract,
deterministic tests, migration rule, removal target, and rollback boundary are
all explicit.

## 3. Refined Hivra Laws

The three laws remain unchanged in count, but 2.0 makes them mechanically
testable.

### Law 1: Modularity means one capability, one owner, one public contract

- A capability owns its commands, facts, projections, and effect requests.
- A DTO has no independent architectural status. It belongs to the contract
  that produces or consumes it.
- A facade is valid only when it hides a capability implementation. A facade
  that merely exposes an internal service graph is a service locator.
- Adding a replacement requires naming and removing or sealing the old entry
  path.

### Law 2: Determinism means one fact history and one effect lifecycle

- Confirmed capsule state is reconstructed from one ledger history.
- Pure decisions consume explicit input values and produce canonical output.
- Effects use stable operation ids and one durable lifecycle owner.
- Timeout, retry, refresh, restart, or capsule switch cannot create a second
  operation or a second truth.
- Wall clock, randomness, network state, and provider responses are inputs or
  evidence, never hidden dependencies.

### Law 3: Dependencies point toward stable contracts; composition stays at the edge

- Domain code depends on no runtime or adapter implementation.
- Use cases depend on domain contracts and effect ports.
- Adapters implement ports without learning domain policy.
- UI and WASM drones call capability APIs; they do not assemble internals.
- The platform composition root is the only owner allowed to connect concrete
  implementations.

## 4. Capability Map

The map is organized by ownership, not by a growing global `services/` or
`models/` bucket.

| Capability | Sole owner | Public surface | Persisted truth | External effects |
| --- | --- | --- | --- | --- |
| Capsule identity | Core Capsule | identity commands/facts | ledger | key port |
| Network isolation | Core Capsule | network scope contract | isolated network-scoped state | transport scope validation |
| Ledger | Core Ledger | append, verify, replay | signed ledger | storage port |
| Invitations | Core Trust | invite decisions/facts | ledger | delivery port |
| Relationships | Core Trust | pair projection | ledger | none |
| Pair Consensus | Core Consensus | pair snapshot/attestation | ledger + verified evidence | signing/delivery ports |
| Delivery | Runtime Delivery | enqueue/status/receipt | durable operation journal | transport adapters |
| External service effects | Runtime External Effects | provider-scoped operation/status/receipt | durable operation journal | allowlisted provider adapters |
| Drone execution | WASM Host | capability-scoped host ABI | plugin registry/evidence | sandbox/runtime ports |
| Application projection | App Shell | screen projections/intents | no independent truth | capability APIs only |
| Trading/chat/AI/staking | External drones | declared WASM contracts | drone-owned state | granted host capabilities |
| External agent presence | External provider drone | declared WASM contract | isolated drone state | Runtime External Effects capability |

`Delivery` owns transport execution but not invitation, chat, or consensus
meaning. The domain owner creates an effect request; Delivery executes and
reports it. A transport adapter only moves authenticated bytes.

`Runtime External Effects` is distinct from Capsule-to-Capsule Delivery. It
owns durable execution and receipts for provider APIs such as exchanges or
agent platforms, while each external drone owns provider-specific product
policy. WASM never receives generic network or credential access.

## 5. Dependency Map

```text
External WASM drones        Application UI
          |                       |
          +------ capability APIs +
                          |
                  Application use cases
                          |
               Core contracts + effect ports
                          |
              Pure Core (Capsule/Ledger/Trust/Consensus)

Platform composition root -> concrete storage/crypto/transport/WASM adapters
```

The arrows above mean "may depend on" toward the stable contract. Concrete
adapters are connected by the composition root; they do not become lateral
dependencies of capability owners.

## 6. Contract Placement Rules

2.0 does not keep a global DTO layer.

- A command, result, event, projection, or error type lives with its owning
  capability contract.
- Wire envelopes belong to the boundary that serializes them.
- Adapter-native request/response types stay inside the adapter and are mapped
  once at its port boundary.
- UI view state belongs to the application projection, not Core.
- Identical field sets do not justify a shared type unless their invariants and
  lifecycle are also identical.
- A type used by multiple capabilities is promoted only when it represents a
  genuine Core value object, not merely to reduce imports.

## 7. Anti-Entropy Budget

Every 2.0 change must keep or improve these measurable properties:

1. One declared owner for each capability, fact, projection, and effect
   lifecycle.
2. No dependency cycle and no forbidden upward or lateral concrete import.
3. No production workflow with more than one callable intent entry path.
4. No domain truth persisted outside the ledger unless the specification names
   it as operational evidence or private drone state.
5. No adapter DTO crosses its port boundary.
6. No screen constructs a feature graph or interprets domain terminal states.
7. No new module without deleting, sealing, or narrowing an old path.
8. No patch that increases both file count and cross-module imports without an
   explicit, reviewed exception.

The architecture review records deltas, not only totals:

- modules/files added and removed;
- public contracts added and retired;
- dependency edges added and removed;
- orchestration paths added and removed;
- duplicated projections or serializers eliminated;
- largest owner files and their reasons for remaining large.

These are signals, not arbitrary size limits. A large cohesive owner is safer
than ten microfiles that distribute one responsibility.

## 7.1 Human-Facing Capsule Experience

Hivra 2.0 makes the Capsule understandable without asking a normal user to
learn its internal protocol vocabulary. A person operates a Capsule, trusted
links, and drones; they do not operate hashes, transport keys, ledger indices,
or starter instances as primary product objects.

This is a product contract for the App Shell. It does not weaken or hide the
underlying security model: the same verified ledger facts, lineage rules, and
effect evidence remain available through deliberate inspection.

### Progressive disclosure contract

The default Capsule experience presents:

- whether the Capsule is ready, needs attention, or is waiting for an explicit
  user decision;
- trusted links, invitations, and their human-readable history;
- installed drones and their user-facing actions;
- a Capsule Map that explains the Capsule's history and current trust state.

The default experience does not lead with starter ids, slot numbers, root or
transport keys, event hashes, consensus commitments, raw ledger events, or
adapter diagnostics.

Those facts remain reachable through explicit depth:

```text
Capsule Home
  -> Capsule Map / relationship history
    -> lineage and decision details
      -> starter lifecycle and fact evidence
        -> technical diagnostics (ledger, signatures, hashes, transport trace)
```

Each layer must explain why the user is seeing the next layer. A technical
identifier without its role, lifecycle, and related human action is not a
usable interface.

### Capsule Map contract

`Capsule Map` is a dedicated application projection owned by the App Shell. It
turns confirmed Capsule history into an explorable, clickable picture:

- Capsule birth and recovery milestones;
- invitation sent, accepted, rejected, expired, or cancelled;
- trust-link establishment, break, and later re-establishment;
- relationship episodes and their current state;
- drone history only where the drone explicitly publishes user-visible,
  non-sensitive facts.

A click on a connection opens its relationship history. A deeper click may
open the starter lineage that caused a trust episode, including burn or
recovery history. This keeps starter lineage available for understanding and
audit without making it the normal navigation model.

The map is never an independent history store. It is reconstructed from the
same ledger projection as all other Capsule state. Operational evidence such
as transport attempts, delivery receipts, and diagnostic failures must be
visually marked as operational evidence, not rendered as confirmed Capsule
truth.

Relationship, invitation, and starter detail views use one typed
`CapsuleHistorySubject -> CapsuleHistoryProjection` contract. Cards pass only a
subject and navigation intent to the App Shell; they do not depend on ledger
decoders, AI providers, credentials, or network adapters.

AI explanation is a sidecar advisory path:

```text
ledger -> scoped deterministic history -> redacted evidence -> inference port
```

It is explicit and user-triggered. The deterministic history remains useful
without a provider, while provider output is visually labelled as advisory and
never feeds back into Core truth or domain actions.

### Engineering boundary

Ledger Inspector, raw hashes, signatures, root/transport identities, consensus
evidence, bootstrap state, delivery queues, and traces belong behind an
explicit Diagnostics or Developer Mode boundary. They are required for
recovery, audit, and engineering, but are not normal-user navigation.

Developer Mode must be explicit, scoped, and reversible. It must not change
Capsule truth, grant a drone additional capabilities, or make a diagnostic
screen the owner of a domain action.

### App Shell acceptance rules

1. A normal user can understand current Capsule state and resolve required
   actions without reading a hash or starter id.
2. No security-relevant decision becomes invisible: destructive or irreversible
   consequences are expressed in human language before confirmation.
3. Every user-facing state shown by Home, Map, or relationship screens comes
   from one named projection owner, not screen-local reconstruction.
4. The same ledger history produces the same map and history projection;
   ordering and grouping rules are canonical and testable.
5. A technical drill-down can explain any visible relationship state back to
   its confirmed facts and, when necessary, its starter lineage.
6. Visual polish must not introduce a parallel state machine, hidden
   persistence, or an alternate action path.

The first 2.0 App Shell contract must name the Capsule Map's input projection,
canonical grouping/order rules, detail routes, and the diagnostics boundary
before visual implementation begins.

## 8. Self-Governing Architecture Map

The final 2.0 map must be generated from code and checked in CI rather than
maintained as an optimistic diagram.

Minimum generated evidence:

- capability -> owner package;
- public contract -> defining package;
- package dependency edges;
- composition-root-only concrete edges;
- facts/events -> projection owners;
- effect kind -> lifecycle owner;
- UI/drone entrypoint -> capability command.

The generator reads existing package/import metadata plus one repository-level
ownership registry. It must not require one manifest file per micro-module.
The registry describes architectural ownership only; code remains the source
for actual dependency edges.

CI fails on:

- an undeclared owner;
- two owners for one fact/effect/projection;
- a cycle or forbidden edge;
- a concrete adapter import outside composition;
- an entrypoint that bypasses a capability API;
- a registry entry with no code or a code owner absent from the registry.

## 9. Migration Rule: Strangler With Deletion

Each migrated capability follows one sequence:

1. Freeze the observed 1.x behavior with replay and golden fixtures.
2. Define the 2.0 owner and public contract.
3. Implement the deterministic core and effect ports in isolation.
4. Replay 1.x fixtures through both implementations and compare projections.
5. Switch one composition-root binding.
6. Remove or seal the 1.x path in the same migration unit.
7. Run automated gates and platform smoke tests.

There is no indefinite dual-write, dual-projection, or fallback-to-old-truth
mode. Compatibility adapters may read old data, but they emit one canonical
2.0 command/fact stream and are removed after the supported migration window.

## 10. Work Packages

### V2-0: Baseline and ownership registry

- inventory current commands, facts, projections, effects, and entrypoints;
- generate the current dependency graph;
- identify duplicate owners and service-locator surfaces;
- run the `product-axis.md` capability-closure proof for known feature families
  before choosing new Core contracts or effect ports;
- record `READY`, `NEEDS_CONTRACT`, `NEEDS_PROTOCOL`, or `REJECTED` together
  with every missing boundary;
- record the baseline entropy report without changing runtime behavior.

### V2-1: Core contract proofs

- define Capsule, Ledger, Trust, and Pair Consensus capability contracts;
- separate immutable `birth_mode` (Genesis/Proto) from runtime role
  (Leaf/future Relay);
- define Hood as a separately namespaced experimental network with isolated
  ledger, slots, operational stores, drone state, delivery, and consensus
  evidence; no shared-state network toggle is permitted;
- define canonical errors and value objects;
- prove deterministic replay with golden vectors.

### V2-2: Effect ports and durable delivery

- define storage, key, signing, clock, and delivery ports;
- bind each operation to one capsule and stable operation id;
- prove restart/retry/receipt idempotence.

### V2-3: Host and application shell

- define a capability-scoped WASM host ABI;
- make UI a projection/intent shell;
- keep drone business logic outside Hivra-App.

### V2-4: Capability-by-capability migration

- migrate one owner at a time;
- switch only at the composition root;
- delete each replaced 1.x path;
- require macOS and Android parity before calling a capability migrated.

## 11. Design Exit Criteria

Implementation of Hivra 2.0 may begin only when:

- every capability in the map has one owner and one public contract;
- persisted truth and operational evidence are distinguished explicitly;
- event and effect lifecycles have canonical identifiers;
- the forbidden dependency matrix is executable as a gate;
- 1.x compatibility fixtures and migration failure behavior are defined;
- the first migration unit names the exact code paths it will retire;
- 1.x release work can continue without importing 2.0 production code.
