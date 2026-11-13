# Hivra Development Control

Status date: 2026-11-13

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

Preserve Chat messages awaiting peer confirmation when their existing deferred
inbox cannot be read or saved. A missing file and a valid empty inbox remain
empty; existing blank bytes, malformed or unsupported snapshots, incomplete
record sets, duplicate identities and wrong-Capsule records must not become a
partial or empty writable queue. Validate the whole snapshot in the existing
deferred-inbox owner before projection or replacement. The existing receive
result must report a safe failure without disclosing file contents and must
leave adapter events unacknowledged until the durable handoff succeeds.

Retry uses the same receive path after storage recovers. If the timeline was
already committed before a deferred-inbox write failed, replay must retain its
stable message identities without duplicating content. The existing item cap,
first-seen expiry, schema and Core-only backup exclusion are unchanged; this is
not an archive, new retention guarantee or new delivery protocol. File access,
deferred-inbox parsing and Chat receive retain their three existing owners and
one handoff path. Remove the lossy empty/partial-read fallback instead of adding
a repair store, controller, API, permission or runtime entity.

Twelve regressions failed before the repair. All 81 focused and 813 full Flutter
tests, analyze and repository review gates passed, including retained limit/
expiry and replay after a committed timeline followed by a failed deferred
write. The repair adds 25 production lines in existing files and introduces no
runtime owner or write path. Source fault checks use temporary synthetic files
only. Exact `bc24dd6` Mac ZIP and Samsung APK passed in-place update, existing
Chat open, retained-history inspection, cache-budget inspection/Cancel, cold
process restart and return to the same Capsule. Repeated reads retained 75
messages on Mac and 24 messages / 100 MB on Samsung without changing either
budget. The three Mac and two Samsung identities, Ledger versions/hashes and
installed packages remained present. All 18 Mac baseline file hashes remained
unchanged. Installed Mac bundle files and the public Samsung APK matched the
packaged artifacts. The initial Mac Keychain handoff outlasted its wait; ordinary
retry opened the same Capsule, and cold reopen needed no further prompt.
Samsung used authorized visible ADB input, not private-file extraction. No new
Capsule, message, permission, trading action, publication or VPS mutation
occurred. Healthy native reads do not qualify injected corruption on owner
files or new end-to-end delivery; failure and retry evidence remains in the
source regressions. The source CI is green; integration and release remain
separate owner choices.

### Qualified Selected-Backup Restore Preservation

Preserve existing Capsule data and avoid partial publication when restoring any
supported backup format. Import Backup and phrase Recovery with a selected file
must converge on the existing atomic import owner, including encrypted v2,
plaintext v1 and raw-Ledger compatibility inputs. The seed and the native
read-only Ledger validator are required before any import writes; asking for
the matching phrase precedes publication rather than repairing authority after
legacy data has already been written. Existing Capsules are never overwritten
or merged with a snapshot. Wrong identity, invalid Ledger or unavailable secure
storage must leave existing data intact; failed staging rolls back and the same
import can retry.

Reuse the existing v3 staging, index/seed rollback and package admission path;
remove the direct legacy snapshot writer and phrase-recovery fallback instead
of adding guards to each path. Backup publication retains one persistence owner
and shrinks from two paths to one. The codec remains the format owner; no new
schema, store, API, controller, permission or runtime entity is introduced.
Core-only export scope and separate seed custody remain unchanged. Seed-only
identity recovery and existing read-only full-state v3 compatibility are outside
this repair and retain their existing behavior.

