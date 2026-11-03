# Hivra Development Control

Status date: 2026-11-03

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
- Protected `main` includes package/VPS recovery, the common protocol-2
  workspace, replacement/reopen/restart and manifest capability admission.
  Read Git for the current commit.
- The latest published prerelease is `v1.0.5-test2`, with runtime source
  `898162f` and its matching canonical runner. Its tag adds only digest-bound
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

Jack Ventura 0.2.1 is the local, unreleased reference package for the common
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
it is not canonical guarded release acceptance. The later bounded packaged
Mac/Android public-market journey is recorded below; Linux/VPS UI and live
trading qualification remain untested.
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

The `v1.0.5-test2` unsigned test prerelease is published. Exact Mac/Android
artifact acceptance, digests and limits belong to
`checklists/release-manual-signoff-log.md`; complete User Lifetime remains
explicitly PENDING.

The next selected delivery outcome is installation through the existing signed
Discovery catalog, not another local-package import. Promote the compatible
Capsule `v1.0.5-test3` before the catalog set Jack 0.2.1, Moltbook 0.8.2 and
Chat 0.2.3: the published test2 lacks Jack's required common host abilities.
Chat receives a new version because its changed manifest must not reuse the
published 0.2.2 identity. Use the existing canonical Linux plugin builder,
signed catalog and registry installation path; no second installer, package
store or Capsule is needed. Acceptance must load the published catalog,
download/install its exact pinned package, open it, return to the same Capsule
and retain the installation after restart. Use the existing Samsung Capsule;
do not replace the Mac Jack package while its remote workflow is active.
Commit, push, merge, tags and publication still require explicit approval.

The owner selected Jack next, followed by its complete product/visual pass.
On 2026-11-03 the owner authorized live trading and VPS changes for this product
acceptance. Use the existing owner Capsule and its explicit trading settings;
an expired earlier grant does not supply new limits or duration. No new test
Capsules, preview applications or standalone acceptance projects are authorized.
The target is Capsule with three replaceable WASM packages; existing isolation,
owner authorization and unresolved-delivery guarantees stay in place while
security/strategy redesign remains outside this product pass. Commit, push,
publication and release still require explicit approval.
Keep service protocol, account facts and strategy in `hivra-plugins`; Capsule
continues to supply the common API and generic workspace presentation.
First make stop coverage observable for the unique position matched to the
managed fill: current closing STOP_MARKET orders, quantity, trigger/source,
partial coverage, duplicates and unavailable/stale evidence. An attached-stop
request or entry/TP receipt does not establish protection. Reacquire these
service observations per action; retain no new stop-history archive or host
trade controller. This bounded observation outcome does not place/amend a
missing stop or qualify full TP/SL closure. Stop repair is excluded by the
owner; full TP/SL closure remains unqualified.
Verify ordinary restart, failed reads, position mismatch and the unchanged
package replacement/revocation boundary. Native synthetic-service replay and
UI presentation qualify local behavior, never live exchange execution.
Then improve Jack's connection/configuration/position/result journey and
visual hierarchy using package presentation and the existing generic workspace;
no service-name dispatch or host strategy rules. Social publication, commit and
new releases are not authorized by this product pass.

Jack's public trading journey now converges on connect, configure, Start/Stop
and actual order/position observation. The previous manual prepare/place/cancel
actions are sealed at the package boundary; the same private cycle steps and
recovery identities remain. Timeframe selection reuses the existing package
choice action without extending the host API. Qualification of these changes
includes existing-Capsule Mac installation of all three packages, open/return,
actual ACH-USDT 1m public market reads and retained configuration after cold
restart. The owner encountered a disabled Allow button without a reason. The
common permission form now derives its explanation from the same validation
decision and labels values by their package-declared role; no service-specific
host path or secret diagnostics are added.

