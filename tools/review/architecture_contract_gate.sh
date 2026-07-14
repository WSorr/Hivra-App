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
DOCS_README="$ROOT/docs/README.md"
PRODUCT_AXIS="$ROOT/docs/product-axis.md"
CHECKLIST="$ROOT/docs/checklists/architecture-review.md"
ROADMAP="$ROOT/docs/roadmap.md"
EXEC_DISCIPLINE="$ROOT/docs/architecture-execution-discipline.md"
V2_BLUEPRINT="$ROOT/docs/architecture-v2-blueprint.md"
DELIVERY_LIFECYCLE_DOC="$ROOT/docs/architecture/transport-delivery-lifecycle.md"
EXTERNAL_PLUGIN_SOURCE="$ROOT/docs/plugins/external_plugin_source.md"
PLUGIN_HOST_API_DOC="$ROOT/docs/plugins/plugin_host_api_v1.md"

RUNTIME="$ROOT/flutter/lib/services/app_runtime_service.dart"
INV_INTENT="$ROOT/flutter/lib/services/invitation_intent_handler.dart"
INV_ACTIONS="$ROOT/flutter/lib/services/invitation_actions_service.dart"
DELIVERY_LIFECYCLE="$ROOT/flutter/lib/services/capsule_delivery_lifecycle_service.dart"
FFI_INVITATION_API="$ROOT/platform/hivra-ffi/src/invitation_api.rs"
FFI_CHAT_API="$ROOT/platform/hivra-ffi/src/chat_api.rs"
PLUGIN_GUARD="$ROOT/flutter/lib/services/plugin_execution_guard_service.dart"
PLUGIN_HOST="$ROOT/flutter/lib/services/plugin_host_api_service.dart"
PLUGIN_CONTRACT_HANDLERS="$ROOT/flutter/lib/services/plugin_contract_handlers.dart"
WASM_REGISTRY="$ROOT/flutter/lib/services/wasm_plugin_registry_service.dart"
SCREENS="$ROOT/flutter/lib/screens"
MAIN_SCREEN="$SCREENS/main_screen.dart"
TRADING_SCREEN="$SCREENS/trading_drone_screen.dart"
WASM_PLUGINS_SCREEN="$SCREENS/wasm_plugins_screen.dart"
CAPSULE_DOCTOR_SCREEN="$SCREENS/capsule_doctor_screen.dart"
INVITATIONS_SCREEN="$SCREENS/invitations_screen.dart"
LEDGER_INSPECTOR_SCREEN="$SCREENS/ledger_inspector_screen.dart"
WIDGETS="$ROOT/flutter/lib/widgets"
SERVICES="$ROOT/flutter/lib/services"
INSPECTOR="$ROOT/flutter/lib/screens/ledger_inspector_screen.dart"
PAIRWISE="$ROOT/flutter/lib/services/pairwise_snapshot_service.dart"
SUPPORT="$ROOT/flutter/lib/services/ledger_view_support.dart"
CONSENSUS="$ROOT/flutter/lib/services/consensus_processor.dart"
CONSENSUS_ATTESTATION_SYNC="$ROOT/flutter/lib/services/consensus_attestation_sync_service.dart"
CONSENSUS_ATTESTATION_STORE="$ROOT/flutter/lib/services/consensus_attestation_store.dart"
CAPSULE_FILE_STORE="$ROOT/flutter/lib/services/capsule_file_store.dart"
CAPSULE_INDEX_STORE="$ROOT/flutter/lib/services/capsule_index_store.dart"
CAPSULE_PERSISTENCE="$ROOT/flutter/lib/services/capsule_persistence_service.dart"
BINDINGS="$ROOT/flutter/lib/ffi/hivra_bindings.dart"
WASM_RUNTIME="$ROOT/platform/hivra-wasm-runtime/src/lib.rs"
WASM_RUNTIME_SERVICE="$ROOT/flutter/lib/services/wasm_plugin_runtime_service.dart"
FFI_TOML="$ROOT/platform/hivra-ffi/Cargo.toml"
FFI_SELFCHECK="$ROOT/platform/hivra-ffi/src/selfcheck_api.rs"
FFI_CONSENSUS_ATTESTATION="$ROOT/platform/hivra-ffi/src/consensus_attestation_api.rs"

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
require_present "$PRODUCT_AXIS" '^## 1\. Axis Statement' \
  "product axis defines one permanent evaluation direction"
