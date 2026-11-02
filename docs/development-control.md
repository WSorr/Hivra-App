# Hivra Development Control

Status date: 2026-11-02

This file is the Hivra control plane. It owns current decisions, development
rules, the selected product outcome, and the integration boundary. Detailed
history belongs in Git, pull requests, release signoff rows, and focused
evidence documents; historical paragraphs below never reopen a retired path.

## Development Rules

### 1. Model the owner journey before choosing a mechanism

Apply the Person-First design basis in `product-axis.md`. For a substantial
decision, first identify the object, observed behavior, states and transitions,
invariants, authority and responsibility boundaries. Separate necessary
constraints from restrictions inherited from the present application. Different
local histories are not automatically a conflict requiring synchronization.

State the capability the person gains and what remains theirs when an executor
is replaced. Trace the complete input-to-effect path, its canonical owner,
existing tests, compatibility paths and contract owner. Classify a restriction
as a Core invariant, delegated permission, external/provider constraint,
resource bound, owner preference or current implementation limit. Require a
concrete failure case before preserving or adding it as a host rule.

Derive the smallest mechanism from that model. For nontrivial choices compare
at least two materially different mechanisms when credible alternatives exist;
do not invent alternatives for a form. Challenge the mechanism with replacement,
different local contexts and partial failure. Define an observable prediction
and the smallest experiment that could disprove it.

Then check current upstream documentation and implementations against the
derived requirements, including ownership, compatibility, runtime cost and
licence. Reuse or adapt a suitable library without importing its account,
tenancy, lifecycle or coordination assumptions. Record checked links/version
and the brief decision in the existing PR or review, proportional to the change.
This does not authorize a dependency upgrade or change Ledger authority.

If the change adds an owner, reducer, DTO, lifecycle, gate or document, first
redesign it to reuse or replace an existing one. Keep this reasoning compact;
routine fixes do not require a new model document, questionnaire or approval
stage. A counterexample changes the model, not merely the error message.

### 2. Keep one truth lane and one effect lane

- The Ledger owns historical domain facts.
- Canonical projections own current state.
- The App Shell renders projections and sends explicit intents.
- WASM owns product behavior and service protocol/response interpretation.
- The host enforces the owner's access grants and supplies shared technical
  execution and optional opaque persistence.
- Service observations are not a second host-owned account truth. The target
  contract and implemented v1 exceptions belong to `plugins/plugin_host_api_v1.md`.

Different inputs that produce the same state change or external effect converge
before execution. A replacement removes or seals the path it supersedes in the
same bounded change.

### 3. Preserve package replacement

An installed package must remain replaceable without rebuilding Capsule. Host
contracts may expose capabilities and opaque state, but the host must not read
private package fields or implement a temporary strategy fallback. Package,
grant, Capsule, restart, and removal changes must be covered where they affect
the lifecycle.

### 4. Work in one bounded product outcome

Every pass names one user-visible outcome, the owner that changes, and the
evidence that proves it. Do not split one journey into status-only passes,
release candidates, or speculative framework work. V2 remains design-only until
an explicit migration unit is activated.

Define relevant failure, restart and replacement behavior before implementation.
Iterate with focused tests; validate the finished scope through required gates
and its exact packaged journey. Reopen accepted work for a concrete defect,
changed behavior or missing evidence required by the declared matrix.

### 5. Use the validation ladder in order

1. Focused unit/widget or package tests for the changed semantics.
2. `flutter analyze` and the relevant Rust/package checks.
3. `tools/review/review_all.sh` and the matching security/architecture gates.
4. A clean exact packaged artifact from the guarded release path.
5. Manual smoke for the user journey, including restart and failure recovery
   when the change affects persistence, credentials, or external effects.
6. Release signoff and publication only after the exact artifact smoke passes.

Tests prove semantics; they do not prove product acceptance. Never call a
build a release candidate before its source, runner, artifact digest, and smoke
evidence are bound together.

Android packaged validation follows `checklists/release-android.md`, which owns
the local macOS emulator environment and evidence requirements.

Required runtimes: Apple Silicon macOS in the current account with isolated test
Capsules, and local macOS Android Emulator. Physical Android adds evidence.
Native Intel and a separate clean macOS account/machine are optional, not release
prerequisites or automatic debts; expanding the matrix needs explicit approval.
Record untested environments. Universal binary checks, data isolation, recovery
and channel-specific signing/signoff requirements remain mandatory.

