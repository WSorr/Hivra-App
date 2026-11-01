# Plugin Host API v1 (WASM Execution Boundary)

This document defines version 1 of the deterministic plugin request/response
contract. It is not the WASM ABI version: current external packages use
`hivra_host_abi_v2` and the `hivra_*_v1` exports below.

## Scope

- WASM bytecode execution through the bounded `wasmi_v1` runtime for resolved
  external packages.
- Explicit method and capability checks before invocation.
- Pair-scoped calls blocked unless the local pair snapshot is signable and the
  required attestations bind both roots to that snapshot.

The host does not grant plugin storage, Ledger writes, transport access, or
provider effects merely because a WASM call succeeds.

The design basis is owned by `docs/product-axis.md`. The contracts below
describe the implemented 1.x surface, not the permanent extent of the owner's
possible capabilities. Fixed view sizes and installation-wide cleanup remain
current limits; package policy does not become universal host policy.

## Unified Capability API: Protocol 2

The maintained 1.x workspace implements the common operations below using the
existing bounded JSON ABI. Protocol 2 is a capability protocol version, not
activation of Hivra 2.0. Jack 0.2.0 uses this path. The old Jack provider adapter,
host financial preflight, normalization and host-selected continuations are
removed. Moltbook 0.8.0 uses the common path without a storage capability.
Chat retains its relationship-scoped specialized contract.

### Responsibilities

| Owner | Responsibility |
| --- | --- |
| Core + Ledger | Capsule identity, owner authority and relationship facts, validated domain commands and canonical projections |
| Host/runtime | Package isolation, owner-grant enforcement, network/TLS and crypto execution, protected credential application, scheduling, generic presentation and optional opaque storage |
| WASM package | Service API rules, request construction, response interpretation, strategy, workflow, reconciliation, settings, private checkpoints and view contents |
| External service | Facts about its own account, accepted operations and results; these are not Hivra domain facts |

Dependencies point from packages to common host contracts and validated Core
operations. The host must not depend on package-private schemas, strategy
commands or a named product's workflow. Access to Core never bypasses its
invariants; granting a plugin network access does not grant identity signing
or direct Ledger writes.

### One Request/Result Path

Reuse the existing JSON invocation and continuation mechanism:

```text
owner action or authorized scheduled wake
  -> package decides and constructs a capability request
  -> host checks the current grant and executes the permitted operation
  -> transport result returns to the package-selected continuation
  -> package interprets the result and decides its next step
```

For network operations the package supplies the destination, method, parameters
or body, scoped credential reference and its own correlation/continuation data.
The host checks that the installed package may use that destination and
credential, applies authentication within dispatch, and returns bounded HTTP
status/body or a transport failure. It must distinguish a proven non-dispatch
from an uncertain outcome; it does not invent a provider receipt or silently
retry a possibly delivered mutation. Provider status and business errors are
interpreted by the package, not normalized into host-owned product lifecycles.

Extract shared authentication from existing Bearer and HMAC implementations
first. Protected material is applied only to the permitted destination and
request; it never becomes plugin output or a reusable arbitrary signing oracle.
Redirects must not carry credentials outside the granted destination. Service
paths, payload formats, parsing and retry/rate-limit policy belong to the
package. Common resource bounds remain host concerns. A genuinely unsupported
authentication/system primitive may extend this boundary; adding a service
using supported primitives does not justify another host adapter.

### Owner Authorization

Installation admits code, not unrestricted secret or network access. Owner
configuration and Start can grant one complete autonomous workflow. The host
binds access to the Capsule, installed package, destination/credential scope,
execution host and chosen duration/revocation terms. It checks that authority
at dispatch without judging the package's product decision or asking for each
step again. Replacement does not silently inherit broader permission.

The package owns trading rules such as margin, zones and stops, or publication
rules such as reply selection and challenge handling. The common API must not
encode these as universal business checks. It guarantees access enforcement,
not independent strategy correctness or a maximum financial loss. Migration
must not silently reinterpret an existing risk-scoped grant as a broader
network grant; the owner must see and authorize the changed terms.

Partial Stop, if a package offers it, is a package workflow choice. Full host
revocation blocks new dispatches in the revoked scope without service keys or
service availability; it cannot undo an admitted request or an exchange order.
The existing local/VPS custody mechanism prevents two scheduled executors for
the same grant. Package-defined scheduling needs no host trading state machine.

