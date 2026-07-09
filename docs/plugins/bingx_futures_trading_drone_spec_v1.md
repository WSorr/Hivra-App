# BingX Futures Trading Drone — Specification v1

Status: Active (runtime-bound)
Scope: Plugin/Application layer only (no Core/ledger invariant changes)

---

## 1. Purpose

Define a deterministic trading-drone spec for BingX futures that:

- computes TVH (entry setup) from a fixed market-data snapshot,
- produces a deterministic intent envelope for capsule peers and runtime execution,
- preserves Hivra laws: modularity, determinism, dependencies strictly downward.

This document describes the full v1 runtime path:

- deterministic signal generation and intent preparation,
- risk-governed execution through runtime invoke boundary,
- deterministic decision/execution observability envelopes.

---

## 2. Architecture Contract (Hivra Laws)

1. Modularity:
   - Drone logic lives in plugin/application boundary.
   - Core invariants/events are untouched.
2. Determinism:
   - Same normalized snapshot + same config => same TVH output hash.
   - Non-deterministic sources (wall clock, random, mutable globals) are forbidden in evaluation.
3. Downward dependencies only:
   - UI -> App services -> plugin host API -> transport adapter.
   - Drone must not create reverse dependency into Core/Engine internals.

### 2.1 Operation Modes (mandatory)

The trading drone supports two operation modes in v1:

1. `situational` (on-demand):
   - Capsule and drone are invoked by explicit user action.
   - Drone computes one deterministic decision cycle on current closed-bar snapshot.
   - Result is projected immediately (`NO_SIGNAL` or deterministic intent draft).
2. `interactive` (always-on):
   - Drone runs continuously with scheduled evaluation cycles.
   - Drone refreshes snapshot on each cycle and manages pending intents/order lifecycle according to policy.
   - Requires heartbeat and self-recovery orchestration in app runtime layer.

Mode invariants:

- Both modes MUST use the same deterministic pipeline:
  `snapshot_normalize -> feature_extract -> rule_engine -> intent_builder`.
- Mode differences are orchestration-only (when/why to run), not decision-logic differences.
- For identical normalized snapshot and identical policy config, both modes MUST produce identical decision payload/hash.

---

## 3. Data Inputs from Exchange (Required for TVH v1)

The drone MUST build a **single normalized snapshot** from these sources:

Data source policy:

- primary and normative source for v1: **BingX API only**,
- third-party market feeds are out of scope for v1 execution path.

1. Instrument metadata
   - symbol, quote/base, tick size, qty step, min qty, max leverage.
2. Prices
   - last trade price,
   - mark price,
   - index price.
3. Candles (OHLCV)
   - 1m, 5m, 15m, 1h, 4h, 1d, 1w timeframes,
   - only **closed candles** are used for indicators,
   - recommended depth: at least 300 closed candles (up to 1d) and at least 120 candles on 1w.
4. Recent trades
   - recent market trades (for taker-flow delta), recommended 200+ rows.
5. Open interest
   - latest value + short history (5m buckets, min 24 points).
6. Funding data
   - current funding rate and next funding timestamp.
7. Liquidity map inputs
   - buyside/sellside external liquidity levels from HTF swings (up to 1w),
   - internal liquidity levels (local equal highs/lows and range inefficiencies on 1m/5m/15m),
   - liquidation-level feed (if provided by data vendor/exchange endpoint).
8. Session volume inputs
   - volume by session windows (Asia/London/NY),
   - session delta profile for current and previous session.

Optional (v1.1+):

- long/short account ratio.

If any required group (1..8) is missing, result MUST be `NO_SIGNAL`.
Missing **optional** groups MUST NOT block signal generation.

### 3.1 Whale Trigger Activation Stream (instead of raw orderbook bias)

For v1, the drone MUST NOT rely on passive orderbook imbalance as a primary decision input.

Instead, it tracks **activated large pending orders** ("whale trigger activations") via:

1. aggressive trade prints near mapped liquidity levels,
2. synchronized impulse in short-window volume,
3. synchronized OI jump/drop in the same event window.

Normalized event output:

- `activation_side: buy|sell`
- `activation_price_decimal`
- `activation_size_decimal`
- `activation_window_start_utc`
- `activation_window_end_utc`
- `activation_confidence_decimal` (0..1)

---