### 6. Upgrade dependencies and tooling as one controlled unit

An upgrade must record the previous and new versions, why the change is needed,
the supported platform matrix, generated-file deltas, focused compatibility
tests, full gates, and an exact packaged smoke. Update
`toolchains/hivra-baseline.conf` and `docs/platform-toolchain-evolution.md`
together.
Do not upgrade a dependency, Flutter, Xcode, Rust, or Android stack as drive-by
cleanup. If the canonical CI runner was built for a different source tree,
packaging stops until a matching runner is available.

### 7. Maintain documentation by status, not chronology

- Current decisions go in this file.
- Permanent laws go in `product-axis.md`.
- Maintained protocol behavior goes in `specification.md`.
- Capability and architecture boundaries go in their focused contract.
- Procedures go in `checklists/`.
- Results go in evidence/signoff records.
- Historical implementation detail stays in Git or an explicitly historical
  evidence document.

Do not duplicate a fact in multiple current documents. When a contract changes,
update its owner and the routing entry in `docs/README.md` in the same pass.

### 8. Stop conditions are explicit

Stop and report a concrete blocker when the exact package cannot be built,
Keychain or signing identity is unavailable, the matching runner is missing,
the artifact differs from the smoke artifact, or the required user journey is
not observable. Do not bypass a gate, substitute a build-tree binary, mutate a
Capsule by hand, or infer success from a provider request without a receipt.

### 9. Definition of done

A pass is complete only when it reports the product outcome, added and removed
owners/paths, validation evidence, remaining risk, and required manual smoke.
No commit, push, tag, release, VPS mutation, or external effect is implied by a
green repository gate.

Closing a runtime architectural debt additionally requires showing that the
capability survives a relevant executor/package/provider replacement without
moving ownership or rewriting unrelated host behavior. A repaired reference
application or passing fixture alone closes only the stated defect. Label
implemented behavior, tested evidence, design requirements and known limits
separately; neither target prose nor accepted 1.x limitations prove completion.

## Current State

- Hivra 1.x is the only maintained runtime; Hivra 2.0 remains design-only.
- Protected `main` includes package/VPS recovery, the common protocol-2
  workspace, replacement/reopen/restart and manifest capability admission.
  Read Git for the current commit.
- The latest published prerelease is `v1.0.5-test1`, with runtime source
  `21ae7b5` and its matching canonical runner. Its tag adds only digest-bound
  manual signoff; ZIP/APK bytes are the exact smoke-tested artifacts. It is an
  unsigned test release for Apple Silicon and local macOS Android Emulator
  (API 36, arm64). Intel, other Android runtime combinations and the complete
  User Lifetime qualification remain unconfirmed.
- Capsule selection bounds delayed Keychain activation to 30 seconds and keeps
  late completion owned by the original activation.
- External WASM package source and package releases belong to `hivra-plugins`.
  Web and Opsnex are outside the Capsule release input.
- Core, Ledger, FFI, the WASM host, and one Flutter App Shell remain the
  runtime. The macOS runner enforces one running Hivra bundle instance.
- ZIP-with-manifest is the only installable external-package format. Legacy raw
  modules remain removable but cannot bind or execute; no OS/process isolation
  is claimed.
- External package versions remain replaceable when the host ABI, contract,
  capability policy, and catalog trust root are unchanged.
- Chat, Moltbook and Jack Ventura use installed WASM packages. The local Moltbook
  0.8.0 replacement uses the common workspace API, service-owned recent history,
  Analyst inference and owner grants. Its host controller, product screen,
  publication journal and local product stores are removed. Its authoritative
  workflow and changed stateless recovery guarantees belong to
  `plugins/moltbook_engagement_lifecycle_v1.md`. Earlier packaged 0.7.3 evidence
  does not qualify the replacement; no live publication is authorized.
- Capsule-scoped credential stores remain authoritative; AI unlock is
  process-scoped. The Flutter 3.47.4, Dart 3.13.3, Xcode 27.1, and Swift
  Package Manager baseline remains authoritative.

## Current Jack Ventura Boundary