### Owner-Granted Connections: Accepted Product Model

The Capsule is the person's execution environment. The person is the authority
issuing access to their installed capabilities, not a tenant whose choices
require a second product administrator in Hivra.

The owner journey is one connection decision on the plugin screen: select the
plugin's permitted effects and the relevant Keychain secrets, then authenticate
in the native Keychain dialog. Hivra does not collect the system password.
The resulting binding makes those capabilities available to the plugin for the
owner-selected scope and duration. Starting the configured workflow uses that
binding; it does not request the same access again for each product step.
Revocation removes availability of the binding. The technical dispatch owner
applies the binding and protected secret; it does not issue another business
approval based on account status, publication quality, trading strategy or a
local copy of service rules.

| Owner | Decision or fact |
| --- | --- |
| Person | Which plugin may use which secret, external effects and connected AI; scope, duration and revocation |
| Keychain | Native authentication and protected secret custody |
| Package | Protocol, requests, parsing, workflow, timing and response interpretation |
| Analyst's existing AI connection | Executes the package's content-generation request through common `ai.infer` |
| External service | Its account facts, accepted publications/orders, restrictions, rate limits and results |
| Capsule host | Executes generic capabilities through the owner's binding and maintains the sandbox boundary |

Moltbook's selected workflow is stateless across starts: it reads publication
and comment history from Moltbook on every start and holds only transient work
in memory. No local publication/comment cache, draft archive, effect journal or
recovery checkpoint is required. Service history is not copied into Core or
Ledger. Host permission records and Keychain secret references are the owner's
access configuration, not a Moltbook account mirror. Unknown delivery and
service errors are interpreted by the package using the service's protocol;
Hivra must not invent independent service guarantees or another approval chain.

The common workspace implements the owner connection model: its permission
screen selects an existing Capsule-scoped Keychain reference or accepts a new
service token/key directly from the owner. One Allow decision saves new fields
together in the existing vault and binds only their references. Cancel and a
failed native write do not issue a grant. The first connection does not require
an older product screen, service adapter, terminal setup or a secret supplied by
WASM. Secret custody and partial-failure behavior have one owner:
`../architecture/capsule-scoped-secret-lifecycle.md`. Native
secure storage performs authentication according to the Keychain item's access
policy; Hivra never asks for the system password. The grant stores references,
not copies of secret values. The package receives only its declared credential
alias and service result. Connection validation is an ordinary package workflow;
there is no `credentials.accept` operation, pending-secret acceptance lane,
action-scoped access bypass or second Start approval for unchanged access.
A changed destination, method or credential connection requires the owner's
updated grant. Full revocation is available for stateless and scheduled plugins.

Moltbook 0.8.0 implements this path without a host controller or product stores.
Its service-history and stateless recovery contract belongs to
`moltbook_engagement_lifecycle_v1.md`. The host reads no prior product checkpoint
for a package lacking `state.plugin.read_write`.

### Minimal Persistence And Recovery

Keep host permissions and credential/executor bindings authoritative in their
existing stores. Package settings and necessary private checkpoints use the
existing optional opaque store; the package owns their schema and upgrades.
Do not introduce another persistence service or required provider-history log.

Workspace uninstall first closes package admission and drains the existing
executor. It deletes code and secrets and invalidates the installed-package
grant binding. The bounded opaque workspace checkpoint and `data-` storage
remain for reconnect/recovery by default; the host never examines pending
identities inside them. The removal dialog offers explicit saved-data deletion,
which tells the owner that pending recovery information will be lost and
external operations are not undone. Reinstall never restores execution access
without a fresh owner grant. This replaces the old Jack journal's retention
role with the package checkpoint, not a second effect archive.

Re-read account facts from the service. Reconstructible candles, balances,
orders, positions and receipts are transient observations or disposable caches,
not a host-owned mirror. Preserve only private decisions that cannot be
reconstructed, relevant operation identifiers and unresolved dispatch intent.
Write the necessary intent before dispatch. The package resolves ambiguity
using the service's actual lookup/idempotency guarantees; not-found alone is
not proof of non-delivery. Exactly-once execution is not promised for an
arbitrary service. If safe recovery cannot be established, the package reports
uncertainty rather than resubmitting blindly.

