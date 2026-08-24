# Moltbook Agent Drone - Design Contract v1

Scope: Optional Capsule-operated public presence on Moltbook
Primary owner: External Moltbook Drone

This document owns capability, identity, storage, inference, and provider
boundaries. Canonical engagement identity, deduplication, trigger policies,
cycle execution, and UI projection belong to
`moltbook_engagement_lifecycle_v1.md`. External write state belongs to
`../architecture/external-effect-lifecycle.md`; inference authority separation
belongs to `../architecture/ai-proposal-boundary.md`.

Current product status and the next selected unit belong only to
`../development-control.md`. Git and release evidence retain implementation
history.

## 1. Product Outcome

A user-owned Capsule may maintain an optional public Moltbook presence without
making Moltbook, AI inference, or social behavior part of Hivra Core.

The user can observe public activity, prepare exact posts or replies, review
their destination and permanence, approve bounded effects, stop future work,
and reconcile provider receipts. The Capsule remains useful when the drone is
absent, offline, revoked, or when Moltbook no longer exists.

## 2. Capability Closure

The WASM runtime has no direct network, credential, unrestricted storage, or
external-effect access. Moltbook therefore uses existing host capabilities:

- provider-scoped account binding and HTTPS adapter;
- Capsule/plugin-scoped secure credential storage;
- isolated plugin state and activity projection;
- bounded inference over explicit minimized input;
- the provider-neutral External Effects lifecycle;
- the canonical Moltbook engagement lifecycle.

No screen, WASM import, AI response, or provider DTO may bypass these owners.
Adding a new action class requires an explicit host capability and deterministic
WASM contract before UI exposure.

## 3. Ownership and Dependencies

```text
user intent or bounded policy
  -> Moltbook Drone contract
    -> WASM Host capability
      -> External Effects lifecycle
        -> Moltbook adapter
          -> Moltbook HTTPS API
```

Optional inference is separate:

```text
Moltbook Drone
  -> Capsule AI Runtime request
    -> selected inference provider adapter
  -> validated advisory proposal
  -> deterministic WASM binding
```

- **Moltbook Drone** owns topic policy, content selection, draft semantics,
  action budget, and plugin-facing history.
- **WASM Host** owns package identity, capability, method, schema, and resource
  validation.
- **External Effects** owns operation identity, retries, receipts, cancellation,
  and restart reconciliation.
- **Moltbook Adapter** owns allowed endpoints, authentication headers, bounded
  response parsing, and provider error mapping.
- **Capsule AI Runtime** owns provider selection and inference sessions only.
- **App Shell** projects state and collects user intent.
- **Core, Ledger, Trust Layer, Pair Consensus, and Capsule transport** have no
  Moltbook dependency or DTO.

## 4. Identity

Capsule identity and Moltbook agent identity are distinct.

- One external account binding belongs to exactly one Capsule root and plugin
  identity.
- A Capsule seed does not derive or recover a Moltbook credential.
- Moltbook credentials cannot act as Capsule, transport, signing, or inference
  credentials.
- Moltbook cannot authorize Capsule identity, relationships, consensus, or
  recovery.
- Account registration, owner verification, rotation, disconnect, and deletion
  remain explicit provider operations.

The host verifies the provider account before publishing is enabled. Secret
scope is at least:

```text
(capsule_root, plugin_id, provider_id, provider_account_id, secret_name)
```

## 5. Data and Storage Authority

| Data | Owner |
| --- | --- |
| Public profile, posts, comments, votes, follows, reputation | Moltbook |
| Moltbook credential | platform secure vault |
| AI credential and process lease | Capsule AI Runtime / secure vault |
| Persona, topic policy, limits, enablement | isolated plugin state |
| Drafts and approval state | isolated plugin state |
| Feed checkpoints and bounded processed-id cache | isolated plugin state |
| Publication operations, attempts, and receipts | External Effects journal |
| Local decision/activity projection | Moltbook Drone |
| Capsule seed, Ledger, relationships, consensus | existing Capsule owners |

Secrets never enter WASM memory, plugin payloads, logs, widget state, Ledger,
ordinary Capsule backup, AI prompts, or public effects. Public provider state
is a local projection, not Capsule truth. Cache loss may cause a bounded read
but cannot authorize duplicate publication.

The user-facing profile contains only non-secret local policy such as agent
name, description, persona summary, allowed topics, approval mode, trigger
policy, and enablement. It cannot rename the Capsule or plugin.

## 6. Content Pipeline

### 6.1 Public bulletin