Source regressions use temporary synthetic files and fake secure storage only;
no installed Capsule, seed, backup, message, trading session or VPS is mutated.
Nine regressions reproduced the legacy overwrite, missing native validation and
partial-publication failures before the repair. All 108 focused and 799 full
Flutter tests, analyze and repository review gates passed; the existing native
Ledger-validator regression also passed without changing active runtime state.
Exact `287e911` Mac ZIP and Samsung APK passed cancellation, refusal to replace
an existing Capsule, preserved data, cold process restart and return. The owner
then authorized one disposable test identity for actual fresh-target restore.
Its native v3 Core export was 9,370 bytes. After confirmed deletion on Mac,
Import Backup restored the same identity, full Ledger hash, version 6, six
events and five starters; the displayed starter IDs matched. Importing that file
on Samsung, where the test identity did not exist, produced the same state.
Both restored copies passed cold process restart. Native deletion then removed
the test identity and its seed on both devices; both digest-matched temporary
backup copies were removed. Final cold launches showed only the original three Mac
and two Samsung Capsules with their original Ledger versions/hashes. All 18
Mac baseline file hashes remained unchanged. The earlier refusal smoke retained
installed packages; its temporary Samsung Core export went to recoverable
Trash, which was not purged. No new permission, message, trading action or VPS
mutation occurred. This qualifies fresh-target native v3 Core restore for the
tested Genesis history and preservation of existing data; it does not qualify
every legacy format natively or full long-term User Lifetime recovery.

### Qualified Retained-Chat Read Preservation

Preserve the retained Chat window when its existing encrypted timeline is blank.
The shared file owner distinguishes a missing timeline from existing empty or
whitespace bytes. The existing timeline owner rejects those bytes rather than
initializing an empty history: budget changes and incoming/outgoing durable
updates cannot replace the source, and ingress is not acknowledged before a
successful durable handoff. Restoring a valid source allows the same owner to
retry and recover its saved budget, completed messages and unresolved sends.

Missing files and authenticated empty timelines remain valid. The owner-selected
byte budget, completed-message eviction, encryption, Core-only backup scope and
read markers are unchanged. File access and encrypted timeline retention keep
their two existing owners and one durable timeline-write path; no new API,
schema, store, retry controller or runtime entity is introduced. All 55 focused
Chat tests, 782 Flutter tests, analyze and review gates passed. Four regressions
failed before the repair. Fault tests use temporary synthetic files only.
Exact `c1835c5` Mac ZIP and Samsung APK passed in-place update, existing Chat
open, saved-budget inspection/Cancel, cold process restart and return to the
same Capsule. Repeated reads retained 75 messages / 100 MB on Mac and
24 messages / 100 MB on Samsung. All 18 Mac baseline file hashes and both
visible Samsung Ledger hashes were retained. Samsung mirror touch injection
was unavailable; after one owner navigation step, visible UI taps/swipes used
the previously requested ADB fallback. No private Android files were extracted
or changed. Working history was not fault-injected; native acceptance covers
healthy reads/restart, not injected corruption or end-to-end delivery. No new
Capsules, messages, permissions, publications, trading or VPS mutations occurred.

### Qualified Delivery-Outbox Preservation

Preserve delivery recovery evidence when the existing outbox is unreadable.
`CapsuleFileStore` distinguishes a missing file from existing blank bytes;
`DeliveryOutboxStore` rejects an invalid or unsupported schema, incomplete
record set, duplicate identity or wrong-Capsule record before migration or
mutation. Failed reads/rewrite cannot become an empty queue or erase prior
publication evidence. Valid legacy schemas retain the existing quarantine and
receipt semantics. The same delivery lifecycle stops a failed scheduled pump,
handles its error once and releases it for a later ordinary retry; it does not
dispatch from an unreadable source or add another retry controller.

The Ledger remains authoritative; the existing outbox remains a local delivery
recovery index, not a service archive or guaranteed end-to-end queue. No new
schema, store, API, runtime owner or repair workflow is introduced. File access,
outbox parsing/mutation and delivery scheduling retain their three existing
owners and one canonical delivery path. All 57 focused store/lifecycle/invitation
and inspection tests, 778 Flutter tests, analyze and review gates passed.
Source fault tests use temporary files and synthetic records only. Exact
`bd10b05` Mac ZIP and Samsung APK passed healthy local inspection, cold process
restart, repeated outbox reads and return to the same existing Capsule. Counts
remained 38 records / 37 published / 0 pending on Mac and 5 / 5 / 0 on Samsung.
Mac baseline file hashes and both visible Samsung Ledger hashes were retained.
Diagnosis made no AI provider call; no new permissions or outgoing messages
were issued. Working owner files were not fault-injected: malformed source and
failed rewrites are qualified by source tests only. Live sends,
invitations/revocations, new Capsules, trading, publications and VPS mutations
remain excluded; this does not qualify end-to-end delivery.