## 4. Snapshot Normalization and Deterministic Hash

Before feature extraction, the drone MUST:

1. Convert all timestamps to UTC ISO-8601.
2. Sort arrays deterministically (timestamp asc, then side/price asc where relevant).
3. Normalize decimals to string with fixed scale per field:
   - prices: 8,
   - quantity: 8,
   - ratios/rates: 10.
4. Exclude partially closed candles from indicator series.

Snapshot digest:

- `market_snapshot_hash = sha256(canonical_json(snapshot_v1))`.

All downstream TVH outputs MUST include this hash.

---

## 5. Feature Set for TVH v1

### 5.1 Trend Context

- EMA50 and EMA200 on 15m.
- Direction:
  - bullish if EMA50 > EMA200,
  - bearish if EMA50 < EMA200.

Trend context must be carried as a bundle, not a single timeframe:

- `trend_15m` from EMA50/EMA200,
- `trend_4h` from higher-timeframe drift bias,
- `trend_1d` from daily drift bias.

The runtime decision envelope must emit this bundle for every live decision.

### 5.2 Volatility/Risk Frame

- ATR14 on 5m.
- Use ATR for stop distance and min displacement filter.

### 5.3 Liquidity Zone Detection

Define swing levels on 5m:

- buyside liquidity: local highs over lookback=40 candles,
- sellside liquidity: local lows over lookback=40 candles.

Sweep condition:

- price wick crosses swing level and closes back inside range within 1–3 candles.

### 5.3.1 Required Detection Algorithm (Pivot Cluster, Jack-Venture Style)

For v1 implementation, liquidity level detection MUST follow the pivot-cluster model equivalent to the provided Pine logic:

1. Pivot source:
   - `pivot_high = pivothigh(liqLen, 1)`
   - `pivot_low = pivotlow(liqLen, 1)`
2. Cluster band:
   - include pivots within `pivot_price ± (ATR10 / liqMar)`
3. Cluster acceptance:
   - level is valid only when `count > 2` pivots in cluster
4. Level price:
   - cluster center = `avg(minPivotPrice, maxPivotPrice)`
5. Zone thickness:
   - top/bottom around center by `± (ATR10 / liqMar)`
6. External/Internal class:
   - buyside external = highest active buyside level
   - sellside external = lowest active sellside level
   - all other active levels are internal
7. Breach logic:
   - buyside breached when `high > zone_top`
   - sellside breached when `low < zone_bottom`
8. Reverse signal logic (post-breach):
   - buy reverse from breached sellside at `level * (1 - buyPctBreak/100)`
   - sell reverse from breached buyside at `level * (1 + sellPctBreak/100)`

Default parameters for v1:

- `liqLen = 7`
- `liqMar = 10 / 6.9`
- `buyPctBreak = 1.0`
- `sellPctBreak = 1.0`
- `maxTrackedLevelsPerSide = visLiq = 3` (configurable)

Determinism constraints:

- level list must be sorted deterministically before hashing/output,
- class assignment (external/internal) must be derived from active level set only,
- no UI/runtime state may influence level computation.

### 5.4 Microstructure Confirmation

- taker-flow delta from recent trades:
  - `delta = aggressive_buy_qty - aggressive_sell_qty`.
- open-interest delta:
  - positive/negative regime relative to prior 3 buckets.
- session volume regime:
  - active session volume percentile vs trailing baseline,
  - session imbalance supports direction.
- whale trigger activation:
  - require at least one high-confidence activation event aligned with intended direction.

### 5.5 External/Internal Liquidity Confirmation

- external liquidity (up to 1w):
  - nearest unswept HTF buyside/sellside pools,
  - distance from current price to target pool.
- internal liquidity:
  - local liquidity pockets inside current dealing range.
- liquidation levels:
  - cluster proximity score near planned entry/invalidation area.
  - liquidation/force-order/orderbook proxy levels are contextual evidence only
    and MUST NOT become executable entry anchors.
  - account-scoped `forceOrders` history is not a market liquidation map and
    MUST NOT be normalized as liquidation-level evidence.
  - orderbook-derived estimates MUST be labeled `liquidation_proxy`; only a
    dedicated market-wide feed may set liquidation state to `known`.

External HTF levels MUST have an explicit deterministic lifecycle:

- `fresh`: a confirmed swing pivot that has not been swept after confirmation;
- `sweep_origin`: a new pivot that itself breaks the previous same-side pivot;
- `post_sweep_reaction`: the first same-side pivot formed after a
  `sweep_origin`; it belongs to the reaction leg and is not new external
  liquidity;
- `consumed`: a confirmed pivot breached by a later candle.

Only `fresh` HTF pivots may be used as pending-entry retest anchors.
The `4h` lifecycle window MUST cover at least 80 days of closed candles so a
level cannot appear fresh merely because an older sweep fell outside a short
runtime lookback.
Raw candle highs/lows MUST NOT be treated as executable liquidity levels.
`sweep_origin`, `post_sweep_reaction`, and `consumed` levels MUST NOT become
fresh again merely because price moved away from them. A trade after a sweep
requires the separate current microstructure path
(`sweep -> reclaim -> displacement`) and a new live decision.
Local `olderHigh/recentHigh/olderLow/recentLow` values may be emitted as
`internal_diagnostic`, but MUST NOT authorize a pending order. If neither a
`fresh` HTF pivot nor a current confirmed micro sweep/reclaim exists, the live
decision MUST emit `liquidity_anchor_unavailable`.

If liquidation-level feed is unavailable:

- liquidation score is marked `unknown`,
- signal can still pass if all non-liquidation criteria pass.

### 5.6 Funding Regime Filter

- block signals on extreme funding:
  - `abs(funding_rate) > funding_extreme_threshold`.
- default threshold v1: `0.0015` (0.15%).

### 5.7 Orderbook Policy

Orderbook depth is **not** a required decision feature for v1 TVH.

- raw bid/ask imbalance must not block or authorize a trade by itself,
- hidden/triggered liquidity is treated through activation events (section 3.1).

---

## 6. TVH Entry Criteria (v1 Rule-Set)

All conditions below MUST pass in one evaluation cycle.

### 6.1 LONG TVH

1. Trend context bullish (EMA50 > EMA200, 15m).
2. A sellside sweep is detected within last 3 closed 5m candles.
3. Price re-enters zone and closes above sweep reclaim level.
   Historical `sweep_origin`/`consumed` HTF levels do not satisfy this rule.
4. Microstructure confirms:
   - delta > 0,
   - open-interest delta >= 0,
   - session volume regime supports long,
   - whale trigger activation supports long.
5. Liquidity confirms:
   - external liquidity map has valid upside target,
   - internal liquidity supports reclaim continuation.
6. Funding is not extreme.

Entry anchor:

- zone-based pending entry inside reclaim zone, using selected zone price rule (`zone_low` / `zone_mid` / `zone_high` / `manual`).

### 6.2 SHORT TVH

1. Trend context bearish (EMA50 < EMA200, 15m).
2. A buyside sweep is detected within last 3 closed 5m candles.
3. Price re-enters zone and closes below sweep reclaim level.
   Historical `sweep_origin`/`consumed` HTF levels do not satisfy this rule.
4. Microstructure confirms:
   - delta < 0,
   - open-interest delta >= 0 (new positioning) or policy-allowed weakening regime,
   - session volume regime supports short,
   - whale trigger activation supports short.
5. Liquidity confirms:
   - external liquidity map has valid downside target,
   - internal liquidity supports reclaim continuation.
6. Funding is not extreme.

Entry anchor:

- zone-based pending entry inside reclaim zone.

### 6.3 Trend-Gate (Continuation vs Far Retest)

To avoid blind far-retest entries during impulsive continuation:

- If decision side is `short`,
- and trend bundle is strongly bearish (`trend_15m=bearish`, `trend_4h=bear`, `trend_1d=bear`),
- and zone model marks `needs_farther_retest=true`,
- and `target_retest_pct >= 0.07`,

then live intent preparation must be blocked with deterministic code:

- `trend_gate_short_far_retest`.

Symmetric long-side rule applies with:

- `trend_gate_long_far_retest`.

### 6.4 Momentum-Missed Gate (Do Not Chase Dead Retests)

To avoid leaving untouched pending orders after the market has already moved:

- If decision side is `short`,
- and trend bundle is strongly bearish (`trend_15m=bearish`, `trend_4h=bear`, `trend_1d=bear`),
- and no fresh sweep-up/reversal signal exists,
- and the proposed sell zone is already at least `1.8%` above current local mid,

