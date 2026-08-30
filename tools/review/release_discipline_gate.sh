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

require_tracked_file() {
  local path="$1"
  local message="$2"
  if [ -f "$path" ] &&
     git -C "$ROOT" ls-files --error-unmatch "${path#$ROOT/}" >/dev/null 2>&1; then
    pass "$message"
  else
    fail "$message"
  fi
}

require_present() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q -- "$pattern" "$file"; then
    pass "$message"
  else
    fail "$message"
  fi
}

run_self_test() {
  local command="$1"
  local message="$2"
  if "$command" --self-test >/dev/null; then
    pass "$message"
  else
    fail "$message"
  fi
}

PRECHECK="$ROOT/tools/release/preflight.sh"
MAC_RELEASE_SCRIPT="$ROOT/tools/release/macos_release.sh"
ANDROID_RELEASE_SCRIPT="$ROOT/tools/release/android_release.sh"
RELEASE_VERSION_GUARD="$ROOT/tools/release/release_version_guard.sh"
DRONE_EVIDENCE_CHECK="$ROOT/tools/release/check_trading_drone_evidence.sh"
DRONE_EVIDENCE_FIXTURE="$ROOT/tools/release/trading_drone_evidence_fixture.json"
MANUAL_SIGNOFF_CHECK="$ROOT/tools/release/check_manual_release_signoff.sh"
GITHUB_RELEASE_PUBLISH="$ROOT/tools/release/publish_github_release.sh"
FLUTTER_VERSION_DERIVER="$ROOT/tools/release/derive_flutter_version.sh"
REVIEW_ALL="$ROOT/tools/review/review_all.sh"
CI_REPOSITORY_GATES="$ROOT/.github/workflows/release-gates.yml"
TOOLCHAIN_VERIFY="$ROOT/tools/toolchain/verify_environment.sh"
TOOLCHAIN_BASELINE="$ROOT/toolchains/hivra-baseline.conf"

for path in \
  "$PRECHECK" \
  "$MAC_RELEASE_SCRIPT" \
  "$ANDROID_RELEASE_SCRIPT" \
  "$RELEASE_VERSION_GUARD" \
  "$DRONE_EVIDENCE_CHECK" \
  "$DRONE_EVIDENCE_FIXTURE" \
  "$MANUAL_SIGNOFF_CHECK" \
  "$GITHUB_RELEASE_PUBLISH" \
  "$FLUTTER_VERSION_DERIVER" \
  "$CI_REPOSITORY_GATES" \
  "$TOOLCHAIN_VERIFY" \
  "$TOOLCHAIN_BASELINE" \
  "$ROOT/docs/checklists/release-macos.md" \
  "$ROOT/docs/checklists/release-android.md" \
  "$ROOT/docs/checklists/manual-smoke.md" \
  "$ROOT/docs/checklists/release-manual-signoff-log.md" \
  "$ROOT/docs/checklists/user-lifetime-safety-pack.md" \
  "$ROOT/docs/checklists/trading-drone-evidence-log.md" \
  "$ROOT/docs/checklists/moltbook-release-smoke.md" \
  "$ROOT/docs/checklists/capsule-analyst-release-smoke.md"; do
  require_file "$path" "${path#$ROOT/} exists"
done

for path in \
  "$ROOT/Cargo.lock" \
  "$ROOT/flutter/pubspec.lock" \
  "$ROOT/flutter/android/gradle/wrapper/gradle-wrapper.jar" \
  "$ROOT/flutter/android/gradlew" \
  "$ROOT/flutter/android/gradlew.bat"; do
  require_tracked_file "$path" "${path#$ROOT/} is repository-owned"
done

require_present "$CI_REPOSITORY_GATES" '^name: Hivra Repository Gates$' \
  "repository workflow keeps the required name"
require_present "$CI_REPOSITORY_GATES" '^  pull_request:$' \
  "repository workflow validates pull requests"
require_present "$CI_REPOSITORY_GATES" '^  push:$' \
  "repository workflow validates main pushes"
require_present "$CI_REPOSITORY_GATES" '^  review-gates:$' \
  "repository workflow keeps the required status context"
require_present "$CI_REPOSITORY_GATES" 'tools/review/review_all\.sh' \
  "repository workflow executes review gates"
require_present "$CI_REPOSITORY_GATES" 'tools/toolchain/verify_environment\.sh --static' \
  "repository workflow verifies toolchain pins"
require_present "$CI_REPOSITORY_GATES" 'tools/toolchain/verify_environment\.sh --self-test' \
  "repository workflow proves toolchain mismatch failure"
require_present "$CI_REPOSITORY_GATES" 'tools/release/check_manual_release_signoff\.sh --self-test' \
  "repository workflow runs signoff mutations"

