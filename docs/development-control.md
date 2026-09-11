# Hivra Development Control

Status date: 2026-09-11

## Current State

- Maintained runtime: Hivra 1.x.
- Current runtime source checkpoint is the protected `main` HEAD; Git and the
  required repository gate retain the exact integration identity.
- Published prerelease: `v1.0.3-test19` at `dabeaa7`; its published macOS and
  Android digests match the retained artifact rows. A documentation audit
  invalidated the Trading Smoke field for both platforms because the retained
  evidence proves a paused scan, not the complete Trading acceptance contract.
- The runtime is a modular monolith around the Rust Core, append-only Ledger,
  FFI boundary, WASM sandbox, and one Flutter App Shell. Installed manifest
  profiles select Chat, Moltbook, and Trading workspaces without a direct
  Settings or product-route bypass.
- Chat has cross-platform delivery evidence and remains guarded by the existing
  pair-consensus, transport, durable inbox, and acknowledgement owners.
- Moltbook owns observation, AI proposal, exact publication, receipt,
  reconciliation, and restart handling. Assisted publication is release-proven;
  Bounded mode remains non-reference-grade under its lifecycle contract.
- Trading supports the same canonical bounded cycle locally or through the
  Remote Runner. Ranked market entries are observations only; exact order
  fields appear only after fresh market validation. The local runner starts
  directly from one selected market and obtains replacement bounded authority
  in the same action when selection changes; signal scan remains optional.
  Local and remote sessions are mutually exclusive and reuse the existing
  execution, effect, reconciliation, credential, and mandate owners. Remote
  authorization now fits the selected notional to the current risk budget
  before signing; packaged macOS evidence produced exactly one bounded live
  VPS effect while the application was closed, then stopped at its effect cap.
- Trading Remote Runner acceptance at `b88a886` remains historical evidence for
  that source state. Current `main` includes later Trading lifecycle changes and
  is not release-qualified by the `test19` Trading evidence. Exact
  managed-position restart reconciliation is proven on macOS; Android evidence
  for that path remains open.
- Capsule-scoped secret owners retain credentials. AI unlock remains
  process-scoped. Legacy split BingX credentials migrate once and are removed.
- Hivra 2.0 remains design-only. No 2.0 runtime or UI implementation is
  authorized.

## Product Direction

The maintained convergence target is:

```text
Core + Ledger
  -> Person Runtime API / Plugin Host
  -> installed Chat, Moltbook, and Trading capabilities
  -> thin App Shell
```

The current product still compiles substantial capability logic into Flutter.
Migration work must follow an active product journey, preserve the three laws,
reuse proven implementation, and remove or seal the host path it replaces.
V2 must not become a second runtime.

## Open Product Evidence

1. Qualify the next release source with complete packaged Trading evidence on
   macOS and Android: deterministic ready/blocked paths, provider receipt,
   restart reconciliation, and duplicate suppression.
2. Complete Moltbook Bounded-mode restart, deduplication, limit, Capsule-scope,
   and macOS/Android evidence required by its lifecycle contract.
3. Reduce hardcoded capability activation and Flutter compatibility surfaces
   only while migrating a proven product capability into the Person Runtime
   boundary; no standalone architecture cleanup is selected.

No plugin ABI change, universal agent runtime, new Core fact, V2 runtime or UI,
release, VPS mutation, or live financial effect is authorized by this status.

## Authority

1. `product-axis.md` owns the three permanent laws and target runtime shape.
2. `specification.md` owns the maintained 1.x protocol.
3. Focused architecture and plugin contracts own capability semantics.
4. This file owns only current state and the next decision boundary.
5. `roadmap.md` owns the milestone index and retained debt; Git, pull requests,
   releases, tests, and evidence logs retain detailed history.

## Integration Boundary

`main` changes only through a pull request with the required `review-gates`
check. Repository validation and product release remain separate. No tag,
Release, packaged smoke, VPS change, or external effect is implied by a green
repository gate.
