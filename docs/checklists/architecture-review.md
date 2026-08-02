# Architecture Review Checklist

Use this checklist when reviewing structural changes, not just feature behavior.

## Product Axis

- [ ] The change preserves the Person-First Runtime (PFR): no application,
      drone, provider, or transport becomes the owner of the person's Capsule
      identity, signed history, trusted relationships, recovery authority, or
      continuity.
- [ ] The change names the `product-axis.md` invariant it strengthens or the
      measured risk it removes.
- [ ] The change maps to the truth lane, effect lane, or both; no third state or
      effect path was introduced.
- [ ] The sole capability owner and public contract are explicit.
- [ ] The proposal has a `READY` capability-closure verdict with a complete
      `entrypoint -> command -> owner -> fact/effect -> port -> adapter -> result`
      trace.
- [ ] Every required value has a named creator, validator, persistence owner,
      version, and deletion lifecycle.
- [ ] No pass-through DTO duplicates an existing capability contract merely to
      cross a service or directory boundary.
- [ ] Adapter wire DTOs and UI view models remain private to their boundaries
      and are mapped exactly at semantic boundaries.
- [ ] Stable event/operation identity survives timeout, retry, restart, refresh,
      and capsule switching.
- [ ] Failure remains visible and fail-closed instead of becoming empty or
      successful state.
- [ ] The removed, sealed, or narrowed path is named; added structure is not
      accepted as improvement by itself.
- [ ] Replay, restart, concurrency, migration, and macOS/Android evidence are
      selected according to the changed boundary.

## Dependency Law

- [ ] Dependencies flow strictly downward.
- [ ] `hivra-core` does not depend on engine, adapters, platform, or Flutter.
- [ ] `hivra-engine` depends on `hivra-core`, not on FFI or Flutter.
- [ ] Adapters do not introduce upward dependencies.
- [ ] FFI is a boundary layer, not a second domain layer.
- [ ] Flutter dependencies flow `Screens/Widgets -> Application Use Cases -> FFI Boundary Services -> Rust`.
- [ ] Widgets do not call raw FFI directly.
- [ ] No cross-screen orchestration coupling was introduced.
- [ ] `AppRuntimeService` exposes neutral capsule/runtime primitives only; it
      does not construct AI, trading, plugin, or other feature-specific graphs.
- [ ] Feature modules assemble feature services behind explicit module/facade
      boundaries before screens consume them.
- [ ] Concrete feature graphs are assembled only by the composition root or a
      feature-module facade; generic runtime services are not service locators.

## Engine Integrity

- [ ] Engine remains the single orchestration layer for time/RNG/crypto injection.
- [ ] Engine does not absorb UI policy or rendering concerns.
- [ ] Core remains pure and deterministic with no time/RNG/crypto calls.
- [ ] Transport remains provider/adapter-only and does not reimplement Engine orchestration.
- [ ] Transport health/backoff policy follows
      `docs/checklists/transport-health-policy.md` instead of being duplicated
      inside screens or feature-specific services.

## Cryptographic Agility

- [ ] Domain identity uses `CapsuleId` semantics and does not define a Capsule
      as one public key, algorithm, public-key length, or signature length.
- [ ] Algorithm implementations remain in crypto/platform adapters; Core owns
      only versioned proof roles and deterministic acceptance policy.
- [ ] New key and signature protocol contracts use versioned, suite-tagged,
      key-id-bound, length-delimited `KeyDescriptor` and `SignatureProof`
      semantics.
- [ ] Root signing, transport signing, and transport encryption/KEM are
      separate roles with independent migration schedules.
- [ ] Nostr secp256k1 identity remains a replaceable transport identity and is
      never promoted to Capsule identity or root authority.
- [ ] Existing-Capsule migration is hybrid and append-only: one mutually bound
      checkpoint authorizes the new key and anchors the exact prior Ledger
      head; historical events are neither rewritten nor re-signed.
- [ ] Hybrid genesis is version-gated and cannot be claimed before genesis,
      recovery, downgrade, and deterministic vector contracts exist.
- [ ] A hybrid KEM transport envelope binds classical and post-quantum
      encapsulations to one sender, recipient, suite set, and ciphertext and
      reuses the canonical delivery path.
