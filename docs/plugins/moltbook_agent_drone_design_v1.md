# Moltbook Agent Drone - Design Contract v1

Status: deterministic drafts, read-only account/home/feed observation,
restart-safe feed identity checkpoints, and assisted publication lifecycle
implemented; bounded autonomy remains gated
Runtime impact: bounded WASM draft contract only
Primary owner: External Moltbook Drone

## 1. Purpose

This document defines how a user-owned Hivra Capsule may maintain an agent
presence on Moltbook without making Moltbook, AI inference, or social behavior
part of Hivra Core.

The target is not a Hivra social network. Moltbook is an external public
service used by one optional WASM drone. A Capsule remains useful when the
drone is absent, offline, revoked, or when Moltbook no longer exists.

## 2. Capability-Closure Verdict

Current verdict: `ASSISTED_PUBLICATION_IMPLEMENTED`; bounded autonomy remains
`NEEDS_THREAT_REVIEW`.

The existing bounded WASM runtime intentionally has no direct network imports,
secret access, or unrestricted storage. A Moltbook package therefore cannot be
implemented safely as WASM alone. Implementation may start only after the host
contracts below are approved.

Missing host capabilities:

- provider-scoped external identity registration and account binding;
- provider-scoped HTTPS read/publish effects;
- Capsule- and plugin-scoped secure credential storage;
- isolated plugin state and local activity journal;
- bounded inference requests over explicit redacted input;
- durable external-effect operation ids, retries, and receipts;
- foreground scheduling with an explicit online/offline lifecycle.

No temporary direct HTTP call from a screen or WASM import may close these
gaps. The currently implemented draft contract does not close them: it only
turns an explicit Public Bulletin into a deterministic, approval-gated draft.

## 3. Ownership and Dependency Stack

```text
User intent / approved autonomy policy
  -> Moltbook Drone contract (decision owner)
    -> WASM Host capability API
      -> External Effect lifecycle (operation/receipt owner)
        -> Moltbook Adapter (protocol owner)
          -> Moltbook HTTPS API
```

Optional inference follows a separate downward path:

```text
Moltbook Drone
  -> bounded inference request
    -> InferenceProvider port
      -> selected provider adapter
```

Responsibilities:

- **Moltbook Drone** owns feed policy, topic policy, draft construction,
  response selection, rate budget, and user-facing history.
- **WASM Host** validates package identity, method scope, granted capabilities,
  canonical input/output, and resource bounds.
- **External Effect lifecycle** owns stable operation ids, retries,
  idempotency, terminal receipts, and restart recovery.
- **Moltbook Adapter** owns endpoint shapes, authentication headers, response
  parsing, provider error mapping, and the Moltbook domain allowlist.
- **InferenceProvider** owns the selected AI protocol only. It does not own
  publication policy or external effects.
- **App Shell** projects state and collects user intent. It does not recreate
  drone policy or call Moltbook directly.
- **Core, Ledger, Trust Layer, Pair Consensus, and Capsule Transport** do not
  depend on Moltbook or its DTOs.

## 4. Identity Model

A Capsule root identity and a Moltbook agent identity are distinct.

- Moltbook registration creates an external account controlled through a
  Moltbook credential and its human-owner claim flow.
- The external account is bound locally to exactly one Capsule root and one
  installed plugin identity.
- A Capsule seed does not derive, replace, or recover a Moltbook API key.
- Moltbook credentials must never be reused as Capsule, transport, signing, or
  inference credentials.
- Moltbook does not become an authority for Capsule identity, relationships,
  consensus, or recovery.

The initial registration flow is explicit:

1. User selects one Capsule and requests Moltbook registration.
2. Host submits the bounded registration effect.
3. Moltbook returns account/claim evidence and a credential when supported by
   the provider flow.
4. User completes the external human-owner verification.
5. Host verifies the resulting account identity before activating publishing.
6. Credential and binding metadata are stored under the selected Capsule and
   plugin scope. The credential uses `(capsule_root, plugin_id, provider_id,
   provider_account_id, secret_name)` in the generic secure vault. The
   non-secret account binding uses isolated plugin state and does not change
   the Core ledger.

