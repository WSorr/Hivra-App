# External Agent Runtime Pattern Audit

Status: research record only. This document does not authorize implementation,
deployment, credentials, background execution, or external effects.

Snapshot date: 2026-08-18

## 1. Purpose

This record preserves reusable product and runtime patterns observed in two
external personal-agent projects without importing their ownership models into
Hivra:

- OpenClaw at commit
  [`d92ebbaf725481a33f7f3cfa2e3a8b274fa948e4`](https://github.com/openclaw/openclaw/commit/d92ebbaf725481a33f7f3cfa2e3a8b274fa948e4)
  (MIT);
- Aithy at commit
  [`672ca3b151eb60a4f13067267d85527c196ab566`](https://github.com/dosco/aithy/commit/672ca3b151eb60a4f13067267d85527c196ab566)
  (Apache-2.0).

The comparison is governed by `product-axis.md`, `specification.md`, and
`architecture-execution-discipline.md`. External popularity or convenience is
not evidence that a pattern fits Hivra.

## 2. Existing Hivra Advantages

The following mechanisms already have canonical owners and must not be
reimplemented under new agent terminology:

- serial bounded scheduling with no overlapping cycle;
- stable operation identifiers and one-event-one-effect semantics;
- durable receipts, restart recovery, and reconciliation;
- provider abstraction and isolated WASM drone execution;
- separation of AI proposal, deterministic authority, approval, effect, and
  receipt;
- signed and identity-bound Remote Runner evidence.

## 3. Patterns Worth Adopting

### 3.1 Operations Center

Provide one human-readable projection of work already owned by the existing
Chat, Moltbook, Trading, transport-delivery, and external-effect lifecycles.
Useful fields are operation, Capsule, drone, state, next action, last evidence,
and terminal or unresolved reason.

This is a read-only composition surface. It must not own another queue,
scheduler, retry policy, DTO family, or effect lifecycle.

### 3.2 Unified Approval Surface

Present proposals from different drones through one approval grammar:

- allow this exact effect once;
- deny this exact effect;
- create a separately reviewed, bounded, versioned mandate.

A broad `allow always` control is not compatible with Hivra authority. A
mandate must remain capability-, subject-, scope-, budget-, expiry-, and
revocation-bound.

### 3.3 Capsule AI Context Model

Private AI/drone state should have explicit semantic classes rather than an
undifferentiated prompt history:

- **Knowledge**: bounded source material;
- **Memory**: retained observations and summaries;
- **Skills**: reviewed capabilities and procedures;
- **Episodes**: operation history and outcomes;
- **Artifacts**: explicit generated outputs.

These classes are not Core truth and do not enter the Ledger merely because an
AI runtime used them. Every outbound evidence pack must expose selected
sources, provenance, size limits, and disclosure preview before inference.

### 3.4 Runtime Health and Usage Advice

Extend the existing Capsule Doctor/Analyst tooling with runtime state,
unresolved operations, provider health, bounded resource use, and suggested
operator actions. Advice remains observational and cannot change policy,
authority, credentials, or effect state.

### 3.5 Explicit Artifacts

Generated files and reports should be first-class private outputs bound to
Capsule ID, plugin ID, operation ID, provenance, and content hash. Export or
publication remains a separate explicit effect.

## 4. Patterns Rejected or Constrained

- No unrestricted host shell, `yolo` mode, or implicit full-filesystem access.
- No Markdown, SQLite, vector store, or model memory as a second Core truth.
- No agent-created or agent-promoted skill without package review, preflight,
  capability policy, and explicit installation.
- No AI memory or inference result may mutate authority or policy.
- No separate mesh trust graph. Remote nodes use the Hivra Trust Layer and
  explicit capabilities.
- No `lost` terminal conclusion derived only from timeout. Unconfirmed effects
  remain subject to durable reconciliation.
- No fixed convenience retention period may delete evidence needed to resolve
  a critical external effect.

## 5. Product Sequence

This research suggests the following order after an explicit product decision:

1. Operations Center as a projection over current lifecycle owners.
2. Unified approval surface over current proposal/effect contracts.
3. Capsule AI context and artifact contracts in private drone state.
4. Runtime health and usage advice inside existing Doctor/Analyst ownership.

None of these steps is selected automatically. Each requires one named owner,
a capability-closure proof, a removed or sealed ambiguity, and regression
evidence before implementation.

## 6. Remote Runner Readiness Fact

An operator has reported that a dedicated BingX futures subaccount now exists
for later Remote Runner validation. This is external preparation only:

- no account identifier, API key, secret, host path, or server credential is
  recorded here;
- the report does not prove the exchange permission set or key restrictions;
- it does not authorize credential transfer, account reads, service
  activation, scheduling, orders, cancellation, or reconciliation;
- the active Pass T gates remain authoritative.

Before any later account or effect pass, evidence must independently verify at
least futures-only API rights, withdrawals disabled, IP restriction where the
provider supports it, isolated balance/risk limits, explicit expiry or
revocation, and an operator-tested kill path.

## 7. Revisit Trigger

Re-run this audit only when a concrete Hivra product finding requires one of
the patterns above or when an external source has materially changed. Do not
poll competitor roadmaps into Hivra's active development board.
