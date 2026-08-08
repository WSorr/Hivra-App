#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0
CHECKLIST="$ROOT/docs/checklists/user-lifetime-safety-pack.md"
REQUIRED_PATTERNS=(
  '^## Scenario 0: Packaged Install And Clean Launch'
  '^## Scenario 1: First Capsule Birth'
  '^## Scenario 2: First Relationship'
  '^## Scenario 2A: Pair Consensus And Chat Continuity'
  '^## Scenario 2B: Plugin Lifecycle And Isolation'
  '^## Scenario 3: Recovery On New Device Path'
  '^## Scenario 4: Update Truth Preservation'
  'Deleting a capsule in canonical storage does not get silently undone by legacy-container migration on next launch'
  '^## Scenario 5: Long-Pending Invitation Stability'
  '^## Scenario 5A: Cross-Platform Restart And Capsule Isolation'
  '^## Automated Readiness Evidence'
)

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

coverage_complete() {
  local file="$1"
  local pattern
  for pattern in "${REQUIRED_PATTERNS[@]}"; do
    rg -q "$pattern" "$file" || return 1
  done
}

if [ -f "$CHECKLIST" ]; then
  pass "checklist exists"
else
  fail "checklist exists"
  exit "$STATUS"
fi

require_present "$CHECKLIST" '^## Scenario 0: Packaged Install And Clean Launch' \
  "covers packaged clean install"
require_present "$CHECKLIST" '^## Scenario 1: First Capsule Birth' \
  "covers first capsule birth"
require_present "$CHECKLIST" '^## Scenario 2: First Relationship' \
  "covers first relationship flow"
require_present "$CHECKLIST" '^## Scenario 2A: Pair Consensus And Chat Continuity' \
  "covers pair consensus and chat continuity"
require_present "$CHECKLIST" '^## Scenario 2B: Plugin Lifecycle And Isolation' \
  "covers plugin lifecycle and isolation"
require_present "$CHECKLIST" '^## Scenario 3: Recovery On New Device Path' \
  "covers recovery on clean runtime/device"
require_present "$CHECKLIST" '^## Scenario 4: Update Truth Preservation' \
  "covers update truth preservation"
require_present "$CHECKLIST" 'Deleting a capsule in canonical storage does not get silently undone by legacy-container migration on next launch' \
  "covers legacy migration rehydration guard"
require_present "$CHECKLIST" '^## Scenario 5: Long-Pending Invitation Stability' \
  "covers pending invitation stability"
require_present "$CHECKLIST" '^## Scenario 5A: Cross-Platform Restart And Capsule Isolation' \
  "covers cross-platform restart and Capsule isolation"
require_present "$CHECKLIST" '^## Automated Readiness Evidence' \
  "maps journey segments to existing automated evidence"

MUTATED_CHECKLIST="$(mktemp)"
trap 'rm -f "$MUTATED_CHECKLIST"' EXIT
cp "$CHECKLIST" "$MUTATED_CHECKLIST"
sed -i.bak '/^## Scenario 2A: Pair Consensus And Chat Continuity$/d' "$MUTATED_CHECKLIST"
rm -f "$MUTATED_CHECKLIST.bak"
if coverage_complete "$MUTATED_CHECKLIST"; then
  fail "negative self-test rejects missing journey coverage"
else
  pass "negative self-test rejects missing journey coverage"
fi

exit "$STATUS"