Jack Ventura 0.2.0 is the local, unreleased reference package for the common
protocol-2 workspace path. Its protocol, parsing, preflight and recovery are
package-owned; the host owns generic access enforcement and execution. The
implemented wire contract has one owner: `plugins/plugin_host_api_v1.md`.

The owner ended the earlier local trading test. It is not a qualification of
fill-to-TP, stop protection, profitability or continuous autonomous operation.
The old test heartbeat was removed; Jack and any external orders were not
stopped or cancelled. No live trading or VPS changes are authorized for the
API implementation. Old test-session migration is explicitly out of scope.

Local verification covers generic permission enforcement and package replacement,
queued inference revocation, real WASM dense six-frame processing, partial/full
reducing observations and restart, plus a provider-free local runner's custody,
singleton, timer and shutdown. Service responses are synthetic. The automatic
development UI smoke on Apple Silicon macOS also passed: independent package
installation, common catalog, owner grants/revocation, cold restart, replacement
with a different private schema and uninstall/reinstall with retained checkpoint.
It used Debug, the existing test-home override and a separate app identifier;
it is not canonical guarded release acceptance. Android and Linux/VPS UI
qualification remain untested. No live provider acceptance was established.
Moltbook 0.8.0 now uses this same workspace path; its native/packaged
acceptance remains separate from synthetic reference-package evidence. No new strategy, trading runner or host fallback belongs
to this pass.

## Unified API Development Decision

The selected documentation outcome is to make the Capsule/package boundary
explicit under the three laws: a small Core for identity, authority and
relationships; a shared technical host; isolated packages for capabilities.
The development target, minimal Jack replacement and storage/recovery terms
have one owner: `plugins/plugin_host_api_v1.md`, under Unified Capability API.

The authorized implementation replaces Jack's host-aware request path with
protocol-2 common operations, package-owned protocol/lifecycle and owner-granted
network/credential/inference access. The generic host does not inspect private
trading state or enforce duplicate strategy policy. The old Jack adapter and
named-request dispatcher are removed. Moltbook 0.8.0 replaces its specialized
host workflow through the same technical API, without a product-state store.

The owner ended the local trading test and explicitly excluded old-session
migration from this pass. Do not add old journal imports or old-ID compatibility
for those sessions. Existing files remain untouched. New sessions still persist
unresolved intent before dispatch and reconcile exact identities after restart;
that is ordinary delivery correctness, not historical migration. Future real
session migrations must define preservation requirements before implementation.
Live trading, publication and VPS mutation remain outside the API work.
Integration follows explicit owner instructions and the protected-main rule.
Local synthetic runtime checks verify implementation; exact packaged product
acceptance remains distinct.

The owner has now selected the product model for Moltbook comparison: owner
permissions and native Keychain secret connection on the plugin screen,
package-owned execution, the existing Analyst AI connection for news generation,
and service-owned publication/comment history read on every start. Moltbook
requires no local business-state persistence. The canonical model and current
implementation differences belong to `plugins/plugin_host_api_v1.md`, under
Owner-Granted Connections. Do not turn service restrictions or content policy
into repeated host approval. The common path now supports owner-selected Keychain references, a single
workflow grant reused by Start, stateless execution, generic choice actions and
bounded waits. Unit/widget checks cover revocation, package replacement and
restart without a workspace checkpoint; native WASM checks use synthetic service
responses. Moltbook 0.8.0 now implements this boundary and has no host-owned
workflow or product store. Guarded macOS acceptance verified catalog discovery,
permission enforcement/revocation and replacement with a different private state
shape; the exact Android APK installed and opened Moltbook's common workspace.
That smoke exposed a missing first-secret connection and a series of native
Keychain prompts during Capsule recovery. The bounded owner-connection repair
adds first-secret input to the existing permission decision and replaces the
recovery seed scan with the existing public-owner comparison. Focused checks
cover native storage failure/cancellation, delayed completion after leaving,
changed owner/package before storage commit and legacy owner recovery without
unlocking unrelated seeds. Exact guarded macOS/Android requalification of
source `82814bc` passed the bounded owner-connection journey: new public-owner recovery on macOS avoided
unrelated seed unlocks; first-secret save, reference reuse after cold process
restart and full grant revocation were exercised through an independent common
API package on both runtimes. The macOS owner completed the native vault unlock.
Protected requests used only a synthetic token and a closed localhost port;
this does not establish authenticated service or live Moltbook acceptance.
Exact digests and native observations for that connection repair are retained in
`/Volumes/Dev/projects/hivra-artifacts/owner-connection-20261101`.
Subsequent authenticated acceptance uses Moltbook 0.8.2 and guarded host source
`21d35a4`: macOS and Android read the agent's service history and prepare a reply
and news through the owner's Cloudflare Workers AI connection in Analyst,
without sending content. Cold restart reacquires history without a local draft or
Moltbook workspace checkpoint. This exposed and repaired a common workspace
defect: idle grants no longer trigger automatic package `open`, and explicit
action results/errors survive timers and app resume. Android also preserves the
visible unavailable-Analyst error across background/resume before the owner
connects a provider. Package 0.8.2 removes false zero-history counts after
preparation without retaining observations or changing the host. This closes
the read-and-prepare journey and disappearing-result defect, not the
entire plugin runtime debt or publication/reply qualification. Digests and native
observations are retained in
`/Volumes/Dev/projects/hivra-artifacts/moltbook-live-read-prepare-20261101`;
no test release or Moltbook content was published.

