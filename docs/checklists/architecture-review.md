# Architecture Review Checklist

Use this checklist when reviewing structural changes, not just feature behavior.

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

## Engine Integrity

- [ ] Engine remains the single orchestration layer for time/RNG/crypto injection.
- [ ] Engine does not absorb UI policy or rendering concerns.
- [ ] Core remains pure and deterministic with no time/RNG/crypto calls.
- [ ] Transport remains provider/adapter-only and does not reimplement Engine orchestration.
- [ ] Transport health/backoff policy follows
      `docs/checklists/transport-health-policy.md` instead of being duplicated
      inside screens or feature-specific services.

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
- [ ] New modules map to one skeleton layer only (`UI Projection` | `Application Use Cases` | `Domain Core` | `Ledger` | `Transport` | `WASM Plugin Host`).
- [ ] AI/provider tooling remains outside Core and outside generic runtime
      services; it is composed through an application-level AI tooling module.

## Determinism

- [ ] Ledger remains the single source of truth for confirmed state.
- [ ] Import and replay are idempotent.
- [ ] Resolved history is immutable.
- [ ] Startup order is `import ledger first`, `receive second`.
- [ ] New code does not add hidden side effects to validation or lookup paths.
- [ ] Application logic does not create a second truth beside ledger-derived projection.

## WASM Plugin Host

- [ ] Plugin registry/storage remains sandboxed and isolated from ledger storage.
- [ ] Plugins do not append ledger events directly.
- [ ] Plugins cannot bypass Engine validation/Core invariants.
- [ ] Transport adapters are not modeled as WASM drones; drones request delivery only through host APIs.
- [ ] Every drone method declares exactly one scope: `solo`, `market_scan`, or `pair_scoped`.
- [ ] Pair-scoped plugin execution requires explicit `peer_hex` and is gated by `ConsensusRuntimeService.signable(peer_hex)`.
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

## Review Gates

- [ ] `tools/review/review_all.sh` passes.
- [ ] Rust tests covering the changed behavior were added or updated.
- [ ] Flutter analysis and tests pass.
- [ ] Manual smoke scenarios were selected intentionally, not ad hoc.
