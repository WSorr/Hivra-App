# Trading Empirical Authority Research

Status: parked research, reconciled against `main` at `b7be618` on
2026-08-19.

This record preserves the supplied empirical-authority brief in English and
compares every proposed claim with the implemented Trading vertical. It is not
a specification, active pass, runtime contract, release decision, or authority
grant. `development-control.md` remains the sole current-work board. The
Trading specification and goal contract remain the owners of implemented 1.x
behavior.

## 1. Research Hypothesis

The long-range hypothesis is that a chain resembling

```text
Person
  -> Capsule
  -> durable intent
  -> bounded capability or delegation
  -> replaceable agent
  -> exact effect
  -> receipt and reconciliation
```

may eventually support several Hivra capabilities. The Trading Drone is the
first adversarial specimen; it is not evidence for a universal protocol by
itself. Abstraction must be extracted only after independently useful
verticals require the same lifecycle.

The canonical Trading cycle is a solo capability. Relationship, Starter,
Circle, Trust Layer, and pair-consensus semantics are not part of its authority
model. A separate foreground pair-scoped intent-routing action retains its
existing consensus guard, but it is not the solo cycle and does not justify a
social-trust dependency for the VPS. No social trust primitive grants solo
trading authority.

## 2. Current Vertical At `b7be618`

| Concern | Implemented owner and fact | Explicit boundary |
| --- | --- | --- |
| Trading product composition | `TradingDroneScreen` delegates the canonical solo cycle to existing strategy, sizing, WASM intent, risk, tracking, and exchange-execution owners. | UI is not an authority or effect owner. |
| Plugin semantics | The external `hivra-plugins` repository owns the deterministic WASM trading evaluator; Hivra-App owns host composition and provider access. | No plugin ABI change or mirrored evaluator is proposed here. |
| Local authority | `BingxFuturesTradingMandate` binds Capsule, account, symbol, mode, validity, notional, risk, and effect limits. The Capsule-scoped tracking store owns mandate and claim state. | This is Trading operational state, not Core, Ledger, or a generic agent authorization. |
| Local effect | `BingxFuturesExchangeExecutionUseCaseService` is the sole implemented exchange-effect owner. | The VPS has no POST/DELETE, order, cancellation, or remote effect path. |
| Local freshness and idempotency | Stable liquidity-event identity, fresh closed-bar revalidation, and an atomic event claim enforce one event to at most one active effect across retry and restart. | This does not authorize a remote scheduler. |
| Local recovery | Managed-order reconciliation adopts only locally persisted, account-bound drone ownership evidence and never recreates missing orders or adopts unrelated manual orders. | The VPS account-read path performs no reconciliation. |
| Local receipts | Decision/execution envelopes, queue outcomes, managed-order provenance, and execution-command receipts already exist under their separate owners. | There is no remote trading-effect receipt because no remote trading effect exists. |
| Public VPS runner | A bounded public-market shadow runner, authenticated stream, portable signed anchor, exact bundle lifecycle, and resource-bounded systemd unit are implemented. | Public observation grants no Capsule, account, mandate, AI, or effect authority. |
| Remote mandate admission | A Capsule root signature binds the complete Trading mandate and exact initialized runner. Canonical verification, downgrade rejection, exact replay, and mutation/conflict rejection are implemented. | Replacement, rotation, signed revocation delivery, scheduling, and effects remain unselected. |
| Remote credential preparation | The existing host lifecycle accepts one account-bound dedicated subaccount credential through hidden input and retains only host-encrypted prepared state. | The persistent public runner cannot load the exchange credential. External permissions and IP restriction are operator/provider controls, not facts proven by Git. |
| Remote authenticated access | Pass U permits exactly one collected transient `balance`, `positions`, and `open_orders` GET sequence, with a crash-safe `pending/completed` operation journal and redacted retained evidence. | No account payload, durable account projection, repeated read lease, risk decision, or exchange effect is authorized. |
| AI or strategy on VPS | None is authorized. The public shadow runner evaluates deterministic public-market evidence only. | No remote `TradeProposal`, inference provider, AI credential, or proposal-to-effect route exists. |