Judge progress by product independence and removed host responsibilities,
not by more adapters, gates or speculative extension layers. Keep development
simple by reducing the host's obligations rather than adding product-aware
infrastructure. Documentation changes alone do not establish runtime
compatibility, isolation or product acceptance.

## Selected Product Outcome

The current selected outcome is replaceable inference connections: the owner
adds an already-supported protocol endpoint, selects a model, connects its key
and uses the same AI Runtime from Analyst and authorized packages without
rebuilding Capsule. Existing working credentials remain available. One HTTP
transport replaces three implementations; connection configuration replaces
closed product-name dispatch. The exact packaged Mac/Android journey must prove
addition, model change, restart and explicit incompatibility without fallback.
No publication, trade, VPS mutation or release is authorized by this outcome.
Native qualification is pending; the preceding maintenance acceptance below
remains historical evidence for its own artifacts.

The bounded Capsule/package maintenance outcome is complete in
`v1.0.5-test1`. Authenticated v3 backup/recovery uses the existing
codec/persistence/file-delivery owners, with public Capsule ID + UTC filenames,
durable Capsule/Chat state, opaque package state and installed ZIPs. Recovery
uses normal package admission, excludes platform credentials and other Capsules,
does not overwrite existing Capsules, and does not renew workspace execution
leases. The maintained wire and safety contract belongs to `specification.md`.

The release includes the completed dependency updates: Nostr/TLS, anyhow
1.0.103, wasmi 0.41.3 without paste and wincode 0.6.3 with frozen bincode 1.3.3
byte compatibility. No Capsule storage migration was introduced.

Exact packaged acceptance covered existing-data update, native backup and
empty-runtime recovery, authentication rejection, invitations in both directions,
scoped Capsule switching, bidirectional Chat, package installation/removal and
reinstallation, required-capability rejection, replacement/reopen and cold
restart. Cross-platform recovery preserved Ledger, encrypted Chat, opaque state
and package digests. Working Capsule files remained unchanged. Per-platform
observations, artifact digests, runner binding and limits have one owner:
`checklists/release-manual-signoff-log.md`.

Local Analyst diagnostics, redacted clipboard/outbound preview and read-only
package audit passed on macOS without a model request. The existing AI Runtime
remains the provider owner under `architecture/capsule-ai-runtime.md`.
Live Moltbook publication/challenge/reply and Jack trading/VPS effects were not
qualified in this isolated release acceptance. Earlier live evidence does not
certify new effects on these artifacts.

This closes the bounded unsigned test matrix. Full User Lifetime, native Intel,
a separate macOS user, long-term migration/lifetime, other Android combinations
and the open Jack evidence remain unconfirmed. Intel and separate-profile
evidence are optional under the required matrix above; channel-specific journey
and signoff requirements still apply. No permanently frozen host ABI is claimed.
Future runtime changes require a new exact-artifact smoke; package
changes within supported contracts must remain independently replaceable.
Do not overwrite attested artifacts or reuse their smoke for changed code.