run_self_test "$RELEASE_VERSION_GUARD" \
  "release version guard self-test passes"
run_self_test "$DRONE_EVIDENCE_CHECK" \
  "trading evidence mutation self-test passes"
run_self_test "$MANUAL_SIGNOFF_CHECK" \
  "manual signoff mutation self-test passes"
run_self_test "$GITHUB_RELEASE_PUBLISH" \
  "release artifact-binding self-test passes"

if "$FLUTTER_VERSION_DERIVER" --self-test >/dev/null &&
   [ "$("$FLUTTER_VERSION_DERIVER" --version v1.0.3-test4 --field name)" = "1.0.3" ] &&
   [ "$("$FLUTTER_VERSION_DERIVER" --version v1.0.3-test4 --field number)" = "100030004" ]; then
  pass "Flutter artifact version derivation is deterministic"
else
  fail "Flutter artifact version derivation is deterministic"
fi

require_present "$PRECHECK" 'tools/review/review_all\.sh' \
  "preflight executes review gates"
require_present "$PRECHECK" 'tools/toolchain/verify_environment\.sh' \
  "preflight verifies the pinned toolchain"
require_present "$PRECHECK" 'flutter pub get --enforce-lockfile' \
  "preflight enforces the Flutter dependency lock"
require_present "$PRECHECK" 'cargo test --locked -p hivra-ffi' \
  "preflight tests Rust against the dependency lock"
require_present "$PRECHECK" 'flutter analyze' \
  "preflight analyzes Flutter"
require_present "$PRECHECK" 'flutter test' \
  "preflight tests Flutter"
require_present "$PRECHECK" 'check_release_bundle' \
  "preflight validates the macOS bundle"
require_present "$PRECHECK" 'check_packaged_macos_release_bundle' \
  "preflight validates the packaged macOS artifact"
require_present "$PRECHECK" 'check_android_release_bundle' \
  "preflight validates the Android bundle"
require_present "$PRECHECK" 'check_trading_drone_evidence_coverage' \
  "preflight validates trading evidence"
require_present "$PRECHECK" 'user_lifetime_safety_gate\.sh' \
  "preflight validates user-lifetime coverage"

for script in "$MAC_RELEASE_SCRIPT" "$ANDROID_RELEASE_SCRIPT"; do
  require_present "$script" 'release_version_guard\.sh' \
    "${script#$ROOT/} enforces release sequencing"
  require_present "$script" 'require_clean_tracked_worktree' \
    "${script#$ROOT/} requires clean source"
  require_present "$script" 'source_commit=\$SOURCE_COMMIT' \
    "${script#$ROOT/} records source commit"
  require_present "$script" 'source_tree_dirty=no' \
    "${script#$ROOT/} records clean source"
  require_present "$script" 'trading-evidence-build-tag "\$VERSION"' \
    "${script#$ROOT/} binds trading evidence to version"
  require_present "$script" '\-\-build-name "\$FLUTTER_BUILD_NAME"' \
    "${script#$ROOT/} embeds the derived version"
done

if [ "$(rg -c 'require_clean_tracked_worktree' "$MAC_RELEASE_SCRIPT")" -ge 3 ] &&
   [ "$(rg -c 'require_clean_tracked_worktree' "$ANDROID_RELEASE_SCRIPT")" -ge 3 ]; then
  pass "release packaging rechecks source after preflight and build"
else
  fail "release packaging rechecks source after preflight and build"
fi

if rg -q -- '--skip-preflight|--skip-build' \
  "$MAC_RELEASE_SCRIPT" "$ANDROID_RELEASE_SCRIPT"; then
  fail "release scripts expose forbidden bypass flags"
else
  pass "release scripts expose no preflight or build bypass"
fi

require_present "$GITHUB_RELEASE_PUBLISH" 'check_manual_release_signoff\.sh' \
  "publication enforces manual signoff"
require_present "$GITHUB_RELEASE_PUBLISH" 'preflight\.sh' \
  "publication enforces automated preflight"
require_present "$GITHUB_RELEASE_PUBLISH" 'gh release create' \
  "publication has one release creation path"
require_present "$GITHUB_RELEASE_PUBLISH" 'require_clean_tracked_worktree' \
  "publication requires clean source"
require_present "$GITHUB_RELEASE_PUBLISH" 'require_tag_points_to_head' \
  "publication binds the tag to HEAD"
require_present "$GITHUB_RELEASE_PUBLISH" 'verify_release_metadata' \
  "publication verifies artifact metadata"

require_present "$REVIEW_ALL" 'release_discipline_gate\.sh' \
  "review_all includes release discipline"
require_present "$REVIEW_ALL" 'user_lifetime_safety_gate\.sh' \
  "review_all includes user-lifetime safety"

exit "$STATUS"
