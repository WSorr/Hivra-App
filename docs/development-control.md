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
and the open Jack evidence remain unconfirmed. No permanently frozen host ABI
is claimed. Future runtime changes require a new exact-artifact smoke; package
changes within supported contracts must remain independently replaceable.
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
