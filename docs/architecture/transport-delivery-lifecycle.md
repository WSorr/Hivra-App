# Transport Delivery Lifecycle v1

## Purpose

Transport is an adapter concern. Delivery recovery is an application-runtime
concern. Neither UI screens nor drones own retry timing, relay receipts, or
the active-capsule lifetime.

This document fixes the single delivery path for invitations, invitation
terminal responses, and relationship-break notifications. It is deliberately
transport-neutral; Nostr is the currently mounted adapter.

## State Boundary

| Layer | Owns | Does not own |
| --- | --- | --- |
| Ledger | Signed domain facts and their deterministic projection | Relay retry state |
| Delivery outbox | Durable reminder that a committed local transport effect still needs delivery | A second copy of domain state or UI state |
| Delivery lifecycle | Capsule-scoped retry schedule, receipt reconciliation, cooldown coordination | Domain decisions, screen state, or a transport protocol |
| Transport adapter | Encode, sign, send, and receive envelopes | Ledger projection or user-flow policy |
| UI | User intent and rendering the projection | Timers, retries, or speculative delivery truth |

The outbox is currently a **delivery recovery index**, not an event journal:
the engine remains the authoritative source for concrete pending invitation and
relationship-break events. It must not be described as a fully independent
reliable queue until an outbox item carries a stable domain-event identifier
and payload digest, and the adapter returns matching per-event receipts.

## Canonical Path

```text
UI intent
  -> use-case / worker boundary
  -> append and persist Ledger fact
  -> enqueue delivery recovery item when relay delivery is unresolved
  -> CapsuleDeliveryLifecycleService pump
  -> transport adapter
  -> receipt reconciliation
  -> Projection rebuild
  -> UI render
```

The worker operates against an explicit capsule bootstrap. If the user changes
the selected capsule while it is running, the result persists under the worker
capsule and the selected runtime is restored. No completion is allowed to
replace another capsule's UI projection.

## Ownership Rules

1. `CapsuleDeliveryLifecycleService` is the only owner of retry delays,
   pending-pump lifetime, and receipt-to-outbox reconciliation.
2. `InvitationActionsService` owns invitation use-cases and worker/ledger
   application only. It does not own a timer or an outbox implementation.
3. `RelationshipService` appends a relationship fact first, then enqueues the
   same lifecycle. It never starts an independent retry loop.
4. Chat, trading signals, and pair attestation currently use transport workers
   but are not durable outbox events. Their migration requires explicit
   delivery semantics: ephemeral, durable inbox, or ledger fact. Do not add
   ad-hoc retry loops before that decision. Chat and trading-signal send are
   currently explicit one-attempt ephemeral actions, so a relay timeout cannot
   silently produce a duplicate message or signal.
5. `TransportHealthPolicyService` may suppress passive polling per capsule;
   it may not suppress a user-requested local Ledger action.

## Migration Status

- Completed: invitation send/accept/reject recovery and relationship breaks
  share the capsule-scoped lifecycle and outbox receipt reconciliation.
- Pending: define one shared passive receive scheduler for invitations,
  pair-attestations, chat, relationship notifications, and trading signals.
- Pending: upgrade the recovery index to a true event-addressed reliable queue
  only if product requirements demand guaranteed delivery beyond engine retry.

## Review Exit Criteria

- A transport channel has exactly one retry owner.
- A screen imports no worker runtime or outbox store.
- Every asynchronous worker result remains bound to its bootstrap capsule.
- Ledger facts are persisted before an unresolved transport effect is queued.
- A new channel declares whether its messages are `ephemeral`, `durable_inbox`,
  or `ledger_fact` before implementation.