Pass U evidence at `5abecf6` and its status checkpoint at `b7be618` proved the
existing remote primitives on the real VPS: exact runner-bound admission,
encrypted prepared credential, one single-use authenticated read, exact
completed replay without another provider request, expired unused/pending
rejection, completed inspection after expiry, mutation rejection, and exact
cleanup without disturbing unrelated co-hosted workloads or the pre-recorded
listener baseline. These are completed facts, not proposed work.

## 3. Minimal Experiment From The Brief

The brief proposed a Capsule-authorized period, a portable artifact, an
offline Capsule, a continuously running VPS agent, untrusted proposals,
deterministic enforcement, and bounded exchange effects.

Only the following subset exists today:

```text
Capsule-owned bounded Trading mandate
  -> Capsule-signed runner-bound admission
  -> host-encrypted prepared credential
  -> exact single-use account-read authority
  -> transient provider GETs
  -> retained redacted evidence
```

The local product separately proves bounded order authority and effect
idempotency, but those local primitives have not been composed into a remote
execution vertical. A future empirical experiment would have to prove that
composition without creating another mandate, risk, effect, receipt, or
reconciliation owner. This research does not select that experiment.

The example constraints from the brief reconcile as follows:

- one symbol, test/live mode, validity up to 24 hours, maximum order notional,
  deterministic risk policy, maximum concurrent positions, and maximum effect
  count already exist in the Trading mandate;
- current local authority covers the canonical limit/zone lifecycle, not a
  generic `open/close` action vocabulary;
- cumulative exposure over an offline remote period is not a proven delegated
  counter;
- withdrawal and transfer are outside every implemented Trading endpoint and
  remain forbidden rather than represented as permitted actions;
- paper or simulated remote execution has not been selected;
- provider-side withdrawal disablement, least privilege, dedicated subaccount,
  and IP allowlisting are desirable independent damage limits, but only the
  prepared dedicated credential workflow has repository evidence. Provider
  configuration must be verified separately before any effect experiment.

## 4. Threat-Scenario Reconciliation

For this comparison, the Capsule root signer, canonical verifiers, the existing
local mandate/risk/effect owners, and the exact host lifecycle are trusted only
within their implemented contracts. Proposal/model output, wire bytes, replay,
provider responses, clocks, restarts, and reports are untrusted inputs. Full
VPS compromise is outside the protection offered by host encryption and must
be bounded independently at the provider account. Each evidence cell below
names the implemented mechanism that currently preserves the relevant
invariant; an absent mechanism remains an unselected question.

| # | Scenario from the brief | Evidence at `b7be618` | Remaining unselected question |
| --- | --- | --- | --- |
| 1 | Agent proposes an allowed trade. | Local deterministic strategy, risk, mandate, event claim, queue, and exchange owner cover the local path. | No VPS proposal or remote effect path exists. |
| 2 | Agent proposes another market. | Local mandate and remote admission bind one exact symbol; mutation fails closed. | No remote proposal parser has been tested. |
| 3 | Agent exceeds maximum notional. | The local exchange owner checks the mandate notional ceiling before effect. | The VPS cannot request an effect. |
| 4 | Agent exceeds cumulative exposure. | Local risk inputs include current positions and bounded concurrent positions. | Period-wide delegated cumulative exposure and crash-safe remote accounting are not proven. |
| 5 | Agent exceeds allowed trade count. | The local mandate has an atomic maximum-effect budget. | No remote effect counter or lease exists. |
| 6 | Agent attempts withdrawal or transfer. | Those endpoints are absent and forbidden artifact markers are rejected. | A future remote effect allowlist would still need negative provider-boundary proof. |
| 7 | Authorization expires. | Local effects fail closed; Pass U rejects expired unused authority and leaves expired pending unresolved while retaining completed evidence. | Long-running effect eligibility and in-flight expiry semantics are unselected. |
| 8 | Old authority is replayed after replacement. | Exact replay is idempotent and changed retained authority conflicts; implicit replacement is forbidden. | Rotation, supersession, and signed revocation delivery are unselected. |
| 9 | One proposal is submitted twice. | Local stable event identity and atomic claim enforce one-event/one-effect. Pass U consumes one read operation. | No remote proposal identity exists. |
| 10 | VPS restarts after losing volatile counters. | Runner identity, shadow evidence, admission, encrypted credential, and Pass U operation state are durable and fail closed. | Remote trading budgets and effect recovery do not exist. |
| 11 | Capsule and VPS clocks differ. | Canonical issued/expiry timestamps and current eligibility checks exist. | An accepted clock-skew window and trusted-time strategy are unselected. |
| 12 | VPS credential is compromised. | The credential is host-encrypted, hidden-input only, account-bound, absent from the persistent runner, and removed by exact uninstall. | Host compromise can still reach the provider credential; provider permission/IP controls and rotation response need empirical proof. |
| 13 | AI or runtime is fully compromised. | No AI runs in the remote authority path. Local proposals cannot bypass deterministic mandate/risk/effect owners. | A hostile remote proposal producer has not been connected or attacked. |
| 14 | VPS expands constraints itself. | The Capsule signature covers the complete mandate, runner, exact read operation, ordered scope, and use count; mutation fails closed. | No signed remote effect operation exists. |
| 15 | Capsule is offline during execution. | Pass U proved one pre-authorized read while no Capsule interaction was required. | Continuous observation, revocation delivery, and remote effects while offline are unselected. |
| 16 | Provider accepts an order and VPS fails before recording it. | Local order execution and read-only reconciliation distinguish terminal from unresolved state. Pass U commits `pending` before GETs and never guesses success. | No remote order journal, receipt, or reconciliation exists. |
| 17 | WebSocket and REST disagree. | Local managed-order reconciliation uses exact provider reads and does not treat a missing order as permission to recreate it. | A cross-channel conflict policy for the remote host is unselected. |
| 18 | VPS returns a false or incomplete report. | Public shadow evidence is runner-signed and continuity-checkable; Pass U retains a bounded canonical redacted verdict. | Account-read evidence is not a provider attestation or complete account transcript, and no independently verifiable remote effect receipt exists. |

