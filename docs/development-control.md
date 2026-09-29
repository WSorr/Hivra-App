# Hivra Development Control

Status date: 2026-09-29

## Current State

- Hivra 1.x is the only maintained runtime; Hivra 2.0 remains design-only.
- Current source is protected `main`. The latest published prerelease is
  `v1.0.3-test21` at `8e5c136`.
- Core, Ledger, FFI, the WASM host, and one Flutter App Shell remain the
  runtime.
- Chat and Moltbook are the maintained installed product capabilities.
- The former Trading capability, its strategy and sizing implementations,
  provider effect path, embedded runner, remote-runner tooling, and active
  release obligations are being removed as one bounded retirement outcome.
  No replacement Trading strategy or runtime is selected.
- Chat delivery is cross-platform and restart-safe; conversation UX,
  notifications, and attachments remain incomplete.
- Moltbook Assisted publication is release-proven. Bounded natural-news code
  is merged, but automatic publication and reply are not yet reference-grade
  on a packaged build.
- Capsule-scoped credential stores remain authoritative. AI unlock is
  process-scoped.
- The Flutter 3.47.4, Dart 3.13.3, Xcode 27, and Swift Package Manager
  baseline remains authoritative.

## Active Outcome: Retire Trading 1.x

Remove the obsolete Trading implementation without changing Core, Ledger,
Chat, Moltbook, Capsule continuity, or the generic WASM host.

The retirement has one direction:

```text
old strategy/order calculation/provider execution/runner paths
  -> removed
  -> no fallback, compatibility route, or replacement strategy
```

Exit evidence:

1. no Trading owner, screen, service, DTO, effect route, runner asset, release
   gate, or active capability contract remains in Hivra-App;
2. legacy transport payloads cannot recreate Trading state or effects;
3. Chat, Moltbook, Capsule switching, persistence, and plugin installation keep
   their existing tests and runtime paths;
4. ownership evidence is regenerated from the reduced registry;
5. the full Flutter, Rust, architecture, security, documentation, and release
   gates pass;
6. packaged smoke confirms the supported macOS and Android journeys before any
   later release decision.

Historical Git, pull-request, and release evidence remains immutable history.
It does not authorize restoration of the retired implementation.

## Product Discipline

1. Freeze V2 implementation, new process documents, universal frameworks,
   speculative DTOs, and optional dependencies.
2. Deliver one complete user outcome per pull request.
3. Use focused tests while developing; run full repository verification once
   on the final candidate before pull request, then rely on required CI.
4. Refactor only the active journey. Owner and execution-path counts must not
   increase; replacements remove or seal their predecessors.
5. Green gates are necessary evidence, not product acceptance.
6. Do not select a replacement Trading strategy, remote execution pass, or
   release automatically after this retirement.

## Queued Product Outcomes

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
5. `roadmap.md`: milestone/debt index; Git, pull requests, releases, tests,
   and evidence logs retain history.

## Integration Boundary

`main` changes only through a pull request with required `review-gates`.
Repository validation does not authorize a tag, Release, packaged smoke, VPS
mutation, or external effect.
