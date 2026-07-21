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
  if rg -q -- "$pattern" "$file"; then
    pass "$message"
  else
    fail "$message"
  fi
}

ROADMAP="$ROOT/docs/roadmap.md"
PRECHECK="$ROOT/tools/release/preflight.sh"
MAC_RELEASE_SCRIPT="$ROOT/tools/release/macos_release.sh"
ANDROID_RELEASE_SCRIPT="$ROOT/tools/release/android_release.sh"
RELEASE_VERSION_GUARD="$ROOT/tools/release/release_version_guard.sh"
REVIEW_ALL="$ROOT/tools/review/review_all.sh"
CI_RELEASE_GATES="$ROOT/.github/workflows/release-gates.yml"
CHECKLIST_MAC="$ROOT/docs/checklists/release-macos.md"
CHECKLIST_ANDROID="$ROOT/docs/checklists/release-android.md"
CHECKLIST_ANDROID_RUNTIME="$ROOT/docs/checklists/android-runtime-hardening.md"
CHECKLIST_SMOKE="$ROOT/docs/checklists/manual-smoke.md"
CHECKLIST_USER_LIFETIME="$ROOT/docs/checklists/user-lifetime-safety-pack.md"
CHECKLIST_AI_ENGINEER_SMOKE="$ROOT/docs/checklists/ai-engineer-release-smoke.md"
CHECKLIST_MANUAL_SIGNOFF="$ROOT/docs/checklists/release-manual-signoff-log.md"
CHECKLIST_DRONE_PARITY="$ROOT/docs/checklists/trading-drone-spec-runtime-parity.md"
CHECKLIST_DRONE_EVIDENCE="$ROOT/docs/checklists/trading-drone-evidence-log.md"
DRONE_GOAL_CONTRACT="$ROOT/docs/plugins/bingx_futures_trading_drone_goal_contract_v1.md"
DRONE_EVIDENCE_RECORD="$ROOT/tools/release/record_trading_drone_evidence.sh"
DRONE_EVIDENCE_CHECK="$ROOT/tools/release/check_trading_drone_evidence.sh"
MANUAL_SIGNOFF_CHECK="$ROOT/tools/release/check_manual_release_signoff.sh"
GITHUB_RELEASE_PUBLISH="$ROOT/tools/release/publish_github_release.sh"
FLUTTER_VERSION_DERIVER="$ROOT/tools/release/derive_flutter_version.sh"

require_file "$PRECHECK" "preflight script exists"
require_file "$MAC_RELEASE_SCRIPT" "macOS release script exists"
require_file "$ANDROID_RELEASE_SCRIPT" "Android release script exists"
require_file "$RELEASE_VERSION_GUARD" "release version guard exists"
require_file "$CHECKLIST_MAC" "macOS release checklist exists"
require_file "$CHECKLIST_ANDROID" "Android release checklist exists"
require_file "$CHECKLIST_ANDROID_RUNTIME" "Android runtime hardening checklist exists"
require_file "$CHECKLIST_SMOKE" "manual smoke checklist exists"
require_file "$CHECKLIST_USER_LIFETIME" "user lifetime safety checklist exists"
require_file "$CHECKLIST_AI_ENGINEER_SMOKE" "AI Engineer release smoke checklist exists"
require_file "$CHECKLIST_MANUAL_SIGNOFF" "manual release signoff log exists"
require_file "$CHECKLIST_DRONE_PARITY" "trading drone spec/runtime parity checklist exists"
require_file "$CHECKLIST_DRONE_EVIDENCE" "trading drone evidence log exists"
require_file "$DRONE_GOAL_CONTRACT" "trading drone goal contract exists"
require_file "$DRONE_EVIDENCE_RECORD" "trading drone evidence-record script exists"
require_file "$DRONE_EVIDENCE_CHECK" "trading drone evidence-check script exists"
require_file "$MANUAL_SIGNOFF_CHECK" "manual release signoff-check script exists"
require_file "$GITHUB_RELEASE_PUBLISH" "guarded GitHub release publish script exists"
require_file "$FLUTTER_VERSION_DERIVER" "Flutter artifact version derivation exists"
require_file "$CI_RELEASE_GATES" "root GitHub release-gates workflow exists"

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
require_present "$CHECKLIST_MAC" 'Tracked worktree and index are clean before packaging' \
  "macOS checklist requires clean tracked worktree"
