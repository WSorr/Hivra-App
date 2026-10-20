# Moltbook Engagement Lifecycle v1

Owner: external Moltbook Drone plus host External Effects boundary

Related contracts:

- `moltbook_agent_drone_design_v1.md`
- `../architecture/ai-proposal-boundary.md`
- `../architecture/external-effect-lifecycle.md`

## 1. Purpose

This document defines one canonical lifecycle for observing a Moltbook target,
deciding whether to engage, preparing exact prose, and publishing at most one
semantic reply. It closes the ambiguity that previously allowed Assisted and
Bounded paths to create separate effects for the same remote comment.

The lifecycle is independent of how it is triggered. Manual, launch catch-up,
and continuous-while-running modes use the same identities, policy, journal,
adapter, and receipt rules.

## 2. Non-goals

- Moltbook state does not become Core or Capsule-ledger truth.
- The selected inference provider never receives credentials or an effect
  capability.
- WASM does not receive network or secure-storage access.
- This contract does not promise an always-running server or background daemon.
- Anti-spam challenges are never bypassed. The selected inference provider may solve an exact bounded
  numeric prompt only after the publication effect is already authorized.
- Pair Consensus is not required for one Capsule operating its own account.

## 3. Canonical identities

### 3.1 Target key

Every engagement target has one canonical key:

```text
(capsule_root,
 plugin_id,
 provider_id,
 provider_account_id,
 post_id,
 action_class,
 parent_comment_id_or_root)
```

`engagement_id` is the lowercase SHA-256 of the versioned canonical JSON form
of this tuple. Provider DTOs and display text are excluded.

For bounded delegation v1, `action_class` must be `reply_draft` and
`parent_comment_id_or_root` must contain one exact foreign comment id. Root
comments, posts, votes, follows, and private messages are not delegated.

### 3.2 One target, one active engagement

For one target key:

- zero or one non-terminal engagement may exist;
- Assisted and Bounded are policies over that same engagement, not separate
  publication routes;
- an existing active effect is resumed, never recreated;
- a succeeded effect permanently closes that exact target;
- an observed direct reply from the bound provider account closes that exact
  target even when the local Capsule journal has no matching operation;
- comments authored by the bound provider account are never reply targets;
- a newer foreign follow-up is a different target because it has a different
  parent comment id;
- a cancelled or expired target may be reopened only through an explicit
  user action; automatic modes do not reopen it.

Moltbook keeps one current effect per Capsule, shared by posts, replies and
community creation. Preparation is serialized and the shared effect owner
atomically enforces capacity one. Pending work blocks a different effect even
when its target, draft text or AI proposal hash differs. Already answered
comments are excluded using current provider observations. The read adapter
omits deleted, spam-marked and unverified comments before any WASM planning or
AI proposal. Visible replies beneath a hidden parent remain observable; hidden
entries do not consume the bounded visible-comment limit. Missing or malformed
visibility evidence fails closed.

### 3.3 Effect identity

An external-effect operation represents one frozen exact outbound payload.
Its stable operation id and payload hash remain owned by the generic External
Effects lifecycle. The Moltbook workflow additionally binds that operation to
`engagement_id`.

Editing text is allowed before effect preparation. After preparation, text is
immutable. Replacing a prepared draft requires explicit cancellation first;
automatic modes cannot replace it. Cancellation of unsent work releases its
slot. An ambiguous provider outcome retains the current operation and permits
only reconciliation, never blind resubmission.

## 4. Aggregate without a second truth store

The user-facing Engagement is a projection, not another mutable journal. It is
rebuilt from existing owners:

| Evidence | Canonical owner |
| --- | --- |
| remote post/comment observation | Moltbook read adapter, in memory |
| processed ids and catch-up cursor | isolated plugin checkpoint |
| engagement decision and hash | deterministic WASM output |
| AI prose proposal | untrusted in-memory proposal |
| exact reply draft and hash | deterministic WASM output |
| approval/delegation evidence | effect approval metadata |
| pending delivery, challenge, reconciliation | single current effect |
| current publication statistics and moderation | Moltbook read adapter, in memory |
| local daily/interval safety budgets | isolated plugin checkpoint |

No screen may keep an independent authoritative status. If evidence disagrees,
the fail-closed external-effect state wins for remote-write progress.

### 4.1 Capsule-owned public change feed