require_present "$PRODUCT_AXIS" '^## 2\. Two Canonical Lanes' \
  "product axis defines truth and effect lanes"
require_present "$PRODUCT_AXIS" '^## 3\. Permanent Product Invariants' \
  "product axis defines stable product invariants"
require_present "$PRODUCT_AXIS" '^## 5\. Pre-Implementation Capability Closure' \
  "product axis requires capability closure before implementation"
require_present "$PRODUCT_AXIS" '^### 5\.4 Feasibility verdict' \
  "product axis defines explicit feasibility verdicts"
require_present "$PRODUCT_AXIS" '`NEEDS_PROTOCOL`; Pair Consensus composition is not assumed sufficient' \
  "product axis does not assume pair consensus closes group protocols"
require_present "$PRODUCT_AXIS" 'A pass-through DTO that copies another contract' \
  "product axis forbids pass-through DTO prostheses"
require_present "$PRODUCT_AXIS" '^## 6\. Change Scorecard' \
  "product axis defines a comparable change scorecard"
require_present "$PRODUCT_AXIS" 'Replacement with deletion' \
  "product axis requires replacement-path removal"
require_present "$SPEC" '^### 0\.1 Product Axis' \
  "specification binds implementation to product axis"
require_present "$CHECKLIST" '^## Product Axis' \
  "architecture review applies product-axis checks"
require_present "$ROADMAP" '^## Product Axis Gate' \
  "roadmap rejects work without measurable axis gain"
require_present "$DOCS_README" 'product-axis\.md' \
  "docs index starts from product axis"
require_present "$SPEC" 'Structural Minimality Contract \(Anti-Sprawl\)' \
  "spec defines anti-sprawl structural contract"
require_present "$SPEC" 'Flutter Boundary Direction' \
  "spec defines downward direction inside Flutter boundary"
require_present "$SPEC" 'WASM Plugin Host Contract' \
  "spec defines wasm plugin-host contract"
require_present "$SPEC" 'Transport adapters are host-level system adapters, not WASM drones' \
  "spec separates transport adapters from wasm drones"
require_present "$CHECKLIST" 'Transport adapters are not modeled as WASM drones; drones request delivery only through host APIs\.' \
  "architecture checklist separates transport adapters from wasm drones"
require_absent "$SPEC" 'Supported transports \(plugins\)|Matrix \(plugin|BLE \(plugin|Local network \(plugin' \
  "spec does not describe transport adapters as ordinary plugins"
require_absent "$README" 'Supported transports \(plugins\)|Matrix \(plugin|BLE \(plugin|Local network \(plugin' \
  "root README does not describe transport adapters as ordinary plugins"
require_present "$SPEC" 'Drone Consensus Guard Standard' \
  "spec defines drone consensus guard standard"
require_present "$SPEC" '`pair_scoped` methods MUST call the shared Consensus Guard boundary' \
  "spec requires pair-scoped methods to use shared consensus guard"
require_present "$CHECKLIST" '## Engine Integrity' \
  "architecture checklist includes engine integrity section"
require_present "$CHECKLIST" '## WASM Plugin Host' \
  "architecture checklist includes wasm plugin-host section"
require_present "$CHECKLIST" 'Every drone method declares exactly one scope: `solo`, `market_scan`, or `pair_scoped`\.' \
  "architecture checklist requires explicit drone consensus scope"
require_present "$CHECKLIST" 'No pair-scoped path treats "any signable peer" as authorization for a missing or different peer\.' \
  "architecture checklist forbids any-signable-peer consensus fallback"
require_present "$CHECKLIST" 'Repo boundary is preserved: `Hivra-App` is host/runtime only; plugin implementation source/release flow lives in `hivra-plugins`\.' \
  "architecture checklist enforces app-vs-plugin repo boundary"
require_present "$EXEC_DISCIPLINE" '^# Hivra Architecture Execution Discipline v1' \
  "execution discipline doc exists"
require_present "$DELIVERY_LIFECYCLE_DOC" '^# Transport Delivery Lifecycle v1' \
  "delivery lifecycle architecture doc exists"
require_present "$DELIVERY_LIFECYCLE_DOC" 'delivery recovery index' \
  "delivery lifecycle doc distinguishes recovery index from reliable queue"
require_present "$EXEC_DISCIPLINE" '^## 1\. Three Non-Negotiable Laws' \
  "execution discipline defines three non-negotiable laws"