The exact guarded Mac artifact from `b428ee8` passed actual BingX connection,
open-order reads, canonical VPS installation and owner Start. The same bound
Jack package then advanced complete ACH-USDT 1m observations while the Mac
process was closed. Reopening the same Capsule returned to the running VPS
workflow without another Start; local authority remains assigned to that VPS.
Back returns to the Capsule's three installed packages without ending the
workflow. The three original Capsule Ledger hashes are unchanged. The owner's
existing manual ACH order is neither adopted nor cancelled. This qualifies
connection, remote scheduling and restart continuity, not a new entry fill,
TP/SL closure or a service restart during an in-flight mutation. The owner chose
to wait for Samsung rather than update the connected Xiaomi. The same exact
Android build updated Samsung SM-A075F in place, preserving its existing
Capsule and Ledger v8. All three approved packages installed through Add package;
Jack returned to that Capsule through both app-bar and Android system Back.
The live catalog exposed a concrete limit: 1,124 available instruments exceed
the 16 KiB generic view budget. The common view budget is now 64 KiB, still
inside the unchanged 128 KiB WASM output boundary; lists are not shortened or
stored by the host. The exact guarded Android artifact from `845d81d` then
passed full catalog loading, search, ACH-USDT selection and an actual 1m market
refresh on that Samsung. A cold restart retained all three packages and
ACH-USDT/1m settings; both app-bar Back and Android system Back returned to the
same Capsule, with its Ledger v8 unchanged. The staged package copies were
removed from Downloads after installation. No Android credentials, trading
Start or VPS binding were added; this does not qualify Android trading or TP.
Source checks pass 682 Flutter tests, analyzer and review gates; CI
`41661825858` is green. Artifact digests and native observations
remain in the existing `jack-capsule-acceptance-20261103/acceptance.json` evidence
record. No new Capsule, emulator, preview project or backup was created.
Opening the owner's installed catalog Jack 0.1.13 exposed a real compatibility
defect: retired named capabilities were still marked ready, then the old package
rejected the common execution projection. Activation/readiness and invocation
now share the existing supported-capability decision. Archived metadata remains
readable for backup/removal; no old adapter or private-state migration is added.

The local 0.2.1 implementation now presents connection, entry, observed/saved
position, stop coverage and inactive-attempt states through that same workspace.
Status/actions precede responsive settings; exact order/calculation evidence
remains expandable. Draft edits survive running-schedule polling and dispatch
only through an explicit action; package rules still own managed-plan changes.
Local checks and native synthetic-service replay cover the observation workflow;
the current counts and exact packaged evidence are recorded below. Earlier
release-mode previews rendered recorded WASM views for connection, position,
failed read and inactive attempt. Those previews alone do not qualify guarded
artifacts or live execution; automatic stop repair remains excluded by the owner.
Execution owners/paths remain one package lifecycle and one common executor;
two retired presentation rewrites were removed. Recorded preview evidence is
in `/Volumes/Dev/projects/hivra-artifacts/jack-protection-20261102`; the disposable
preview application and project have been removed.

The owner confirmed that the stop attached to the entry already works and
excluded stop restoration/amendment. The current bounded outcome is complete,
searchable instrument selection from the service contract catalog, not the
quote ticker. A saved comparison found 81 quoted USDT symbols outside the active,
API-open set and one available contract absent from quotes; the ticker path is
replaced. Jack filters contract status/API-open flags and USDT support itself;
Capsule has no instrument policy. Selection is explicit and cannot rewrite a
managed plan. The catalog lives only in the chooser's memory and is reacquired
on reopening/retry; only the owner's selected symbol is retained. Acceptance
found that first-time public selection still required the broader account grant.
Choice `source.access` now uses the existing owner permission dialog for public
GET only, with no Keychain selection or scheduled workflow. Account connection
and Start retain their existing explicit owner-grant path.