Public development news enters Moltbook through one bounded plugin-state feed,
not through repository, Ledger, or unrestricted Capsule-history access by AI.
Each confirmed item binds one producer-supplied `source_id`, one allowed topic,
and 1..8 explicit public facts to a versioned SHA-256 commitment. Exact replay
is idempotent; reuse of the same source id for different facts fails closed.

The feed is Capsule scoped, oldest-first for explicitly recorded items, and
bounded to 100 items. A reviewed build-time manifest is an ordered snapshot
lineage: only its newest allowed snapshot may remain pending, while older
undrafted entries from that same manifest are sealed instead of replayed as
current news on a new Capsule. AI may turn only the next pending item into an
advisory bulletin proposal. Every source line must remain verbatim in the
ordered supporting facts, but the public body is original, source-grounded
prose. If AI changes the grounding or cannot produce a substantive body, the
draft is rejected; there is no mechanical facts-block fallback. A foreground cycle may prepare
that local draft when no remote target claimed the cycle's proposal slot. A
draft for the same source is never generated twice; another local draft or
unresolved effect does not starve a distinct confirmed change. The item becomes
drafted only after the existing ambassador WASM preserves the exact title/body
and the existing draft store durably records the canonical draft hash.

Stopping the ambassador disables configured cycles and provider writes, not
explicit local authoring. The user may still select a confirmed public change,
request an unlocked AI proposal, and retain an exact WASM draft. These actions
preserve topic, Capsule, account and installed-package binding and create no
publication operation. Stop during an action, package replacement/removal or
scope change invalidates its unfinished result; saving a draft never enables
the ambassador or grants publication authority.

`Assisted` mode stops at the local draft. Existing `Bounded` mode may advance
one exact public-change draft through the existing post effect to the active
Capsule's configured primary community. The destination is fixed by local
policy before draft and effect preparation; AI cannot choose or change it.
An uncertain effect retains the single slot until the provider outcome is
known. No new reply/post effect or AI publication proposal starts while that
slot is occupied. Approved and queued work resumes with the same identity after
restart; interrupted delivery reconciles without another POST. Legacy multiple
pending records are drained through the same path; none may be discarded or
replaced by selecting the newest record. This migration ends when old pending
work reaches a definite outcome.
Publishing to an existing community does not require ownership evidence.
Provider permissions and community rules still fail closed at delivery. The
same operation id, exact destination binding, receipt, unresolved state, and
reconciliation rules apply across restart, so repeated launches cannot create
a second semantic post. AI fact drift, secret-like material, Capsule switching,
account rotation, destination drift, or provider rejection keeps the change
pending or terminally closed without a second provider effect.
The application may import a bounded, reviewed build-time manifest when the
Moltbook workspace opens. The manifest parser is strict and atomic, validates
the complete lineage, and exposes only the newest entry matching the Capsule's
existing allowed-topic policy. A configured exact public GitHub repository URL
is also observed without credentials when a foreground cycle starts. Only the
latest immutable commit identity, timestamp, subject, one bounded descriptive
message line, and changed areas enter the same feed as evidence, not mandatory
public wording. Legacy repository fact-dump drafts cannot auto-publish. Raw patches,
repository contents, issues, secrets, private Capsule state, and GitHub write
authority remain unavailable. Exact commit replay is idempotent; source or
response mutation fails closed before inference or WASM. Both producers use the
same ingestion contract and gain no draft, approval, effect, or publication
authority.
The same commit SHA observed under the earlier repository evidence format is
not queued again under the current format.
If draft persistence succeeds but the feed marker cannot be written, the item
remains pending and requires explicit operator resolution; no heuristic may
adopt a draft by title, bulletin id, category, or text similarity.

A local post draft is authoring state, not publication history. An accepted
challenge or authenticated provider read is insufficient for a post receipt:
the adapter must read the exact post without credentials, match its account,
destination, title and body, and observe verified, not-spam, not-deleted status.
Missing public evidence remains unresolved and retains the provider reference.
A profile lookup can locate an id but cannot substitute for this public read.

The last provider-referenced post remains in the existing single effect slot,
with its exact payload and source draft, even after a successful receipt or a
known moderation rejection. Loading, reopening and another cycle never erase
that result or create a competing effect. The current-publication card opens
the result and shows the exact submitted title/body, provider link and a fresh
anonymous moderation/visibility observation. Unknown status stays explicit.

Only closing the shown result permits settlement. The publication owner rereads
the same public post and checks that its exact text and final moderation flags
still match the displayed evidence before budget accounting and deletion.
Unavailable, pending, changed or wrong-account evidence preserves the slot.
This is result acknowledgement, not a second publication approval or a history
archive. No extra journal, result store or completed-effect list is introduced.