### Operation Catalog And Wire

Every package can request `api.describe` to discover the versioned catalog.
All requests have `kind`, a correlation `id` matching
`[a-z][a-z0-9_.-]{0,63}`, and a package-selected `continuation` action matching
`[a-z][a-z0-9_]{0,63}`. No operation name contains a service name.

| Operation | Manifest permission | Additional request fields | Result |
| --- | --- | --- | --- |
| `api.describe` | none | none | `catalog`: operation descriptors |
| `runtime.yield` | `workspace.continue` | none | correlation only; begins a fresh bounded invocation |
| `http.request` | `network.http` and `credentials.use` when protected | `url`, `method`, optional string `body`, string-map `headers`, `credential`, `auth`, `max_response_bytes` | `outcome`, HTTP `status`, bounded `headers` and `body`, or safe `error` |
| `runtime.wait` | `workspace.continue` | integer `milliseconds` from 0 to 60000 | correlation only after a bounded delay |
| `storage.read` | `state.plugin.read_write` | `key` | string or null `value`, or size `error` |
| `storage.write` | `state.plugin.read_write` | `key`, string `value` | `written` |
| `ai.infer` | `inference.request` | package `instructions`, object `input`, optional `max_output_bytes` | `outcome` and bounded inference result |

An invocation receives `api_version: 2`, `action`, opaque `state`, transient
`context`, owner-submitted `settings`, `observed_at_ms`, current `execution`
(`enabled`, `running`, `scope`), and the previous request's `result` when continuing.
It returns `state`, `context`, `view`, and zero or one `requests`. The host
adds the request's `id` to the result and invokes its exact continuation.
For packages declaring opaque storage, non-null state is persisted before dispatch. Without that capability state is transient and may be null; no workspace file is read or written. A private strategy may have internal
semantic commands, but they never cross this public request boundary.

Example package output:

```json
{
  "state": {"pending_operation": "package-owned-identity"},
  "context": {"next_step": "package-private"},
  "view": {
    "title": "Application", "message": "Working", "details": "",
    "fields": [], "actions": [], "columns": [], "rows": []
  },
  "requests": [{
    "kind": "http.request", "id": "request-1", "continuation": "receive",
    "method": "POST", "url": "https://service.example/items",
    "headers": {"Content-Type": "application/json"}, "body": "{}",
    "credential": "default",
    "auth": {"headers": {"Authorization": {"field": "token", "prefix": "Bearer "}}}
  }]
}
```

Access descriptor, authorized once on the plugin screen for the workflow:

```json
{
  "version": 2,
  "network": [{
    "origin": "https://service.example", "methods": ["GET", "POST"],
    "credential": "default"
  }],
  "credentials": {"default": [{"id": "token", "label": "Connection token"}]},
  "inference": false
}
```

A null/absent credential grants only unprotected requests. Each named alias
lists the fields the package needs. The owner selects a Keychain reference for
each field from this Capsule's existing secrets. The host resolves only that
mapping; the package cannot select or import a vault entry. Values never enter
settings, private state or WASM input. Grant metadata is bound to the current
owner, package ID/digest, executor and exact network scope in the existing
`workspace-execution.v1.json`; its `credentials` map contains references only.
Local dispatch resolves them through the existing Capsule-scoped vault. An
owner-selected remote executor receives a version-3 protected provisioning
payload (`connections: {alias: {field: value}}`) through the existing custody
path. The updated runner advertises `execution_controls: 3`; older runners
are refused for permission changes and package actions. Rebinding credentials
requires returning authority locally first.

A `workspace.authorize` presentation action opens owner permissions before
running the package's ordinary connection action. Package actions cannot carry
independent `access`. Start uses `schedule: {version: 2, action,
interval_seconds, description, access}`; it reuses an active matching grant,
including its expiry and secret connections. It asks for permission only when
required access is absent or broader. Permissions need no schedule; `running`
means a scheduled workflow, while `enabled` means the owner's access is enabled.
The owner may choose a deadline or authorize until revocation. `workspace.stop`
fully revokes host dispatch. A package may expose an ordinary partial-Stop
workflow without revoking access to its remaining operations.

