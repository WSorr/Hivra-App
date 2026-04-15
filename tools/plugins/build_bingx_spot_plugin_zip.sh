#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist/plugins}"
OUT_FILE="$OUT_DIR/bingx-spot-plugin-v1.zip"
TMP_DIR="$(mktemp -d)"
PLUGIN_DIR="$TMP_DIR/plugin"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$PLUGIN_DIR" "$OUT_DIR"

cat >"$PLUGIN_DIR/manifest.json" <<'JSON'
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
JSON

# Minimal valid WASM module with exported function `hivra_entry_v1`.
printf '\x00\x61\x73\x6d\x01\x00\x00\x00\
\x01\x04\x01\x60\x00\x00\
\x03\x02\x01\x00\
\x07\x12\x01\x0e\x68\x69\x76\x72\x61\x5f\x65\x6e\x74\x72\x79\x5f\x76\x31\x00\x00\
\x0a\x04\x01\x02\x00\x0b' >"$PLUGIN_DIR/module.wasm"

(
  cd "$TMP_DIR"
  zip -qr "$OUT_FILE" plugin
)

echo "Created plugin package: $OUT_FILE"
