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

### 2.2 Canonical Trading Cycle Port

`BingxFuturesTradingCycleUseCaseService` is the capability-owned application
port for one solo limit-strategy cycle. It composes the existing live-strategy,
order-sizing, WASM intent, and exchange-execution use cases without taking over
their decision, plugin, risk, mandate, claim, queue, provider, receipt, or
reconciliation ownership.

The port accepts one bounded cycle command and returns one explicit prepared,
blocked, or executed result. The exact liquidity event determines the stable
client order id. A cycle cannot prepare an intent without an executable event,
closed-bar evidence, valid sizing, and the existing WASM contract result. When
effect execution is requested, the port MUST delegate only to
`BingxFuturesExchangeExecutionUseCaseService`, which revalidates freshness,
mandate, risk, event claim, and provider outcome.

The `executed` outcome requires both the canonical execution-owner status and
an explicit successful provider result. Provider rejection, exhausted retry,
timeout, missing success evidence, or a contradictory wrapper status remains a
failed effect. A failed provider result MUST NOT confirm the reserved event
claim and MUST NOT authorize recreation through this or another cycle path.

The foreground solo/limit UI uses this port instead of rebuilding the same
cycle in the screen. A future headless host may invoke the same port, but this
contract does not provide a scheduler, daemon, credential transfer, deployment,
lease, or remote authority. Pair-scoped consensus and manual exchange tools
remain distinct foreground actions until a later bounded convergence pass.

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
   - the all-perpetual signal scan prefilter uses the three latest closed 5m candles and admits only strictly rising volume; the forming candle never participates.
4. Recent trades
   - bounded recent market trades, recommended 200+ rows,
   - this sample is recent-flow evidence only and MUST NOT be expanded or
     regrouped into a session profile.
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
   - session taker-imbalance profile for the current and previous session,
   - each profile declares its evidence source and whether coverage is
     complete,
   - incomplete coverage MUST produce `NO_SIGNAL` even when recent flow,
     trend, and whale activation align.

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

- a closed-candle wick crosses a previously established swing level;
- reclaim is evaluated by the bounded microstructure lifecycle in section
  5.3.2, not by a fixed percentage offset.

### 5.3.1 Canonical Hivra Pivot-Cluster Contract

The v1 liquidity detector is an independently specified deterministic
pivot-cluster model:

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
8. Breached clusters become historical evidence only. They do not authorize a
   reverse signal by applying a fixed percentage offset.

Default parameters for v1:

- `liqLen = 7`
- `liqMar = 10 / 6.9`
- `maxTrackedLevelsPerSide = visLiq = 3` (configurable)

Determinism constraints:

- level list must be sorted deterministically before hashing/output,
- class assignment (external/internal) must be derived from active level set only,
- no UI/runtime state may influence level computation.

### 5.3.2 Closed-Candle Sweep/Reclaim Lifecycle

The executable microstructure path MUST be a pure reduction over ordered,
closed 5m OHLC candles. A currently forming provider candle MUST NOT enter the
canonical normalized snapshot, derived liquidity, ATR, or zone decision.

For the side selected by TVH:

1. Start from the structure level established before the recent evaluation
   window.
2. Record a sweep when a closed wick crosses that level. A deeper wick in the
   same active event updates its extreme without creating another event.
3. Confirm reclaim only when a closed candle finishes back beyond the level in
   the intended direction and its directional body is at least `0.5 * ATR14`.
4. Expire an unconfirmed sweep after 8 closed bars.
5. Invalidate it after more than 2 failed close-back attempts.
6. Once confirmed, keep one event anchored to the exact sweep extreme until a
   later sweep starts a new event. Repeated evaluation of identical candles
   MUST produce the same event and zone.

The reducer has no persisted mutable market state. Restart, local execution,
and shadow replay reconstruct the same lifecycle from the same canonical
candle sequence. The zone owner derives a domain-separated stable liquidity
event identity from symbol, side, executable anchor source/lifecycle, anchor
price, and the closed-candle event timestamp. A deeper wick inside an
unconfirmed sweep does not create another event; a later sweep does.

The prepared execution context records the latest closed 5m bar used for the decision.
Immediately before any exchange effect, the existing execution use case MUST
recompute the decision and require the same event identity, same latest closed
bar, exact live-decision hash, side, and zone side. Market movement, a new bar,
an expired/consumed anchor, a side change, or a different event closes the
intent as stale.

