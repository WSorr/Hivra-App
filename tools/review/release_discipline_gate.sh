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

require_file "$PRECHECK" "preflight script exists"
require_file "$CHECKLIST_MAC" "macOS release checklist exists"

require_present "$ROADMAP" '^### 6\. Release Preflight as a Gate' \
  "roadmap tracks release preflight gate"
require_present "$ROADMAP" '^### 7\. Public macOS Release Quality' \
  "roadmap tracks macOS release quality"

require_present "$CHECKLIST_MAC" 'tools/release/preflight\.sh' \
  "macOS checklist requires preflight run"
require_present "$CHECKLIST_MAC" 'codesign --verify --deep --strict' \
  "macOS checklist requires codesign verify"

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
