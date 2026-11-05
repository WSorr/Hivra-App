# Hivra Development Control

Status date: 2026-11-05

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

Reuse one isolated acceptance profile per runtime instead of accumulating
Capsules, preview applications and emulator definitions for successive passes.
Fixture-only packages belong in tests, never in the owner's working profile or
the product catalog. A clean-install/recovery case may use disposable userdata;
remove that data and its test credentials through the normal lifecycle after
the check, once no unresolved effects remain. Retain digest-bound results and
necessary release artifacts, not duplicate app bundles, generated backup payloads
or standalone preview projects. Cleanup belongs to the same acceptance journey.

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
- The current local VPS connection/status repair is not in the published test3
  artifacts. Its contract belongs to `plugins/plugin_host_api_v1.md`; new exact
  macOS/Android acceptance is required before shipping the repair. This source
  pass does not change the running owner Capsule, exchange orders or VPS.
- Protected `main` includes package/VPS recovery, the common protocol-2
  workspace, replacement/reopen/restart and manifest capability admission.
  Read Git for the current commit.
- Published versions and exact packaged acceptance are recorded under Selected
  Product Outcome and `checklists/release-manual-signoff-log.md`. Apple Silicon
  macOS and physical Samsung API 37 arm64 have bounded current-release evidence;
  Intel and complete User Lifetime qualification remain unconfirmed.
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
- Chat, Moltbook and Jack Ventura use installed WASM packages. Moltbook
  uses the common workspace API, service-owned recent history,
  Analyst inference and owner grants. Its host controller, product screen,
  publication journal and local product stores are removed. Its authoritative
  workflow and changed stateless recovery guarantees belong to
  `plugins/moltbook_engagement_lifecycle_v1.md`. Earlier packaged 0.7.3 evidence
  does not qualify the replacement. Live writes require an explicit owner grant;
  the bounded November 4 Mac publication was separately authorized.
- Capsule-scoped credential stores remain authoritative; AI unlock is
  process-scoped. Exact SDK/compiler versions have one owner:
  `../toolchains/hivra-baseline.conf`.

## Current Jack Ventura Boundary

Jack Ventura 0.2.1 is published in `v0.2.11-plugins` for the common
protocol-2 workspace path. Its protocol, parsing, preflight and recovery are
package-owned; the host owns generic access enforcement and execution. The
implemented wire contract has one owner: `plugins/plugin_host_api_v1.md`.

The old local trading test ended without fill-to-TP qualification; its heartbeat
was removed without stopping Jack or cancelling external orders. Old test-session
migration was explicitly excluded from the common-API replacement. New protocol-2
sessions retain necessary unresolved intent through the existing opaque store.

The owner later authorized the separate live connection/remote scheduling
acceptance recorded under Selected Product Outcome. That evidence does not
qualify entry-to-TP, service restart during an ambiguous mutation, stop repair,
profitability or continuous autonomous operation. Native synthetic replay proves
only its tested observation and recovery behavior. Automatic stop restoration
and amendment remain excluded by the owner.

## Unified API Development Decision

The maintained boundary is a small Core for identity, authority and
relationships; one technical host; replaceable packages for product behavior.
The operation catalog, grant and checkpoint contracts have one owner:
`plugins/plugin_host_api_v1.md`.

Jack and Moltbook now use protocol-2 common operations. Their old named-request
dispatchers, service adapters and host product controllers are removed. The host
does not inspect package-private trading state or repeat strategy/editorial
policy. Owner settings and Start can authorize the complete workflow; dispatch
still enforces the current package, owner, grant and sandbox boundary. Chat
retains a specialized relationship/delivery workspace and is not yet proof that
every capability is replaceable through the generic workspace alone.

Moltbook reads service publication/comment history on each authorized open/start
and cycle, uses Analyst-selected inference, and retains no local product state.
Its explicit stateless recovery limit belongs to
`plugins/moltbook_engagement_lifecycle_v1.md`. Guarded source `21d35a4` with
Moltbook 0.8.2 passed authenticated history, AI news/reply preparation without
sending, and restart reconstruction on macOS/Android. Evidence remains in
`/Volumes/Dev/projects/hivra-artifacts/moltbook-live-read-prepare-20261101`.
That earlier evidence closes read-and-prepare only. The later bounded Mac
publication and independent 0.8.4 Discovery update are recorded below; neither
closes the remaining general host/package convergence debt.

