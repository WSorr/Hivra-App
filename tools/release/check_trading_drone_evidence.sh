#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$ROOT/docs/checklists/trading-drone-evidence-log.md"

usage() {
  cat <<'USAGE'
Usage:
  tools/release/check_trading_drone_evidence.sh --build-tag <tag>

Checks required coverage for the given build tag:
  - macOS situational
  - macOS interactive
  - Android situational
  - Android interactive
  - at least one row with risk path = risk_blocked
  - non-empty decision/execution envelope hashes for all rows
USAGE
}

BUILD_TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build-tag) BUILD_TAG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$BUILD_TAG" ]; then
  printf 'Missing required --build-tag.\n' >&2
  usage
  exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
  printf 'Evidence log not found: %s\n' "$LOG_FILE" >&2
  exit 1
fi

rows="$(awk -F'|' -v tag="$BUILD_TAG" '
function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
$0 ~ /^\|/ {
  c1 = trim($2)
  if (c1 == "Build Tag" || c1 == "---" || c1 != tag) next
  platform = trim($4)
  mode = trim($5)
  decision = trim($6)
  execution = trim($7)
  risk = trim($8)
  print platform "|" mode "|" decision "|" execution "|" risk
}
' "$LOG_FILE")"

if [ -z "$rows" ]; then
  printf 'FAIL evidence-check: no rows found for build tag %s\n' "$BUILD_TAG" >&2
  exit 1
fi

has_macos_situational=0
has_macos_interactive=0
has_android_situational=0
has_android_interactive=0
has_risk_blocked=0
invalid_hash_rows=0

while IFS='|' read -r platform mode decision execution risk; do
  [ -z "$platform" ] && continue
  if [ "$platform" = "macOS" ] && [ "$mode" = "situational" ]; then
    has_macos_situational=1
  fi
  if [ "$platform" = "macOS" ] && [ "$mode" = "interactive" ]; then
    has_macos_interactive=1
  fi
  if [ "$platform" = "Android" ] && [ "$mode" = "situational" ]; then
    has_android_situational=1
  fi
  if [ "$platform" = "Android" ] && [ "$mode" = "interactive" ]; then
    has_android_interactive=1
  fi

  decision_clean="${decision//\`/}"
  execution_clean="${execution//\`/}"
  risk_clean="${risk//\`/}"
  if [[ ! "$decision_clean" =~ ^[0-9a-fA-F]{64}$ ]] ||
     [[ ! "$execution_clean" =~ ^[0-9a-fA-F]{64}$ ]]; then
    invalid_hash_rows=$((invalid_hash_rows + 1))
  fi
  if [ "$risk_clean" = "risk_blocked" ]; then
    has_risk_blocked=1
  fi
done <<< "$rows"

missing=0
if [ "$has_macos_situational" -ne 1 ]; then
  printf 'FAIL evidence-check: missing coverage row for macOS|situational\n' >&2
  missing=1
fi
if [ "$has_macos_interactive" -ne 1 ]; then
  printf 'FAIL evidence-check: missing coverage row for macOS|interactive\n' >&2
  missing=1
fi
if [ "$has_android_situational" -ne 1 ]; then
  printf 'FAIL evidence-check: missing coverage row for Android|situational\n' >&2
  missing=1
fi
if [ "$has_android_interactive" -ne 1 ]; then
  printf 'FAIL evidence-check: missing coverage row for Android|interactive\n' >&2
  missing=1
fi

if [ "$invalid_hash_rows" -gt 0 ]; then
  printf 'FAIL evidence-check: %d rows have invalid decision/execution hashes (expected 64 hex chars)\n' "$invalid_hash_rows" >&2
  missing=1
fi

if [ "$has_risk_blocked" -ne 1 ]; then
  printf 'FAIL evidence-check: no risk_blocked row found for build tag %s\n' "$BUILD_TAG" >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

printf 'PASS evidence-check: build tag %s has required trading-drone evidence coverage\n' "$BUILD_TAG"
