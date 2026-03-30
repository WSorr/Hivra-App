#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

run_check() {
  local script="$1"
  printf '\n== %s ==\n' "$script"
  if ! "$ROOT/tools/review/$script"; then
    STATUS=1
  fi
}

run_check "topology_check.sh"
run_check "dependency_check.sh"
run_check "architecture_contract_gate.sh"
run_check "ui_ffi_boundary_gate.sh"
run_check "release_discipline_gate.sh"
run_check "user_lifetime_safety_gate.sh"
run_check "security_check.sh"

exit "$STATUS"
