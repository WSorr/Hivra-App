# Hivra Development Control

Status date: 2026-09-21

## Current State

- Hivra 1.x is the only maintained runtime; Hivra 2.0 remains design-only.
- Current source is protected `main`. Prerelease `v1.0.3-test20` points to
  `7ed28cd`; exact macOS and Android packages built from `d418329` passed
  digest-bound packaged signoff.
- Core, Ledger, FFI, the WASM host, and one Flutter App Shell remain the runtime.
  Chat, Moltbook, and Trading are installed capabilities, but substantial
  orchestration still lives in Flutter.
- Architecture `READY` means canonical ownership is closed, not that the user
  journey is product-complete.
- Chat delivery is cross-platform and restart-safe; conversation UX,
  notifications, and attachments remain incomplete.
- Moltbook Assisted publication is release-proven; Bounded autonomous operation
  is not reference-grade.
- Trading reuses one execution use case, effect journal, order-tracking store,
  and execution queue. `test20`
  proves packaged risk rejection and macOS reconciliation without a duplicate
  effect. Opening the workspace reconciles the current VPS session state first;
  locally retained signed evidence may enrich only that exact server-reported
  session and cannot define operational authority. Capsule-managed VPS
  onboarding requires no Git or terminal work.
  A conflicting external order now pauses the Runner after one retained check
  instead of exhausting the signed session. Current source recomputes fresh
  entry authority from a closed 4h sweep/reclaim with subsequent 5m confirmation;
  micro-only and void entry are removed locally, not deployed. A stale Runner-managed
  order is canceled through the existing effect journal, and a replacement may
  be placed only by the next cycle. Packaged and live VPS evidence for this
  lifecycle remains incomplete.
- Capsule-scoped credential stores remain authoritative. AI unlock is
  process-scoped.
- The Flutter 3.47.4, Dart 3.13.3, Xcode 27, and Swift Package Manager
  baseline is authoritative after packaged macOS and Android smoke, PR `#315`,
  and its successful post-merge repository run.

## Product Recovery Mode

Until the next accepted prerelease:

1. Freeze V2 implementation, new gates/process documents, universal frameworks,
   speculative DTOs, and optional dependencies.
2. Deliver one complete user outcome per pull request. Do not split it into
   named passes or a separate status pull request.
3. Use focused tests while developing; run full repository verification once
   on the final candidate before pull request, then rely on required CI.
4. Refactor only the active journey. Owner and execution-path counts must not
   increase; replacements remove or seal their predecessors.
5. Product acceptance requires no-terminal operation, restart/offline
   continuity, duplicate suppression, useful diagnostics, and packaged
   macOS/Android evidence where supported. Green gates alone are insufficient.
6. A fresh task receives this file plus actual Git state, completes only the
   selected outcome, and does not select the next one.

This is the final status-only reset. Later status updates ship with the product
outcome they attest.

## Active Outcome: Trading 24/7

The approved local strategy replacement is HTF-first: a 4h parent liquidity
zone has priority over conflicting 1h context; 5m confirms entry inside it.
Only sweep/reclaim is selected. Implementation binds parent evidence and
strategy version through the existing decision and authorization paths.
Candidate `ec9496b` was deployed for an explicitly authorized VPS trial, but
its first cycle failed while loading retained pre-upgrade market evidence;
zero cycles and zero effects completed in that new session. Service startup
alone is not autonomous acceptance. The local correction separates historical
chain authentication from current executable-proposal validation and was
deployed as `42bf66c`. One closed-Capsule cycle completed without an
exchange effect; the next failed while exporting completed effects from the
read-only scheduler namespace. The local correction consolidates journal
export in the existing effect-state sandbox without network or exchange
credentials. Its deployment and consecutive closed-Capsule cycles remain
pending. The definition is owned by the trading
strategy specification. Do not deploy a
trend-only filter as a substitute or change the active signed VPS session.

Release is on hold until the autonomous order-to-position journey and the
strategy are product-accepted. Order Check cleanup alone does not close this
outcome. The remaining work is:

1. Complete the lifecycle of an already accepted order when the new-entry
   budget is exhausted. Define and authorize observation, cancellation, and
   protection explicitly; do not silently extend expired authority.
2. Reuse the canonical structural revalidation for existing orders. A blocked
   new-entry proposal alone must not decide whether their zone is invalid.
