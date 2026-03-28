#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS projection-discipline: %s\n' "$1"
}

fail() {
  printf 'FAIL projection-discipline: %s\n' "$1"
  STATUS=1
}

require_absent() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$path"; then
    fail "$message"
  else
    pass "$message"
  fi
}

require_present() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$path"; then
    pass "$message"
  else
    fail "$message"
  fi
}

INSPECTOR="$ROOT/flutter/lib/screens/ledger_inspector_screen.dart"
PAIRWISE="$ROOT/flutter/lib/services/pairwise_snapshot_service.dart"
SUPPORT="$ROOT/flutter/lib/services/ledger_view_support.dart"

require_present "$SUPPORT" 'String kindLabel\(dynamic kind\)' \
  "ledger support exposes canonical kindLabel mapper"

require_absent "$INSPECTOR" 'String _kindLabel\(' \
  "inspector does not declare local kindLabel dictionary"
require_present "$INSPECTOR" '_support\.kindLabel\(event\['"'"'kind'"'"'\]\)' \
  "inspector uses shared kindLabel mapping"

require_absent "$PAIRWISE" 'String _kindLabel\(' \
  "pairwise service does not declare local kindLabel dictionary"
require_present "$PAIRWISE" '_support\.kindLabel\(event\['"'"'kind'"'"'\]\)' \
  "pairwise service uses shared kindLabel mapping"

exit "$STATUS"
