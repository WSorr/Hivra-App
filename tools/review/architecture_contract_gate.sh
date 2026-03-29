#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS architecture-contract: %s\n' "$1"
}

fail() {
  printf 'FAIL architecture-contract: %s\n' "$1"
  STATUS=1
}

require_present() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$path"; then
    pass "$message"
  else
    fail "$message"
  fi
}

require_absent() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$path"; then
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
CHECKLIST="$ROOT/docs/checklists/architecture-review.md"

RUNTIME="$ROOT/flutter/lib/services/app_runtime_service.dart"
INV_INTENT="$ROOT/flutter/lib/services/invitation_intent_handler.dart"
PLUGIN_GUARD="$ROOT/flutter/lib/services/plugin_execution_guard_service.dart"
WASM_REGISTRY="$ROOT/flutter/lib/services/wasm_plugin_registry_service.dart"
SCREENS="$ROOT/flutter/lib/screens"
SERVICES="$ROOT/flutter/lib/services"
INSPECTOR="$ROOT/flutter/lib/screens/ledger_inspector_screen.dart"
PAIRWISE="$ROOT/flutter/lib/services/pairwise_snapshot_service.dart"
SUPPORT="$ROOT/flutter/lib/services/ledger_view_support.dart"
CONSENSUS="$ROOT/flutter/lib/services/consensus_processor.dart"

# 1) Dependency law for transport adapter.
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

# 2) Dependency law must be present in checks and docs.
require_present "$DEP_CHECK" 'hivra-transport must not depend on hivra-core' \
  "dependency_check enforces transport->core ban"
require_present "$SPEC" '`hivra-transport` does not depend on `hivra-core`' \
  "spec documents transport->core ban"
require_present "$README" '`hivra-transport` is adapter-only and does \*\*not\*\* depend on `hivra-core`' \
  "root README documents transport->core ban"

# 3) Spec/checklist anti-sprawl + engine/plugin contracts.
require_present "$SPEC" 'Structural Minimality Contract \(Anti-Sprawl\)' \
  "spec defines anti-sprawl structural contract"
require_present "$SPEC" 'Flutter Boundary Direction' \
  "spec defines downward direction inside Flutter boundary"
require_present "$SPEC" 'WASM Plugin Host Contract' \
  "spec defines wasm plugin-host contract"
require_present "$CHECKLIST" '## Engine Integrity' \
  "architecture checklist includes engine integrity section"
require_present "$CHECKLIST" '## WASM Plugin Host' \
  "architecture checklist includes wasm plugin-host section"

# 4) Flutter invitation flow application boundary.
require_present "$INV_INTENT" 'class InvitationIntentHandler' \
  "InvitationIntentHandler exists"
require_present "$RUNTIME" 'InvitationIntentHandler get invitationIntents' \
  "runtime exposes invitation intent boundary"
require_absent "$SCREENS" "import '../services/invitation_actions_service.dart';" \
  "screens do not import invitation_actions_service directly"

# 5) WASM plugin boundaries and readiness guard.
require_present "$WASM_REGISTRY" 'class WasmPluginRegistryService' \
  "wasm plugin registry service exists"
require_present "$PLUGIN_GUARD" 'class PluginExecutionGuardService' \
  "plugin execution guard service exists"
require_present "$PLUGIN_GUARD" 'inspectHostReadiness' \
  "plugin guard exposes readiness inspection"

# 6) Projection discipline: shared kind mapping only.
require_present "$SUPPORT" 'String kindLabel\(dynamic kind\)' \
  "ledger support exposes canonical kindLabel mapper"
require_absent "$INSPECTOR" 'String _kindLabel\(' \
  "inspector does not declare local kindLabel dictionary"
require_present "$INSPECTOR" '_support\.kindLabel\(event\['"'"'kind'"'"'\]\)' \
  "inspector uses shared kindLabel mapping"
if [ -f "$PAIRWISE" ]; then
  require_absent "$PAIRWISE" 'String _kindLabel\(' \
    "pairwise service does not declare local kindLabel dictionary"
  require_present "$PAIRWISE" '_support\.kindLabel\(event\['"'"'kind'"'"'\]\)' \
    "pairwise service uses shared kindLabel mapping"
else
  pass "legacy pairwise service removed; checking consensus processor mapping instead"
  require_absent "$CONSENSUS" 'String _kindLabel\(' \
    "consensus processor does not declare local kindLabel dictionary"
  require_present "$CONSENSUS" '_support\.kindLabel\(event\['"'"'kind'"'"'\]\)' \
    "consensus processor uses shared kindLabel mapping"
fi

# 7) Screen layer should not bypass boundary at usage level.
require_absent "$SCREENS" 'HivraBindings\(' \
  "screens do not instantiate HivraBindings"
require_absent "$SCREENS" '\.importLedger\(' \
  "screens do not import ledger directly"
NON_INSPECTOR_EXPORT_CALLS="$(
  rg -n '\.exportLedger\(' "$SCREENS" -g '*.dart' | rg -v 'ledger_inspector_screen\.dart' || true
)"
if [ -n "$NON_INSPECTOR_EXPORT_CALLS" ]; then
  fail "non-inspector screens do not export ledger directly"
  echo "$NON_INSPECTOR_EXPORT_CALLS"
else
  pass "non-inspector screens do not export ledger directly"
fi

# 8) Boundary services expected by architecture remain present.
require_present "$SERVICES/consensus_processor.dart" 'class ConsensusProcessor' \
  "consensus processor boundary exists"
require_present "$SERVICES/consensus_runtime_service.dart" 'class ConsensusRuntimeService' \
  "consensus runtime facade exists"

exit "$STATUS"
