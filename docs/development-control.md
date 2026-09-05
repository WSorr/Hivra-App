# Hivra Development Control

Status date: 2026-09-05

## Current State

- Trading HTTP deadlines, retained-session admission, concurrent provider
  reads, and packaged Remote Runner activation are merged at `604bf09`. A
  bounded DOGE live session was accepted by the updated VPS Runner with zero
  exchange attempts before its first scheduled cycle; Android is unverified.
- Current bounded product unit: an untouched timestamped HTF buyside/sellside
  level may authorize one counter-directional pending entry through the existing
  zone decision owner. Sweep/reclaim remains preferred when present. Missing
  timestamps, breached or consumed levels, liquidation proxies alone, and
  internal fallback geometry remain non-executable.
- Maintained runtime: Hivra 1.x.
- Published prerelease: `v1.0.3-test18` at `9cd70cc`; exact macOS and Android
  artifacts have manual signoff.
- Current source baseline: manifest-bound plugin workspaces opened through one
  App Shell navigation path, with Chat UI, Moltbook lifecycle, and the local
  Trading intent route assigned to dedicated capability owners; Capsule
  Analyst is the sole in-app diagnostic AI surface.
- Trading Remote Runner acceptance remains complete at `b88a886`.
- Hivra 2.0 remains design-only. No 2.0 runtime or UI implementation is
  authorized.
- Trading reclaim-only entry and causal cluster evidence are merged.
  Untouched HTF pivots remain observations/targets, not executable entry anchors.
  The existing feature detector now uses confirmation-time ATR rather than
  final-snapshot ATR for historical clusters. Automated validation passes.
  Existing-order revalidation on the operator's experimental subaccount is
  authorized for smoke; new orders, VPS changes and release remain outside
  this unit. Revalidation may cancel anchors rejected by the stricter policy.
  The existing sweep/reclaim reducer now consumes detected cluster evidence;
  window extrema cannot authorize entry. Consumed clusters cannot restart an
  expired, invalidated, or already-reclaimed setup. Automated wiring validation
  passes; retest geometry remains a separate, unselected decision.
  Observation display remediation retains detected clusters on blocked entry
  without populating order fields. Automated session tests now derive blocked
  and ready evidence from successive synthetic candles through the production
  strategy, reach one simulated order, recover its lost receipt by GET, and
  reject recomposition under the retained operation ID. They do not prove a
  deployed offline strategy run. macOS Release observation smoke passed: blocked DOGE entry
  retains both liquidity sides with empty order fields; changing to BNB clears
  the previous snapshot and selecting its scan result shows only BNB clusters.
  Android smoke and deployed offline strategy acceptance remain unverified.
- Current selected runtime unit: readable Trading Remote Runner status through
  the existing restricted status operation. Session counters, scheduled checks,
  and retained cycle outcomes are read-only operational evidence, not execution
  authority. The updated strategy's bounded offline session is paused after
  exposure smoke; live effect acceptance remains unverified. Deployment and
  reactivation require separate approval after the leverage finding is closed.
- The same pending product batch adds a local margin/risk estimate and an exact
  intent review before manual execution. Active mandate symbol/notional restore
  together after restart. Exchange leverage and free margin are read, never
  changed. The pending batch now binds symbol leverage/margin reads into signed
  deterministic authority and enforces the shared risk rule before delivery.
- Packaged smoke observed `60x` isolated leverage with a selected `5%` stop.
  Local exact-order review now rejects a stop outside the nominal leverage
  price buffer and labels cap-only estimates as unsafe. The running remote
  session was paused with zero effects observed in that earlier smoke. Runner enforcement
  in the installed build remains blocked. Pending source changes seal new
  execution with legacy authority lacking exposure read scope, preserving
  retained evidence/reconciliation. Deployment, new authority, and packaged
  acceptance are not yet confirmed; the current mandate cannot imply new scope.
- macOS read-only smoke on 2026-09-05 confirms restored DOGE/8 USDT selection,
  side-specific leverage, available margin, and unsafe SL warnings. No order was
  submitted. The installed Runner reports paused without session-detail support.
  SSH initially reported `inactive/dead` with `UnitFileState=enabled`.
  Operator-approved startup disablement now leaves the unit `inactive/dead`,
  `linked`, with no boot dependency links. Unit registration is retained for
  status/control; no session was started. Remote enforcement and Android
  acceptance remain unverified.

- Smoke follow-up in the same pending batch separates process pause from
  startup enablement in the existing status label. Enabled startup is warned
  explicitly; absent evidence cannot imply a restart-safe pause. This UI-only
  follow-up has not yet received a new packaged smoke.

## Product Direction

Hivra 1.x now converges from an application with embedded plugin products into
a Person Runtime with installable capabilities. The target boundary is defined
in `product-axis.md`:

```text
Core + Ledger
  -> Person Runtime API / Plugin Host
  -> installed Chat, Moltbook, and Trading capabilities
  -> thin App Shell
```

Plugin workspaces are activated by the installed package's exact manifest
profile rather than product-id routing. The App Shell owns the single workspace
navigation decision; the generic Plugins screen owns package/catalog UI and
cannot construct product screens or a second runtime module. The direct
Trading route and the legacy Settings plugin route are sealed, so a workspace
cannot bypass package installation.

Chat remains pair-consensus-bound: the capability screen calls the existing
runtime module, which ensures attestation and passes through the canonical host
consensus guard before the existing delivery owner can send or acknowledge
anything.

Moltbook owns its observation, AI proposal, publication, receipt,
reconciliation, and restart lifecycle in one capability module. New Moltbook
configurations default to one foreground session catch-up; leaving the active
Capsule runtime stops that trigger and clears its process-scoped AI unlock.
Existing saved trigger choices remain unchanged. Trading now
prepares pending liquidity-zone intents through one Capsule-local cycle and
reuses the accepted execution, reconciliation, and Remote Runner owners.
Unavailable equity, realized PnL, or position evidence remains absent and
blocks both test and live execution before the risk governor. The
former peer-selected intent route, Chat signal inbox, and Trading-side Pair
Consensus dependencies are removed. The thin App Shell navigation boundary is
closed without duplicating capability UI or runtime ownership. No runtime unit
beyond the selected Trading work is authorized. Secure seed access failures remain distinct from a missing
seed and cannot open the recovery path; irreversible Capsule deletion verifies
the active native seed, Capsule-scoped secure seed, and known legacy seed
locations before removing local history. A plugin ABI change, universal agent
runtime, new Core fact, V2 UI, release, VPS mutation, or live financial effect
requires a separate decision.

## Authority

1. `product-axis.md` contains the three permanent laws and target runtime
   shape.
2. `specification.md` is normative for the maintained 1.x protocol.
3. A focused architecture or plugin contract owns its capability semantics.
4. This file owns only current state and the next decision boundary.
5. `roadmap.md` is a milestone index; Git, merged PRs, releases, tests, and
   evidence logs retain detailed history.

## Integration Boundary

`main` changes only through a pull request with the required `review-gates`
check. Repository validation and product release remain separate. No tag,
Release, packaged smoke, VPS change, or external effect is implied by a green
repository gate.
