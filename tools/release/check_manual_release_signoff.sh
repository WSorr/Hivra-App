#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="${HIVRA_MANUAL_SIGNOFF_LOG:-$ROOT/docs/checklists/release-manual-signoff-log.md}"

BUILD_TAG=""
PLATFORM=""

usage() {
  cat <<'USAGE'
Usage:
  tools/release/check_manual_release_signoff.sh --build-tag <tag> --platform <macOS|Android|all>
  tools/release/check_manual_release_signoff.sh --self-test

Environment:
  HIVRA_MANUAL_SIGNOFF_LOG  Optional path override for tests.
USAGE
}

die() {
  echo "FAIL manual-signoff: $*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

field_value() {
  local row="$1"
  local index="$2"
  awk -F'|' -v idx="$index" '{ gsub(/^[ \t]+|[ \t]+$/, "", $idx); print $idx }' <<< "$row"
}

status_is_pass() {
  [ "$(trim "$1")" = "PASS" ]
}

status_is_pass_or_na() {
  local value
  value="$(trim "$1")"
  [ "$value" = "PASS" ] || [ "$value" = "N/A" ]
}

find_row() {
  local platform="$1"
  awk -F'|' -v tag="$BUILD_TAG" -v platform="$platform" '
    $0 ~ /^\|/ {
      original = $0
      for (i = 1; i <= NF; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i)
      }
      if ($2 == tag && $4 == platform) {
        print original
        exit
      }
    }
  ' "$LOG_FILE"
}

check_platform() {
  local platform="$1"
  local row
  row="$(find_row "$platform")"
  [ -n "$row" ] || die "missing $platform signoff row for $BUILD_TAG in $LOG_FILE"

  local date artifact manual trading lifetime ai signer
  date="$(field_value "$row" 3)"
  artifact="$(field_value "$row" 5)"
  manual="$(field_value "$row" 6)"
  trading="$(field_value "$row" 7)"
  lifetime="$(field_value "$row" 8)"
  ai="$(field_value "$row" 9)"
  signer="$(field_value "$row" 10)"

  [ -n "$date" ] || die "$platform signoff row has empty date"
  [ -n "$artifact" ] || die "$platform signoff row has empty artifact"
  [ -n "$signer" ] || die "$platform signoff row has empty signer"
  [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
    die "$platform signoff date must be UTC ISO-8601 seconds: $date"

  status_is_pass "$manual" || die "$platform Manual Smoke must be PASS"
  status_is_pass "$trading" || die "$platform Trading Smoke must be PASS"
  status_is_pass "$lifetime" || die "$platform User Lifetime must be PASS"

  if [ "$platform" = "macOS" ]; then
    status_is_pass "$ai" || die "macOS AI Engineer must be PASS"
  else
    status_is_pass_or_na "$ai" || die "$platform AI Engineer must be PASS or N/A"
  fi

  echo "PASS manual-signoff: $BUILD_TAG $platform"
}

run_check() {
  [ -n "$BUILD_TAG" ] || die "--build-tag is required"
  [ -n "$PLATFORM" ] || die "--platform is required"
  [ -f "$LOG_FILE" ] || die "signoff log not found: $LOG_FILE"

  case "$PLATFORM" in
    macOS|Android)
      check_platform "$PLATFORM"
      ;;
    all)
      check_platform macOS
      check_platform Android
      ;;
    *)
      die "--platform must be macOS, Android, or all"
      ;;
  esac
}

self_test() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<'EOF'
# Release Manual Signoff Log

| Build Tag | Date (UTC) | Platform | Artifact | Manual Smoke | Trading Smoke | User Lifetime | AI Engineer | Signer | Notes |
|---|---|---|---|---|---|---|---|---|---|
| v-selftest | 2026-01-01T00:00:00Z | macOS | hivra_app-v-selftest-macos-universal.zip | PASS | PASS | PASS | PASS | codex | self-test |
| v-selftest | 2026-01-01T00:00:01Z | Android | hivra_app-v-selftest-android-universal.apk | PASS | PASS | PASS | N/A | codex | self-test |
EOF

  HIVRA_MANUAL_SIGNOFF_LOG="$tmp" bash "$0" \
    --build-tag v-selftest \
    --platform all >/dev/null

  if HIVRA_MANUAL_SIGNOFF_LOG="$tmp" bash "$0" \
    --build-tag v-missing \
    --platform all >/dev/null 2>&1; then
    rm -f "$tmp"
    die "self-test expected missing build tag to fail"
  fi

  rm -f "$tmp"
  echo "PASS manual-signoff: self-test"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build-tag)
      BUILD_TAG="${2:-}"
      shift 2
      ;;
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --self-test)
      self_test
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

run_check
