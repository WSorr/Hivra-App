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

check_crypto_fixed_size_compatibility_boundary() {
  local pattern='(?i)(pubkey|public_key|private_key|secret_key|signer|sign(?:ature)?|seed).{0,100}\[u8;\s*(32|64)\]|\[u8;\s*(32|64)\].{0,100}(pubkey|public_key|private_key|secret_key|signer|sign(?:ature)?|seed)|pubkey32|signature64|cardSignature64'
  local matches
  matches="$({
    cd "$ROOT"
    rg --pcre2 -n \
      --glob '!**/test/**' \
      --glob '!**/tests/**' \
      --glob '!**/tests.rs' \
      --glob '!**/*_test.dart' \
      --glob '!target/**' \
      --glob '!flutter/build/**' \
      "$pattern" core engine adapters platform flutter/lib || true
  })"

  local match_count
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  if (( match_count <= 100 )); then
    pass "fixed-size crypto compatibility debt is non-increasing ($match_count/100)"
  else
    fail "fixed-size crypto compatibility debt grew ($match_count/100)"
  fi

  local unexpected=""
  local file
  while IFS=: read -r file _; do
    [[ -z "$file" ]] && continue
    case "$file" in
      adapters/hivra-ed25519-crypto/src/lib.rs | \
        adapters/hivra-nostr-crypto/src/lib.rs | \
        adapters/hivra-transport/src/lib.rs | \
        adapters/hivra-transport/src/nostr/mod.rs | \
        core/hivra-core/src/capsule.rs | \
        core/hivra-core/src/invitation.rs | \
        core/hivra-core/src/primitives.rs | \
        core/hivra-core/src/relationship.rs | \
        engine/hivra-engine/src/lib.rs | \
        flutter/lib/ffi/app_runtime_runtime.dart | \
        flutter/lib/ffi/capsule_address_runtime.dart | \
        flutter/lib/ffi/hivra_bindings.dart | \
        flutter/lib/ffi/invitation_actions_runtime.dart | \
        flutter/lib/services/capsule_address_service.dart | \
        platform/hivra-ffi/src/capsule_api.rs | \
        platform/hivra-ffi/src/chat_api.rs | \
        platform/hivra-ffi/src/consensus_attestation_api.rs | \
        platform/hivra-ffi/src/invitation_api.rs | \
        platform/hivra-ffi/src/invitation_support.rs | \
        platform/hivra-ffi/src/runtime_support.rs | \
        platform/hivra-ffi/src/seed_api.rs | \
        platform/hivra-ffi/src/selfcheck_api.rs | \
        platform/hivra-keystore/src/lib.rs) ;;
      *) unexpected+="$file"$'\n' ;;
    esac
  done <<< "$matches"

  if [[ -z "$unexpected" ]]; then
    pass "fixed-size crypto shapes stay inside the explicit 1.x compatibility boundary"
  else
    fail "fixed-size crypto shapes escaped the explicit 1.x compatibility boundary"
    printf '%s' "$unexpected" | sort -u >&2
  fi
}

TRANSPORT_TOML="$ROOT/adapters/hivra-transport/Cargo.toml"
TRANSPORT_SRC="$ROOT/adapters/hivra-transport/src"
NOSTR_TRANSPORT="$TRANSPORT_SRC/nostr/mod.rs"
DEP_CHECK="$ROOT/tools/review/dependency_check.sh"
SPEC="$ROOT/docs/specification.md"
README="$ROOT/README.md"
DOCS_README="$ROOT/docs/README.md"
PRODUCT_AXIS="$ROOT/docs/product-axis.md"
CHECKLIST="$ROOT/docs/checklists/architecture-review.md"
ROADMAP="$ROOT/docs/roadmap.md"
EXEC_DISCIPLINE="$ROOT/docs/architecture-execution-discipline.md"
V2_BLUEPRINT="$ROOT/docs/architecture-v2-blueprint.md"
PLATFORM_TOOLCHAIN="$ROOT/docs/platform-toolchain-evolution.md"
CONTINUOUS_LEDGER_PROTOCOL="$ROOT/docs/architecture/continuous-ledger-protocol-v5.md"
DELIVERY_LIFECYCLE_DOC="$ROOT/docs/architecture/transport-delivery-lifecycle.md"
EXTERNAL_EFFECT_LIFECYCLE_DOC="$ROOT/docs/architecture/external-effect-lifecycle.md"
AI_PROPOSAL_BOUNDARY_DOC="$ROOT/docs/architecture/ai-proposal-boundary.md"
CAPSULE_AI_RUNTIME_DOC="$ROOT/docs/architecture/capsule-ai-runtime.md"
MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC="$ROOT/docs/plugins/moltbook_engagement_lifecycle_v1.md"
TRANSPORT_HEALTH_CHECKLIST="$ROOT/docs/checklists/transport-health-policy.md"
CAPSULE_SECRET_LIFECYCLE_DOC="$ROOT/docs/architecture/capsule-scoped-secret-lifecycle.md"
EXTERNAL_PLUGIN_SOURCE="$ROOT/docs/plugins/external_plugin_source.md"
PLUGIN_HOST_API_DOC="$ROOT/docs/plugins/plugin_host_api_v1.md"

TRANSPORT_HEALTH_POLICY="$ROOT/flutter/lib/services/transport_health_policy_service.dart"
CAPSULE_CHAT_DELIVERY="$ROOT/flutter/lib/services/capsule_chat_delivery_service.dart"
ATTESTATION_SYNC="$ROOT/flutter/lib/services/consensus_attestation_sync_service.dart"
MAIN_SCREEN="$ROOT/flutter/lib/screens/main_screen.dart"