## 5. Data Authority and Storage

| Data | Storage owner | Authority |
| --- | --- | --- |
| Moltbook profile, posts, comments, votes, follows, reputation | Moltbook | Moltbook |
| Moltbook API credential | platform secure storage | local Capsule binding |
| AI provider credential | platform secure storage | local provider binding |
| private persona/policy, allowed topics, autonomy limits | isolated plugin state | Moltbook Drone |
| unpublished drafts and approval state | isolated plugin state | Moltbook Drone |
| feed cursor, processed remote ids, bounded cache | isolated plugin state | Moltbook Drone |
| publication operation ids, attempts, and receipts | external-effect journal | Runtime External Effects |
| local decision/audit history | plugin activity journal | Moltbook Drone |
| Capsule seed, ledger, relationships, consensus evidence | Capsule storage | Hivra Core/runtime owners |

Secure credential lookup is scoped by at least:

```text
(capsule_root, plugin_id, provider_id, provider_account_id)
```

The user-facing Ambassador configuration is one host-owned plugin-state
document, not a manifest extension or a Core record. It contains only the
Moltbook profile and local policy: `agent_name`, `agent_description`,
`persona_summary`, `allowed_topics`, `approval_mode`, and `enabled`.
`agent_name` and `agent_description` customize the external agent only; they
never rename the Capsule or plugin. Credentials, claim tokens, seeds, transport
keys, ledger data, and contact data are excluded. The draft-only WASM method
does not consume this configuration until the host registration, preview, and
publication ports exist.

Rules:

- Public Moltbook state is projected locally; it is not copied into the Core
  ledger as Capsule truth.
- Drone decisions and operational receipts use a plugin-scoped journal, not
  relationship or consensus events.
- Secrets never enter WASM memory, canonical plugin payloads, logs, UI state,
  the Core ledger, ordinary Capsule backup, or AI prompts.
- Non-secret plugin state must be isolated from other Capsules and plugins.
- Sensitive private memory must be encrypted at rest or omitted entirely.
- Cache loss may cause a bounded re-sync but must not cause duplicate posts.

## 6. Processing Pipeline

```text
explicit Public Bulletin
  -> Moltbook Drone draft contract
  -> normalized public facts
  -> deterministic eligibility/policy gate
  -> optional minimized AI inference
  -> canonical draft
  -> explicit approval

Future remote mode:

remote feed -> Moltbook Adapter -> normalized untrusted content
  -> deterministic eligibility/policy gate -> canonical draft
  -> approval/autonomy gate -> durable publish operation
  -> Moltbook Adapter -> remote receipt -> local plugin projection
```

All Moltbook content, including apparent instructions to the agent, is
untrusted input. It cannot grant capabilities, alter policy, request secrets,
invoke developer tools, access repositories, execute code, or bypass user
approval.

AI output is also untrusted advisory data. A deterministic host/drone policy
must validate output shape, topic, target, size, rate budget, and action class
before a publish operation can be created.

## 7. Operating Modes

### 7.1 Observe

- Read approved feeds/submolts.
- Build a local projection and summaries.
- No remote write capability.

### 7.2 Assisted

- Prepare posts or replies.
- Show source context, reason, destination, and exact outbound text.
- Require explicit user approval for every remote write.
- This is the required first releasable mode.

### 7.3 Bounded Interactive

- Run only while the Capsule runtime is online.
- Publish within an explicit topic allowlist, action allowlist, time window,
  and rate budget.
- Keep a visible stop control and durable receipt history.
- High-risk, ambiguous, private, financial, promotional, or identity-related
  content always returns to manual approval.

There is no background-service promise in v1. Closing the application stops
new reads and decisions. Moltbook retains already-published remote state.

## 8. Method Scopes

Current draft contract: `hivra.contract.moltbook-ambassador.v1`.

Current methods:

- `prepare_moltbook_draft`: `solo`, deterministic draft preparation from an
  explicit Public Bulletin; no network effect.
- `plan_moltbook_heartbeat`: `solo`, deterministic prioritization of one
  host-normalized Home/Feed snapshot; no network effect.

Future remote contract methods are not implemented yet:

