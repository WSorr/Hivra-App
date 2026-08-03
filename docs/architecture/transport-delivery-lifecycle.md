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
The audit for `12.3 / pass 11` proved that this also requires an acknowledged
ingress handoff: the adapter currently advances its per-relay cursor and marks
an event seen before FFI routing. A future limiter must not acknowledge an
authenticated envelope until it is either consumed by the canonical ingress
owner or durably quarantined. Capacity exhaustion must apply backpressure and
remain visible; it must not evict an unconsumed valid envelope silently.

### Acknowledged Ingress Handoff Contract

This is the normative prerequisite established by `12.3 / pass 12`. It does
not authorize sender limiting or quarantine storage by itself.

The adapter MUST return one bounded ingress batch without mutating its
committed cursor or acknowledged-event set. Every observation in that batch
retains:

- the stable adapter event id;
- every relay/end-point that returned that event;
- the signed wire timestamp and the candidate cursor for each observation;
- either the authenticated transport-neutral `DeliveryEnvelope` or one
  deterministic adapter rejection.

The application-runtime ingress owner routes each authenticated envelope once
through the existing FFI ingress path and returns exactly one disposition:

- `consumed`: the canonical owner durably accepted the message, determined it
  was an already-consumed replay, or completed an explicit terminal policy
  rejection;
- `quarantined`: the original event identity and envelope were durably stored
  in the Capsule/network-scoped quarantine before acknowledgement;
- `retry`: canonical consumption did not complete and durable quarantine did
  not commit.

Adapter-invalid wire input may receive a separate permanent-rejection
disposition only after deterministic signature, recipient, envelope, and
sender-binding checks have established that it is not a valid authenticated
Hivra envelope. Bounded rejection evidence MAY retain its event id and reason;
it is not a domain fact or quarantine payload.

Acknowledgement is a resolve-once batch operation. The adapter may add an event
id to its acknowledged set only for `consumed`, `quarantined`, or deterministic
adapter rejection. It may advance one relay cursor only through the greatest
candidate prefix for which every event observed from that relay has one of
those terminal dispositions. Any `retry`, callback failure, panic, timeout,
quarantine write failure, or full quarantine capacity leaves the affected
prefix unacknowledged and applies visible backpressure. Partial success may
deduplicate already acknowledged event ids, but it must not skip the unresolved
relay prefix.

The cursor is only a fetch optimization. It is not receipt evidence, domain
truth, or proof of canonical consumption. Process restart may replay an
overlap; Core idempotence, capability inbox identity, and durable quarantine
identity must make that replay safe.

Quarantine recovery MUST re-enter the same canonical FFI ingress router with
the original adapter event id and envelope. It cannot invoke a capability
handler directly, append Core facts itself, or become a second receive route.
Expiry is an explicit terminal policy transition that leaves bounded evidence
of event id, sender, scope, reason, and time; silent payload eviction is
forbidden.

Threat closure required before implementation:

- spoofing and key confusion fail before authenticated-envelope disposition;
- replay is keyed by stable adapter event id and then by the owning domain's
  immutable identity;
- wrong-recipient and cross-network input fail closed before routing;
- downgrade input remains confined to the existing read-only compatibility
  decoder and receives no alternate acknowledgement path;
- sender throttling happens only after sender binding and can choose only
  canonical consumption, durable quarantine, or visible backpressure;
- a malicious sender cannot force unbounded memory, disk, or cursor growth.

### Inbound Quarantine Repository and Sender Policy Contract

`12.3 / pass 14` defines this contract. `12.3 / pass 15` implements repository
storage and recovery only; it does not authorize sender throttling.

One `CapsuleInboundQuarantineRepository` is the sole owner of retained
authenticated envelopes. Its scope is the tuple `(Capsule, network,
transport endpoint)`. It is application/platform state outside Core, Ledger,
delivery outbox, capability inboxes, and transport adapters. The adapter owns
wire identity and cursor commit; the FFI ingress router owns disposition; this
repository owns only encrypted retention, eligibility, expiry, and bounded
diagnostic evidence.

Repository schema v1 has one record per `(scope, adapter, adapter_event_id)`:

```text
InboundQuarantineRecordV1 {
  schema_version = 1
  scope { capsule_id, network, transport_endpoint }
  adapter
  adapter_event_id
  authenticated_sender
  observed_by[]
  message_kind
  reason
  first_observed_at
  quarantined_at
  eligible_after
  expires_at
  attempt_count
  last_attempt_at?
  envelope_ciphertext
}
```

`adapter_event_id` is the idempotency key. Re-observation merges bounded relay
provenance and never creates another record or resets expiry. The complete
transport-neutral envelope is authenticated-encrypted at rest with a
Capsule-scoped storage key provided by the crypto/platform boundary. Root
signing keys, transport signing keys, and transport encryption keys are not
reused as storage keys. No plaintext envelope, key, or payload may enter logs,
diagnostic tombstones, temporary files, or the Ledger.

Schema-v1 bounds are protocol-operational constants, not UI preferences:

- at most `256` retained records per scope;
- at most `32 MiB` of encrypted envelope bytes per scope;
- at most `32` retained records per authenticated sender per scope;
- at most `16` distinct relay/end-point observations per record;
- retained payload expiry is `72 hours` after first quarantine and is never
  extended by replay;
- terminal tombstones retain metadata only for at most `30 days`, with at most
  `1024` tombstones or `1 MiB` per scope, whichever is reached first.

Capacity is fail-closed. A record that cannot be committed atomically because
of record, byte, sender, filesystem, encryption, or index capacity receives
`retry`, keeps the affected relay prefix unacknowledged, and exposes a degraded
transport diagnostic. The repository MUST NOT evict another retained payload
to admit a newer one. Capacity can be released only by successful canonical
consumption, explicit expiry, or an explicit user diagnostic action that
creates the same terminal tombstone evidence.

Expiry is a resolve-once transition. It securely removes ciphertext and writes
a bounded tombstone containing only scope, adapter event id, sender, message
kind, terminal reason, and timestamps. Expiry is neither a Core fact nor proof
that the peer action expired. If tombstone capacity is unavailable, payload
removal and ingress acknowledgement stop with visible backpressure rather than
silently losing evidence.

`SenderIngressPolicyV1` is transport-neutral and applies only after outer
signature, recipient, envelope authentication, sender binding, schema, and
payload-size checks. It uses authenticated transport sender plus scope, never
IP address, relay, application screen, domain kind, social trust, or Capsule
relationship state. V1 permits a burst of `8` new event ids and refills one
permit every `15 seconds`, capped at `8`. The same event id is charged at most
once; acknowledged replay and quarantine replay are not charged again. No
sender, contact, plugin, or domain kind has a hidden bypass.

The maintained v1 repository persists each sender bucket and exact recent
charge evidence inside the same authenticated-encrypted snapshot. Charge
evidence is retained for `8 days`, bounded to `65536` event ids and `8 MiB`
per scope, with at most `40960` ids for one sender. Exhausting sender-state or
charge-evidence capacity returns `retry`; it cannot silently forget evidence
to grant a permit or create a second deduplication store.

When no permit exists, the router may return `quarantined` only after the v1
record commits atomically. Repository failure or full capacity returns `retry`.
Adapter-invalid input follows deterministic rejection and never consumes
quarantine capacity. Sender policy state is bounded to `1024` active senders
per scope and persists the last refill/checkpoint needed to prevent restart
bypass. Evicting inactive sender-policy state may reduce throttling only after
its bucket is fully refilled and it has no retained records.

Recovery is deterministic and single-route:

1. Validate and decrypt one eligible record ordered by `(eligible_after,
   quarantined_at, adapter_event_id)`.
2. Re-enter the same FFI ingress router with the original event id and envelope
   under a `quarantine_replay` flag that prevents a second rate charge.
3. On `consumed`, atomically remove ciphertext and write a consumed tombstone.
4. On `retry`, increment the bounded attempt metadata and compute capped
   transport-health backoff; no capability-specific scheduler is created.
5. On process restart or Capsule switch, resume only the selected scope. A
   corrupt, undecryptable, unsupported-schema, or partially committed record
   fails closed as degraded quarantine evidence and cannot append a Core fact.

Repository writes use one atomic snapshot/index owner with temporary-file
cleanup and authenticated integrity. There is no second database, outbox
status, relay cursor, receive worker, or Core event for quarantine. Deleting a
Capsule must delete its quarantine ciphertext and policy state through the
existing Capsule deletion lifecycle while retaining only user-approved export
evidence, never hidden payload copies.

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
7. The adapter owns wire verification, event identity, relay observations, and
   cursor commit. The application-runtime FFI boundary owns ingress routing and
   disposition. A future Capsule-scoped quarantine repository owns retention
   bytes and expiry evidence; it owns no routing or domain interpretation.
