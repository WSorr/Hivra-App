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

## Engine Integrity

- [ ] Engine remains the single orchestration layer for time/RNG/crypto injection.
- [ ] Engine does not absorb UI policy or rendering concerns.
- [ ] Core remains pure and deterministic with no time/RNG/crypto calls.
- [ ] Transport remains provider/adapter-only and does not reimplement Engine orchestration.

## Modularity

- [ ] Domain rules live in core/engine, not inside UI widgets.
- [ ] Transport concerns are isolated to adapter and boundary code.
- [ ] Crypto concerns are isolated to adapter/platform code.
- [ ] UI reads projections instead of inventing parallel truth.
- [ ] No new cross-cutting timer, watcher, or hidden background pipeline was introduced.
- [ ] Any new module has explicit non-overlapping ownership.
- [ ] New modules map to one skeleton layer only (`UI Projection` | `Application Use Cases` | `Domain Core` | `Ledger` | `Transport` | `WASM Plugin Host`).

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
- [ ] Pair-scoped plugin execution is gated by consensus guard readiness.
- [ ] Plugin inputs/outputs are deterministic for identical inputs.

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
