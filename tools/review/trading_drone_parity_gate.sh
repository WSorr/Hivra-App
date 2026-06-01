#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKLIST="$ROOT/docs/checklists/trading-drone-spec-runtime-parity.md"
STATUS=0

pass() {
  printf 'PASS trading-drone-parity: %s\n' "$1"
}

fail() {
  printf 'FAIL trading-drone-parity: %s\n' "$1"
  STATUS=1
}

if [ ! -f "$CHECKLIST" ]; then
  fail "missing checklist: $CHECKLIST"
  exit "$STATUS"
fi

pass "checklist exists"

UNRESOLVED="$(awk -F'|' '
function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
BEGIN { in_table = 0; rows = 0; done_rows = 0 }
$0 ~ /^\| Area \| Status \| Runtime Evidence \| Remaining Debt \|$/ { in_table = 1; next }
in_table && $0 ~ /^\|---/ { next }
in_table && $0 !~ /^\|/ { in_table = 0; next }
in_table && $0 ~ /^\|/ {
  area = trim($2)
  status = trim($3)
  if (area == "" || status == "" || area == "Area" || status == "Status") next
  rows += 1
  if (status == "DONE") done_rows += 1
  if (status == "TODO" || status == "PARTIAL") {
    print area " [" status "]"
  }
}
END {
  if (rows == 0) print "__NO_ROWS__"
  else if (done_rows == 0) print "__NO_DONE_ROWS__"
}
' "$CHECKLIST")"

if printf '%s\n' "$UNRESOLVED" | rg -q '^__NO_ROWS__$'; then
  fail "runtime status table is missing or unparsable"
elif printf '%s\n' "$UNRESOLVED" | rg -q '^__NO_DONE_ROWS__$'; then
  fail "runtime status table has no DONE rows"
elif [ -n "$UNRESOLVED" ]; then
  fail "runtime status table still has unresolved rows:"
  printf '%s\n' "$UNRESOLVED" | sed 's/^/  - /'
else
  pass "runtime status table has no TODO/PARTIAL rows"
fi

exit "$STATUS"