Choice fields use `source.action` through the same action executor and return
`view.options`. There is no field-specific host action or service lookup.

HTTP permits exact HTTPS origins and explicit methods (GET, HEAD, POST, PUT,
PATCH, DELETE, OPTIONS). Origin permission covers paths at that origin; the
host does not implement a service's endpoint allowlist. TLS is verified,
redirects are disabled, and transport has finite connection/response timeouts
and no retries. `auth.headers` applies a protected field with an optional
literal prefix. `auth.hmac_query` takes `field` and `parameter`: it appends the
hex HMAC-SHA256 of sorted, decoded `key=value` query pairs joined by `&`.
Duplicate query keys and an existing signature parameter are refused. This is
a defined common signing primitive, not arbitrary access to secret-derived
outputs. A service needing another signing primitive requires a common API
extension. Protected values and signed URLs echoed by a service are withheld
from response body/headers; that outcome remains uncertain.

HTTP outcomes have precise delivery meaning: `not_dispatched` means no
transport admission; `unknown` means the host cannot prove non-delivery;
`response` means an HTTP response, including service errors. Only the package
interprets that response as success, rejection, partial completion or a receipt.
The host never retries. Inference uses the existing owner-selected Capsule AI
connection and queue. The package supplies instructions and input; the same
package/grant is rechecked at actual adapter dispatch after queue waiting.
The result includes `text`, `provider_id`, `provider_label` and `model`. Unavailable inference is reported without a fallback product controller.

Resource bounds: state 32 KiB, transient context 16 KiB, view 16 KiB; HTTP body
24 KiB request/default response; a request may select `max_response_bytes` up to
256 KiB. The total WASM invocation input is bounded at 512 KiB; output remains
128 KiB, linear memory 128 MiB and fuel 5,000,000. Response headers 8 KiB/64 fields, access descriptor
4 KiB/16 origin entries, and at most 512 continuations in one owner action or
scheduled wake. Existing ABI input/output/fuel bounds also apply to the
combined envelope. `storage.*` accepts only safe `data-` keys in this
Capsule/package namespace and at most 24 KiB values. It cannot modify grants,
executor custody, workspace state or another package. The workspace checkpoint
already uses the existing opaque store and needs no extra archive.

### Jack Checkpoint And Current Scope

Jack owns its protocol, UID-derived account binding, request identities,
preflight, parsing, lifecycle and partial/full reducing-exit decisions. It
streams bounded candle pages and yields between chunks within the unchanged
WASM fuel limit. Its private checkpoint keeps its necessary strategy decisions
and unresolved dispatch intents. After timeout/restart it queries the exact
client/order identity; a missing order does not authorize resubmission.
Package replacement/removal, Capsule switch and grant revocation before
dispatch deny access without asking the host to parse Jack's private state.

The owner ended the old local test sessions and explicitly excluded migration
of their trading history from this pass. There is no old-journal importer,
old-ID mapping, old-checkpoint upgrade, or legacy named-request execution
fallback. Jack 0.2.0 requires a fresh workspace session; an old local test
workspace uses normal package removal with explicit saved-data deletion and
reinstall. Incompatible state is rejected before
persistence. Existing local files are not deleted by this source change. Future migration of real owner
sessions must explicitly define which unresolved identities require retention
before replacing their execution path. New protocol-2 sessions retain their
own pending intent across ordinary restart.

The common API also supplies HTTP/authentication and inference primitives for
other packages. It does not claim Moltbook's old host workflow has migrated.
No live trading, VPS changes or production qualification are part of this pass.

## Implemented v1 Contracts

The specialized contracts below remain maintained. Their permission does not
authorize network access through the common workspace API.

- `hivra.contract.capsule-chat.v1`
  - `post_capsule_chat_message`
  - Successful WASM preparation does not authorize a later transport call.
    The existing runtime authorization capture pins the installed package and
    peer-scoped preflight. Chat delivery requires that authorization and an
    explicit owner Capsule; it rechecks them inside the shared FFI queue,
    immediately before starting the send worker. Replacement, removal, lost
    capability/consensus or a Capsule change while queued refuses dispatch.
    A refused queued attempt is failed, not transport-accepted or ambiguous;
    it is not retried. Package changes after worker admission do not revoke
    a network operation that has already started.
