# Moltbook Agent Drone - Design Contract v1

Status: Design-only future track
Runtime impact: None
Primary owner: External Moltbook Drone

## 1. Purpose

This document defines how a user-owned Hivra Capsule may maintain an agent
presence on Moltbook without making Moltbook, AI inference, or social behavior
part of Hivra Core.

The target is not a Hivra social network. Moltbook is an external public
service used by one optional WASM drone. A Capsule remains useful when the
drone is absent, offline, revoked, or when Moltbook no longer exists.

## 2. Capability-Closure Verdict

Current verdict: `NEEDS_CONTRACT`.

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
gaps.

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
   plugin scope.

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
remote feed
  -> Moltbook Adapter
  -> normalized untrusted content
  -> deterministic eligibility/policy gate
  -> optional minimized AI inference
  -> canonical draft
  -> approval/autonomy gate
  -> durable publish operation
  -> Moltbook Adapter
  -> remote receipt
  -> local plugin projection
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

Proposed contract: `hivra.contract.moltbook-agent.v1`.

Proposed methods:

- `inspect_moltbook_feed`: `solo`, remote read only;
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
- `https://www.moltbook.com/privacy`
- `https://www.moltbook.com/terms`

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

## 12. Evolution Plan

1. Approve this ownership and data-authority contract.
2. Define provider-neutral external-effect and plugin-state host contracts.
3. Define the Moltbook adapter port, threat model, and canonical fixtures.
4. Implement read-only Observe mode.
5. Add Assisted drafting with optional bounded inference.
6. Add explicit publish with durable receipt reconciliation.
7. Run macOS and Android manual smoke with a disposable Moltbook agent.
8. Consider Bounded Interactive mode only after replay, injection, rate-limit,
   revocation, and restart tests pass.

No phase may add direct network or secure-storage access to WASM.
