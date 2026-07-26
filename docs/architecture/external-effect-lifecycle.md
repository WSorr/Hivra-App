# External Effect Lifecycle v1

## Purpose

External Effects is the single application-runtime owner for durable actions
against an external provider that are not Core facts. Examples include
publishing provider content, placing an exchange order, or invoking a future
wallet adapter.

This lifecycle implements the effect lane from `docs/product-axis.md`:

```text
explicit intent
  -> capability policy
  -> stable operation
  -> approval when required
  -> External Effects lifecycle
  -> provider-neutral adapter port
  -> provider adapter
  -> reconcile
  -> terminal receipt or terminal failure
```

It is not a second ledger, a transport outbox, a plugin-owned retry loop, or a
provider SDK abstraction.

## Ownership Boundary

| Owner | Owns | Must not own |
| --- | --- | --- |
| Core/Ledger | Signed Hivra domain facts | Provider attempts or receipts |
| Drone | Deterministic proposal and provider-neutral capability request | Credentials, HTTP, retry timing, or durable effect state |
| External Effects | Operation identity, lifecycle transitions, attempts, restart recovery, reconciliation, cancellation, terminal receipt | Provider DTO, Core projection, transport delivery, or UI state |
| Provider adapter | Credential use, provider request/response mapping, remote reconciliation | Operation policy, approval, ledger truth, or plugin state |
| UI | Intent, exact preview, approval, status rendering | Direct provider calls or retry loops |

`ExternalEffectService` is the sole lifecycle owner. Provider adapters implement
`ExternalEffectAdapter`. Composition belongs to `PluginRuntimeModuleService`;
screens and `AppRuntimeService` do not become provider service locators.

## Scope And Persistence

Every journal is isolated by:

```text
(capsule_root_hex, plugin_id)
```

The canonical file is:

```text
capsules/<capsule_root_hex>/plugin_state/<plugin_id>/external_effects.v1.json
```

One operation contains:

- stable `operation_id`;
- owner Capsule and plugin id;
- provider id and opaque account-binding reference;
- effect kind;
- canonical JSON object and SHA-256 payload hash;
- approval evidence hash;
- attempt count and monotonic revision;
- lifecycle state and bounded diagnostic error;
- optional bounded provider-required action while unresolved;
- terminal provider receipt when successful.

An operation never contains a credential. Adapter requests carry the immutable
owner Capsule and plugin scope so credential lookup remains bound to the
operation after Capsule switching or restart. Credential material remains in
the provider adapter's platform secure-storage boundary.

The journal uses the Capsule atomic file writer. Its top-level Capsule/plugin
scope and every operation scope must match exactly. Duplicate operation ids,
unsupported schemas, malformed payloads, and scope mismatches fail closed.
When the bounded journal reaches 1000 entries, only oldest terminal entries may
be pruned toward 800 entries. Non-terminal work is never discarded to make
space.

Uninstall removes the plugin state directory from every local Capsule. Capsule
deletion removes the directory as part of Capsule state deletion.

## Canonical States

```text
prepared
  -> approved
  -> queued
  -> delivering
  -> succeeded
  -> terminal_failure

delivering -> unresolved
unresolved -> reconcile -> succeeded | terminal_failure | unresolved
unresolved -> reconcile(not_found) -> queued
unresolved(required_action) -> explicit response -> succeeded | terminal_failure | unresolved
prepared | approved | queued -> cancelled
```

`succeeded`, `terminal_failure`, and `cancelled` are terminal. Only
`succeeded` may contain a receipt.

Approval is bound to an immutable evidence hash. Repeating approval with
different evidence fails closed. Reusing an operation id with different
provider, account binding, effect kind, or payload hash also fails closed.

## Delivery And Reconciliation Rules

1. A timeout or adapter exception becomes `unresolved`, never `succeeded`.
2. An unresolved operation reconciles provider state before another delivery.
3. `not_found` may return the same semantic operation to `queued`; retry never
   invents a new operation id.
4. A process restart that finds `delivering` changes it to `unresolved` and
   reconciles before delivery.
5. Calls for the same Capsule/plugin/operation share one in-flight execution
   inside the runtime.
6. Durable writes are compare-and-apply operations bound to the expected state
   and revision. A late adapter result cannot overwrite a newer reconciliation
   result or downgrade a terminal receipt.
7. Completion remains bound to the Capsule that started the operation even if
   the selected Capsule changes.
8. Cancellation is allowed only before delivery starts. Remote cancellation,
   when supported, is a separate explicit effect rather than a local state
   rewrite.
9. A provider challenge is stored as one bounded provider-neutral required
   action. It blocks reconciliation and redelivery until the user responds or
   the action expires.
10. Required-action tokens are never logged or exposed as UI state. The
    adapter consumes the persisted action, and success still requires matching
    remote evidence rather than a successful challenge response alone.

Adapter receipts prove only the external provider outcome represented by the
adapter. They are not Core truth and do not imply transport delivery or peer
agreement.

## Relationship To Transport Delivery

Transport delivery and external provider effects are separate lifecycle
owners:

- `CapsuleDeliveryLifecycleService` recovers publication of committed Hivra
  domain facts through a replaceable transport rail.
- `ExternalEffectService` executes explicit non-Core provider operations for a
  drone capability.

They may share general engineering patterns such as stable ids, atomic
persistence, and reconciliation, but they must not share journals, DTOs,
retry pumps, receipts, or state enums.

## Phase 1 Status

Implemented host baseline:

- provider-neutral operation, receipt, adapter request, and adapter result
  contracts;
- Capsule/plugin-isolated atomic journal;
- approval, enqueue, delivery, reconciliation, cancellation, and terminal
  transitions;
- timeout/restart retry semantics with one stable operation id;
- shared in-flight deduplication and stale-completion revision guards;
- bounded payloads, diagnostics, and journal retention;
- plugin-uninstall cleanup across local Capsules;
- fake-adapter coverage for success, timeout, restart, not-found retry,
  concurrent processing, stale completion, cancellation, collision, Capsule
  switching, and cleanup.

Provider integrations implemented above this generic phase:

- Moltbook Account/Home observation and assisted post publication;
- Capsule/plugin/account-scoped Moltbook credential resolution;
- exact post receipt and bounded recent-profile reconciliation;
- durable verification challenge, explicit numeric response, and post
  visibility confirmation;
- fail-closed handling for expired challenges and ambiguous delivery.

Not implemented in this generic phase:

- remote read/observe mode;
- provider-specific DTOs;
- generic background scheduling;
- promotion of any provider receipt into a Core fact.

## Review Exit Criteria

- Exactly one lifecycle owner exists for a provider effect.
- A drone and screen cannot call a provider adapter directly.
- No credential or provider DTO enters Core, ledger, WASM, or the generic
  operation journal.
- Timeout/retry/restart cannot create a second semantic operation.
- A late result cannot overwrite a newer revision.
- Uninstall and Capsule deletion leave no plugin effect journal behind.
- The provider adapter can be replaced without changing operation states,
  plugin contracts, or Core.