RUNTIME="$ROOT/flutter/lib/services/app_runtime_service.dart"
INV_INTENT="$ROOT/flutter/lib/services/invitation_intent_handler.dart"
INV_ACTIONS="$ROOT/flutter/lib/services/invitation_actions_service.dart"
CAPSULE_FFI_WORKER_QUEUE="$ROOT/flutter/lib/services/capsule_ffi_worker_queue.dart"
DELIVERY_LIFECYCLE="$ROOT/flutter/lib/services/capsule_delivery_lifecycle_service.dart"
DELIVERY_OUTBOX="$ROOT/flutter/lib/services/delivery_outbox_store.dart"
FFI_INVITATION_API="$ROOT/platform/hivra-ffi/src/invitation_api.rs"
FFI_CHAT_API="$ROOT/platform/hivra-ffi/src/chat_api.rs"
FFI_ATTESTATION_API="$ROOT/platform/hivra-ffi/src/consensus_attestation_api.rs"
FFI_TRANSPORT_CACHE="$ROOT/platform/hivra-ffi/src/transport_cache.rs"
FFI_INBOUND_QUARANTINE="$ROOT/platform/hivra-ffi/src/inbound_quarantine.rs"
PLATFORM_KEYSTORE="$ROOT/platform/hivra-keystore/src/lib.rs"
HIVRA_BINDINGS="$ROOT/flutter/lib/ffi/hivra_bindings.dart"
CAPSULE_PERSISTENCE="$ROOT/flutter/lib/services/capsule_persistence_service.dart"
PLUGIN_GUARD="$ROOT/flutter/lib/services/plugin_execution_guard_service.dart"
PLUGIN_HOST="$ROOT/flutter/lib/services/plugin_host_api_service.dart"
PLUGIN_CONTRACT_HANDLERS="$ROOT/flutter/lib/services/plugin_contract_handlers.dart"
WASM_REGISTRY="$ROOT/flutter/lib/services/wasm_plugin_registry_service.dart"
SCREENS="$ROOT/flutter/lib/screens"
MAIN_SCREEN="$SCREENS/main_screen.dart"
TRADING_SCREEN="$SCREENS/trading_drone_screen.dart"
WASM_PLUGINS_SCREEN="$SCREENS/wasm_plugins_screen.dart"
MOLTBOOK_AMBASSADOR_SCREEN="$SCREENS/moltbook_ambassador_screen.dart"
MOLTBOOK_PROVIDER_ADAPTER="$ROOT/flutter/lib/services/moltbook_provider_adapter.dart"
MOLTBOOK_EFFECT_ADAPTER="$ROOT/flutter/lib/services/moltbook_external_effect_adapter.dart"
MOLTBOOK_PUBLICATION="$ROOT/flutter/lib/services/moltbook_publication_service.dart"
PLUGIN_RUNTIME_MODULE="$ROOT/flutter/lib/services/plugin_runtime_module_service.dart"
PLUGIN_CONTRACT_IDS="$ROOT/flutter/lib/models/plugin_contract_ids.dart"
MOLTBOOK_CONNECTION="$ROOT/flutter/lib/services/moltbook_connection_service.dart"
MOLTBOOK_DRAFT_STORE="$ROOT/flutter/lib/services/moltbook_draft_store.dart"
MOLTBOOK_PUBLIC_BULLETIN_AI="$ROOT/flutter/lib/services/moltbook_public_bulletin_ai_service.dart"
MOLTBOOK_AMBASSADOR_MODELS="$ROOT/flutter/lib/models/moltbook_ambassador_models.dart"
MOLTBOOK_CYCLE_TRIGGER="$ROOT/flutter/lib/services/moltbook_cycle_trigger_service.dart"
CAPSULE_DOCTOR_SCREEN="$SCREENS/capsule_doctor_screen.dart"
INVITATIONS_SCREEN="$SCREENS/invitations_screen.dart"
LEDGER_INSPECTOR_SCREEN="$SCREENS/ledger_inspector_screen.dart"
WIDGETS="$ROOT/flutter/lib/widgets"
SERVICES="$ROOT/flutter/lib/services"
INSPECTOR="$ROOT/flutter/lib/screens/ledger_inspector_screen.dart"
PAIRWISE="$ROOT/flutter/lib/services/pairwise_snapshot_service.dart"
SUPPORT="$ROOT/flutter/lib/services/ledger_view_support.dart"
LEDGER_VIEW="$ROOT/flutter/lib/services/ledger_view_service.dart"
LEDGER_SUMMARY="$ROOT/flutter/lib/services/capsule_ledger_summary_parser.dart"
INVITATION_PROJECTION="$ROOT/flutter/lib/services/invitation_projection_service.dart"
CORE_INVITATION="$ROOT/core/hivra-core/src/invitation.rs"
RELATIONSHIP_PROJECTION="$ROOT/flutter/lib/services/relationship_projection_service.dart"
CORE_RELATIONSHIP="$ROOT/core/hivra-core/src/relationship.rs"
FFI_LEDGER_API="$ROOT/platform/hivra-ffi/src/ledger_api.rs"
CONSENSUS="$ROOT/flutter/lib/services/consensus_processor.dart"
HISTORY_PROJECTION="$ROOT/flutter/lib/services/capsule_history_projection_service.dart"
CONSENSUS_ATTESTATION_SYNC="$ROOT/flutter/lib/services/consensus_attestation_sync_service.dart"
CONSENSUS_ATTESTATION_STORE="$ROOT/flutter/lib/services/consensus_attestation_store.dart"
CAPSULE_FILE_STORE="$ROOT/flutter/lib/services/capsule_file_store.dart"
CAPSULE_FILE_STORE_TEST="$ROOT/flutter/test/capsule_file_store_test.dart"
CAPSULE_BACKUP_CODEC_TEST="$ROOT/flutter/test/capsule_backup_codec_test.dart"
ANDROID_MANIFEST="$ROOT/flutter/android/app/src/main/AndroidManifest.xml"
ANDROID_BACKUP_RULES="$ROOT/flutter/android/app/src/main/res/xml/backup_rules.xml"
ANDROID_DATA_EXTRACTION_RULES="$ROOT/flutter/android/app/src/main/res/xml/data_extraction_rules.xml"
ANDROID_KEYSTORE_BRIDGE="$ROOT/flutter/android/app/src/main/kotlin/com/hivra/hivra_app/HivraKeystoreBridge.kt"
ANDROID_KEYSTORE_ADAPTER="$ROOT/platform/hivra-keystore/src/android/mod.rs"
CAPSULE_INDEX_STORE="$ROOT/flutter/lib/services/capsule_index_store.dart"
CAPSULE_PERSISTENCE="$ROOT/flutter/lib/services/capsule_persistence_service.dart"
CAPSULE_SECRET_VAULT="$ROOT/flutter/lib/services/capsule_scoped_secret_vault.dart"
PLUGIN_RUNTIME_MODULE="$ROOT/flutter/lib/services/plugin_runtime_module_service.dart"
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
require_present "$NOSTR_TRANSPORT" 'const APP_EVENT_KIND: Kind = Kind::Custom\(9444\)' \
  "Nostr transport emits the canonical Hivra authenticated-envelope kind"
require_present "$NOSTR_TRANSPORT" 'nip44::Version::V2' \
  "Nostr transport encrypts new envelopes with NIP-44 v2"
require_present "$NOSTR_TRANSPORT" 'const LEGACY_NIP04_EVENT_KIND: Kind = Kind::Custom\(4\)' \
  "deprecated NIP-04 input remains explicitly isolated from the write kind"

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
require_present "$PRODUCT_AXIS" 'Person-First Runtime \(PFR\)' \
  "product axis defines the Person-First Runtime category"
require_present "$SPEC" 'PFR is not a second runtime layer, a new Core entity, or a separate execution' \
  "specification keeps PFR on the canonical architecture path"
require_present "$CHECKLIST" 'preserves the Person-First Runtime \(PFR\)' \
  "architecture review protects person-first ownership"
require_present "$PRODUCT_AXIS" 'Cryptographic agility' \
  "product axis defines cryptographic agility as a permanent invariant"
require_present "$SPEC" '^### 0\.3 Cryptographic Agility' \
  "specification defines the canonical crypto-agility contract"
require_present "$SPEC" '`CapsuleId` is conceptually separate from any public key' \
  "specification separates CapsuleId from concrete public keys"
require_present "$SPEC" '^KeyDescriptor \{' \
  "specification defines versioned key descriptors"
require_present "$SPEC" '^SignatureProof \{' \
  "specification defines suite-tagged signature proofs"
require_present "$SPEC" 'Existing Ledger events are never rewritten or re-signed' \
  "specification preserves append-only history across suite migration"
