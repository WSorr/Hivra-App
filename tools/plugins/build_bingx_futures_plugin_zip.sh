#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist/plugins}"
OUT_FILE="$OUT_DIR/bingx-futures-plugin-v1.zip"
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
JSON

# Minimal valid WASM module with exported function `hivra_entry_v1`.
# Use hex decode to avoid shell-escape/newline corruption in binary output.
cat >"$TMP_DIR/module.wasm.hex" <<'HEX'
0061736d01000000010401600000030201000712010e68697672615f656e7472795f763100000a040102000b
HEX
xxd -r -p "$TMP_DIR/module.wasm.hex" >"$PLUGIN_DIR/module.wasm"

(
  cd "$TMP_DIR"
  zip -qr "$OUT_FILE" plugin
)

echo "Created plugin package: $OUT_FILE"
