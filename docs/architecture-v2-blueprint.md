# Hivra 2.0 Architecture Blueprint

Status: design-only draft. `V2-0 / passes A-E` is complete. The ownership
registry, generated baseline, owner discovery, service-locator classification,
explicit UI/Flutter-FFI surface mapping, bounded identity-family decomposition,
and exit audit are fail-closed evidence. `V2-1 / pass A` defines the Capsule
identity and birth design contract. Current work selection and status live in
`development-control.md`. This document does not change the normative Hivra
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

#### V2-1/A Capsule Identity and Birth Contract

- Contract id: `capsule_identity_birth_contract_v2`
- Contract version: `1`
- Contract boundary: design-only; no production wire format or runtime binding.

This section is the normative design source. The machine-readable schema at
`architecture/contracts/capsule-identity-birth-v2.schema.json` and semantic
vectors at `architecture/fixtures/capsule-identity-birth-v2-vectors.json` are
generated-review evidence for this section; they are not a second architecture
authority.

##### Ownership and canonical path

```text
First Launch intent
  -> BirthRequestV2
  -> Engine/application authorization verification
  -> VerifiedBirthCommandV2
  -> Core Capsule Birth transition
  -> CapsuleBornFactV2 + deterministic initial Starter plan
  -> one atomic Ledger append/result boundary
```

- Capsule Birth owns the birth decision, immutable birth fact, and accepted or
  rejected result.
- Crypto/platform adapters own `KeyDescriptorV1` and `SignatureProofV1`
  verification. They do not decide birth mode, network, Starter plan, or
  Capsule truth.
- Core receives `VerifiedBirthCommandV2`. It never receives a recovery seed,
  private key, raw signature bytes, RNG, clock, transport identity, or provider
  object.
- Starter inventory owns Starter facts. The birth result exposes a deterministic
  initial Starter plan; the later Starter contract must prove how that plan and
  `CapsuleBornFactV2` enter one atomic Core transaction before implementation.
- No runtime implementation is authorized by this contract design.

##### Contract values

`CapsuleIdV2` is an opaque, versioned, scheme-tagged, length-delimited domain
identifier:

```text
CapsuleIdV2 {
  version: 1,
  scheme_id: "hivra.capsule-id.opaque.v1",
  value: length-delimited bytes
}
```

The identifier is generated outside Core and supplied as an explicit command
value. Generation and recovery are platform/migration responsibilities and are
not silently inferred from a root key. Core validates the identifier shape,
stores it, compares it, and binds facts to it. `CapsuleIdV2.value` MUST NOT be
the raw bytes of any root, transport, signing, encryption, or KEM key.

`KeyDescriptorV1` and `SignatureProofV1` follow the permanent crypto-agility
contract: each contains `version`, `suite_id`, `key_id`, and variable-length
bytes. The proof and descriptor MUST bind the same suite and key id. Key and
signature lengths are adapter concerns and have no branch in the Core birth
transition.

`BirthModeV2` has exactly two values:

- `GENESIS`: the accepted result requests the ordered initial Starter kinds
  `JUICE`, `SPARK`, `SEED`, `PULSE`, `KICK`;
- `PROTO`: the accepted result requests no initial Starter.

`runtime_role` is not a birth request, verified command, fact, or result field.
Leaf and future Relay behavior belong to a separate runtime-role contract and
cannot alter immutable birth mode or retroactively create initial Starters.

Only `hivra.neste` is accepted by version 1. Hood remains a separately
namespaced future network design and cannot be enabled through a birth flag.

##### Request, verified command, fact, and result

`BirthRequestV2` is the application-to-verifier boundary:

```text
BirthRequestV2 {
  contract_version,
  operation_id,
  capsule_id,
  network_id,
  birth_mode,
  root_authority: KeyDescriptorV1,
  authorization_proof: SignatureProofV1
}
```

Version 1 uses three domain-separated, length-delimited commitments. Ordered
fields are encoded as a four-byte unsigned big-endian byte length followed by
the UTF-8 field bytes; each commitment is SHA-256 over the encoded domain label
followed by its encoded fields:

1. `RootAuthorityCommitmentV1` covers descriptor version, `suite_id`, `key_id`,
   and the complete variable-length public-key bytes.
