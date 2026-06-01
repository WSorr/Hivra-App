#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$ROOT/docs/checklists/trading-drone-evidence-log.md"

usage() {
  cat <<'USAGE'
Usage:
  tools/release/record_trading_drone_evidence.sh \
    --build-tag <tag> \
    --platform <macOS|Android> \
    --mode <situational|interactive> \
    --decision-hash <hash> \
    --execution-hash <hash> \
    --risk-path <risk_allowed|risk_blocked|risk_cooldown> \
    [--notes <text>] \
    [--date-utc <iso8601>]
USAGE
}

BUILD_TAG=""
PLATFORM=""
MODE=""
DECISION_HASH=""
EXECUTION_HASH=""
RISK_PATH=""
NOTES=""
DATE_UTC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --build-tag) BUILD_TAG="${2:-}"; shift 2 ;;
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --decision-hash) DECISION_HASH="${2:-}"; shift 2 ;;
    --execution-hash) EXECUTION_HASH="${2:-}"; shift 2 ;;
    --risk-path) RISK_PATH="${2:-}"; shift 2 ;;
    --notes) NOTES="${2:-}"; shift 2 ;;
    --date-utc) DATE_UTC="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$BUILD_TAG" ] || [ -z "$PLATFORM" ] || [ -z "$MODE" ] || [ -z "$DECISION_HASH" ] || [ -z "$EXECUTION_HASH" ] || [ -z "$RISK_PATH" ]; then
  printf 'Missing required arguments.\n' >&2
  usage
  exit 1
fi

case "$PLATFORM" in
  macOS|Android) ;;
  *)
    printf 'Invalid --platform: %s\n' "$PLATFORM" >&2
    exit 1
    ;;
esac

case "$MODE" in
  situational|interactive) ;;
  *)
    printf 'Invalid --mode: %s\n' "$MODE" >&2
    exit 1
    ;;
esac

if [ -z "$DATE_UTC" ]; then
  DATE_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

if [ ! -f "$LOG_FILE" ]; then
  printf 'Evidence log not found: %s\n' "$LOG_FILE" >&2
  exit 1
fi

NOTES_SANITIZED="${NOTES//$'\n'/ }"
DECISION_HASH_DISPLAY="\`${DECISION_HASH}\`"
EXECUTION_HASH_DISPLAY="\`${EXECUTION_HASH}\`"

printf '| %s | %s | %s | %s | %s | %s | `%s` | %s |\n' \
  "$BUILD_TAG" \
  "$DATE_UTC" \
  "$PLATFORM" \
  "$MODE" \
  "$DECISION_HASH_DISPLAY" \
  "$EXECUTION_HASH_DISPLAY" \
  "$RISK_PATH" \
  "$NOTES_SANITIZED" >> "$LOG_FILE"

printf 'Recorded trading-drone evidence row in %s\n' "$LOG_FILE"