The existing common permission form supports new secret input and reference
reuse; Cancel/native write failure issues no grant. Native owner-connection
acceptance and its limits remain in
`/Volumes/Dev/projects/hivra-artifacts/owner-connection-20261101`.
Old-session migration, a mandatory service-history archive, renewed authority on
recovery and repeated per-step approvals are not implicit API requirements.
Documentation and green fixtures alone do not establish product acceptance.

## Selected Product Outcome

The owner clarified remote Start: replace the one managed VPS process with the
current package and chosen symbol/settings, independent of the installing device.
The current source reuses setup/grant adoption for this lifecycle and removes the
busy-runner veto; no service-specific host adapter or WASM API operation is added.
The real-WASM probe covers another authorized device, selected-symbol Start,
server checkpoint retention, stale replay, old control refusal and failed-Start
revocation. Unit tests also cover a lost old observation and revocation before
setup dispatch. This is source/synthetic evidence; the prior running 0.2.2
artifact remains unchanged until exact-artifact acceptance of this host change. Its source contract is `plugins/plugin_host_api_v1.md`.

The owner accepted Moltbook for v1 and selected Jack's completed-trade journey:
show the actual exchange result, then continue the authorized cycle without a
second product controller. The unreleased Jack 0.2.3 source includes the
existing common HTTP/checkpoint path for one last-trade locator and transient
fill accounting; no host implementation or API operation is added. It also
recovers a pre-dispatch interruption as not sent while retaining uncertain
sent identities. Native synthetic closure/reopen evidence is not live TP
acceptance. The preceding exact local 0.2.2 package was installed through the
existing Mac UI without rebuilding Capsule, after returning the old VPS authority and checkpoint.
Reconnection reused the saved secrets; owner Start resumed ACH-USDT 1m, margin
1 USDT and stop budget 20% on the same VPS. The previously stranded pre-dispatch
plan became not sent. All three Ledger files and application executable/AOT
hashes remained unchanged. Live closure/reentry, restart during a managed trade
and Android 0.2.2 acceptance remain pending. No new Capsule, backup or emulator
is part of this pass. Digest-bound checks and current observation use the
existing `jack_completed_trade_20261105` section in the acceptance record below.

The `v1.0.5-test3` unsigned test prerelease and `v0.2.12-plugins` are
published. Exact Mac/Android artifact acceptance, digests and limits belong to
`checklists/release-manual-signoff-log.md`; complete User Lifetime remains
explicitly PENDING.

Moltbook 0.8.4 is published independently through the signed Discovery catalog
in `v0.2.12-plugins`, from `hivra-plugins` PR #21. It uses the existing common API;
Capsule was not rebuilt or replaced. The exact canonical Linux package passed
the real-WASM host probe and replaced the installed local 0.8.3 through public
Discovery on the existing Mac Capsule. It opened and returned to the same
Ledger v121; all three Ledger files and the app executable/AOT hashes stayed
unchanged. Installed Chat/Jack versions and package bytes were retained. A
replacement digest requires reconnection and does not resume prior authority.
The same implementation in the preceding local 0.8.3 candidate completed an
owner-authorized news publication with an independent verified public receipt.
No new publication was sent during the 0.8.4 Discovery acceptance. Generated
prose remains model-dependent. The existing physical Samsung also passed the
0.8.2 to 0.8.4 public Discovery update/open/return without an APK rebuild, new
Capsule or publication. Exact 0.8.4 live-write acceptance was not repeated. The package tests cover fresh history, computed verification,
receipt/deduplication, restart and revocation/removal through the existing probe.
Release digests, CI, public downloads and native evidence are owned by
`/Volumes/Dev/projects/hivra-artifacts/jack-capsule-acceptance-20261103/moltbook-smoke-20261104/plugin-candidate.json`.

The original `v0.2.11-plugins` signed Discovery delivery outcome is complete. Update Capsule to
`v1.0.5-test3`, then use Plugins → Discover plugins to install Jack 0.2.1,
Moltbook 0.8.4 and Chat 0.2.3. Test2 lacks Jack's required common host abilities.
The compatible Capsule was published before promoting the signed catalog;
public downloads match its pinned canonical Linux package digests.

The existing Samsung Capsule passed actual public catalog download/install,
opening all three packages, Jack AppBar Back and system Back, and a cold
application restart with the same Ledger and retained settings/packages.
Same-version local Jack/Moltbook packages were removed with saved-data deletion
unchecked before installing the published packages. No new Capsule, backup,
installer or package store was created. The registry remains the single install
owner for both file import and Discovery (one before, one after).
The exact Mac ZIP also passed in-place update, existing Jack open/return and
local Analyst inspection; its working Jack package and VPS were not replaced
or changed. This delivery does not qualify full TP/SL or social publication.
Evidence has one owner:
`/Volumes/Dev/projects/hivra-artifacts/jack-capsule-acceptance-20261103/acceptance.json`.
The owner explicitly authorized commits, push, merge, tags and these test
publications; future passes and releases still require explicit approval.

