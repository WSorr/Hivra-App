# Hivra Architecture Execution Discipline v1

This document defines the execution discipline for application flows so we keep:

- strict modularity
- deterministic behavior
- dependency direction strictly downward

It is an internal Hivra standard and should be applied to all new modules and refactors.

## 1. Three Non-Negotiable Laws

1. Modularity by explicit ownership:
   - each module has one layer owner and one responsibility
   - no duplicate orchestration in screens and services at the same time
2. Determinism by ledger truth:
   - domain state is projected from ledger events
   - replaying the same ledger history yields the same projection
3. Dependencies strictly downward:
   - no upward imports
   - no lateral bypass across layer boundaries

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

## 5. Projection Discipline

Projection readers are shared and centralized:

- invitation projection semantics are defined in one service
- relationship projection semantics are defined in one service
- counters and list screens consume the same projection outputs

No screen-local reinterpretation of terminal states is allowed.

## 6. Module Creation Checklist

Before adding a new module, verify:

1. It maps to an existing layer in the six-layer skeleton.
2. It does not duplicate an existing owner.
3. Its dependencies point only downward.
4. Its state output is reconstructible from ledger truth.
5. It has regression tests for replay/idempotence where applicable.

## 7. Acceptance Criteria For Refactors

A refactor is considered valid only when:

- no upward dependency is introduced
- deterministic replay behavior is unchanged or improved
- projection semantics remain aligned across summary and detail screens
- review gates and tests pass