require_present "$MAC_RELEASE_SCRIPT" 'release_version_guard\.sh' \
  "macOS release packaging enforces the published version line"
require_present "$ANDROID_RELEASE_SCRIPT" 'release_version_guard\.sh' \
  "Android release packaging enforces the published version line"
require_present "$RELEASE_VERSION_GUARD" 'allowed_next_test_versions\(\)' \
  "release version guard derives allowed next test tags"
require_present "$RELEASE_VERSION_GUARD" 'next_patch_base\(\)' \
  "release version guard allows next patch test train"
require_present "$RELEASE_VERSION_GUARD" 'is_allowed_next_test_version "\$latest" "\$VERSION"' \
  "release version guard rejects skipped test release numbers"
require_present "$RELEASE_VERSION_GUARD" '--allow-existing-remote-tag' \
  "release version guard supports publication-only existing tag mode"
require_present "$RELEASE_VERSION_GUARD" 'self-test' \
  "release version guard has network-free self-test"
require_present "$RELEASE_VERSION_GUARD" 'EXPECTED_REPOSITORY="WSorr/Hivra-App"' \
  "release version guard pins the canonical GitHub repository"
require_present "$CHECKLIST_MAC" 'tools/release/macos_release\.sh' \
  "macOS checklist requires scripted release packaging"
require_present "$CHECKLIST_MAC" 'explicit `--channel` \(`test` or `public`\)' \
  "macOS checklist requires explicit channel selection"
require_present "$CHECKLIST_MAC" 'codesign --verify --deep --strict' \
  "macOS checklist requires codesign verify"
require_present "$CHECKLIST_MAC" 'Packaged ZIP artifact was unpacked and verified' \
  "macOS checklist requires packaged-artifact verification"
require_present "$CHECKLIST_MAC" 'update path was evaluated for truth preservation' \
  "macOS checklist requires update truth-preservation verification"
require_present "$CHECKLIST_MAC" 'does not re-materialize previously resolved invitation history' \
  "macOS checklist requires no resolved-invite resurrection check"
require_present "$CHECKLIST_MAC" 'does not rehydrate deleted canonical capsule files on relaunch' \
  "macOS checklist requires no legacy rehydration after deletion"
require_present "$CHECKLIST_MAC" 'Trading Drone smoke gate completed' \
  "macOS checklist requires trading drone smoke gate"
require_present "$CHECKLIST_MAC" 'Trading drone spec/runtime parity checklist was completed' \
  "macOS checklist requires drone spec/runtime parity completion"
require_present "$CHECKLIST_MAC" 'AI Engineer release smoke checklist was completed' \
  "macOS checklist requires AI Engineer smoke completion"
require_present "$CHECKLIST_MAC" 'Trading Drone evidence row recorded in `docs/checklists/trading-drone-evidence-log\.md`' \
  "macOS checklist requires trading drone evidence log row"
require_present "$CHECKLIST_MAC" 'tools/release/record_trading_drone_evidence\.sh' \
  "macOS checklist requires trading drone evidence-record script reference"
require_present "$CHECKLIST_MAC" 'tools/release/check_trading_drone_evidence\.sh --build-tag <version-tag>' \
  "macOS checklist requires trading drone evidence-coverage check command"
require_present "$CHECKLIST_MAC" '`situational` decision envelope hash captured' \
  "macOS checklist requires situational decision hash capture"