### Qualified Recovery-Seed Migration Preservation

Preserve recovery seeds through failed legacy plaintext migration. Capsule
selection and bootstrap retain the existing `CapsuleSeedStore` migration path:
validate every source entry before writing, refuse conflicting secure seeds,
reuse identical stored entries, and delete the source only after all entries
are confirmed in secure storage. A differing visible legacy copy retains both
sources and blocks completion instead of silently deleting the other copy.
Unreadable data or failed native reads,
writes/read-back block activation with the existing retryable error instead
of deleting the source or reporting a missing seed. Retry may reuse verified
partial writes; it introduces no repair service, new plaintext fallback,
credential prompt, schema, API or persistence owner. Key derivation, Core,
Ledger and backup scope are unchanged. Migration source bytes and the secure
destination remain separate until successful verification.

All 87 focused seed/bootstrap/backup/selector/recovery tests, 757 Flutter tests,
analyze and review gates passed. Regression tests use temporary files and
synthetic secure storage only; working owner seed records are not fault-injected.
The existing migration owner/path remains 1/1, with no additional runtime files
or entities. Exact `d3a171c` Mac ZIP and Samsung APK passed existing-Capsule
open, cold process restart and return. Mac returned through the selector
without another unlock after restart; all three Ledger files, card/name files,
package registry and recovery bytes retained their baseline hashes. Samsung
retained both Ledger versions/hashes, its signer and original install time;
Jack open/return required no renewed permission or Start. Installed bundle/APK
bytes matched their packaged artifacts. The first Mac activation elapsed during
the owner Keychain handoff; ordinary retry opened the same Capsule without a
second prompt. Results belong to `seed_migration_preservation_20261112` in the
existing acceptance record. Healthy native open does not qualify injected
migration failure: malformed legacy sources and native storage faults retain
source-test evidence only. No new Capsule, trading, publication or VPS mutation
was used. These are unpublished test artifacts, not a release qualification.

### Qualified Plugin-Credential Read Preservation

Preserve plugin credentials when native storage returns an unreadable vault.
Only a missing Keychain entry starts an empty vault; an existing empty or
whitespace-only value follows the existing malformed-JSON failure path. Every
picker, reference resolution, connection save and cleanup retains the same
`CapsuleScopedSecretVault` owner. A failed read must neither overwrite native
storage nor cache an empty replacement, so retry can read a restored valid
record without restarting the application. No new store, permission, prompt,
repair, migration, API or runtime owner is introduced.

Source regressions use synthetic storage only and cover blank/malformed data,
rejected mutations, unchanged bytes, retry and existing package-removal failure
retention. All 73 focused vault/workspace tests, 740 Flutter tests, analyze and
review gates passed. Exact `e4afbd1` Mac ZIP and Samsung APK qualified saved
reference pickers, cancellation without renewed access, cold process restart
and return to the same Capsule. Mac retained all three Ledger files, card/name
files, package registry and recovery bytes; Samsung retained both Ledger
versions/hashes, its signer and original install time. Installed bytes matched
the packaged artifacts. Existing Moltbook reference metadata remained readable;
no credential values were extracted and no Allow or Start was used. Results
belong to `secret_vault_read_preservation_20261112` in the existing acceptance
record. Working Keychain records were not fault-injected: corruption/retry
remains source-test evidence, not native failure qualification. Trading,
publications and VPS changes were excluded.

### Qualified Saved-Card Read Recovery

Make saved-card loading failures visible and retryable in Settings. Initial
summary, opening and post-mutation refresh use one existing list read; the
separate raw-entry count methods are removed. Loading is not zero, and a thrown
read failure is unavailable information, not an empty address book. Tapping
the existing list retries the same reader; a successful empty read alone shows
zero cards. Raw exceptions and file contents are not disclosed.

