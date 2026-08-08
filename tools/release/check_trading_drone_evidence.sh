#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="${HIVRA_TRADING_EVIDENCE_LOG_FILE:-$ROOT/docs/checklists/trading-drone-evidence-log.md}"
FIXTURE_FILE="${HIVRA_TRADING_EVIDENCE_FIXTURE_FILE:-$ROOT/tools/release/trading_drone_evidence_fixture.json}"

usage() {
  cat <<'USAGE'
Usage:
  tools/release/check_trading_drone_evidence.sh --build-tag <tag>
  tools/release/check_trading_drone_evidence.sh --self-test

Checks that the candidate has exactly one row for each canonical platform/mode
fixture and that every decision hash, execution hash, and risk path matches the
production-backed fixture.
USAGE
}

validate() {
  local build_tag="$1"
  python3 - "$LOG_FILE" "$FIXTURE_FILE" "$build_tag" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
fixture_path = Path(sys.argv[2])
build_tag = sys.argv[3]
hash_pattern = re.compile(r"^[0-9a-f]{64}$")

if not log_path.is_file():
    raise SystemExit(f"FAIL evidence-check: evidence log not found: {log_path}")
if not fixture_path.is_file():
    raise SystemExit(f"FAIL evidence-check: canonical fixture not found: {fixture_path}")

fixture = json.loads(fixture_path.read_text())
if fixture.get("schema_version") != 1:
    raise SystemExit("FAIL evidence-check: unsupported fixture schema_version")

decision_hash = fixture.get("decision", {}).get("expected_hash", "")
executions = fixture.get("executions", {})
coverage = fixture.get("coverage", [])
if not hash_pattern.fullmatch(decision_hash):
    raise SystemExit("FAIL evidence-check: fixture decision hash is not canonical lowercase hex")
if not isinstance(coverage, list) or not coverage:
    raise SystemExit("FAIL evidence-check: fixture coverage is empty")

expected = {}
for item in coverage:
    key = (item.get("platform"), item.get("mode"))
    execution_name = item.get("execution")
    execution = executions.get(execution_name, {})
    execution_hash = execution.get("expected_hash", "")
    risk_path = execution.get("risk_decision_code", "")
    if None in key or key in expected:
        raise SystemExit("FAIL evidence-check: fixture coverage keys must be unique")
    if not hash_pattern.fullmatch(execution_hash):
        raise SystemExit(f"FAIL evidence-check: invalid fixture execution hash for {key}")
    if risk_path not in {"risk_allowed", "risk_blocked", "risk_cooldown"}:
        raise SystemExit(f"FAIL evidence-check: invalid fixture risk path for {key}")
    expected[key] = (decision_hash, execution_hash, risk_path)

actual = {}
for line in log_path.read_text().splitlines():
    if not line.startswith("|"):
        continue
    columns = [column.strip().strip("`") for column in line.split("|")[1:-1]]
    if len(columns) != 8 or columns[0] != build_tag:
        continue
    key = (columns[2], columns[3])
    if key in actual:
        raise SystemExit(f"FAIL evidence-check: duplicate row for {key[0]}|{key[1]}")
    actual[key] = (columns[4], columns[5], columns[6])

missing = sorted(set(expected) - set(actual))
unexpected = sorted(set(actual) - set(expected))
if missing:
    rendered = ", ".join(f"{platform}|{mode}" for platform, mode in missing)
    raise SystemExit(f"FAIL evidence-check: missing canonical coverage rows: {rendered}")
if unexpected:
    rendered = ", ".join(f"{platform}|{mode}" for platform, mode in unexpected)
    raise SystemExit(f"FAIL evidence-check: unexpected coverage rows: {rendered}")

for key, expected_values in expected.items():
    if actual[key] != expected_values:
        platform, mode = key
        raise SystemExit(
            f"FAIL evidence-check: evidence mismatch for {platform}|{mode}; "
            "hashes and risk path must match the canonical fixture"
        )

if not any(values[2] == "risk_blocked" for values in actual.values()):
    raise SystemExit(f"FAIL evidence-check: no risk_blocked row found for build tag {build_tag}")

print(f"PASS evidence-check: build tag {build_tag} matches canonical trading fixture")
PY
}

self_test() {
  local temp_dir valid_log mutated_log
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN
  valid_log="$temp_dir/valid.md"
  mutated_log="$temp_dir/mutated.md"

  python3 - "$FIXTURE_FILE" > "$valid_log" <<'PY'
import json
import sys
from pathlib import Path

fixture = json.loads(Path(sys.argv[1]).read_text())
decision_hash = fixture["decision"]["expected_hash"]
print("| Build Tag | Date (UTC) | Platform | Mode | Decision Envelope Hash | Execution Envelope Hash | Risk Path | Notes |")
print("|---|---|---|---|---|---|---|---|")
for item in fixture["coverage"]:
    execution = fixture["executions"][item["execution"]]
    print(
        f"| self-test | 2026-01-01T00:00:00Z | {item['platform']} | {item['mode']} | "
        f"`{decision_hash}` | `{execution['expected_hash']}` | "
        f"`{execution['risk_decision_code']}` | fixture |"
    )
PY

  LOG_FILE="$valid_log" validate "self-test" >/dev/null

  expect_rejected() {
    local reason="$1"
    if LOG_FILE="$mutated_log" validate "self-test" >/dev/null 2>&1; then
      echo "FAIL evidence-check self-test: $reason was accepted" >&2
      return 1
    fi
  }

  cp "$valid_log" "$mutated_log"
  python3 - "$mutated_log" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
path.write_text(re.sub(r"`[0-9a-f]([0-9a-f]{63})`", r"`0\1`", text, count=1))
PY
  expect_rejected "mutated decision hash"

  cp "$valid_log" "$mutated_log"
  python3 - "$mutated_log" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("`risk_allowed`", "`risk_cooldown`", 1))
PY
  expect_rejected "altered risk path"

  cp "$valid_log" "$mutated_log"
  tail -n 1 "$valid_log" >> "$mutated_log"
  expect_rejected "duplicate coverage row"

  cp "$valid_log" "$mutated_log"
  python3 - "$mutated_log" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
path.write_text("\n".join(lines[:-1]) + "\n")
PY
  expect_rejected "missing coverage row"

  echo "PASS evidence-check: canonical fixture self-test"
}

BUILD_TAG=""
SELF_TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --build-tag) BUILD_TAG="${2:-}"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  [ -z "$BUILD_TAG" ] || { echo "--self-test cannot be combined with --build-tag" >&2; exit 1; }
  self_test
  exit 0
fi

if [ -z "$BUILD_TAG" ]; then
  printf 'Missing required --build-tag.\n' >&2
  usage
  exit 1
fi

validate "$BUILD_TAG"
