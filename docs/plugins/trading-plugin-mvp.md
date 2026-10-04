# Trading Plugin MVP: Product Brief

Status: accepted product brief; implementation authorized on 2026-09-30.
Current implementation state belongs to `../development-control.md`.
Live exchange effects, VPS mutation, commit, push, and release require their
own authorization. Trading 1.x was retired; this is not a compatibility plan
for it.

## Outcome

A person installs a Trading plugin and immediately chooses either managed VPS
operation or `Trade online` without a server. They connect one exchange account,
choose one instrument, set their own margin per entry, and start trading. The
plugin identifies liquidity lines, places at most one managed entry near a
formed line before a reversal marker under one explicit placement rule, and
shows what the exchange actually did. It never scans a whitelist or selects
another instrument for the user.
For remote mode, the same installed strategy keeps running when the app is
closed. The user does not need Git, a terminal, runner IDs, session hashes, or
manual server cleanup.

This is a trading tool, not a claim of profitable signals. Product acceptance
requires a real, correctly placed order and understandable recovery; strategy
quality is measured separately from actual closed-trade outcomes.

## Minimal User Journey

1. Install a digest-pinned plugin package from the signed source catalog. The
   package contains the strategy; no Trading business logic is compiled into
   the app shell. On first load, offer two clear actions: `Connect VPS` and
   `Trade online`.
2. `Connect VPS` asks for the server address and one-time connection credentials;
   the host provisions or replaces one managed installation without Git,
   terminal commands, runner IDs, or manual cleanup. The plugin never retains
   the server password. If there is no server, `Trade online` selects local
   operation of the same strategy without VPS setup; trading starts only after
   account, instrument, and margin setup. Local operation requires the app to
   remain running and online; it is not presented as 24/7 execution. Switching
   modes does not create a second active trader for the same account and
   instrument.
3. Connect one supported exchange account through a host-owned credential
   handle. The plugin never receives raw API keys. Select one instrument from
   the exchange's current contracts using a searchable list, not a required
   manually typed symbol or a locally maintained whitelist;
   enter the initial margin to use per entry rather than leveraged notional,
   and choose a stop-loss percentage of that margin.
   Read the existing leverage for that instrument and direction from the
   exchange; never change it silently. Show the estimated leveraged notional
   and stop trigger before start, accounting for exchange quantity and price
   rounding. Keep the live or test endpoint visible and never change it
   silently. Waiting for a person to confirm must not impose a one-minute
   button deadline. Recheck current leverage and complete market evidence
   covering the waiting period before sending, without silently changing the
   confirmed price, quantity or stop. If price entered the zone or the evidence
   no longer covers that period, explain why a fresh plan is needed.
4. See the currently formed lines, their side and timeframe, the exact entry
   price and the reason an entry is or is not eligible. No unexplained
   `active` state or hidden confirmation chain.
5. After initial setup, the primary controls are the chosen instrument, margin
   per entry, and Start/Stop. Start, stop, or update with one user action each
   in either mode; do not expose a whitelist, scanner, runner ID, or session
   hash as a prerequisite.
   Keep advanced strategy settings and calculation evidence in optional,
   collapsed sections. Keep the execution mode, connected account, endpoint,
   current trading status, and actionable failures visible without expanding
   diagnostics. Routine operation must not require watching charts or reading
   a table of levels. Exchange notifications complement, but never replace,
   the plugin's reconciliation; a person may manage the order directly at the
   exchange, and the plugin must observe that change rather than recreate it.
6. See the exact provider order ID and current provider state: pending, open,
   partially filled, filled, cancelled, rejected, or unknown. Entry acceptance
   is not reported as a fill, protected position, or PnL.
   Refresh current open orders for the selected instrument and connected
   account inside the plugin. Keep this read-only list distinct from the
   managed entry: manual orders are visible, never automatically adopted or
   cancelled. Failed reading is not an empty list; reopening requires fresh
   provider evidence rather than presenting cached rows as current.
7. Reopen the app or restart the runner. The same order is reconciled, not
   submitted again. Stop prevents new entries but does not cancel a pending
   exchange order or close a position. The existing order stays visible and
   may still fill; its filled position remains managed. Cancel order and Close
   position are separate explicit actions. Never silently presume an order was
   cancelled.
   Uninstall does not cancel provider orders; after reinstall, reconnecting
   the same account allows exact provider reconciliation.