The existing `http.request` gains optional package-selected JSON paths, discovered
through `api.describe`: one bounded request/result, no response handles, persistent
catalog, service adapter or second executor. The original source is bounded at
1 MiB with projection; raw/selected results still fit 256 KiB. Selected JSON is
returned directly, avoiding JSON encoded inside a string. This permits complete
catalog reads without a host-owned chunk/cache lifecycle. Protocol interpretation,
eligibility and pre-entry rechecks remain package-owned. A missing capability or
insufficient source bound produces an explicit Capsule-update requirement.
The contract owner is `plugins/plugin_host_api_v1.md`.

Native measurements disproved the earlier assumption that the historical 5M
instruction allowance could process the complete catalog. The same import-free
runtime now has a finite 16M fuel allowance; memory/input/output and owner-grant
boundaries are unchanged. Infinite entry/start functions must still trap. This
is a generic execution resource bound, not package/business authorization.
Service observations, source snapshots and measurements remain in
`/Volumes/Dev/projects/hivra-artifacts/jack-protection-20261102`.

The complete catalog passed common HTTP dispatch and native WASM validation:
1325 captured source contracts produced all 942 eligible USDT choices, with no
persistent catalog or trading request. Actual installed-package acceptance also
found and fixed incomplete choice view envelopes; all choice stages now satisfy
the canonical workspace contract. Public choice grants exclude old schedule
fields, so authorizing a read cannot resume a revoked workflow.

Guarded unpublished `v1.0.5-test3` ZIP/APK artifacts bind runtime source
`b7f7e09` to its matching canonical CI runner; CI run `41591994124` succeeded.
The exact Mac artifact used an isolated application identifier and data home;
the exact release APK ran in a dedicated API 36 arm64 emulator. Independent
Jack package replacement used the same Capsule artifacts. Digests, source
commits, observations and screenshots have one evidence owner:
`/Volumes/Dev/projects/hivra-artifacts/jack-capsule-acceptance-20261103/acceptance.json`.
The published `v1.0.5-test2` lacks the new optional ability and fuel budget.

Mac passed public catalog/search/ACH selection, full six-frame actual market
history, recovery from service rejection, return to its disposable Capsule,
process restart and retained selection without an autonomous workflow.
Android passed public catalog/search/ACH selection, an actual 1m market refresh,
package replacement, AppBar Back and system Back into the same disposable
Capsule. Its full six-frame read stopped on provider `100410` after bounded
retries and remains unqualified; it did not hang or dispatch trading effects.
A cold emulator reboot and fresh application process retained the same Capsule,
ACH-USDT and 1m setting; no scheduled workflow resumed.

Real service acceptance fixed exclusive candle end times and replaced 24-candle
pages with measured 96-candle pages, processing 12-candle strategy chunks.
The package keeps its 64 KiB input and 16 KiB continuation bounds. It uses the
existing common wait primitive between candle reads and permits at most two
five-second retries of rejected candle reads across an action. Mutations retain
the existing reconcile-only path; no host service controller or new API operation
was added. Captured actual 600-candle history passes the packaged Mac FFI;
true missing candles are still rejected. Current gates pass 90 Jack tests,
678 Flutter tests, analyzer, host/plugin reviews and 13 runtime tests including
infinite entry/start fuel traps. Synthetic native workflow replay uses 369
invocations; it does not qualify trading execution.

The working Capsule and Samsung were not controlled or used for this acceptance.
No account secrets, Start, live trading, stop repair, social publication or VPS
change was authorized or performed. Local commits in both repositories and the
Capsule feature-branch push for its CI runner were authorized; merge, tag and
publication remain unauthorized. This bounded public-market/navigation evidence
is not full TP/SL, autonomous trading, Intel-native, physical-Android or general
release qualification.

