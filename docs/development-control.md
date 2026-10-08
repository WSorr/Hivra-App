# Hivra Development Control

Status date: 2026-10-08

## Current State

- Hivra 1.x is the only maintained runtime; Hivra 2.0 remains design-only.
- Current source is protected `main`. The latest published prerelease is
  `v1.0.3-test21` at `8e5c136`.
- The prepared but unpublished `v1.0.4-test1` candidate is based on runtime
  source `1d48082`; its GitHub tag and Release do not exist yet. Exact macOS
  and Android artifacts still require the matching manual signoff rows before
  release.
- The macOS runner enforces one running Hivra bundle instance: a duplicate
  launch activates the existing process and exits before Flutter/Capsule
  initialization.
- Core, Ledger, FFI, the WASM host, and one Flutter App Shell remain the
  runtime.
- External-package admission hardening is complete: ZIP with a manifest is the
  only installable format; legacy raw modules remain removable but cannot
  bind or execute. The sandbox boundary is specified in specification section
  5.2.3 (WASM Plugin Host Contract); no OS/process isolation is claimed.
- External plugin package versions are independently replaceable when the host
  ABI, contract, capability policy and catalog trust root remain unchanged.
- Chat and Moltbook are the maintained installed product capabilities.
- Trading 1.x was retired in `d1b6581` (#335). The user selected a new
  installable Jack Ventura WASM plugin under `plugins/trading-plugin-mvp.md`.
  Its installed WASM observation workspace passed macOS packaged smoke:
  BTC and XRP calculations across six timeframes, instrument replacement,
  invalid-input recovery, and unchanged saved state after process restart.
  The instrument field now uses a searchable exchange-backed choice instead
  of manual symbol entry. Its updated macOS packaged smoke passed: live
  instrument loading, case-insensitive search, XRP-to-VET replacement with
  old results hidden, six-timeframe VET calculation, and unchanged saved
  selection and state after a full restart of the final choice-enabled binary.
  Reinspection after restart also passed. Failed instrument loading and
  cancellation preserved the previous selection.
  The workspace now adds a host-only BingX LIVE connection and a WASM quantity/stop
  preview using the user's margin and existing exchange leverage. Advanced
  settings and calculation details are collapsed; account, status and errors
  remain visible. Focused boundary/widget and Rust sizing tests passed.
  The rebuilt package also passed the macOS artifact's actual WASM runtime:
  six-frame fixture calculation, sizing/stop preview, and unchanged reopen.
  Packaged macOS account/restart smoke passed on binary `8c9e3548` and local
  plugin archive `7f49da89`: live VET account connection, exchange leverage
  sizing, unchanged saved state on reopen, and a fresh private account read
  using saved vault credentials after a full process restart. Capsule activation
  required the user's Keychain confirmation. No credentials were present in
  WASM state; that smoke sent no order.
  Source now connects one explicitly confirmed PostOnly limit entry with an
  attached stop request to the existing external-effect journal. WASM owns
  the plan and managed-order state; the host owns signing and exact provider
  reads. Focused tests cover uncertain delivery without duplicate POST,
  package/grant changes, exact large order IDs, partial fill/cancellation,
  restart and retained receipts after uninstall/reinstall. Current-candle
  sweeps and the final pre-delivery quote are checked in WASM; historical
  candles cannot touch a line before its first-known time. Binary `ad3db9de`
  and archive `fb131622` passed the actual packaged WASM fixture journey,
  including higher-timeframe ties, final-quote rejection and partial-fill
  reopen. Flutter 786/786, Rust workspace, plugin Rust 19/19, analyze and
  review gates passed. Subsequent live preview returned a signature rejection
  (`100001`). The host now sends parameters in the same sorted order used for
  signing; a wire-order regression test covers private reads. Entry delivery
  also rereads directional leverage without changing it, and exact order
  reads reject the opposite position side. Focused 15/15 and analyze passed;
  rebuilt binary `2c4524f2` passed signature verification and live private
  reading with the saved account credentials. The refreshed WASM preview was
  VET long on 30M at `0.008739`, quantity `8582`, exchange leverage 75x,
  estimated margin `0.999975` USDT and stop `0.008716`. No raw credentials
  were present in plugin state. The user approved the package's new order
  permissions; archive `fb131622` was updated in place without replacing
  the saved account or instrument. Live preparation on binary `2c4524f2`
  produced a VET long 5M limit at `0.008708`, quantity `8612`, 75x leverage,
  estimated margin `0.999911` USDT and requested stop `0.008685`. The host
  confirmation dialog was reached, but two delayed confirmations expired
  before any journaled delivery. The minute-long confirmation window is now
  replaced by a bounded 48-hour history window: final WASM validation requires
  continuous 5M evidence covering the entire waiting period, a current candle,
  and no touch of the confirmed line. Confirmed price, quantity, stop and
  operation identity do not change. Round-trip float parsing preserves the
  exact fractional plan across reopening. Validation reuses bounded candle
  batches without increasing WASM fuel or changing Core/FFI. Rust 21/21,
  focused Flutter 16/16 and analyze passed. Archive `a443ef7b` passed the
  packaged WASM engine with a two-hour confirmation delay, unchanged plan,
  missing-history/touch rejection and no duplicate request on reopen.
  Interactive delivery found two pre-POST parser failures: wrapped open-order
  evidence and the position-mode string documented by BingX. Both are fixed
  in the existing adapter; exact boolean/string modes are accepted and unknown
  values remain non-dispatch. Such failures now persist as `entry_not_sent`,
  not uncertain delivery, and explicit retry retains the same plan and client
  order ID. The single old misclassified test record was repaired with user
  approval and local backups, without sending an order. Restart restored the
  correct not-sent state. Plugin Rust 22/22, focused Flutter 46/46, analyze,
  and signature verification passed. Current macOS binary is `6a37a441`,
  with installed archive `b18fa976`. Live preflight now passed position-mode
  and leverage reads, then rejected the unchanged VET long entry because price
  had passed `0.008708`; fresh market evidence was below the entry. No provider
  POST or order receipt occurred. Recovery still needs a usable fresh-plan
  action after confirmed non-dispatch, rather than only retrying the old plan.
  Fresh-plan recovery is now implemented in the same WASM entry owner and
  host journal path. Confirmed non-dispatch offers `Recalculate entry`; all
  six frames and account data are reread, the old operation stays historical,
  and reopening does not restore it over the fresh draft. Unknown/dispatched
  entries remain managed. Operation identity now binds every immutable plan
  field, avoiding collisions when the same zone is recalculated. Rust 23/23,
  focused Flutter 47/47, analyze and the actual macOS WASM engine passed.
  Binary `a67645a5` and installed archive `f0ba8369` passed interactive recovery:
  VET recalculation reread six frames and the saved account, prepared a 4H long
  at `0.006554` with quantity `11443`, 75x leverage, margin `0.999966` USDT and
  requested stop `0.006537`. Reopening the workspace preserved byte-identical
  state and journal; the old not-sent operation remained historical. No new
  provider POST occurred. The user's subsequent confirmation also stopped
  before POST because BingX returned a nonempty open-order list. That binary
  did not validate row symbols or order IDs, so the claimed VET conflict is
  not yet independently established. Source now validates both and identifies
  an exact conflicting order; mismatched or malformed responses remain
  non-dispatch without being mislabeled as a VET order. Focused Flutter 48/48,
  full Flutter 792/792 and plugin Rust 23/23 passed. Rebuilt macOS binary
  `2f48749807ad8d7581f6a24e2fb78a6a82395182ec7a7201288814d781bfbbd5`
  passed signature verification and restart/reopen with installed archive
  `f0ba8369`; workspace and effect journal remained byte-identical. The old
  build was closed before rebuilding, and only the new process is running.
  The workspace implementation now offers a transient selected-instrument open-order
  list through the same account-bound parser used by entry preflight. It does
  not adopt manual orders, store another order history, or mix previous delivery
  errors into the current observation. The packaged WASM engine passed 0/1/16/32/64
  synthetic rows against the saved workspace, with unchanged strategy state and
  no effect requests. Parsing and table serialization were simplified to fit
  the unchanged 5,000,000 fuel budget. At the user's request, the common runtime
  memory ceiling is now 128 MiB per invocation; other resource limits and rights
  are unchanged. Runtime 4/4, FFI 104/104, plugin Rust 25/25, full Flutter 795/795
  and analyze passed; the final read-only host adjustment passed focused Flutter
  24/24. Current macOS binary is `65be126a`, installed local archive `ee2ff383`;
  signature verification passed. First live reading returned zero open VET-USDT
  orders for account ending 0870. It also exposed an unwanted JSON state rewrite;
  the read-only route now neither applies returned state nor persists it, including
  its revalidation continuations. A regression covers reordered rendering output.
  Final packaged repeat returned zero open VET-USDT orders for the same account.
  Closing and reopening the workspace restored the saved trading plan without
  reusing the transient list as fresh evidence. Workspace and effect-journal
  files remained byte-identical through the repeat and reopen. Nonempty lists
  are covered by packaged synthetic fixtures, not live provider evidence.
  Exchange orders are neither cancelled nor adopted by this observation.
  The next live-entry preparation exposed WASM fuel exhaustion with retained
  six-frame state and 48-candle batches, before any provider POST. The existing
  host streaming path now uses 12-candle batches for market refresh and final
  entry validation, without raising fuel or changing strategy semantics.
  Exact-state parity across batch sizes and complete ordered host streaming
  passed; all six live public histories passed the packaged WASM engine with
  the retained workspace. Full Flutter 795/795, focused 24/24, plugin Rust
  25/25 and analyze passed. Corrected macOS binary `f56deae8` passed signature
  verification and interactive preparation after the old process was closed.
  The unchanged installed WASM prepared a VET long on the untouched 15M
  sellside line at `0.008688`, quantity `8632`, 75x exchange leverage, margin
  `0.99993088` USDT and requested stop `0.008665`. A fresh account-bound list
  returned zero open VET orders; returning from the list preserved that plan.
  The user's confirmation on binary `f56deae8` stopped before POST: the second
  final-validation batch still exhausted fuel with 24 candles and canonical
  JSON. Operation `977d73db` is journaled as `entry_not_sent`, with no receipt.
  Twelve-candle batches passed the actual WASM engine through all six frames,
  preparation, placement request, complete final validation, synthetic order
  observation and reopen using canonical host input; the plan stayed exact.
  Corrected binary `63d07e48` passed signature verification and the live path:
  after the user's confirmation, operation `91e06670` completed one delivery
  attempt with BingX order `2105918659918786560`. Exact account-bound GET and
  a separate refresh both confirmed the VET long limit open at `0.008688`,
  quantity `8632`, with zero filled quantity. Workspace close/reopen restored
  the same order; the effect journal stayed byte-identical through refresh
  and reopen. This proves submission and exact-order observation, not fill,
  verified stop protection, PnL or full application-restart recovery.
  Source now removes the adapter's hardcoded final `5M/600` strategy read:
  the installed package requests its own final evidence through the existing
  validation action. The same host tests passed `5M/600` and `15M/49`, plus
  denied/foreign/nested evidence and package replacement without a POST.
  Focused Flutter 24/24 and plugin Rust 27/27 cover final evidence, opaque
  private state, multi-record recovery, package/grant/Capsule changes during
  recovery, and failed exact-order reads without state loss or another POST.
  The new WASM
  also preserved the saved order and completed 50 canonical validation batches
  through the unchanged packaged FFI engine with synthetic market evidence.
  Recovery now belongs to WASM: the host verifies the requested account and
  streams its durable journal without choosing a plan or reading private state.
  The unchanged packaged FFI engine recovered the exact saved VET plan from
  four real journal records, then ignored nine synthetic trailing rejections,
  without provider calls, invented observations or writes to the saved files.
  Four records per invocation exceeded the existing fuel limit with real
  state; one record per invocation passed without increasing runtime limits.
  Pending-line comparison passed on macOS binary `21c21cc9` and local Jack Ventura `0.1.2`
  archive `3c21b389`. The update from `0.1.1` changed only the package,
  not Capsule, FFI, capabilities, or host code. Installation preserved
  byte-identical workspace and effect journal. The same entry and observed
  provider identity survived full application restart.
  `Refresh order and zones` now asks the existing host for one exact-order
  read and six market histories. WASM compares the original plan's line,
  timeframe, origin and first-known time; a nearer alternative does not
  replace it. Missing/moved/touched lines, stale or incomplete evidence, and
  any filled quantity do not authorize another entry. Partial market batches
  do not expose a current-line verdict. Full tables are rendered only after
  the managed refresh completes, avoiding fuel exhaustion without raising
  resource limits or changing the host's twelve-candle stream.
  The unchanged packaged FFI engine passed 309 invocations on all six live
  VET histories with the saved plan, without effects or saved-file writes.
  Live UI reconciliation confirmed order `2105918659918786560` open at
  `0.008688`, filled quantity zero, and the original 15M sellside line still
  present at its exact price and untouched. The journal stayed byte-identical.
  Full process restart retained that new state and displayed its observation
  age, requiring a fresh check instead of treating cached validity as current.
  A fresh post-restart private reread then confirmed the same open order,
  zero filled quantity and unchanged original line, without journal changes.
  The current host no longer chooses the package's private preparation action
  or binds credential/effect authority to private action names. Root WASM
  output selects one bounded `resume_action` after permitted reads; nested
  requests, chained continuations, and unconfirmed effects are rejected.
  The explicit `workspace.continue` capability seals the superseded private
  workflow without a compatibility fallback. Existing tests exercise arbitrary
  preparation, connection and submission names, opaque state, package/Capsule
  changes and grant revocation. The entry journal and exact-plan approval
  remain the sole effect path; no owner, service or execution path was added.
  Current macOS binary is `6b64ac63`, installed Jack Ventura `0.1.3` archive
  `d067c336`. The old process was closed before rebuilding; the packaged FFI
  is unchanged. Installation and workspace reopen preserved byte-identical
  state and journal, including order `2105918659918786560`. The packaged WASM
  engine completed a synthetic seven-read preparation, package-selected
  continuation and exact-plan reopen in 26 invocations without provider calls
  or saved-file writes. The live exact-order/zone refresh on the new build
  confirmed the same open VET order, zero filled quantity and unchanged,
  untouched original 15M line. Workspace close/reopen retained byte-identical
  refreshed state and journal; aged line evidence required a fresh check.
  The generic busy message now explains the pending system permission prompt
  instead of claiming settings changed; widget and packaged UI checks passed.
  Provider-specific confirmation presentation remains an unresolved boundary.
  Host verification: Flutter 795/795, focused 27/27, analyze and Rust workspace
  passed. Current plugin Rust 31/31, manifest validation, package build and
  both repositories' whitespace checks passed.
  That packaged binary has no autonomous loop, fill-based protection or
  opposite-line exit. Local cycle source work is described in the active outcome
  below, not claimed as packaged acceptance.
  Android packaged smoke, the complete exchange lifecycle, and remote operation remain
  incomplete; this is not yet a finished Trading drone.
- Chat delivery is cross-platform and restart-safe; conversation UX,
  notifications, and attachments remain incomplete.
- Moltbook Assisted publication is release-proven. Bounded natural-news code
  is merged, but automatic publication and reply are not yet reference-grade
  on a packaged build.
- Capsule-scoped credential stores remain authoritative. AI unlock is
  process-scoped.
- The Flutter 3.47.4, Dart 3.13.3, Xcode 27, and Swift Package Manager
  baseline remains authoritative.

## v1 Outcome: Installable Jack Ventura Plugin

### v1 Closure Boundary

As of 2026-10-07, the maintained v1 product is closed at a medium product
result. Jack Ventura is an installable signed WASM capability with one
user-selected instrument, host-owned credentials, a managed local or VPS
executor, one durable effect journal, provider-scoped order reconciliation,
Stop semantics, package replacement, restart recovery, and bounded VPS
installation. This is the product users can operate without Git, a terminal,
runner IDs, or manual server cleanup.

This closure does not claim profitable strategy behavior or full autonomous
trade performance. Live fill-to-confirmed-closure-to-reentry evidence remains
an explicit experimental limitation, not a release promise. No further v1
strategy filters, confirmation layers, alternative runner, or Trading host
workflow may be added under this outcome. Any later live experiment must use
the existing package and executor path and replace this status only with
actual provider evidence.

The user accepted the current single-entry evidence as sufficient for advancing
on 2026-10-02. Continuous VPS operation and reentry remain experimental
follow-up evidence, not another mandatory v1 development pass.
Do not tune strategy selection or add signal filters during this outcome.
Calculation is not an obligation to place an order at start or on every cycle.
One Start enables observation and the authorized trading lifecycle for the
selected account, instrument, margin and stop settings; Stop disables new
entries. The user must not recreate a session or manually prepare each entry
after a TP, SL or manual closure while that authority remains valid.

The execution boundary is:

```text
host market evidence + saved plugin state + user action
  -> installed WASM decisions + next state + bounded workspace
  -> host presentation, persistence, and permitted provider operations
```

Exit evidence:

1. one managed VPS executor runs the same pinned WASM module while the app is
   closed; the host schedules and supplies evidence, but does not implement
   trading transitions or private package commands;
2. the cycle distinguishes pending entry, partial fill, open position and
   confirmed closure, with exchange-side protection and the accepted
   opposite-line profit exit; an entry fill alone cannot rearm trading;
3. after confirmed closure and reconciliation of remaining managed orders,
   WASM refreshes zones/account data and may request a distinct next entry;
   no eligible entry means visible waiting, not a fabricated trade;
4. runner restart, uncertain provider responses, Stop and package replacement
   do not duplicate an entry or lose its managed lifecycle; the UI reflects
   actual executor health and retained observations, not merely saved intent;
5. provisioning and updates use one managed installation without accumulating
   runner/session directories or touching unrelated website/VPN services.

Strategy profitability and an order on every cycle are not autonomy acceptance.
Missing PnL alone must not prevent reentry when position closure and remaining
order evidence are conclusive; missing closure evidence must not enable it.
Existing exchange orders are observation evidence, not permission to cancel
them or create another. Live orders, VPS mutation, commit, push and release
still need their own authorization. The retired Trading runner must not be restored.

Server execution remains in progress. The standalone workspace process now
uses the same executor and installed WASM through a WASM-only build of the
existing FFI, without Capsule, Ledger, Keychain or transport dependencies.
It restores the existing host grant without requiring a provider response at
startup, accepts package/Capsule-bound commands over a private Unix socket,
and refuses a second process for the same data directory. Process health and
unavailable exchange observation are separate results. The actual compiled
macOS process with local Jack `0.1.9` passed handoff, timer, restart, exact
replay, singleton and unchanged grant/state/journal checks using isolated
synthetic data only.
The process timer exercised read-only `open`, not a live trading cycle;
no exchange request or order was sent by that process smoke.
Those synthetic checks are not live exchange lifecycle evidence.

Handoff uses the existing host grant to bind execution to
local or one explicit VPS identity, without renewing its expiry or copying
credentials into package state. The source drains actions and remains detached
after restart or local package removal. The destination atomically adopts
opaque workspace state and the canonical effect journal into an unused
workspace. Exact replay acknowledges without restoring older files, renewing
expired authority or undoing Stop. One staging directory bounds interrupted
imports; no second strategy, effect journal or execution owner was added.
Pre-field local grants are read as local only for existing 24-hour grants;
remove this default when those stored grants are no longer supported.
Executor identity must be established independently by authenticated host
transport, not trusted from the incoming checkpoint alone.

Source adds native package setup through the existing
Registry, without creating execution authority. Exact reinstallation preserves
the package binding, opaque state, grant and effect journal; setup refuses a
running installation or silent package replacement. Before adoption, status
reports process health without initializing WASM state. Direct VPS admission
does not briefly arm a local timer or claim remote running status. Focused
tests and the actual compiled macOS process with Jack `0.1.9` passed these
isolated setup/reinstall/handoff/restart checks; no live provider effect occurred.

Capsule source now connects workspace packages through one host-owned SSH
transport: pinned server identity, verified bundled Linux artifact, one fixed
installation and a restricted Capsule-held key. Root credentials are used only
for installation. Start, Stop and observations route to the existing executor;
return to local ends remote authority before restoring opaque state/journal.
Package update first returns authority; uninstall also removes remote credentials
and managed server data. Lost adoption acknowledgements do not permit local fallback.
Local tests cover this journey with independent package state and distinct
Mac/server package IDs, including retained Stop intent after a disconnected
request. Flutter 809/809, analyze and the compiled macOS runner with Jack
`0.1.11` passed setup, handoff, timer, restart and replay checks without network
effects. Current Ubuntu CI `37196644177` passed for source tree `373dfbb6`
matching host commit `d41fbc0`; runner archive digest is `ff4b5ee0774ce6e2`.
The full macOS binary `f058e76c` provisioned that runner and exact installed
Jack `0.1.11` archive `a8e11012` through Capsule on Debian 13 x86-64.
With Capsule closed and the user-approved DASH grant active, the server
cancelled invalidated order `2106427247753916416` and submitted replacement
`2106703408299995136`, one journaled attempt each. Subsequent normalized
provider evidence identified the replacement as open with zero fill.
Reopening Capsule restored the server lifecycle. Stop disabled new entries;
return to online sealed all server authority (`expires_at_ms=0`) and retrieved
the same order and journal without starting local cycles or cancelling the order.
Jack `0.1.12` then replaced `0.1.11` in the unchanged Capsule binary and retained
that managed order. Package-owned wording no longer falsely calls VPS cycles local.
nginx PID and the two Amnezia container IDs remained unchanged; installation
uses the fixed managed directory rather than per-session runner copies.
Live fill/protection, profit exit, closure/reentry and loss-of-response recovery
remain unobserved; no full autonomy or release acceptance is claimed.
Repeated VPS selection now uses the saved restricted key and existing setup
operation, without a root-password prompt or trading Start. The rebuilt macOS
binary `81f92dc9` updated the server to the same Jack `0.1.12` digest `6db7399b`
without replacing the native runner or executor identity. Failed reconnection
does not select a new target; provider credentials stay in the host store.
Focused 38/38, full Flutter 810/810, analyze and review gates passed.
Native runtime update is now exposed separately in advanced settings through
the same installer. It returns opaque state and ends VPS authority before root
installation, preserving the managed order and journal. Failed return blocks
installation; failed installation does not hide acknowledged authority return
or grant another Start. Success, cancellation and both failure paths passed
widget tests. Packaged/live update smoke remains pending; no new owner or route.
The user then authorized DASH VPS cycles on `0.1.12` until
2026-10-05T11:40:28.312Z. The first completed cycle at
2026-10-04T11:42:16.219Z reread order `2106703408299995136` as open with zero
fill, reported no cycle error, and added no effect-journal attempt. Capsule
displayed the same successful-cycle timestamp. This does not prove a fill,
exchange-side protection or closure/reentry.
Strategy, workspace execution and effect owners remain one each.

The local `0.1.13` candidate now allows a new opposite-line exit for a freshly matched
remaining position after the previous exit is conclusively terminal. WASM
owns that transition and sizing; the existing host journal checks the exact
previous provider order before admitting another exit. Active, partial,
unavailable or mismatched prior evidence still prevents duplicate delivery.
The host admission fix needs a matching canonical native build; replacing WASM
alone cannot remove the old native runner's permanent exit prohibition.
This source change is not installed on VPS and does not prove live closure or
reentry. Cleanup of still-open obsolete exits and conditional-stop verification
remain outstanding; no additional owner, capability or execution route was added.
Validation: Jack Rust 62/62, Flutter 810/810, both Rust workspaces, analyze and
review gates passed. The compiled WASM ran terminal/open/partial exit scenarios
inside the unchanged sandbox with synthetic evidence and no provider effects.
Exact dispatched-exit replay also survived lost private state and unavailable
older provider history without another POST; removal/replacement during the
prior-order read prevented delivery. The live runner remained active with no
restart; no package, grant or exchange order was changed by this validation.

The same local candidate now adds automatic closed-lifecycle retention in the
existing effect journal: last five confirmed groups, plus unexpired public replay
windows and all unconfirmed records. WASM supplies the public retired plan;
the host checks normalized provider closure and exact journal scope, not private
package fields. Completion is journaled before private-state retirement;
restart retries an interrupted write without dispatch. BingX acceptance receipts
can no longer trigger capacity-based history eviction. This requires matching
host/runner support and is not deployed; earlier unconfirmed history is not
silently deleted. No additional file, owner, daemon or exchange effect route.
Validation: Flutter 815/815, Jack Rust 62/62, both Rust workspaces, analyze,
plugin validation and review gates passed. Synthetic provider tests cover
five grouped lifecycles, expiry/restart, retained acceptance and interrupted
journal/state writes; the compiled WASM passed closure/reopen without effects.
Local candidate archive digest is `c2de33db`; installed `0.1.12` is unchanged.
Packaged macOS smoke on binary `22bcef6e` restored the active DASH VPS view
through the saved key, including order `2106703408299995136` shown open with
zero fill and advancing cycle timestamps. No package, grant or order changed.
The isolated actual-WASM probe reduced seven confirmed groups to five,
preserved unconfirmed records, and reopened one unchanged journal without
dispatch. The compiled production runner passed isolated handoff, timer,
restart, singleton and replay smoke; this is not deployment evidence.
UI status polling is now once per minute for VPS while the screen and app
are active, with immediate refresh on app resume; local status keeps its
15-second interval. Hidden-screen/background/disposal tests passed. This
UI-only adjustment follows the packaged smoke and needs the next app build;
it changes neither server scheduling nor authority.

Earlier local implementation evidence, not autonomy acceptance: app and headless
used the same workspace executor and effect journal. The `0.1.7` candidate
added a real opposite-line reducing limit exit, fixed at dispatch and reconciled
by exact client/provider identity. WASM owns selection, state and retirement;
the host's new `position.exit.place` provider capability checks the journaled
entry and current position without interpreting private package state. Stop
disables entries/cancellations, not reducing exits within the unexpired grant.
Unknown dispatch outcomes and package replacement cannot authorize a duplicate.
Conditional-stop verification, resizing/cleanup while an earlier exit remains
active, and live exit smoke remain incomplete.
Do not claim SL/TP or autonomous product acceptance from this source evidence.
The dense actual-WASM exit fixture uses unchanged memory/fuel limits. Changing
state is serialized once; swings are written as compact triples with a one-way
import of `0.1.6` objects. Remove that import when `0.1.6` stored state is no longer
supported; there is no second strategy/reducer or host-owned state migration.
The package installed during that earlier smoke was `0.1.6`, not the candidate:
archive `57a6bd10` on macOS binary `c2428660`. No live effects or VPS mutation
were made in that check. Earlier candidate evidence: Jack Rust 49/49, full
Flutter 801/801, analyze and plugin
validation passed. The packaged-WASM dense exit/reopen and headless lifecycle
fixtures passed with synthetic evidence only. Candidate ZIP SHA-256 is
`f93b273599317257f75b489e1a854c0151b1c0ec7b901e75a87b1ca4970f4cf7`.
Update/open preserved the existing workspace and effect journal byte-for-byte,
without new grants or enabled cycles. After the user completed Keychain,
live read-only refresh confirmed VET order `2105918659918786560` open with zero
fills, all six timeframes checked and the original 15M line unchanged/untouched.
Workspace close/reopen retained the refreshed state byte-for-byte; the effect
journal remained unchanged. This is package-update/read-only smoke only:
no live filled-position, SL/TP, autonomous cycle or VPS acceptance is claimed.
Local Start/Stop and bounded cycles now use
the same executor and effect journal: WASM reconciles, waits or prepares; the host
checks the separately confirmed package/account/instrument grant before POST
or exact cancellation. The same WASM pending-line classifier now proposes
cancellation only for its invalidated, open zero-fill entry. One journaled
DELETE is reconciled without blind retry; a racing fill stays managed and a
replacement waits for confirmed retirement plus fresh market/account evidence.
Stop also disables automatic cancellation. No second executor, strategy
fallback or private-state interpretation was added to the host.
No live Start, new order, VPS change or packaged smoke of these local cycles has
been performed. Source and synthetic evidence are not autonomous product acceptance.
Last full source baseline: Flutter 801/801, Jack Ventura Rust 38/38,
both Rust workspaces, analyze, plugin validation and review gates passed.
The actual WASM headless fixture passed closure/reopen and invalidated-entry
cancellation with one synthetic DELETE, zero POSTs and no network access.
Host tests also cover uncertain cancellation, fill races, wrong order IDs,
missing journal authority, package replacement and Stop during provider reads.
Pending cancellation records are reconciled through later lifecycle reads,
even when a fill stops the package proposing cancellation. Local timers resume
when the installed workspace is reopened, not merely when Capsule starts.
Package-update/read-only smoke passed on macOS binary `c2428660` with Jack
archive `e93fa9db`. Live refresh exposed fuel exhaustion in the final 5M batch:
the package now uses the existing continuation to render after streaming,
and read-only presentation retains saved state without another serialization.
No host change, larger resource limit or strategy change was needed. A dense
six-frame actual-WASM regression, synthetic lifecycle/cancellation, focused
Flutter 33/33, plugin Rust 38/38, analyze and manifest validation passed.
Live BingX reread confirmed VET order `2105918659918786560` open with zero fills
and its original 15M line unchanged and untouched. Workspace close/reopen
preserved saved state; the effect journal remained byte-identical, cycles
were not enabled, and no entry or cancellation was sent. This does not close
the pending Start/Stop, protection, profit-exit or VPS acceptance.

Historical Git, pull-request, and release evidence remains immutable history.
It does not authorize restoration of the retired implementation.

## Product Discipline

1. Freeze V2 implementation, new process documents, universal frameworks,
   speculative DTOs, and optional dependencies.
2. Deliver one complete user outcome per pull request.
3. Use focused tests while developing; run full repository verification once
   on the final candidate before pull request, then rely on required CI.
4. Refactor only the active journey. Owner and execution-path counts must not
   increase; replacements remove or seal their predecessors.
5. Green gates are necessary evidence, not product acceptance.
6. Keep new Trading implementation within the accepted JackV brief; do not
   restore retired strategy, runner, or host workflow paths.

## Queued Product Outcomes

1. Moltbook: bounded observation, AI proposal, publication, comment/reply,
   limits, restart recovery, and Capsule isolation through the existing effect
   lifecycle.
2. Chat: conversation UX, notifications, attachments, offline history, and
   recovery without another delivery or consensus path.

## Authority

1. `product-axis.md`: permanent laws and target runtime shape.
2. `specification.md`: maintained 1.x protocol.
3. Focused contracts: capability semantics.
4. This file: current state and the single selected product outcome.
5. `roadmap.md`: milestone/debt index; Git, pull requests, releases, tests,
   and evidence logs retain history.

## Integration Boundary

`main` changes only through a pull request with required `review-gates`.
Repository validation does not authorize a tag, Release, packaged smoke, VPS
mutation, or external effect.
