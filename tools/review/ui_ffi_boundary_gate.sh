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
WIDGET_IMPORTS="$(
  rg -n "import .*ffi/hivra_bindings.dart" "$ROOT/flutter/lib/widgets" -S || true
)"
UTIL_IMPORTS="$(
  rg -n "import .*ffi/hivra_bindings.dart" "$ROOT/flutter/lib/utils" -S || true
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

if [ -n "$WIDGET_IMPORTS" ]; then
  fail "widgets must not import ffi/hivra_bindings.dart directly"
  echo "$WIDGET_IMPORTS"
else
  pass "no direct HivraBindings imports in flutter/lib/widgets"
fi

if [ -n "$UTIL_IMPORTS" ]; then
  fail "utils must not import ffi/hivra_bindings.dart directly"
  echo "$UTIL_IMPORTS"
else
  pass "no direct HivraBindings imports in flutter/lib/utils"
fi

exit "$STATUS"