require_present "$CHECKLIST_MAC" '`interactive` parity hash verified' \
  "macOS checklist requires interactive parity hash verification"
require_present "$CHECKLIST_MAC" 'risk-block and retry paths exercised' \
  "macOS checklist requires risk-block/retry smoke"
require_present "$CHECKLIST_MAC" 'execution envelope receipt hash captured' \
  "macOS checklist requires execution receipt hash capture"
require_present "$CHECKLIST_MAC" 'signed/notarized or test-only' \
  "macOS checklist requires signed/notarized disclosure in release notes"
require_present "$CHECKLIST_MAC" 'RELEASE-METADATA\.txt' \
  "macOS checklist requires release metadata traceability"
require_present "$CHECKLIST_MAC" 'source_tree_dirty=no' \
  "macOS checklist requires clean-source metadata"
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
require_present "$CHECKLIST_MAC" 'release-manual-signoff-log\.md' \
  "macOS checklist requires manual signoff log"
require_present "$CHECKLIST_MAC" 'tools/release/check_manual_release_signoff\.sh --build-tag <version-tag> --platform macOS' \
  "macOS checklist requires platform manual signoff check"
require_present "$CHECKLIST_MAC" 'tools/release/publish_github_release\.sh' \
  "macOS checklist requires guarded GitHub publication"
require_present "$CHECKLIST_MAC" 'GitHub Release assets match the latest local artifacts' \
  "macOS checklist requires publish artifact parity check"
require_present "$CHECKLIST_MAC" '`Pre-release` flag is correct' \
  "macOS checklist requires publish pre-release flag check"
require_present "$CHECKLIST_MAC" '`test` => pre-release, `public` => stable release' \
  "macOS checklist requires pre-release flag/channel mapping"
require_present "$CHECKLIST_ANDROID" 'Invitation send succeeds' \
  "Android checklist covers invitation send flow"
require_present "$CHECKLIST_ANDROID" 'Invitation accept succeeds' \
  "Android checklist covers invitation accept flow"
require_present "$CHECKLIST_ANDROID" 'Trading Drone smoke gate completed' \
  "Android checklist requires trading drone smoke gate"
require_present "$CHECKLIST_ANDROID" 'Trading drone spec/runtime parity checklist was completed' \
  "Android checklist requires drone spec/runtime parity completion"
require_present "$CHECKLIST_ANDROID" 'Trading Drone evidence row recorded in `docs/checklists/trading-drone-evidence-log\.md`' \
  "Android checklist requires trading drone evidence log row"
require_present "$CHECKLIST_ANDROID" 'tools/release/record_trading_drone_evidence\.sh' \
  "Android checklist requires trading drone evidence-record script reference"
require_present "$CHECKLIST_ANDROID" 'tools/release/check_trading_drone_evidence\.sh --build-tag <version-tag>' \
  "Android checklist requires trading drone evidence-coverage check command"
require_present "$CHECKLIST_ANDROID" '`situational` decision envelope hash captured' \
  "Android checklist requires situational decision hash capture"
require_present "$CHECKLIST_ANDROID" '`interactive` parity hash verified' \
  "Android checklist requires interactive parity hash verification"
require_present "$CHECKLIST_ANDROID" 'risk-block and retry paths exercised' \
  "Android checklist requires risk-block/retry smoke"
require_present "$CHECKLIST_ANDROID" 'execution envelope receipt hash captured' \
  "Android checklist requires execution receipt hash capture"
require_present "$CHECKLIST_ANDROID" 'tools/release/android_release\.sh' \
  "Android checklist requires scripted release packaging"
require_present "$CHECKLIST_ANDROID" 'Tracked worktree and index are clean before packaging' \
  "Android checklist requires clean tracked worktree"
require_present "$CHECKLIST_ANDROID" 'explicitly \(`test` for internal/pre-release, `public` for stable release\)' \
  "Android checklist requires explicit channel selection"
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
require_present "$CHECKLIST_ANDROID" 'release-manual-signoff-log\.md' \
  "Android checklist requires manual signoff log"
