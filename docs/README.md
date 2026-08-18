# Hivra Docs Map

This folder contains the canonical project documentation for the current Hivra v1 line.

## Documents

### 1) `product-axis.md` (canonical evaluation contract)

Use this before designing or reviewing any material product or architecture
change.

Contains:
- the Person-First Runtime (PFR) architectural category
- the permanent product axis and two canonical workflow lanes
- user-ownership, replay, effect-lifecycle, and isolation invariants
- cryptographic agility as a permanent algorithm- and size-independent
  identity/authority invariant
- predictable extension rules for drones, transports, Core, and networks
- a pre-implementation capability-closure proof and architecture runway
- a mandatory change scorecard and comparable improvement evidence

### 2) `specification.md` (normative)
Use this as the source of truth for implementation and review.

Contains:
- protocol architecture and dependency rules
- Core/Engine/Transport boundaries
- `CapsuleId`, suite-tagged proof, hybrid migration, and fixed-size 1.x
  compatibility-debt rules
- domain events, invariants, serialization rules
- role and network rules
- UI Screen Contract requirements

If there is any conflict, `specification.md` wins.

### 3) `hivra-conceptual-model.md` (product model)
Use this to understand product intent, user-facing mechanics, and behavior scenarios.

Contains:
- the Person-First Runtime (PFR) definition and person/user/Capsule distinction
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

### Generated architecture evidence

- `generated/architecture-ownership-baseline.md` is the deterministic current
  ownership, dependency, closure, composition-binding, and owner-surface report.
- Its source registry is `../architecture/ownership-registry.v1.json`; update
  the registry or generator, never the generated report by hand.

### 5) `android-keystore-migration.md` (implementation note)
Use this when working on Android seed-storage hardening.

Contains:
- historical and forward-looking Android secure-storage migration notes
- target keystore-backed storage model
- migration path for existing Android users
- implementation constraints and rollout checkpoints

### 6) `identity-decoupling-migration.md` (implementation note)
Use this for the completed 1.x root/transport-key separation. Use
`product-axis.md`, `specification.md`, and `architecture-v2-blueprint.md` for
the target crypto-agile identity contract.

Contains:
- current legacy coupling between capsule identity and Nostr identity
- maintained 1.x Ed25519 root-signing model and its 2.0 limitation
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

### 11) `architecture/capsule-scoped-secret-lifecycle.md` (secret lifecycle)
Use this when adding plugin/provider credentials or changing Capsule/plugin
deletion.

Contains:
- the single Secure Storage vault owner
- Capsule/plugin/provider/account secret scope
- fail-closed parsing and serialized updates
- mandatory Capsule deletion and plugin removal cleanup

Contains:
- Ledger/outbox/lifecycle/adapter/UI ownership boundaries
- canonical delivery execution path
- migration rules for durable and ephemeral transport channels
- delivery lifecycle review exit criteria

### 12) `architecture/external-effect-lifecycle.md` (provider effect architecture)
Use this when adding a durable non-Core action against an exchange, content
provider, wallet, or another external system.

Contains:
- the single External Effects ownership boundary
- canonical operation states, persistence scope, and receipts
- timeout, restart, reconciliation, cancellation, and stale-result rules
- the strict separation from Core truth and transport delivery

### 13) `architecture/ai-proposal-boundary.md` (AI capability architecture)

Use this for every AI-assisted or delegated drone capability.

Contains:
- the Hivra-specific split between untrusted inference and authority
- prompt-injection invariants enforced without relying on prompts
- disclosure, proposal, deterministic decision, effect, and receipt ownership
- Observe, Assisted, and Bounded Delegation release requirements
- reference mappings for Moltbook, trading, and staking drones

### 14) `architecture/capsule-ai-runtime.md` (shared inference runtime)

Use this when adding an AI-enabled feature, provider, local model, credential
flow, inference scheduler, or WASM inference host capability.

Contains:
- the single Capsule AI Runtime owner and public request path
- provider/session, disclosure, scheduling, and proposal boundaries
- the rule that WASM receives inference capability but never credentials
- the incremental 1.x convergence path and mandatory Hivra 2.0 contract

### 15) `plugins/bingx_futures_trading_drone_spec_v1.md` (trading drone spec)
Use this when implementing TVH/signal logic for the BingX futures plugin.

