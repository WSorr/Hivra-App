# Trading Drone Spec/Runtime Parity Checklist (BingX Futures v1)

Use this checklist after any trading-drone logic change and before release packaging.

## Current Runtime Status (2026-06-14)

Legend:
- `DONE`: implemented and wired in live runtime path
- `PARTIAL`: implemented module exists, but not fully consumed by live entry path
- `TODO`: not implemented in required runtime path yet

| Area | Status | Runtime Evidence | Remaining Debt |
|---|---|---|---|
| Snapshot normalization + canonical hash | DONE | `flutter/lib/services/bingx_futures_market_snapshot_service.dart` | Keep regression green |
| Live exchange data surface for full TVH snapshot | DONE | `BingxFuturesExchangeService` exposes `getPublicPrice`, `getPublicKlines`, `getPublicDepth`, `getPublicTrades`, `getPublicPremiumIndex`, `getPublicOpenInterest` | Keep parsing tests green and verify exchange payload variants |
| Feature extractor (EMA/ATR/liquidity/flow context) | DONE | `flutter/lib/services/bingx_futures_feature_extractor_service.dart` | Keep regression green |
| TVH rule engine (`LONG/SHORT/NO_SIGNAL/BLOCKED`) | DONE | `flutter/lib/services/bingx_futures_tvh_rule_engine_service.dart` | Keep regression green |
| Deterministic replay harness | DONE | `flutter/lib/services/bingx_futures_deterministic_replay_harness_service.dart` | Keep fixture parity checks |
| Live entry uses TVH decision as primary gate | DONE | `TradingDroneScreen` resolves limit intents via `BingxFuturesLiveDecisionService` before host call | Keep live-decision replay checks green |
| Side/zone provenance linked to TVH decision hash | DONE | `snapshot/feature/tvh/live` hashes are propagated into host result and decision/execution envelopes | Keep provenance envelope regression tests green |
| Trend bundle + far-retest continuation gate | DONE | `BingxFuturesLiveDecisionService` emits `trend_15m/4h/1d` and deterministic `trend_gate_*` block codes | Keep live-decision regressions green |
| Momentum-missed continuation gate | DONE | `BingxFuturesLiveDecisionService` blocks untouched far pending entries with deterministic `momentum_gate_*_missed_retest` codes | Keep missed-retest regressions green |
| HTF liquidity lifecycle gate | DONE | `BingxFuturesZoneDecisionService` accepts only untouched confirmed swing pivots or a bounded closed-candle micro sweep/reclaim with ATR body, expiry, and retest limits; internal fallback levels are diagnostic-only | Keep fresh/sweep-origin/consumed/weak-body/expiry/retest-limit/non-executable-fallback regressions green |
| Pending-zone evidence projection | DONE | `TradingDroneScreen` labels HTF bounds as pending rather than current price and projects source, formation time, age, signed distance, and mandatory Run Intent revalidation from the matching existing live decision | Keep formatter, malformed-evidence fallback, and live-decision reference-price regressions green; manually verify symbol reset in packaged smoke |
| Public liquidity confluence proxies | DONE | `BingxFuturesLiveSnapshotBuilderService` deterministically emits at most three bounded `liquidation_proxy` levels per side; `BingxFuturesZoneDecisionService` uses them only to rank valid closed-structure candidates and never as entry authority | Keep permutation, bounded-output, structural-ranking, stale/crossed-depth, force-order isolation, and proxy-only no-authority regressions green |
| Live public shadow probe | DONE | The existing replay harness signs canonical public observations through `BingxFuturesPublicMarketDataPort`; run-count `1` remains the one-shot compatibility path and accepts no Capsule, credential, mandate, account state, or effect owner | Unbounded daemon operation, deployment, leases, account reads, and remote effects remain unauthorized |
| Durable public shadow stream | DONE | `BingxFuturesShadowStreamStore` atomically commits the runner identity, retains at most 256 authenticated tail files, then commits the exact signed tail head as a local checkpoint before bounded cleanup and global sequence continuation | Keep identity/checkpoint pending recovery, foreign-key/corruption/unbound-state rejection, crash overlap, conflicting checkpoint no-delete, repeated compaction, and concurrency regressions green; external anchoring, daemon scheduling, deployment, leases, receivers, account reads, and remote effects remain unauthorized |
| Bounded public shadow scheduler | DONE | The existing probe composition root may run 1–8928 strictly serial public observations at a 60–3600 second fixed delay; process-scoped session evidence enriches context as coverage accumulates, and the first failure terminates without overlap, retry, or inferred success | Keep unbounded loops, credential access from the public runner, listeners, automatic gap bridging, account reads outside their separate one-shot path, and remote effects unauthorized |
| Verifiable standalone runner artifact | DONE | One packaging tool compiles the existing public-shadow and transient account-read composition root from a clean pinned source tree and binds the exact host-native binary SHA-256, size, source commit, Dart version, platform, entrypoint, and authority profile in a strict manifest | Dart AOT is not claimed byte-reproducible; keep Linux build evidence, transfer, installation, supervisor, VPS configuration, credentials, durable account state, external anchoring, and remote effects scoped to separate passes |
| Fail-closed public-shadow supervisor contract | DONE | One systemd unit uses encrypted credential-file delivery, restarts only after a successful bounded batch, stops on failure, denies listener binding, and fixes 128 MiB memory, zero swap, 16 tasks, finite runtime, dynamic identity, and public-only arguments | Keep bundle creation, atomic installation, credential creation, enablement, exact-unit runtime smoke, external anchoring, account reads, leases, and remote effects unauthorized |
| Verifiable runner bundle and persistent disabled install | DONE | The existing artifact owner binds exact binary/unit bytes and canonical paths, atomically publishes one `/opt` bundle, refuses pre-existing state, persists one encrypted runner-only credential, and leaves the exact unit disabled and inactive; exact uninstall verifies ownership, removes the bundle last for retryability, and the same smoke proves restart identity before complete cleanup | Keep credential rotation/replacement, external anchoring, account reads, leases, and remote effects unauthorized; boot enablement is owned only by the separate identity-bound activation row |
| Identity-bound public-shadow activation | DONE | The existing artifact owner initializes one persistent identity while disabled, requires the operator-confirmed `runner_key_id`, proves matching authenticated evidence before exact boot enablement, and deactivates before preserving the same identity | Merge-SHA VPS evidence proved initialize, wrong-key rejection, activate, observe, deactivate, exact uninstall, and unchanged co-hosted workloads; external anchoring, account reads, leases, and effects remain unauthorized |
| Portable external evidence anchor | DONE | The existing artifact owner atomically exports exact signed evidence bytes plus the identity-bound public key, while the existing replay harness performs bounded canonical parsing, signature verification, and retained-anchor continuity checks off-host | Merge-SHA VPS-to-Mac evidence proved exact replay, one-step continuation, reverse rollback rejection, bounded resources, cleanup, and unchanged co-hosted workloads; no listener, receiver, account authority, lease, credential rotation, or effect path is authorized |
| Capsule-signed remote mandate admission | DONE | The existing mandate model owns one domain-separated canonical admission commitment; the Capsule root signer binds it to the exact initialized runner, and the existing host lifecycle verifies and stores one prepared artifact | Merge-SHA macOS-to-VPS evidence proved admission, idempotent replay, mutation rejection, byte-identical retention, exact uninstall, and unchanged co-hosted workloads; credentials, account reads, leases, listeners, and effects remain unauthorized |
| Mandate-bound prepared exchange credential | DONE | The existing host lifecycle accepts a dedicated subaccount key only through bounded stdin, verifies its API-key hash against the active Capsule-signed mandate, and retains only one host-encrypted prepared value | Keep the credential absent from the runner unit; merge-SHA VPS provisioning, exact replay/conflict rejection, uninstall, and co-host preservation remain completion evidence; only the separately bounded one-shot account read may consume it, while persistent reads and effects remain unauthorized |
| Exact single-use account read | DONE | The existing v2 remote admission commitment binds the Capsule signature to one runner, account, mandate, exact ordered balance/positions/open-orders scope, and `max_uses=1`; static verification remains valid after expiry, while execution eligibility is checked only after journal resolution and before the lifecycle creates `pending` | Return exact retained `completed` evidence after expiry without provider access; reject expired unused/pending authority, v1 authority, widened/reordered scope, second provider invocation, corrupt/conflicting journal state, payload retention, persistent credential access, schedules, leases, POST/DELETE, reconciliation, and effects; require merge-SHA VPS proof and exact cleanup before closure |
| Pinned Linux x64 runner evidence | DONE | The same packaging owner resolves one exact pure-Dart lock, binds its SHA-256 into the manifest, and cross-compiles only the explicit `linux/x64` target; verification requires an ELF x86-64 binary matching that manifest | Keep Linux execution, libc/runtime compatibility smoke, transfer, installation, service supervision, VPS networking/resources, credentials, account reads, external anchoring, and remote effects unauthorized |
| Intent freshness + one-event/one-effect | DONE | Stable event identity remains in the zone owner; the execution use case revalidates the event and closed bar, then atomically claims only a LIVE effect in the existing Capsule-scoped tracking store; TEST success is validation without an order claim | Keep stale-bar/event/hash, validation-without-claim, concurrent live duplicate, restart, isolation, bounded-journal, and single-effect-owner regressions green |
| Capsule-owned bounded trading mandate | DONE | The existing tracking store owns one versioned mandate commitment; the existing exchange execution owner checks exact Capsule/account/symbol/mode/time/notional/risk/effect bounds and binds each event claim to it | Keep mutation, expiry, revoke, restart, Capsule/account isolation, policy escalation, notional, and atomic effect-budget regressions green |
| Managed-order restart recovery + reconciliation | DONE | The existing execution use case reconciles only locally persisted, account-bound order/client ids through exact provider reads; terminal and unresolved evidence remain distinct and no missing order is recreated or adopted | Keep exact-status, not-found, timeout, account-mismatch, reserved-claim recovery, Capsule-switch, and manual-order isolation regressions green |
| Durable Capsule emergency pause | DONE | The existing Capsule-scoped tracking store persists explicit control state; the exchange execution owner checks it before risk work and immediately before claim/queue, while missing, legacy, malformed, restarted, or cross-Capsule state fails closed | Keep unavailable, restart, Capsule-isolation, and mid-flight pause regressions green |
| Canonical solo trading cycle port | DONE | `BingxFuturesTradingCycleUseCaseService` composes the existing live-strategy, sizing, WASM intent, and exchange-execution owners; `TradingDroneScreen` delegates solo limit preparation to it; `executed` additionally requires the nested provider result to be successful | Keep invalid input, missing event, sizing failure, missing credential, refresh, provider rejection, contradictory outcome, and single-effect delegation regressions green; scheduler/VPS remains blocked |
| Risk governor before execution | DONE | `TradingDroneScreen` delegates execution risk to `BingxFuturesExchangeExecutionUseCaseService` | Keep policy regression and envelope checks green |
| Exchange contract minimums before execution | DONE | Public contract rules feed minimum quantity/notional into `BingxFuturesRiskGovernorService` | Keep ETH-style minimum-size regression green |
| Realized-loss risk inputs | DONE | Authenticated BingX `REALIZED_PNL` records are normalized into one Capsule-scoped atomic risk projection; UTC daily PnL, loss streak, and last-loss time feed the governor | Keep persistence, dedupe, truncation, and live cooldown regressions green |
| Exchange-backed risk inputs (equity/pnl/positions) | DONE | `BingxFuturesExchangeRiskInputService` is consumed by the trading-drone execution use case using `getUserBalance/getUserPositions`; live execution fails closed when those inputs fall back | Keep exchange payload variant and live-fallback-block tests green |
| External package binding and invoke evidence | DONE | `place_bingx_futures_order_intent` requires an installed package, strict contract/capabilities, package digest and runtime invoke evidence | Keep fail-closed security tests green |
| Plugin-owned semantic contract execution | DONE | `hivra-plugins` owns BingX/chat evaluators; `hivra-wasm-runtime` executes ABI v2 JSON-in/JSON-out through bounded `wasmi`; Flutter validates canonical output and no longer contains mirrored contract evaluators | Keep ABI, runtime, integrity and cross-platform regressions green |
| Plugin-owned signal ranking | DONE | `rank_bingx_futures_signals` is implemented in the external BingX futures plugin; Flutter sends deterministic live-decision summaries and renders the returned `entries`/`scan_hash_hex` without mirroring score logic | Keep plugin ABI tests and host boundary tests green |
| Idempotency/TTL/retry discipline | DONE | `flutter/lib/services/bingx_futures_execution_queue_service.dart` | Keep regression green |
| Managed order revalidation | DONE | `BingxFuturesOrderRevalidationService` cancels stale managed drone orders when live TVH invalidates the setup | Keep revalidation regressions green |
| Managed order provenance journal | DONE | Capsule-scoped tracking state persists canonical intent + decision hash lineage for each managed order | Use provenance as the mandatory input for future deterministic replacement |
| Deterministic stale-zone replacement | DONE | `BingxFuturesOrderReplacementService` plans same-side replacement; runtime repeats host/consensus, risk, idempotency, and exchange gates | Keep replacement planner and manual exchange smoke green |
| Decision/execution observability envelopes | DONE | envelope logs wired through the dedicated trading-drone execution surface | Keep release smoke evidence |