require_present "$CHECKLIST_ANDROID" 'tools/release/check_manual_release_signoff\.sh --build-tag <version-tag> --platform Android' \
  "Android checklist requires platform manual signoff check"
require_present "$CHECKLIST_ANDROID" 'tools/release/publish_github_release\.sh' \
  "Android checklist requires guarded GitHub publication"
require_present "$CHECKLIST_ANDROID" 'RELEASE-METADATA\.txt' \
  "Android checklist requires release metadata traceability"
require_present "$CHECKLIST_ANDROID" 'source_tree_dirty=no' \
  "Android checklist requires clean-source metadata"
require_present "$CHECKLIST_ANDROID" 'Release notes mention testing scope and known Android limitations' \
  "Android checklist requires publish release-notes scope check"
require_present "$CHECKLIST_ANDROID" '`test` => pre-release, `public` => stable release' \
  "Android checklist requires pre-release flag/channel mapping"
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
require_present "$CHECKLIST_SMOKE" 'Trading Drone \(Observability Gate\)' \
  "manual smoke checklist covers trading drone observability gate"
require_present "$CHECKLIST_SMOKE" 'before GitHub' \
  "manual smoke checklist is explicitly before GitHub publication"
require_present "$CHECKLIST_SMOKE" 'release-manual-signoff-log\.md' \
  "manual smoke checklist writes canonical signoff log"
require_present "$CHECKLIST_SMOKE" 'Trading drone parity checklist is completed' \
  "manual smoke checklist requires drone parity checklist completion"
require_present "$CHECKLIST_SMOKE" 'drone\.decision\.envelope' \
  "manual smoke checklist requires decision envelope visibility"
require_present "$CHECKLIST_SMOKE" 'drone\.execution\.envelope' \
  "manual smoke checklist requires execution envelope visibility"
require_present "$CHECKLIST_DRONE_PARITY" '## Hivra Laws \(Non-Negotiable\)' \
  "drone parity checklist includes Hivra laws gate"
require_present "$CHECKLIST_DRONE_PARITY" 'Modularity: decision/risk/execution logic stays in services; UI is projection-only' \
  "drone parity checklist enforces modularity"
require_present "$CHECKLIST_DRONE_PARITY" 'Determinism: same normalized snapshot \+ same policy => same decision hash' \
  "drone parity checklist enforces determinism"
require_present "$CHECKLIST_DRONE_PARITY" 'Downward dependencies: `UI -> app services -> plugin host API -> adapter` only' \
  "drone parity checklist enforces downward dependencies"
require_present "$CHECKLIST_DRONE_PARITY" '## Spec vs Runtime Matrix' \
  "drone parity checklist includes spec/runtime matrix"
require_present "$CHECKLIST_DRONE_PARITY" '## Test Evidence \(Required\)' \
  "drone parity checklist includes test evidence gate"
require_present "$CHECKLIST_DRONE_PARITY" '## Manual Verification \(Release Candidate\)' \
  "drone parity checklist includes manual verification gate"
require_present "$CHECKLIST_DRONE_EVIDENCE" '^# Trading Drone Evidence Log' \
  "drone evidence log has canonical title"
require_present "$CHECKLIST_DRONE_EVIDENCE" '\| Build Tag \| Date \(UTC\) \| Platform \| Mode \| Decision Envelope Hash \| Execution Envelope Hash \| Risk Path \| Notes \|' \
  "drone evidence log includes required evidence table columns"
require_present "$CHECKLIST_DRONE_EVIDENCE" 'Required Coverage Per Candidate' \
  "drone evidence log includes per-candidate coverage requirements"
require_present "$CHECKLIST_DRONE_EVIDENCE" 'tools/release/check_trading_drone_evidence\.sh --build-tag <version-tag>' \
  "drone evidence log includes coverage verification command"