2. `BirthSemanticCommitmentV1` uses domain
   `hivra/capsule-birth/semantic/v1` and covers contract version, the complete
   versioned `CapsuleIdV2`, network id, birth mode, and
   `RootAuthorityCommitmentV1`. It excludes `operation_id` to avoid circularity.
3. `operation_id` is derived with domain `hivra/capsule-birth/operation/v1`
   from `BirthSemanticCommitmentV1`. `BirthAuthorizationCommitmentV1` then uses
   domain `hivra/capsule-birth/authorization/v1` and covers both the semantic
   commitment and derived operation id.

`SignatureProofV1` is verified only over
`BirthAuthorizationCommitmentV1`. Changing CapsuleId, network, birth mode,
operation id, or any authority-descriptor field invalidates authorization.
The hash choice versions this commitment encoding; it does not define Capsule
identity or constrain future signing suites.

After adapter verification, the application boundary creates exactly one
`VerifiedBirthCommandV2`. It carries the verified semantic commitment,
`RootAuthorityRefV1`, and an opaque `authorization_evidence_id`; raw key and
proof bytes do not cross into the Core command.

An accepted transition produces exactly one `CapsuleBornFactV2` and one
deterministic initial Starter plan. The fact binds:

- contract/fact version;
- `CapsuleIdV2`;
- network id;
- immutable birth mode;
- birth operation id;
- root authority descriptor version, suite id, and key id.

It does not contain runtime role, transport identity, mutable settings, seed,
private material, raw public-key bytes, or raw signature bytes.

The transition is deterministic for the same verified command and existing
Ledger projection. The projection records `operation_id` with its semantic
commitment and accepted fact. An exact repeat returns that fact with
`REPLAYED` and appends nothing. Reusing an operation id with changed birth
semantics fails `INVALID_OPERATION_ID` because the identifier no longer matches
its deterministic derivation. A different valid operation against an existing
Capsule id returns `CAPSULE_ALREADY_EXISTS`; it does not append another fact.

##### Canonical errors

Version 1 defines these closed error codes:

- `UNEXPECTED_FIELD`;
- `UNSUPPORTED_CONTRACT_VERSION`;
- `INVALID_OPERATION_ID`;
- `INVALID_CAPSULE_ID`;
- `CAPSULE_ID_KEY_ALIAS_FORBIDDEN`;
- `UNSUPPORTED_NETWORK`;
- `INVALID_BIRTH_MODE`;
- `AUTHORITY_BINDING_MISMATCH`;
- `AUTHORIZATION_COMMITMENT_MISMATCH`;
- `AUTHORIZATION_INVALID`;
- `CAPSULE_ALREADY_EXISTS`.

Unknown fields and unknown enum values fail closed. Adapter error text is
diagnostic only and cannot become a Core decision branch or persisted fact.

##### 1.x compatibility and migration

The maintained 1.x payload remains unchanged and readable:

```text
CapsuleCreatedPayloadV1 = [network_byte, capsule_type_byte]
network_byte 1 -> hivra.neste
capsule_type_byte 1 -> GENESIS
capsule_type_byte 0 -> PROTO
```

The current Rust names `Relay = 1` and `Leaf = 0` are compatibility labels for
that byte only. They MUST NOT be copied into the V2 birth contract or used to
infer runtime role.

Existing Ledger events are never rewritten, re-signed, or replaced with
`CapsuleBornFactV2`. An existing 1.x Capsule receives an opaque `CapsuleIdV2`
only through a future append-only migration checkpoint mutually bound to the
active classical authority and exact prior Ledger head. Until that checkpoint
contract exists, the 1.x root-key identity alias remains isolated at the
compatibility boundary and MUST NOT be presented as a native V2 CapsuleId.

New V2 birth and 1.x import cannot be dual-written. A future composition switch
must select one canonical result path after fixture parity, seal the old write
entrypoint, and retain the old payload decoder for the declared read window.

##### Replacement and sealing targets

The future migration unit must replace or seal, not wrap indefinitely:

- `FirstLaunchService.createCapsuleDraft(String type)` and its stringly typed
  `genesis`/`proto` choice;
- `CapsuleDraftRuntime.createCapsuleError(... isGenesis ...)`;
- `HivraBindings.createCapsule(... isGenesis ...)` and direct
  `capsuleType` byte construction;
- `CapsuleType::Leaf/Relay` where it currently carries birth meaning;
- writable uses of `CapsuleCreatedPayload.capsule_type`;
- duplicated `isGenesis` bootstrap/cache truth once Ledger projection and the
  migration window prove replacement safety.

