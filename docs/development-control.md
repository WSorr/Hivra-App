# Hivra Development Control

Status date: 2026-08-14
Current released baseline: commit `2a23411` (`v1.0.3-test16`, macOS and Android manual signoff recorded)
Current development focus: packaged evidence closure after the completed `1.x
Relationship Root-Signed Break Projection` remediation. The fix is merged at
`89c3b36` through protected PR `#63`; post-merge repository run `31710031485`
passed. Fresh macOS and Android Release artifacts were built from that exact
SHA. macOS Hands evidence proved that a real root-signed remote Seed break
became pending, required the existing local confirmation, and left the
Relationships screen with one visible canonical refresh action. Cross-platform
Chat evidence then proved one accepted macOS-to-Android delivery, one accepted
Android-to-macOS delivery, passive receive, unread projection, and persistence
of the `A27` conversation after a real macOS process restart. Android cold-
restart persistence remains the only unclosed packaged evidence item because
the device is currently disconnected. No active runtime finding, following
product pass, tag, or Release is selected.
The preceding `1.x Capsule-scoped Chat Unread Indicator` remains complete.
The preceding durable receive handoff is complete on `main` at `c9caa7e` with
green protected PR/post-merge gates and packaged macOS/Android restart smoke.
The bounded implementation extends the existing Chat inbox/projection owner
with one persisted Capsule-scoped read state over retained message ids. The
cross-screen Plugins navigation badge is a shell projection only, and messages
become read only after the canonical Chat workspace projects them. Replay,
restart, retention, corruption, Capsule isolation, and concurrent projection
vectors are covered. Protected PR `#60`, post-merge run `31673505950`, and
fresh packaged macOS/Android Hands smoke from source `d50e70f`, local build
`1.0.3+100030025`, completed the pass. A second inbox,
transport route, Core/Ledger fact, OS push service, attachment lifecycle, or
cross-Capsule unread state is not authorized. The bounded Android
Invitations refresh remediation is complete on `main` at `96433fa`. The top-
bar action now invokes the existing canonical passive-receive owner, refreshes
the retained Capsule-scoped projection independently of Ledger-version change,
and presents every non-empty result through the same invitation feedback path
as pull-to-refresh. Fresh packaged Android Release smoke from `96433fa`, local
build `1.0.3+100030023`, SHA-256
`0886443a6eee643025395f8b0310c8e0a2f1df3ae06a1c5fcc657e413483c151`,
proved a top-bar tap produced `reason=manual` and the user-visible
`No new invitation deliveries` result without a swipe. Protected PRs `#54`
and `#56` and post-merge repository gate `31664542748` passed. No second
receive, inbox, transport, projection, or feedback owner was added. The bounded
P2 Capsule AI unlock remediation is complete on `main`. Packaged macOS Release
smoke from `b6c2e01` migrated the legacy provider preference, then a cold restart unlocked
Gemini with zero password prompts and changed `Unlock AI` to `Lock AI`. Provider
credentials remain in Secure Storage while the non-secret provider id belongs
to local configuration under the same credential owner. No second credential
owner, provider path, or AI authority was added. The completed Moltbook feed
pass adds one
Capsule-scoped, commitment-bound queue of explicitly confirmed public facts to
the existing Moltbook plugin-state owner. Gemini may propose the next queued
item only after process-scoped unlock; the existing WASM draft, exact approval,
external-effect, receipt, and reconciliation owners remain unchanged. Direct
AI access to Ledger, repository, Capsule history, credentials, or publication
authority remains forbidden. A Git/CI producer is not part of this pass.
Trading Restart Recovery and Reconciliation is complete on `main`. Exact
account-bound provider evidence now distinguishes active,
terminal, and unresolved managed orders without adopting manual orders or
recreating missing effects. Remote Runner/VPS and background execution remain
blocked. `v1.0.3-test16` remains the published
GitHub test prerelease. Exact artifacts built from clean source commit `30e0800` passed
packaged hands smoke on macOS and Android; release tag `v1.0.3-test16` records
the evidence-only HEAD `2a23411`. The published macOS artifact is unsigned and
not notarized. Moltbook Reference-Grade passes A-B closed the session-trigger
latch and verified the existing Assisted post/reply lifecycle through exact
approval, publication challenge, receipt reconciliation, cold restart, and
no-duplicate recovery on Android. No new effect owner, release candidate, or
automatic publication authority was added. Moltbook Reference-Grade Pass C is
complete: explicit foreground nested-reply authority uses the existing
engagement/effect path. Android Hands smoke found that WASM could
reselect a journal-owned comment and stop before considering another eligible
comment; the existing publication owner now filters such targets before
planning. Follow-up Android smoke then proved that a `no_action` result on the
first heartbeat candidate starved later candidates; the same cycle owner now
continues through the bounded ordered set while still advancing at most one
action. Final cross-Capsule review found that the same external account could
already have answered a target from another local Capsule, so provider-visible
direct replies now close that target before planning. Packaged Hands smoke from
source `4899b2d`, build `1.0.3+100030020`, passed on macOS and Android: exact
approval, challenge verification, provider receipt, public visibility, cold
restart, ordered candidate exhaustion, and no duplicate effect were confirmed.
The Trading protective-order ownership audit is complete. BingX placement and
open-orders contracts expose no verified parent-to-generated-protection ID
binding, while the documented `triggerOrderId` read field is insufficiently
directional to authorize ownership. Hivra therefore keeps those orders
`Exchange only`; exact managed `orderId` evidence and Capsule-scoped tracking
remain the only ownership path. No heuristic adoption, second registry, DTO,
service, exchange effect, or runtime route was added. The bounded Capsule AI
Runtime restart acceptance is complete. It changed no production runtime:
automated evidence proves process-lock and Capsule binding, while packaged
macOS `test16` evidence proves that Gemini configuration survives a cold start,
an explicit Ask restores the saved credential without key re-entry, outbound
context remains redacted, provider backpressure is visible, and one bounded
retry returns an advisory result. Trading Remote Runner Pass B remediation is
complete: public market shadow computation is physically separated from local
consensus/risk/execution inputs, verification begins from exact canonical
untrusted bytes, and Dart plus independent Python golden evidence covers wire,
hash, key binding, and negative mutations. Runtime consumers, network,
persistence, credentials, UI, VPS, exchange effects, Pass C, and a second
execution path remain unauthorized. The bounded post-Pass-B consolidation is
complete: the existing TVH rule owner now exposes market-only evaluation
without consensus inputs, while its existing guarded entry retains local
consensus policy. No decision semantics or product authority changed.
Trading Liquidity Lifecycle hardening is complete as a bounded 1.x product
pass. The
existing market pipeline now excludes forming provider candles from the
canonical snapshot digest, derived liquidity, and zone evaluation, and the
existing zone owner reduces a bounded closed-candle sweep/reclaim lifecycle
with ATR-body, expiry, and retest limits. No new owner, plugin ABI, credential,
network, persistence, remote runner, or exchange-effect path is added. Full
automated gates and an automatic macOS zone-calculation smoke are complete. The
smoke scanned the six-symbol Core Watchlist, selected a READY SOL-USDT setup,
calculated an executable fresh sellside zone, and prepared a decision envelope
without invoking an exchange order effect. No live order, release, or following
pass was authorized by that result. The active pass keeps liquidity-event
identity in the existing zone owner, freshness and exchange submission in the
existing execution use case, and durable Capsule-scoped effect claims in the
existing managed-order store. Remote Runner/VPS, background execution, a new
plugin ABI, and any second effect route remain unauthorized.
Stable `1.0`, another release candidate, and 2.0 runtime work remain
unauthorized without a separate explicit decision.
V2-0 passes A-E and V2-1 passes A-E are complete; 2.0 design is paused with no
next pass selected. They
established repository ownership evidence, Capsule identity/birth, Starter
inventory, continuity export, recovery, and Capsule selection/prepared-
activation contracts without changing a runtime path. Recovery, persistence,
UI/FFI, addressing, seed handling, import/export/delete, and runtime
implementation remain unauthorized. Capsule AI Runtime convergence remains
complete, feature-owned provider dispatch and credential reads remain zero,
and the full T0 environment verifier matches every repository pin. No AI-5,
T1, or other runtime upgrade is implied.
Transactional serialized
plugin install/update/remove is complete; authenticated Nostr delivery uses
signed kind `9444` plus NIP-44 v2, while deprecated kind `4`/NIP-04 remains
isolated to guarded read-only compatibility input.