The owner-approved Jack product pass also qualified account connection,
read-only open-order observation, VPS setup, owner Start and remote scheduling
while the Mac app was closed on the earlier guarded `b428ee8` candidate.
Reopening returned to the same remote workflow without another Start; the
owner's manual ACH order was not adopted or cancelled. That is historical
connection/custody evidence, not a live-trading smoke for changed release bytes.
The earlier `845d81d` Samsung artifact qualified complete instrument selection,
actual 1m market reads and restart/navigation. Exact package/runtime provenance
and per-stage limits remain in the same acceptance record linked above.

Current Jack presentation uses the package's connection, settings, order,
position and result views; manual prepare/place/cancel controls are sealed.
Stop observation is displayed without automatic stop repair. Draft edits survive
status polling. The contract chooser reads all eligible service contracts into
transient memory; only the selected symbol is retained. Public choice permission
is GET-only and does not connect credentials or start a schedule. Capsule renders
these through the existing generic workspace and enforces the owner's access;
service eligibility, rules and rechecks stay in WASM. The common resource/HTTP
projection bounds are specified only in `plugins/plugin_host_api_v1.md`.
Full six-frame Android market history previously met bounded provider rejection
`100410`; do not infer that it passed from a successful 1m refresh or catalog read.

Retained completed product decisions remain binding:

- New Capsule backups retain authenticated Ledger and Capsule type/network
  metadata only. Seed custody is separate. Chat content, operational pair
  attestations, delivery queues, contact labels, package checkpoints and
  installed ZIPs are excluded. Recovery accepts loss of that application data;
  install/reconnect applications afterward and reacquire operational pair
  evidence from peers. Core export must not depend on application volume,
  corruption or package removal. Legacy full-state v3 remains read-only import
  compatibility; no archive/synchronization subsystem or renewed authority is
  implied. The maintained format belongs to `specification.md`. Native exact
  Mac/API36-emulator evidence (including the 9,254-byte public fixture) is in
  `/Volumes/Dev/projects/hivra-artifacts/core-backup-20261102/acceptance.json`;
  that fixture does not qualify physical-device peer-evidence reacquisition.
- Chat's owner-configurable default 100 MB window covers completed serialized
  message content across conversations. Evict oldest completed records first;
  pending/ambiguous deliveries, Core identity and Ledger remain outside that
  budget. Keep the local window across restart/package replacement without
  mandatory full-history synchronization or recovery of evicted content. New
  Core-only backups do not transfer it. Its contract is
  `architecture/transport-delivery-lifecycle.md`; native budget/restart evidence
  is in `/Volumes/Dev/projects/hivra-artifacts/chat-retention-20261102/acceptance.json`.
  Earlier full-state recovery evidence is historical, not a new-backup promise.
- Analyst shows local technical observations and exact redacted outbound preview
  before inference. Missing observations stay unavailable; no fabricated file,
  seed or trace result may replace them. Preview needs no provider key and is
  invalidated by query edits or refreshed evidence. This closes truthful local
  disclosure, not complete diagnostic coverage or model-answer quality. The
  contract is `architecture/capsule-ai-runtime.md`; exact native evidence is in
  `/Volumes/Dev/projects/hivra-artifacts/analyst-evidence-20261102/acceptance.json`.
- Supported inference protocols share one transport. Owners may add endpoints,
  change models and reconnect without rebuilding Capsule; genuinely new
  protocols may require a host extension. Saved provider connections and local
  model weights remain outside Core. Exact test2 connection/change/restart/
  removal evidence and its limits are in
  `/Volumes/Dev/projects/hivra-artifacts/inference-connections-20261102/native-acceptance.json`.

Earlier release records retain their own artifact-specific backup, delivery,
recovery and dependency-update evidence. They cannot qualify changed bytes or
silently enlarge current recovery scope. General User Lifetime, native Intel,
a separate macOS user, long-term migration, full Jack TP/SL and Moltbook live
writes remain unqualified by that original bounded Discovery delivery. Within supported
capabilities, package changes remain independent; host changes require a new
exact-artifact smoke. No permanently frozen host ABI is claimed.

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
  journey before implementation. Analyst's truthful disclosure repair is complete;
  broader useful technical coverage remains separate from privacy and coarse
  error categorization.

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
