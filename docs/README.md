# Hivra Docs Map

This folder contains the canonical project documentation for the current Hivra v1 line.

## Documents

### 1) `product-axis.md` (canonical evaluation contract)

Use this before designing or reviewing any material product or architecture
change.

Contains:
- the permanent product axis and two canonical workflow lanes
- user-ownership, replay, effect-lifecycle, and isolation invariants
- predictable extension rules for drones, transports, Core, and networks
- a pre-implementation capability-closure proof and architecture runway
- a mandatory change scorecard and comparable improvement evidence

### 2) `specification.md` (normative)
Use this as the source of truth for implementation and review.

Contains:
- protocol architecture and dependency rules
- Core/Engine/Transport boundaries
- domain events, invariants, serialization rules
- role and network rules
- UI Screen Contract requirements

If there is any conflict, `specification.md` wins.

### 3) `hivra-conceptual-model.md` (product model)
Use this to understand product intent, user-facing mechanics, and behavior scenarios.

Contains:
- conceptual framing of Capsules, Starters, the Core Trust Layer, and drones
- invitation mechanics and edge-case behavior
- relay and trust model from product perspective
- documentation/comment language policy rationale

This document must stay consistent with `specification.md`.

### 4) `roadmap.md` (engineering priorities)
Use this to track the current engineering direction and the highest-value stabilization work.

Contains:
- replay safety priorities
- persist/import reliability work
- device migration safety
- release discipline and preflight expectations
- medium-term architecture and plugin-host work

### 5) `android-keystore-migration.md` (implementation note)
Use this when working on Android seed-storage hardening.

Contains:
- historical and forward-looking Android secure-storage migration notes
- target keystore-backed storage model
- migration path for existing Android users
- implementation constraints and rollout checkpoints

### 6) `identity-decoupling-migration.md` (implementation note)
Use this when working on canonical capsule identity and transport-key separation.

Contains:
- current legacy coupling between capsule identity and Nostr identity
- target root-identity model
- phased migration plan
- upgrade-safety decision points and constraints

### 7) `capsule-addressing-model.md` (design note)
Use this when working on peer addressing after root identity became canonical.

Contains:
- why `v1.0.0` send worked with one visible key
- why root identity alone is not enough for remote routing
- the public capsule card model
- trusted peer records and encrypted endpoint updates

### 8) `checklists/user-lifetime-safety-pack.md` (release safety checklist)
Use this to validate the real-world user path (one or two capsules across long-term use, restore, and update).

Contains:
- first capsule birth stability
- first relationship creation flow
- recovery-on-clean-runtime verification
- update truth-preservation checks
- pending invitation stability checks

### 9) `architecture-execution-discipline.md` (architecture execution standard)
Use this when introducing/refactoring modules and async flows.

Contains:
- the three non-negotiable architecture laws
- execution-path contract (`intent -> effect -> ledger -> projection`)
- effect and async resolution discipline
- module creation checklist and refactor acceptance criteria

### 10) `architecture/transport-delivery-lifecycle.md` (delivery architecture)
Use this when changing invitations, relationship notifications, outbox, relay
retries, or receipt handling.

Contains:
- Ledger/outbox/lifecycle/adapter/UI ownership boundaries
- canonical delivery execution path
- migration rules for durable and ephemeral transport channels
- delivery lifecycle review exit criteria

### 11) `plugins/bingx_futures_trading_drone_spec_v1.md` (trading drone spec)
Use this when implementing TVH/signal logic for the BingX futures plugin.

Contains:
- required exchange data surface for deterministic TVH
- snapshot normalization and hashing contract
- v1 entry criteria (long/short), risk filters, and output schema
- host API and capability boundary for futures intent preparation

### 12) `checklists/trading-drone-spec-runtime-parity.md` (drone parity checklist)
Use this after any drone logic change and before release packaging.

Contains:
- mandatory Hivra laws gate for the drone module
- spec-vs-runtime parity matrix
- required automated test evidence list
- required manual verification records for release candidates

### 13) `checklists/trading-drone-evidence-log.md` (drone evidence journal)
Use this to record build-tagged decision/execution evidence across macOS and Android release-candidate runs.

Contains:
- per-build parity rows (`platform x mode`)
- decision/execution envelope hash traceability
- risk-path coverage records
- deterministic coverage check command
### 14) `plugins/bingx_futures_trading_drone_goal_contract_v1.md` (drone goal contract)
Use this as the operational anchor for trading-drone development cadence.

Contains:
- source-of-truth authority stack for capsule/plugin/drone docs
- fixed v1 target outcome and boundaries
- mandatory patch->test->smoke cadence
- acceptance gates and ownership rule

### 15) `architecture-v2-blueprint.md` (design-only architecture map)

Use this when planning Hivra 2.0 in parallel with the maintained 1.x line.

Contains:
- the 1.x/2.0 version boundary
- capability ownership and dependency maps
- contract-placement and anti-entropy rules
- self-governing architecture evidence requirements
- migration work packages and design exit criteria

This document is non-normative for 1.x. `specification.md` continues to win for
all current runtime and release behavior.

### 16) `development-control.md` (current-stage navigation)

Use this at the start and end of every engineering session.

Contains:
- the current 1.x / 2.0 development board
- the exact distinction between maintenance, release, and design work
- the session protocol that keeps a change tied to one owner, invariant, and
  verification boundary

It is a navigation layer only. It links to the specification, roadmap, and
architecture blueprint rather than duplicating their rules.

## Recommended Reading Order

1. `product-axis.md`
2. `specification.md`
3. `hivra-conceptual-model.md`
4. `roadmap.md`
5. `android-keystore-migration.md` when touching Android seed storage
6. `identity-decoupling-migration.md` when touching root identity or transport key derivation
7. `capsule-addressing-model.md` when touching invitation addressing or peer endpoint resolution
8. `checklists/user-lifetime-safety-pack.md` when preparing release candidates
9. `architecture-execution-discipline.md` when designing/refactoring module boundaries and async behavior
10. `architecture/transport-delivery-lifecycle.md` when changing delivery or relay recovery
11. `plugins/bingx_futures_trading_drone_spec_v1.md` when implementing trading-drone logic
12. `plugins/bingx_futures_trading_drone_goal_contract_v1.md` to keep drone work aligned with one operational target
13. `checklists/trading-drone-spec-runtime-parity.md` before drone release packaging and manual smoke sign-off
14. `checklists/trading-drone-evidence-log.md` to capture build-tagged parity evidence
15. `architecture-v2-blueprint.md` when designing 2.0 ownership, contracts, or migration units
16. `development-control.md` before resuming, scoping, or closing any work item

## Update Rules

- Any protocol, invariant, event, or UI contract change must update `specification.md` in the same PR.
- Every material change must pass the `product-axis.md` scorecard and name its
  capability owner, lane mapping, axis gain, and removal delta.
- If product behavior/flows are affected, update `hivra-conceptual-model.md` in the same PR.
- Keep terminology consistent: Capsule, Starter, Invitation, Relationship, Ledger, Network.
- All product-bound documentation and code comments must be in English.
- 2.0 design work must not alter the normative 1.x specification until a
  capability migration is explicitly approved.

## Quick PR Checklist

- Architecture/dependency rules still valid
- Invariants still valid
- Event set and payload fields still valid
- UI contract still valid
- Conceptual flows and exceptional cases updated (if behavior changed)