require_present "$SPEC" 'hybrid KEM envelope' \
  "specification records hybrid KEM confidentiality migration"
require_present "$SPEC" '^### 6\.4 Capsule Effect Proof' \
  "specification defines independently verifiable Capsule Effect Proof"
require_present "$V2_BLUEPRINT" '^### Cross-Cutting Invariant: Cryptographic Agility' \
  "v2 blueprint carries the crypto-agility migration contract"
require_present "$CHECKLIST" '^## Cryptographic Agility' \
  "architecture checklist reviews crypto agility"
require_present "$ROADMAP" '^\- `12\.4 Cryptographic Agility Compatibility Debt`' \
  "roadmap registers fixed-size crypto compatibility debt"
check_crypto_fixed_size_compatibility_boundary
require_present "$ROOT/flutter/lib/services/capsule_backup_codec.dart" 'encryptedVersion = 2' \
  "backup codec defines encrypted envelope v2"
require_present "$ROOT/flutter/lib/services/capsule_backup_codec.dart" 'AesGcm\.with256bits' \
  "backup codec uses authenticated AES-256-GCM"
require_present "$ROOT/flutter/lib/services/capsule_backup_codec.dart" 'Hkdf\(hmac: Hmac\.sha256\(\)' \
  "backup codec derives a domain-separated export key"
require_present "$ROOT/flutter/lib/services/temporary_backup_share_service.dart" 'finally' \
  "temporary backup share lifecycle always enters cleanup"
require_present "$ANDROID_MANIFEST" 'android:allowBackup="false"' \
  "Android disables implicit OS backup of Capsule runtime state"
require_present "$ANDROID_MANIFEST" 'android:fullBackupContent="@xml/backup_rules"' \
  "Android 11-and-lower backup exclusions are explicit"
require_present "$ANDROID_MANIFEST" 'android:dataExtractionRules="@xml/data_extraction_rules"' \
  "Android 12+ cloud and device-transfer exclusions are explicit"
require_present "$ANDROID_BACKUP_RULES" '<exclude domain="device_sharedpref" path="\." />' \
  "legacy Android backup rules exclude device-protected private state"
require_present "$ANDROID_DATA_EXTRACTION_RULES" '<device-transfer>' \
  "Android data extraction rules govern device-to-device transfer"
require_present "$ANDROID_DATA_EXTRACTION_RULES" '<exclude domain="device_sharedpref" path="\." />' \
  "Android cloud and device transfer exclude device-protected private state"
require_present "$ANDROID_KEYSTORE_BRIDGE" 'nativeInit\(requireNotNull\(appContext\)\.filesDir\.absolutePath\)' \
  "Android keystore initializes from the active runtime user's app-private files directory"
require_present "$ANDROID_KEYSTORE_ADAPTER" 'APP_FILES_DIR' \
  "Android keystore adapter consumes the canonical app-private files directory"
require_absent "$ANDROID_KEYSTORE_ADAPTER" '/data/user/0|/data/data/' \
  "Android keystore adapter does not hardcode owner-user storage paths"
require_absent "$ROOT/flutter/lib/screens/backup_screen.dart" 'Directory\.systemTemp|SharePlus\.instance\.share' \
  "backup screen does not own temporary export or share effects"
require_absent "$ROOT/flutter/lib/screens/capsule_selector_screen.dart" 'Directory\.systemTemp|SharePlus\.instance\.share' \
  "capsule selector does not own temporary export or share effects"
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
require_present "$SPEC" 'Canonical Domain Projection Contract' \
  "spec defines canonical Core projection contract"
require_present "$SPEC" '`CurrentView`' \
  "spec defines current-state canonical view"
require_present "$SPEC" '`PairView`' \
  "spec defines pair-consensus canonical view"
require_present "$SPEC" '`HistoryView`' \
  "spec defines history/audit canonical view"
require_present "$SPEC" 'MUST NOT independently walk raw events' \
  "spec forbids independent domain replay outside Core"
require_present "$PRODUCT_AXIS" 'CurrentView.*PairView.*HistoryView' \
  "product axis binds consumers to canonical scoped views"
require_present "$CHECKLIST" 'Normative domain lifecycle semantics are interpreted once' \
  "architecture review checks single domain interpreter"
require_present "$ROADMAP" 'Canonical Core Projection Convergence' \
  "roadmap tracks canonical projection convergence debt"
require_present "$CORE_INVITATION" 'pub fn invitation_current_view_v1' \
  "Core owns the versioned invitation current view"
require_present "$FFI_LEDGER_API" 'hivra_project_invitation_current_view_v1' \
  "FFI exposes the canonical invitation current view"
require_present "$INVITATION_PROJECTION" 'hivra\.invitation_current_view' \
  "Flutter invitation adapter consumes the versioned Core view"
require_absent "$INVITATION_PROJECTION" \
  'InvitationSent|InvitationReceived|InvitationAccepted|InvitationRejected|InvitationExpired|kindCode\(|payloadBytes\(' \
  "Flutter invitation adapter does not replay raw domain events"
require_absent "$LEDGER_SUMMARY" 'InvitationProjectionService' \
  "ledger summary does not own a second invitation reducer"
require_present "$CORE_RELATIONSHIP" 'pub fn relationship_current_view_v1' \
  "Core owns the versioned relationship current view"
require_present "$FFI_LEDGER_API" 'hivra_project_relationship_current_view_v1' \
  "FFI exposes the canonical relationship current view"
require_present "$RELATIONSHIP_PROJECTION" 'hivra\.relationship_current_view' \
  "Flutter relationship adapter consumes the versioned Core view"
require_absent "$RELATIONSHIP_PROJECTION" \
  'RelationshipEstablished|RelationshipBroken|kindCode\(|payloadBytes\(|\['"'"'events'"'"'\]' \
  "Flutter relationship adapter does not replay raw domain events"
require_absent "$LEDGER_SUMMARY" 'RelationshipProjectionService' \
  "ledger summary does not own a second relationship reducer"
require_present "$ROOT/core/hivra-core/src/pair.rs" 'pub fn pair_view_v1' \
  "Core owns the versioned pair-consensus view"
require_present "$FFI_LEDGER_API" 'hivra_project_pair_view_v1' \
  "FFI exposes the canonical pair-consensus view"
require_present "$CONSENSUS" 'hivra\.pair_view' \
  "Flutter consensus adapter consumes the versioned Core PairView"
require_absent "$CONSENSUS" \
  'InvitationSent|InvitationReceived|InvitationAccepted|InvitationRejected|InvitationExpired|RelationshipEstablished|RelationshipBroken|kindCode\(|payloadBytes\(|\['"'"'events'"'"'\]' \
  "Flutter consensus adapter does not replay raw domain events"
require_present "$ROOT/core/hivra-core/src/history.rs" 'pub fn history_view_v1' \
  "Core owns the versioned subject-scoped history view"
require_present "$FFI_LEDGER_API" 'hivra_project_history_view_v1' \
  "FFI exposes the canonical subject-scoped history view"
require_present "$HISTORY_PROJECTION" 'hivra\.history_view' \
  "Flutter history adapter consumes the versioned Core HistoryView"
