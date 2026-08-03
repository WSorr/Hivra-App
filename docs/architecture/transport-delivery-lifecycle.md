# Transport Delivery Lifecycle v1

## Purpose

Transport is an adapter concern. Delivery recovery is an application-runtime
concern. Neither UI screens nor drones own retry timing, relay receipts, or
the active-capsule lifetime.

This document fixes the single delivery path for invitations, invitation
terminal responses, and relationship-break notifications. It is deliberately
transport-neutral; Nostr is the currently mounted adapter.

Hivra transport is modeled as a bank-message rail, not as a social protocol
client. The application hands the transport a sealed Hivra envelope and later
receives sealed Hivra envelopes back. Adapter-specific details such as Nostr
kinds, relay subscriptions, NIPs, relay `OK` semantics, cursors, and publish
budgets must terminate inside the adapter boundary. Core and UI are allowed to
reason only about Hivra envelope metadata, verified domain facts, and local
delivery lifecycle state.

## State Boundary

| Layer | Owns | Does not own |
| --- | --- | --- |
| Ledger | Signed domain facts and their deterministic projection | Relay retry state |
| Delivery outbox | Durable reminder that a committed local transport effect still needs delivery | A second copy of domain state or UI state |
| Delivery lifecycle | Capsule-scoped retry schedule, receipt reconciliation, cooldown coordination | Domain decisions, screen state, or a transport protocol |
| Transport adapter | Encode, sign, send, and receive envelopes | Ledger projection or user-flow policy |
| UI | User intent and rendering the projection | Timers, retries, or speculative delivery truth |

The outbox is a **delivery recovery index**, not an event journal: the engine
remains authoritative for concrete invitation and relationship facts. Each
item is addressed by one immutable domain reference. For invitation effects it
is the `invitation_id`; for relationship effects it must be the signed domain
event id. The item stores no duplicate domain payload and derives its effect
from the ledger worker.

## Canonical Path

```text
UI intent
  -> use-case / worker boundary
  -> append and persist Ledger fact
  -> enqueue one delivery-propagation item for that fact
  -> CapsuleDeliveryLifecycleService pump
  -> transport adapter publishes that exact fact
  -> relay-publication reconciliation
  -> Projection rebuild
  -> UI render
```

The worker operates against an explicit capsule bootstrap. If the user changes
the selected capsule while it is running, the result persists under the worker
capsule and the selected runtime is restored. No completion is allowed to
replace another capsule's UI projection.

The Rust FFI runtime is process-global. Every Dart worker that bootstraps it,
including invitation, chat, and pair-attestation workers, MUST pass through
the shared `CapsuleFfiWorkerQueue`. This queue is global rather than
per-capsule because a worker bootstrap temporarily replaces the active native
runtime. A Dart timeout does not cancel a compute worker; when a late worker
has appended a Core fact, it MUST persist the matching outbox item before
releasing the FFI queue. A timeout may change UI feedback, never the durable
delivery obligation.

A relay acceptance changes an outbox item to `published`; it does **not** mean
the peer capsule has fetched or acted on the event. Adapter receipts carry the
envelope `correlation_id`; publication evidence can update only the matching
outbox item. A peer accept/reject/revoke or relationship projection is still
resolved only from ledger facts. This is not a guaranteed end-to-end queue: an
unresolved invitation remains pending until a terminal signed fact arrives or
the user revokes it.

## Non-Negotiable Boundary

`receive()` is an inbound operation. It may decrypt, authenticate, deduplicate,
append a verified fact, and return a projection. It must never publish an
outbound fact or cause a ledger-wide retry scan.

Likewise, a delivery retry accepts one exact outbox item. It must not infer a
batch of unresolved work by re-scanning the ledger. A ledger scan is allowed
only for deterministic recovery of a missing, uniquely identified outbox item;
an ambiguous legacy item is quarantined for reconciliation rather than replayed.
`delivery_outbox.json` schema v5 makes that quarantine explicit: a pending or
legacy retry-exhausted record without one valid immutable `delivery_reference`
is retained as `quarantined`, excluded from every due-item query, and exposed
through diagnostics. The first successful store load rewrites an older schema
to v5, making the classification explicit on disk. It cannot bind a receipt,
wake a repeated retry loop, or be revived by aggregate ledger inference.
Referenced legacy records may still resume through the one canonical lifecycle.

This distinction matters because a Nostr `OK` is a relay acknowledgement, not
receiver delivery. NIP-01 defines `OK` as acceptance or denial of an `EVENT`;
the receiving capsule still has to retrieve the event through its own `REQ`
subscription. Therefore the UI must never label a relay receipt as peer
delivery.

The same boundary applies to every future transport. Hivra does not depend on
Nostr-specific delivery semantics. A transport adapter may use Nostr, Matrix,
BLE, local network, or another rail, but its output to the application is only a
Hivra `DeliveryEnvelope` plus adapter receipt metadata. The application must
not branch on adapter-specific concepts when deciding whether a domain fact is
valid or visible.

Inbound protection is allowed only before ledger materialization and must be
transport-neutral:

- authenticate the envelope sender against the adapter signer and Hivra
  envelope `from`;
- reject malformed envelopes, wrong recipient, wrong network, or unsupported
  schema version;