Contains:
- required exchange data surface for deterministic TVH
- snapshot normalization and hashing contract
- v1 entry criteria (long/short), risk filters, and output schema
- host API and capability boundary for futures intent preparation

### 16) `checklists/trading-drone-spec-runtime-parity.md` (drone parity checklist)
Use this after any drone logic change and before release packaging.

Contains:
- mandatory Hivra laws gate for the drone module
- spec-vs-runtime parity matrix
- required automated test evidence list
- required manual verification records for release candidates

### 17) `checklists/trading-drone-evidence-log.md` (drone evidence journal)
Use this to record build-tagged decision/execution evidence across macOS and Android release-candidate runs.

Contains:
- per-build parity rows (`platform x mode`)
- decision/execution envelope hash traceability
- risk-path coverage records
- deterministic coverage check command

### 18) `plugins/bingx_futures_trading_drone_goal_contract_v1.md` (drone goal contract)
Use this as the operational anchor for trading-drone development cadence.

Contains:
- source-of-truth authority stack for capsule/plugin/drone docs
- fixed v1 target outcome and boundaries
- mandatory patch->test->smoke cadence
- acceptance gates and ownership rule

### 19) `architecture-v2-blueprint.md` (design-only architecture map)

Use this when planning Hivra 2.0 in parallel with the maintained 1.x line.

Contains:
- the 1.x/2.0 version boundary
- capability ownership and dependency maps
- contract-placement and anti-entropy rules
- self-governing architecture evidence requirements
- migration work packages and design exit criteria

This document is non-normative for 1.x. `specification.md` continues to win for
all current runtime and release behavior.

### 20) `development-control.md` (current-stage navigation)

Use this at the start and end of every engineering session.

Contains:
- the current 1.x / 2.0 development board
- the exact distinction between maintenance, release, and design work
- the session protocol that keeps a change tied to one owner, invariant, and
  verification boundary

It is a navigation layer only. It links to the specification, roadmap, and
architecture blueprint rather than duplicating their rules.

### 21) `plugins/moltbook_agent_drone_design_v1.md` (Moltbook drone contract)

Use this when evaluating an optional Capsule-operated Moltbook presence.

Contains:
- Capsule/Moltbook identity separation
- remote-versus-local data authority and storage ownership
- WASM, host adapter, external-effect, inference, and UI boundaries
- Observe, Assisted, and Bounded Interactive operating modes
- recovery, prompt-injection, credential, and publication safety contracts

The canonical per-target reply lifecycle and automatic/session scheduling
rules are separated into
`plugins/moltbook_engagement_lifecycle_v1.md`. Use it whenever changing
engagement identity, Assisted/Bounded orchestration, catch-up, continuous
operation, challenge handling, or duplicate prevention.

This document describes the implemented Observe and Assisted publication
boundaries, the foreground bounded-reply experiment, and the gated automatic
evolution track. WASM remains deterministic and effect-free; remote reads and
writes run only through host-owned adapters and the External Effects lifecycle.

### 22) `docs/platform-toolchain-evolution.md` (platform evolution contract)

Use this when changing or evaluating Flutter/Dart, Rust/Cargo, Android SDK,
AGP/Gradle/Kotlin/JDK/NDK, Xcode, or CocoaPods.

Contains:
- the verified macOS and Android toolchain matrix
- stable C-ABI boundary rules
- dedicated upgrade units and their required evidence
- Android signing and macOS packaging constraints

It explicitly forbids hiding an SDK migration inside product or protocol work.

### 23) `architecture/continuous-ledger-protocol-v5.md` (ledger protocol contract)

Use this when reviewing the implemented v5 continuous-ledger protocol or its
v4 compatibility boundary.

Contains:
- the v5 split between signed domain provenance and locally signed history
- the exact ordering and verification commitments
- v4 compatibility, migration-anchor, and read-only safety rules
- implementation units and adversarial evidence required before release

It records the implemented replacement for the v4 replay checksum. Fresh
runtimes and append paths use v5; v4 remains a guarded migration input.

### 24) `external-agent-runtime-pattern-audit.md` (research record)

Use this only when evaluating personal-agent operations, approvals, AI context,
artifacts, or runtime-health UX against Hivra's existing owners and laws.

