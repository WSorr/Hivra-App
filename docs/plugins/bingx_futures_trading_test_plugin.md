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
    "abi": "hivra_host_abi_v2",
    "entry_export": "hivra_evaluate_v1",
    "module_path": "plugin/module.wasm"
  },
  "contract": {
    "kind": "bingx_futures_order_intent"
  }
}
```

## Build Test Package

```bash
cd ../hivra-plugins
./scripts/build_plugin_zip.sh bingx_futures_test_plugin
```

Generated file:

- `hivra-plugins/dist/plugins/bingx_futures_test_plugin-0.2.2.zip`

## Host API Binding

- `plugin_id`: `hivra.contract.bingx-futures-trading.v1`
- `method`: `place_bingx_futures_order_intent`
- required capabilities:
  - `consensus_guard.read`
  - `exchange.trade.bingx.futures`

## Notes

- The external package owns deterministic intent validation, normalization,
  canonical JSON and intent hashing.
- Hivra-App owns sandbox execution, consensus/capability gates, risk and
  exchange adapters; it does not mirror plugin contract semantics.
- Actual exchange execution stays outside host API v1.
- TVH computation and trading-drone rule-set are specified separately:
  - `docs/plugins/bingx_futures_trading_drone_spec_v1.md`