- [ ] Capsule Effect Proof uses suite-tagged signatures and can be verified
      independently from provider receipts, transport evidence, and the
      producing Hivra process.
- [ ] The change preserves one Core, one Ledger, one proof-selection path, and
      one effect lifecycle; hybrid verification does not become parallel
      classical and post-quantum owners.
- [ ] Fixed-size cryptographic compatibility shapes (`[u8; 32]`, `[u8; 64]`,
      `pubkey32`, `signature64`) do not spread beyond the explicit 1.x
      compatibility boundary enforced by the architecture gate.
- [ ] No documentation, UI, test, or release claim implies that the maintained
      1.x runtime already provides post-quantum signing or confidentiality.

## Modularity

- [ ] Domain rules live in core/engine, not inside UI widgets.
- [ ] Transport concerns are isolated to adapter and boundary code.
- [ ] Crypto concerns are isolated to adapter/platform code.
- [ ] UI reads projections instead of inventing parallel truth.
- [ ] Screens remain projection/action surfaces and do not become service
      locators for broad feature graphs.
- [ ] No new cross-cutting timer, watcher, or hidden background pipeline was introduced.
- [ ] New transport retry/receive loops share the common transport health
      policy and cannot spin independently under degraded network conditions.
- [ ] Delivery recovery follows
      `docs/architecture/transport-delivery-lifecycle.md`: one lifecycle owns
      retry timing, receipt reconciliation, and capsule-scoped pump lifetime.
- [ ] The outbox is described accurately as a recovery index unless every item
      is bound to a concrete domain-event id and matching per-event receipt.
- [ ] Any new module has explicit non-overlapping ownership.
- [ ] Every fact, effect lifecycle, and projection rule has one named owner
      after the change; the prior owner/path was removed or narrowed.
- [ ] The change records what code/path was deleted or narrowed instead of
      adding a parallel implementation.
- [ ] New modules map to one skeleton layer only (`UI Projection` | `Application Use Cases` | `Domain Core` | `Ledger` | `Transport` | `WASM Plugin Host`).
- [ ] AI/provider tooling remains outside Core and outside generic runtime
      services; it is composed through an application-level AI tooling module.

## Backup Boundary

- [ ] New user-visible Capsule exports emit only authenticated encrypted backup
      envelopes; plaintext v1/raw Ledger input remains read-only compatibility.
- [ ] A recognized encrypted envelope fails closed on suite, shape, seed, or
      authentication failure without plaintext downgrade.
- [ ] Backup codec, filesystem writer, and temporary-share cleanup each have
      one named owner; screens only collect intent and render results.
- [ ] Temporary backup artifacts are removed on success, cancellation, and
      failure, and their paths are never presented as durable saved backups.
- [ ] Seed-to-Ledger owner binding is checked before export and after decrypt;
      backup handling never mutates Core truth outside canonical Ledger import.
- [ ] Android manifest, legacy backup rules, and Android 12+ data extraction
      rules exclude all private runtime domains from cloud restore and
      device-to-device transfer; OS backup is not a second recovery path.
- [ ] Android secure-storage paths come from the active process
      `Context.filesDir`; adapters do not hardcode owner-user paths such as
      `/data/user/0`.

## Determinism

- [ ] Ledger remains the single source of truth for confirmed state.
- [ ] Import and replay are idempotent.
- [ ] Resolved history is immutable.
- [ ] Startup order is `import ledger first`, `receive second`.
- [ ] New code does not add hidden side effects to validation or lookup paths.
- [ ] Application logic does not create a second truth beside ledger-derived projection.
- [ ] Normative domain lifecycle semantics are interpreted once by the Core
      projector; Flutter, consensus, and drones do not independently replay raw
      events to derive current state.
- [ ] The consumer uses the correct canonical read model: `CurrentView` for
      effective UI state, `PairView` for pair consensus, or `HistoryView` for
      explicit audit/history.
- [ ] Persisted projection caches are disposable, version/hash-bound, and fail
      closed; no cache is accepted as a domain fact or ledger mutation input.
- [ ] Each async effect has one capsule binding, one queue/lifecycle owner, and
      one result-application route across timeout, retry, refresh, and screen
      switching.

## WASM Plugin Host

