# Plugin Host API v1 (Pre-WASM Execution)

This document defines the first deterministic host API boundary used before wasm runtime execution is mounted.

## Scope

- No wasm bytecode execution.
- Explicit API boundary for plugin calls.
- Guard-first behavior:
  - pair-scoped calls are blocked when consensus is not signable.

## Supported Contracts (v1)

- `hivra.contract.temperature-li.tomorrow.v1`
  - method: `settle_temperature_tomorrow`
- `hivra.contract.bingx-trading.v1`
  - method: `place_bingx_spot_order_intent`
- `hivra.contract.capsule-chat.v1`
  - method: `post_capsule_chat_message`

## Request Shape

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.temperature-li.tomorrow.v1",
  "method": "settle_temperature_tomorrow",
  "args": {
    "target_date_utc": "2026-04-01",
    "threshold_deci_celsius": 85,
    "proposer_rule": "above",
    "draw_on_equal": true,
    "location_code": "LI",
    "observed_deci_celsius": 90,
    "oracle_source_id": "oracle.mock.weather.v1",
    "oracle_event_id": "evt-1",
    "oracle_recorded_at_utc": "2026-04-01T12:00:00Z"
  }
}
```

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.bingx-trading.v1",
  "method": "place_bingx_spot_order_intent",
  "args": {
    "peer_hex": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "client_order_id": "ord-1",
    "symbol": "BTC-USDT",
    "side": "buy",
    "order_type": "limit",
    "quantity_decimal": "0.01",
    "limit_price_decimal": "60000",
    "time_in_force": "GTC",
    "entry_mode": "direct",
    "created_at_utc": "2026-04-09T10:00:00Z",
    "strategy_tag": "demo"
  }
}
```

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.bingx-trading.v1",
  "method": "place_bingx_spot_order_intent",
  "args": {
    "peer_hex": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "client_order_id": "ord-zone-1",
    "symbol": "BTC-USDT",
    "side": "buy",
    "order_type": "limit",
    "quantity_decimal": "0.02",
    "time_in_force": "GTC",
    "entry_mode": "zone_pending",
    "zone_side": "buyside",
    "zone_low_decimal": "58000",
    "zone_high_decimal": "60000",
    "zone_price_rule": "zone_mid",
    "trigger_price_decimal": "58900",
    "stop_loss_decimal": "57500",
    "take_profit_decimal": "62000",
    "created_at_utc": "2026-04-09T10:00:00Z",
    "strategy_tag": "zone-demo"
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
  - `execution_contract_kind`: nullable manifest contract kind
  - `execution_capabilities`: normalized/sorted capability list from runtime binding metadata
  - `execution_runtime_mode`: nullable runtime mode (`wasm_stub_v1` in current phase)
  - `execution_runtime_abi`: nullable runtime ABI id (`hivra_host_abi_v1`)
  - `execution_runtime_entry_export`: nullable entry export symbol (`hivra_entry_v1`)
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
- It exists to lock deterministic host semantics before introducing wasm runtime execution.
- Runtime execution source is resolved by host-side binding policy:
  - `execute(...)` forces `host_fallback`
  - `executeWithRuntimeHook(...)` may resolve installed package metadata and emit `external_package`
  - external-package runtime binding shape is validated before invoke (`package_id` required, `package_kind` must be `wasm|zip`); invalid metadata is rejected (`runtime_binding_invalid`)
  - when external package is resolved, host includes deterministic package digest (`execution_package_digest_hex`)
  - when external package exposes `execution_contract_kind`, host rejects mismatches against requested `plugin_id` (`runtime_contract_kind_mismatch`)
  - when external package exposes capability metadata, host validates required capabilities for requested `(plugin_id, method)` and rejects missing/unsupported grants (`runtime_capability_mismatch`)
  - host canonical response includes normalized runtime capability metadata (`execution_capabilities`) for deterministic diagnostics
- Runtime capability requirements are method-scoped:
  - `settle_temperature_tomorrow` requires `consensus_guard.read` and one oracle capability from:
    - `oracle.read.mock_weather`
    - `oracle.read.temperature.li`
  - `place_bingx_spot_order_intent` requires `consensus_guard.read` and `exchange.trade.bingx.spot`
  - `post_capsule_chat_message` requires `consensus_guard.read`
- Current runtime phase exposes deterministic invoke evidence via `wasm_stub_v1`:
  - when `execution_package_digest_hex` is present, host verifies installed package bytes against that digest before runtime module extraction
    - digest shape mismatch or digest mismatch rejects runtime invoke as invalid
  - host reads module bytes from resolved package:
    - direct `.wasm` package bytes, or
    - `runtime.module_path` from zip manifest when provided, otherwise first `.wasm` in lexical order
    - zip entries containing parent-traversal segments (`..`) are ignored for runtime module selection
    - when a zip contains `.wasm` entries but all candidate module paths are traversal-shaped, runtime invoke is rejected as invalid
  - runtime metadata is strict for external packages: `runtime.abi=hivra_host_abi_v1` and `runtime.entry_export=hivra_entry_v1`
  - runtime invoke validates that selected wasm module exports function `hivra_entry_v1` with `() -> ()` signature; missing export or signature mismatch is rejected as invalid runtime invoke
  - runtime invoke rejects modules declaring imports in `wasm_stub_v1` phase (import-enabled ABI execution is deferred until full runtime host stage)
  - runtime invoke rejects modules declaring `start` section in `wasm_stub_v1` phase (auto-start semantics deferred to full runtime host stage)
  - runtime invoke executes `hivra_entry_v1` through a deterministic no-host instruction subset in `wasm_stub_v1`:
    - allowed: `nop`, `drop`, `i32.const`, `i64.const`, `f32.const`, `f64.const`, `i32.add`, `i32.sub`, `i32.mul`, `block`, `if`, `else`, `br`, `br_if`, `end`
    - structured control-flow is currently limited to empty block type (`0x40`); non-void block types are rejected
    - `loop` remains explicitly unsupported in `wasm_stub_v1`
    - disallowed opcodes reject invoke as invalid (explicit diagnostics)
    - runtime execution is additionally bounded by fixed limits (instruction count and stack depth); overflow rejects invoke as invalid
  - manifest `runtime.module_path` with parent traversal is rejected by runtime invoke validation
  - host emits module digest + invoke digest without granting plugin-side side effects
- `place_bingx_spot_order_intent` supports:
  - `entry_mode=direct` (current flat spot intent)
  - `entry_mode=zone_pending` (deterministic pending-entry parameters from `buyside/sellside` zones)
- In `zone_pending`, host API computes the final limit entry price from zone rules and returns it in deterministic result payload; no live-trading execution is performed in host API v1.
- `post_capsule_chat_message` currently returns a deterministic envelope hash only; transport delivery remains outside this host API boundary.