Proposed methods:

- `prepare_moltbook_post`: `solo`, pure draft decision;
- `prepare_moltbook_reply`: `solo`, pure draft decision;
- `publish_moltbook_content`: `solo`, explicit external write effect;
- `sync_moltbook_receipts`: `solo`, remote read and local projection update;
- `revoke_moltbook_binding`: `solo`, explicit credential/binding teardown.

Pair Consensus is not required for one Capsule operating its own external
account. Any later collaborative or delegated publishing protocol must use a
new explicitly `pair_scoped` or group protocol; it must not silently add a
peer requirement to these solo methods.

## 9. Security and Privacy Contract

- HTTPS host is pinned to an explicit Moltbook domain allowlist.
- Adapter endpoints and methods are allowlisted; there is no generic fetch.
- Read and publish capabilities are separate grants.
- Registration, credential rotation, revocation, and account deletion require
  explicit user confirmation.
- Remote write operations use stable local operation ids and provider-supported
  idempotency where available.
- Retry never creates a second semantic publication.
- Provider rate limits and terminal errors are visible and deterministic.
- Remote text is never interpreted as a tool instruction.
- Outbound AI context is minimized, previewable in Assisted mode, and contains
  no Capsule secrets or broad private history.
- Published content must be treated as public and potentially permanent.
- The user is responsible for the agent's external actions under the provider
  terms; autonomy defaults to off.

External references are informative, not Hivra protocol authorities:

- `https://www.moltbook.com/`
- `https://www.moltbook.com/skill.md`
- `https://www.moltbook.com/privacy`
- `https://www.moltbook.com/terms`

The Phase 2 adapter baseline was checked against official Moltbook skill
contract `1.12.0` on 2026-07-26. Provider documentation remains informative:
the local allowlist and tests are the executable Hivra boundary.

Observe v1 permits only:

- origin `https://www.moltbook.com`;
- path prefix `/api/v1/`;
- `GET /api/v1/agents/me`;
- `GET /api/v1/agents/status`;
- `GET /api/v1/home`.

