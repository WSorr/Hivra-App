# BingX Spot Trading Test Plugin v1

This document defines a draft contract shape for BingX spot order intent.

Purpose:
- provide a loadable/installable BingX plugin package
- lock manifest/capability shape before WASM runtime execution is mounted

Status:
- pre-WASM execution stage
- package can be installed and listed in plugin registry
- host API v1 supports deterministic intent method (`place_bingx_spot_order_intent`)
- package is not executed for live trading by host API v1

## Manifest (v1 draft)

```json
{
  "schema": "hivra.plugin.manifest",
  "version": 1,
  "plugin_id": "hivra.contract.bingx-trading.v1",
  "capabilities": [
    "exchange.read.bingx.market",
    "exchange.trade.bingx.spot"
  ],
  "runtime": {
    "abi": "hivra_host_abi_v1",
    "entry_export": "hivra_entry_v1",
    "module_path": "plugin/module.wasm"
  },
  "contract": {
    "kind": "bingx_spot_order_intent"
  }
}
```

## Build Package

Run:

```bash
./tools/plugins/build_bingx_spot_plugin_zip.sh
```

Output:
- `dist/plugins/bingx-spot-plugin-v1.zip`
- generated wasm module includes required runtime export `hivra_entry_v1`

Install:
- open `WASM Plugins` screen in app
- click install and choose the generated zip file
- package passes preflight and appears in installed plugin list

## Capability Model (v1 Allowlist)

- `exchange.read.bingx.market`
- `exchange.trade.bingx.spot`

Unknown capabilities are rejected during package preflight.

## Host API v1 Method

- `plugin_id`: `hivra.contract.bingx-trading.v1`
- `method`: `place_bingx_spot_order_intent`
- supported entry modes:
  - `direct`: explicit `limit/market` intent
  - `zone_pending`: deterministic pending-entry intent derived from zone parameters
    - `zone_side`: `buyside | sellside`
    - `zone_low_decimal`, `zone_high_decimal`
    - `zone_price_rule`: `zone_low | zone_mid | zone_high | manual`
    - optional risk params: `trigger_price_decimal`, `stop_loss_decimal`, `take_profit_decimal`
- response: deterministic `intent_hash_hex` + `canonical_intent_json`
- no exchange-side order placement is performed in v1

## Capsule Trade Signal (App-Layer)

Current app layer can broadcast a prepared BingX intent to consensus peers as a
transport message (`kind=4097`) with:

- `contract_kind`: `bingx_trade_signal_v1`
- `signal_type`: `intent_prepared`
- `signal_id`
- `intent_hash_hex`
- `canonical_intent_json`
- order summary fields (`symbol`, `side`, `order_type`, `quantity_decimal`,
  `entry_mode`)

Receivers can:

- observe incoming trade signals in plugin inbox
- load `Repeat as draft` to prefill local intent fields

Auto-copy execution is intentionally not enabled in this phase.
