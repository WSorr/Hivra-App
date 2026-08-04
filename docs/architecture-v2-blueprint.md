# Hivra 2.0 Architecture Blueprint

Status: design-only draft. `V2-0 / passes A-E` is complete. The ownership
registry, generated baseline, owner discovery, service-locator classification,
explicit UI/Flutter-FFI surface mapping, bounded identity-family decomposition,
and exit audit are fail-closed evidence. `V2-1 / pass A` is selected for the
Capsule identity and birth contract design only. This document does not change the
normative Hivra 1.x protocol or authorize a 1.x runtime migration.

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

### Cross-Cutting Invariant: Cryptographic Agility

Domain identity, authority, and Capsule continuity do not depend on one
algorithm, public-key size, or signature size. `CapsuleId` is a Core domain
identifier, while algorithms and key material belong to role-specific
crypto/platform adapters.

The 2.0 contract uses versioned, suite-tagged, key-id-bound,
length-delimited `KeyDescriptor` and `SignatureProof` values. Root signing,
transport signing, and transport encryption/KEM are separate roles and may
migrate independently. Nostr secp256k1 identity remains transport-only.

Migration is hybrid and append-only:

- an existing Capsule appends one mutually bound migration checkpoint signed
  by the active classical root and proven by the new post-quantum key;
- the checkpoint commits to the exact prior Ledger head, Capsule, roles,
  descriptors, suite policy, and activation version;
- prior Ledger events are never rewritten or re-signed;
- subsequent verification uses one canonical policy/result path rather than a
  classical Core plus a post-quantum Core;
- a later protocol version may define hybrid genesis for new Capsules only
  after deterministic genesis and recovery vectors exist.

Confidentiality migration uses a hybrid KEM envelope behind the existing
delivery port so classical and post-quantum encapsulations bind to one sender,
recipient, suite set, and ciphertext. Capsule Effect Proof uses suite-tagged
signatures and remains independently verifiable from transport and provider
receipts.

This section is a contract target, not a claim of 1.x post-quantum runtime
support. Ed25519 replacement is deliberately gradual and controlled.

## 4. Capability Map

The map is organized by ownership, not by a growing global `services/` or
`models/` bucket.

| Capability | Sole owner | Public surface | Persisted truth | External effects |
| --- | --- | --- | --- | --- |
| Capsule identity | Core Capsule | `CapsuleId`, key-authorization commands/facts, migration checkpoint | ledger | role-specific key/signing ports |
| Network isolation | Core Capsule | network scope contract | isolated network-scoped state | transport scope validation |
| Ledger | Core Ledger | append, verify, replay | signed ledger | storage port |
| Invitations | Core Trust | invite decisions/facts | ledger | delivery port |
| Relationships | Core Trust | pair projection | ledger | none |
| Pair Consensus | Core Consensus | pair snapshot/attestation | ledger + verified evidence | signing/delivery ports |
| Delivery | Runtime Delivery | enqueue/status/receipt | durable operation journal | transport adapters |
| External service effects | Runtime External Effects | provider-scoped operation/status/receipt | durable operation journal | allowlisted provider adapters |
| Capsule AI Runtime | Host AI capability | bounded inference request/result port | process lease + bounded request evidence; never Core truth | pinned inference adapters only |
| AI proposal semantics | External drone/capability | drone-owned proposal contract | private bounded drone state or none | no direct capability effect |
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
                    /             \
       Capsule AI Runtime      Core contracts + effect ports
               |                         |
      inference adapters       Pure Core (Capsule/Ledger/Trust/Consensus)

