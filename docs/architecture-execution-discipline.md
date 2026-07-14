# Hivra Architecture Execution Discipline v1

This document defines the execution discipline for application flows so we keep:

- strict modularity
- deterministic behavior
- dependency direction strictly downward

It is an internal Hivra standard and should be applied to all new modules and refactors.

## 1. Three Non-Negotiable Laws

1. **Modularity means one owner per responsibility.**
   - each domain fact, effect lifecycle, and projection rule has exactly one
     owner module
   - a new module must take over an existing responsibility and remove or
     narrow the old path; adding a parallel owner is not modularization
   - screens, feature facades, and runtime services must not orchestrate the
     same workflow independently
   - a module API exposes actions and results, never its internal service graph
2. **Determinism means one input route and one result.**
   - domain state is projected from ledger events
   - replaying the same ledger history yields the same projection
   - every async effect is bound to one capsule, one queue/lifecycle owner, and
     one result-application path
   - timeout, retry, refresh, or a screen switch must not create a second
     competing operation or a second truth
3. **Dependencies strictly downward means contracts down, composition up.**
   - no upward imports or lateral bypass across layer boundaries
   - UI depends on feature APIs, feature modules depend on neutral runtime
     contracts, and effects stay below those contracts
   - the application composition root is the only place that connects concrete
     implementations; generic runtime services do not assemble feature graphs

### Mandatory Change Questions

Before code is added or moved, the author must answer all four questions:

1. Who is the sole owner after this change?
2. What is the sole route of the effect from intent to persisted result?
3. Which lower-layer contract is used instead of a concrete lateral dependency?
4. Which old path, owner, or code is removed or narrowed?

If any answer is not singular and explicit, the change does not satisfy the
three laws and must not proceed as a new layer of glue.

## 2. Execution Path Contract

Every user action follows one path:

`UI intent -> use-case boundary -> runtime/FFI call -> ledger append -> projection rebuild -> UI render`

Rules:

- UI does not mutate domain state directly.
- Use-case boundaries orchestrate calls and map errors.
- Runtime/FFI boundary performs effects only.
- Projection services rebuild state from ledger events.

## 3. Effect Discipline

Effects are explicit and isolated:

- network send/receive
- key access and signing
- filesystem read/write
- clock/time lookup

Rules:

- effectful calls are made only behind runtime interfaces
- projection and policy functions remain pure for identical inputs
- side effects must not run from widget build/render paths

## 4. Async Resolution Discipline

For each async flow:

- start with one operation id
- resolve exactly once (`success` or `error`)
- ignore stale completions for superseded operations

Additional rules:

- never keep UI spinners open after the operation is resolved
- close action dialogs/snackbars immediately on submit, then show short result status
- retries must be explicit and user-visible
- a retry owner is unique per effect class; another screen or service may not
  start a competing retry loop

## 5. Projection Discipline

Projection readers are shared and centralized:

- invitation projection semantics are defined in one service
- relationship projection semantics are defined in one service
- counters and list screens consume the same projection outputs

No screen-local reinterpretation of terminal states is allowed.

## 6. Module Creation Checklist

Before adding a new module, verify:

1. It maps to an existing layer in the six-layer skeleton.
2. It names the sole owner it replaces or narrows.
3. Its action path has one queue/lifecycle and one result-application route.
4. Its dependencies point only downward through lower-layer contracts.
5. Its state output is reconstructible from ledger truth where it is domain
   state.
6. It has regression tests for replay/idempotence where applicable.

## 7. Plugin Repository Boundary

Plugin platform work is split by ownership:

- `Hivra-App` owns host/runtime boundaries, UI projection, policy guards, and catalog install flow.
- `hivra-plugins` owns plugin implementation source and plugin package release artifacts.

Rules:

- no duplicate plugin-source implementation across both repositories
- plugin behavior changes are authored in `hivra-plugins` and consumed by `Hivra-App` through host/runtime boundary
- host changes in `Hivra-App` must remain generic to plugin execution boundary, not business logic forks per plugin

## 8. Acceptance Criteria For Refactors

A refactor is considered valid only when:

- no upward dependency is introduced
- no parallel owner or parallel effect path remains
- deterministic replay behavior is unchanged or improved
- projection semantics remain aligned across summary and detail screens
- review gates and tests pass
