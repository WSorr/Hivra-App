# Hivra Development Control

Status date: 2026-11-07

This file is the Hivra control plane. It owns current decisions, development
rules, the selected product outcome, and the integration boundary. Detailed
history belongs in Git, pull requests, release signoff rows, and focused
evidence records. The project map in `docs/README.md` routes tasks to those
owners; historical results never reopen a retired path.

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

Hivra 1.x is the maintained runtime: Core, Ledger, FFI, the bounded WASM host
and one Flutter App Shell. V2 remains design-only. Read Git for source and
branch state; published artifacts and their signoff belong to
[release evidence](checklists/release-manual-signoff-log.md).

- Chat, Moltbook and Jack are installed packages developed in `hivra-plugins`.
  Package versions can change independently within the supported ABI, host
  contract, capability policy and catalog trust root. Web and Opsnex are
  outside the Capsule release input.
- Jack and Moltbook use the common protocol-2 workspace. Their former named
  service dispatchers, host product controllers and provider adapters are
  removed. Chat retains its specialized relationship/delivery binding.
  The implemented boundary is [Plugin Host API](plugins/plugin_host_api_v1.md).
- ZIP-with-manifest is the installable package format. Legacy raw modules
  remain removable but cannot bind or execute; no OS/process isolation is
  claimed. The macOS runner admits one running Hivra bundle instance.
- Capsule selection bounds delayed Keychain activation to 30 seconds; late
  completion remains owned by the original activation. Capsule-scoped secret
  stores remain authoritative, and AI unlock is process-scoped.
- Moltbook is accepted for v1. Its host product screen, publication journal and
  local product stores are removed. It reads service history and uses Analyst
  inference under owner grants; its stateless recovery limits belong to the
  [Moltbook lifecycle](plugins/moltbook_engagement_lifecycle_v1.md).
- Jack's completed-trade journey remains experimental. Live entry-to-TP,
  closure/reentry, restart during ambiguous delivery, profitability and
  continuous operation are not qualified by connection or synthetic probes.
  Automatic stop restoration/amendment remain excluded. Old local test-session
  migration was excluded; new protocol-2 sessions retain unresolved intent in
  the existing opaque store.

## Selected Product Outcome

Integrate the validated 1.x work through one reviewed branch, then close the
remaining v1 journeys in priority order. Keep one checkout writer and one PR
under integration at a time; re-read the remote base and exact head before
merging. A clean `main` is the integration baseline, not a claim that every
runtime debt is accepted.

First finish owner-granted connection reuse and inference on Mac/Samsung with
the existing packages and Capsules. Then qualify device replacement and Start
recovery with matching runtime artifacts when VPS access and owner authority
are available. Jack's actual completed-trade journey needs separate live
evidence; do not substitute placement receipts or synthetic fills. Retained
design-only work does not become a v1 implementation requirement.

The import-form repair is accepted on exact `6e35c8d` Mac/Samsung artifacts:
long JSON, editor scrolling, Cancel/reopen and existing-card Import passed;
Samsung's real keyboard left both footer actions accessible. No new Capsule,
card duplicate, dependency or execution path was added. All three Mac Ledgers,
saved cards, installed registry and execution grants retained their digests.
The artifact-bound result is `card_import_layout_20261107` in the existing
acceptance record below; Android landscape and larger text have widget-test
evidence, not a physical-device claim.

## Runtime Work Still Awaiting Acceptance

The common API contract owns behavior; the existing acceptance record owns
artifact-bound results. Source tests, fixtures and earlier packaged runs do not
qualify changed bytes. Accepted bounded journeys do not close unrelated runtime
work.

| Bounded outcome | Source behavior / remaining acceptance |
| --- | --- |
| Use one peer address and retain concurrent card updates | Chat and pair-attestation exchange share the address owner; persistence delegates card writes and cleanup. Source tests cover precedence, concurrent mutation, reopen and corrupt-file behavior. Exact e265681 Mac/Samsung smoke qualified existing-card reimport, one Mac-to-Samsung message, cold process restart and return. Real contact/Capsule deletion and new invitation were excluded on owner data; those cases retain source-test evidence. Results: `address_consolidation_20261107` in the existing acceptance record below. |
| Reuse owner-granted connections | Existing grants cover Connect, inference and subsequent requests; cancelled/denied access and package/grant changes are checked. Complete exact Mac/Samsung acceptance of credential reuse and inference remains required. |
| Recover after another device replaces the VPS installation | Authenticated return restores the sealed opaque checkpoint without new authority; recovery remains visible after failed first open. Finish exact Mac/Samsung and matching-runner recovery acceptance, including an unreachable VPS. |
| Start the selected package/settings on the chosen VPS | One setup/custody owner replaces the managed process independently of the installing device; stale replay and failed-Start revocation have source/real-WASM evidence. Device replacement and failure recovery need matching-artifact native evidence. |
| Show Jack's actual completed trade and continue | Package-owned last-trade locator, fill accounting and pre-dispatch recovery use the common API. Live closure/reentry and restart during a managed trade remain open; synthetic closure is not TP acceptance. |