- Installed packages declaring `plugin_workspace_v1` use method `workspace`
  and the common protocol-2 operations above. Required capabilities are
  `workspace.render` and `workspace.continue`; opaque storage is optional.
  The generic view supports eight text/integer/number/choice fields, four
  actions, 64 rows/six columns and optional `details_title`.
  Choice sources declare a package action, never a named service request.
  Host action markers are only `workspace.authorize`, `workspace.start`,
  `workspace.stop`; capability checks use the resolved installed binding.
  Opening sends no draft settings. Edits survive status refresh, errors cannot
  overwrite a newer action, and failed observations mark the view unavailable.
  Local and headless execution share `PluginWorkspaceRuntime`, the same vault
  ports, workspace serialization/OS lease and package binding checks. Existing
  local/VPS custody still has one executor and no implicit local fallback.
  Reading a v1 grant retains custody evidence; it never becomes v2 network
  authority, arms a timer or silently upgrades its scope. The owner must approve
  the new generic terms. The source change does not deploy or restart a VPS.

## Request Shape

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.capsule-chat.v1",
  "method": "post_capsule_chat_message",
  "args": {
    "peer_hex": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "client_message_id": "msg-1",
    "message_text": "hello",
    "created_at_utc": "2026-04-04T10:00:00Z"
  }
}
```

## Response Shape

- `status`: `executed | blocked | rejected`;
- `result`: present only for `executed`;
- `blocking_facts`: present for `blocked`;
- `error_code` and `error_message`: present for `rejected`;
- `canonical_json` and `response_hash_hex`: deterministic for identical
  request and runtime inputs;
- runtime evidence:
  - execution source and package identity;
  - package, module, and invocation digests;
  - contract kind and normalized capabilities;
  - runtime mode, ABI, entry export, and selected module path.

## Error Codes

- `invalid_schema_version`
- `unsupported_plugin`
- `unsupported_method`
- `invalid_args`
- `runtime_invoke_invalid`
- `runtime_invoke_failed`
- `runtime_invoke_unavailable`
- `runtime_binding_invalid`
- `runtime_contract_kind_mismatch`
- `runtime_capability_mismatch`

## Runtime Boundary

External execution is fail-closed:

- package id and kind are required;
- package bytes must match the resolved digest;
- contract kind and required method capabilities must match the manifest;
- specialized Flutter workspaces open only when the installed manifest grants
  every capability required by that workspace's supported methods;
- runtime ABI is `hivra_host_abi_v2`;
- runtime entry export is `hivra_evaluate_v1`;
- zip module paths cannot traverse parents;
- modules cannot import host functions;
- module, input, output, linear memory, and fuel are bounded: linear memory
  permits at most 128 MiB per invocation; fuel remains 5,000,000;
- missing exports, signature mismatch, traps, invalid UTF-8, malformed
  envelopes, and output-hash mismatch are rejected;
- no legacy fail-open path exists for missing contract or capability metadata.

ABI exports:

- `hivra_alloc_v1(len: u32) -> u32`
- `hivra_evaluate_v1(ptr: u32, len: u32) -> u64`
- `hivra_dealloc_v1(ptr: u32, len: u32)`

The packed evaluate result is `(output_ptr << 32) | output_len`.

## Capability Ownership

- Chat requires `consensus_guard.read`, returns plugin-owned canonical message
  bytes, and leaves pair consensus and transport delivery to the host. The
  host accepts the canonical result only when its peer, client message id,
  creation timestamp, and bounded canonical message text remain bound to the
  exact request; it never fills missing semantic fields from host input.
- Moltbook draft, planning, reply, and delegated-reply methods require their
  corresponding `content.*` capabilities. WASM output is proposal or bounded
  authorization evidence, not a network publication receipt.
- Host fallback is retained only for explicitly allowed compatibility methods.
  It is not a second WASM evaluator and must not duplicate plugin semantics.

## Consensus Scopes

- Solo methods do not read pair consensus.
- Pair-scoped methods require a valid `peer_hex` and the attested host guard.
- `ConsensusRuntimeService.signable(peer_hex)` is only a local snapshot
  precondition; it is not sufficient authorization.
- The host never substitutes a missing peer with an arbitrary signable peer.