Before exchange submission, the existing Capsule-scoped managed-order store
MUST atomically reserve `(test/live, liquidity_event_id)`. An existing claim
blocks retry, double-click, restart replay, reconnect replay, and replacement.
The journal is capped at 256 claims and fails closed when full; it never evicts
a claim merely to authorize another effect. This lifecycle adds no second
order authority or exchange path.

After restart or reconnect, managed-order reconciliation MUST remain read-only
and Capsule-scoped. The existing exchange execution use case owns the decision:

- current open-orders evidence may confirm only an exact locally persisted
  managed `orderId`;
- an absent managed order MUST be queried through the exact provider order
  endpoint by its persisted `orderId`, or by the persisted deterministic
  `clientOrderId` when provider acceptance preceded local order-id capture;
- `NEW` and `PARTIALLY_FILLED` remain active; `FILLED`, `CANCELED`, `REJECTED`,
  and `EXPIRED` become explicit terminal evidence;
- timeout, malformed evidence, unknown status, provider `not found`, legacy
  records without account binding, and account-binding mismatch remain
  `unresolved` and MUST NOT authorize delivery, recreation, replacement, or a
  terminal success claim;
- reconciliation evaluates only locally persisted ownership evidence. It MUST
  never adopt manual, protective, or otherwise unrelated provider orders;
- effect claims remain durable after active tracking ends, and a late result is
  written only to the Capsule that started reconciliation.

The account binding is a non-secret hash of the exact API-key identity. No
credential enters the tracking journal. Test-order validation has no provider
order lifecycle and therefore remains explicitly unresolved rather than being
queried as a live order.

### 5.3.3 Capsule-Owned Bounded Trading Mandate

Every new exchange order effect requires one active, versioned mandate owned
by the selected Capsule. The mandate is capability-owned Trading operational
state, not a Core or Ledger fact and not a generic agent authorization.

The semantic commitment binds the Capsule root scope, exact non-secret BingX
account binding, one symbol, test/live mode, issue and expiry times, maximum
order notional, deterministic risk policy, and maximum effect count. Its
domain-separated SHA-256 identifier is stable for those exact semantics.
Changing any bound field creates a different mandate rather than mutating or
extending the old authority. A mandate lasts at most 24 hours and authorizes at
most 256 effects; the current product surface issues at most 32.
The current mandate action set is exactly the canonical limit/zone lifecycle;
direct or market effects remain blocked because they have no liquidity-event
claim against which the atomic effect budget can be consumed.

The existing Capsule-scoped order-tracking store is the sole mandate-state
owner. The existing exchange-execution use case is the sole enforcement and
effect owner. It MUST verify pause state, Capsule, account, symbol, mode,
validity window, exact risk policy, notional ceiling, and remaining effect
budget before risk work and again immediately before the event claim. The
store atomically binds the claim to the same mandate and fails closed on
revocation, expiry, scope mismatch, or exhausted budget.

`Resume` is an explicit local authorization of the exact displayed bounds.
`Emergency Pause` both disables trading and records revocation; resuming
requires a new commitment. Missing, legacy, malformed, expired, or revoked
mandate state cannot authorize an effect. Restart and Capsule switching do not
renew or transfer authority. Reconciliation remains read-only and cannot
create, enlarge, or renew a mandate.

This contract adds no scheduler, background process, remote lease, credential
transfer, provider route, plugin ABI, Core path, or Ledger fact. A future
headless host must call the same execution owner and cannot convert shadow
evidence into mandate authority.

### 5.3.4 Public Shadow Stream Identity Commit

`BingxFuturesShadowStreamStore` remains the sole owner of runner-only stream
identity and retained shadow evidence. Initial identity binding MUST write one
fixed pending identity, flush it, and atomically rename it to the committed
identity before any evidence can be produced. A restart may complete an exact
valid pending identity for the same runner or replace malformed uncommitted
bytes only while both evidence directories are empty.

A malformed committed identity, a valid pending identity for another runner,
simultaneous committed and pending identities, or any unbound retained state
MUST fail closed without deletion or rebinding. Identity recovery grants no
Capsule, credential, account, mandate, provider, scheduler, or effect authority.

### 5.4 Microstructure Confirmation

- taker-flow imbalance from recent trades:
  - raw quantity delta remains diagnostic only,
  - the directional gate uses the dimensionless notional ratio
    `(aggressive_buy_notional - aggressive_sell_notional) /
    (aggressive_buy_notional + aggressive_sell_notional)`.
- open-interest delta:
  - positive/negative regime relative to prior 3 buckets.