8. While Start remains enabled, repeat the complete trading cycle without
   asking the person to calculate another entry or recreate a session. Start
   authorizes this behavior within the selected account, instrument, margin
   and stop settings; Stop disables new entries and automatic entry replacement.
   After a TP, SL or manual position closure, reconcile the managed position
   and its remaining entry/exit orders before calculating a fresh entry.
   An entry fill is not a completed trade. If no eligible line exists, wait
   visibly and continue observing; do not manufacture an entry to keep trading.

## Strategy Boundary

- Use the 249-line Jack Ventura source at Saint Julia commit `3b81753`,
  published at `https://ru.tradingview.com/script/mJkMc7Ey-jack-ventura/`
  on 2026-09-30, as the chart reference. Later revisions require an explicit
  strategy decision. This source retains the latest 50 alternating confirmed
  swings and forms a line after at least three same-side swings match within
  an ATR(10)-scaled radius. The line price is the last matching swing visited
  by its scan; the midpoint of the highest and lowest matches defines the
  zone center, not the line price. A rendered line may update as new swings
  arrive, including after a breach. Its drawing is backdated to the earliest
  matching swing, but it first becomes knowable only when the third match is
  confirmed. Use that first-known time and observed price for decisions, never
  the backdated origin or a later revised drawing. No order may be justified
  by a level that was only knowable after the proposed order time.
- JackV has two different observable events. A formed, unswept line exists
  before price reaches it. A reversal marker is emitted only after a sweep
  beyond the zone boundary and the first confirmed close back across the line
  while its sweep remains active, possibly on the breach candle. The marker is
  too late for the selected entry approach and must not trigger an order. It
  remains useful only as observational evidence. Its plotted midpoint of the
  shaded sweep is not an executable entry price.
- The entry is one pre-positioned limit order at the selected confirmed line,
  rounded to the exchange's price tick without moving it past the line toward
  current price. It uses only levels known when the order is placed.
  JackV draws the shaded sweep area only after a breach; that future box cannot
  be used as a pre-sweep input. Do not add an arbitrary percentage offset. If
  the selected line moves before touch, or fresh JackV evidence shows it is
  no longer an eligible line, reconcile its pending order and cancel the
  unfilled entry. Confirm cancellation and zero executed quantity before
  recalculating and placing a replacement from fresh market/account evidence.
  If no eligible replacement exists, wait without an entry. An unchanged
  eligible line keeps its existing order; a nearer alternative alone does not
  cause cancel/recreate churn. If any amount fills, including during a cancel
  race, manage that position instead of replacing the entry. Missing or
  ambiguous cancellation evidence is not permission to place a second order.
  Past pivots used
  to form the line are not entry events. If price passed the intended entry
  after the level first became knowable but before placement, do not chase or
  backfill that entry. Entry eligibility belongs to the whole formed zone,
  not just its line: buyside is captured when a subsequent high reaches its
  lower boundary; sellside is captured when a subsequent low reaches its upper
  boundary. Boundary equality counts. Closed history, the live candle and
  the final delivery check use the same criterion; a close, reversal marker
  or retest is not required. Capture is retained after price leaves the zone
  and across restart; a later redraw must not rearm a captured zone.
- Buyside corresponds to a short opportunity and sellside to a long only
  under the selected entry policy. Run the same current-chart algorithm
  independently on `1D`, `4H`, `1H`, `30M`, `15M`, and `5M`; JackV itself does
  not choose between timeframes. Evaluate only the instrument explicitly
  selected by the user: no whitelist, market-wide candidate search, automatic
  symbol switching, or ranking across instruments. When there is no active
  managed entry, inspect fresh, complete evidence for all six timeframes and
  select the nearest line in a zone that price has not entered since it became
  knowable. The entire zone must remain ahead of current price on the appropriate
  side. A captured zone is excluded; continue choosing among the other
  timeframes. Break ties by higher timeframe, then earlier first-known time,
  then stable zone identity. Do not switch away from a valid pending entry or
  an open position. An invalidated unfilled entry may be replaced through the
  reconciled cancellation flow above; no higher-timeframe veto is added.
  Saved line-only evidence is not proof that its surrounding zone is untouched:
  reinspection must cover its first-known time before it becomes eligible.
  If the bounded provider history cannot prove that period, show the zone as
  unverified rather than inventing freshness. This recovery concerns only
  historical plugin state; it does not change a managed order's fixed plan.
  Reinspection or replacement of that saved zone ends its line-only state;
  there is no legacy eligibility fallback.
  Each refresh reconstructs all six frames from the existing bounded provider
  window, so corrected historical candles cannot trap calculation behind a
  saved candle cache. Retained capture/consumption marks survive reconstruction
  and interruption; its temporary checkpoint ends when that frame is complete.
  Partial reads cannot make a zone current or change a managed order's plan.