require_present "$CHECKLIST_DRONE_EVIDENCE" 'release approval is recorded separately' \
  "drone evidence log cannot replace manual release signoff"
require_present "$CHECKLIST_MANUAL_SIGNOFF" '\| Build Tag \| Date \(UTC\) \| Platform \| Artifact \| Manual Smoke \| Trading Smoke \| User Lifetime \| AI Engineer \| Signer \| Notes \|' \
  "manual signoff log includes required table columns"
require_present "$DRONE_EVIDENCE_CHECK" '\^\[0-9a-fA-F\]\{64\}\$' \
  "drone evidence checker requires canonical 64-hex hashes"
require_present "$MANUAL_SIGNOFF_CHECK" '--self-test' \
  "manual signoff checker has network-free self-test"
if "$MANUAL_SIGNOFF_CHECK" --self-test >/dev/null; then
  pass "manual signoff checker self-test passes"
else
  fail "manual signoff checker self-test passes"
fi
require_present "$DRONE_GOAL_CONTRACT" '## 2\. Three Hivra Laws \(Mandatory\)' \
  "drone goal contract includes Hivra laws section"
require_present "$DRONE_GOAL_CONTRACT" '## 3\. Source-of-Truth Stack \(Order of Authority\)' \
  "drone goal contract includes source-of-truth stack"
require_present "$DRONE_GOAL_CONTRACT" '## 6\. Work Cadence for Every Drone Change' \
  "drone goal contract includes mandatory work cadence"
require_present "$DRONE_GOAL_CONTRACT" '## 7\. Acceptance Gates \(Must Pass Together\)' \
  "drone goal contract includes acceptance gates"
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
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Capsule Analyst opens from Settings' \
  "AI Engineer smoke covers Capsule Analyst entry"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Outbound preview is shown before provider submission' \
  "AI Engineer smoke covers scoped AI preview"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Last selected inference provider persists across Capsule Analyst and' \
  "AI Engineer smoke covers provider preference persistence"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Installed plugin package audit renders package digest' \
  "AI Engineer smoke covers Plugin Auditor evidence"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Developer Mode is disabled by default' \
  "AI Engineer smoke covers Developer Mode boundary"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Workspace preview scans only explicit local repository paths' \
  "AI Engineer smoke covers Workspace Preview"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Selected Context includes only user-selected allowlisted files' \
  "AI Engineer smoke covers Selected Context"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Hivra Engineer outbound preview shows capsule snapshot hash' \
  "AI Engineer smoke covers Hivra Engineer outbound preview"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'Preview/Ask Hivra Engineer stays disabled until selected context has at' \
  "AI Engineer smoke covers empty selected-context guard"
require_present "$CHECKLIST_AI_ENGINEER_SMOKE" 'AI advisory output is marked unverified until required gates are run' \
  "AI Engineer smoke covers Review Gate integration"

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
require_present "$PRECHECK" 'Packaged macOS Artifact Checks' \
  "preflight includes packaged macOS artifact check step"
require_present "$PRECHECK" 'check_packaged_macos_release_bundle' \
  "preflight wires packaged macOS artifact validation"
require_present "$PRECHECK" 'Android Release Bundle Checks' \
  "preflight includes Android release bundle check step"
require_present "$PRECHECK" 'check_android_release_bundle' \
  "preflight wires check_android_release_bundle"
require_present "$PRECHECK" 'Trading Drone Evidence Coverage' \
  "preflight includes trading drone evidence coverage step"
require_present "$PRECHECK" 'check_trading_drone_evidence_coverage' \
  "preflight wires trading drone evidence coverage"
require_present "$PRECHECK" 'Missing required --trading-evidence-build-tag' \
  "preflight requires trading evidence build tag"
require_present "$GITHUB_RELEASE_PUBLISH" 'check_manual_release_signoff\.sh' \
  "GitHub publish script enforces manual signoff"
