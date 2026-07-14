# Plugin Host API v1 (WASM Execution Boundary)

This document defines the deterministic host API boundary used by the current
bounded WASM runtime and retained host-side adapters.

## Scope

- WASM bytecode execution through the bounded `wasmi_v1` runtime for resolved
  external packages.
- Explicit API boundary for plugin calls.
- Guard-first behavior:
  - pair-scoped calls are blocked unless the local snapshot is signable and
    the host has verified attestations from exactly both pair roots over that
    snapshot hash.

## Supported Contracts (v1)

- `hivra.contract.bingx-futures-trading.v1`
  - method: `place_bingx_futures_order_intent`
  - method: `rank_bingx_futures_signals`
- `hivra.contract.capsule-chat.v1`
  - method: `post_capsule_chat_message`

## Request Shape

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.bingx-futures-trading.v1",
  "method": "place_bingx_futures_order_intent",
  "args": {
    "peer_hex": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "client_order_id": "ord-fut-1",
    "symbol": "BTC-USDT",
    "side": "sell",
    "order_type": "limit",
    "quantity_decimal": "0.02",
    "limit_price_decimal": "61000",
    "time_in_force": "GTC",
    "entry_mode": "direct",
    "created_at_utc": "2026-04-09T10:00:00Z",
    "strategy_tag": "futures-demo"
  }
}
```

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

- `status`: `executed | blocked | rejected`
- `result`: present only for `executed`
- `blocking_facts`: present for `blocked`
- `error_code`/`error_message`: present for `rejected`
- runtime binding metadata:
  - `execution_source`: `host_fallback | external_package`
  - `execution_package_id`: nullable package record id
  - `execution_package_version`: nullable package version
  - `execution_package_kind`: nullable package kind (`wasm` / `zip`)
  - `execution_package_digest_hex`: nullable SHA-256 of resolved package bytes
  - `execution_contract_kind`: required manifest contract kind for external packages
  - `execution_capabilities`: normalized/sorted capability list from runtime binding metadata
  - `execution_runtime_mode`: nullable runtime mode (`wasmi_v1`)
  - `execution_runtime_abi`: nullable runtime ABI id (`hivra_host_abi_v2`)
  - `execution_runtime_entry_export`: nullable entry export symbol (`hivra_evaluate_v1`)
  - `execution_runtime_module_path`: nullable selected runtime module path
    - if runtime hook resolves module path explicitly, this reflects selected module
    - otherwise falls back to manifest `runtime.module_path` when available
  - `execution_runtime_module_selection`: nullable module-selection strategy
    - `manifest_module_path` | `lexical_first_wasm` | `package_wasm`
  - `execution_runtime_module_digest_hex`: nullable SHA-256 of selected wasm module bytes
  - `execution_runtime_invoke_digest_hex`: nullable deterministic digest of `(plugin_id, method, args, module_selection, module_path, module_digest)` for runtime invoke evidence
- `canonical_json` + `response_hash_hex`:
  - deterministic for identical request + runtime inputs

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

## Notes

- This API is an application-layer boundary and does not grant plugin storage or ledger-write privileges.
- It locks deterministic host semantics around current WASM execution.
- Runtime execution source is resolved by host-side binding policy:
  - `execute(...)` forces `host_fallback`
  - `executeWithRuntimeHook(...)` may resolve installed package metadata and emit `external_package`
  - for `place_bingx_futures_order_intent`, host-fallback execution is disallowed:
    - if external runtime package is not resolved, request is rejected (`runtime_invoke_unavailable`)
    - if runtime invoke evidence is missing, request is rejected (`runtime_invoke_unavailable`)
  - external-package runtime binding shape is validated before invoke (`package_id` required, `package_kind` must be `wasm|zip`); invalid metadata is rejected (`runtime_binding_invalid`)
  - when external package is resolved, host includes deterministic package digest (`execution_package_digest_hex`)
  - external packages must expose a non-empty `execution_contract_kind`; missing or mismatched values are rejected (`runtime_contract_kind_mismatch`)
  - external packages must expose capability metadata; host validates all required capabilities for requested `(plugin_id, method)` and rejects missing/unsupported grants (`runtime_capability_mismatch`)
  - no legacy fail-open path exists for missing contract or capability metadata
  - host canonical response includes normalized runtime capability metadata (`execution_capabilities`) for deterministic diagnostics
- Runtime capability requirements are method-scoped:
  - `place_bingx_futures_order_intent` requires `consensus_guard.read` and `exchange.trade.bingx.futures`
  - `post_capsule_chat_message` requires `consensus_guard.read`
- Drone consensus scopes are explicit:
  - `solo` methods do not require a peer and must not read pair consensus.
  - `market_scan` methods may read public/external data and rank opportunities
    without pair consensus, but must not mutate pair-scoped state or execute
    peer-scoped effects.
  - `pair_scoped` methods require `peer_hex` and must call
    the attested host guard. `ConsensusRuntimeService.signable(peer_hex)` is
    only the local snapshot precondition; it is not sufficient authorization.
  - host code must never replace a missing or unresolved `peer_hex` with "any
    signable peer".
- Current runtime executes plugin-owned semantics through bounded `wasmi_v1`:
  - when `execution_package_digest_hex` is present, host verifies installed package bytes against that digest before runtime module extraction
    - digest shape mismatch or digest mismatch rejects runtime invoke as invalid
  - host reads module bytes from resolved package:
    - direct `.wasm` package bytes, or
    - exact `runtime.module_path` from the zip manifest
    - parent-traversal segments (`..`) are rejected
  - runtime metadata is strict for external packages: `runtime.abi=hivra_host_abi_v2` and `runtime.entry_export=hivra_evaluate_v1`
  - ABI exports are:
    - `hivra_alloc_v1(len: u32) -> u32`
    - `hivra_evaluate_v1(ptr: u32, len: u32) -> u64`
    - `hivra_dealloc_v1(ptr: u32, len: u32)`
  - the packed evaluate result is `(output_ptr << 32) | output_len`
  - request and response are canonical UTF-8 JSON with explicit schema/status
  - runtime rejects all module imports and enforces module/input/output size plus fuel limits
  - missing exports, signature mismatch, traps, fuel exhaustion, invalid UTF-8,
    malformed envelopes and output hash mismatch fail closed
  - manifest `runtime.module_path` with parent traversal is rejected by runtime invoke validation
  - host emits module digest + invoke digest that binds canonical input and output
  - plugin owns deterministic contract semantics; host owns package integrity,
    capabilities, consensus guard, risk and effectful exchange/transport adapters
- `place_bingx_futures_order_intent` supports:
  - `entry_mode=direct`
  - `entry_mode=zone_pending`
- In `zone_pending`, the BingX plugin computes the final limit entry price from
  zone rules and returns canonical intent JSON; exchange execution remains
  outside the plugin boundary.
- `rank_bingx_futures_signals` ranks precomputed live-decision summaries:
  - host/runtime owns exchange reads, TVH live-decision summaries and UI projection
  - plugin owns deterministic bucket/score ordering and returns `canonical_json`
    plus `scan_hash_hex`
  - ranking is market-scan scoped and does not require `consensus_guard.read`
  - host must not mirror plugin-side ranking/scoring semantics
- `post_capsule_chat_message` returns plugin-owned canonical envelope JSON and
  hash; transport delivery remains outside this host API boundary.