Unavailable optional contact names must not hide readable cards: the dialog
shows Capsule addresses and a clear names-unavailable notice. Reopening reads
names again. The canonical card and name stores retain their existing parsing,
write protection and lifecycle; the legacy non-object card-root read fallback
is unchanged. No repair, schema, storage, host API or runtime owner is added.
Source checks cover parser/I/O failure, repeated failure, recovery to populated
and empty lists, deferred completion after disposal and optional-name recovery
at phone/desktop widths. All 40 focused tests, 736 Flutter tests, analyze and
review gates passed. Exact `3585315` Mac ZIP and Samsung APK qualified repeated
read/open/close, cold process restart and return in the existing Capsules.
Counts stayed 10/2 and names remained unchanged. Mac retained the card and
name-file hashes, Ledgers and Jack recovery bytes; Samsung retained both Ledger
hashes, its signer and original installation time. Installed bytes matched the
packaged artifacts. These unpublished test artifacts use the guard-permitted
`v1.0.6-test1` build number for an in-place Android update; no release was made.
Artifact-bound results belong to `contact_list_retry_20261111` in the existing
acceptance record. Working files were not fault-injected: failure/retry and
optional-name failure/recovery remain widget-test evidence. No new Capsule or
contact, data mutation, message, trading or VPS mutation was used.

### Qualified Contact-Name Preservation

Keep owner-local contact names intact when a rename fails or overlaps another
rename. `CapsuleContactLabelStore` remains the only name owner and write path;
its existing Capsule file and atomic writer are retained. The whole mutation
is serialized per file across store instances. Missing data may start empty;
an existing empty, malformed or unsupported file is not permission to replace
the saved names. Read-only presentation retains its best-effort fallback.
This is local restart retention, not a new archive, backup, repair or migration.

The existing name dialog must show a safe save failure, keep the entered name
and allow retry without claiming a successful rename. A committed card removal
still completes if its optional local-name cleanup fails; the names file is
retained and that cleanup failure is disclosed. Core, card identity, provider
protocols, secrets and Ledger do not change. Source qualification uses temporary
file faults, two simultaneous store instances and phone/desktop widget journeys;
20 focused tests, all 730 Flutter tests, analyze and review gates passed.
Exact `50cc1a7` Mac ZIP and Samsung APK qualified saving the current value,
cancelling a changed draft, reopening the original value, cold process restart
and return to the same Capsule. Mac retained all three name-file hashes, the
card inventory, Ledgers and Jack recovery bytes. Samsung retained both card
labels and Ledger v17/v12 hashes; its existing empty name stayed unset. Card
counts remained 10/2. Installed bytes matched the packaged artifacts, and
Samsung retained its signer and original install time. Artifact-bound results
belong to `contact_label_preservation_20261111` in the existing acceptance record.
Working data was not fault-injected: corrupt-file failure/retry and optional
name-cleanup failure remain source-test evidence. No new Capsule, contact,
message, trading Start or VPS mutation was used.

### Qualified Contact-Card Preservation

Preserve an existing contact-card file when it contains syntactically valid
JSON with a non-object root. Explicit import, key synchronization and cleanup
must not reinterpret unreadable saved data as an empty writable address book.
`CapsuleAddressService` enforces this inside its existing per-file mutation
queue before the action or atomic write. Read-only fallback for non-object
roots remains unchanged, and optional routing metadata must not block Core
activation. There is no new store, repair path, backup, schema or migration.

Source regressions cover malformed JSON, array/null/scalar roots, every card
mutation entry point, unchanged bytes and successful concurrent operations
after an external repair. Working owner data is not fault-injected. Exact
`e18d09b` Mac ZIP and Samsung APK qualified existing-card reimport, unchanged
card counts (10/2), cold restart and return to the same Capsule. Mac upgraded
an existing v1 own card with its signed Share-card output and repeated
that import; Samsung reimported its existing signed card. Ledger v121/v17 and
Mac recovery-file hashes remained unchanged. Artifact digests and bounded
acceptance are recorded in the existing `acceptance.json` under
`contact_card_preservation_20261111`; native corrupt-file recovery is not claimed.
No new Capsule, contact, relationship, message, trading Start or VPS mutation
was used.

