# Capsule AI Runtime

Status: normative target architecture for AI execution in maintained Hivra 1.x
and mandatory capability boundary for Hivra 2.0.

This document complements `product-axis.md` and
`architecture/ai-proposal-boundary.md`. The proposal boundary defines what AI
may never authorize. This document defines the single runtime owner through
which every Hivra feature obtains inference.
Person-First ownership and design requirements are owned by `product-axis.md`.
Target capabilities below are not a claim that every package/provider path is
already implemented; current limits and selected work belong to
`development-control.md`.

## 1. Purpose

Hivra treats AI like a Capsule-owned compute subsystem, analogous to a device
neural engine, not like a feature embedded separately into every screen or
drone.

The intelligent executor is temporary and replaceable. The person retains
identity, relationships, local history and capability authority when it changes.
Provider accounts supply computation; they do not become owners of continuity.

```text
Capsule Host Runtime
  |-- Core Truth Layer
  |-- Trust Layer
  |-- Delivery Runtime
  |-- External Effect Runtime
  |-- WASM Drone Runtime
  `-- Capsule AI Runtime
       |-- provider session broker
       |-- disclosure and redaction gate
       |-- inference scheduler and budgets
       |-- proposal-schema validation
       `-- one inference transport
            |-- Responses encoding
            |-- Chat Completions encoding
            `-- Generate Content encoding
```

The analogy is computational only. Capsule AI Runtime has no independent
authority. It cannot mutate Core, append ledger facts, send transport messages,
publish content, trade, stake, install plugins, write repositories, or approve
an external effect.

## 2. Sole Ownership

Capsule AI Runtime is the sole owner of:

- inference-provider selection and adapter dispatch;
- host access to inference credentials;
- process-memory credential leases;
- bounded disclosure envelopes and redaction evidence;
- inference request cancellation, timeout, rate, and size budgets;
- provider-independent inference status and failure classification;
- structural validation of the requested proposal schema;
- non-authoritative inference evidence such as provider, model, request hash,
  disclosed-section list, and timing.

It does not own:

- Core facts or ledger projections;
- drone business semantics or deterministic policy;
- approval, capability grants, effect identity, retry, or receipts;
- provider-specific product behavior such as Moltbook publication or financial
  execution;
- UI workflow state beyond a projection of AI-session/request status.

## 3. Canonical Request Path

Every AI-enabled feature follows one path:

```text
user or drone intent
  -> capability-owned context selection
  -> Capsule AI Runtime disclosure gate
  -> canonical bounded inference request
  -> configured provider adapter
  -> untrusted proposal
  -> exact schema and safety validation
  -> capability-owned deterministic policy
  -> optional normal Truth or Effect Lane
```

There is no direct `drone -> Gemini`, `screen -> OpenAI`, or
`provider response -> effect adapter` path.

## 4. Public Contract

The runtime contract carries semantic values, not provider DTOs. A request
contains at least:

- stable request id;
- active Capsule scope;
- requesting capability or plugin id;
- disclosure-envelope version and canonical hash;
- explicit redacted input sections;
- proposal schema id and version;
- provider policy (`preferred`, `local_only`, or an explicit allowlist);
- model-independent byte, token, time, and rate budgets;
- cancellation/supersession scope.

A result contains at least:

- the same request and Capsule/capability scope;
- validated untrusted proposal value;
- provider and model evidence;
- disclosure and response hashes;
- terminal status or typed visible failure.

Provider-native request, response, token, safety, and billing DTOs remain
inside their adapters. A global `AiDto` layer and pass-through feature wrappers
are forbidden.

### Owner-Selected Compute

Analyst lists saved connections and built-in presets. **Add AI connection**
accepts an owner-selected name, supported protocol, protocol base URL, model
and whether an API key is required. Responses and Chat Completions use a base
such as `https://host/v1`; Generate Content uses `https://host/v1beta/models`.
The runtime appends the protocol route, never infers a service from its name.
A compatible service or model needs configuration, not a Capsule rebuild.
A new protocol or genuinely missing execution ability may extend the transport.
Local weights remain with the local executor, outside Capsule.

