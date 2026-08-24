# BingX Futures Trading Drone - Goal Contract v1

Status: Active product contract
Scope: Hivra 1.x Trading Drone and its bounded Remote Runner

## 1. Purpose

This document fixes the product outcome, ownership boundary, and acceptance
criteria for Trading Drone work. It is not a progress journal. Current work is
selected in `docs/development-control.md`; completed implementation history
belongs to Git, tests, and release evidence.

## 2. Three Hivra Laws (Mandatory)

1. Modularity
   - decision, risk, authority, execution, and reconciliation remain in their
     named owners;
   - UI projects state and dispatches intent only.
2. Determinism
   - identical normalized market input and policy produce the same decision
     payload and hash;
   - replay of one exact authorized intent cannot produce a second effect.
3. Dependencies strictly downward
   - UI calls the application module;
   - the module composes existing owners;
   - adapters implement provider effects without acquiring product authority.

One effect has one use case and one owner. Local, remote, manual, and scheduled
entry paths may differ only as adapters into that use case.

## 3. Source-of-Truth Stack (Order of Authority)

1. Capsule protocol invariants: `docs/specification.md`
2. External-effect lifecycle: `docs/architecture/external-effect-lifecycle.md`
3. Plugin host and capability contract: `docs/plugins/plugin_host_api_v1.md`
4. Trading decision and TVH contract:
   `docs/plugins/bingx_futures_trading_drone_spec_v1.md`
5. Runtime parity gate:
   `docs/checklists/trading-drone-spec-runtime-parity.md`
6. Current product selection: `docs/development-control.md`

Historical roadmap or pass text cannot override these owners.

## 4. Product Outcome

An operational Trading Drone must complete one understandable bounded journey:

1. obtain fresh public market data and complete private account-risk data;
2. derive a deterministic `READY` or `BLOCKED` decision;
3. create an exact order intent only from a `READY` decision;
4. verify an active Capsule-scoped mandate before any provider effect;
5. submit at most one provider order for that exact intent;
6. bind the provider receipt to the intent, authority, and operation identity;
7. restore and reconcile the same operation after restart without duplication;
8. expose current, terminal, blocked, and revoked state to the user.

The product is not operational merely because tests pass, one order was
accepted, or a Remote Runner pass was completed.

## 5. Canonical Owners

The local application owner is `TradingDroneModuleService`. It composes the
existing decision, risk, intent, authority, effect, and reconciliation owners.
The screen must not reproduce their semantics.

The canonical local cycle is:

```text
fresh market snapshot
  -> deterministic market decision
  -> transient account-risk snapshot
  -> risk and mandate validation
  -> exact intent
  -> one external-effect operation
  -> provider receipt
  -> durable reconciliation projection
```

The Remote Runner is a replaceable host adapter. It cannot own Capsule truth,
policy, approval, credentials, an order lifecycle, or a second retry path.

## 6. Work Cadence for Drone Changes

For each bounded product change:

1. name the observable outcome and existing owner;
2. change the contract only if behavior or an invariant changes;
3. add focused regression evidence;
4. run repository gates once before integration;
5. run focused manual smoke only when the changed risk requires it;
6. remove or seal the replaced path in the same pass.

Routine fixes do not require a separate status commit or documentation PR.
Open failures remain in the active issue or development board.

## 7. Acceptance Gates (Must Pass Together)

1. `docs/checklists/trading-drone-spec-runtime-parity.md`
2. the Trading Drone section of `docs/checklists/manual-smoke.md`
3. the applicable platform release checklist
4. build-tagged evidence in
   `docs/checklists/trading-drone-evidence-log.md` when preparing a release
5. protected repository gates and clean-checkout verification

Release evidence must cover `READY`, `BLOCKED`, risk rejection, provider
receipt, restart reconciliation, and duplicate suppression on every platform
included in that release.

## 8. Deterministic Decision Boundary

The normative market inputs, normalization, liquidity rules, trend filters,
risk rules, target selection, and output schema live only in
`bingx_futures_trading_drone_spec_v1.md` and the external plugin contract.

