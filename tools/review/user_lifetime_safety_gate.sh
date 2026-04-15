#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0
CHECKLIST="$ROOT/docs/checklists/user-lifetime-safety-pack.md"

pass() {
  printf 'PASS user-lifetime-safety: %s\n' "$1"
}

fail() {
  printf 'FAIL user-lifetime-safety: %s\n' "$1"
  STATUS=1
}

require_present() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    pass "$message"
  else
    fail "$message"
  fi
}

if [ -f "$CHECKLIST" ]; then
  pass "checklist exists"
else
  fail "checklist exists"
  exit "$STATUS"
fi

require_present "$CHECKLIST" '^## Scenario 1: First Capsule Birth' \
  "covers first capsule birth"
require_present "$CHECKLIST" '^## Scenario 2: First Relationship' \
  "covers first relationship flow"
require_present "$CHECKLIST" '^## Scenario 3: Recovery On New Device Path' \
  "covers recovery on clean runtime/device"
require_present "$CHECKLIST" '^## Scenario 4: Update Truth Preservation' \
  "covers update truth preservation"
require_present "$CHECKLIST" 'Deleting a capsule in canonical storage does not get silently undone by legacy-container migration on next launch' \
  "covers legacy migration rehydration guard"
require_present "$CHECKLIST" '^## Scenario 5: Long-Pending Invitation Stability' \
  "covers pending invitation stability"

exit "$STATUS"