This is the short operational map for deciding what Hivra work is happening
now. It is not a second specification, backlog, or release record. It points
to the authoritative document for each kind of decision.

## 1. Read This First

Before resuming work, answer four questions in this order:

| Question | Current answer | Authority |
| --- | --- | --- |
| What product rules cannot move? | The product axis, the three laws, local-first Capsule ownership, Ledger truth, and capability isolation. | `product-axis.md`, then `specification.md` |
| Which runtime is releasable? | Hivra 1.x on `main` is the sole production line. | `specification.md`, release checklists |
| What is the next 1.x step? | No next pass is selected. Moltbook Change Feed and the AI unlock remediation are complete; Git/CI ingestion, automatic publication, Remote Runner/VPS, deployment, and release remain blocked pending an explicit product decision. | `architecture/capsule-ai-runtime.md`, `plugins/moltbook_engagement_lifecycle_v1.md`, `roadmap.md` |
| Is 2.0 implementation work allowed? | No. Completed V2-0/V2-1 design checkpoints authorize no production path; a later unit must be selected explicitly. | `architecture-v2-blueprint.md` |

Do not start from the chronological history in `roadmap.md`. Start from this
table, then open only the linked authority for the selected work item.

## 2. Current Development Board

| Line | State | Current unit | Completion evidence | Next boundary |
| --- | --- | --- | --- | --- |
| **1.x maintained runtime** | Relationship root-signed break remediation complete; Chat packaged evidence closure active | Existing Core relationship projection and existing Capsule-scoped Chat timeline remain the sole owners. | PR `#63`, post-merge run `31710031485`, real remote-break confirmation, bidirectional packaged Chat delivery, passive receive, unread projection, and macOS cold-restart persistence passed from `89c3b36`. | Complete Android cold-restart Chat persistence; no following product pass is selected. |
| **1.x release** | `v1.0.3-test16` published as test prerelease | Verified source artifacts from `30e0800`; evidence-only release tag at `2a23411`. | Manual signoff, guarded preflight, exact remote asset digests, PR gates, and post-merge gates passed. | No next candidate or stable `1.0` claim is selected automatically. |
| **2.0 architecture** | `V2-0` and `V2-1 / passes A-E` complete; paused with no next pass selected | No active 2.0 unit. Runtime implementation remains unauthorized. | Post-Pass E consolidation confirmed one normative blueprint owner, subordinate schema/vector evidence, history-only roadmap entries, and registry-owned production debt without a duplicate contract source. | Resume only by an explicit later decision after the active 1.x product pass; do not infer Pass F. |
| **Platform toolchain** | T0 reverified | One baseline manifest, exact Rust pin, and fail-closed verifier cover the Flutter/Dart, Rust, Android, and macOS matrix. | Full verification on 2026-08-04 matches every pin; only the documented simulator-discovery and host-evidence warnings remain outside macOS/Android packaging scope. | T1 remains unselected; select a dedicated upgrade unit only after V2-0/pass A or a release-blocking toolchain finding. |
| **Capsule AI Runtime** | P2 unlock remediation complete on `main` | The existing credential owner keeps provider credentials in Secure Storage, the non-secret provider id in local configuration, and one process lease. | One protected read per post-migration unlock, bounded non-enumerating legacy migration, malformed local preference failure, PR `#52`, post-merge run `31659447915`, and packaged macOS cold-restart smoke from `b6c2e01`. | No next AI pass is selected; no second credential owner or AI-5. |
| **Future product tracks** | Parked | AI trading advice, distributed backup drone, staking drone, and any further Moltbook authority remain unselected. Moltbook Observe/Assisted effects and explicit foreground bounded replies retain their existing reviewed boundaries. | Their own approved contract and capability-closure result; Moltbook additionally follows `plugins/moltbook_engagement_lifecycle_v1.md`. | They do not become active without an explicit product decision. |