require_present "$EXEC_DISCIPLINE" 'Modularity means one owner per responsibility' \
  "execution discipline requires one owner per responsibility"
require_present "$EXEC_DISCIPLINE" 'Determinism means one input route and one result' \
  "execution discipline requires one effect route and result"
require_present "$EXEC_DISCIPLINE" 'Dependencies strictly downward means contracts down, composition up' \
  "execution discipline requires downward contracts and top-level composition"
require_present "$EXEC_DISCIPLINE" '^### Mandatory Change Questions' \
  "execution discipline requires pre-change ownership questions"
require_present "$EXEC_DISCIPLINE" 'UI intent -> use-case boundary -> runtime/FFI call -> ledger append -> projection rebuild -> UI render' \
  "execution discipline defines canonical action path"
require_present "$EXEC_DISCIPLINE" '^## 4\. Async Resolution Discipline' \
  "execution discipline defines async resolution rules"
require_present "$EXEC_DISCIPLINE" '^## 7\. Plugin Repository Boundary' \
  "execution discipline defines plugin repository boundary"
require_present "$V2_BLUEPRINT" '^Status: design-only draft\.' \
  "v2 blueprint cannot silently change normative v1 behavior"
require_present "$V2_BLUEPRINT" '^## 4\. Capability Map' \
  "v2 blueprint defines capability ownership map"
require_present "$V2_BLUEPRINT" '^## 7\. Anti-Entropy Budget' \
  "v2 blueprint defines measurable anti-entropy budget"
require_present "$V2_BLUEPRINT" '^## 8\. Self-Governing Architecture Map' \
  "v2 blueprint requires generated architecture evidence"
require_present "$V2_BLUEPRINT" '^## 9\. Migration Rule: Strangler With Deletion' \
  "v2 blueprint requires replacement-path deletion"
require_present "$V2_BLUEPRINT" 'separate immutable `birth_mode` \(Genesis/Proto\) from runtime role' \
  "v2 blueprint separates capsule birth mode from runtime role"
require_present "$V2_BLUEPRINT" 'define Hood as a separately namespaced experimental network' \
  "v2 blueprint requires isolated Hood network design"
require_present "$SPEC" 'Birth mode \(`Genesis` or `Proto`\) is not a runtime role\.' \
  "v1 specification separates birth mode from runtime role"
require_present "$SPEC" 'The supported 1\.x runtime operates Capsules in Neste only\.' \
  "v1 specification does not claim active Hood support"
require_present "$SPEC" 'first-valid-terminal semantics' \
  "v1 specification defines first-valid-terminal invitation lifecycle"
require_absent "$SPEC" 'accepted > rejected > expired' \
  "v1 specification has no obsolete terminal precedence"
require_present "$DOCS_README" 'architecture-v2-blueprint\.md' \
  "docs index references v2 architecture blueprint"
require_present "$ROADMAP" '^## Parallel Version Tracks' \
  "roadmap separates maintained v1 and design-only v2 tracks"
require_present "$EXTERNAL_PLUGIN_SOURCE" '^## Repository boundary contract \(mandatory\)' \
  "external plugin source doc defines mandatory repo boundary contract"
require_present "$EXTERNAL_PLUGIN_SOURCE" '`Hivra-App` repository is host/runtime only\.' \
  "external plugin source doc fixes Hivra-App host-only ownership"
require_present "$EXTERNAL_PLUGIN_SOURCE" 'WASM plugin implementation source and plugin package release flow belong to `hivra-plugins` repository\.' \
  "external plugin source doc fixes plugin-source ownership in hivra-plugins"
require_present "$PLUGIN_HOST_API_DOC" 'rank_bingx_futures_signals' \
  "host API docs include plugin-owned futures signal ranking method"
require_present "$PLUGIN_HOST_API_DOC" 'host must not mirror plugin-side ranking/scoring semantics' \
  "host API docs forbid mirrored signal ranking semantics"
require_present "$PLUGIN_HOST_API_DOC" 'Drone consensus scopes are explicit' \
  "host API docs define explicit drone consensus scopes"
require_present "$PLUGIN_HOST_API_DOC" 'host code must never replace a missing or unresolved `peer_hex` with "any' \
  "host API docs forbid peer fallback for pair-scoped consensus"
if find "$ROOT/tools/plugins" -maxdepth 1 -type f \
  -name 'build_*_plugin_zip.sh' | grep -q .; then
  fail "Hivra-App contains plugin package build scripts owned by hivra-plugins"
