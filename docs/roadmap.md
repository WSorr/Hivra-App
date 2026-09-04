# Hivra Milestone Index

This file is not an active backlog, pass diary, or source of current status.
Current state belongs to `development-control.md`. Detailed implementation
history belongs to Git, merged pull requests, release records, tests, and
evidence logs.

## Maintained 1.x Runtime

The following product foundations are implemented and retained:

- deterministic Capsule Core and append-only Ledger projections;
- Capsule birth, recovery, selection, Starter inventory, invitations,
  relationships, pair consensus, and history views;
- NIP-44-only authenticated Nostr transport with durable delivery and
  acknowledged ingress handling;
- sandboxed, signed, digest-bound WASM package installation;
- manifest-bound plugin workspace activation without a direct product bypass;
- one App Shell workspace navigation path with the legacy Settings route
  removed;
- shared external-effect and Capsule AI Runtime boundaries;
- Chat delivery across macOS and Android;
- Chat capability workspace ownership with host-owned Pair Consensus,
  delivery, durable inbox, and acknowledgement boundaries;
- Core-owned Starter-kind and invitation identity projections consumed by the
  Flutter runtime without product-side Ledger payload decoding;
- Moltbook proposal, publication, reply, receipt, and restart lifecycle;
- dedicated Moltbook capability runtime ownership outside the generic plugin
  and Chat module;
- Trading decision, bounded execution, reconciliation, and Remote Runner
  acceptance;
- dedicated Trading capability ownership with one Capsule-local pending-intent
  cycle and no peer-selected or Chat-signal route;
- guarded repository integration and exact-artifact release signoff.

The current public prerelease is `v1.0.3-test18`. The invalid `test17` artifact
evidence remains immutable history and cannot authorize another publication.

## Current Product Convergence

The 1.x host is a modular monolith around a real Core, Ledger, FFI boundary,
and WASM sandbox. Product logic is still compiled into Flutter, while installed
manifest profiles now control which product workspace can be opened.

The remaining migration direction is a thin App Shell over the proven Person
Runtime API. Chat, Moltbook, and Trading capability ownership are complete, and
workspace navigation now has one App Shell owner without a duplicate Settings
entry or plugin-screen runtime composition path.

Every migration must remove or seal the host path it replaces. V2 does not
receive a duplicated runtime.

## Design-Only Hivra 2.0 Evidence

V2-0 ownership inventory and V2-1 contract proofs A-E are complete and remain
design-only:

- Capsule identity and birth;
- Starter inventory and atomic Genesis seed plan;
- Capsule continuity export;
- Capsule recovery;
- Capsule selection and prepared activation.

Their schemas, semantic vectors, and validators remain evidence for a future
implementation decision. No later V2 pass is selected.

## Retained Debt

- Flutter host product logic remains too large and too aware of concrete
  plugins.
- Plugin UI activation is hardcoded in the application shell.
- Several 1.x FFI and screen surfaces remain measured compatibility boundaries
  in `architecture/ownership-registry.v1.json`.
- Crypto-agility migration is specified but no post-quantum 1.x runtime is
  authorized.
- Trust Layer issue `#7` remains a future protocol boundary.

Debt is selected only when it blocks a product journey, closes a concrete
security/correctness defect, or is removed as part of a capability migration.