Contains:
- anonymized external personal-agent runtime observations;
- patterns that may be adapted without adding a second lifecycle owner;
- patterns rejected by Hivra authority and Ledger boundaries;
- a forward scenario model centered on persistent principal, durable intent,
  bounded mandate, effect evidence, receipt, and reconciliation;
- a non-authorizing Remote Runner readiness fact and revisit trigger.

## Recommended Reading Order

1. `development-control.md`
2. `product-axis.md`
3. `specification.md`
4. the selected `roadmap.md` item and its owning architecture contract
5. `hivra-conceptual-model.md` for product-language context
6. `android-keystore-migration.md` when touching Android seed storage
7. `identity-decoupling-migration.md` when touching root identity or transport key derivation
8. `capsule-addressing-model.md` when touching invitation addressing or peer endpoint resolution
9. `checklists/user-lifetime-safety-pack.md` when preparing release candidates
10. `architecture-execution-discipline.md` when designing/refactoring module boundaries and async behavior
11. `architecture/transport-delivery-lifecycle.md` when changing delivery or relay recovery
12. `plugins/bingx_futures_trading_drone_spec_v1.md` when implementing trading-drone logic
13. `plugins/bingx_futures_trading_drone_goal_contract_v1.md` to keep drone work aligned with one operational target
14. `checklists/trading-drone-spec-runtime-parity.md` before drone release packaging and manual smoke sign-off
15. `checklists/trading-drone-evidence-log.md` to capture build-tagged parity evidence
16. `architecture-v2-blueprint.md` when designing 2.0 ownership, contracts, or migration units
17. `plugins/moltbook_agent_drone_design_v1.md` when planning the Moltbook future track
18. `docs/platform-toolchain-evolution.md` before changing the native build stack
19. `architecture/continuous-ledger-protocol-v5.md` before changing ledger signing, import, or persistence
20. `external-agent-runtime-pattern-audit.md` when evaluating external personal-agent runtime patterns

## Supporting Index

The detailed entries above cover the primary reading path. The remaining
checked-in documents have these narrower owners:

- `architecture/plugin-package-lifecycle.md`: transactional plugin package
  install, update, removal, recovery, and registry/file ownership.
- `plugins/plugin_host_api_v1.md`,
  `plugins/bingx_futures_trading_test_plugin.md`, and
  `plugins/external_plugin_source.md`: plugin ABI, test-package, and external
  source contracts.
- `checklists/architecture-review.md`: mandatory architecture review gate for
  selected implementation work.
- `checklists/manual-smoke.md`, `checklists/release-macos.md`,
  `checklists/release-android.md`, and
  `checklists/release-manual-signoff-log.md`: release-candidate execution and
  evidence; unchecked boxes are templates until a candidate is named.
- `checklists/device-migration.md`,
  `checklists/android-runtime-hardening.md`, and
  `checklists/transport-health-policy.md`: focused recovery, Android, and
  transport-health evidence.
- `checklists/ai-engineer-release-smoke.md` and
  `checklists/moltbook-release-smoke.md`: feature-specific release smoke that
  activates only when its surface changes or a release checklist requires it.

No document in this supporting index owns the current priority. Current work
selection remains exclusively in `development-control.md` and `roadmap.md`.
20. `architecture/ai-proposal-boundary.md` before connecting inference to any drone capability or external effect

## Update Rules

- Any protocol, invariant, event, or UI contract change must update `specification.md` in the same PR.
- Every material change must pass the `product-axis.md` scorecard and name its
  capability owner, lane mapping, axis gain, and removal delta.
- If product behavior/flows are affected, update `hivra-conceptual-model.md` in the same PR.
- Keep terminology consistent: Capsule, Starter, Invitation, Relationship, Ledger, Network.
- All tracked repository text must be in English. Spoken conversation is the
  only language-policy exception; Cyrillic text is rejected by repository gates.
- 2.0 design work must not alter the normative 1.x specification until a
  capability migration is explicitly approved.

## Quick PR Checklist

- Architecture/dependency rules still valid
- Invariants still valid
- Event set and payload fields still valid
- UI contract still valid
- Conceptual flows and exceptional cases updated (if behavior changed)