8. `CapsuleInboundQuarantineRepository` is the only future owner of retained
   inbound ciphertext, sender buckets, expiry transitions, and tombstones. It
   cannot own polling, routing, domain validation, Ledger append, or UI policy.

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
- Completed in `12.3 / pass 11`: default and quick operations share one
  Capsule transport-key-owned Nostr session, relay pool, seen set, and
  per-relay cursor map. Profiles select only bounded operation timeouts; they
  cannot create a second receive session or cursor owner.
- Contract completed in `12.3 / pass 12`: acknowledged ingress is a bounded
  resolve-once batch handoff. Authenticated events become cursor/seen terminal
  only after canonical consumption or durable quarantine; unresolved capacity
  or persistence failure preserves the relay prefix and exposes backpressure.
  Runtime implementation and sender quarantine remain separate later passes.
- Completed in `12.3 / pass 13`: the Nostr adapter returns one bounded pending
  batch with stable event identity and merged relay provenance. Relay fetch no
  longer advances cursors or inserts new seen ids. The canonical FFI ingress
  router returns an exact per-event disposition and resolves the same cached
  adapter session; only terminal relay prefixes commit. Retry items remain in
  the pending batch under a new resolve-once batch id. The legacy aggregate
  Nostr `Transport::receive` route is sealed. Full chat and attestation inboxes
  return retry backpressure without evicting older unconsumed items, and their
  in-process deduplication uses the adapter event id.
- Contract completed in `12.3 / pass 14`: one bounded encrypted
  Capsule/network/transport-endpoint repository owns quarantine records,
  sender buckets, expiry, and tombstones. Exact schema-v1 limits, atomic
  capacity backpressure, sender policy, same-router replay, restart behavior,
  storage-key separation, and deletion are fixed. Runtime implementation and
  sender-policy activation remain separate later passes.
- Completed in `12.3 / pass 15`:
  one FFI-boundary repository persists an authenticated-encrypted snapshot and
  separately authenticated envelope ciphertexts through distinct platform
  crypto roles. It enforces schema-v1 bounds without eviction, recovers one
  eligible item through the original `route_inbound_envelope` entrypoint,
  creates metadata-only consumed/expired tombstones, fails closed on corrupt
  storage, and participates in the existing Capsule deletion lifecycle.
  `SenderIngressPolicyV1` remains inactive and no Core or adapter storage path
  was added. Full automated gates, universal macOS launch, and Android
  update/restart evidence passed with preserved Ledger state and zero ingress
  retry. Pass 16 is the first pass authorized to activate only the specified
  sender policy behind this unchanged repository and router.
- Completed in `12.3 / pass 16`: `SenderIngressPolicyV1` is activated only in
  the canonical FFI ingress before routing. Burst/refill checkpoints and exact
  bounded charge evidence persist in the pass-15 encrypted snapshot; pass-15
  snapshots migrate with empty policy state without rewriting retained
  quarantine evidence. Stable event replay and quarantine recovery do not
  consume another permit. Throttled input becomes terminal only after atomic
  quarantine, while repository, sender-state, or evidence capacity returns
  cursor-safe `retry`. No capability, message kind, relationship, relay, UI,
  plugin, Core, or scheduler bypass was added.
- Audited before `12.3 / pass 17`: passive receive had one native
  router, one cached Capsule transport session/cursor owner, one shared
  process-global FFI worker queue, and one shared health policy, but it does
  not yet have one application-level scheduling owner. The current trigger map
  is:
  - `MainScreen` requests invitation ingress on launch, resume, connectivity
    restoration, and delayed follow-ups, then separately requests pair
    attestation receive;
  - `InvitationsScreen` requests an initial quick receive, a full receive every
    15 seconds while mounted, and another quick receive after Capsule switch;
  - trading and plugin-chat screens request chat/trading receive and then
    independently request pair-attestation receive;
  - relationship refresh reuses invitation ingress and trading signals reuse
    chat ingress, so neither owns a distinct native route;
  - `CapsuleFfiWorkerQueue.shared` prevents overlap, but serialization does not
    coalesce these requests. Both chat and pair-attestation FFI drain functions
    call `hivra_transport_receive_quick()` before draining their own keyed
    inbox, so one UI refresh can perform two sequential relay polls.
