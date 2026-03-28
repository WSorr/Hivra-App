#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS release-discipline: %s\n' "$1"
}

fail() {
  printf 'FAIL release-discipline: %s\n' "$1"
  STATUS=1
}

require_file() {
  local path="$1"
  local message="$2"
  if [ -f "$path" ]; then
    pass "$message"
  else
    fail "$message"
  fi
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

ROADMAP="$ROOT/docs/roadmap.md"
PRECHECK="$ROOT/tools/release/preflight.sh"
REVIEW_ALL="$ROOT/tools/review/review_all.sh"
CHECKLIST_MAC="$ROOT/docs/checklists/release-macos.md"
CHECKLIST_SMOKE="$ROOT/docs/checklists/manual-smoke.md"

require_file "$PRECHECK" "preflight script exists"
require_file "$CHECKLIST_MAC" "macOS release checklist exists"
require_file "$CHECKLIST_SMOKE" "manual smoke checklist exists"

require_present "$ROADMAP" '^### 6\. Release Preflight as a Gate' \
  "roadmap tracks release preflight gate"
require_present "$ROADMAP" '^### 7\. Public macOS Release Quality' \
  "roadmap tracks macOS release quality"

require_present "$CHECKLIST_MAC" 'tools/release/preflight\.sh' \
  "macOS checklist requires preflight run"
require_present "$CHECKLIST_MAC" 'codesign --verify --deep --strict' \
  "macOS checklist requires codesign verify"
require_present "$CHECKLIST_MAC" 'update path was evaluated for truth preservation' \
  "macOS checklist requires update truth-preservation verification"
require_present "$CHECKLIST_MAC" 'does not re-materialize previously resolved invitation history' \
  "macOS checklist requires no resolved-invite resurrection check"
require_present "$CHECKLIST_MAC" 'signed/notarized or test-only' \
  "macOS checklist requires signed/notarized disclosure in release notes"
require_present "$CHECKLIST_MAC" 'Release asset name clearly indicates version and target' \
  "macOS checklist requires packaging asset naming check"
require_present "$CHECKLIST_MAC" 'ZIP or DMG was rebuilt from the latest `.app`' \
  "macOS checklist requires package rebuild check"
require_present "$CHECKLIST_MAC" '`SHA256SUMS.txt` was regenerated' \
  "macOS checklist requires checksum regeneration check"
require_present "$CHECKLIST_MAC" 'Tester instructions are included if the build is unsigned' \
  "macOS checklist requires unsigned-build tester instructions"
require_present "$CHECKLIST_MAC" 'Correct Git tag exists on the intended commit' \
  "macOS checklist requires publish tag verification"
require_present "$CHECKLIST_MAC" 'GitHub Release assets match the latest local artifacts' \
  "macOS checklist requires publish artifact parity check"
require_present "$CHECKLIST_MAC" '`Pre-release` flag is correct' \
  "macOS checklist requires publish pre-release flag check"
require_present "$CHECKLIST_SMOKE" 'Invitation Flow' \
  "manual smoke checklist covers invitation flow"
require_present "$CHECKLIST_SMOKE" 'Relationship Flow' \
  "manual smoke checklist covers relationship flow"
require_present "$CHECKLIST_SMOKE" 'Ledger Truth' \
  "manual smoke checklist covers ledger truth projection"

require_present "$PRECHECK" 'tools/review/review_all\.sh' \
  "preflight executes review_all"
require_present "$PRECHECK" 'cargo test -p hivra-ffi' \
  "preflight executes Rust FFI tests"
require_present "$PRECHECK" 'flutter analyze' \
  "preflight executes flutter analyze"
require_present "$PRECHECK" 'flutter test' \
  "preflight executes flutter tests"
require_present "$PRECHECK" 'macOS Release Bundle Checks' \
  "preflight includes macOS release bundle check step"
require_present "$PRECHECK" 'check_release_bundle' \
  "preflight wires check_release_bundle"
require_present "$REVIEW_ALL" 'release_discipline_gate\.sh' \
  "review_all includes release discipline gate"

exit "$STATUS"
