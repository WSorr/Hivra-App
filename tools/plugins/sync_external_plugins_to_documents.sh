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

zip_uri() {
  python3 - "$1" <<'PY'
import pathlib, sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
}

sha256_hex() {
  shasum -a 256 "$1" | awk '{print tolower($1)}'
}

current_plugin_zip() {
  local plugin_name="$1"
  local manifest="$EXTERNAL_REPO/plugins/$plugin_name/manifest.json"
  local version
  version="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("release_version", d.get("version")))' "$manifest")"
  echo "$EXTERNAL_REPO/dist/plugins/${plugin_name}-${version}.zip"
}

BINGX_SOURCE_ZIP="$(current_plugin_zip bingx_futures_test_plugin)"
CHAT_SOURCE_ZIP="$(current_plugin_zip capsule_chat_test_plugin)"

for source_zip in "$BINGX_SOURCE_ZIP" "$CHAT_SOURCE_ZIP"; do
  if [[ ! -f "$source_zip" ]]; then
    echo "missing current plugin zip: $source_zip"
    exit 1
  fi
done

rm -f "$SOURCE_DIR"/bingx_futures_test_plugin-*.zip
rm -f "$SOURCE_DIR"/capsule_chat_test_plugin-*.zip
cp -f "$BINGX_SOURCE_ZIP" "$CHAT_SOURCE_ZIP" "$SOURCE_DIR"/

BINGX_ZIP="$SOURCE_DIR/$(basename "$BINGX_SOURCE_ZIP")"
CHAT_ZIP="$SOURCE_DIR/$(basename "$CHAT_SOURCE_ZIP")"
BINGX_ENTRY_ID="bingx-futures-test"
BINGX_PLUGIN_ID="hivra.contract.bingx-futures-trading.v1"
BINGX_DISPLAY_NAME="BingX Futures Trading (Test Plugin)"
BINGX_VERSION="$(basename "$BINGX_ZIP" | sed -E 's/^bingx_futures_test_plugin-([0-9.]+)\.zip$/\1/')"

BINGX_SHA256="$(sha256_hex "$BINGX_ZIP")"
CHAT_SHA256="$(sha256_hex "$CHAT_ZIP")"

CHAT_VERSION="$(basename "$CHAT_ZIP" | sed -E 's/^capsule_chat_test_plugin-([0-9.]+)\.zip$/\1/')"

cat > "$CATALOG_PATH" <<JSON
{
  "schema": "hivra.plugin.catalog",
  "version": 2,
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