`12.3` passes 1-18 are complete. Any later transport remediation requires a
new named finding and bounded pass; no pass is inferred merely because a screen
appears to work in one manual run.

### Ordered Tail

This is the current execution order, not a second backlog:

1. **P1 — complete:** The bounded Moltbook Capsule Public Change Feed passed
   full gates, protected PR `#50`, and post-merge CI at `caed6d4`. No next pass
   is selected; do not infer Git/CI ingestion, automatic publication, Remote
   Runner/VPS, background trading, or release.
2. **P2 — complete:** AI provider preference migration and post-migration cold
   unlock passed from `b6c2e01`; the same process lease and credential owner
   remain canonical.
3. **P3 — parked work:** crypto-agility protocol design, dependency upgrades,
   AI trading advice, distributed backup, and staking remain non-runtime or
   parked until the active design unit or a named release decision permits
   selection.

Unchecked boxes in reusable release/smoke checklists are execution templates,
not automatically active debt. A checklist becomes active only for a named
candidate or selected pass recorded here and in `roadmap.md`.

## 3. The Only Two Work Lanes

```text
1.x maintenance
  reported failure or review finding
  -> one scoped remediation pass
  -> regression test + gates
  -> focused manual smoke when risk requires it
  -> commit
  -> optional release decision

2.0 design
  capability inventory or future requirement
  -> owner + public contract + dependency proof
  -> migration/removal target + compatibility decision
  -> design review
  -> no 1.x runtime code until the 2.0 exit rule permits it
```

