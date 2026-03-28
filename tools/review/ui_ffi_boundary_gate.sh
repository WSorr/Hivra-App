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
MAIN_IMPORTS="$(
  rg -n "import .*ffi/hivra_bindings.dart" "$ROOT/flutter/lib/main.dart" -S || true
)"

if [ -n "$SCREEN_IMPORTS" ]; then
  fail "screens must not import ffi/hivra_bindings.dart directly"
  echo "$SCREEN_IMPORTS"
else
  pass "no direct HivraBindings imports in flutter/lib/screens"
fi

if [ -n "$MAIN_IMPORTS" ]; then
  fail "main.dart must not import ffi/hivra_bindings.dart directly"
  echo "$MAIN_IMPORTS"
else
  pass "no direct HivraBindings import in flutter/lib/main.dart"
fi

exit "$STATUS"
