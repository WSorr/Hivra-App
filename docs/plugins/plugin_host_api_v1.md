# Plugin Host API v1 (WASM Execution Boundary)

This document defines version 1 of the deterministic plugin request/response
contract. It is not the WASM ABI version: current external packages use
`hivra_host_abi_v2` and the `hivra_*_v1` exports below.

## Scope

- WASM bytecode execution through the bounded `wasmi_v1` runtime for resolved
  external packages.
- Explicit method and capability checks before invocation.
- Pair-scoped calls blocked unless the local pair snapshot is signable and the
  required attestations bind both roots to that snapshot.

The host does not grant plugin storage, Ledger writes, transport access, or
provider effects merely because a WASM call succeeds.

## Supported Contracts

- `hivra.contract.capsule-chat.v1`
  - `post_capsule_chat_message`
- `hivra.contract.moltbook-ambassador.v1`
  - `prepare_moltbook_draft`
  - `plan_moltbook_heartbeat`
  - `plan_moltbook_engagement`
  - `prepare_moltbook_reply`
  - `authorize_moltbook_delegated_reply`
- Installed packages declaring `plugin_workspace_v1`
  - `workspace`
  - Require `workspace.render`, `workspace.continue` and `state.plugin.read_write`.
  - Return bounded `state`, `view`, and `requests`. The view contains title,
    message, optional account summary, details, up to eight text/numeric/choice fields, four actions, and a
    table of at most 64 rows and six columns, with an optional `details_title`
    supplied by the package. The shell renders these values;
    it does not implement package business logic. Fields marked `advanced`
    and calculation evidence are collapsed by default; status and errors
    remain visible.
  - State is at most 32 KiB and is persisted through the existing
    Capsule/plugin file store. One action is serialized per Capsule/plugin;
    Capsule and installed-package identity are checked before continuations.
    State internals are opaque to the host: the package owns account, strategy,
    and managed-order interpretation. Provider scope comes from explicit
    capability requests, not private state field names.
    `PluginWorkspaceRuntime` owns the same invocation, persistence and effect
    path in app and headless hosts. The app module supplies its scoped vault
    through credential ports; Flutter, Chat and Moltbook are not dependencies
    of the executor. Installed-package bindings are resolved by the existing
    registry, not reconstructed independently by each host.
  - Root output may declare `resume_action` with a bounded action ID, alongside
    one or more permitted reads. After all evidence is admitted through the
    public provider continuations (`market`, `account`, `order`, `restore_entry`),
    the host invokes that package-selected action once. It must finish without
    requests or another continuation. Transient open-order lists, credential
    connection and entry effects cannot request this step. The host never
    selects private preparation commands or associates authority with their
    names. Credential input authorizes only its single `account.connect`
    request; entry confirmation authorizes only the exact single effect.
    Packages without `workspace.continue` are not activated by this host, and
    older hosts reject the new capability rather than silently skipping the
    preparation step. There is no legacy private-command fallback.
  - `workspace.schedule` permits a separately confirmed local execution grant.
    The package exposes a public `schedule`: action, interval (30..3600 seconds),
    account ID, instrument, maximum entry margin and maximum requested-stop
    percentage. Start binds that scope, public settings and the installed package
    digest for 24 hours in host-owned storage, separate from opaque WASM state.
    WASM receives only account/instrument and `allow_new_entries`. The shared
    executor calls the package-selected cycle and uses the existing exact entry
    journal/dispatch path, checking grant revision and limits again immediately
    before POST or exact entry cancellation. Start explicitly includes cancellation
    of an invalidated unfilled managed entry before replacement. Stop revokes
    both automatic entry and cancellation during in-flight reads; Stop itself
    neither cancels orders nor closes positions. Observation may continue until expiry.
    Replacement, removal, revocation or Capsule change does not transfer authority.
    A per-Capsule/account/instrument dispatch lease prevents concurrent sends
    through the same file store. Saved intent is not runner-health evidence;
    the view reports actual cycle observations separately. This implements local
    cycles while the app is open, not managed VPS installation, verified stop
    protection, profit-taking or a daily loss cap.
  - `market.candles.read` permits only the bounded BingX public-candle adapter,
    with an explicit symbol, supported timeframe, and 1..600 candles. The host
    normalizes evidence and excludes unclosed candles. The plugin interprets
    the snapshots. This capability does not grant credentials or order effects.
  - `account.connect` permits a host-owned credential dialog explicitly
    marked by action `host: "bingx.account.connect"`. Keys are passed only to
    the host, never to WASM settings or state. The fixed BingX LIVE read-only
    adapter verifies exact UID, USDT available margin, side-specific leverage,
    and contract constraints. One credential pair is kept in the existing
    Capsule/plugin-scoped secure vault. Failed connection preserves the prior
    binding; package and grants are checked again after reads and secure save.
  - `account.snapshot.read` refreshes that connection for the selected
    instrument. Its normalized snapshot contains endpoint, hashed account UID,
    display label, available margin, long/short leverage, price/quantity
    precision, minimum quantity/notional, and observation time. The host
    rejects a UID that differs from the request's explicit `account_id`.
    Cached data is labelled with its age;
    the plugin calculates sizing and stop previews, not the host. No order
    submission, leverage change, or financial authority is granted by either
    account capability. API/network errors never include signed URLs or keys.
    The account and leverage reads follow the BingX
    [account API](https://github.com/BingX-API/api-ai-skills/blob/main/skills/swap-account/api-reference.md)
    and [trade API](https://github.com/BingX-API/api-ai-skills/blob/main/skills/swap-trade/api-reference.md).
  - A `choice` field declares its `source` as
    `{"kind":"market.instruments.read","provider":"bingx"}`.
    Its granted read uses the same serialized workspace boundary, validates
    the installed package again after the read, and returns transient options
    to a searchable picker. The shell accepts only an explicit selection;
    cancellation or read failure does not change the field or run a strategy.
    Only the selected value is passed to WASM on the next action. The catalog
    is not stored in plugin state or the Ledger. BingX's
    [contract information API](https://github.com/BingX-API/api-ai-skills/blob/main/skills/swap-market/api-reference.md)
    supplies active, API-open contracts, deduplicated and sorted; the host does
    not rank instruments. Reads are limited to 4096 contracts and 2 MiB;
    candle-response limits remain unchanged.
  - `order.entry.place` permits one explicitly confirmed BingX LIVE entry.
    WASM prepares the immutable account-bound plan; a host action marked
    `host: "bingx.order.submit"` shows the exact instrument, side, quantity,
    price, margin, leverage and requested stop. Confirmation is required for
    that exact plan unless a separately confirmed, package-pinned schedule grant
    covers it; both use the same execution path. The host rechecks
    package/grants, account UID and entry expiry before its single POST.
    It never calculates strategy levels or sizing. The request is a PostOnly
    limit with an attached stop request; this is not verified position
    protection or automatic profit-taking.
    Before dispatch, the pinned package receives `validate_entry` without a
    snapshot and requests 1..7 bounded `market.candles.read` observations for
    the approved instrument. The package selects the supported timeframe and
    history depth, not the provider adapter. The host requires the market-read
    grant, acquires those observations, and supplies each through
    `validate_entry` with complete-history bounds and a final-batch marker.
    Every continuation rechecks package identity and grants. Empty evidence
    requests, foreign instruments, nested effects or rejected validation stop
    before POST; there is no host-owned strategy-validation fallback.
  - `order.entry.cancel` uses the same `bingx.order.submit` action, exact
    confirmation or package-pinned schedule grant, adapter and effect journal.
    Its request carries the original immutable `plan` and exact string `order_id`.
    The host requires that plan's entry in the journal and verifies its account,
    client operation, provider ID, side, price and quantity before cancellation.
    The pinned package admits the decision through `validate_cancel` without
    nested reads/effects; the host does not interpret private line/state fields.
    Current position/order reads must show no position and an open zero-fill entry.
    Package, read/cancel grants and schedule revision are rechecked immediately
    before one exact DELETE; manual orders and bulk cancellation are not admitted.
    An uncertain response permits read-only reconciliation, not another DELETE.
    Subsequent exact lifecycle reads also reconcile the pending cancel journal
    operation, even when a fill means the package no longer proposes cancellation.
    A confirmed pre-dispatch failure is retained as `cancel_not_sent` and reported;
    only that proven non-dispatch may be reauthorized. Terminal reconciliation
    can mean a racing fill, not successful cancellation. The original entry's
    lifecycle evidence is returned to WASM; neither a cancel request nor its
    receipt authorizes a replacement. The next cycle must reconcile terminal
    order, flat positions and no remaining orders, then obtain fresh market/account
    evidence. The exact cancellation uses BingX's
    [trade API](https://github.com/BingX-API/api-ai-skills/blob/main/skills/swap-trade/api-reference.md).
  - `position.exit.place` adds a reducing BingX LIVE GTC limit exit through the
    same `bingx.order.submit` confirmation/schedule, adapter and effect journal.
    Its public `plan` has exactly seven fields: `entry_plan` (the immutable
    fourteen-field entry contract), `position_id`, `quantity`, `average_price`,
    `price`, `prepared_at_ms`, and `expires_at_ms` (at most 60 seconds later).
    The host requires that exact entry in the package/account journal; the
    adapter rereads its fill and the single matching current position before
    sending only the observed remaining quantity. One-way mode uses
    `positionSide=BOTH` and `reduceOnly=true`; hedge mode uses the opposite order
    side and the original LONG/SHORT position side, without `reduceOnly`.
    `closePosition` is never sent. The pinned package admits the decision via
    `validate_exit` without nested reads/effects. The host does not select a
    line, read private position/strategy fields, or invent a fallback exit.
    Unknown responses permit reconciliation of the same deterministic client ID,
    never another POST. Another exit for the same entry is blocked until its
    existing journaled operation is resolved by the supported lifecycle.
    This capability does not place or verify a protective conditional stop.
    A package may add `exit_plan` to its lifecycle read to receive optional
    normalized `exit` evidence for that exact journaled reducing order; packages
    not requesting it retain the previous evidence shape. Stop retains reducing
    exit authority within the current package/account/instrument grant until
    expiry, but disables new entries and entry replacement cancellations.
  - `order.snapshot.read` queries the exact client operation/order. Its
    `scope: "open"` variant reads current open orders for the selected instrument
    and connected account, not account-wide history. The host verifies the UID
    binding and returns at most 64 normalized rows with exact IDs, side/position
    side, type, provider status, price/trigger, quantity/fill and observation time.
    This list is transient view evidence, not saved strategy state or managed
    entries; failure is not an empty list, reopening requires a fresh read,
    and foreign/manual orders are never automatically adopted or cancelled.
    Both listing and entry preflight use the same provider parser. The existing external-effect journal owns
    delivery identity and receipts; WASM owns managed-order interpretation.
    A restart or uncertain response performs read-only reconciliation, never
    a blind second POST. Provider acceptance, open order, partial/full fill,
    cancellation, rejection, expiry, and unknown remain distinct; no position
    or PnL is inferred. Effect receipts survive plugin uninstall while keys
    and strategy state are deleted. Reconnecting the same account restores
    the durable request for reconciliation; foreign accounts are not adopted.
    For recovery the package requests `order.snapshot.read` with
    `scope: "durable"`, `provider`, and `account_id`. After verifying the UID
    and read grant, the host streams the existing journal's account/provider
    scoped operations unchanged through `restore_entry`, one record per
    invocation, with `batch_complete`. Only WASM selects eligible entries;
    the host does not select the newest plan or reinterpret delivery state.
    Package identity, Capsule and grants are rechecked between records;
    recovered state is saved once, after the complete successful read.
    Recovery neither submits an order nor fabricates fresh provider evidence.
    An unavailable exact-order read retains the last observation and reports
    failure. Confirmed non-dispatch reasons are evidence rendered by WASM,
    rather than a host rewrite of the package's view.
  - `order.snapshot.read` with `scope: "lifecycle"` additionally requires
    `position.snapshot.read`. It reads the journal-bound exact entry, current
    positions and all open orders of the explicit account/instrument through
    the existing adapter. `lifecycle` receives a bounded snapshot containing
    `account_id`, `symbol`, `entry`, `positions`, `orders`, and `observed_at_ms`.
    Position rows expose exact ID, side, quantity and average price; they do
    not grant management of manual positions. Incomplete, malformed, foreign
    or excessively slow reads fail rather than become empty exposure. The
    package owns closure interpretation and recovery checkpoints; no closure,
    PnL, protection or authority is inferred by the host. Existing single-entry
    confirmation or a separate schedule grant remains required. This read
    contract alone does not authorize another entry.
  - At most seven requested reads are processed sequentially and supplied through subsequent
    WASM invocations in host transport batches of 12 candles. Each batch carries the
    full history's end time and whether it is the final batch, so streaming
    does not change the plugin's calculation window. Nested provider requests
    are rejected. No host import or direct plugin network access is added.

## Request Shape

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.capsule-chat.v1",
  "method": "post_capsule_chat_message",
  "args": {
    "peer_hex": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "client_message_id": "msg-1",
    "message_text": "hello",
    "created_at_utc": "2026-04-04T10:00:00Z"
  }
}
```

## Response Shape

- `status`: `executed | blocked | rejected`;
- `result`: present only for `executed`;
- `blocking_facts`: present for `blocked`;
- `error_code` and `error_message`: present for `rejected`;
- `canonical_json` and `response_hash_hex`: deterministic for identical
  request and runtime inputs;
- runtime evidence:
  - execution source and package identity;
  - package, module, and invocation digests;
  - contract kind and normalized capabilities;
  - runtime mode, ABI, entry export, and selected module path.

## Error Codes

- `invalid_schema_version`
- `unsupported_plugin`
- `unsupported_method`
- `invalid_args`
- `runtime_invoke_invalid`
- `runtime_invoke_failed`
- `runtime_invoke_unavailable`
- `runtime_binding_invalid`
- `runtime_contract_kind_mismatch`
- `runtime_capability_mismatch`

## Runtime Boundary

External execution is fail-closed:

- package id and kind are required;
- package bytes must match the resolved digest;
- contract kind and required method capabilities must match the manifest;
- runtime ABI is `hivra_host_abi_v2`;
- runtime entry export is `hivra_evaluate_v1`;
- zip module paths cannot traverse parents;
- modules cannot import host functions;
- module, input, output, linear memory, and fuel are bounded: linear memory
  permits at most 128 MiB per invocation; fuel remains 5,000,000;
- missing exports, signature mismatch, traps, invalid UTF-8, malformed
  envelopes, and output-hash mismatch are rejected;
- no legacy fail-open path exists for missing contract or capability metadata.

ABI exports:

- `hivra_alloc_v1(len: u32) -> u32`
- `hivra_evaluate_v1(ptr: u32, len: u32) -> u64`
- `hivra_dealloc_v1(ptr: u32, len: u32)`

The packed evaluate result is `(output_ptr << 32) | output_len`.

## Capability Ownership

- Chat requires `consensus_guard.read`, returns plugin-owned canonical message
  bytes, and leaves pair consensus and transport delivery to the host.
- Moltbook draft, planning, reply, and delegated-reply methods require their
  corresponding `content.*` capabilities. WASM output is proposal or bounded
  authorization evidence, not a network publication receipt.
- Host fallback is retained only for explicitly allowed compatibility methods.
  It is not a second WASM evaluator and must not duplicate plugin semantics.

## Consensus Scopes

- Solo methods do not read pair consensus.
- Pair-scoped methods require a valid `peer_hex` and the attested host guard.
- `ConsensusRuntimeService.signable(peer_hex)` is only a local snapshot
  precondition; it is not sufficient authorization.
- The host never substitutes a missing peer with an arbitrary signable peer.