require_absent "$HISTORY_PROJECTION" \
  'kindCode\(|payloadBytes\(|\['"'"'events'"'"'\]|InvitationSent|InvitationReceived|InvitationAccepted|InvitationRejected|InvitationExpired|StarterCreated|StarterBurned|RelationshipEstablished|RelationshipBroken' \
  "Flutter history adapter does not replay raw domain events"
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
require_present "$CHECKLIST" '## AI Proposal Boundary' \
  "architecture checklist includes AI proposal boundary section"
require_present "$CHECKLIST" 'Prompt wording is treated only as defense in depth' \
  "architecture checklist rejects prompt-only enforcement"
require_present "$CHECKLIST" 'Every drone method declares exactly one scope: `solo`, `market_scan`, or `pair_scoped`\.' \
  "architecture checklist requires explicit drone consensus scope"
require_present "$CHECKLIST" 'No pair-scoped path treats "any signable peer" as authorization for a missing or different peer\.' \
  "architecture checklist forbids any-signable-peer consensus fallback"
require_present "$CHECKLIST" 'Repo boundary is preserved: `Hivra-App` is host/runtime only; plugin implementation source/release flow lives in `hivra-plugins`\.' \
  "architecture checklist enforces app-vs-plugin repo boundary"
require_present "$EXEC_DISCIPLINE" '^# Hivra Architecture Execution Discipline v1' \
  "execution discipline doc exists"
require_present "$EXEC_DISCIPLINE" 'if two actions produce the same canonical domain or effect result' \
  "execution discipline merges equivalent result paths under one owner"
require_present "$DELIVERY_LIFECYCLE_DOC" '^# Transport Delivery Lifecycle v1' \
  "delivery lifecycle architecture doc exists"
require_present "$EXTERNAL_EFFECT_LIFECYCLE_DOC" '^# External Effect Lifecycle v1' \
  "external effect lifecycle architecture doc exists"
require_present "$EXTERNAL_EFFECT_LIFECYCLE_DOC" 'ExternalEffectService.*sole lifecycle owner' \
  "external effect lifecycle has one application owner"
require_present "$EXTERNAL_EFFECT_LIFECYCLE_DOC" 'late adapter result cannot overwrite a newer reconciliation' \
  "external effect lifecycle rejects stale adapter completion"
require_present "$EXTERNAL_EFFECT_LIFECYCLE_DOC" 'must not share journals, DTOs' \
  "external effects remain separate from transport delivery"
require_present "$AI_PROPOSAL_BOUNDARY_DOC" '^# AI Proposal Boundary' \
  "AI proposal boundary architecture doc exists"
require_present "$AI_PROPOSAL_BOUNDARY_DOC" 'Inference ends before authority begins' \
  "AI proposal boundary separates inference from authority"
require_present "$AI_PROPOSAL_BOUNDARY_DOC" 'prompt wording is cited as the primary security boundary' \
  "AI proposal boundary rejects prompt-only security"
require_present "$CAPSULE_AI_RUNTIME_DOC" '^# Capsule AI Runtime' \
  "Capsule AI Runtime architecture contract exists"
require_present "$CAPSULE_AI_RUNTIME_DOC" 'There is no direct `drone -> Gemini`, `screen -> OpenAI`' \
  "Capsule AI Runtime forbids direct feature-to-provider paths"
require_present "$CAPSULE_AI_RUNTIME_DOC" 'A locked automatic cycle stops before inference' \
  "Capsule AI Runtime defines fail-closed credential sessions"
require_present "$CAPSULE_AI_RUNTIME_DOC" 'A global `AiDto` layer and pass-through feature wrappers' \
  "Capsule AI Runtime forbids global AI DTO prostheses"
require_present "$CAPSULE_AI_RUNTIME_DOC" 'AI Runtime imports Core mutation or an external-effect adapter' \
  "Capsule AI Runtime cannot acquire Core or effect authority"
require_present "$SPEC" 'architecture/ai-proposal-boundary\.md' \
  "specification binds AI-enabled capabilities to proposal boundary"
require_present "$SPEC" 'architecture/capsule-ai-runtime\.md' \
  "specification binds inference to Capsule AI Runtime"
require_present "$DOCS_README" 'architecture/ai-proposal-boundary\.md' \
  "docs index references AI proposal boundary"
require_present "$DOCS_README" 'architecture/capsule-ai-runtime\.md' \
  "docs index references Capsule AI Runtime"
require_present "$CONTINUOUS_LEDGER_PROTOCOL" '^# Cryptographically Continuous Ledger Protocol v5' \
  "continuous-ledger v5 protocol contract exists"
require_present "$CONTINUOUS_LEDGER_PROTOCOL" 'Local history acceptance' \
  "continuous-ledger contract separates domain and local history signatures"
require_present "$CONTINUOUS_LEDGER_PROTOCOL" 'legacy_snapshot_commitment' \
  "continuous-ledger contract defines explicit v4 migration anchor"
require_present "$CONTINUOUS_LEDGER_PROTOCOL" '^### P3-A: Core commitments and vectors' \
  "continuous-ledger contract defines Core vector implementation unit"
require_present "$CONTINUOUS_LEDGER_PROTOCOL" '^### P3-B: Engine and FFI append/import' \
  "continuous-ledger contract defines Engine/FFI implementation unit"
require_present "$CONTINUOUS_LEDGER_PROTOCOL" '^### P3-C: Persistence and release evidence' \
  "continuous-ledger contract defines persistence implementation unit"
require_present "$CAPSULE_BACKUP_CODEC_TEST" 'preserves continuous v5 evidence through backup envelope' \
  "continuous-ledger backup evidence preserves the complete v5 export object"
require_present "$CAPSULE_FILE_STORE_TEST" 'keeps ledger and backup generation when derived projection fails' \
  "continuous-ledger persistence permits only the derived projection to lag"
require_present "$DOCS_README" 'continuous-ledger-protocol-v5\.md' \
  "docs index references continuous-ledger protocol"
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
require_present "$PLATFORM_TOOLCHAIN" '^# Hivra Platform Toolchain Evolution' \
  "platform toolchain evolution contract exists"
require_present "$PLATFORM_TOOLCHAIN" 'Hivra does not plan a bridge-framework' \
  "platform contract keeps the explicit C ABI boundary"
require_present "$PLATFORM_TOOLCHAIN" '^### T0: Baseline and reproducibility' \
  "platform contract defines reproducible baseline work"
require_present "$PLATFORM_TOOLCHAIN" '^### T1: Flutter/Dart stable update' \
  "platform contract isolates Flutter/Dart upgrades"
require_present "$PLATFORM_TOOLCHAIN" '^### T2: Android build-stack update' \
  "platform contract treats Android tooling as a compatibility set"
require_present "$PLATFORM_TOOLCHAIN" '^### T3: macOS/Xcode update' \
  "platform contract defines macOS/Xcode evidence"
require_present "$ROADMAP" '^## Platform Toolchain Evolution' \
  "roadmap tracks platform toolchain evolution separately"
require_present "$DOCS_README" 'platform-toolchain-evolution\.md' \
  "docs index references platform toolchain evolution"
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
require_present "$FFI_INVITATION_API" 'queue_incoming_chat_if_match' \
  "single transport receive owner routes chat before core event parsing"