The old `CapsuleCreated` reader, old Ledger verification, and recovery of
supported 1.x histories remain compatibility inputs. They do not become a
second Core path.

##### Semantic golden vectors and exit rule

The checked-in vectors cover:

- accepted Proto birth with a current classical key shape;
- accepted Genesis birth with different key and signature lengths;
- exact Genesis and Proto Starter plans;
- rejection of `runtime_role` and `LEAF` as birth inputs;
- rejection of CapsuleId/public-key aliasing;
- proof/descriptor binding mismatch;
- exact proof binding to CapsuleId, network, birth mode, operation id, and the
  complete authority descriptor;
- exact idempotent replay and rejection of operation-id reuse with changed
  semantics;
- invalid authorization evidence;
- duplicate Capsule birth;
- unsupported contract version and network;
- invalid operation and Capsule identifiers.

These are semantic vectors, not a production JSON or binary wire-format
commitment. A later implementation pass must choose canonical encoding only
with schema versioning, length delimiting, cross-language fixtures, and removal
targets approved together.

Pass A review exits only when the blueprint, schema, vectors, validator
negative mutations, ownership registry, and full repository review agree. Exit
closes the reviewed design contract; it does not authorize implementation or
automatically select the next contract.

Pass A review evidence:

- the normative blueprint contract above;
- a strict draft-2020-12 schema with opaque variable-length CapsuleId,
  suite-tagged variable-length authority/proof values, exact birth modes,
  closed errors, and no runtime-role field;
- semantic vectors covering accepted Genesis/Proto behavior, exact replay,
  changed-operation rejection, exact authorization binding, variable key/proof
  sizes, identifier separation, duplicate birth, and malformed inputs;
- standard draft-2020-12 validation plus negative mutations for an empty root,
  proof-binding weakening, missing vectors, and semantic drift;
- explicit 1.x read compatibility plus append-only migration and removal/sealing
  targets;
- zero Rust, Flutter, FFI, storage, adapter, persisted-format, or production
  binding changes.

Selection of a later contract is outside this normative section. The current
work item and next decision are recorded only in `development-control.md`, with
history and debt retained in `roadmap.md`.

#### V2-1/B Starter Inventory and Genesis Seed Contract

- Contract id: `starter_inventory_contract_v2`
- Contract version: `1`
- Contract boundary: design-only; no production event, storage, FFI, Flutter,
  or runtime binding.

This section is the normative design source. The schema at
`architecture/contracts/starter-inventory-v2.schema.json` and vectors at
`architecture/fixtures/starter-inventory-v2-vectors.json` are machine-readable
evidence only.

##### Ownership and canonical path

Starter Inventory is the sole owner of Starter lifecycle facts, slot occupancy,
and the canonical inventory current view. Capsule Birth remains the owner of
the birth decision and `CapsuleBornFactV2`. Invitation owns invitation status
and reservation/lock meaning; `LOCKED` is not a Starter lifecycle state.

```text
VerifiedBirthCommandV2
  -> Capsule Birth transition
  -> Starter Inventory pure Genesis seed plan
  -> one Core atomic fact batch
     GENESIS: CapsuleBornFactV2 + five StarterCreatedFactV2
     PROTO:   CapsuleBornFactV2
  -> one Ledger append/result boundary
```

There is no `SeedStartersCommand`, second operation id, second birth result, or
post-birth repair route. Exact birth replay returns the prior result and appends
nothing. Failure to produce the complete ordered batch appends nothing.

##### Values, facts, and current view

`StarterIdV2` is a versioned, scheme-tagged, length-delimited domain identifier;
it is not a root, transport, signing, encryption, or KEM key. Genesis Starter
ids use scheme `hivra.starter-id.genesis.v1` and are derived from the exact
birth semantic commitment, derived birth operation id, CapsuleId, network,
slot index, and Starter kind with domain `hivra/starter-id/genesis/v1`. The v1
commitment encoding reuses the length-delimited SHA-256 convention defined by
Pass A without making Capsule or Starter identity depend permanently on SHA-256.

