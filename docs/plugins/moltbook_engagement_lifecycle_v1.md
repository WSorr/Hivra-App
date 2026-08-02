# Moltbook Engagement Lifecycle v1

Status: normative design contract; Assisted remote-engagement cycle implemented,
package 6 release evidence in progress

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
- Gemini or another inference provider never receives credentials or an effect
  capability.
- WASM does not receive network or secure-storage access.
- This contract does not promise an always-running server or background daemon.
- Anti-spam challenges are not solved or bypassed automatically.
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
- a newer foreign follow-up is a different target because it has a different
  parent comment id;
- a cancelled or expired target may be reopened only through an explicit
  user action; automatic modes do not reopen it.

Before preparing a new provider effect, the host must scan the existing
Capsule/plugin external-effect journal by canonical target fields. A matching
active or succeeded effect blocks creation of another operation. This check is
mandatory even when the new draft text or AI proposal hash differs.

### 3.3 Effect identity

An external-effect operation represents one frozen exact outbound payload.
Its stable operation id and payload hash remain owned by the generic External
Effects lifecycle. The Moltbook workflow additionally binds that operation to
`engagement_id`.

Editing text is allowed before effect preparation. After preparation, text is
immutable. Replacing a prepared draft requires explicit cancellation first;
automatic modes cannot replace it. Cancellation does not erase journal
history or permit blind provider resubmission after an ambiguous outcome.

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
| delivery, challenge, retry, receipt | external-effect journal |

No screen may keep an independent authoritative status. If evidence disagrees,
the fail-closed external-effect state wins for remote-write progress.

A local post draft is authoring state, not publication history. Once the
external-effect journal contains a validated `succeeded` post operation bound
to that draft's `source_draft_hash_hex`, the application composition owner
must archive the matching draft. Loading the workspace performs the same
reconciliation for pre-existing data. Failed, cancelled, unresolved, queued,
reply, or malformed operations must not archive post drafts.

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
9. Provider challenge remains unresolved until explicit human completion.
10. Only a target-bound verified receipt produces `succeeded`.

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
7. Exclude targets already active, succeeded, expired by age policy, authored
   by self, unverified, spam-marked, locked, or outside allowed topics.
8. Ask WASM to rank/plan a bounded candidate set.
9. For selected targets only, request an AI proposal if configured.
10. Validate and bind exact prose through WASM.
11. Under Assisted policy, prepare one immutable local effect and stop for exact
    human review. Under a separately released Bounded policy, apply the current
    delegation authorization.
12. Process authorized effects through the common adapter and record receipts.
13. Commit the checkpoint only through the newest safely observed boundary.
14. Publish a local cycle summary and stop.

Closing the application stops new cycles. The next launch resumes from durable
checkpoint/effect evidence. It must not infer that missed time implies missed
permission.

## 8. Bounded limits

Every cycle has explicit limits. Initial v1 defaults are:

- at most 100 normalized remote items inspected per cycle;
- at most 5 candidates sent to deterministic planning;
- at most 3 committed replies per UTC day;
- at least 30 minutes between committed replies;
- no automatic reply to a target older than the configured maximum age;
- no more than one cycle in flight per Capsule/plugin/account;
- no concurrent effect processing for the same `engagement_id`.

`approved`, `queued`, `delivering`, `unresolved`, and `succeeded` effects count
as committed. A provider challenge therefore consumes the target and budget
until resolved, cancelled safely, or expired according to provider evidence.

## 9. Challenges and failure behavior

- A numeric/provider challenge always requires explicit user action.
- A challenge is bound to one operation and expiry. It cannot be reused.
- Failure or expiry of one challenge does not stop observation or reconciliation
  of other targets.
- Network timeout remains unresolved and reconciles before any retry.
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
- summary: read, eligible, proposed, published, challenged, blocked;
- engagement card: target, reason, exact draft, mode, effect state, receipt;
- stop: immediately prevents new proposals/effects while preserving journals;
- diagnostics: hashes, provider ids, attempts, and raw state remain secondary.

If a target already has an active operation, the only primary action is to
continue, verify, reconcile, or cancel that operation. The UI may never offer a
second prepare/publish path for the same target.

Stop advances the cycle owner's generation. In-flight provider reads may
finish at the adapter boundary, but their late result cannot begin WASM/AI
planning, start another external effect, commit a checkpoint, or overwrite the
stopped UI projection. A replacement cycle waits for the stopped predecessor
to quiesce instead of creating a parallel route.

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

## 12. Implementation work packages

1. **Identity and projection (implemented)**: canonical `engagement_id`,
   Capsule-scoped target lookup, legacy duplicate freeze before approval or
   delivery, and projection/restart/concurrency tests.
2. **Single orchestration port (implemented)**: Assisted and Bounded writes use
   one `advanceMoltbookEngagement` use case; the screen cannot authorize,
   queue, deliver, or compensate an engagement through a parallel route.
3. **Cycle engine (implemented)**: one Capsule/account-scoped in-flight cycle
   reconciles unresolved effects, performs paginated heartbeat observation and
   deterministic WASM planning, selects at most one target, obtains one bounded
   AI proposal in Assisted mode, binds it through WASM, and prepares one local
   immutable effect. It commits the checkpoint only after ownership checks and
   never approves, queues, delivers, or solves a challenge automatically.
4. **Trigger policies (implemented)**: a single application controller mounts
   `on_demand`, once-per-process `session`, and sequential
   `continuous_while_running` triggers over the same cycle port. Continuous
   wake-ups never overlap, are scoped by Capsule/plugin/account, and stop
   without deleting checkpoints or effect evidence. Existing schema-v1
   profiles migrate to `on_demand`; no autonomous mode is enabled implicitly.
5. **UI projection (implemented)**: one canonical workspace projection gives
   active challenged/unresolved/queued effects priority over every new draft
   path, exposes one primary next action, shows write and trigger policy
   separately, keeps Stop visible, projects bounded cycle/effect counts, and
   moves provider ids, hashes, attempts, checkpoints, and manual provider reads
   into secondary technical details. Bounded publication is not exposed by the
   release UI before package 6 evidence passes.
6. **Release evidence**: hostile input, duplicate target, restart, timeout,
   challenge, Capsule switch, rate limit, kill switch, macOS, and Android.
   Deterministic tests cover the hostile-input boundary, semantic
   deduplication, restart reconciliation, provider timeout/challenge/rate-limit
   mapping, Capsule/account changes, and the generation-bound Stop contract.
   Packaged-artifact evidence remains mandatory on both platforms.

## 13. Release gates

Bounded or automatic mode remains unreleasable until all are true:

- duplicate Assisted/Bounded actions cannot create two active effects for one
  target;
- repeated click, restart, timeout, and late completion preserve one semantic
  reply;
- a succeeded target cannot be selected again;
- catch-up reaches the saved boundary without skipping or replaying targets;
- session and continuous modes produce identical decisions for identical
  normalized inputs and explicit times;
- stop prevents new AI/effect work immediately;
- challenges remain human-only and restart-safe;
- daily/interval limits survive restart and Capsule switching;
- no secret, Core data, relationship data, or provider DTO enters AI or WASM;
- macOS and Android manual evidence passes with a disposable account.

Until these gates pass, the shipped default remains Assisted and automatic
cycle controls remain hidden or clearly marked experimental.