- session volume regime:
  - active session volume percentile vs trailing baseline,
  - a dimensionless notional imbalance supports direction,
  - only complete current/previous session evidence may authorize a signal.
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
  - the public-depth proxy map groups valid same-side levels into deterministic
    5 bps distance buckets around current price, aggregates duplicate notionals,
    and retains at most three ranked clusters per side;
  - ranking may use closed-candle structure proximity, open-interest growth,
    funding crowding direction, and aggressive trade flow, but every retained
    level remains a proxy rather than observed liquidation-position evidence;
  - depth older than 30 seconds, more than 5 seconds in the future, crossed
    against current price, malformed, non-positive, or outside bounded input
    retention MUST NOT produce a liquidation proxy;
  - canonical input permutation MUST produce the same ordered proxy prices;
    proxy-only evidence MUST NOT change exchange-effect eligibility.

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

The Trading UI MUST present executable HTF bounds as a **pending liquidity
zone**, not as current market price. Its existing live-decision projection MUST
show the anchor timeframe/source, formation time, age at the latest closed
observation, signed distance from the reference price, and that `Run Intent`
revalidates the zone. A ranked scan selection may project the matching retained
live decision, but changing the symbol MUST clear that evidence and execution
MUST continue to use a newly computed decision.

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
- bounded depth clusters may rank liquidation-proxy context and activation or
  target areas, but cannot independently select an entry zone,
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
- replacement receives the same deterministic client-id derivation from the fresh liquidity event identity,
- consensus/host preparation and risk governor are evaluated again, while exchange submission still flows only through `BingxFuturesExchangeExecutionUseCaseService`,
- an event already claimed by the original order is cancel-only and cannot create a replacement effect,
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

Risk-history boundary:

- account equity and concurrent positions are read from authenticated BingX
  account endpoints,
- daily realized PnL, consecutive losses, and last-loss time are projected from
  authenticated `REALIZED_PNL` income records, not inferred from the account
  balance summary,
- the normalized 90-day projection is stored atomically inside the active
  Capsule runtime directory and remains outside the Core ledger,
- account-wide loss scope is intentional because manual losses reduce the same
  capital available to the drone,
- incomplete, conflicting, unsupported, unavailable, or unpersistable income
  history blocks live execution; test-order paths may expose fallback behavior
  only for explicit diagnostics.

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

1. Capsule-scoped durable trading control is present and explicitly enabled;
   missing, legacy, malformed, paused, or cross-Capsule state fails closed
2. consensus guard signable for sender peer
3. envelope shape and field validity
4. target capsule match (`target_capsule_root_hex == local capsule root`)
5. TTL validity (`now <= expires_at_utc`)
6. anti-replay (`command_id` not seen before)
7. risk policy:
   - symbol in allowlist
   - leverage <= configured max
   - risk_percent <= configured max
8. optional local intent linkage:
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
- the existing 1.x delivery capability owner durably retains evaluated command
  decisions and incoming receipts before adapter acknowledgement; it is a
  compatibility boundary, not a second exchange-effect owner,
- a failed outgoing receipt retains and retries the exact canonical bytes after
  restart; command policy is not re-evaluated to reconstruct a receipt,
- receipt sender/target/local-peer binding and canonical receipt hash are
  verified before retained state is trusted,
- durable command identity supplies restart-safe anti-replay for the current
  1.x path; a separate plugin execution journal must not duplicate it.

## 16. Remote One-Exact-Order Boundary

The remote runner may execute only a Capsule-signed `one_exact_order`
admission bound to one runner key, one trading mandate, one account binding,
one symbol, one canonical trigger-limit payload, and `max_uses = 1`.

- `ExternalEffectService` remains the sole durable effect lifecycle owner.
- The read-only public-shadow executable has no order-effect imports or routes.
- A separate bounded effect executable is invoked only by the existing host
  lifecycle with transient systemd credentials and a 128 MiB memory limit.
- `delivering` is durable before the provider POST.
- Timeout, interruption, or missing query evidence is `unresolved`, never
  success and never permission for a second POST.
- Live reconciliation uses the exact `client_order_id`; a missing order remains
  unresolved instead of returning `notFound` to the generic retry transition.
- Test-order success proves provider-boundary wiring but not live acceptance;
  a live subaccount order requires a separate explicit operator decision.
- Scheduling, leases, cancellation, leverage/margin mutation, withdrawal,
  transfer, Pair Consensus, AI authority, and multi-symbol execution are out of
  scope.