- After an entry fills, the profit-taking exit targets a confirmed opposite
  JackV liquidity line on the profitable side of entry and closes only the
  filled position quantity. Choose the nearest eligible opposite line already
  known at fill, with its zone still ahead of current price and uncaptured
  since first-known time, and keep that target price fixed once placed. If none exists, keep the
  position protected and visibly show `No profit target yet`; place the exit
  at the first later opposite line that is still ahead of price and untouched.
  No independent TP-zone calculator or abstract R-multiple target is part of
  the strategy.
- The user chooses one stop-loss percentage of their entry margin, not a
  percentage move in market price. After a fill, derive the protective stop
  trigger from the actual average fill price and filled quantity. For a
  partial fill, scale the margin and loss budget to the filled portion. Place
  the protective exit with the exchange so it remains active when the app is
  closed; an unconfirmed stop is shown as unprotected, not silently accepted.
- Both local and remote execution continuously reconcile the managed trade
  and update JackV lines from new closed candles, using current price for
  touch evidence. After a position closes, confirm no remaining entry can
  reopen it and reconcile or cancel obsolete managed exits before rearming.
  The next entry uses newly calculated zones and account data, not the previous
  plan or a consumed/touched line. Its durable identity is distinct from the
  completed trade. TP/SL closure does not require a new user session while
  the existing trading authority remains valid. Restart resumes reconciliation
  of the current lifecycle before evaluating another entry.
- Each candidate carries symbol, timeframe, side, line price, first-known time,
  placement time, invalidation condition, and stable zone identity. Its
  decision must be reproducible from the exact exchange candle input and
  settings used by the running plugin. No order-book, volume, or AI filter is
  added without a specific product finding.
- The current JackV source is a rewrite of the zone engine and is published
  under the user's account. Older published revisions attributed their
  source-derived engine to LuxAlgo. Do not describe the current file as still
  carrying that old header, but also do not infer legal clearance from a
  removed header alone. Preserve the source provenance for release review.

## Ownership And Effects

- Source for the trading WASM package belongs in `hivra-plugins`. The plugin
  owns all Trading business logic: JackV zone formation, timeframe and
  candidate selection, entry price and quantity, margin sizing, stop and
  profit-exit calculations, and the trading state machine. It interprets
  provider evidence to decide whether to wait, replace, protect, or close its
  managed order or position, including after restart. Its bounded state must
  explain those decisions.
- The existing host remains the owner of installation, Capsule selection,
  credential handles, public market-data acquisition, bounded storage, and
  exchange effects. Provider adapters fetch candles, instrument constraints,
  leverage, orders, and positions; normalize provider evidence; and sign and
  send explicitly permitted requests. The host checks authority, account
  scope, request validity, and operation identity. It must not select a zone,
  calculate Trading prices or quantities, interpret Trading state, or run a
  fallback strategy. Core and Ledger do not gain Trading-specific types.
- Use the existing bounded WASM input/output execution model. Each invocation
  receives market and provider snapshots, user settings, explicit observation
  time, and the plugin's saved state. It returns its next state, presentation
  data, and requested effects. The host persists state and durable request
  results and supplies them on the next invocation. The scheduling loop
  belongs to the execution host; trading transitions belong to the plugin.
  Raw credentials, direct network access, and arbitrary filesystem access
  remain outside WASM. This journey does not require unrestricted host imports.
- The journey requires market/account snapshots, order effects, state
  persistence, remote execution, and a package-defined workspace. Implement
  only the narrow host boundaries needed by this journey through the existing
  runtime and effect ownership; do not restore retired Trading services or
  build a general agent framework. Availability belongs to the current status
  document, not this product contract.
- The plugin package declares its settings and actions; WASM returns its
  current view data and explanations. The App Shell renders those through a
  reusable bounded workspace and dispatches user actions to the plugin.
  System credential and VPS connection dialogs remain host-owned. No
  dedicated Flutter Trading screen may calculate decisions or contain a
  second trading workflow. Installing the package must add its workspace;
  changing strategy behavior or its supported settings must not require an
  App Shell rebuild within the supported host contract.
