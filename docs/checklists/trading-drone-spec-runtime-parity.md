# Trading Drone Spec/Runtime Parity Checklist (BingX Futures v1)

Use this checklist after any trading-drone logic change and before release packaging.

## Current Runtime Status (2026-05-26)

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
| Risk governor before execution | DONE | `TradingDroneScreen._evaluateExecutionRisk`, `WasmPluginsScreen._evaluateBingxExecutionRisk` | Keep policy regression and envelope checks green |
| Exchange-backed risk inputs (equity/pnl/positions) | DONE | `BingxFuturesExchangeRiskInputService` wired in `TradingDroneScreen` and `WasmPluginsScreen` using `getUserBalance/getUserPositions` | Keep exchange payload variant tests green |
| Runtime-only futures intent execution | DONE | `place_bingx_futures_order_intent` runtime path enforced (plugin host boundary) | Keep smoke+tests green |
| Idempotency/TTL/retry discipline | DONE | `flutter/lib/services/bingx_futures_execution_queue_service.dart` | Keep regression green |
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
- [ ] Rule engine decision path is explicit and hashable: `LONG | SHORT | NO_SIGNAL | BLOCKED`.
- [ ] Funding guard is applied before execution intent.
- [ ] Risk governor is applied before exchange execution.
- [ ] Execution queue enforces idempotency + TTL + deterministic retry classification.
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