require_present "$FFI_CHAT_API" 'hivra_transport_receive_quick' \
  "chat receive delegates polling to the single transport receive owner"
require_absent "$FFI_CHAT_API" '\.receive\(' \
  "chat receive does not own a parallel relay poll path"
require_absent "$SCREENS" "import '../services/invitation_actions_service.dart';" \
  "screens do not import invitation_actions_service directly"
require_absent "$SCREENS" "import '../services/consensus_runtime_service.dart';" \
  "screens do not import consensus_runtime_service directly"
require_present "$CAPSULE_FFI_WORKER_QUEUE" 'class CapsuleFfiWorkerQueue' \
  "transport workers share a process-global FFI queue"
require_present "$INV_ACTIONS" 'CapsuleFfiWorkerQueue\.shared' \
  "invitation transport workers use the shared FFI queue"
require_present "$INV_ACTIONS" 'capsuleHex: initialCapsuleHex' \
  "queued invitation workers refresh bootstrap inside the capsule queue"
require_present "$DELIVERY_LIFECYCLE" 'class CapsuleDeliveryLifecycleService' \
  "delivery lifecycle owns shared retry scheduling"
require_present "$DELIVERY_LIFECYCLE" 'receipt-to-outbox' \
  "delivery lifecycle documents receipt reconciliation ownership"
require_present "$DELIVERY_OUTBOX" 'const int deliveryOutboxSchemaVersion = 5' \
  "delivery outbox uses explicit aggregate quarantine schema"
require_present "$DELIVERY_OUTBOX" 'DeliveryOutboxStatus\.quarantined' \
  "unreferenced retry obligations enter durable quarantine"
require_present "$DELIVERY_OUTBOX" 'schemaVersion < deliveryOutboxSchemaVersion' \
  "legacy outbox quarantine is rewritten under schema v5"
require_present "$DELIVERY_LIFECYCLE" 'if \(expected == null\) return false' \
  "aggregate outbox records cannot bind adapter receipts"
require_present "$DELIVERY_LIFECYCLE_DOC" 'excluded from every due-item query' \
  "delivery lifecycle records non-due quarantine semantics"
require_present "$FFI_TRANSPORT_CACHE" 'static NOSTR_TRANSPORT:' \
  "default and quick operations share one Nostr session cache"
require_absent "$FFI_TRANSPORT_CACHE" 'DEFAULT_NOSTR_TRANSPORT|QUICK_NOSTR_TRANSPORT|cache_for_profile' \
  "transport profiles do not own separate sessions or cursors"
require_present "$FFI_INVITATION_API" 'receive_batch_with_timeout\(profile\.receive_timeout_secs\(\)\)' \
  "receive profile selects an operation budget on the shared session"
require_present "$DELIVERY_LIFECYCLE_DOC" 'acknowledged ingress handoff' \
  "sender quarantine remains gated on durable ingress acknowledgement"
require_present "$DELIVERY_LIFECYCLE_DOC" '^### Acknowledged Ingress Handoff Contract' \
  "acknowledged ingress has one normative lifecycle contract"
require_present "$DELIVERY_LIFECYCLE_DOC" 'stable adapter event id' \
  "ingress batch retains stable adapter event identity"
require_present "$DELIVERY_LIFECYCLE_DOC" 'greatest' \
  "relay cursor advances only through a terminal disposition prefix"
require_present "$DELIVERY_LIFECYCLE_DOC" 'Quarantine recovery MUST re-enter the same canonical FFI ingress router' \
  "quarantine recovery cannot create a second ingress route"
require_present "$DELIVERY_LIFECYCLE_DOC" 'full quarantine capacity leaves the affected' \
  "full quarantine capacity applies cursor-safe backpressure"
require_present "$SPEC" '^### 5\.5 Acknowledged Ingress Handoff' \
  "specification binds acknowledged ingress to the canonical lifecycle"
require_present "$CHECKLIST" 'original event identity' \
  "architecture review preserves event identity across quarantine replay"
require_present "$DELIVERY_LIFECYCLE_DOC" '^### Inbound Quarantine Repository and Sender Policy Contract' \
  "inbound quarantine has one normative repository contract"
require_present "$DELIVERY_LIFECYCLE_DOC" 'CapsuleInboundQuarantineRepository' \
  "one repository owns retained inbound quarantine"
require_present "$DELIVERY_LIFECYCLE_DOC" 'at most `256` retained records per scope' \
  "quarantine record capacity is explicit"
require_present "$DELIVERY_LIFECYCLE_DOC" 'at most `32 MiB` of encrypted envelope bytes per scope' \
  "quarantine byte capacity is explicit"
require_present "$DELIVERY_LIFECYCLE_DOC" 'retained payload expiry is `72 hours`' \
  "quarantine retention is explicit"
require_present "$DELIVERY_LIFECYCLE_DOC" 'MUST NOT evict another retained payload' \
  "full quarantine cannot silently evict retained input"
require_present "$DELIVERY_LIFECYCLE_DOC" 'SenderIngressPolicyV1' \
  "sender policy is versioned"
require_present "$DELIVERY_LIFECYCLE_DOC" 'burst of `8` new event ids' \
  "sender policy burst is explicit"
require_present "$DELIVERY_LIFECYCLE_DOC" 'permit every `15 seconds`' \
  "sender policy refill is explicit"
require_present "$DELIVERY_LIFECYCLE_DOC" 'under a `quarantine_replay` flag' \
  "quarantine replay cannot be charged twice"
require_present "$DELIVERY_LIFECYCLE_DOC" 'reused as storage keys' \
  "quarantine storage uses a distinct crypto role"
require_present "$SPEC" '^### 5\.6 Inbound Quarantine and Sender Policy' \
  "specification binds quarantine to the canonical lifecycle"
require_present "$CHECKLIST" 'full capacity returns `retry`' \
  "architecture review enforces quarantine backpressure"
require_present "$FFI_INBOUND_QUARANTINE" 'struct CapsuleInboundQuarantineRepository' \
  "FFI boundary owns one inbound quarantine repository"
require_present "$FFI_INBOUND_QUARANTINE" 'const MAX_RECORDS: usize = 256' \
  "runtime pins the schema-v1 quarantine record bound"
require_present "$FFI_INBOUND_QUARANTINE" 'const MAX_CIPHERTEXT_BYTES: usize = 32 \* 1024 \* 1024' \
  "runtime pins the schema-v1 quarantine byte bound"
require_present "$FFI_INBOUND_QUARANTINE" 'const PAYLOAD_RETENTION_SECS: u64 = 72 \* 60 \* 60' \
  "runtime pins the schema-v1 quarantine retention"
require_present "$FFI_INBOUND_QUARANTINE" 'seal_inbound_quarantine_record' \
  "quarantine payloads are authenticated-encrypted at rest"
require_present "$PLATFORM_KEYSTORE" 'HIVRA_INBOUND_QUARANTINE_RECORD_KEY_v1' \
  "platform crypto owns a distinct quarantine record key role"
require_present "$PLATFORM_KEYSTORE" 'HIVRA_INBOUND_QUARANTINE_SNAPSHOT_KEY_v1' \
  "platform crypto owns a distinct quarantine snapshot key role"
