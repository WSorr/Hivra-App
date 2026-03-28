#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS architecture: %s\n' "$1"
}

fail() {
  printf 'FAIL architecture: %s\n' "$1"
  STATUS=1
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

require_absent() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    fail "$message"
  else
    pass "$message"
  fi
}

TRANSPORT_TOML="$ROOT/adapters/hivra-transport/Cargo.toml"
TRANSPORT_SRC="$ROOT/adapters/hivra-transport/src"
DEP_CHECK="$ROOT/tools/review/dependency_check.sh"
SPEC="$ROOT/docs/specification.md"
README="$ROOT/README.md"

# 1) Code-level dependency law for transport adapter.
require_absent "$TRANSPORT_TOML" 'hivra-core' \
  "hivra-transport has no direct dependency on hivra-core"
require_absent "$TRANSPORT_TOML" 'hivra-engine' \
  "hivra-transport has no direct dependency on hivra-engine"
require_absent "$TRANSPORT_TOML" 'hivra-ffi' \
  "hivra-transport has no direct dependency on hivra-ffi"
require_absent "$TRANSPORT_SRC" 'hivra_core::|use hivra_core' \
  "hivra-transport source does not import hivra_core"
require_absent "$TRANSPORT_SRC" 'hivra_engine::|use hivra_engine' \
  "hivra-transport source does not import hivra_engine"

# 2) Gate script must enforce the same law.
require_present "$DEP_CHECK" 'hivra-transport must not depend on hivra-core' \
  "dependency_check enforces transport->core ban"

# 3) Normative docs must state the same compile-time contract.
require_present "$SPEC" '`hivra-transport` does not depend on `hivra-core`' \
  "spec documents transport->core ban"
require_present "$README" '`hivra-transport` is adapter-only and does \*\*not\*\* depend on `hivra-core`' \
  "root README documents transport->core ban"

exit "$STATUS"