- `CapsulePassiveReceiveCoordinator` is the sole application-level
  owner of passive receive trigger lifetime, per-Capsule in-flight joining,
  foreground periodic cadence, lifecycle/network follow-up coalescing, and one
  bounded manual-retry follow-up. It owns no transport session, cursor,
  message interpretation, Ledger fact, inbox, retry outbox, or attestation
  response policy.
- The canonical pass-17 operation is `trigger -> coordinator -> one existing
  default/quick FFI ingress poll -> canonical FFI router -> capability-owned
  projection/drain`. Invitation and relationship facts continue through the
  existing Ledger/Core projection. Pair attestations continue through the
  attestation verifier/store. Chat and trading payloads continue through the
  chat delivery filter and their existing inbox owners. A channel drain MUST
  NOT poll a relay.
- Pass-17 concurrency and lifecycle semantics are implemented as follows:
  - automatic requests for the same Capsule join the active operation and do
    not queue another relay poll;
  - one explicit manual retry may bypass health cooldown and, if a passive
    operation is active, becomes at most one forced follow-up rather than a
    parallel operation;
  - the existing process-global FFI queue remains the final cross-Capsule
    serialization boundary;
  - delayed and periodic passive work stops when the app is not foreground;
    resume creates one coalesced trigger wave;
  - a Capsule switch invalidates delayed work for the previous Capsule. Any
    already completed worker result remains bound to and persisted for its
    bootstrap Capsule, while stale UI projection is discarded;
  - restart creates no durable scheduler state. Relay cursor, quarantine,
    Ledger, and capability inbox owners retain their existing independent
    persistence contracts.
- Pass 17 removes or seals the exact redundant paths: screen-owned passive
  timers and lifecycle/network follow-ups; `MainScreen` invitation-versus-
  attestation in-flight flags; direct passive receive orchestration in
  invitations, trading, and plugin-chat screens; and the nested transport poll
  inside chat and pair-attestation drain FFI functions. Explicit user refresh
  remains, but enters the same coordinator as a bounded manual-retry intent.
  Existing `hivra_transport_receive()` and
  `hivra_transport_receive_quick()` remain the only native poll entrypoints;
  no second transport route, Core path, DTO family, or durable scheduler store
  is authorized.
- Completed in `12.3 / pass 17` on 2026-08-03:
  - launch, resume, connectivity, foreground periodic, screen-activation,
    post-send, and manual triggers enter one process-scoped coordinator;
  - same-Capsule automatic work joins the active operation and manual work can
    schedule only one bounded forced follow-up;
  - the canonical invitation/relationship ingress performs the sole relay poll
    and transport-health decision before attestation and chat/trading drains;
  - chat and pair-attestation FFI drains no longer call
    `hivra_transport_receive_quick()` and remain capability-owned projection
    boundaries;
  - the invitations-screen periodic timer, direct screen receive chains, and
    MainScreen receive in-flight flags were removed or sealed;
  - pause, Capsule-switch, connectivity cooldown, poll-before-drain ordering,
    drain-failure isolation, and cross-capability convergence are covered by
    regression tests;
  - the existing FFI router, cached Nostr session/cursors, process-global FFI
    queue, Core/Ledger projection, capability inboxes, and native poll
    entrypoints remain unchanged as the only canonical path.
  - `git diff --check`, Rust formatting, `flutter analyze`, all `726` Flutter
    tests, `cargo test --workspace`, and `tools/review/review_all.sh` passed;
    the universal macOS release bundle launched through launch, resume,
    follow-up, and periodic receive while preserving Ledger versions `105`,
    `62`, and `119`, and no process error/fault was emitted;
  - Android smoke build `versionCode=100000325`, SHA-256
    `ac0dd45dbd195f7094c83b151e68af2cffccded3c6faf8e1b07813b78661de3d`,
    updated in place, preserved Ledger `v82`, and completed launch, periodic,
    explicit manual retry, attestation drain, and cold restart without a fatal
    runtime error.