## 5. Security Property Status

The brief's target property remains useful:

```text
ExecutedEffects(t) is a subset of EffectiveCapability(t)
Capability(delegate) is a subset of Authority(issuer)
```

For the remote host, the first property is currently true only because remote
exchange effects are structurally absent. Pass U is stronger than a paper
claim for authenticated reads, but it is not evidence for remote trading.

For local Trading, the implemented mandate, deterministic risk owner, atomic
event claim, queue, provider result check, and reconciliation regressions are
evidence toward the property. They do not establish a domain-independent
delegation theorem. Any future remote effect experiment must demonstrate that
the VPS cannot create, enlarge, renew, or reinterpret Capsule authority.

## 6. Adversarial Evidence Status

The repository already uses negative mutation and restart tests for malformed
artifacts, signature and runner/account/scope mismatch, expiry, replay,
conflicting journals, stale events, duplicate claims, policy escalation,
Capsule switching, missing orders, and manual-order isolation. Independent
Dart/Python reconstruction covers the remote commitment boundary.

Broad property-based or fuzz generation over proposals, amounts, markets,
timestamps, ordering, restart sequences, and constraint combinations is not an
implemented remote-effect gate. It remains an experiment question. Test count
alone must not substitute for proving that forbidden input cannot reach a
provider effect boundary.

## 7. Proposal, Decision, Effect, And Receipt

The terms must remain distinct:

| Stage | Current Trading fact |
| --- | --- |
| Proposal | Local WASM intent and deterministic strategy outputs exist; remote AI proposals do not. |
| Authorization decision | The local exchange owner enforces the active Trading mandate and risk policy; Pass U enforces exact read eligibility. |
| Effect request | Local canonical exchange order requests exist under one execution owner; no remote request exists. |
| External result | Local provider results are checked explicitly; Pass U records only three redacted read booleans. |
| Receipt | Local execution-command receipts and observability envelopes exist; no remote effect receipt exists. |
| Reconciliation | Local managed-order reconciliation is read-only and ownership-bound; no remote order reconciliation exists. |

WebSocket state is not sufficient proof of an order effect. A future remote
experiment would need exact REST/history reconciliation and retained unresolved
states without inferring success. This requirement remains unselected.

## 8. Independent Verification

Current primitives preserve a partial verification path:

- the Capsule signature identifies the issuing Capsule root and binds the
  complete Trading mandate, account commitment, runner, operation, scope, and
  use limit;
- the public shadow runner signs portable evidence and exposes continuity
  anchors;
