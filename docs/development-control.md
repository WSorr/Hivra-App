# Hivra Development Control

Status date: 2026-10-23

This file is the Hivra control plane. It owns current decisions, development
rules, the selected product outcome, and the integration boundary. Detailed
history belongs in Git, pull requests, release signoff rows, and focused
evidence documents; historical paragraphs below never reopen a retired path.

## Development Rules

### 1. Establish the owner before editing

Before changing code, identify the complete input-to-effect path, its canonical
owner, existing tests, compatibility paths, and the document that owns the
contract. If the change would add an owner, reducer, DTO, lifecycle, gate, or
document, first redesign it to reuse or replace an existing one.

### 2. Keep one truth lane and one effect lane

- The Ledger owns historical domain facts.
- Canonical projections own current state.
- The App Shell renders projections and sends explicit intents.
- WASM owns package-private strategy and policy semantics.
- The host owns authorization, credentials, persistence, normalized provider
  evidence, and permitted effects.
- A transport or provider adapter moves data; it does not become a domain owner.

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

## Current State

- Hivra 1.x is the only maintained runtime; Hivra 2.0 remains design-only.
- Protected `main` includes package/VPS recovery, the last-result Moltbook
  lifecycle, replacement/reopen/restart and manifest capability admission.
  Read Git for the current commit.
- The latest published prerelease is `v1.0.4-test3`, with runtime source
  `6660392` and its matching canonical runner. Its tag adds only digest-bound
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
- Chat, Moltbook and Jack Ventura use installed WASM packages. Moltbook now
  keeps its last post result until public visibility, exact text, link and
  moderation have been shown and explicitly completed. Its canonical contract
  is `plugins/moltbook_engagement_lifecycle_v1.md`. Exact packaged archived-result
  smoke covered refresh, reopen and restart without a new publication; a live
  automatic reply receipt remains unobserved.
- Capsule-scoped credential stores remain authoritative; AI unlock is
  process-scoped. The Flutter 3.47.4, Dart 3.13.3, Xcode 27.1, and Swift
  Package Manager baseline remains authoritative.

## Current Jack Ventura Boundary

Jack Ventura is the maintained installable WASM trading capability. Its v1
boundary is one selected instrument, host-owned credentials, one local or VPS
executor, one durable effect journal, provider-scoped reconciliation, Stop,
package replacement, restart recovery, and bounded VPS installation.

Existing v1 evidence proves package replacement, restart-safe workspace state,
exact-order reconciliation, bounded provisioning, and one accepted entry
lifecycle. It does not prove
profitability, fill-to-closure-to-reentry, exchange-side protection, or
continuous autonomous VPS operation. The retired Trading runner and strategy
must remain sealed.

Open Jack evidence is bounded to these items:

- live closure/reentry, conditional-stop behavior, protection verification,
  and loss-of-response recovery remain unproven;
- packaged runtime-update smoke remains pending.

No new strategy filter, runner, host fallback, or second effect owner is
permitted under this boundary. Any future Jack pass must use the existing
package/executor path and replace one of the open evidence items with actual
provider evidence.

## Selected Product Outcome

The active maintenance outcome is complete authenticated Capsule backup and
recovery through the existing codec/persistence/file-delivery owners: readable
public ID + UTC date names, durable Capsule state and opaque package state,
normal ZIP package admission, no platform credential export, no stale workspace
execution renewal and no overwrite of an existing Capsule. The canonical wire
and safety contract remains in `specification.md`. Acceptance uses isolated data
for full restore/reopen/restart, package replacement, authentication/path/package
rejection and failure rollback. Exact packaged acceptance is pending a clean
approved source and matching runner; existing attested artifacts are unchanged.

The preceding dependency outcome (wincode 0.6.3 with frozen bincode 1.3.3 byte
compatibility, no storage migration) is retained in the current Git base. This
backup pass does not change dependencies, toolchain pins or its source scope.

The bounded Capsule/package release outcome is complete in `v1.0.4-test3`.
Real Chat, Moltbook and Jack packages were installed/opened, removed through the
product, kept absent through restart, then reinstalled/opened from the canonical
catalog on both exact platforms. Unrelated package state and Capsule truth were
preserved; deleted Moltbook drafts did not return. New two-way Chat after
reinstallation survived restart exactly once. Replacement with a different
private state shape retained opaque state through reopen/restart, and missing
required capabilities blocked workspace admission.

The same artifacts passed native encrypted backup export, authenticated
empty-data recovery, negative imports, scoped Capsule switching and invitation
send/accept in both directions, with terminal receipts retained after restart.
Android used isolated local macOS emulators, cold boots without snapshots and a
separate initially empty userdata root. Working Capsule files remained unchanged.
The exact digests, per-platform observations and limits have one owner:
`checklists/release-manual-signoff-log.md`.

Main CI can be run on demand through the existing repository workflow when
GitHub misses a push event; it executes the same checks and runner builder.
The final runtime source main run passed before publication. The host now binds
queued Chat dispatch to captured package/peer authority and the active Capsule;
replacement, removal or lost authorization before worker dispatch fails closed.
Package recovery commands and workspace execution controls follow the installed
contract rather than package-private host interpretation.

Local Analyst redaction, read-only package audit and normal Keychain session
unlock/lock passed on macOS. Cloudflare configuration survived restart and plugin
removal/reinstallation; no token re-entry was needed. The existing AI Runtime
remains the provider owner, under `architecture/capsule-ai-runtime.md`.
Earlier live Cloudflare evidence does not certify new live effects on test3.

Live automatic Moltbook publication/challenge/reply was not qualified because
isolated Capsules had no connected Moltbook account. Jack public live
market-data reached a WASM observation preview on both artifacts; no order or
VPS mutation was performed. Do not promote these observations into a live
publication, trading or VPS teardown claim.

This closes the bounded unsigned test matrix, not full User Lifetime or a
permanently frozen host ABI. Native Intel, a separate macOS user, long-term
migration/lifetime, other Android runtime combinations and the open Jack evidence
remain unconfirmed. Future runtime changes need a new exact-artifact smoke;
package changes within supported contracts must remain independently replaceable.
Do not overwrite attested artifacts or reuse their smoke for changed code.

## Deferred Product Work

- New Chat UX and Moltbook engagement features remain outside the selected
  package-replacement outcome; they do not reopen the Capsule release scope.
- Jack live closure/reentry and continuous VPS evidence remain experimental
  follow-up, not a second v1 development stream.
- Flutter host/plugin convergence, measured 1.x compatibility boundaries,
  crypto-agility, and Trust Layer issue `#7` remain retained architectural
  debt. Select them only when they block the selected product journey or close
  a concrete security/correctness defect.

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