One transport owns HTTP, timeout, redirect refusal and errors; three encodings
reuse the existing protocol parsers. No automatic provider/model fallback is
permitted. Errors show status or protocol incompatibility without echoing the
service response body. Analyst labels each answer with its connection and
model, and clears the preceding answer on a new request or changed selection;
a previous success cannot stand in for a failed request. These wire formats follow the
[Generate Content contract](https://ai.google.dev/api/generate-content) and
[Chat Completions compatibility contract](https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/).

Connection names are presentation; random saved IDs bind configuration and
secure credentials. A new destination receives a new ID and key reference,
even when its name matches an existing connection. Replace an address/protocol
by adding a new connection and connecting its key, then remove the old one.
Removal clears only that connection's key, model preference and process lease.
It cannot undo an already accepted inference request. Presets retain existing
credential keys and endpoints; the Cloudflare preset retains its official
HTTPS account destination and capacity option. Generic connections use the
owner-selected HTTP(S) destination without user credentials in the URL or
redirects. Protocol base URLs retain non-secret query parameters such as API
versions when the runtime appends the route.

Authorized packages reuse this computation through common `ai.infer`. Packages
own prompts, context and proposal meaning; no connection or model selection
acquires authority to publish, trade or mutate Capsule truth. There is one
runtime and one credential owner for Analyst and packages.

### 4.1 Frozen 1.x Contract V1

The provider-independent 1.x boundary is frozen before implementation as two
semantic records. This is one runtime contract, not a provider DTO family.

`CapsuleInferenceRequestV1` binds:

- `request_id`, `capsule_root`, and `capability_id`;
- disclosure schema version, canonical disclosure hash, explicitly disclosed
  section ids, and exact UTF-8 byte count;
- capability-owned proposal schema id and version;
- provider policy and model policy without a provider-native request object;
- either the persisted preferred provider/default model policy or an explicit
  user-selected provider id and bounded model name;
- input, output, timeout, and concurrency budgets;
- cancellation/supersession scope;
- bounded instructions and canonical input JSON.

`CapsuleInferenceResultV1` binds:

- the same request, Capsule, capability, disclosure, and proposal-schema
  identity;
- terminal status or one typed visible failure;
- validated untrusted proposal bytes owned by the requesting capability;
- provider and model evidence plus response hash and timing evidence.

Canonicalization uses UTF-8, sorted JSON object keys, preserved array order,
no insignificant whitespace, and lowercase hexadecimal SHA-256 evidence.
Unknown fields, unknown schema versions, scope changes, oversized input or
output, unavailable unlocked credentials, timeout, cancellation, and stale
Capsule completion fail closed. A retry cannot change provider policy, model
policy, disclosure hash, proposal schema, or request identity.

The runtime validates only the common envelope and declared size/schema
boundary. The feature or drone still parses and validates its exact proposal
meaning; no generic AI response acquires capability semantics.

## 5. Drone Boundary

A drone may declare an inference capability and a drone-owned proposal schema.
It may submit bounded public or user-approved context through the host ABI.

A drone never receives:

- provider API keys or the credential lease;
- a generic network, filesystem, repository, shell, signing, or tool port;
- raw provider configuration or unrestricted model selection;
- another Capsule's context or another plugin's private state;
- authority inferred from model output.

The drone owns the meaning of its proposal. Moltbook prose, financial analysis,
staking alerts, and Capsule diagnostics remain different contracts even when
they use the same inference runtime.

## 6. Credential And Session Contract

Inference secrets stay in platform Secure Storage under the host AI owner. A
user explicitly unlocks the selected provider into one process-memory lease.
Connection names, protocols, base URLs, preferred connection ID and model
choices are non-secret host configuration stored outside Secure Storage by the same owner, in the existing
provider preference file. Analyst saves and restores the model together with
provider settings. A provider-default request uses the configured model, or
the built-in initial default when no model was saved. Explicit request models
remain authoritative. Runtime resolves provider and model into an explicit
execution request before scheduling; its canonical identity includes that
resolved choice. A later preference change cannot redirect a queued request. The queued lease
also binds its connection, destination and credential; removal, lock or a changed
lease during authorization fails before dispatch.
No automatic model or provider fallback is performed on failure.

One explicit unlock performs at most one protected credential read after
configuration migration; a legacy Keychain-stored provider id is read once
and then removed without enumerating unrelated Keychain records.

- The lease may be reused by Capsule Analyst and authorized
  drones while the app process remains open.
- Every request is still bound to its originating Capsule and capability.
- Switching Capsules cannot transfer request context or a late proposal.
- WASM and provider-effect adapters never receive the inference credential.
- Locking or closing the app clears the in-memory lease, not the saved secret.
- A locked automatic cycle stops before inference without opening an operating
  system password dialog and without consuming its input checkpoint.
- v1 makes no app-closed/background AI execution promise.

The process lease prevents repeated Keychain reads; it is not a global
capability grant. Capability and disclosure checks still run for every request.
An explicit one-shot provider unlock changes only the process session. It does
not silently rewrite the persisted preferred-provider choice.

Technical context may be authorized as a whole by the owner's analysis request,
without per-section UI approval. The existing disclosure owner must exclude
secrets, personal content and owner/peer addresses while retaining useful
technical evidence. Field allowlists and coarse error categories are mechanisms
to evaluate against that outcome, not permanent limits on diagnostic scope.
An outbound preview identifies what is actually disclosed. This does not grant
arbitrary filesystem access or interpretation of package-private state.

Provider-key availability is a metadata lookup through the same credential
owner. It must not read secret bytes, unlock the process lease, or call a
provider. Concurrent availability checks share the pending lookup without
persisting another copy of credential state. The Analyst UI accepts delayed
completion only for its current selection, offers an explicit retry after a
real storage failure, and never turns an arbitrary UI deadline into a missing
key. Saving, clearing or asking waits until that selection's status is known.

Moltbook uses common `ai.infer` through this same broker and the Analyst-selected
connection. The package supplies public facts, conversation input and its own
prompts. Provider/model evidence returns through the common result. The host
rechecks package/owner authority at actual dispatch after queue waiting.

## 7. Determinism And Persistence

Inference is nondeterministic external input. Therefore:

- model output is never ledger truth;
- deterministic decisions remain reproducible without replaying prose;
- private raw prompts and responses are not persisted by default;
- persisted drafts are capability-owned, bounded, and explicitly classified as
  untrusted advisory state;
- request/evidence hashes may prove what was disclosed or reviewed but do not
  prove factual correctness;
- retries never silently switch provider, model policy, Capsule, proposal
  schema, or effect identity.

## 8. Scheduling

One inference scheduler owns concurrency, cancellation, timeout, and budget
enforcement. Feature modules do not create independent AI queues or timers.

Supported 1.x execution is foreground only:

- explicit one-shot request;
- once-per-process session cycle while unlocked;
- continuous foreground cycle while unlocked and visibly enabled.

Closing the app stops scheduling. Future background or always-on execution is
a separate capability proposal requiring platform lifecycle, power, privacy,
budget, and revocation evidence.
Foreground-only operation is a maintained 1.x implementation limit, not a
permanent definition of person-owned delegation. Its replacement must preserve
explicit owner scope and revocation through the existing execution owners.

## 9. 1.x Convergence

The 1.x implementation grew as separate Capsule Analyst, history-advisor, and
Moltbook AI services; its experimental Developer Mode was removed rather than
promoted into another runtime surface. The convergence path is:

1. one process-scoped credential/session owner;
2. one provider-independent inference request port;
3. one disclosure/redaction and request-budget owner;
4. migrate one feature at a time to that port;
5. delete each feature-local provider lookup and dispatch path in the same
   migration unit;
6. keep feature proposal schemas and deterministic policies with their owners.

No broad 1.x rewrite or parallel runtime is authorized. Each step must reduce
callable paths or duplicated ownership and preserve current release behavior.

### 9.1 AI-0 Inventory Baseline

AI-0 registered the feature-owned dispatch paths for Capsule Analyst, history
advisor, and Moltbook. The only allowed
composition access to the shared process lease remains
`AiToolingModuleService` and `PluginRuntimeModuleService`.

`tools/review/capsule_ai_runtime_gate.sh` makes this compatibility debt
non-increasing and rejects any new screen, widget, feature, Core, Engine,
adapter, or platform path. A migration passes only when it routes one listed
feature through the single runtime owner and deletes that feature's direct
credential and adapter access in the same unit.

### 9.2 AI-1 History Advisor Checkpoint

AI-1 routes `CapsuleHistoryAiAdvisorService` through
`CapsuleAiRuntimeService`. The runtime now owns canonical JSON and request
identity, explicit process-session unlock, provider dispatch, process-wide
serialization, same-scope supersession, input/output/time budgets, provider
evidence validation, Capsule binding, and stale-completion rejection.

The history advisor retains only its redacted ledger-history disclosure and
advisory proposal semantics. Its direct credential and adapter imports are
deleted, and the executable gate rejects their return. No Core, FFI, truth, or
effect path changed.

### 9.3 AI-2 Developer Engineer Removal

The experimental Developer Engineer, repository workspace/cache, plugin
scaffold, patch preview, and AI review-gate paths are removed from Hivra 1.x.
Capsule Analyst exposes no repository context or code-modification surface.

### 9.4 AI-3 Capsule Analyst Checkpoint

AI-3 routes `AiDoctorChatService` through the same
`CapsuleAiRuntimeService`. Capsule Analyst automatically includes technical
summaries from all diagnostic modules without section-selection controls. The
existing prompt owner projects technical fields, excludes secrets, personal
content, owner/peer addresses, filesystem paths and raw exception text, and
fingerprints only that outbound context. Errors are represented by diagnostic categories; package-private state
is not read or interpreted. This is a technical snapshot, not an AI filesystem
or module-reading tool. Capsule Analyst retains redaction, outbound preview,
payload limits, and advisory proposal semantics.
This describes the pending source projection, not proof of complete technical
coverage or exact packaged acceptance; that outcome remains under review in
`development-control.md`.
The runtime now owns provider preference, credential and base-URL
configuration, explicit session unlock, canonical request identity, and exact
provider/model response binding.

The feature's direct credential, provider-adapter, provider DTO, and dispatch
access are deleted and gated against return. Its provider/model UI uses
semantic ids only; no Core, FFI, truth, effect, or second credential path was
added.

### 9.5 Moltbook Common Inference

Moltbook 0.8.0 uses common workspace `ai.infer`. Its former
`MoltbookPublicBulletinAiService`, host prompts, durable feed checkpoint,
approval/delegation controller and publication-effect service are removed.
The runtime continues to own the preferred connection, process-scoped secret
lease, inference queue, request bounds, provider dispatch and provenance.
The package owns public input selection, content/reply/challenge prompts and
service interpretation. No separate Moltbook AI connection is created.

Its current workflow, stateless restart and acceptance limits belong to
`../plugins/moltbook_engagement_lifecycle_v1.md`.

No legacy feature-owned provider dispatch or credential-read path remains
callable. Service-specific inference behavior belongs to installed packages.

## 10. Hivra 2.0 Contract

Hivra 2.0 includes Capsule AI Runtime as a first-class host capability beside
WASM Drone Runtime and the two effect runtimes. The application composition
root connects provider adapters. Core and drones depend only on stable
capability contracts, never concrete AI services.

The 2.0 design is incomplete until it provides:

- a frozen request/result contract and golden canonicalization vectors;
- forbidden-import and single-entrypoint gates;
- per-Capsule/capability isolation and stale-completion tests;
- compromised-model and prompt-injection tests;
- provider substitution tests, including a local model;
- credential lock/revocation and process-restart tests;
- budget, cancellation, timeout, and concurrency evidence;
- a migration map deleting the replaced 1.x provider paths.

## 11. Rejection Rules

Reject an implementation when:

- a screen or drone constructs a concrete provider adapter;
- a feature reads an inference key directly;
- AI Runtime imports Core mutation or an external-effect adapter;
- a generic AI response type replaces a drone-owned proposal schema;
- two schedulers, credential owners, disclosure gates, or provider dispatch
  paths remain callable for the same request;
- a model-selected tool or URL becomes a host capability;
- an AI failure is converted into success, empty truth, checkpoint loss, or an
  unreviewed fallback effect.

Capsule AI Runtime is successful when intelligence becomes replaceable shared
compute while authority, truth, and effects remain explicit and capability
owned.