require_present "$FFI_INVITATION_API" 'CapsuleInboundQuarantineRepository::open' \
  "canonical ingress opens the Capsule-scoped quarantine repository"
require_present "$FFI_INVITATION_API" 'recover_one_quarantined_envelope' \
  "canonical ingress owns bounded quarantine recovery"
require_present "$FFI_INVITATION_API" 'route_inbound_envelope' \
  "quarantine recovery reuses the canonical ingress router"
require_present "$FFI_INVITATION_API" 'InboundDeliveryDisposition::Quarantined' \
  "durable quarantine produces the acknowledged ingress disposition"
require_present "$FFI_INBOUND_QUARANTINE" 'struct SenderIngressPolicyV1' \
  "sender policy state shares the canonical encrypted snapshot"
require_present "$FFI_INBOUND_QUARANTINE" 'const SENDER_POLICY_BURST: u8 = 8' \
  "runtime pins sender policy burst"
require_present "$FFI_INBOUND_QUARANTINE" 'const SENDER_POLICY_REFILL_SECS: u64 = 15' \
  "runtime pins sender policy refill"
require_present "$FFI_INBOUND_QUARANTINE" 'const MAX_POLICY_SENDERS: usize = 1024' \
  "runtime bounds active sender policy state"
require_present "$FFI_INBOUND_QUARANTINE" 'apply_sender_policy' \
  "repository exposes one sender policy activation path"
require_present "$FFI_INVITATION_API" 'quarantine\.apply_sender_policy' \
  "canonical ingress applies sender policy before routing"
require_present "$FFI_INVITATION_API" 'recover_one_quarantined_envelope' \
  "quarantine recovery remains outside sender policy charging"
require_absent "$FFI_CHAT_API" 'SenderIngressPolicyV1|apply_sender_policy' \
  "capability inbox cannot own a sender policy bypass"
require_present "$HIVRA_BINDINGS" 'hivra_set_application_storage_root' \
  "Flutter initializes the canonical native application storage root"
require_present "$CAPSULE_PERSISTENCE" 'deleteInboundQuarantine' \
  "Capsule deletion includes native quarantine lifecycle cleanup"
require_present "$NOSTR_TRANSPORT" 'pending_receive_batch: Mutex<Option<PendingReceiveBatch>>' \
  "Nostr adapter retains one unresolved ingress batch"
require_present "$NOSTR_TRANSPORT" 'pub fn resolve_receive_batch\(' \
  "Nostr adapter exposes one resolve-once batch acknowledgement"
require_absent "$NOSTR_TRANSPORT" 'advance_receive_cursor_for_relay' \
  "relay fetch cannot advance a cursor before ingress resolution"
require_present "$NOSTR_TRANSPORT" 'Err\(TransportError::NotImplemented\)' \
  "legacy aggregate Nostr receive route is sealed"
require_present "$FFI_INVITATION_API" 'InboundDeliveryResolution' \
  "canonical FFI ingress returns per-event dispositions"
require_present "$FFI_INVITATION_API" 'resolve_receive_batch' \
  "canonical FFI ingress resolves the fetched batch"
require_present "$FFI_TRANSPORT_CACHE" 'with_current_nostr_transport' \
  "batch resolution cannot rebuild away pending session state"
require_absent "$FFI_CHAT_API" 'messages\.drain\(0\.\.overflow\)' \
  "full chat inbox cannot silently evict an unconsumed envelope"
require_absent "$FFI_ATTESTATION_API" 'messages\.drain\(0\.\.overflow\)' \
  "full attestation inbox cannot silently evict an unconsumed envelope"
require_present "$FFI_CHAT_API" 'return InboundRouteResult::Retry;' \
  "full chat inbox applies retry backpressure"
require_present "$FFI_ATTESTATION_API" 'return InboundRouteResult::Retry;' \
  "full attestation inbox applies retry backpressure"
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
require_absent "$WASM_PLUGINS_SCREEN" 'MoltbookAmbassadorConfiguration' \
  "generic plugins screen does not own Moltbook profile configuration"
require_present "$MOLTBOOK_AMBASSADOR_SCREEN" '^class MoltbookAmbassadorScreen ' \
  "Moltbook profile uses a dedicated workspace"
require_present "$MOLTBOOK_PROVIDER_ADAPTER" "https://www\\.moltbook\\.com/api/v1/" \
  "Moltbook adapter pins the official HTTPS API origin"
require_present "$MOLTBOOK_PROVIDER_ADAPTER" "followRedirects = false" \
  "Moltbook adapter rejects redirects before credential forwarding"
require_present "$MOLTBOOK_PROVIDER_ADAPTER" "maxResponseBytes = 256 \\* 1024" \
  "Moltbook adapter bounds provider responses"
require_present "$MOLTBOOK_PROVIDER_ADAPTER" "Moltbook transport only permits GET and POST" \
  "Moltbook adapter restricts methods to the reviewed read and publication set"
require_absent "$MOLTBOOK_AMBASSADOR_SCREEN" "moltbook_provider_adapter|CapsuleScopedSecretVault" \
  "Moltbook screen cannot call provider or secure storage directly"
require_absent "$MOLTBOOK_AMBASSADOR_SCREEN" "InferenceProviderAdapter|AiDoctorCredentialStore" \
  "Moltbook screen cannot call inference provider or credential store directly"
require_absent "$MOLTBOOK_AMBASSADOR_SCREEN" "PluginHostApiService|executeWithRuntimeHook" \
  "Moltbook screen cannot call the plugin host directly"
require_absent "$MOLTBOOK_PUBLIC_BULLETIN_AI" "import .*ledger|import .*repository|MoltbookProvider|ExternalEffect|CapsuleFileStore|dart:io" \
  "Moltbook public-facts AI has no private truth, repository, provider, effect, or filesystem dependency"
require_present "$MOLTBOOK_PUBLIC_BULLETIN_AI" "content_only_from_source_notes_and_canonical_anchor.*true" \
  "Moltbook public-bulletin AI is constrained to explicit source notes and canonical anchor"
require_present "$MOLTBOOK_PUBLIC_BULLETIN_AI" "canonicalProductAnchor" \
  "Moltbook public-bulletin AI carries the Capsule-first product anchor"
require_present "$MOLTBOOK_AMBASSADOR_MODELS" "relationship-first\\|concept system" \
  "Moltbook public-bulletin validation rejects contradictory positioning"
require_present "$MOLTBOOK_AMBASSADOR_MODELS" '_unsafePublicTextControls' \
  "Moltbook AI proposals reject hidden text controls"
require_present "$MOLTBOOK_EFFECT_ADAPTER" 'payload contains unsupported fields' \
  "Moltbook external effects reject unknown envelope fields"
require_present "$PLUGIN_CONTRACT_IDS" 'authorize_moltbook_delegated_reply' \
  "Moltbook bounded delegation has an explicit plugin method"
require_present "$PLUGIN_HOST_API_DOC" 'authorize_moltbook_delegated_reply' \
  "host API documents Moltbook bounded delegation method"
require_present "$PLUGIN_CONTRACT_HANDLERS" 'content\.reply\.delegate' \
  "Moltbook delegated reply requires its own WASM capability"
require_present "$PLUGIN_CONTRACT_HANDLERS" 'moltbook_ambassador_delegated_reply_authorization' \
  "Moltbook host validates delegated authorization contract kind"