Platform composition root -> concrete storage/crypto/transport/WASM adapters
```

The arrows above mean "may depend on" toward the stable contract. Concrete
adapters are connected by the composition root; they do not become lateral
dependencies of capability owners.

Capsule AI Runtime is a sibling host capability, not a Core service and not a
generic tool bus. Drones own proposal meaning while the runtime owns provider
sessions, disclosure, scheduling, budgets, and dispatch. Its complete contract
and 1.x migration evidence are defined in `architecture/capsule-ai-runtime.md`.

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
- inventory every fixed-size public-key/signature contract in
  Core/Engine/FFI/Flutter and keep the 1.x compatibility-boundary gate
  non-increasing;
- record the baseline entropy report without changing runtime behavior.

Selected pass A (2026-08-04):

- define one repository-level ownership-registry schema rather than one
  manifest per micro-module;
- generate current capability, public-contract, package dependency,
  composition-only concrete edge, fact/projection owner, effect owner, and
  UI/drone entrypoint evidence from 1.x code plus that registry;
- emit explicit `READY`, `NEEDS_CONTRACT`, `NEEDS_PROTOCOL`, or `REJECTED`
  closure verdicts for registered capability families;
- fail the review gate on missing code/registry entries, duplicate owners,
  dependency cycles, concrete adapter imports outside composition, or an
  entrypoint that bypasses its declared capability API;
- record entropy totals and largest remaining owner surfaces without moving
  runtime files or introducing a 2.0 DTO, facade, storage format, event, or
  executable path.

Pass A completed on 2026-08-04 with:

- the reviewed registry at `architecture/ownership-registry.v1.json`;
- the deterministic report at
  `docs/generated/architecture-ownership-baseline.md`;
- package-inventory, Rust-cycle, forbidden-edge, composition-binding,
  duplicate-owner, code-symbol, closure, and entrypoint-bypass validation in
  `tools/review/ownership_registry_gate.sh`;
- no runtime-code or production-path changes.

The baseline records twelve known capability families. `trading_drone` and
`person_runtime_shell` are explicitly `NEEDS_CONTRACT`; no placeholder 2.0
contract was added to make them appear ready. The largest registered owner
surface is the current Moltbook module composition boundary, not a new Core
owner.

Selected pass B:

- derive deterministic owner candidates from current production declarations
  and composition/service-builder surfaces;
- require every discovered candidate to be registered as a capability owner,
  classified as supporting evidence, or explicitly bounded compatibility debt;
- report service-locator and oversized owner surfaces without moving files or
  creating a replacement facade;
- keep `trading_drone` and `person_runtime_shell` contract work deferred until
  discovery proves their complete current boundaries.

Pass B completed on 2026-08-04 with:

- deterministic discovery of 158 owner-like Flutter declarations;
- 33 service/module builder surfaces restricted to eight registered
  composition roots;
- explicit classification of each candidate as a capability owner, registered
  evidence/entrypoint, composition support, supporting component, or bounded
  compatibility debt;
- zero generic service-locator pattern occurrences;
- an entropy report exposing fifteen candidate files at or above the 800-line
  review threshold, including the current Trading, Moltbook, plugin, exchange,
  persistence, chat, and invitation surfaces;
- negative tests for an unclassified owner, a builder outside composition, and
  a generic locator escaping its allowance.

The discovery does not prove that every broad `SUPPORTING_COMPONENT` or
`COMPATIBILITY_DEBT` classification has the correct future capability target.
It makes that remaining ambiguity measurable instead of silently treating each
class as an independent architecture owner.

Selected pass C:

- replace broad screen and Flutter/FFI compatibility classifications with
  explicit per-surface records and named current capability boundaries;
- map every discovered screen to a registered command entrypoint or a named
  bounded 1.x UI debt target;
- map every discovered Flutter/FFI runtime port to its owning capability and
  compatibility boundary;
- keep App Shell and Trading command-contract design deferred until those
  mappings prove their complete present-day surfaces.

Pass C completed on 2026-08-04 with:

- explicit records for all 17 discovered screen surfaces and all 18 discovered
  Flutter/FFI runtime declarations;
- seven `CANONICAL` UI entrypoints bound to their exact registered capability
  command targets;
- twenty-eight `COMPATIBILITY_DEBT` surfaces with capability-qualified targets
  and per-surface rationale;
- fail-closed rejection of missing/duplicate mappings, unknown capabilities,
  canonical target drift, and registered-entrypoint downgrade;
- removal of the broad screen and Flutter/FFI classification rules.

The resulting map exposes one new concentration rather than hiding it:
`capsule_identity` currently receives sixteen UI/FFI mappings spanning birth,
selection, addressing, backup, recovery, and settings. Treating those as one
future capability would create a god owner and violate capability closure.

Selected pass D:

- separate the current evidence into bounded birth, selection, continuity,
  recovery, and addressing capability families, plus Starter inventory where
  it is currently folded into invitations;
- name one current owner and closure verdict for each family using existing
  code only;
- update surface targets to those bounded families and fail closed if a broad
  catch-all identity assignment returns;
- introduce no new DTO, command implementation, facade, storage format, event,
  or executable route.

Pass D completed on 2026-08-04 with:

- six bounded current capability families: `capsule_birth`,
  `capsule_selection`, `capsule_continuity`, `capsule_recovery`,
  `capsule_addressing`, and `starter_inventory`;
- one existing code owner and explicit closure verdict for each family;
- seventeen UI/FFI mappings moved out of the `capsule_identity` catch-all;
- zero UI/FFI surface assignments left on the base Core identity capability;
- fail-closed policy requiring all six bounded families to retain mapped
  evidence and forbidding `capsule_identity` from returning as a surface
  catch-all;
- no runtime, Core, storage, DTO, event, facade, or executable-path change.

The six families are not declared 2.0-ready. Birth, selection, continuity, and
Starter inventory remain `NEEDS_CONTRACT`; recovery and addressing remain
`NEEDS_PROTOCOL`. The registry now names the missing boundaries instead of
allowing them to collapse back into one identity service.

Selected pass E — final `V2-0` exit audit:

- verify every `V2-0` work-package requirement against generated evidence and
  current gates;
- summarize all non-`READY` capability families and order contract/protocol
  work without implementing it;
- verify that owner discovery, dependency, composition, surface mapping,
  crypto-debt, and entropy evidence are deterministic and fail closed;
- decide whether `V2-0` can close and name at most one first `V2-1` design
  contract, but do not create that contract or any V2 runtime code in pass E.

Pass E completed on 2026-08-04 with:

- all seven V2-0 work-package requirements recorded `COMPLETE` in the generated
  exit matrix;
- deterministic evidence for 18 capability families, 161 owner candidates, 33
  composition builders, 35 explicit UI/FFI mappings, dependency edges,
  concrete bindings, crypto compatibility debt, and entropy surfaces;
- closure totals of ten `READY`, six `NEEDS_CONTRACT`, and two
  `NEEDS_PROTOCOL` capability families;
- all eight non-ready families ordered without changing their verdicts;
- explicit `runtime_implementation_authorized: false` enforced by the registry
  gate and its negative self-tests.

V2-0 is complete. It authorizes architecture contract design review only. It
does not authorize a second Core, production V2 code, runtime migration,
dual-write/projection, new persisted format, or release claim.

Selected `V2-1 / pass A` — `capsule_identity_birth_contract_v2`:

- define the design contract for `CapsuleId` as a domain identifier independent
  of key algorithm, key length, and signature length;
- define immutable Genesis/Proto `birth_mode` separately from runtime role;
- define the canonical birth command/result/fact boundary, errors, invariants,
  and deterministic golden vectors;
- define migration/removal targets against current First Launch and
  Flutter/FFI draft surfaces without implementing them;
- preserve one Core path and append-only Ledger history.

Pass A is contract/schema/fixture design only. No Rust, Flutter, FFI, storage,
crypto adapter, migration runtime, or production binding may be implemented
until the contract review and its own exit criteria are complete.

### V2-1: Core contract proofs

- define Capsule, Ledger, Trust, and Pair Consensus capability contracts;
- separate immutable `birth_mode` (Genesis/Proto) from runtime role
  (Leaf/future Relay);
- define Hood as a separately namespaced experimental network with isolated
  ledger, slots, operational stores, drone state, delivery, and consensus
  evidence; no shared-state network toggle is permitted;
- define canonical errors and value objects;
- define `CapsuleId`, suite registry rules, `KeyDescriptor`, `SignatureProof`,
  migration checkpoint, mutual key binding, hybrid genesis, downgrade, and
  recovery contracts without adding 2.0 production runtime to 1.x;
- prove deterministic replay with golden vectors.

### V2-2: Effect ports and durable delivery

- define storage, key, signing, clock, and delivery ports;
- define the hybrid KEM envelope and independently verifiable suite-tagged
  Capsule Effect Proof behind the existing delivery/effect lanes;
- bind each operation to one capsule and stable operation id;
- prove restart/retry/receipt idempotence.

### V2-3: Host and application shell

- define a capability-scoped WASM host ABI;
- make UI a projection/intent shell;
- keep drone business logic outside Hivra-App.

### V2-4: Capability-by-capability migration

- migrate one owner at a time;
- migrate root signing, transport signing, and transport encryption as
  separate role-scoped units under one checkpoint/verification policy;
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
- suite registry, variable-length encoding, mutual-binding checkpoint, hybrid
  genesis, hybrid KEM, Capsule Effect Proof, downgrade, and recovery golden
  vectors are reviewed;
- the first crypto migration preserves one CapsuleId, one Ledger history, and
  one Core verification path without rewriting or re-signing old events;
- the first migration unit names the exact code paths it will retire;
- 1.x release work can continue without importing 2.0 production code.