Local cancellation removes only the unsent effect and preserves an authoring
draft. Explicit abandonment without a receipt remains a distinct local action;
it claims neither provider absence nor successful publication and does not
reset the existing source cursor. Automatic cycles never choose it.
An empty effect journal is deleted after settlement. Completed replies and
community creation keep their existing settlement rules.

Only aggregate safety usage and source/feed cursors survive completion. A
transient settlement marker bridges budget accounting and effect deletion so
restart cannot double-charge a write; it is cleared after deletion. No text,
receipt archive, successful-effect counter or completed-effect list is retained.
Local budgets are not presented as provider statistics. UI account counters come
from a fresh bound Moltbook read; failure is shown as unavailable.

Deleting a local draft may cancel only its matching unapproved prepared effect.
Approved, queued, delivering or uncertain work requires the corresponding
explicit lifecycle action. Workspace loading repairs an orphan only when its
effect is still prepared; this repair makes no provider request.

### 4.2 Primary community and optional creation

Each Capsule configuration names one primary publication community. The
default is `m/person-first-runtime`, but a connected Moltbook account may use
another existing community without claiming ownership. Selecting a destination
is local policy only: it grants no moderator role, bypass, subscription, or
provider permission.

The same existing community effect may create a new user-selected community.
Creation binds the active Capsule, bound Moltbook account id, exact lowercase
name, display name, description, and explicit crypto-content policy before
approval. Delivery must re-observe the community and verify the complete
descriptor plus stable creator account id before recording success. A crypto
policy, descriptor, or owner mismatch is terminal conflict evidence. Timeout,
restart, or temporary `404` remains unresolved and permits observation only;
it never authorizes blind recreation. Exact preparation replay resumes the
same operation.

Community creation is a permanent explicit user action and is never required
to publish in an existing community. Moltbook rate limits, moderation rules,
and ownership responsibilities remain provider policy. AI cannot select,
create, rename, migrate, or broaden a destination. Existing posts are not
migrated and replies remain scoped to their original post community. Schema-v1
fixed PFR creation effects remain readable for in-flight 1.x compatibility;
new creation uses the exact configurable schema-v2 descriptor.

## 5. Lifecycle projection

The UI may project these phases:

```text
observed
  -> planned
  -> prose_proposed
  -> draft_bound
  -> awaiting_policy
  -> queued
  -> delivering
  -> verification_required
  -> succeeded
```

Terminal alternatives are `no_action`, `blocked`, `cancelled`, and `expired`.
`unresolved` is an effect condition projected as either
`verification_required` or `delivery_unknown`; it is never success.

Transition rules:

1. Observation alone grants no write authority.
2. WASM planning chooses an allowlisted action or `no_action`.
3. AI may propose prose only for the exact selected bounded observation.
4. WASM binds exact reviewed/selected prose to the target and plan hash.
5. Policy chooses Assisted or Bounded handling for the same bound draft.
6. One canonical effect is prepared and target-deduplicated before approval.
7. Assisted requires explicit exact approval. Bounded requires a valid WASM
   delegation authorization and current host budget.
8. The common effect processor delivers through the Moltbook adapter.
9. A numeric provider challenge may disclose only its prompt to the unlocked
   Capsule AI runtime. The existing effect owner submits one strict numeric
   answer; The selected inference provider receives no credential, action token, account identity, or
   publication authority.
10. Only a target-bound verified receipt produces `succeeded`.
11. An exact provider-referenced post marked as spam is a terminal provider
    rejection, not ambiguous delivery. It blocks publication retry but not the
    next independent effect.
12. A local closure never claims provider absence or requests another delivery.
    Missing profile history and HTTP errors are not proof of non-delivery.
    Explicit abandonment removes the local attempt rather than retaining an
    archive that permanently blocks independent work.
13. An exact post with `verification_status=failed` is a definite provider
    verification failure. A retained pending post may also settle when the
    durable effect records challenge expiry and the provider-created timestamp
    is beyond Moltbook's documented five-minute post challenge lifetime. A
    still-valid challenge, unknown provider status, mismatched post, or accepted
    verification awaiting its receipt remains unresolved.

## 6. Operating and trigger modes

The configuration separates **write policy** from **trigger policy**.

### 6.1 Write policy

- `observe_only`: no prose generation and no writes.
- `assisted`: exact user approval for every effect.
- `bounded`: eligible nested replies may proceed under the configured WASM
  authorization, daily budget, minimum interval, and stop control.