- A remote executor, if used, runs the same verified strategy package and
  exact WASM module digest as the app through the same input/output contract.
  It supplies scheduling, storage, credentials, and provider adapters around
  that module. There must not be separate Dart and VPS strategy implementations
  or two active executors able to place the same order. Local and remote modes
  differ only in where that one strategy runs, not in its decision semantics.
- Exactly one durable operation identity binds candidate, account, provider
  request, and result across retry/restart. Before any retry after uncertainty,
  query the provider for that exact operation. Missing evidence is `unknown`,
  not permission to submit another order.
- Confirmed pre-dispatch failure offers fresh zone/account calculation and a
  new explicitly confirmed plan, without deleting its historical journal entry.
  Identity binds the complete immutable plan, not just the zone. Unknown or
  dispatched entries cannot be replaced through this recovery action.
- One managed installation per MVP VPS/account. Provisioning must not alter
  unrelated services such as an existing website or VPN. Updates replace
  atomically;
  remove obsolete runner packages and session scratch state automatically,
  retaining only the active package and at most two prior packages.
  Multi-user and multi-account VPS isolation are not part of this MVP.

## Necessary Limits, Not Process Gates

The user chooses initial margin per entry in account currency and a stop-loss
percentage of that margin. The host supplies the exchange's current
side-specific leverage and instrument constraints; WASM derives target
notional, rounded quantity, and stop price. For example, 1 USDT at 50x
targets about 50 USDT notional before rounding and fees. A 20% stop targets
roughly 0.20 USDT loss on a fully filled entry, not a 20% market-price move.
Neither amount is a guaranteed maximum loss: fees, slippage, liquidation, and
cross margin can change the realized result. Do not silently increase the
user's margin to satisfy exchange minimums. Enforce one active managed entry
for the selected instrument and explain when its minimum cannot fit the
entered margin. These are runtime safety properties; they do not justify a
stack of approvals, shadow protocols, synthetic mandates, or repeated release
candidates for a small test account.

## Acceptance Evidence

- Fixed chart examples show when each line first became knowable, how its
  displayed price changed, which snapshot justified the order, and which
  pre-sweep prices were actually eligible. Compare the placement rule with the
  current JackV source on matching exchange candles; include conflicting
  timeframes.
  A later reversal marker is recorded separately, not counted as an entry.
- A packaged macOS and Android build installs the same plugin and shows the
  same decision for the same candle snapshot. No second Trading UI/strategy
  path exists in the host. First load offers VPS setup and `Trade online`; a
  user without a server can trade locally without seeing VPS internals.
- Update the plugin's strategy or a supported setting through a new verified
  package while keeping the macOS/Android App Shell binaries unchanged. Its
  workspace and decisions must update from the package. Local and VPS
  execution of the same module digest, inputs, and saved state must produce
  the same decisions. Removing the module leaves the host unable to calculate
  Trading decisions or originate new strategy entries; durable request
  receipts and read-only provider reconciliation remain available.
- With a deliberately small live test account, the selected entry event
  causes one actual provider order at the specified price. Verify its exact
  provider state independently of UI counters. If the event does not occur,
  record `no trade`; a fixture is not substituted for a live effect.
- On the selected instrument only, verify that the entered margin, the
  exchange-reported leverage, and the actual order quantity match the displayed
  estimate. A filled entry exits at the eligible opposite line rather than an
  R-multiple target; the exit never opens a reverse position. Verify the
  exchange's protective stop against the chosen margin-loss percentage and
  actual fill, including a partial fill and app closure.
- App close/reopen and remote restart do not duplicate the order. A stop or
  plugin update does not orphan a live order, and the user can see its state.
- Fresh candles that move or invalidate a pending line cause a reconciled
  cancellation and at most one replacement, without a second live entry.
  Exercise a fill during cancellation and an ambiguous cancellation result.
  After confirmed TP/SL closure, the enabled strategy recalculates and places
  the next eligible entry without manual restart; no eligible line means wait.
- Remote mode continues while the app is closed. Repeated updates do not
  accumulate unbounded runner directories or require manual server cleanup.
- Local mode stops making new decisions when the app is not running; reopening
  reconciles its existing provider order before any new entry.
