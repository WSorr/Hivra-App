#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() { echo "PASS ui-ffi: $1"; }
fail() {
  echo "FAIL ui-ffi: $1"
  STATUS=1
}

SCREEN_IMPORTS="$(
  rg -n "import .*ffi/hivra_bindings.dart" "$ROOT/flutter/lib/screens" -S || true
)"

if [ -n "$SCREEN_IMPORTS" ]; then
  fail "screens must not import ffi/hivra_bindings.dart directly"
  echo "$SCREEN_IMPORTS"
else
  pass "no direct HivraBindings imports in flutter/lib/screens"
fi

exit "$STATUS"