else
  pass "Hivra-App does not duplicate external plugin package build sources"
fi
if rg -q 'bingx_futures_(credential|exchange|intent|live|risk|execution)' \
  "$ROOT/flutter/lib/screens/wasm_plugins_screen.dart"; then
  fail "plugin catalog screen contains trading-drone orchestration"
else
  pass "plugin catalog screen is free of trading-drone orchestration"
fi
require_present "$DOCS_README" 'architecture-execution-discipline\.md' \
  "docs index references execution discipline standard"
require_present "$ROADMAP" '`9\.10 Execution Discipline Standard`' \
  "roadmap tracks execution discipline standard"
require_present "$CHECKLIST" '## Execution Discipline v1' \
  "architecture checklist includes execution discipline section"
require_present "$CHECKLIST" 'UI intent -> use-case boundary -> runtime/FFI call -> ledger append -> projection rebuild -> UI render' \
  "architecture checklist enforces canonical action path review"
require_present "$CHECKLIST" 'Async flows resolve once and ignore stale completions' \
  "architecture checklist enforces async resolve-once review"
require_present "$CHECKLIST" 'Every fact, effect lifecycle, and projection rule has one named owner' \
  "architecture checklist enforces unique ownership"
require_present "$CHECKLIST" 'Each async effect has one capsule binding, one queue/lifecycle owner' \
  "architecture checklist enforces one async effect route"

# 4) Flutter invitation flow application boundary.
require_present "$INV_INTENT" 'class InvitationIntentHandler' \
  "InvitationIntentHandler exists"
require_present "$RUNTIME" 'InvitationIntentHandler get invitationIntents' \
  "runtime exposes invitation intent boundary"
require_present "$RUNTIME" 'verifySignature: _runtime\.verifyConsensusSignature' \
  "production consensus runtime wires cryptographic signature verification"
require_present "$FFI_SELFCHECK" 'fn hivra_sign_root_digest32' \
  "FFI exposes root signing only for fixed-size consensus commitments"
require_present "$BINDINGS" "'hivra_sign_root_digest32'" \
  "Flutter binds the root commitment signing adapter"
require_present "$FFI_CONSENSUS_ATTESTATION" 'PAIR_CONSENSUS_ATTESTATION_KIND: u32 = 4098' \
  "FFI exposes a dedicated pair-consensus attestation transport kind"
require_present "$FFI_CONSENSUS_ATTESTATION" 'fn hivra_send_pair_consensus_attestation' \
  "FFI exposes pair-consensus attestation send boundary"
require_present "$FFI_CONSENSUS_ATTESTATION" 'fn hivra_receive_pair_consensus_attestations_json' \
  "FFI exposes pair-consensus attestation receive boundary"
require_present "$BINDINGS" "'hivra_send_pair_consensus_attestation'" \
  "Flutter binds pair-consensus attestation send boundary"
require_present "$BINDINGS" "'hivra_receive_pair_consensus_attestations_json'" \
  "Flutter binds pair-consensus attestation receive boundary"
require_present "$CAPSULE_FILE_STORE" 'pair_consensus_attestations\.json' \
  "capsule file store owns pair-consensus attestation evidence under capsule storage"
require_present "$CONSENSUS_ATTESTATION_STORE" 'class ConsensusAttestationStore' \
  "pair-consensus attestation store exists"
require_present "$CONSENSUS_ATTESTATION_SYNC" '_verifyEvidence\(payload\)' \
  "pair-consensus attestation receive verifies evidence before storing"
require_present "$CONSENSUS_ATTESTATION_SYNC" 'await _store\.merge\(localRootHex, verified\)' \
  "pair-consensus attestation sync stores only verified evidence"
require_present "$RUNTIME" 'buildConsensusAttestationSyncService' \
  "runtime exposes pair-consensus attestation sync module"
require_present "$FFI_INVITATION_API" 'queue_incoming_attestation_if_match' \
  "invitation receive routes pair-consensus attestations before core event parsing"
require_present "$FFI_CHAT_API" 'queue_incoming_attestation_if_match' \
  "chat receive preserves pair-consensus attestations sharing the transport receive cache"
require_absent "$SCREENS" "import '../services/invitation_actions_service.dart';" \
  "screens do not import invitation_actions_service directly"