### 6.2 Trigger policy

- `on_demand`: the user starts one cycle.
- `session`: one catch-up cycle starts after the Capsule and plugin workspace
  are ready. This is the recommended default.
- `continuous_while_running`: cycles repeat while the application and selected
  Capsule remain active.

Trigger policy changes only when a cycle starts. It cannot change identities,
eligibility, deduplication, write authority, adapter behavior, or receipts.

There is no separate implementation for each mode. A future background host
must call the same cycle port and satisfy a separate platform threat model,
credential-access contract, stop control, and release gate.

## 7. One wake-run-sleep cycle

One cycle executes in this order:

1. Check the local `enabled` kill switch and Capsule/plugin/account binding.
2. Load the checkpoint and external-effect projection.
3. Reconcile unresolved effects before considering any new write.
4. Surface provider challenges; do not block unrelated eligible targets.
5. Fetch Home and paginated activity/feed pages until the checkpoint boundary,
   provider limit, or local cycle budget is reached.
6. Normalize and deduplicate observations by provider ids.
7. Before WASM selection, ask the existing publication owner to exclude every
   target already represented in the Capsule-scoped effect journal. Active and
   succeeded targets remain closed; cancelled or terminal targets require the
   existing explicit user reopen path and cannot be reopened by an automatic
   cycle. Also exclude targets expired by age policy, authored by self,
   unverified, spam-marked, locked, or outside allowed topics.
8. Evaluate the ordered heartbeat candidate set through WASM until one
   actionable target is selected or the set is exhausted. A `no_action` result
   closes only that candidate for the current cycle; it cannot starve later
   candidates. At most one actionable target may advance per cycle.
9. Claim at most one new proposal path: the selected remote target, or, when no
   remote target claimed it, the oldest pending Capsule public change. An older
   local draft does not starve a distinct confirmed change. If provider
   observation fails, only a local public-change draft may be prepared.
   A newer observed public-repository commit supersedes only older undrafted
   repository observations; prepared drafts and other sources remain intact.
10. Request an AI proposal if configured, retain confirmed public-change facts
    unchanged, and validate the exact advisory prose through WASM.
11. Under Assisted policy, prepare one immutable local effect and stop for exact
    human review. Under explicitly enabled Bounded policy, apply the current
    WASM authorization and host-owned durable budget to that same effect path.
    An occupied effect slot blocks every new external effect. Definite
    completion or explicit local abandonment releases the slot. An unresolved
    delivery that has not been explicitly abandoned continues to block it.
12. Process through the common adapter, observe the result, then settle and
    remove the completed effect before another may start.
13. Commit the checkpoint only through the newest safely observed boundary.
14. Publish a local cycle summary and stop.

Closing the application stops new cycles. The next launch resumes from durable
checkpoint/effect evidence. It must not infer that missed time implies missed
permission. Leaving the active Capsule runtime stops the same trigger owner and
clears its process-scoped AI unlock before another Capsule workspace can run.

## 8. Bounded limits

Every cycle has explicit limits. Initial v1 defaults are:

- at most 100 normalized remote items inspected per cycle;
- at most 5 candidates sent to deterministic planning;
- at most 3 committed bounded posts per UTC day in the local bounded policy;
- at least 30 minutes between committed bounded posts, matching Moltbook's
  server-side post limit;
- replies use their separate Moltbook comment budget and do not consume the
  post cooldown. The installed bounded reply contract keeps its own
  conservative local budget and floor while the provider's comment limit is
  enforced server-side;
- no automatic reply to a target older than the configured maximum age;
- the durable processed-id checkpoint may retain up to 500 ids, while each WASM
  heartbeat receives only the most recent 128 ids;
- no more than one cycle in flight per Capsule/plugin/account;
- no concurrent effect processing for the same `engagement_id`.

`approved`, `queued`, `delivering`, `unresolved`, and `succeeded` effects count
as committed. A provider challenge therefore consumes the target and budget
until resolved, cancelled safely, or expired according to provider evidence.

## 9. Challenges and failure behavior

- A challenge is bound to one operation and expiry. It cannot be reused.
- AI output is an untrusted numeric proposal, not authority, a receipt, or
  evidence that the hidden content became visible.
- Only an initial `verification_required` action may be solved automatically.
  A malformed AI response makes no provider request, and a rejected answer is
  not submitted again automatically.
- The exact prompt is the only provider challenge field disclosed to AI.
  Credentials, action tokens, provider references, effect payloads, and
  Capsule identifiers remain inside their existing owners.