```text
explicit public facts and fixed Capsule-first anchor
  -> optional minimized AI proposal
  -> exact user review/edit
  -> deterministic WASM draft
  -> policy validation
  -> local prepared effect
  -> explicit approval
  -> External Effects delivery and receipt
```

The AI receives only explicitly public source notes, selected public topic,
public persona, and the fixed product anchor. It receives no Ledger, contacts,
private Capsule history, repository files, credentials, or provider DTOs.

### 6.2 Engagement

```text
bounded public conversation
  -> deterministic eligibility and target selection
  -> optional minimized AI reply proposal
  -> deterministic WASM target/text binding
  -> canonical engagement lifecycle
  -> approval policy
  -> External Effects delivery and receipt
```

Remote content and AI output are untrusted data. Neither can select an
endpoint, credential, capability, operation id, authority scope, or delivery
state. Validation rejects unknown fields, hidden text controls, target drift,
unsupported action classes, and policy/rate violations.

Product-news generation accepts facts only through the Public Change Feed
defined in `moltbook_engagement_lifecycle_v1.md`. It cannot read Capsule
Analyst output or create another draft/effect queue.

## 7. Operating Modes

### Observe

Read and project allowed public provider state. No write capability.

### Assisted

Prepare exact content and show source, reason, destination, account, and
permanence. Every remote write requires explicit user approval.

### Bounded Interactive

Allow only explicitly enabled action classes within topic, time, rate, and
daily budgets while the Capsule runtime and required AI lease are active.
Ambiguous, private, financial, promotional, identity-related, or policy-drifted
content returns to manual approval.

Write policy and trigger policy are independent. `on_demand`, `session`, and
`continuous_while_running` invoke the same canonical lifecycle. Closing the
application stops new local reads and decisions; it creates no background
service promise and does not undo already public provider state.

## 8. WASM Method Boundary

Contract: `hivra.contract.moltbook-ambassador.v1`.

Current deterministic methods:

- `prepare_moltbook_draft`
- `plan_moltbook_heartbeat`
- `plan_moltbook_engagement`
- `prepare_moltbook_reply`
- `authorize_moltbook_delegated_reply`

These methods prepare, select, bind, or authorize canonical data. They perform
no network request and receive no credential. A remote write still requires
the host capability, canonical effect envelope, applicable approval, and
External Effects owner.

All methods are `solo`. Pair Consensus is not required for one Capsule
operating its own account. A future collaborative protocol must declare a new
pair- or group-scoped contract rather than adding an implicit peer dependency.

## 9. Provider Adapter Boundary

- HTTPS origin and API prefix are pinned to the reviewed Moltbook allowlist.
- Reads and writes use separate grants; there is no generic fetch capability.
- Redirects, malformed responses, oversized payloads, missing required fields,
  unsupported methods, and invalid rate metadata fail closed.
- Provider text is never interpreted as a tool instruction.
- Stable local operation identity and provider-supported idempotency prevent a
  blind second semantic publication.
- Reconciliation binds exact account, destination, parent target when present,
  approved content, and provider receipt type.
- Verification challenges are explicit unresolved provider actions. Numeric
  answers and receipts must bind the exact operation and remote object.

Provider documentation is informative, not Hivra authority. Endpoint and
response policy is executable only through the adapter allowlist and tests.

## 10. Failure and Recovery

- **Offline:** retain local checkpoints and drafts; do not invent success.
- **Timeout:** keep the write unresolved until reconciliation.
- **Restart:** recover by stable engagement and effect operation identity.
- **Duplicate action:** return the existing operation/projection.
- **Revoked credential:** disable provider effects and require explicit
  re-authentication.
- **Capsule switch or Stop:** invalidate in-flight generation before another
  effect can be created.
- **Plugin removal:** revoke grants and remove scoped local state and secrets;
  external account deletion remains separate.
- **Seed restore:** does not silently restore external credentials.
- **Provider disappearance:** leaves Capsule, Core, other drones, and local
  private state operational.

Ordinary distributed backup excludes Moltbook and inference secrets. Any
encrypted secret export requires a separate threat model and explicit user
action.

## 11. Release Boundary

A releasable Moltbook capability must prove:

- Capsule and plugin isolation;
- hostile-input and malformed-provider rejection;
- exact approval or bounded-policy binding;
- one target and one semantic effect under duplicate click, timeout, restart,
  retry, and reconciliation;
- credential revocation and Stop behavior;
- challenge handling without blind resubmission;
- packaged macOS and Android behavior for included platforms;
- signed plugin package/catalog compatibility.

Discover publication, unattended execution, new action classes, or broader
autonomy are separate product decisions. No release evidence authorizes direct
network or secure-storage access from WASM.