The completed bounded Core-only Capsule backup outcome below retains
Ledger and Capsule type/network metadata only; operational pair attestations,
Chat content, local delivery queues, contact labels, opaque plugin state and
installed ZIPs are excluded. The owner accepts loss of application content when
recovering from a new backup. This does not prune local app state or unresolved
effect evidence, revoke an existing remote grant, or resume a recovered app.
Restore identity/history/relationships from Ledger through the existing
authenticated v3 codec and atomic import owner. Operational pair attestations
are reacquired through the existing peer exchange; unavailable peers may leave
pair actions blocked without erasing relationship truth. Use normal application
installation/reconnection afterward.
Application volume, corruption or package removal must not block Core export
or new Core-only recovery.
Keep existing full-state v3 imports read-only until that supported format is
explicitly retired; no new full-state export path remains. No separate app
archive, synchronization engine or new backup format is selected. Acceptance
must prove size independence, unchanged source app data, authenticated recovery,
restart and failure rollback, then exact packaged Mac/Android export/recovery.
Source checks pass: 669 Flutter tests, 113 FFI tests, analyzer and review gates.
Exact guarded artifacts from `a492319e3c7a91f756ddff264eb1a0b41fafb5ce`
qualified native export and fresh-target recovery on Apple Silicon macOS and
Android API 36 arm64 emulator. The same public fixture now exports as 9,254 bytes
on both runtimes, compared with its previous 237,312,202-byte full-state archive.
Authenticated native Core verification confirms empty files/packages and an
unchanged signed Ledger. A new public fixture restores the same identity,
six-event Ledger and five starters on both runtimes, including cold restart.
Existing Mac Capsule and installed-package files matched their baseline hashes;
only the shared index, new contact card and UI log changed during recovery.
The writer, codec and atomic import owner each remain one; recursive app export
and installed-ZIP snapshots each go from one to zero. New Core recovery no longer
requires a healthy package registry. Production code delta is -59 lines.
Digests and native observations are retained in
`/Volumes/Dev/projects/hivra-artifacts/core-backup-20261102/acceptance.json`.
Native fixtures have no relationships; live peer-attestation reacquisition,
physical Android and Intel execution are not qualified by this acceptance.
Old full-state v3 import compatibility remains read-only. No publication,
trading, model request, VPS mutation or release was performed.

The bounded owner-configurable lightweight Chat retention outcome was completed
before the Core-only backup decision above; its native evidence is historical.
The existing encrypted Capsule timeline remains the only retained message
window across conversations, restart and package replacement. A default 100 MB
budget for UTF-8 serialized completed message records replaces the 256-record
limit. Oldest completed records leave first; pending and ambiguous outgoing
sends remain outside that budget until their outcome is known. Existing
delivery queues, identity, relationships and Core Ledger remain unchanged.
The owner can change the local budget in Chat. UI projections follow the
retained window without resurrecting evicted content from earlier views.
The existing timeline/read-state owner and files remain; no service archive,
mandatory history synchronization, new storage engine or recovery of evicted
messages is part of this outcome. Acceptance covers cross-conversation eviction,
unresolved-delivery preservation and write failure in focused tests, retained
then-accepted full-window recovery/replacement, and budget/edit/eviction/restart on exact packaged
Mac/Android artifacts. Source checks pass: 668 Flutter tests, 113 FFI tests,
analyzer and review gates. Exact artifacts from
`f9024298ee0d9559856928a728a346ff6975d72e` passed budget reduction from 100 MB
and 24,229 synthetic records to 0.001 MB and three records, then cold restart
with unchanged identity/Ledger on arm64 Mac and Android API 36 arm64 emulator.
Android also passed full recovery of the 237,312,202-byte synthetic backup and
Chat removal/reinstallation with the reduced window and budget retained.
Mac full-size restore passed on the preceding `4b70b5c` candidate; the final
Mac artifact qualified the recovered window, budget change and cold restart.
Native acceptance found and repaired Android selector heap exhaustion: JSON
and ZIP selection now stream through the existing native document owner.
The encrypted timeline and delivery executor each remain one; independent UI
history mergers went from two to zero. Production delta is +186 lines, not a
host-size reduction. Existing Chat compatibility ownership remains. Larger
owner windows can exceed explicit backup bounds; evicted history is not
guaranteed recoverable. Artifact digests, observations and the working-context
activation incident are retained in
`/Volumes/Dev/projects/hivra-artifacts/chat-retention-20261102/acceptance.json`.
No live delivery, physical-device or Intel execution is claimed. No trading,
publication or VPS mutation is authorized.

