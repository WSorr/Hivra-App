# Hivra Development Control

Status date: 2026-09-26

## Current State

- Hivra 1.x is the only maintained runtime; Hivra 2.0 remains design-only.
- Current source is protected `main`. The latest published prerelease is
  `v1.0.3-test21` at `8e5c136`. The trading candidate in PR `#328` is not
  merged or released.
- Core, Ledger, FFI, the WASM host, and one Flutter App Shell remain the runtime.
  Chat, Moltbook, and Trading are installed capabilities, but substantial
  orchestration still lives in Flutter.
- Architecture `READY` means canonical ownership is closed, not that the user
  journey is product-complete.
- Chat delivery is cross-platform and restart-safe; conversation UX,
  notifications, and attachments remain incomplete.
- Moltbook Assisted publication is release-proven. Bounded natural-news code
  is merged, but its automatic publication and reply journey is not yet
  reference-grade on a packaged build.
- Trading has one execution use case, effect journal, order-tracking store,
  execution queue, and Capsule-managed VPS onboarding. A live remote session
  placed one pending order, but provider acceptance did not prove fill,
  protection, terminal result, or strategy quality. The runner was
  paused; signed-session revocation and the order's final provider state were
  not confirmed. Do not report this as a completed autonomous trading journey.
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

Deliver one complete no-terminal journey: configure a VPS, authorize one
bounded strategy, run it with the application closed, and inspect the actual
result after reconnect. The current candidate signs a choice between 4h/15m
and 1h/5m active liquidity zones. Use one fixed mode for product acceptance;
do not add filters or tune both modes while the order lifecycle is incomplete.
The strategy contract lives in the Trading specification, not this status file.

```text
one Capsule -> one configured VPS -> one signed session
            -> at most one external effect per market event
```

The remaining blockers are the lifecycle of an already accepted order after
the new-entry budget is exhausted; exact provider reconciliation through
fill, position protection, and terminal result; and chronological evaluation
of the fixed strategy with fees, funding, slippage, and conservative fills.
An unverified order is not a position or PnL. A blocked new-entry proposal
cannot invalidate an earlier managed order. No session may silently extend
expired authority, adopt an unowned order, or create a duplicate provider
effect. Preserve the existing queue, tracking store, effect journal, signed
runner cycle, and structural revalidation owners; add no parallel route.

Exit evidence is one packaged bounded session that continues while the app is
closed and proves the complete order-to-result path, pause/resume,
restart/reconnect, invalidation, duplicate suppression, and useful diagnostics
on supported platforms. Provider states must be read from exact provider
evidence, not inferred from a UI counter. Then package the clean candidate
once, smoke the exact macOS/Android bytes, record digest-bound signoff, and
request separate tag/publication approval. Until then, release is on hold.

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
