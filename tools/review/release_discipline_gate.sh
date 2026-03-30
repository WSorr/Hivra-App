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
CHECKLIST_ANDROID="$ROOT/docs/checklists/release-android.md"
CHECKLIST_ANDROID_RUNTIME="$ROOT/docs/checklists/android-runtime-hardening.md"
CHECKLIST_SMOKE="$ROOT/docs/checklists/manual-smoke.md"
CHECKLIST_USER_LIFETIME="$ROOT/docs/checklists/user-lifetime-safety-pack.md"

require_file "$PRECHECK" "preflight script exists"
require_file "$CHECKLIST_MAC" "macOS release checklist exists"
require_file "$CHECKLIST_ANDROID" "Android release checklist exists"
require_file "$CHECKLIST_ANDROID_RUNTIME" "Android runtime hardening checklist exists"
require_file "$CHECKLIST_SMOKE" "manual smoke checklist exists"
require_file "$CHECKLIST_USER_LIFETIME" "user lifetime safety checklist exists"

require_present "$ROADMAP" '^### 6\. Release Preflight as a Gate' \
  "roadmap tracks release preflight gate"
require_present "$ROADMAP" '^### 7\. Public macOS Release Quality' \
  "roadmap tracks macOS release quality"
require_present "$ROADMAP" '^### 7\.2 Android Release Quality' \
  "roadmap tracks Android release quality"
require_present "$ROADMAP" '^### 8\.1 Android Runtime Hardening' \
  "roadmap tracks Android runtime hardening"

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
require_present "$CHECKLIST_MAC" 'User Lifetime Safety Pack' \
  "macOS checklist requires user lifetime safety pass"
require_present "$CHECKLIST_MAC" 'Correct Git tag exists on the intended commit' \
  "macOS checklist requires publish tag verification"
require_present "$CHECKLIST_MAC" 'GitHub Release assets match the latest local artifacts' \
  "macOS checklist requires publish artifact parity check"
require_present "$CHECKLIST_MAC" '`Pre-release` flag is correct' \
  "macOS checklist requires publish pre-release flag check"
require_present "$CHECKLIST_ANDROID" 'Invitation send succeeds' \
  "Android checklist covers invitation send flow"
require_present "$CHECKLIST_ANDROID" 'Invitation accept succeeds' \
  "Android checklist covers invitation accept flow"
require_present "$CHECKLIST_ANDROID" 'packaged release artifact' \
  "Android checklist requires packaged-artifact install verification"
require_present "$CHECKLIST_ANDROID" 'Outbound transport failure path was exercised' \
  "Android checklist covers transport diagnostics"
require_present "$CHECKLIST_ANDROID" 'Android keystore-backed seed storage behavior was validated' \
  "Android checklist covers keystore seed storage validation"
require_present "$CHECKLIST_ANDROID" 'Checksums were generated for published APK assets' \
  "Android checklist requires APK checksum verification"
require_present "$CHECKLIST_ANDROID" 'Release asset name clearly indicates version and target' \
  "Android checklist requires publish asset naming check"
require_present "$CHECKLIST_ANDROID" 'Release notes mention testing scope and known Android limitations' \
  "Android checklist requires publish release-notes scope check"
require_present "$CHECKLIST_ANDROID" 'User Lifetime Safety Pack' \
  "Android checklist requires user lifetime safety pass"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'matches ledger-first policy' \
  "Android runtime checklist covers ledger-first bootstrap parity"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'preserves active capsule selection' \
  "Android runtime checklist covers active-capsule stability on restart"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'Seed-to-capsule binding remains stable across app restart' \
  "Android runtime checklist covers restart seed-binding stability"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'Keystore-backed seed access is validated after cold restart' \
  "Android runtime checklist covers keystore cold-restart validation"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'does not silently reuse stale app-private seed state' \
  "Android runtime checklist covers reinstall stale-seed guard"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'Backup import path reconstructs the same ledger truth as before reinstall' \
  "Android runtime checklist covers backup-import truth parity"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'Outbound relay write failures surface actionable diagnostics' \
  "Android runtime checklist covers outbound transport diagnostics"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'Receive path diagnostics distinguish transport failure from projection/ledger failure' \
  "Android runtime checklist covers receive-path diagnostic separation"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'invitation send/accept projections match macOS for the same ledger history' \
  "Android runtime checklist covers invitation projection parity"
require_present "$CHECKLIST_ANDROID_RUNTIME" 'relationship break/re-invite projections match macOS for the same ledger history' \
  "Android runtime checklist covers relationship projection parity"
require_present "$CHECKLIST_SMOKE" 'Invitation Flow' \
  "manual smoke checklist covers invitation flow"
require_present "$CHECKLIST_SMOKE" 'Relationship Flow' \
  "manual smoke checklist covers relationship flow"
require_present "$CHECKLIST_SMOKE" 'Ledger Truth' \
  "manual smoke checklist covers ledger truth projection"
require_present "$CHECKLIST_USER_LIFETIME" 'Scenario 1: First Capsule Birth' \
  "user lifetime checklist covers capsule birth"
require_present "$CHECKLIST_USER_LIFETIME" 'Scenario 2: First Relationship' \
  "user lifetime checklist covers first relationship"
require_present "$CHECKLIST_USER_LIFETIME" 'Scenario 3: Recovery On New Device Path' \
  "user lifetime checklist covers recovery path"
require_present "$CHECKLIST_USER_LIFETIME" 'Scenario 4: Update Truth Preservation' \
  "user lifetime checklist covers update safety"
require_present "$CHECKLIST_USER_LIFETIME" 'Scenario 5: Long-Pending Invitation Stability' \
  "user lifetime checklist covers pending stability"

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
require_present "$PRECHECK" 'user_lifetime_safety_gate\.sh' \
  "preflight includes user lifetime safety gate"
require_present "$REVIEW_ALL" 'release_discipline_gate\.sh' \
  "review_all includes release discipline gate"
require_present "$REVIEW_ALL" 'user_lifetime_safety_gate\.sh' \
  "review_all includes user lifetime safety gate"

exit "$STATUS"