## Hivra Laws (Non-Negotiable)

- [ ] Modularity: decision/risk/execution logic stays in services; UI is projection-only.
- [ ] Determinism: same normalized snapshot + same policy => same decision hash.
- [ ] Downward dependencies: `UI -> app services -> plugin host API -> adapter` only.

## Spec vs Runtime Matrix

- [ ] Spec section `3. Data Inputs` is satisfied by runtime snapshot builder.
- [ ] Closed-bar structure and recent aggressive trades are present before a directional market decision can prepare an intent.
- [ ] Recent REST trades remain bounded recent-flow evidence and cannot be
      relabeled as complete session evidence.
- [ ] Incomplete current/previous session coverage remains explicit context and
      cannot independently authorize or block a directional decision.
- [ ] Public session evidence retains only three aggregate buckets in process;
      disconnect, malformed input, stale heartbeat, process restart, and the
      bounded supervisor restart reset completeness because the source has no
      sequence identifier.
- [ ] Recent aggressive trade activation uses dimensionless notional imbalance;
      session and raw base-asset quantity deltas remain diagnostic-only.
- [ ] Snapshot normalization rules are honored (UTC, deterministic sorting, fixed decimal scales, closed candles only).
- [ ] `market_snapshot_hash` is produced from canonical JSON.
- [ ] Feature extractor computes trend (EMA50/EMA200 15m), ATR14(5m), liquidity levels, and large-flow context deterministically.
- [ ] Live decision emits trend bundle (`trend_15m`, `trend_4h`, `trend_1d`) and deterministic trend-gate status.
- [ ] Live decision blocks missed continuation retests before host intent preparation.
- [ ] HTF pending-entry anchors are confirmed untouched swing pivots, never raw highs/lows.
- [ ] The `4h` lifecycle window covers at least 80 days of closed candles.
- [ ] `sweep_origin`, immediate `post_sweep_reaction`, and `consumed` levels cannot silently enter the fresh candidate set.
- [ ] Post-sweep entry requires a current `sweep -> reclaim -> displacement` decision.
- [ ] Internal older/recent high/low fallback is diagnostic-only and cannot authorize an intent.
- [ ] Liquidation, force-order, and orderbook proxy levels may rank valid structural candidates but cannot authorize an intent or become its anchor.
- [ ] Trend, OI, session evidence, and large-flow activation remain context; recent aggressive-volume imbalance owns directional activation.
- [ ] Missing executable liquidity anchor emits `liquidity_anchor_unavailable` and makes managed-order revalidation cancel-only.
- [ ] Pending-zone fields cannot be mistaken for current price: source, formation time, age, signed distance, and Run Intent revalidation are visible, and changing symbol clears prior evidence.
- [ ] Rule engine decision path is explicit and hashable: `LONG | SHORT | NO_SIGNAL | BLOCKED`.
- [ ] A blocked foreground cycle exposes the exact funding, volume, structure,
      zone-conflict, or continuation reason without invoking intent/effect owners.