### Qualified Plugins Inventory Recovery

Make Plugins recover visibly from an unreadable local package inventory. A
failed registry read is unavailable information, not an empty installation.
The screen must end loading, show a safe retry action, and avoid offering
package mutations or activation until the canonical registry can be read.
Retry reuses that registry; no screen repair, alternate inventory, new store,
service or provider policy is introduced. Working owner files must not be
corrupted to exercise the failure.

Widget regressions reproduce malformed-file and filesystem failures at phone
and desktop widths, repeated failure, successful retry and package activation.
All 713 Flutter tests, analyze and review gates passed. Exact ZIP/APK from
`c8a079b` qualified healthy inventory, published-catalog loading and Jack
open/return on Mac and Samsung. Mac's three Ledgers, recovery files and package
registry were unchanged; Samsung retained its original install time, both
Capsule Ledger hashes and three package versions. The installed APK digest
matched the packaged artifact. These checks introduced no new Capsule, grant,
trading Start or VPS mutation. Native owner files were not fault-injected;
malformed-file and I/O failure/retry remain widget and registry-test evidence.
Artifact-bound results belong to `plugin_inventory_retry_20261111` in the
existing acceptance record below.

### Qualified Local Package Removal

Remove the existing local Jack package on Mac through Plugins → Remove without
contacting a previously selected VPS. A saved connection is a transport choice,
not an execution assignment. Keep the existing registry, secret cleanup and
opaque recovery retention; an assigned VPS still requires authenticated return,
and malformed execution controls still fail closed. No manual data cleanup,
new Capsule, trading Start or VPS mutation is part of this acceptance.

Source regressions reproduce the failure with a replaced local grant and an
unavailable saved server, and cover retained remote authority and corrupt grant
data. The exact 475620b Mac ZIP qualified native removal, absence after a cold
restart, Discovery reinstall and Jack open/return in the same existing Capsule.
All three Ledgers, Jack's three recovery files and the other package records
remained unchanged. No new access, Start, manual cleanup or VPS mutation was
performed. Artifact-bound evidence is in the existing acceptance record below.

### Qualified Jack Market-History Result

Make Jack read all selected timeframes for a contract listed inside its bounded
600-candle window. Existing Mac and Samsung 0.2.4 both reject MNT's leading daily
pages: the service has 459 contiguous daily candles including the current one,
not 600. Its matching contract reports launch time 1754539200000; the first daily
candle starts at 1754524800000. The first 96-candle page from that listing candle
is complete. A missing pre-listing candle is not an internal service gap.

The package owns the adjustment. A short leading page may trigger one public
contract read; only unique matching-symbol launch evidence inside the requested
window can move its start. Re-read through the same bounded page path and retain
all gap, closed-candle, current-quote and zone first-known coverage checks. Missing
or contradictory launch evidence still fails. Blindly skipping empty pages is
rejected because it could hide unavailable history. No host operation, provider
adapter, persistent listing cache, strategy change or new Capsule is needed.