These source repairs are not qualified by the published test3 artifacts.
Moltbook's independent Discovery update on Mac and Samsung qualified package
replacement/open/return without rebuilding Capsule; exact 0.8.4 live writes
were not repeated. Earlier authorized publication evidence is package-specific,
and generated prose remains model-dependent. General host/package convergence
is still open.

The original Discovery delivery qualified install/open/return and restart on
its recorded Mac/Samsung bytes. It did not qualify full trading outcomes,
continuous operation or later host changes. The six-frame Android market-history
request met provider rejection `100410`; a successful 1m read does not close it.
Native Intel, a separate macOS account, long-term migration and complete User
Lifetime qualification remain unconfirmed. They do not expand the required
runtime matrix defined above.

## Retained Product Decisions

These accepted scopes remain binding when selecting later work; contracts own
their protocol details and evidence owns the tested runtime limits.

| Decision | Retained scope | Contract |
| --- | --- | --- |
| Core-only backup | Authenticated Ledger and Capsule type/network metadata; seed custody stays separate. Application content, operational pair attestations, queues, contact labels, packages and checkpoints may be lost on recovery. Reinstall/reconnect and reacquire peer evidence; no renewed effect authority. Application size/corruption/removal cannot block Core export. Legacy full-state v3 is read-only import compatibility. | [Specification](specification.md) |
| Chat retention | Owner-configured completed-message window, default 100 MB across conversations. Evict oldest completed content; retain pending/ambiguous delivery evidence, Core and Ledger. Keep the local window across restart/replacement; Core-only backup does not transfer it. No full-history synchronization or recovery of evicted content. | [Delivery lifecycle](architecture/transport-delivery-lifecycle.md) |
| Analyst disclosure | Show actual local observations and an exact redacted outbound preview. Missing evidence stays unavailable; edits/refreshed evidence invalidate preview. Preview needs no provider key. Acceptance covers truthful disclosure, not general diagnostic coverage or model-answer quality. | [AI runtime](architecture/capsule-ai-runtime.md) |
| Replaceable inference | Supported protocols share one transport. Owners may change endpoints/models or reconnect without rebuilding Capsule; a new protocol can require a host extension. Saved connections and model weights stay outside Core. | [AI runtime](architecture/capsule-ai-runtime.md) |
| Package/host boundary | Owner settings and Start may grant the autonomous workflow; dispatch checks package, scope, current authority and sandbox. Host does not repeat strategy/editorial policy. A mandatory service-history archive and per-step approvals are not API requirements. | [Plugin Host API](plugins/plugin_host_api_v1.md) |

## Evidence Index

Use the row matching the changed journey. Historical evidence remains bound to
its source, artifact and scope; it is not a new permission or completion claim.

| Journey | Existing evidence owner |
| --- | --- |
| Releases and exact packaged signoff | [Manual signoff](checklists/release-manual-signoff-log.md) |
| Capsule/Jack/Discovery and later owner-grant acceptance | `/Volumes/Dev/projects/hivra-artifacts/jack-capsule-acceptance-20261103/acceptance.json`; Jack completed-trade observations use its `jack_completed_trade_20261105` section |
| Moltbook candidate, publication and independent 0.8.4 Discovery delivery | `/Volumes/Dev/projects/hivra-artifacts/jack-capsule-acceptance-20261103/moltbook-smoke-20261104/plugin-candidate.json` |
| Earlier Moltbook read/prepare and owner connections | `/Volumes/Dev/projects/hivra-artifacts/moltbook-live-read-prepare-20261101`; `/Volumes/Dev/projects/hivra-artifacts/owner-connection-20261101` |
| Core backup | `/Volumes/Dev/projects/hivra-artifacts/core-backup-20261102/acceptance.json`; does not qualify physical-device peer-evidence reacquisition |
| Chat retention | `/Volumes/Dev/projects/hivra-artifacts/chat-retention-20261102/acceptance.json` |
| Analyst disclosure | `/Volumes/Dev/projects/hivra-artifacts/analyst-evidence-20261102/acceptance.json` |
| Inference connection/change/restart/removal | `/Volumes/Dev/projects/hivra-artifacts/inference-connections-20261102/native-acceptance.json` |

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