- deduplicate by immutable envelope/event reference and domain reference;
- rate-limit unknown or unauthenticated senders before expensive processing;
- cap inbound batch size and payload size;
- quarantine suspicious input for diagnostics instead of appending speculative
  ledger facts.

Spam protection must not become product policy. A valid invitation, chat
message, trade signal, or pair attestation is interpreted by its owning domain
after it passes the neutral inbound guard.

The first mounted guard slice enforces envelope schema v1, exact transport
recipient, and a 256 KiB opaque-payload ceiling after adapter sender
authentication. Deterministically rejected adapter events still enter
adapter-event deduplication, preventing an overlap cursor from reprocessing the
same malformed event indefinitely.

Sender rate limiting remains `NEEDS_CONTRACT`. It cannot silently drop an
otherwise valid envelope after a relay cursor advances. The required follow-up
is a bounded durable quarantine/deferred-inbox contract with stable envelope
identity, capsule/network scope, retry eligibility, expiry, and diagnostics.

## Ownership Rules

1. `CapsuleDeliveryLifecycleService` is the only owner of retry delays,
   pending-pump lifetime, and relay receipt-to-outbox reconciliation.
2. `InvitationActionsService` and `RelationshipService` append a domain fact
   and enqueue its exact delivery reference. They do not publish a network
   envelope, own a timer, or scan unresolved ledger state.
3. The transport adapter only publishes or retrieves explicitly supplied
   envelopes. It does not inspect the ledger, invoke a projection, or apply
   retry policy.
4. Chat, trading signals, and pair attestation currently use transport workers
   but are not durable outbox events. Their migration requires explicit
   delivery semantics: ephemeral, durable inbox, or ledger fact. Do not add
   ad-hoc retry loops before that decision. Chat and trading-signal send are
   currently explicit one-attempt ephemeral actions, so a relay timeout cannot
   silently produce a duplicate message or signal.
5. `TransportHealthPolicyService` may suppress passive polling per capsule;
   it may not suppress a user-requested local Ledger action.
6. Transport adapters are replaceable rails. They may optimize delivery, but
   they may not define Hivra truth, relationship state, consensus, or UI
   projection.

## Migration Status

- Completed: invitation, invitation-terminal, and relationship-break outbox
  items use immutable event references and exact retry endpoints.
- Completed: a late Core worker completion cannot append a fact without first
  enqueueing its matching delivery obligation.
- Completed: all current Dart FFI workers share one global bootstrap queue;
  no channel may overlap another capsule's native runtime.
- Completed: receive no longer triggers relationship-break publication.
- Completed: aggregate FFI retry entrypoints were removed. The mounted ABI
  exposes only exact invitation-offer, invitation-terminal, and
  relationship-break publication by immutable reference.
- Completed: a published outbox record persists normalized adapter evidence
  in place: exact recipient endpoint, adapter endpoint, envelope identifier,
  message kind, failed-endpoint count, and observation time. Receipt evidence
  never means peer receipt or ledger acceptance.
- Completed: the transport-neutral inbound envelope guard rejects unsupported
  schema versions, wrong recipients, and payloads above 256 KiB before domain
  routing; deterministic rejects are adapter-deduplicated.
- Completed: the Nostr adapter emits signed kind `9444` events containing
  NIP-44 v2 authenticated `DeliveryEnvelope v1` ciphertext. It verifies the
  outer event before decrypt, requires exactly one matching recipient tag,
  binds the decoded sender to the event signer, and never falls back from a
  failed NIP-44 decode to NIP-04. Deprecated kind `4`/NIP-04 is isolated to a
  read-only rolling-compatibility decoder with the same ingress and replay
  guards; it cannot publish or create another lifecycle path.
- Pending: define one shared passive receive scheduler for invitations,
  pair-attestations, chat, relationship notifications, and trading signals.
  Until then, screen-triggered receives are serialized but can still perform
  redundant relay polls.
- Pending: consolidate the native default and quick Nostr session/cursor
  caches behind one capsule-owned transport session with explicit operation
  budgets. They are safe under the global queue, but currently retain
  duplicate relay connections and independent cursors.
- Pending: pair-attestation re-announcement needs a pair/snapshot-scoped
  rate-limit or a durable acknowledgement policy. It is currently an
  intentionally best-effort convergence aid, not a Core outbox effect.
- Completed in `12.3 / pass 10`: schema v5 explicitly quarantines every
  unreferenced retryable outbox record. Quarantine is durable diagnostic
  evidence, never a second delivery route or a source of domain truth.
- Pending: decide whether product requirements justify a true end-to-end
  reliable queue with receiver acknowledgements beyond engine retry.
- Pending: complete transport-neutral spam protection with a durable bounded
  quarantine/deferred inbox. Sender throttling must never turn a valid retained
  envelope into silent data loss after cursor advancement.

## Review Exit Criteria

- A transport channel has exactly one retry owner.
- A screen imports no worker runtime or outbox store.
- A receive operation has no outbound transport side effect.
- One outbox item can produce at most one matching envelope per attempt.
- Every retryable outbox item has one immutable delivery reference; an
  unreferenced record is durable quarantine and is never due.
- Every asynchronous worker result remains bound to its bootstrap capsule.
- Ledger facts are persisted before an unresolved transport effect is queued.
- A new channel declares whether its messages are `ephemeral`, `durable_inbox`,
  or `ledger_fact` before implementation.
- A transport adapter can be replaced without changing Core fact validation or
  screen projection logic.