Qualification requires listing/gap/restart regressions, the canonical replacement
WASM, complete fresh native reads on Mac/Samsung, preserved pending-order identity,
return and restart. Initial native reproduction retained Ledger v121/v13, left
both schedules off and restored MNT 1m through successful read-only refreshes.
Listing qualification requires no Start, exchange mutation or VPS update.
Canonical 0.2.6 passes
102 package tests, both repository CIs and the existing actual-WASM replacement
probe. Mac completed two fresh native all-frame reads, the second after a cold
process restart with saved access and the same selection. Each reached
`complete=true`; every required frame had a newer quote observation and its
last closed candle matched that observation. The original MNT 1m read also
completed. Capsule and host production code were not changed or rebuilt.
Samsung's canonical 0.2.6 replacement retained the pending MNT order and saved
one-hour access. Its first all-frame read ended visibly with `100410`; after a
pause and cold process restart, the same native action finished without error
and returned a fresh quote. Fresh Open orders returned the same four IDs.
On 11 November, two more native all-frame reads completed without a visible
error, including one after another cold restart. Saved access, the selection,
Capsule and Ledger v13 survived. The second read reconciled the same 220.16 MNT
entry as closed by SL: average entry 0.4542, exit 0.4556, trading PnL -0.308224
USDT and signed fees -0.070151 USDT, yielding -0.378375 USDT excluding funding.
Matched fills and flat position/order evidence confirmed that result; a fresh
open-order read retained the unrelated BUY/LONG trigger order without adoption
or cancellation. The initial `100410` remains in the evidence; these successful
repeats establish the bounded native read journey, not continuous rate stability.
Android acceptance used native UI results; individual raw frame timestamps were
not inspected. The final MNT 1m read recovered after one visible unavailable
service response, then returned a fresh quote and the same confirmed SL result.
Return preserved Ledger v13 and three packages, with the automatic cycle off.
No Start or exchange mutation was used for these checks.

A separate unsigned GET sequence reproduced `100410` on request 22 at roughly
1.2-second dispatch spacing; the host, credentials and WASM were absent. A slower
constant alone still met a later rejection. The repaired package reuses its
existing transient retry count and wait requests: rejected pages keep their
exact offset, cooldown increases and remaining candle reads slow down. The two
retries remain bounded across the action; mutation requests gain no retry. The
same public paging algorithm completed all six frames in 50 requests, including
two real rate rejections followed by successful reads of those exact pages.
Moving this service policy into a host throttle is rejected. Enlarging candle
responses is unnecessary and would change the proven sandbox/input budget.
A persistent provider refusal still ends visibly rather than fabricating data
or retrying indefinitely. Results belong to `jack_market_history_20261108` and
its `rate_recovery` section in the existing acceptance record.

The completed-trade accounting repair uses the observed service fill shape;
Capsule production code is unchanged. Its existing actual-WASM probe covers
partial/full reducing fills, reopen and executor replacement/removal. Mac
replacement and fresh reads confirmed its retained MNT SL; Samsung's later
0.2.6 read above also exercised closed-trade arithmetic and flat reconciliation.
These retained trades do not qualify new-cycle TP, closure/reentry or restart
during a managed trade. Earlier results belong to
`jack_completed_trade_20261105.fill_response_repair_20261108` in the existing
acceptance record.

The owner separately pressed Start on Samsung on 11 November with MNT-USDT 1m,
1 USDT / 20%, using the existing one-hour permission. A local cycle completed
with no eligible entry and no order sent; the following cycle reported an
unavailable service response without blind resubmission. After permission expiry
the native workspace showed inactive permissions and automatic cycle off.
This qualifies local Start/expiry observation, not a new trade or continuous
operation. Results belong to `rate_recovery.samsung_026.owner_start_20261111`
under `jack_market_history_20261108` in the same acceptance record.

Owner Start/device replacement is accepted on the exact main-equivalent
Mac/Samsung artifacts for MNT-USDT 1m, 1 USDT / 20%. Each owner Start replaced
the managed process, ended the prior executor and completed package cycles;
Samsung continued with its app process stopped, then reopened saved access and
returned to the same Capsule without root setup. The pre-existing MNT position
and its orders were unchanged. Results belong to
`vps_start_replacement_20261105.current_main_start_acceptance_20261108` in the
existing acceptance record. Failed/stale Start retains source/real-WASM evidence;
no working owner data was fault-injected. This does not qualify a new entry fill
or completed trade.

