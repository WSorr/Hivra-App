# External Agent Runtime Pattern Audit

Status: research record only. This document does not authorize implementation,
deployment, credentials, background execution, or external effects.

Snapshot date: 2026-08-18

## 1. Purpose

This record preserves reusable product and runtime patterns observed across
two classes of external personal-agent implementations without identifying
those implementations or importing their ownership models into Hivra:

- task-, approval-, and standing-operation-oriented runtimes;
- context-, memory-, skill-, episode-, and artifact-oriented runtimes.

The comparison is governed by `product-axis.md` and `specification.md`.
External popularity or convenience is not evidence that a pattern fits Hivra.

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

## 8. Forward Scenario Model

This section is a scenario model, not a product claim or forecast. Current
signals support increasing agent interoperability, hybrid edge/cloud
inference, outcome-oriented financial execution, cheaper independent
verification, and explicit software-agent authorization. They do not prove
that one protocol, chain, model, agent framework, or asset class will dominate.

The common architecture requirement across plausible outcomes is:

```text
person
  -> user-owned persistent principal (Capsule)
  -> durable intent
  -> deterministic policy and bounded mandate
  -> replaceable intelligence provider
  -> replaceable executor or solver
  -> external effect
  -> evidence and receipt
  -> reconciliation, dispute, or compensation
  -> Capsule-owned state
```

`Personal Digital Root` may be used as an explanatory description of the
Capsule's continuity and authority property. It is not a new domain entity, a
replacement for Person-First Runtime, or authorization for another identity,
storage, DTO, or execution owner.

### 8.1 Scenarios the architecture must survive

1. **Cloud concentration:** most reasoning and execution run in large external
   services. Hivra still owns disclosure, intent, mandate, receipt, and
   revocation boundaries.
2. **Personal edge intelligence:** local accelerators handle private context,
   filtering, classification, and lightweight planning while expensive work is
   routed outward. Hivra still treats every model as a replaceable provider.
3. **Regulated machine economy:** agents receive formal identities and service
   accounts. Hivra still binds authority to the person's Capsule and grants
   only bounded, attributable delegation.

The architecture must not depend on selecting one of these scenarios.

### 8.2 Intent is not an effect

A durable intent describes an owned objective and constraints across time. It
is not an API request, provider payload, order, transaction, or permission.
Planning may choose or replace executors, but trusted code must compile each
eligible action into an exact bounded mandate and the existing effect
lifecycle must reconcile its result.

The minimal future authority chain is:

```text
durable intent
  -> proposal
  -> deterministic eligibility decision
  -> bounded mandate
  -> exact effect operation
  -> provider evidence
  -> verified receipt or unresolved observation
  -> reconciliation
```

No AI output may skip or own an arrow in this chain.

### 8.3 State and settlement tiers

Hivra must not assume that all activity belongs in one consensus domain:

- local state records person-owned truth and private operational state under
  their existing separate owners;
- pair-scoped evidence supports exact bilateral interaction where its
  invariants are sufficient;
- multi-party coordination requires its own ordering, quorum, and conflict
  contract rather than being inferred from pair consensus;
- global settlement or anchoring is an optional effect provider used only when
  public ordering, scarce ownership, clearing, or dispute evidence requires it.

No chain, solver, broker, bank, or synthetic-asset system becomes Core truth.

### 8.4 Financial abstraction boundary

The runtime may eventually express objectives in purchasing power, liquidity,
risk, duration, and constraints instead of a particular asset or settlement
rail. It must not hide collateral, oracle, counterparty, jurisdiction,
liquidation, custody, or settlement risk. Synthetic instruments are provider
capabilities with explicit evidence and failure modes, not a new Hivra asset
ontology.

### 8.5 Product consequence

Future user surfaces should center goals, active mandates, resource/risk
limits, unresolved obligations, effects, and receipts. A list of agent
personalities or provider-specific tasks is secondary diagnostic information.
The Operations Center described above is the likely composition surface, but
it remains a projection over existing owners until a separate bounded product
unit proves otherwise.