The adapter rejects redirects, non-HTTPS origins, malformed JSON, missing
required fields, invalid rate-limit headers, and responses over 256 KiB. Its
default request timeout is 12 seconds. It reads `X-RateLimit-Limit`,
`X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `Retry-After`; the documented
provider read budget is 60 requests per 60 seconds per API key.

Observe does not use the External Effects journal because a bounded read is not
an external write effect. Future publication uses the provider-neutral
External Effects lifecycle and must not add a second retry journal.

## 10. Recovery and Failure Semantics

- Offline: retain the cursor and pending local drafts; do not invent remote
  success.
- Timeout: operation remains unresolved until receipt reconciliation.
- Restart: resume unresolved operations by stable operation id.
- Credential revoked: disable remote effects and request re-authentication.
- Plugin removed: revoke local grants and remove local non-secret plugin state
  only after user confirmation; remote account remains external.
- Capsule restored from seed: Moltbook access is not automatically restored.
  User recovers through the Moltbook owner flow and rotates/imports the
  external credential.
- Moltbook unavailable or discontinued: Capsule, Core state, other drones, and
  local private history continue to work.

Ordinary distributed Capsule backup excludes Moltbook and inference secrets.
An optional encrypted secret export would require a separate threat model and
must never be enabled implicitly.

## 11. Hivra Laws Gate

### Modularity

- Moltbook behavior lives in the external plugin repository.
- Provider protocol and effects live in one host adapter/lifecycle boundary.
- Core and generic transport contain no Moltbook branches.

### Determinism

- The same normalized remote snapshot, local policy, explicit time input, and
  model result produce the same canonical draft/decision hash.
- AI text never becomes hidden decision state.
- Every remote effect has one stable operation id and terminal receipt state.

### Dependencies strictly downward

- `UI -> Moltbook Drone contract -> WASM Host -> External Effect port -> adapter`.
- Concrete adapter DTOs do not cross their port.
- Moltbook, AI, UI, and plugin state never become dependencies of Core.

## 12. Approved Implementation Plan

This order is normative. A later phase cannot begin by bypassing an
unimplemented contract from an earlier phase.

### Phase 0 - Draft Baseline

Status: implemented locally; plugin source published outside Discover.

- Keep Public Bulletin production explicit, bounded, and reviewable.
- Keep `prepare_moltbook_draft` deterministic and approval-required.
- Keep Ambassador profile and policy isolated by `(capsule_root, plugin_id)`.
- Do not grant network, credential, ledger, or generic filesystem access to
  WASM.

Exit gate:

- plugin tests, manifest validation, host contract tests, and profile isolation
  tests pass;
- the package remains absent from Discover.

### Phase 1 - Provider-Neutral External Effects

Status: `HOST_BASELINE_IMPLEMENTED`.

The normative provider-neutral lifecycle is
`docs/architecture/external-effect-lifecycle.md`. Moltbook does not define a
second state machine, journal, retry owner, or receipt type.

The implemented generic host path is:

```text
prepare -> approve -> enqueue -> deliver -> reconcile -> terminal receipt
```

It is Capsule/plugin isolated, contains no credential, reconciles before retry,
and rejects stale adapter completions by state/revision. The Moltbook adapter
is mounted only at the application composition boundary.

Exit gate:

- completed: transition, idempotency, persistence, restart, cancellation, and
  stale-completion rules are owned by the generic architecture contract;
- completed: fake-adapter tests prove timeout/retry/restart and concurrent
  calls without duplicate effects;
- completed: Core, ledger, generic transport, and WASM contain no provider DTO;
- completed: Moltbook endpoint, timeout, response-size, redirect, error, and
  rate-limit policy is isolated in one provider adapter.

### Phase 2 - Moltbook Adapter and Observe Mode

Status: account connection, strict read-only Account/Home/Feed Observe,
deterministic WASM heartbeat planning, and durable feed identity checkpoints
mounted.

- Completed: implement one strict Moltbook adapter for normalized Observe
  projections.
- Completed: pin allowed HTTPS host, paths, methods, request timeout, response
  size, redirects, and provider error mapping.
- Completed: bind credentials in platform secure storage by Capsule, plugin,
  provider, and external account only after the adapter verifies the key.
- Completed: one generic secure plugin-credential vault is scoped by Capsule,
  plugin, provider, external account, and secret name; Capsule deletion and
  plugin removal delete the corresponding scopes before destructive cleanup.
- Completed: mount account connection, verification, rotation, and local
  disconnect on that vault without adding a second provider-specific
  credential store.
- Completed: ordinary workspace loading reads only non-secret binding metadata
  and does not access Secure Storage. Explicit Connect and Refresh own the
  credential access.
- Completed: mount bounded Home observation as an explicit in-memory read. It
  does not create ledger events, plugin cache, or a second retry lifecycle.
- Completed: mount a bounded `new` feed observation as an explicit in-memory
  read with strict normalized post projections and no provider DTO leakage.
- Completed: pass one Home/Feed observation through the external WASM package
  and return only `review_activity`, `inspect_feed`, or `idle`; the plan always
  requires review and cannot create an external effect.
- Completed: normalize activity on the agent's own posts as bounded structured
  Home data. A `review_activity` plan returns only those exact post ids, while
  an `inspect_feed` plan returns only verified non-spam feed ids.
- Completed: persist one bounded Capsule/plugin-scoped checkpoint containing
  only processed post ids, newest post id, observation time, and the last
  continuation cursor. Remote title/body/author content is never persisted.
- Completed: every heartbeat starts from the newest feed page. Provider
  `next_cursor` is used only for a bounded second page inside that heartbeat,
  because it paginates toward older posts and is not a cross-session
  "since-new" cursor.
- Completed: stop bounded pagination when a previously processed post is
  reached, pass only unseen post ids to WASM, and commit the checkpoint only
  after a valid no-effect plan returns.
- Treat every remote field as untrusted data.

Exit gate:

- read-only Observe mode survives offline, timeout, malformed response,
  credential revocation, restart, and rate-limit tests;
- no remote write capability is granted.

### Phase 3 - Ambassador Workspace

Status: local profile/policy, read-only Connection, deterministic WASM Draft
Preview, and durable assisted-publication surfaces implemented.

The plugin card opens a dedicated workspace. The generic Plugins screen shows
installation and health only; it must not become a provider dashboard.

The current workspace contains local `Profile`, `Stop`, read-only `Connection`,
and exact `Draft Preview` controls. Connection verifies the API key through the
host adapter, then moves it into the generic secure vault and clears the input.
Draft Preview accepts only an explicit bounded Public Bulletin, invokes the
installed WASM package through the plugin host, and projects the validated
title, body, audience, safety flags, approval gate, and canonical draft hash.
The validated result is stored in one bounded Capsule/plugin-scoped local draft
history, deduplicated by canonical hash, with status `awaiting_approval`.
Deleting it removes only the local draft. It neither reads the credential nor
creates a remote effect. The screen retains only non-secret account metadata
and does not imply remote write execution.

The complete workspace will contain:

1. `Connection`: provider account, verification state, reconnect, revoke.
2. `Profile`: agent name, description, persona, allowed topics, enabled state.
3. `Drafts`: exact deterministic preview and bounded durable local draft
   history are implemented.
4. `Approval Queue`: operations awaiting explicit approval.
5. `Activity`: delivery state, attempts, receipts, and actionable errors.
6. `Stop`: immediate local disable without pretending to delete remote state.

The UI reads host projections. It does not call the adapter directly, store
credentials in widget state, or translate provider responses into domain
truth.

Exit gate:

- switching Capsules cannot display or mutate another Capsule's binding,
  drafts, operations, or profile;
- removing the plugin clears local non-secret plugin state after confirmation,
  while external account deletion remains a separate provider action.

### Phase 4 - Assisted Publication

Status: host implementation and fake-provider tests complete. The macOS
Release smoke completed the real nested-provider challenge flow through a
publicly visible verified post. Android manual smoke remains.

- Completed: convert one canonical draft into one stable durable external
  operation.
- Completed: show exact destination, account, title/body, public repository
  attribution, and permanence warning before approval. The operation marker is
  embedded in the attribution URL for machine reconciliation instead of being
  exposed as an unreadable public suffix.
- Completed: require explicit approval and a separate explicit publish action
  for every post.
- Completed: bind credential lookup to the originating Capsule, plugin,
  provider, and external account rather than the currently selected Capsule.
- Completed: reconcile a provider receipt before showing success.
- Completed: treat verification challenges, missing receipts, timeouts, and
  absent reconciliation markers as unresolved instead of inventing success or
  blindly resubmitting.
- Completed: expose cancel-before-delivery and reconciliation controls through
  the one generic external-effect journal.
- Completed: persist nested `post.verification` as a provider-neutral required
  action, show the exact challenge and expiry, submit an explicit numeric
  answer through the adapter, and require the verification receipt to bind the
  exact post id before recording success.
- Completed: legacy or expired challenges remain fail-closed without blind
  resubmission.
- Completed manual macOS evidence on 2026-07-27: one approved operation created
  hidden post `32a3006b-94e3-4087-82f6-58e3666cef4e`, persisted the provider
  challenge as unresolved, accepted one explicit answer, then recorded success
  only after the exact post id, approved text, operation marker, and
  `verification_status=verified` were observed.
- Completed: the Ambassador surface presents one prominent next action for the
  Draft, Review, Approve, Publish, and Verify sequence; provider-neutral
  operation details remain available as diagnostics rather than primary
  navigation.

Exit gate:

- duplicate-click, timeout-after-provider-acceptance, restart, retry,
  cancellation, and revoked-credential cases produce at most one semantic
  publication;
- macOS and Android manual smoke passes with a disposable Moltbook agent.

### Phase 5 - Discover and Later Autonomy

Discover publication is allowed only after Phases 1-4 pass automated and
manual release evidence. The signed catalog entry must pin the reviewed package
hash and minimum host ABI/capabilities.

Bounded Interactive mode remains a separate future decision. It requires a new
threat review and replay, prompt-injection, rate-limit, revocation, kill-switch,
and unattended-restart tests. It must not be enabled by changing a profile
field in the Assisted release.

No phase may add direct network or secure-storage access to WASM.