Stopped recovery after server-identity/device replacement is merged in PR #427
and accepted on exact Mac/Samsung artifacts with the same source tree as main
`cdee304`. Owner-verified root repair, saved-key cold reopen, sealed-checkpoint
return, failed-open local revocation and unavailable-network controls passed;
Samsung reopened the saved VPS after the owner restored VPN. Permissions stayed
revoked and opaque checkpoints were retained. Results belong to
`vps_start_replacement_20261105.stopped_recovery_20261107.identity_recovery.android_offline_revocation_20261107`
in the existing acceptance record below. This closes stopped recovery, not
financial Start or Jack's completed-trade journey.

The canonical Moltbook 0.8.6 package and Capsule `5673149` APK are installed in
the same Samsung Capsule, with Ledger v13 and saved credentials retained.
Owner Start completed a cycle at 15:22:07 MSK on 2026-11-08: all five recent
GitHub source commits were already represented in verified service posts, so
the package sent no duplicate. Independent public reads confirmed those source
matches. Schedule state, last result and Run/Stop controls were visible before
configuration and survived workspace return/reopen. The owner-authorized local
schedule remains enabled; the app must stay open. Results belong to
`owner_grant_reuse_20261107.moltbook_samsung_start_20261108.source_repair` in the
existing acceptance record. This qualifies the repaired Samsung cycle and
presentation, not a new 0.8.6 publication/challenge or native injected gateway
failure; those paths retain regression-test evidence. No new Capsule, API,
store, Jack action or VPS mutation was introduced.

The registry corruption repair is merged and accepted for source faults and
exact Mac/Samsung healthy-inventory smoke in `registry_corruption_20261107` of
the existing acceptance record below. Owner data was not fault-injected.

The import form, Cloudflare Account ID form and bounded owner-connection reuse
journeys are accepted on their recorded artifacts. The existing acceptance
record below owns the results: `card_import_layout_20261107`,
`cloudflare_account_form_20261107` and
`owner_grant_reuse_20261107.current_main_qualification`. The last covers cold
Mac/Samsung launch, saved access, repeated Connect, AI preparation without
sending and return. These results do not qualify destructive removal or Jack's
remote/trading journey; a clean `main` does not close those debts.

## Runtime Work Still Awaiting Acceptance

The common API contract owns behavior; the existing acceptance record owns
artifact-bound results. Source tests, fixtures and earlier packaged runs do not
qualify changed bytes. Accepted bounded journeys do not close unrelated runtime
work.

| Bounded outcome | Source behavior / remaining acceptance |
| --- | --- |
| Preserve private files when native secret cleanup fails | The existing removal path cleans secrets before files. Fault-injected module tests cover both retention choices, non-executable pending state and retry with a reopened registry; native Keychain failure is not exercised on working owner data. |
| Use one peer address and retain concurrent card updates | Chat and pair-attestation exchange share the address owner; persistence delegates card writes and cleanup. Source tests cover precedence, concurrent mutation, reopen and corrupt-file behavior. Exact e265681 Mac/Samsung smoke qualified existing-card reimport, one Mac-to-Samsung message, cold process restart and return. Real contact/Capsule deletion and new invitation were excluded on owner data; those cases retain source-test evidence. Results: `address_consolidation_20261107` in the existing acceptance record below. |
| Show Jack's actual completed trade and continue | Package-owned last-trade locator and pre-dispatch recovery use the common API. Native Mac and Samsung reads reconstructed their retained MNT SL results; Samsung 0.2.6 also retired the filled entry after complete flat evidence. Replacement, cold restart and return passed without rebuilding Capsule. Live new-cycle TP/closure/reentry and restart during a managed trade remain open; historical SL reconciliation does not qualify them. |

These source repairs are not qualified by the published test3 artifacts.
Moltbook's independent Discovery update on Mac and Samsung qualified package
replacement/open/return without rebuilding Capsule; exact 0.8.4 live writes
were not repeated. Earlier authorized publication evidence is package-specific,
and generated prose remains model-dependent. General host/package convergence
is still open.

The original Discovery delivery qualified install/open/return and restart on
its recorded Mac/Samsung bytes. It did not qualify full trading outcomes,
continuous operation or later host changes. The current all-frame market-history
qualification is recorded in the selected outcome above; a successful 1m read
alone does not close it.
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