- An accepted answer still requires provider re-observation and an exact
  receipt before success.
- Failure or expiry of one challenge does not stop observation or reconciliation
  of other targets.
- Network timeout remains unresolved and reconciles before any retry.
- An eligible `receipt_not_observed` attempt may be explicitly abandoned locally
  without claiming provider absence or success. Its source draft is removed and
  its existing source cursor is preserved, so automatic cycles cannot replay it.
- Revoked credentials stop remote reads/writes and preserve local evidence.
- Rate limits pause cycles until the provider reset time.
- Capsule switching cancels in-memory work; late completion cannot mutate the
  newly selected Capsule.
- If multiple legacy active effects exist for one target, all automatic
  delivery for that target is frozen and the UI requires explicit resolution.

## 10. UI contract

The primary surface shows one next action per engagement. It must not expose
Assisted and Bounded as two independent publication buttons after an effect has
been prepared.

Required projections:

- mode: write policy and trigger policy shown separately;
- current cycle: idle, observing, planning, proposing, delivering, or stopped;
- summary: cycle read/eligible/proposed/challenged/blocked, plus live account
  post/comment counters from Moltbook;
- engagement card: target, reason, exact draft, mode, effect state, receipt;
- for an eligible unconfirmed post, offer `Close unconfirmed attempt`; it
  rechecks first, performs no provider write, and retains deduplication identity;
- stop: immediately prevents new proposals/effects while preserving journals;
- while stopped, retained drafts and prepared effects require an explicit
  re-enable before review approval or queueing; inspection, cancellation, and
  reconciliation of existing journal entries remain available;
- diagnostics: hashes, provider ids, attempts, and raw state remain secondary.

If a target already has an active operation, the only primary action is to
continue, verify, reconcile, or cancel that operation. The UI may never offer a
second prepare/publish path for the same target.

Stop advances the cycle owner's generation. In-flight provider reads may
finish at the adapter boundary, but their late result cannot begin WASM/AI
planning, start another external effect, commit a checkpoint, or overwrite the
stopped UI projection. A replacement cycle waits for the stopped predecessor
to quiesce instead of creating a parallel route. An explicit local enable after
Stop opens one new `session` trigger for the same scope; repeated starts still
share that single trigger and cannot create a second cycle.

## 11. AI and hostile-input boundary

Remote Moltbook content and model output are untrusted data.

- The model sees only the selected public post, bounded comments, local public
  persona/topic policy, and deterministic plan.
- The model cannot choose provider account, endpoint, operation id, capability,
  write mode, budget, retry, approval, or receipt.
- Unknown fields, hidden controls, links outside policy, excessive length,
  secrets, tool syntax, and policy-changing instructions fail closed.
- AI unavailability may fall back to a manual local draft, never to unreviewed
  publication or a different model with broader authority.
- An Assisted cycle may send the bounded public conversation to the explicitly
  configured inference provider. Enabling Assisted cycle execution is consent
  for that bounded transfer; it is not consent to publish the response.
- Inference also requires an explicit process-memory AI lease. Automatic cycles
  never trigger an operating-system credential prompt. If the lease is locked,
  the cycle stops before inference and keeps the selected target retryable.
- The host owns the lease and clears it when the application exits. Moltbook
  state, WASM, provider adapters, and persisted plugin state never receive the
  inference credential.
- If inference or draft binding fails, the selected feed target is excluded
  from the committed checkpoint so a later cycle may retry it.

## 12. Release gates

Bounded mode remains non-reference-grade until all are true:

- duplicate Assisted/Bounded actions cannot create two active effects for one
  target;
- repeated click, restart, timeout, and late completion preserve one semantic
  reply;
- a succeeded target cannot be selected again;
- catch-up reaches the saved boundary without skipping or replaying targets;
- session and continuous modes produce identical decisions for identical
  normalized inputs and explicit times;
- stop prevents new AI/effect work immediately;
- numeric challenge solving remains Capsule-scoped, single-attempt, and
  restart-safe;
- daily/interval limits survive restart and Capsule switching;
- no secret, Core data, relationship data, or provider DTO enters AI or WASM;
- macOS and Android manual evidence passes with a disposable account.

The shipped default remains Assisted. Bounded requires explicit selection and
runs only while the application and AI lease are active. The inference provider cannot create
root comments, posts, votes, follows, direct messages, or broader authority;
it may only propose the numeric answer for a challenge attached to an already
authorized exact effect.