require_absent "$SCREENS" "import '../services/consensus_runtime_service.dart';" \
  "screens do not import consensus_runtime_service directly"
require_present "$INV_ACTIONS" 'class CapsuleWorkerQueue' \
  "invitation transport workers have a capsule-scoped queue"
require_present "$INV_ACTIONS" 'capsuleHex: initialCapsuleHex' \
  "queued invitation workers refresh bootstrap inside the capsule queue"
require_present "$DELIVERY_LIFECYCLE" 'class CapsuleDeliveryLifecycleService' \
  "delivery lifecycle owns shared retry scheduling"
require_present "$DELIVERY_LIFECYCLE" 'receipt-to-outbox' \
  "delivery lifecycle documents receipt reconciliation ownership"
require_absent "$INV_ACTIONS" '_pendingRetryPumpByCapsule|_schedulePendingOutgoingRetryPump' \
  "invitation actions do not own a parallel retry pump"
require_present "$INV_ACTIONS" 'await _applyWorkerLedgerResult\(' \
  "queued invitation workers persist ledger before releasing the capsule queue"
require_absent "$INV_ACTIONS" '_scheduleLateWorkerLedgerApply' \
  "timed-out invitation workers do not bypass capsule serialization"
require_present "$CAPSULE_INDEX_STORE" '_serializeMutation' \
  "capsule index serializes selection and metadata mutations"
require_present "$CAPSULE_INDEX_STORE" 'writePreservingActive' \
  "capsule index reconciliation preserves the latest explicit selection"
require_absent "$CAPSULE_PERSISTENCE" '_touchActiveCapsule' \
  "background persistence cannot use the legacy active-selection writer"
require_present "$CAPSULE_PERSISTENCE" '_touchRuntimeCapsuleMetadata' \
  "background persistence updates runtime capsule metadata only"
require_present "$MAIN_SCREEN" 'capsuleStateMatchesSelection' \
  "main screen rejects transient projections from another capsule"

# 5) WASM plugin boundaries and readiness guard.
require_present "$WASM_REGISTRY" 'class WasmPluginRegistryService' \
  "wasm plugin registry service exists"
require_present "$PLUGIN_GUARD" 'class PluginExecutionGuardService' \
  "plugin execution guard service exists"
require_present "$PLUGIN_GUARD" 'inspectHostReadiness' \
  "plugin guard exposes readiness inspection"
require_absent "$PLUGIN_HOST" 'bingx_trading_contract_service|capsule_chat_contract_service' \
  "generic plugin host does not import concrete plugin contracts"
require_absent "$PLUGIN_HOST" 'Bingx|CapsuleChat|bingx|capsule_chat' \
  "generic plugin host does not branch on concrete plugin identities"
require_present "$FFI_TOML" 'hivra-wasm-runtime = \{ path = "../hivra-wasm-runtime" \}' \
  "FFI depends downward on isolated wasm runtime"
require_present "$WASM_RUNTIME" 'pub fn invoke_json' \
  "isolated wasm runtime exposes semantic JSON invocation"
require_present "$WASM_RUNTIME" 'module\.imports\(\)\.next\(\)\.is_some\(\)' \
  "wasm runtime rejects host imports"
require_present "$WASM_RUNTIME_SERVICE" "hivra_host_abi_v2" \
  "Flutter runtime boundary requires semantic ABI v2"
require_absent "$SERVICES" 'class BingxTradingContractService|class CapsuleChatContractService' \
  "Flutter does not mirror external plugin contract evaluators"
require_present "$PLUGIN_CONTRACT_HANDLERS" 'rankBingxFuturesSignalsMethod' \
  "Flutter host exposes futures signal ranking method boundary"
require_absent "$SERVICES" 'fn signal_score|signal_score\(|signal_bucket\(|bucket_priority\(|rank_signal_candidate\(' \
  "Flutter services do not mirror plugin futures signal ranking scorer"
require_absent "$SCREENS" 'BingxFuturesLiveSnapshotBuilderService|BingxFuturesLiveDecisionInput' \
  "screens do not orchestrate BingX snapshot and live decision pipeline"
require_absent "$SCREENS" 'BingxFuturesRiskGovernorInput|_riskGovernor\.evaluate' \
  "screens do not construct or evaluate BingX risk governor inputs"
require_absent "$TRADING_SCREEN" 'buildBingx|buildPluginHostApiService|buildManualConsensusCheckService|buildCapsuleChatDeliveryService' \
  "trading drone screen uses module boundary instead of assembling service graph"