The bounded truthful Analyst evidence-before-disclosure outcome is complete.
The owner opens local diagnostics, sees which checks were actually observed,
and expands the exact technical payload and instructions before any model call.
An unavailable or failed bootstrap/trace check must not invent negative file or
seed observations, erase the other check's successful result, or appear healthy.
The existing diagnostic collector owns availability; the existing prompt owner
projects public technical evidence and excludes secrets, personal content,
addresses, paths and raw exceptions. Preview is local and requires no provider
key. Query edits and refreshed snapshots invalidate stale previews/answers.
Acceptance covers partial failure and privacy in source checks, and local
preview/refresh/restart on exact packaged Mac/Android artifacts from
`363a23cd0c3527d4099b87d696caffb1f0b04179`. Source checks pass (662 Flutter tests,
113 FFI tests, analyzer and review gates). Both native journeys passed exact
data/instructions disclosure, query edit and refresh invalidation, and cold
restart with unchanged Capsule identity and Ledger. No password or model request
was needed. Artifact digests and observations are retained in
`/Volumes/Dev/projects/hivra-artifacts/analyst-evidence-20261102/acceptance.json`.
The collector, prompt and execution owners each remain one; overlapping failure
handlers went from two to one and fabricated report builders from two to zero.
This closes truthful availability and local disclosure, not full technical
diagnostic coverage or model answer quality. No publication, trading, VPS
mutation or release is authorized by this outcome.

The bounded replaceable inference connections outcome is complete: the owner
adds an already-supported protocol endpoint, selects a model, connects its key
and uses the same AI Runtime from Analyst and authorized packages without
rebuilding Capsule. Existing working credentials remain available. One HTTP
transport replaces three implementations; connection configuration replaces
closed product-name dispatch. Exact `v1.0.5-test2` Mac/Android artifacts from
`a1df90883f3c6dfb9078bab049f22089851fc71f` passed live connection addition,
model change, cold restart, explicit incompatibility without fallback or stale
answers, and test-connection removal with the original connection still working.
Capsule identity, Ledger, relationships and package state were preserved;
107 existing working Mac files matched their baseline hashes. Artifact digests
and observations are retained in
`/Volumes/Dev/projects/hivra-artifacts/inference-connections-20261102/native-acceptance.json`.
No publication, trade, VPS mutation or release is authorized by this outcome.
This qualifies the supported-protocol connection journey, not every provider,
model or protocol implementation. The maintenance acceptance below remains
historical evidence for its own artifacts.

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
  are non-goals. This bounded debt is closed by the existing encrypted timeline
  and owner budget control; packaged acceptance and its limits are recorded
  under Selected Product Outcome. Local restart/package replacement retain the window; new Core-only backups
  do not transfer it. Broader host/package convergence remains separate.
- Replaceable inference connections: an owner must be able to use updated or
  new models and add providers speaking an already supported inference
  protocol without rebuilding Capsule. Provider name, protocol, endpoint and
  model are host configuration; credentials remain bound to that connection
  in secure storage. Local model weights belong to the local inference
  executor, outside Capsule. Reuse the existing AI Runtime and adapters;
  a genuinely new protocol or execution capability may require an adapter
  extension. This bounded debt is closed by saved protocol-based connections
  through the existing AI Runtime and one HTTP transport; the exact packaged
  acceptance and its limits are recorded under Selected Product Outcome.
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