`StarterKindV1` remains the closed ordered set `JUICE`, `SPARK`, `SEED`,
`PULSE`, `KICK`. Inventory capacity is five slots indexed `0..4`. Kind is not a
general slot property: only the Genesis seed plan maps that ordered kind set to
slots `0..4`. Pass B does not define later Starter creation or authorize reuse
of the Genesis identifier scheme; that requires a separately reviewed
capability contract before runtime work.

`StarterCreatedFactV2` binds StarterId, CapsuleId, network, slot, kind, and the
single operation that created it. `StarterBurnedFactV2` binds StarterId,
CapsuleId, network, the consuming operation, and a versioned closed reason.
Burn is terminal for one StarterId; the same id can never reactivate.

`StarterInventoryViewV1` is reconstructed only from accepted Starter facts in
Ledger order. It exposes exactly five `EMPTY` or `ACTIVE` slots and the Ledger
head commitment used for projection. It does not expose `LOCKED`, invitation
status, relationship truth, UI labels, or historical audit. Reservation is a
separate composition of this view with the canonical Invitation current view.

Projection fails closed on duplicate StarterId, occupied-slot creation,
Capsule/network mismatch, unknown reason, burn of an unknown Starter, or
reactivation after burn. Malformed and foreign-scope facts cannot become empty
or successful inventory state.

##### Deterministic Genesis seed plan and atomicity

For `GENESIS`, the pure plan contains exactly these ordered entries:

| Ordinal | Slot | Kind |
| --- | --- | --- |
| 0 | 0 | `JUICE` |
| 1 | 1 | `SPARK` |
| 2 | 2 | `SEED` |
| 3 | 3 | `PULSE` |
| 4 | 4 | `KICK` |

Each entry carries its derived `StarterIdV2`. For `PROTO`, the plan is empty.
The plan consumes the already verified Pass A command; it does not receive raw
proof, key bytes, seed, nonce, RNG, clock, or transport identity.

The Core transaction validates the complete plan before append. A Genesis
transaction commits the birth fact and all five Starter facts in canonical
order or commits zero facts. Persisting only the birth fact, any subset of the
Starter facts, reordered facts, duplicate slots, wrong kinds, or ids derived
from another Capsule/network/birth commitment returns
`NON_ATOMIC_BIRTH_BATCH` or the narrower closed validation error and appends
nothing.

##### Closed errors

Version 1 defines `INVALID_GENESIS_PLAN`, `INVALID_STARTER_ID`,
`INVALID_STARTER_FACT`,
`CAPSULE_SCOPE_MISMATCH`, `NETWORK_SCOPE_MISMATCH`, `DUPLICATE_STARTER_ID`,
`SLOT_OCCUPIED`, `STARTER_NOT_FOUND`, `STARTER_ALREADY_BURNED`, and
`NON_ATOMIC_BIRTH_BATCH`. Adapter text remains diagnostic and cannot become a
Core branch or fact.

##### 1.x compatibility and sealing targets

Maintained 1.x history remains readable and is never rewritten. Its fixed
32-byte `StarterId`, seed/slot derivation, `StarterCreatedPayload`,
`StarterBurnedPayload`, and first-free `SlotLayout` replay are compatibility
inputs, not V2 contracts. A future migration checkpoint derives V2 Starter ids
and slot facts from the exact accepted 1.x Ledger order without dual-write.

The implementation migration must replace or seal:

- the Genesis Starter loop in `platform/hivra-ffi/src/runtime_support.rs`;
- direct FFI `derive_starter_id` / `derive_starter_nonce` policy;
- per-slot `hivra_starter_get_id`, `hivra_starter_get_type`, and
  `hivra_starter_exists` probes after one versioned inventory view is bound;
- Dart reconstruction of Starter kinds and invitation locks in
  `LedgerViewService`;
- writable fixed-size `StarterId` assumptions outside the declared 1.x
  compatibility boundary.

Old event decoders remain for the declared read window. No V2 runtime work is
authorized until vectors prove exact Genesis/Proto plans, all-or-none append,
idempotent replay, terminal burn, scope isolation, and deterministic current
view through one Core path.

#### V2-1/C Capsule Continuity Export Contract

- Contract id: `capsule_continuity_export_contract_v2`
- Contract version: `1`
- Contract boundary: design-only application contract; no Core fact, recovery
  protocol, production wire format, storage, FFI, Flutter, or runtime binding.

This section is the normative design source. The schema at
`architecture/contracts/capsule-continuity-export-v2.schema.json` and vectors
at `architecture/fixtures/capsule-continuity-export-v2-vectors.json` are
machine-readable evidence only.