- [ ] Plugin registry/storage remains sandboxed and isolated from ledger storage.
- [ ] Plugins do not append ledger events directly.
- [ ] Plugins cannot bypass Engine validation/Core invariants.
- [ ] Transport adapters are not modeled as WASM drones; drones request delivery only through host APIs.
- [ ] Every drone method declares exactly one scope: `solo`, `market_scan`, or `pair_scoped`.
- [ ] Pair-scoped plugin execution requires explicit `peer_hex`, local
      `ConsensusRuntimeService.signable(peer_hex)`, and verified attestations
      from exactly both pair roots over the same snapshot hash.
- [ ] No pair-scoped path treats "any signable peer" as authorization for a missing or different peer.
- [ ] Market-scan/diagnostic bypasses do not send peer-scoped commands, broadcast pair-scoped intent, or execute peer-scoped effects.
- [ ] Plugin inputs/outputs are deterministic for identical inputs.
- [ ] Repo boundary is preserved: `Hivra-App` is host/runtime only; plugin implementation source/release flow lives in `hivra-plugins`.
- [ ] Plugin changes in `Hivra-App` are limited to host API/runtime boundary, install/catalog projection, and execution guards (no plugin-source duplication).
- [ ] External contract semantics execute inside ABI v2 WASM; Flutter does not mirror plugin evaluators.
- [ ] WASM execution is import-free, fuel-bounded, size-bounded, and validates canonical output hashes.

## Execution Discipline v1

- [ ] Action path follows `UI intent -> use-case boundary -> runtime/FFI call -> ledger append -> projection rebuild -> UI render`.
- [ ] Effectful operations (network, filesystem, keys, time) stay behind runtime boundaries.
- [ ] Async flows resolve once and ignore stale completions from superseded operations.
- [ ] UI action surfaces close immediately on submit, then show short result status.
- [ ] Screens consume shared projection services and do not reinterpret terminal states locally.

## AI Proposal Boundary

- [ ] Every inference path enters the single Capsule AI Runtime contract in
      `docs/architecture/capsule-ai-runtime.md`.
- [ ] No screen, drone, or feature service reads a provider credential,
      constructs a concrete inference adapter, or owns a parallel scheduler.
- [ ] The process-memory provider lease is host-owned, explicitly unlocked,
      cleared on lock/exit, and never exposed to WASM.
- [ ] A locked automatic cycle opens no OS credential dialog, creates no
      effect, and consumes no input checkpoint.
- [ ] Request/result scope binds Capsule, requesting capability, disclosure
      hash, proposal schema, budgets, and stale-completion cancellation.
- [ ] The AI path follows `docs/architecture/ai-proposal-boundary.md`; inference
      is an untrusted proposal source, not a capability owner.
- [ ] The inference adapter has no direct reference to Core mutation, effect
      execution, credentials outside its own provider scope, or another
      capability adapter.
- [ ] The proposal uses one exact bounded drone-owned schema and rejects
      unknown fields, hidden controls, malformed content, and excess size.
- [ ] Remote content, model output, and tool-call syntax cannot choose a
      capability, endpoint, account, operation id, approval, retry, or receipt.
- [ ] Deterministic capability policy remains authoritative and testable without
      trusting or replaying AI prose.
- [ ] Any external action enters the existing durable Effect Lane with stable
      identity, Capsule/plugin scope, approval policy, and receipt reconciliation.
- [ ] Bounded Delegation has explicit action/topic/target/time/rate limits, a
      kill switch, hostile-model tests, and a separate release decision.
- [ ] Provider engagement follows one canonical target identity; Assisted and
      Bounded policies cannot create parallel active effects for that target.
- [ ] Trigger modes call one cycle/use-case port and change only scheduling,
      never identity, eligibility, effect, retry, or receipt semantics.
- [ ] A succeeded target is closed, an active target is resumed, and legacy
      duplicate active targets freeze automatic delivery for explicit review.
- [ ] Prompt wording is treated only as defense in depth, never as the primary
      enforcement boundary.

## Review Gates

- [ ] `tools/review/review_all.sh` passes.
- [ ] Rust tests covering the changed behavior were added or updated.
- [ ] Flutter analysis and tests pass.
- [ ] Manual smoke scenarios were selected intentionally, not ad hoc.