require_present "$MOLTBOOK_PUBLICATION" 'validateDelegatedReplyBinding' \
  "Moltbook delegated approval binds the exact canonical reply effect"
require_present "$PLUGIN_RUNTIME_MODULE" 'maxDailyWrites = 3' \
  "Moltbook delegated replies have a conservative daily budget"
require_present "$PLUGIN_RUNTIME_MODULE" 'minIntervalMinutes = 30' \
  "Moltbook delegated replies have a conservative minimum interval"
require_present "$MOLTBOOK_PUBLIC_BULLETIN_AI" "natural_non_repetitive_prose.*true" \
  "Moltbook public-bulletin AI requests bounded natural prose"
require_present "$MOLTBOOK_PUBLIC_BULLETIN_AI" "human_review_required.*true" \
  "Moltbook public-bulletin AI requires human review"
require_present "$PLUGIN_RUNTIME_MODULE" "Future<MoltbookDraftPreview> prepareMoltbookDraft" \
  "Moltbook draft preview is mounted through the plugin runtime module"
require_present "$PLUGIN_RUNTIME_MODULE" "method: prepareMoltbookDraftMethod" \
  "Moltbook draft preview executes the canonical WASM contract method"
require_present "$PLUGIN_RUNTIME_MODULE" "preview\\.body != reviewedBody\\.trim\\(\\)" \
  "Moltbook host rejects plugins that do not preserve reviewed prose"
require_present "$PLUGIN_RUNTIME_MODULE" "moltbookDrafts\\.save\\(preview\\)" \
  "validated Moltbook drafts enter one local store"
require_present "$MOLTBOOK_DRAFT_STORE" "writePluginState" \
  "Moltbook draft history uses Capsule-scoped plugin state"
require_absent "$MOLTBOOK_DRAFT_STORE" "ledger|ExternalEffect|MoltbookProviderAdapter" \
  "Moltbook local drafts do not become ledger, remote effects, or provider calls"
require_present "$MOLTBOOK_AMBASSADOR_SCREEN" "Approve permanent publication" \
  "Moltbook workspace requires exact human publication approval"
require_present "$MOLTBOOK_PUBLICATION" "approval_kind.*permanent_publication" \
  "Moltbook approval evidence binds the public permanence decision"
require_present "$MOLTBOOK_EFFECT_ADAPTER" "automatic resubmission is blocked" \
  "Moltbook reconciliation cannot blindly duplicate an ambiguous post"
require_present "$MOLTBOOK_EFFECT_ADAPTER" "request\\.ownerCapsuleHex" \
  "Moltbook credential lookup is bound to the originating Capsule"
require_absent "$MOLTBOOK_EFFECT_ADAPTER" "AppRuntimeService|Ledger|Transport" \
  "Moltbook external effect adapter remains outside Core and transport"
require_present "$MOLTBOOK_CONNECTION" "_observer\\.observeAccount\\(normalizedKey\\)" \
  "Moltbook connection verifies a credential before storage"
require_present "$MOLTBOOK_CONNECTION" "_secretVault\\.replaceAccountSecret" \
  "Moltbook account rotation uses the generic secret vault"
require_absent "$MOLTBOOK_CONNECTION" "FlutterSecureStorage|dart:io" \
  "Moltbook connection owns no second credential store"
require_present "$MOLTBOOK_CONNECTION" "_secretVault\\.deleteAccount" \
  "Moltbook disconnect removes the account secret"
require_absent "$EXTERNAL_EFFECT_LIFECYCLE_DOC" "MoltbookHttp|MoltbookProvider" \
  "generic external-effect lifecycle contains no Moltbook DTO"
require_present "$CAPSULE_SECRET_LIFECYCLE_DOC" "single application owner" \
  "capsule-scoped secret lifecycle has one application owner"
require_absent "$CAPSULE_SECRET_VAULT" "dart:io|File\\(|Directory\\(" \
  "capsule-scoped secret vault has no plaintext filesystem fallback"
require_present "$CAPSULE_PERSISTENCE" "_secretVault\\.deleteCapsules\\(keysToDelete\\)" \
  "Capsule deletion cleans every Capsule-scoped plugin secret"
require_present "$PLUGIN_RUNTIME_MODULE" "_secretVault\\.deletePlugin\\(pluginId\\)" \
  "plugin removal cleans its secrets across Capsules"
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
  pass "legacy pairwise service removed; checking Core PairView adapter instead"
  require_absent "$CONSENSUS" 'String _kindLabel\(' \
    "consensus processor does not declare local kindLabel dictionary"
  require_present "$CONSENSUS" 'hivra\.pair_view' \
    "consensus processor consumes the versioned Core PairView"
  require_absent "$CONSENSUS" "event\['kind'\]" \
    "consensus processor does not inspect raw ledger event kinds"
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
require_present "$SERVICES/wasm_plugin_registry_service.dart" '_dedupeByPluginId' \
  "plugin registry keeps one active package per plugin id"

# 9) Ledger-derived slot projection contract: no legacy per-slot FFI probes in Flutter.
require_absent "$BINDINGS" 'starterExists|getStarterId|getStarterType' \
  "flutter bindings do not expose legacy per-slot starter probes"
require_absent "$BINDINGS" 'hivra_starter_get_id|hivra_starter_get_type|hivra_starter_exists' \
  "flutter bindings do not bind legacy starter FFI symbols"
require_present "$LEDGER_VIEW" '_starterIdsFromCapsuleState\(capsuleState\)' \
  "ledger view consumes Core-owned starter slot projection"
require_present "$LEDGER_VIEW" 'stateVersion == events\.length' \
  "ledger view requires a version-matched Core projection"
require_absent "$LEDGER_VIEW" '_starterIdsFromLedger|StarterBurned.*StarterCreated|StarterCreated.*StarterBurned' \
  "ledger view does not mirror starter lifecycle transitions"
require_present "$LEDGER_SUMMARY" '_starterCountFromCoreProjection' \
  "capsule selector consumes Core-owned starter slot projection"
require_absent "$LEDGER_SUMMARY" '_parseStarterCreated|_parseStarterBurnedId|activeStartersById' \
  "capsule selector does not mirror starter lifecycle transitions"

# 10) Moltbook automatic evolution must preserve one target lifecycle.
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" '^# Moltbook Engagement Lifecycle v1$' \
  "Moltbook canonical engagement lifecycle exists"
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" 'engagement_id' \
  "Moltbook lifecycle defines canonical engagement identity"
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" 'zero or one non-terminal engagement' \
  "Moltbook lifecycle forbids parallel active target engagements"
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" 'on_demand.*session.*continuous_while_running|`on_demand`|`continuous_while_running`' \
  "Moltbook trigger modes share one lifecycle contract"
require_present "$ROOT/docs/plugins/moltbook_agent_drone_design_v1.md" 'moltbook_engagement_lifecycle_v1\.md' \
  "Moltbook design references canonical engagement lifecycle"
require_present "$ROADMAP" 'moltbook_engagement_lifecycle_v1\.md' \
  "roadmap tracks canonical Moltbook engagement remediation"
