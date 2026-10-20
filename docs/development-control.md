# Hivra Development Control

Status date: 2026-10-20

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
- The latest published prerelease is `v1.0.4-test1`, built from `bfe6945`.
  No `v1.0.4-test2` release is published; any new candidate requires the
  current source commit and matching canonical runner.
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

Add Cloudflare Workers AI to the existing Capsule AI Runtime provider selection
and let Moltbook news, replies and challenge proposals use that selected session.
Reuse the credential store, provider broker, scheduler, disclosure contracts and
Chat Completions adapter. No new plugin-private state, effect lane, provider
fallback or authority is introduced. The canonical boundary is
`architecture/capsule-ai-runtime.md`.

Acceptance covers pinned credential destinations, provider-isolated settings
across restart/lock/clear, request/response evidence, bounded failures without
secret echoes or quota retries, and Moltbook proposal paths without publication.
The user has prepared a Cloudflare account and a Workers-AI-only API token.
Next acceptance is an exact packaged UI smoke with secure configuration,
normal Keychain unlock and a bounded live response without publication or
trading. Live provider acceptance remains unconfirmed until that smoke passes.

The prior Apple Silicon + Android Capsule-safety candidate remains bound to
source `f6099fa` and its exact artifact digests in PR #377. Its signoff does not
certify this new provider. Publication is paused at the user's request; no tag
or release was created. Full User Lifetime and native Intel remain unconfirmed.
Do not overwrite the attested artifacts or reuse their smoke for changed code.

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
