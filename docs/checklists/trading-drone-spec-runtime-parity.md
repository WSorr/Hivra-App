# Trading Drone Spec/Runtime Parity Checklist (BingX Futures v1)

Use this checklist after any trading-drone logic change and before release packaging.

## Current Runtime Status (2026-06-12)

Legend:
- `DONE`: implemented and wired in live runtime path
- `PARTIAL`: implemented module exists, but not fully consumed by live entry path
- `TODO`: not implemented in required runtime path yet

| Area | Status | Runtime Evidence | Remaining Debt |
|---|---|---|---|
| Snapshot normalization + canonical hash | DONE | `flutter/lib/services/bingx_futures_market_snapshot_service.dart` | Keep regression green |
| Live exchange data surface for full TVH snapshot | DONE | `BingxFuturesExchangeService` exposes `getPublicPrice`, `getPublicKlines`, `getPublicDepth`, `getPublicTrades`, `getPublicPremiumIndex`, `getPublicOpenInterest` | Keep parsing tests green and verify exchange payload variants |
| Feature extractor (EMA/ATR/liquidity/whale) | DONE | `flutter/lib/services/bingx_futures_feature_extractor_service.dart` | Keep regression green |
| TVH rule engine (`LONG/SHORT/NO_SIGNAL/BLOCKED`) | DONE | `flutter/lib/services/bingx_futures_tvh_rule_engine_service.dart` | Keep regression green |
| Deterministic replay harness | DONE | `flutter/lib/services/bingx_futures_deterministic_replay_harness_service.dart` | Keep fixture parity checks |
| Live entry uses TVH decision as primary gate | DONE | `TradingDroneScreen` and `WasmPluginsScreen` resolve limit intents via `BingxFuturesLiveDecisionService` before host call | Keep live-decision replay checks green |
| Side/zone provenance linked to TVH decision hash | DONE | `snapshot/feature/tvh/live` hashes are propagated into host result and decision/execution envelopes | Keep provenance envelope regression tests green |
| Trend bundle + far-retest continuation gate | DONE | `BingxFuturesLiveDecisionService` emits `trend_15m/4h/1d` and deterministic `trend_gate_*` block codes | Keep live-decision regressions green |
| Momentum-missed continuation gate | DONE | `BingxFuturesLiveDecisionService` blocks untouched far pending entries with deterministic `momentum_gate_*_missed_retest` codes | Keep missed-retest regressions green |
| HTF liquidity lifecycle gate | DONE | `BingxFuturesZoneDecisionService` accepts only untouched confirmed swing pivots or a current confirmed micro sweep/reclaim; internal fallback levels are diagnostic-only | Keep fresh/sweep-origin/consumed/non-executable-fallback regressions green |
| Risk governor before execution | DONE | `TradingDroneScreen._evaluateExecutionRisk`, `WasmPluginsScreen._evaluateBingxExecutionRisk` | Keep policy regression and envelope checks green |
| Exchange contract minimums before execution | DONE | Public contract rules feed minimum quantity/notional into `BingxFuturesRiskGovernorService` | Keep ETH-style minimum-size regression green |
| Exchange-backed risk inputs (equity/pnl/positions) | DONE | `BingxFuturesExchangeRiskInputService` wired in `TradingDroneScreen` and `WasmPluginsScreen` using `getUserBalance/getUserPositions` | Keep exchange payload variant tests green |
| Runtime-only futures intent execution | DONE | `place_bingx_futures_order_intent` runtime path enforced (plugin host boundary) | Keep smoke+tests green |
| Idempotency/TTL/retry discipline | DONE | `flutter/lib/services/bingx_futures_execution_queue_service.dart` | Keep regression green |
| Managed order revalidation | DONE | `BingxFuturesOrderRevalidationService` cancels stale managed drone orders when live TVH invalidates the setup | Keep revalidation regressions green |
| Managed order provenance journal | DONE | Capsule-scoped tracking state persists canonical intent + decision hash lineage for each managed order | Use provenance as the mandatory input for future deterministic replacement |
| Deterministic stale-zone replacement | DONE | `BingxFuturesOrderReplacementService` plans same-side replacement; runtime repeats host/consensus, risk, idempotency, and exchange gates | Keep replacement planner and manual exchange smoke green |
| Decision/execution observability envelopes | DONE | envelope logs wired in both execution surfaces | Keep release smoke evidence |

## Hivra Laws (Non-Negotiable)

- [ ] Modularity: decision/risk/execution logic stays in services; UI is projection-only.
- [ ] Determinism: same normalized snapshot + same policy => same decision hash.
- [ ] Downward dependencies: `UI -> app services -> plugin host API -> adapter` only.