A task must name exactly one primary lane. A 1.x fix may add a test or a gate
that helps 2.0 later; it must not add speculative v2 events, DTOs, services, or
parallel execution paths. A 2.0 design task may use 1.x code as evidence; it
must not change 1.x behavior merely to make a diagram look cleaner.

## 4. Session Protocol

At the beginning of a development session, record the following in the task
conversation before editing:

1. **Lane and item:** for example, `1.x / 12.3 pass 3` or `2.0 / V2-0`.
2. **Invariant:** the one product-axis invariant being strengthened.
3. **Owner:** the sole capability/module allowed to own the decision or effect.
4. **Exit evidence:** exact tests, gates, and manual smoke required.
5. **Removal/sealing:** the old path, ambiguity, or forbidden edge that will
   disappear or be made unreachable.

Before packaged manual smoke begins, follow the operator-selection rule in
`docs/checklists/manual-smoke.md`: stop and ask **"Hands or automatic?"**. Do
not start interactive actions until the person chooses who drives the UI.

At the end of a meaningful pass, update only the source that owns its status:

| Change type | Update |
| --- | --- |
| Current behavior, protocol, invariant | `specification.md` and, if user-visible, `hivra-conceptual-model.md` |
| Engineering item state / next pass | `roadmap.md` and the board in this file |
| 2.0 ownership / contract / migration proof | `architecture-v2-blueprint.md` and the board in this file |
| Flutter/Rust/Android/macOS toolchain update | `docs/platform-toolchain-evolution.md`, the roadmap, and release evidence |
| Release readiness | the applicable release checklist and release evidence |

No status update means the work is not ready to be called complete.

## 5. Decision Rules

- If a proposed feature does not have one named owner and public contract, it
  is `NEEDS_CONTRACT`, not implementation work.
- If it needs a new Core fact, event, or trust meaning, it is
  `NEEDS_PROTOCOL`, not a Flutter workaround.
- If the same intent can reach an external effect through two paths, stop and
  consolidate its lifecycle before adding behavior.
- If the task cannot state what old path is removed or sealed, it must not add
  a new abstraction.
- If a manual test exposes a discrepancy, record the reproduction and route it
  into one active 1.x remediation pass rather than creating an untracked fix.
- If a task is not needed for the next 1.x release and changes ownership or
  contracts, it belongs in the 2.0 design line first.

## 6. Repository Integration Gate

Repository integration and product release are separate processes.

- `.github/workflows/release-gates.yml` is the repository push/PR workflow
  displayed as `Hivra Repository Gates`. Its required GitHub status context is
  the stable job name `review-gates`.
- `main` accepts changes only through a pull request. Branch protection requires
  `review-gates` on the current head, requires the branch to be up to date,
  applies to administrators, and forbids force pushes and branch deletion.
- The repository workflow validates a commit; it does not create a tag, build a
  release candidate, publish artifacts, or replace the explicit release
  scripts, checklists, manual signoff, and guarded publication process.
- A green local `tools/review/review_all.sh` is necessary but not sufficient
  when CI, review gates, documentation integrity, toolchains, or generated and
  ignored paths change. Those changes must also pass from a clean detached
  checkout and then pass the GitHub `review-gates` check on the pushed branch.
- After every push, inspect the corresponding GitHub Actions run and wait for a
  terminal green result. Do not merge, push another pass, or call the commit
  complete while that run or the previous repository-gate run is red.
- Required checks, pull-request enforcement, administrator enforcement, and
  force-push/deletion restrictions have no repository-local bypass. If GitHub
  cannot enforce them, work stops at a documented external limitation rather
  than substituting a script that direct pushes can bypass.

## 7. Practical Reading Set

For a normal 1.x repair, read only:

1. `development-control.md`
2. the relevant `roadmap.md` item
3. `product-axis.md`
4. the relevant specification/architecture contract and focused tests

For 2.0 design, replace item 2 with `architecture-v2-blueprint.md` and use the
current code only to inventory reality. This keeps the context small without
forgetting the product's hard rules. `V2-0` may start once the current baseline
and ordered 1.x debt are reflected consistently in this document and the
roadmap; it remains design evidence only until the blueprint exit criteria are
satisfied.