##### Ownership and canonical path

Capsule Continuity owns export intent, exact snapshot binding, authorization
scope, operation replay, and prepared-artifact evidence. Ledger/Core remains
the sole owner of history truth and the immutable export snapshot. The crypto
and backup codec adapter owns artifact encoding. The filesystem writer owns a
durable write receipt, and Temporary Backup Share owns disposable share-file
cleanup. Recovery owns import, migration, owner verification, and history
anchoring; export cannot call or define recovery.

```text
ContinuityExportRequestV1
  -> resolve exact Ledger/Core snapshot
  -> verify local export authority
  -> VerifiedContinuityExportCommandV1
  -> existing authenticated backup codec profile
  -> ContinuityArtifactEvidenceV1
  -> one prepared result
  -> future V2-2 storage/share effect receipt
```

There is no second Ledger export route, no Core event, no export-owned recovery
command, and no screen-owned serialization or write path. Raw seed, key,
mnemonic, proof bytes, destination path, clock, nonce, salt, ciphertext, and
filesystem receipt do not enter the continuity command.

##### Request, snapshot, and operation identity

`ContinuitySnapshotV1` binds CapsuleId, network, Ledger head commitment, event
count, canonical Ledger export commitment, and continuity metadata commitment.
Its domain-separated semantic commitment covers every field using the
length-delimited convention from Pass A. An active snapshot mismatch fails
closed; export never silently advances to a newer head after authorization.

`ContinuityExportRequestV1` binds contract version, operation id, the complete
snapshot, and artifact profile `hivra.capsule_backup.v2`. The request commitment
is domain-separated and covers the exact snapshot commitment. The operation id
is caller-created opaque intent identity: an exact repeat is idempotent and may
return the prior prepared result, while the same id with another request
commitment returns `OPERATION_ID_CONFLICT`.

The only allowed v1 artifact profile names the maintained authenticated 1.x
backup envelope as a compatibility output. It does not redefine that wire
format and does not authorize a second or future V2 backup format. Plaintext v1
and raw Ledger output are never allowed for a new user-visible export.

##### Authorization and prepared evidence

Platform crypto verifies local Capsule export authority over the exact request
commitment. `VerifiedContinuityExportCommandV1` carries only the verified
request, request commitment, and opaque authorization evidence id. A boolean
`valid`, raw proof, seed, key, or mnemonic is not accepted as authority.

`ContinuityArtifactEvidenceV1` binds operation id, request commitment, snapshot
commitment, artifact profile, suite-tagged variable-length artifact digest, and
artifact byte length. `ContinuityExportResultV1` is `PREPARED` or `REPLAYED`
and carries that exact evidence. It is not a filesystem or share receipt and
cannot claim durability, publication, recovery, or import success.

Artifact randomness belongs to the codec adapter. Exact operation replay must
return the previously recorded evidence rather than silently create a second
artifact. Crash/write reconciliation and durable effect receipts belong to the
future V2-2 effect contract and are not invented here.

##### Closed rejection and sealing targets

Version 1 defines `INVALID_REQUEST`, `OPERATION_ID_CONFLICT`,
`CAPSULE_SCOPE_MISMATCH`, `NETWORK_SCOPE_MISMATCH`, `SNAPSHOT_STALE`,
`SNAPSHOT_COMMITMENT_MISMATCH`, `AUTHORIZATION_REQUIRED`,
`AUTHORIZATION_SCOPE_MISMATCH`, `PROFILE_NOT_ALLOWED`, and
`ARTIFACT_EVIDENCE_MISMATCH`. Rejection appends no Core fact and produces no
artifact or downstream write obligation.

The implementation migration must replace or seal:

- `BackupService` methods that pass raw seed and target path as capability
  intent;
- `BackupRuntime` ownership of mnemonic generation and post-birth persistence;
- direct `CapsulePersistenceService` composition of snapshot selection, seed
  binding, codec invocation, and filesystem destination;
- screen-selected export/share routes that can appear to be separate
  continuity operations;
- any attempt to treat internal plaintext snapshots, paths, or recovery import
  results as continuity export success.

No V2 runtime work is authorized until vectors prove full snapshot binding,
authorization binding, exact replay, operation conflict, stale/wrong scope
rejection, authenticated-profile enforcement, and exact artifact evidence.

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