then live intent preparation must be blocked with deterministic code:

- `momentum_gate_short_missed_retest`.

Symmetric long-side rule applies when the market already continued upward and the buy zone is at least `1.8%` below current local mid:

- `momentum_gate_long_missed_retest`.

Runtime implication:

- already-open managed drone orders must be revalidated against a fresh live decision snapshot during order tracking,
- each managed order must persist capsule-scoped provenance (canonical intent and decision hash lineage) before it can participate in replacement lifecycle,
- only capsule-managed drone orders may be auto-canceled,
- manual exchange orders must not be touched by this lifecycle,
- market-dead reasons (`momentum_gate_*_missed_retest`, `trend_gate_*_far_retest`, `liquidity_anchor_unavailable`) require deterministic cancel of the stale pending order,
- side mismatch or entry price leaving the current TVH zone also requires deterministic cancel.
- `NO_SIGNAL` alone must neither cancel nor preserve a managed order blindly: revalidation must lock the existing order side and evaluate the current structural zone independently from trade-delta signal eligibility,
- a side-locked structural evaluation may only keep or cancel the existing order; it must never authorize a new or replacement order,
- when the side-locked structural anchor is executable and the order remains inside its zone, the order is kept even if transient flow inputs produce `NO_SIGNAL`,
- when the side-locked anchor is unavailable or the order price left its structural zone, the order is canceled without replacement unless a separate normal actionable live decision exists.
- replacement must never reuse an unprovenanced order or bypass fresh decision, risk, idempotency, and execution gates.

Automatic replacement policy:

- `live_zone_mismatch` may produce one same-side replacement per `(peer, symbol, side)` lifecycle cycle,
- replacement uses the fresh live TVH zone and retains original quantity,
- original stop-distance percentage and risk/reward ratio are projected onto the fresh zone midpoint,
- replacement receives a deterministic client id derived from old intent hash + fresh live decision hash,
- consensus/host preparation, risk governor, execution idempotency, and exchange receipt are evaluated again,
- `live_side_mismatch`, `momentum_gate_*`, `trend_gate_*`, and `liquidity_anchor_unavailable` are cancel-only and must never auto-reverse or auto-replace.

---

## 7. Risk, Stop, Target Rules

For every accepted TVH:

1. Stop-loss distance:
   - `max(structure_invalidation_distance, 0.8 * ATR14_5m)`.
2. Take-profit baseline:
   - first target at `>= 1.8R`,
   - optional second target at `>= 2.5R`.
3. Reject setup when:
   - estimated slippage > `max_slippage_bps`,
   - stop distance violates symbol precision/min distance constraints.
4. One active pending intent per `(symbol, side, capsule-peer)` in v1.

---

## 8. Drone Output Contract