## Deferred Product Work

These entries record accepted product boundaries for future selection, not
implemented guarantees or permission to begin every item. Carry the selected
entry's required retention, permitted eviction/re-entry and non-goals into its
existing contract, tests and acceptance; do not expand them implicitly.

- Package replacement through reconnection: installing a replacement must not
  require preserving the old package's credentials or complete private state.
  Host-held connection secrets may remain scoped in secure storage, or the
  owner may supply them again when the new package reconnects. Reacquire
  provider-verifiable orders, positions or publication state through the same
  adapter/effect owners; do not require a duplicate permanent service archive.
  Non-reconstructible owner data follows an explicit retention choice. Keep
  the minimal identity/evidence needed to reconcile unresolved sends and avoid
  duplicates. Separate package installation/UI availability from resuming a
  remote executor: old authority must not silently transfer or create two
  authorized financial executors. Acceptance covers replacement, reconnect,
  provider-state recovery and restart, including an unavailable old VPS;
  mandatory whole-checkpoint migration and automatic authority renewal are
  not acceptance requirements. Current 1.x behavior remains unchanged pending
  the selected implementation and its compatibility checks.
- Lightweight Chat retention: a default owner-configurable 100 MB rolling
  message-content cache per Capsule, shared across its conversations. Evict
  the oldest completed messages when its storage budget is reached; retain the
  remaining window across restart and package replacement. Each device may
  keep its own window without mandatory complete-history synchronization.
  Existing bounded delivery queues keep unresolved sends until their outcome
  is handled; cache eviction must not erase their identity or repeat a send.
  Identity, relationships and Core Ledger facts are outside this cache.
  Acceptance covers budget eviction, retained-window recovery/restart and
  unresolved-delivery preservation. Infinite message retention, guaranteed
  recovery of evicted messages from Nostr and a full messaging-service archive
  are non-goals. This is the selected design direction, not the current 1.x
  storage limit or permission to prune existing data now.
- Replaceable inference connections: an owner must be able to use updated or
  new models and add providers speaking an already supported inference
  protocol without rebuilding Capsule. Provider name, protocol, endpoint and
  model are host configuration; credentials remain bound to that connection
  in secure storage. Local model weights belong to the local inference
  executor, outside Capsule. Reuse the existing AI Runtime and adapters;
  a genuinely new protocol or execution capability may require an adapter
  extension. Implementation is selected: saved protocol-based connections through the
  existing AI Runtime, replacing closed provider dispatch and consolidating
  HTTP execution. Native acceptance remains open until exact packaged Mac/APK
  evidence is recorded. Acceptance: the same installed Mac/APK can
  change model, add a compatible provider, retain the selection after restart
  and report incompatibility without silently rerouting requests; Capsule
  identity, Ledger, relationships and package state remain unchanged.
- New Chat UX and Moltbook engagement features remain outside the selected
  package-replacement outcome; they do not reopen the Capsule release scope.
- Jack live closure/reentry and continuous VPS evidence remain experimental
  follow-up, not a second v1 development stream.
- Flutter host/plugin convergence, measured 1.x compatibility boundaries,
  crypto-agility, and Trust Layer issue `#7` remain retained architectural
  debt. Select them only when they block the selected product journey or close
  a concrete security/correctness defect.
- Reassess owner/capability boundaries before closing the retained host debt:
  installation-wide package/version and deletion scope, same-owner context
  recovery, reference-specific workspace/provider bindings, host editorial and
  local-budget policy, and UI-bound execution lifetime are current limits to
  evaluate, not permanent Person-First requirements. Select one bounded owner
  journey before implementation. Recheck the pending Analyst context patch for
  useful technical coverage as well as privacy; coarse field/error reduction
  is not evidence that the owner has full technical diagnostics.

## Authority

1. `product-axis.md`: permanent laws and target runtime shape.
2. `specification.md`: maintained 1.x protocol.
3. Focused contracts: capability semantics.
4. This file: current state and the single selected product outcome.
5. `roadmap.md`: milestone/debt index; Git, pull requests, releases, tests,
   and evidence logs retain history.

## Integration Boundary

`main` changes only through a pull request with required `review-gates`.
Repository validation does not authorize a tag, Release, packaged smoke, VPS
mutation, or external effect.