3. Verify provider acceptance of the locally implemented shared structure/ATR
   stop and reduced notional sizing. Local and remote preparation now apply
   instrument price precision before sizing and risk/reward checks;
   focused regressions pass, but packaged/provider acceptance is pending.
   Opposite-liquidity targets remain authoritative. Verify order, fill,
   protection, and terminal-result continuity.
4. Evaluate the fixed strategy chronologically on real market evidence,
   including fees, funding, slippage, and conservative fill assumptions.
   Keep evaluation data separate from tuning; unavailable inputs must remain
   explicit. Deterministic fixtures alone do not establish trading quality.

Work proceeds through lifecycle completion, strategy reconciliation, and
end-to-end autonomous acceptance using the existing owners. These requirements
do not grant additional trading authority or change current signed sessions.

Local implementation now enforces the placement budget in the existing exact
effect executor using retained attempted placements, including uncertain and
rejected deliveries. Same-operation reconciliation remains available. Focused
tests pass; this has not been deployed. New session authorization explicitly
signs bounded post-budget checks and pending-order cancellation. Existing
sessions retain their original stop policy. Pending-order revalidation now binds
the retained signed placement observation to the exact journal-owned order and
checks its original signed parent/entry against continuous closed 5m candles through
the existing zone owner. A different or blocked new-entry proposal is not a
cancellation reason. Missing proof/history or partial execution retains the
order as revalidation unavailable. Local source now extends 5m coverage back to
the selected or retained parent through one bounded reader; packaged and live
acceptance of this history extension remains pending.
Order-to-position protection continuity and packaged/VPS
acceptance remain unfinished; this is not autonomous product acceptance.

```text
one Capsule -> one configured VPS -> one signed session
            -> at most one external effect per market event
```

The application must configure and provision the VPS and let the user authorize,
start, pause, resume, and inspect the runner without Git or terminal work.
Restart or reconnect must recover the same session and managed-order state
without another provider effect.

Pending orders stay on the existing path:

- `BingxFuturesExecutionQueueService`: pending tracking and TTL;
- the VPS Runner's retained signed cycle: bounded managed-order revalidation
  and cancellation, never a local UI refresh effect;
- the existing tracking store and effect journal: durable state, receipt,
  reconciliation, and duplicate suppression. `Check Open Orders` only reads
  provider state and reconciles local evidence.

A session without signed post-budget maintenance stops after its first exchange
request when its budget is one.
Its provider receipt does not prove the order is still open, and a stopped
Runner does not monitor or manage it. A new signed session cannot automatically
adopt an earlier session's open order; it pauses on that ownership conflict.
Continued VPS trading requires explicit authorization after the existing order
is resolved. No renewal or ownership transfer is inferred.

An order not owned by the signed Runner session is never canceled or replaced.
The Runner records the conflict once, persists an operator hold in its bounded
state, and preserves the same resumable authority for explicit review. A boot
may start the hardened service, but the hold stops it before market or exchange
access until explicit Resume. An ownership-verification failure follows the
same fail-closed path.

A terminal or stopped-out intent cannot resurrect; re-entry requires a fresh
market event and new bounded intent. No new daemon, effect route, Core/Ledger
fact, generic mandate layer, parallel order store, or V2 runtime is authorized.
Change code only for a reproduced defect or missing user-facing step.

Exit evidence is one packaged bounded session that continues with the app
closed and proves pause/resume, restart/reconnect, invalidation, reconciliation,
duplicate suppression, and useful diagnostics on supported platforms.

The release route remains: close the stop/protection and strategy acceptance
gaps above; integrate the coherent change through required PR checks; package
the clean candidate once; perform macOS/Android smoke on those exact bytes;
record digest-bound signoff, then request explicit tag/publication approval.
The local public-data history probe and blocked build-tree smoke do not replace
packaged positive-path evidence. Planned 1D/1W/1M observation is not part of
this release acceptance scope.

## Queued Outcomes

1. Moltbook: bounded observation, AI proposal, publication, comment/reply,
   limits, restart recovery, and Capsule isolation through the existing effect
   lifecycle.
2. Chat: conversation UX, notifications, attachments, offline history, and
   recovery without another delivery or consensus path.

## Authority

1. `product-axis.md`: permanent laws and target runtime shape.
2. `specification.md`: maintained 1.x protocol.
3. Focused contracts: capability semantics.
4. This file: current state and the single selected product outcome.
5. `roadmap.md`: milestone/debt index; Git, pull requests, releases, tests, and
   evidence logs retain history.

## Integration Boundary

`main` changes only through a pull request with required `review-gates`.
Repository validation does not authorize a tag, Release, packaged smoke, VPS
mutation, or external effect.