require_present "$GITHUB_RELEASE_PUBLISH" 'preflight\.sh' \
  "GitHub publish script enforces automated preflight"
require_present "$GITHUB_RELEASE_PUBLISH" 'gh release create' \
  "GitHub publish script owns release creation"
require_present "$GITHUB_RELEASE_PUBLISH" 'require_clean_tracked_worktree' \
  "GitHub publish script requires clean tracked worktree"
require_present "$GITHUB_RELEASE_PUBLISH" 'require_tag_points_to_head' \
  "GitHub publish script requires release tag to point at HEAD"
require_present "$GITHUB_RELEASE_PUBLISH" 'verify_release_metadata' \
  "GitHub publish script verifies packaged artifact metadata"
require_present "$GITHUB_RELEASE_PUBLISH" '--allow-existing-remote-tag' \
  "GitHub publish script allows already-pushed release tags only at publication"
require_present "$MAC_RELEASE_SCRIPT" 'require_clean_tracked_worktree' \
  "macOS release packaging requires clean tracked worktree"
require_present "$ANDROID_RELEASE_SCRIPT" 'require_clean_tracked_worktree' \
  "Android release packaging requires clean tracked worktree"
require_present "$MAC_RELEASE_SCRIPT" 'source_commit=\$SOURCE_COMMIT' \
  "macOS release metadata records source commit"
require_present "$ANDROID_RELEASE_SCRIPT" 'source_commit=\$SOURCE_COMMIT' \
  "Android release metadata records source commit"
require_present "$MAC_RELEASE_SCRIPT" 'source_tree_dirty=no' \
  "macOS release metadata records clean source tree"
require_present "$ANDROID_RELEASE_SCRIPT" 'source_tree_dirty=no' \
  "Android release metadata records clean source tree"
require_present "$MAC_RELEASE_SCRIPT" 'trading-evidence-build-tag "\$VERSION"' \
  "macOS release binds evidence coverage to release version"
require_present "$ANDROID_RELEASE_SCRIPT" 'trading-evidence-build-tag "\$VERSION"' \
  "Android release binds evidence coverage to release version"
require_present "$MAC_RELEASE_SCRIPT" '\-\-build-name "\$FLUTTER_BUILD_NAME"' \
  "macOS release embeds derived release version"
require_present "$ANDROID_RELEASE_SCRIPT" '\-\-build-name "\$FLUTTER_BUILD_NAME"' \
  "Android release embeds derived release version"
if rg -q -- '--skip-preflight|--skip-build' \
  "$MAC_RELEASE_SCRIPT" "$ANDROID_RELEASE_SCRIPT"; then
  fail "release scripts expose forbidden preflight/build bypass flags"
else
  pass "release scripts do not expose preflight/build bypass flags"
fi
if [ "$("$FLUTTER_VERSION_DERIVER" \
  --version v1.0.3-test4 --field name)" = "1.0.3" ] &&
   [ "$("$FLUTTER_VERSION_DERIVER" \
  --version v1.0.3-test4 --field number)" = "100000304" ]; then
  pass "Flutter artifact version derivation is deterministic"
else
  fail "Flutter artifact version derivation is deterministic"
fi
require_present "$PRECHECK" 'user_lifetime_safety_gate\.sh' \
  "preflight includes user lifetime safety gate"
require_present "$REVIEW_ALL" 'release_discipline_gate\.sh' \
  "review_all includes release discipline gate"
require_present "$REVIEW_ALL" 'user_lifetime_safety_gate\.sh' \
  "review_all includes user lifetime safety gate"
require_present "$CI_RELEASE_GATES" 'tools/review/review_all\.sh' \
  "GitHub release-gates workflow runs review gates"
require_present "$CI_RELEASE_GATES" 'tools/release/check_manual_release_signoff\.sh --self-test' \
  "GitHub release-gates workflow runs manual signoff self-test"

exit "$STATUS"