- Audited on 2026-08-03 for `12.3 / pass 18`: pair-attestation
  re-announcement is a best-effort convergence aid, not a Core fact, transport
  outbox obligation, or peer-delivery acknowledgement. Runtime evidence after
  pass 17 showed the current blind response path can form a cross-device
  ping-pong: a verified duplicate is reported as newly stored, answered, and
  then answered again by the peer on a later periodic receive.
- `ConsensusAttestationExchangeService` is the sole owner of the automatic
  response decision. `ConsensusAttestationStore` remains the sole persistence
  owner for verified evidence and may extend the same Capsule-scoped file with
  bounded response checkpoints. The passive receive coordinator only hands
  drained evidence to this owner; it MUST NOT interpret pair consensus or own
  an attestation retry loop.
- The pass-18 response contract is:
  - response identity binds the local Capsule, sorted pair roots, exact
    snapshot hash, peer signer/peer evidence `recordKey`, and local evidence
    `recordKey`;
  - store schema v1 migrates to v2 with unchanged evidence bytes and an empty
    response-checkpoint set; Ledger/Core history is not rewritten;
  - an automatic response reserves its checkpoint atomically before send. If
    storage is corrupt, unavailable, or at the `4096`-checkpoint bound, the
    response fails closed without a network effect;
  - adapter-accepted send marks the checkpoint delivered. A failed or timed-out
    send may become eligible only after a persisted `15 minute` retry boundary;
    no process restart, relay overlap, screen refresh, or periodic receive may
    bypass that boundary;
  - a delivered checkpoint is terminal for that exact peer evidence and local
    evidence pair. A different valid snapshot creates a different identity and
    may converge independently;
  - repeated verified envelopes remain valid evidence input but are not
    described as newly stored and do not trigger another automatic response;
  - explicit pair synchronization when current two-root evidence is missing
    retains its existing user/capability path. The ready path loses blind
    fire-and-forget re-announcement and reuses the same bounded response owner;
  - no timer, scheduler, receiver acknowledgement protocol, second outbox,
    second transport route, or Core event is added.
- Pass-18 threat model covers duplicate/replayed peer evidence, concurrent
  receive and guard calls, restart after reservation or send, failed adapter
  delivery, stale snapshots, wrong pair/signer, corrupt or full checkpoint
  storage, Capsule switch/deletion, and a trusted peer attempting checkpoint
  exhaustion. Exit evidence requires v1 migration, exact-key idempotence,
  retry-boundary, success-terminal, new-snapshot, corruption/capacity,
  concurrency, and cross-Capsule regressions plus macOS/Android runtime logs
  showing that a stable snapshot reaches zero repeated automatic responses.
- Completed in `12.3 / pass 10`: schema v5 explicitly quarantines every
  unreferenced retryable outbox record. Quarantine is durable diagnostic
  evidence, never a second delivery route or a source of domain truth.
- Pending: decide whether product requirements justify a true end-to-end
  reliable queue with receiver acknowledgements beyond engine retry.
- Pending: complete transport-neutral spam protection with a durable bounded
  quarantine/deferred inbox and acknowledged ingress handoff. Sender
  throttling must never turn a valid retained envelope into silent data loss
  after cursor advancement.

## Review Exit Criteria

- A transport channel has exactly one retry owner.
- A screen imports no worker runtime or outbox store.
- A receive operation has no outbound transport side effect.
- One passive trigger wave performs at most one relay poll before all current
  capability inboxes are projected or drained.
- A channel-specific drain cannot initiate transport receive or own a timer.
- Launch, resume, connectivity, periodic, and manual triggers enter one
  application-level coordinator and preserve bootstrap-Capsule result binding.
- An authenticated envelope cannot become cursor/seen terminal before
  canonical consumption or durable quarantine.
- An unresolved batch disposition preserves its relay cursor prefix and
  exposes backpressure.
- Quarantine replay re-enters the same FFI ingress router and cannot call a
  domain owner directly.
- One outbox item can produce at most one matching envelope per attempt.
- Every retryable outbox item has one immutable delivery reference; an
  unreferenced record is durable quarantine and is never due.
- Every asynchronous worker result remains bound to its bootstrap capsule.
- Ledger facts are persisted before an unresolved transport effect is queued.
- A new channel declares whether its messages are `ephemeral`, `durable_inbox`,
  or `ledger_fact` before implementation.
- A transport adapter can be replaced without changing Core fact validation or
  screen projection logic.