- [ ] Funding guard is applied before execution intent.
- [ ] Risk governor is applied before exchange execution.
- [ ] Live exchange execution is blocked if balance, pnl, or position inputs
      fall back; fallback risk inputs are diagnostic/test-only.
- [ ] BingX contract minimum quantity/notional gates run before order submission.
- [ ] Execution queue enforces idempotency + TTL + deterministic retry classification.
- [ ] Zone-pending execution recomputes the live decision and rejects a changed live-decision hash, new closed bar, changed/expired/consumed event, side change, or zone-side change.
- [ ] One LIVE `liquidity_event_id` can reserve at most one exchange effect across double-click, retry, restart, and reconnect; TEST validation creates no effect claim.
- [ ] The Capsule-scoped event-claim journal is bounded and fails closed rather than evicting authority evidence.
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
- [ ] Runtime invoke path is used for futures signal ranking (no Flutter-side plugin scoring mirror).
- [ ] Runtime ABI is `hivra_host_abi_v2` with `hivra_alloc_v1`, `hivra_evaluate_v1`, and `hivra_dealloc_v1`.
- [ ] Runtime rejects imports, oversized modules/input/output, invalid signatures, and fuel exhaustion.
- [ ] Host validates plugin canonical JSON identity and SHA-256 before using the result.
- [ ] Capability guard includes:
- [ ] `consensus_guard.read`
- [ ] `exchange.trade.bingx.futures`
- [ ] `rank_bingx_futures_signals` requires `exchange.read.bingx.market`, not pair consensus.
- [ ] Pair-scoped execution is blocked when consensus guard is not signable.

## Test Evidence (Required)

- [ ] `flutter test test/bingx_futures_market_snapshot_service_test.dart`
- [ ] `flutter test test/bingx_futures_feature_extractor_service_test.dart`
- [ ] `flutter test test/bingx_futures_tvh_rule_engine_service_test.dart`
- [ ] `flutter test test/bingx_futures_deterministic_replay_harness_service_test.dart`
- [ ] `flutter test test/bingx_futures_shadow_stream_store_test.dart`
- [ ] `flutter test test/bingx_futures_risk_governor_service_test.dart`
- [ ] `flutter test test/bingx_futures_execution_queue_service_test.dart`
- [ ] `flutter test test/bingx_futures_order_revalidation_service_test.dart`
- [ ] `flutter test test/bingx_futures_order_replacement_service_test.dart`
- [ ] `flutter test test/bingx_futures_trading_cycle_use_case_service_test.dart`
- [ ] `flutter test test/bingx_futures_order_tracking_store_test.dart`
- [ ] `flutter test test/bingx_futures_exchange_execution_use_case_service_test.dart`
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