Public market evidence may contain only canonical public inputs, the exact
`READY` or `BLOCKED` proposal, policy/package/build commitments, bounded
timestamps, and the authenticated runner identity. It must not contain account
state, credentials, Capsule secrets, mandate material, or effect authority.

A stale, malformed, conflicting, forked, identity-drifted, or incomplete
market proposal fails closed. A blocked proposal cannot retain executable UI
fields or enter intent composition.

## 9. Local Bounded Mandate

Section 5.3.3 of `bingx_futures_trading_drone_spec_v1.md` owns mandate
semantics. A mandate is Capsule-scoped and binds the exact account, symbols,
mode, validity window, notional/risk limits, and maximum effect count.

The mandate:

- grants no withdrawal or transfer capability;
- cannot be inferred from a UI toggle, runner id, key file, or stored API key;
- requires explicit authorization and supports explicit revocation;
- remains independent from Pair Consensus for solo trading;
- is revalidated immediately before every effect.

## 10. Remote Runner Contract

Remote execution reuses the canonical local cycle and external-effect owner.
It does not introduce a second strategy, effect journal, order sender, retry
loop, or reconciliation path.

### 10.1 Verified bundle and identity

- The runner executes an exact verified bundle with pinned package, policy,
  binary, unit, and target commitments.
- A runner anchor authenticates one runner identity for one Capsule; raw ids
  and standalone key files grant no authority.
- Bundle installation, activation, pause, status, and uninstall are explicit
  and exactly reversible.
- Co-hosted services and network configuration are outside runner ownership.

### 10.2 Credential and account boundary

- Exchange credentials remain host-encrypted and bound to the exact Capsule,
  provider account, runner, and mandate.
- Credentials are never placed in the signed mandate, public evidence, logs,
  plugin state, or process arguments.
- Account reads are transient, redacted, freshness-bounded, and effect-free.
- Missing or partially parsed balance, position, contract-rule, or realized-PnL
  data blocks execution.

### 10.3 Prepared activation and scheduling

- Preparing credentials and admitting a session are inert operations.
- Activation is an explicit state transition and creates no exchange effect.
- The scheduler is serial, cadence-bound, cycle-capped, mandate-capped, and
  revocation-aware.
- Persistent service execution invokes the same scheduler owner, uses
  `Restart=no`, and has explicit status, pause, terminal stop, and uninstall.
- Restart never implies catch-up orders or guessed success.

### 10.4 One event, one effect

The canonical exact `intent_hash_hex` is the external-effect operation
identity. Renewed or replaced authority cannot create another operation for
the same exact intent.

Before a provider request, the effect journal atomically retains `pending`.
After a verified provider response it retains terminal evidence. Replay of a
terminal operation returns the retained result without another request. Replay
of unresolved `pending` enters reconciliation only; it cannot rebuild an
intent or issue another order.

Corrupt, conflicting, expired, revoked, mutated, or unexpectedly linked state
fails closed.

## 11. User-Facing Product Boundary

The user must be able to:

- understand why a decision is `READY` or `BLOCKED`;
- see whether displayed zones are current, historical, or non-executable;
- choose and authorize a bounded trading budget;
- configure a Remote Runner without manually composing internal artifacts;
- distinguish local pause from remote revocation and confirmed terminal stop;
- inspect only drone-owned orders and their reconciliation state;
- remove the runner and credentials without orphaned authority or effects.

Raw hashes, internal pass names, journal records, and infrastructure paths
belong in technical details, not the primary workflow.

## 12. Explicit Non-Goals

This contract does not authorize:

- withdrawals, transfers, arbitrary provider endpoints, or discretionary
  commands;
- AI authority over risk, mandate, or execution;
- unbounded scheduling, parallel order effects, or hidden retries;
- a second remote trading implementation;
- Core or Ledger expansion for exchange telemetry;
- strategy-profit claims beyond the documented deterministic rule set;
- Hivra 2.0 runtime work, a release, or a VPS mutation by documentation alone.
