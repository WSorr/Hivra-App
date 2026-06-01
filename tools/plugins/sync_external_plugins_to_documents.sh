#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXTERNAL_REPO="${1:-$ROOT_DIR/../hivra-plugins}"
DOCS_PLUGIN_DIR="$HOME/Documents/Hivra/Plugins"
SOURCE_DIR="$DOCS_PLUGIN_DIR/source"
CATALOG_PATH="$DOCS_PLUGIN_DIR/plugin_catalog.json"

if [[ ! -d "$EXTERNAL_REPO" ]]; then
  echo "external repo not found: $EXTERNAL_REPO"
  exit 1
fi

if [[ ! -x "$EXTERNAL_REPO/scripts/build_all_plugins.sh" ]]; then
  echo "build script missing in external repo: $EXTERNAL_REPO/scripts/build_all_plugins.sh"
  exit 1
fi

echo "Building external plugin packages..."
"$EXTERNAL_REPO/scripts/build_all_plugins.sh"

mkdir -p "$SOURCE_DIR"
cp -f "$EXTERNAL_REPO"/dist/plugins/*.zip "$SOURCE_DIR"/

zip_uri() {
  python3 - "$1" <<'PY'
import pathlib, sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
}

sha256_hex() {
  shasum -a 256 "$1" | awk '{print tolower($1)}'
}

latest_zip_or_empty() {
  local pattern="$1"
  local latest
  latest="$(ls $pattern 2>/dev/null | sort | tail -n1 || true)"
  echo "$latest"
}

BINGX_FUTURES_ZIP="$(latest_zip_or_empty "$SOURCE_DIR"/bingx_futures_test_plugin-*.zip)"
BINGX_SPOT_ZIP="$(latest_zip_or_empty "$SOURCE_DIR"/bingx_spot_test_plugin-*.zip)"
CHAT_ZIP="$(ls "$SOURCE_DIR"/capsule_chat_test_plugin-*.zip | sort | tail -n1)"

if [[ -n "$BINGX_FUTURES_ZIP" ]]; then
  BINGX_ZIP="$BINGX_FUTURES_ZIP"
  BINGX_ENTRY_ID="bingx-futures-test"
  BINGX_PLUGIN_ID="hivra.contract.bingx-futures-trading.v1"
  BINGX_DISPLAY_NAME="BingX Futures Trading (Test Plugin)"
  BINGX_VERSION="$(basename "$BINGX_ZIP" | sed -E 's/^bingx_futures_test_plugin-([0-9.]+)\.zip$/\1/')"
elif [[ -n "$BINGX_SPOT_ZIP" ]]; then
  BINGX_ZIP="$BINGX_SPOT_ZIP"
  BINGX_ENTRY_ID="bingx-spot-test"
  BINGX_PLUGIN_ID="hivra.contract.bingx-trading.v1"
  BINGX_DISPLAY_NAME="BingX Spot Trading (Test Plugin)"
  BINGX_VERSION="$(basename "$BINGX_ZIP" | sed -E 's/^bingx_spot_test_plugin-([0-9.]+)\.zip$/\1/')"
else
  echo "missing BingX plugin zip (expected bingx_futures_test_plugin-*.zip or bingx_spot_test_plugin-*.zip)"
  exit 1
fi

BINGX_SHA256="$(sha256_hex "$BINGX_ZIP")"
CHAT_SHA256="$(sha256_hex "$CHAT_ZIP")"

CHAT_VERSION="$(basename "$CHAT_ZIP" | sed -E 's/^capsule_chat_test_plugin-([0-9.]+)\.zip$/\1/')"

cat > "$CATALOG_PATH" <<JSON
{
  "schema": "hivra.plugin.catalog",
  "version": 1,
  "source_id": "local.hivra.plugins",
  "source_name": "Local Hivra Plugins",
  "entries": [
    {
      "id": "$BINGX_ENTRY_ID",
      "plugin_id": "$BINGX_PLUGIN_ID",
      "display_name": "$BINGX_DISPLAY_NAME",
      "version": "$BINGX_VERSION",
      "package_kind": "zip",
      "download_url": "$(zip_uri "$BINGX_ZIP")",
      "sha256_hex": "$BINGX_SHA256"
    },
    {
      "id": "capsule-chat-test",
      "plugin_id": "hivra.contract.capsule-chat.v1",
      "display_name": "Capsule Chat (Test Plugin)",
      "version": "$CHAT_VERSION",
      "package_kind": "zip",
      "download_url": "$(zip_uri "$CHAT_ZIP")",
      "sha256_hex": "$CHAT_SHA256"
    }
  ]
}
JSON

echo "Synced plugin zips to: $SOURCE_DIR"
echo "Updated local source catalog: $CATALOG_PATH"
