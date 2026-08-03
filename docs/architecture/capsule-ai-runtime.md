# Capsule AI Runtime

Status: normative target architecture for AI execution in maintained Hivra 1.x
and mandatory capability boundary for Hivra 2.0.

This document complements `product-axis.md` and
`architecture/ai-proposal-boundary.md`. The proposal boundary defines what AI
may never authorize. This document defines the single runtime owner through
which every Hivra feature obtains inference.

## 1. Purpose

Hivra treats AI like a Capsule-owned compute subsystem, analogous to a device
neural engine, not like a feature embedded separately into every screen or
drone.

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
       `-- provider adapters
            |-- Gemini
            |-- OpenAI
            `-- local OpenAI-compatible model
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
- provider-specific product behavior such as Moltbook publication or BingX
  trading;
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

The drone owns the meaning of its proposal. Moltbook prose, trading analysis,
staking alerts, and Capsule diagnostics remain different contracts even when
they use the same inference runtime.

## 6. Credential And Session Contract

Inference secrets stay in platform Secure Storage under the host AI owner. A
user explicitly unlocks the selected provider into one process-memory lease.

- The lease may be reused by Capsule Analyst, Developer Mode, and authorized
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

## 9. 1.x Convergence

The existing 1.x implementation grew as separate Capsule Analyst, Developer
Mode, history-advisor, and Moltbook AI services. The safe convergence path is:

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

AI-0 registered four legacy feature-owned dispatch paths: Capsule Analyst,
Developer Engineer, history advisor, and Moltbook. The only allowed
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

### 9.3 AI-2 Developer Engineer Checkpoint

AI-2 routes `AiDeveloperEngineerService` through the same
`CapsuleAiRuntimeService`. Developer Engineer retains selected-context
construction, path denylisting, redaction constraints, payload preview, and
advisory proposal semantics. The runtime now binds explicit provider and model
selection into request identity, owns temporary session unlock, validates exact
provider/model response evidence, and keeps persistent preference separate from
the process session.

The feature's direct credential, provider-adapter, provider DTO, and dispatch
access are deleted and gated against return. Its existing provider/model UI
remains available through semantic ids; no Core, FFI, repository-write, patch,
git, release, truth, or effect authority was added.

### 9.4 AI-3 Capsule Analyst Checkpoint

AI-3 routes `AiDoctorChatService` through the same
`CapsuleAiRuntimeService`. Capsule Analyst retains selected-section disclosure,
redaction, outbound preview, payload limits, and advisory proposal semantics.
The runtime now owns provider preference, credential and base-URL
configuration, explicit session unlock, canonical request identity, and exact
provider/model response binding.

The feature's direct credential, provider-adapter, provider DTO, and dispatch
access are deleted and gated against return. Its provider/model UI uses
semantic ids only; no Core, FFI, truth, effect, or second credential path was
added.

One legacy feature-owned dispatch path remains callable:

1. `MoltbookPublicBulletinAiService`.

AI-4 is bounded to that final path. Moltbook remains last because its proposals
feed an effect-owning plugin lifecycle. Migration must preserve the plugin's
proposal schema, durable input checkpoint, explicit session behavior, and
normal effect owner while deleting direct provider and credential access.

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