- canonical encodings and stable hashes permit independent reconstruction;
- the Pass U operation journal retains exact redacted completed evidence.

They do not prove that a trade happened, that BingX produced a particular
state, or that an account-read verdict is a provider-signed attestation. Future
third-party verification, ordering, timestamp anchoring, and dispute evidence
remain separate research questions. Blockchain is not required or selected.

## 9. Empirical Questions And Current Answers

| Question preserved from the brief | Current answer |
| --- | --- |
| What is the minimum portable VPS artifact? | For one read, the implemented minimum is one canonical Capsule-signed admission containing the complete Trading mandate, exact runner, exact read operation/scope, and `max_uses=1`. This does not answer remote effects. |
| Which constraints belong inside it? | Capsule/account/symbol/mode/time/notional/risk/effect bounds plus exact runner and operation scope are currently signed. Remote cumulative exposure and effect-specific request fields remain unresolved. |
| What does the Capsule sign? | Today it signs the domain-separated remote admission commitment, not an AI proposal, provider payload, or universal warrant. |
| What can the VPS verify while the Capsule is offline? | Canonical shape, commitment, Capsule signature, runner/account/mandate/scope binding, operation state, and current eligibility for an unused read. |
| How is replay prevented? | Exact replay is idempotent; mutation conflicts; one operation journal transitions unused to `pending` to `completed`; completed replay returns retained evidence without provider access. |
| How are cumulative limits enforced? | Local Trading owns effect and risk limits. No durable remote cumulative-effect accounting exists. |
| How is revocation delivered when the Capsule returns? | Local Emergency Pause persists revocation. Remote signed revocation and rotation delivery are unselected. |
| What happens if the Capsule remains offline until expiry? | An unused read expires and cannot call the provider; pending remains unresolved; completed evidence remains inspectable. Continuous remote activity is not authorized. |
| How do receipts bind to authority? | Pass U evidence binds operation, runner, account, and mandate commitments. A remote exchange-effect receipt binding does not exist. |
| What enables later independent verification? | Canonical commitments, Capsule signatures, runner-signed public evidence, stable operation ids, and retained evidence are useful primitives; provider proof and trusted ordering remain unresolved. |
| Which parts are Trading-specific? | Symbols, test/live mode, liquidity events, notional and risk policy, positions, effect budgets, BingX account binding, endpoints, order ownership, and reconciliation semantics. |
| Which parts may be domain-independent? | Bounded canonical input, issuer/delegate binding, exact scope, expiry, stable operation identity, pending/completed journaling, fail-closed replay, redacted evidence, and reconciliation discipline are candidates only. |

## 10. Generalization Gate

Do not create `Capability`, `Warrant`, `Receipt`, or a general mandate runtime
from this record. Reconsider consolidation only after at least one independent
capability, such as Moltbook, backup, remote engineering, or Capsule-to-Capsule
delegated effects, naturally requires the same lifecycle without importing
Trading semantics.

If a common layer repeatedly needs symbols, positions, notional, liquidity
events, exchange accounts, or order reconciliation, it belongs in Trading. A
shared lifecycle may be proposed only with evidence of multiple owners being
removed or merged, not by adding a new parallel owner.

## 11. Explicitly Unselected Work

This research does not select or authorize:

- a Universal Warrant Protocol or global capability ontology;
- a generic capability, delegation, receipt, or multi-agent DTO family;
- a PKI, Trust Layer integration, relationship flow, Starter, Circle, or pair
  consensus dependency for solo Trading;
- blockchain anchoring or mandatory global settlement;
- a generic multi-agent orchestration framework;
- Staking Drone or another product vertical;
- new Core primitives, Ledger facts, FFI, plugin ABI, UI, or service owners;
- remote AI, proposals, schedules, leases, persistent account reads, trading
  effects, cancellation, or reconciliation;
- VPS deployment or configuration changes;
- a release, tag, or 2.0 implementation pass.

## 12. Revisit Trigger

Revisit this research only after a concrete product decision selects a bounded
remote Trading experiment or a second independent capability demonstrates the
same authority lifecycle. Before implementation, produce an updated vertical
map, threat model, reused-owner proof, exact experiment boundary, negative
vectors, and a list of abstractions deliberately not added.

The governing method remains: think far, prove close, and derive abstractions
from working systems rather than fitting systems to a preferred abstraction.
