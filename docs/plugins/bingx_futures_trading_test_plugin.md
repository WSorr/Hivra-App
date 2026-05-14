# BingX Futures Trading Test Plugin v1

This document defines the loadable test package shape for BingX futures intent execution.

## Goal

- keep futures intent routing explicit and deterministic
- keep host boundary narrow (no live order placement in v1)
- preserve module isolation and downward-only dependency topology

## Manifest Shape

```json
{
  "schema": "hivra.plugin.manifest",
  "version": 1,
  "plugin_id": "hivra.contract.bingx-futures-trading.v1",
  "capabilities": [
    "consensus_guard.read",
    "exchange.read.bingx.market",
    "exchange.trade.bingx.futures"
  ],
  "runtime": {
    "abi": "hivra_host_abi_v1",
    "entry_export": "hivra_entry_v1",
    "module_path": "plugin/module.wasm"
  },
  "contract": {
    "kind": "bingx_futures_order_intent"
  }
}
```

## Build Test Package

```bash
./tools/plugins/build_bingx_futures_plugin_zip.sh
```

Generated file:

- `dist/plugins/bingx-futures-plugin-v1.zip`

## Host API Binding

- `plugin_id`: `hivra.contract.bingx-futures-trading.v1`
- `method`: `place_bingx_futures_order_intent`
- required capabilities:
  - `consensus_guard.read`
  - `exchange.trade.bingx.futures`

## Notes

- This package is for deterministic intent preparation only.
- Actual exchange execution stays outside host API v1.
- TVH computation and trading-drone rule-set are specified separately:
  - `docs/plugins/bingx_futures_trading_drone_spec_v1.md`