require_present "$MOLTBOOK_PUBLICATION" 'String replyEngagementId\(' \
  "Moltbook publication owner derives canonical engagement identity"
require_present "$MOLTBOOK_PUBLICATION" "'engagement_id': engagementId" \
  "Moltbook reply payload binds the canonical engagement identity"
require_present "$MOLTBOOK_PUBLICATION" 'findReplyOperations\(' \
  "Moltbook publication owner projects targets from the effect journal"
require_present "$MOLTBOOK_PUBLICATION" 'conflicting active publication effects' \
  "Moltbook publication owner freezes legacy duplicate targets"
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" 'Single orchestration port \(implemented\)' \
  "Moltbook lifecycle records the implemented orchestration port"
require_present "$PLUGIN_RUNTIME_MODULE" 'Future<ExternalEffectOperation> advanceMoltbookEngagement\(' \
  "Moltbook runtime exposes one engagement orchestration port"
MOLTBOOK_ENGAGEMENT_ADVANCE_ROUTE_COUNT="$(
  rg -c 'advanceMoltbookEngagement' \
    "$MOLTBOOK_AMBASSADOR_SCREEN" || true
)"
if [ "${MOLTBOOK_ENGAGEMENT_ADVANCE_ROUTE_COUNT:-0}" -eq 2 ]; then
  pass "Moltbook release UI has one Assisted orchestration route"
else
  fail "Moltbook release UI has one Assisted orchestration route"
fi
require_absent "$MOLTBOOK_AMBASSADOR_SCREEN" 'prepareMoltbookReplyPublication|authorizeDelegatedMoltbookReply|approveDelegatedMoltbookReply' \
  "Moltbook screen has no parallel reply authorization or queue route"
require_absent "$MOLTBOOK_AMBASSADOR_SCREEN" 'MoltbookEngagementWritePolicy\.bounded|Bounded queue' \
  "Moltbook release UI does not expose Bounded publication before evidence"
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" 'Cycle engine \(implemented\)' \
  "Moltbook lifecycle records the implemented serialized cycle"
require_present "$PLUGIN_RUNTIME_MODULE" 'static final Map<String, Future<MoltbookCycleSummary>> _moltbookCycles' \
  "Moltbook runtime serializes cycles by Capsule and provider account"
require_present "$PLUGIN_RUNTIME_MODULE" 'Future<MoltbookCycleSummary> runMoltbookCycle\(' \
  "Moltbook runtime exposes one wake-run-sleep cycle port"
require_present "$PLUGIN_RUNTIME_MODULE" "operation.state == ExternalEffectState.unresolved" \
  "Moltbook cycle reconciles unresolved effects before new observation"
require_present "$PLUGIN_RUNTIME_MODULE" 'final heartbeat = await _observeAndPlanMoltbookHeartbeat\(' \
  "Moltbook cycle uses generation-bound deterministic heartbeat observation and planning"
require_present "$PLUGIN_RUNTIME_MODULE" "'sleep inspected=" \
  "Moltbook cycle publishes one bounded local summary"
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" 'Trigger policies \(implemented\)' \
  "Moltbook lifecycle records the implemented trigger policies"
require_present "$MOLTBOOK_AMBASSADOR_MODELS" "triggerContinuous = 'continuous_while_running'" \
  "Moltbook configuration separates trigger policy from write policy"
require_present "$MOLTBOOK_CYCLE_TRIGGER" 'Future<MoltbookCycleSummary> runOnDemand\(' \
  "Moltbook trigger owner exposes on-demand execution"
require_present "$MOLTBOOK_CYCLE_TRIGGER" 'Future<MoltbookCycleSummary\?> startSession\(' \
  "Moltbook trigger owner exposes once-per-session execution"
require_present "$MOLTBOOK_CYCLE_TRIGGER" 'Future<MoltbookCycleSummary> startContinuous\(' \
  "Moltbook trigger owner exposes sequential continuous execution"
require_present "$MOLTBOOK_CYCLE_TRIGGER" 'void stopAll\(\)' \
  "Moltbook trigger owner exposes an immediate scheduling stop"
require_absent "$MOLTBOOK_CYCLE_TRIGGER" 'moltbook_provider_adapter|moltbook_external_effect_adapter|plugin_host_api_service' \
  "Moltbook trigger owner depends only on the canonical cycle callback"
require_present "$PLUGIN_RUNTIME_MODULE" 'Future<MoltbookCycleSummary\?> startConfiguredMoltbookCycles\(' \
  "Moltbook runtime maps persisted trigger policy to one controller"
require_present "$PLUGIN_RUNTIME_MODULE" 'Future<void> stopMoltbookCyclesAndDisable\(' \
  "Moltbook runtime exposes one persistent kill-switch route"
require_present "$MOLTBOOK_AMBASSADOR_SCREEN" 'runMoltbookOnDemandCycle\(\)' \
  "Moltbook manual cycle uses the canonical cycle port"
require_present "$MOLTBOOK_AMBASSADOR_SCREEN" 'onStop: _saving \? null : _stopCycles' \
  "Moltbook Stop remains available while cycle work is in flight"
require_absent "$MOLTBOOK_AMBASSADOR_SCREEN" 'planMoltbookHeartbeat\(\)' \
  "Moltbook screen has no legacy direct heartbeat planning route"
require_present "$MOLTBOOK_ENGAGEMENT_LIFECYCLE_DOC" 'UI projection \(implemented\)' \
  "Moltbook lifecycle records the implemented workspace projection"
require_present "$MOLTBOOK_AMBASSADOR_MODELS" 'class MoltbookWorkspaceProjection' \
  "Moltbook workspace has one canonical UI projection"
require_present "$MOLTBOOK_AMBASSADOR_SCREEN" 'MoltbookWorkspaceProjection\.resolve\(' \
  "Moltbook screen derives actions and summary from the canonical projection"
require_present "$MOLTBOOK_AMBASSADOR_SCREEN" 'Technical account controls' \
  "Moltbook manual provider controls remain secondary"
require_present "$MOLTBOOK_AMBASSADOR_SCREEN" 'Technical cycle details' \
  "Moltbook raw cycle evidence remains secondary"

# 11) Transport receive surfaces share one capsule-scoped health policy.
require_present "$TRANSPORT_HEALTH_POLICY" 'class TransportHealthSnapshot' \
  "transport health policy owns the capsule-scoped diagnostic snapshot"
require_present "$INV_INTENT" '_transportHealth\.canRun\(' \
  "invitation and relationship receive use shared transport health policy"
require_present "$CAPSULE_CHAT_DELIVERY" '_transportHealth\.canRun\(' \
  "chat and trading receive use shared transport health policy"
require_present "$ATTESTATION_SYNC" '_transportHealth\.canRun\(' \
  "pair attestation receive uses shared transport health policy"
require_present "$MAIN_SCREEN" '_invitationIntents\.fetchInvitations\(' \
  "relationship refresh reuses the canonical domain receive service"
require_absent "$MAIN_SCREEN" 'RelationshipTransport|relationshipReceiveWorker' \
  "relationship refresh has no second transport route"
require_present "$TRANSPORT_HEALTH_CHECKLIST" 'one-attempt manual retry' \
  "transport health checklist records bounded explicit retry semantics"

exit "$STATUS"
