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
SERVICE_IMPORTS="$(
  rg -n "import .*ffi/hivra_bindings.dart" "$ROOT/flutter/lib/services" -S || true
)"

declare -a SERVICE_ALLOWLIST=(
  "$ROOT/flutter/lib/services/app_runtime_service.dart"
  "$ROOT/flutter/lib/services/capsule_persistence_service.dart"
)
MAX_SERVICE_IMPORTS=4

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

if [ -n "$SERVICE_IMPORTS" ]; then
  SERVICE_IMPORT_COUNT="$(printf '%s\n' "$SERVICE_IMPORTS" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
  if [ "${SERVICE_IMPORT_COUNT}" -gt "${MAX_SERVICE_IMPORTS}" ]; then
    fail "services exceeded direct HivraBindings import budget (${SERVICE_IMPORT_COUNT} > ${MAX_SERVICE_IMPORTS})"
    printf '%s\n' "$SERVICE_IMPORTS"
  else
    pass "service-layer direct HivraBindings imports stay within budget (${SERVICE_IMPORT_COUNT}/${MAX_SERVICE_IMPORTS})"
  fi

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path_part="${line%%:*}"
    if [[ "$path_part" = /* ]]; then
      full_path="$path_part"
    else
      full_path="$ROOT/$path_part"
    fi
    allowed=0
    for item in "${SERVICE_ALLOWLIST[@]}"; do
      if [ "$full_path" = "$item" ]; then
        allowed=1
        break
      fi
    done
    if [ "$allowed" -ne 1 ]; then
      fail "service has direct HivraBindings import outside allowlist: $path_part"
    fi
  done <<< "$SERVICE_IMPORTS"
else
  pass "no direct HivraBindings imports in flutter/lib/services"
fi

exit "$STATUS"