## Spec vs Runtime Matrix

- [ ] Spec section `3. Data Inputs` is satisfied by runtime snapshot builder.
- [ ] Required snapshot groups (instrument, prices, candles, trades, OI, funding, liquidity/session inputs) are present, else `NO_SIGNAL`.
- [ ] Snapshot normalization rules are honored (UTC, deterministic sorting, fixed decimal scales, closed candles only).
- [ ] `market_snapshot_hash` is produced from canonical JSON.
- [ ] Feature extractor computes trend (EMA50/EMA200 15m), ATR14(5m), liquidity levels, and whale activations deterministically.
- [ ] Live decision emits trend bundle (`trend_15m`, `trend_4h`, `trend_1d`) and deterministic trend-gate status.
- [ ] Live decision blocks missed continuation retests before host intent preparation.
- [ ] HTF pending-entry anchors are confirmed untouched swing pivots, never raw highs/lows.
- [ ] The `4h` lifecycle window covers at least 80 days of closed candles.
- [ ] `sweep_origin`, immediate `post_sweep_reaction`, and `consumed` levels cannot silently enter the fresh candidate set.
- [ ] Post-sweep entry requires a current `sweep -> reclaim -> displacement` decision.
- [ ] Internal older/recent high/low fallback is diagnostic-only and cannot authorize an intent.
- [ ] Liquidation, force-order, and orderbook proxy levels remain contextual evidence and cannot authorize an intent.
- [ ] Missing executable liquidity anchor emits `liquidity_anchor_unavailable` and makes managed-order revalidation cancel-only.
- [ ] Rule engine decision path is explicit and hashable: `LONG | SHORT | NO_SIGNAL | BLOCKED`.
- [ ] Funding guard is applied before execution intent.
- [ ] Risk governor is applied before exchange execution.
- [ ] BingX contract minimum quantity/notional gates run before order submission.
- [ ] Execution queue enforces idempotency + TTL + deterministic retry classification.
- [ ] Managed open orders are revalidated against fresh live TVH snapshots before being left active.
- [ ] `NO_SIGNAL` managed orders receive a side-locked structural revalidation; transient flow failure alone neither cancels nor preserves them blindly.
- [ ] Structural-only revalidation can keep/cancel but cannot create or replace an order.
- [ ] Every managed open order retains capsule-scoped intent/decision provenance across restart.
- [ ] Stale-zone replacement is same-side only and passes fresh host/consensus, risk, idempotency, and exchange gates.
- [ ] Market-dead and side-flip cancellations never auto-replace.
- [ ] Observability envelopes are emitted (`drone.decision.envelope`, `drone.execution.envelope`).

## Runtime Boundary Checks

- [ ] Futures intent method is `place_bingx_futures_order_intent`.
- [ ] Runtime invoke path is used for futures execution (no host fallback execution path).
- [ ] Capability guard includes:
- [ ] `consensus_guard.read`
- [ ] `exchange.trade.bingx.futures`
- [ ] Pair-scoped execution is blocked when consensus guard is not signable.

## Test Evidence (Required)

- [ ] `flutter test test/bingx_futures_market_snapshot_service_test.dart`
- [ ] `flutter test test/bingx_futures_feature_extractor_service_test.dart`
- [ ] `flutter test test/bingx_futures_tvh_rule_engine_service_test.dart`
- [ ] `flutter test test/bingx_futures_deterministic_replay_harness_service_test.dart`
- [ ] `flutter test test/bingx_futures_risk_governor_service_test.dart`
- [ ] `flutter test test/bingx_futures_execution_queue_service_test.dart`
- [ ] `flutter test test/bingx_futures_order_revalidation_service_test.dart`
- [ ] `flutter test test/bingx_futures_order_replacement_service_test.dart`
- [ ] `flutter test test/bingx_futures_observability_envelope_service_test.dart`
- [ ] `flutter test test/plugin_host_api_service_test.dart`
- [ ] `flutter test test/wasm_plugin_capability_policy_service_test.dart`

## Manual Verification (Release Candidate)

- [ ] `situational` run hash captured and stable on replay.
- [ ] `interactive` run on the same fixture input matches `situational` hash.
- [ ] `risk_blocked` path exercised with deterministic reason code.
- [ ] Retry/transient failure path exercised and execution envelope logged.
- [ ] Exchange execution receipt path is traceable to decision hash.
- [ ] macOS + Android results are recorded with build id/tag and date.
- [ ] Evidence rows are appended to `docs/checklists/trading-drone-evidence-log.md` for each platform/mode cycle.