require_absent "$WASM_PLUGINS_SCREEN" 'buildPluginHostApiService|buildManualConsensusCheckService|buildCapsuleChatDeliveryService|WasmPluginRegistryService\(|WasmPluginSourceCatalogService\(' \
  "wasm plugins screen uses module boundary instead of assembling service graph"
require_absent "$MAIN_SCREEN" 'build[A-Za-z0-9_]*Service\(' \
  "main screen uses module boundary instead of assembling child service graph"
require_absent "$INVITATIONS_SCREEN" 'buildRelationshipService|buildCapsuleAddressService|late final [A-Za-z0-9_]+Service ' \
  "invitations screen uses module boundary instead of assembling service graph"
require_absent "$TRADING_SCREEN" 'late final [A-Za-z0-9_]+Service ' \
  "trading drone screen does not keep individual service fields"
require_absent "$WASM_PLUGINS_SCREEN" 'late final [A-Za-z0-9_]+Service ' \
  "wasm plugins screen does not keep individual service fields"
require_absent "$WASM_PLUGINS_SCREEN" "services/wasm_plugin_(registry|source_catalog)_service\\.dart" \
  "wasm plugins screen imports plugin DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_order_tracking_store\\.dart" \
  "trading drone screen imports order-tracking DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_risk_governor_service\\.dart" \
  "trading drone screen imports risk DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_live_decision_service\\.dart" \
  "trading drone screen imports live-decision DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_exchange_service\\.dart" \
  "trading drone screen imports exchange DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_order_sizing_service\\.dart" \
  "trading drone screen imports order-sizing DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_signal_rank_use_case_service\\.dart" \
  "trading drone screen imports signal-rank DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_live_strategy_use_case_service\\.dart" \
  "trading drone screen imports live-strategy DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_intent_use_case_service\\.dart" \
  "trading drone screen imports intent DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_exchange_execution_use_case_service\\.dart" \
  "trading drone screen imports exchange-execution DTOs from model boundary"
require_absent "$TRADING_SCREEN" "services/bingx_futures_order_replacement_service\\.dart" \
  "trading drone screen imports replacement DTOs from model boundary"
require_absent "$SCREENS" "services/capsule_chat_delivery_service\\.dart" \
  "screens import capsule chat DTOs from model boundary"
require_absent "$SCREENS" "services/plugin_contract_handlers\\.dart" \
  "screens import plugin contract ids from model boundary"
require_absent "$SCREENS" "services/plugin_host_api_service\\.dart" \
  "screens import plugin host API DTOs from model boundary"
require_absent "$PLUGIN_CONTRACT_HANDLERS" "plugin_host_api_service\\.dart" \
  "plugin contract handlers import plugin host API DTOs from model boundary"
require_absent "$ROOT/flutter/lib/services/plugin_host_contract_handler.dart" "plugin_host_api_service\\.dart" \
  "plugin host contract handler imports plugin host API DTOs from model boundary"
require_absent "$WASM_RUNTIME_SERVICE" "plugin_host_api_service\\.dart" \
  "wasm runtime service imports plugin host API DTOs from model boundary"
require_present "$CAPSULE_DOCTOR_SCREEN" 'AiToolingModuleService\(runtime: widget\.runtime\)' \
  "capsule analyst screen uses AI tooling module boundary"
require_absent "$CAPSULE_DOCTOR_SCREEN" 'late final [A-Za-z0-9_]+Service |build[A-Za-z0-9_]*Service\(' \
  "capsule analyst screen does not keep individual service fields"
require_absent "$LEDGER_INSPECTOR_SCREEN" 'build[A-Za-z0-9_]*Service\(' \
  "ledger inspector screen uses module boundary instead of assembling service graph"
require_absent "$WIDGETS" 'AiToolingModuleService|AppRuntimeService|build[A-Za-z0-9_]*Service\(' \
  "widgets do not construct runtime/module service graphs"

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

# 9) Ledger-derived slot projection contract: no legacy per-slot FFI probes in Flutter.
require_absent "$BINDINGS" 'starterExists|getStarterId|getStarterType' \
  "flutter bindings do not expose legacy per-slot starter probes"
require_absent "$BINDINGS" 'hivra_starter_get_id|hivra_starter_get_type|hivra_starter_exists' \
  "flutter bindings do not bind legacy starter FFI symbols"

exit "$STATUS"
