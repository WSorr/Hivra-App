# Architecture Review Checklist

Use this checklist when reviewing structural changes, not just feature behavior.

## Dependency Law

- [ ] Dependencies flow strictly downward.
- [ ] `hivra-core` does not depend on engine, adapters, platform, or Flutter.
- [ ] `hivra-engine` depends on `hivra-core`, not on FFI or Flutter.
- [ ] Adapters do not introduce upward dependencies.
- [ ] FFI is a boundary layer, not a second domain layer.

## Modularity

- [ ] Domain rules live in core/engine, not inside UI widgets.
- [ ] Transport concerns are isolated to adapter and boundary code.
- [ ] Crypto concerns are isolated to adapter/platform code.
- [ ] UI reads projections instead of inventing parallel truth.
- [ ] No new cross-cutting timer, watcher, or hidden background pipeline was introduced.

## Determinism

- [ ] Ledger remains the single source of truth for confirmed state.
- [ ] Import and replay are idempotent.
- [ ] Resolved history is immutable.
- [ ] Startup order is `import ledger first`, `receive second`.
- [ ] New code does not add hidden side effects to validation or lookup paths.

## Review Gates

- [ ] `tools/review/review_all.sh` passes.
- [ ] Rust tests covering the changed behavior were added or updated.
- [ ] Flutter analysis and tests pass.
- [ ] Manual smoke scenarios were selected intentionally, not ad hoc.