The drone emits deterministic envelope payload:

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.bingx-futures-trading.v1",
  "contract_kind": "bingx_futures_order_intent",
  "rule_set": "tvh_v1",
  "market_snapshot_hash": "<sha256>",
  "symbol": "BTC-USDT",
  "side": "buy|sell",
  "entry_mode": "zone_pending",
  "zone_side": "buyside|sellside",
  "zone_low_decimal": "...",
  "zone_high_decimal": "...",
  "zone_price_rule": "zone_low|zone_mid|zone_high|manual",
  "trigger_price_decimal": "...",
  "stop_loss_decimal": "...",
  "take_profit_decimal": "...",
  "risk_model": {
    "atr14_5m_decimal": "...",
    "rr_min_decimal": "1.8"
  },
  "liquidity_model": {
    "external_tf_max": "1w",
    "external_target_side": "buyside|sellside",
    "internal_liquidity_state": "supportive|neutral|conflict",
    "liquidation_score": "known|unknown"
  },
  "created_at_utc": "..."
}
```

Intent hash:

- `intent_hash = sha256(canonical_json(intent_payload))`.

---

## 9. Integration with Current Hivra Runtime

Current host API binding:

- `plugin_id`: `hivra.contract.bingx-futures-trading.v1`
- `method`: `place_bingx_futures_order_intent`
- required capabilities:
  - `consensus_guard.read`
  - `exchange.trade.bingx.futures`

Runtime execution behavior (v1):

- host method produces deterministic intent payload and intent hash,
- exchange mutation is performed only via runtime execution queue path,
- risk governor and idempotency/TTL guards are mandatory pre-execution checks,
- decision/execution envelopes are emitted for traceability.

Broadcast behavior:

- signal envelope may be shared with consensus peers as plugin-domain message,
- peer broadcast is informational and does not bypass local execution gate.

---

## 10. Acceptance Criteria (v1)

1. Determinism:
   - repeated evaluation on identical snapshot produces identical `intent_hash`.
2. Safety:
   - missing required data -> `NO_SIGNAL`, never partial trade intent.
   - failed risk gate -> deterministic `blocked` decision code.
3. Boundary discipline:
   - no direct ledger writes from drone,
   - no transport-side business logic leakage.
4. Explainability:
   - each emitted TVH includes rule-set id and matched condition summary.
5. Mode parity:
   - `situational` and `interactive` modes produce identical decision payload/hash for identical snapshot+policy inputs.
6. Runtime parity:
   - execution path uses runtime invoke boundary only (no host fallback mutation path),
   - execution envelope hash is traceable to intent hash and decision hash.

---

## 11. Open Decisions for v1.1

1. Add liquidation feed as mandatory confirmation or keep optional.
2. Include long/short ratio as regime filter.
3. Introduce symbol-specific threshold profiles (BTC/ETH vs alts).
4. Add deterministic session windows (for example, London/NY overlap filters).

---

## 12. Implementation Work Packages (Step-by-Step)

WP order is strict and mirrors dependency-down discipline.

### WP-1. Market Snapshot DTO + Canonicalizer

Target:

- add normalized snapshot model and canonical serializer.

Implementation:

- create `flutter/lib/services/bingx_futures_market_snapshot_service.dart`
- include:
  - snapshot DTOs (instrument, prices, candles, orderbook, trades, oi, funding),
  - normalization helpers,
  - deterministic canonical JSON + `market_snapshot_hash`.

Tests:

- `flutter/test/bingx_futures_market_snapshot_service_test.dart`.

### WP-2. Feature Extractor (pure deterministic math)

Target:

- compute EMA/ATR/sweeps/microstructure/funding flags from normalized snapshot.

Implementation:

- create `flutter/lib/services/bingx_futures_feature_extractor_service.dart`
- no transport or UI calls allowed.

Tests:

- `flutter/test/bingx_futures_feature_extractor_service_test.dart`
- fixed fixtures with exact expected numeric outputs.

### WP-3. TVH Rule Engine

Target:

- deterministic decision: `LONG | SHORT | NO_SIGNAL` plus reason codes.

Implementation:

- create `flutter/lib/services/bingx_futures_tvh_rule_engine_service.dart`
- input: feature model + policy thresholds.
- output: rule-set evaluation object with matched/missed criteria.

Tests:

- `flutter/test/bingx_futures_tvh_rule_engine_service_test.dart`
- include:
  - bullish pass,
  - bearish pass,
  - funding block,
  - insufficient data block.

### WP-4. Intent Builder

Target:

- map TVH decision into host-api-ready futures intent payload.

Implementation:

- keep intent mapping in
  `flutter/lib/services/bingx_futures_intent_use_case_service.dart`.
- do not reintroduce the removed `bingx_trading_contract_service.dart`
  boundary; futures intent preparation belongs to the futures application
  service layer.
- must emit:
  - `rule_set`,
  - `market_snapshot_hash`,
  - risk block,
  - deterministic `intent_hash`.

Tests:

- maintain `flutter/test/bingx_futures_intent_use_case_service_test.dart`.

### WP-5. Host API Wiring + Guard

Target:

- route drone output through current plugin host API boundary.

Implementation:

- keep using:
  - `plugin_id = hivra.contract.bingx-futures-trading.v1`
  - `method = place_bingx_futures_order_intent`
- keep capability gate:
  - `consensus_guard.read`
  - `exchange.trade.bingx.futures`

Files:

- `flutter/lib/services/plugin_host_api_service.dart`
- `flutter/lib/services/wasm_plugin_capability_policy_service.dart`
- `flutter/lib/services/app_runtime_service.dart`

Tests:

- extend `flutter/test/plugin_host_api_service_test.dart`
- extend `flutter/test/wasm_plugin_capability_policy_service_test.dart`.

### WP-6. UI Projection and Explainability

Target:

- show deterministic decision and reasons without embedding domain logic in UI.

Implementation:

- keep calculation in services,
- UI only renders:
  - rule-set outcome,
  - top blocking reason,
  - short hash preview.

Files:

- `flutter/lib/screens/wasm_plugins_screen.dart`.

Tests:

- widget tests for rendering state transitions only.

---

## 13. Test Matrix

### 13.1 Unit Tests (mandatory)

1. Snapshot normalization:
   - unordered input -> stable canonical output.
2. Snapshot hash:
   - same snapshot -> same hash.
3. Feature math:
   - EMA/ATR and sweep detection exact fixture checks.
4. Rule engine:
   - long/short/no-signal branches with explicit reason code assertions.
5. Intent builder:
   - stable `intent_hash` and required fields for equal inputs.

### 13.2 Contract/Boundary Tests (mandatory)

1. Host method mismatch -> `unsupported_method`.
2. Missing futures capability -> `runtime_capability_mismatch`.
3. Contract kind mismatch -> `runtime_contract_kind_mismatch`.
4. Guard blocked consensus -> `blocked` response with fact codes.

### 13.3 Integration Tests (recommended)

1. End-to-end dry run:
   - snapshot fixture -> TVH decision -> host response -> broadcast payload.
2. Replay determinism:
   - rerun identical fixture N times and compare all hashes.

### 13.4 Manual Smoke (release gate)

1. Run futures intent from plugin screen.
2. Verify snackbar/result hash stable for same fixture inputs.
3. Verify signal appears in peer inbox and can be repeated as draft.
4. Verify no ledger mutation side effects beyond existing transport envelope behavior.

---

## 14. Definition of Done (v1 Drone)

All conditions must hold:

1. Work packages WP-1..WP-6 merged.
2. New tests added and passing in CI.
3. No dependency-rule violations in review gates.
4. Futures plugin package installable from source catalog.
5. Manual smoke passed on macOS and Android release builds.

---

## 15. Execution Command Flow v1 (Capsule Integration)

This section defines how a capsule receives and authorizes entry commands.

### 15.1 Command Envelope (incoming)

Command payload kind:

- `command_kind = futures_execution_command_v1`

Required fields:

- `schema_version = 1`
- `plugin_id = hivra.contract.bingx-futures-trading.v1`
- `command_id` (globally unique command key)
- `intent_hash_hex` (64 hex)
- `symbol`
- `side = buy|sell`
- `quantity_decimal`
- `entry_price_decimal`
- `stop_loss_decimal`
- `take_profit_decimal`
- `leverage_decimal`
- `risk_percent_decimal`
- `created_at_utc`
- `expires_at_utc`
- `target_capsule_root_hex` (exact local capsule root identity)

### 15.2 Local Execution Gate (mandatory)

Each recipient capsule MUST run a local gate before exchange execution.

Gate checks (in order):

1. consensus guard signable for sender peer
2. envelope shape and field validity
3. target capsule match (`target_capsule_root_hex == local capsule root`)
4. TTL validity (`now <= expires_at_utc`)
5. anti-replay (`command_id` not seen before)
6. risk policy:
   - symbol in allowlist
   - leverage <= configured max
   - risk_percent <= configured max
7. optional local intent linkage:
   - known `intent_hash_hex` in local plugin inbox/journal

If any check fails: reject command and emit deterministic receipt.

### 15.3 Exchange Execution Responsibility

If gate passes:

- only the local capsule that holds exchange credentials executes the order,
- execution adapter uses local secret storage only,
- exchange API credentials MUST NOT be mirrored into user-visible or
  app-private plaintext files; unavailable secure storage blocks persistence,
- no remote capsule can force direct exchange mutation.

### 15.4 Receipt Envelope (outgoing)

Receipt payload kind:

- `receipt_kind = futures_execution_receipt_v1`

Fields:

- `schema_version = 1`
- `command_id`
- `intent_hash_hex`
- `decision = accepted|rejected`
- `decision_code`
- `decision_message`
- `target_capsule_root_hex`
- `peer_hex`
- `receipt_created_at_utc`
- `receipt_hash_hex` (sha256 of canonical receipt JSON)

### 15.5 Storage Policy

- command/receipt envelopes are plugin-domain artifacts (inbox/journal projection),
- do not extend Core ledger invariants for exchange noise,
- anti-replay state is kept in plugin execution journal/state.
