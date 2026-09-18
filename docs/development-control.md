# Hivra Development Control

Status date: 2026-09-18

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
  execution queue, revalidation service, and replacement service. `test20`
  proves packaged risk rejection and macOS reconciliation without a duplicate
  effect. Opening the workspace restores the verified retained VPS mandate and
  projects its exact market, mode, and effect budget before remote secrets are
  unlocked. Capsule-managed VPS onboarding requires no Git or terminal work.
  A conflicting external order now pauses the Runner after one retained check
  instead of exhausting the signed session. Current source recomputes fresh
  entry authority from confirmed 5m sweep/reclaim or untouched liquidity-void
  zones; 4h/1d/1w pivots are targets and context only. A stale Runner-managed
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
- `BingxFuturesOrderRevalidationService`: keep or cancel from current market;
- `BingxFuturesOrderReplacementService`: fresh same-side replacement through
  the existing execution use case;
- existing tracking store and effect journal: durable state, receipt,
  reconciliation, and duplicate suppression.

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
