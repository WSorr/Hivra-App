#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS capsule-ai-runtime: %s\n' "$1"
}

fail() {
  printf 'FAIL capsule-ai-runtime: %s\n' "$1"
  STATUS=1
}

check_bounded_files() {
  local label="$1"
  local maximum="$2"
  local matches="$3"
  shift 3
  local allowed=("$@")
  local count
  local file
  local expected
  local accepted

  count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  if (( count <= maximum )); then
    pass "$label is non-increasing ($count/$maximum)"
  else
    fail "$label grew ($count/$maximum)"
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    accepted=0
    for expected in "${allowed[@]}"; do
      if [[ "$file" == "$expected" ]]; then
        accepted=1
        break
      fi
    done
    if [[ "$accepted" -ne 1 ]]; then
      fail "$label escaped the legacy boundary: $file"
    fi
  done <<< "$matches"
}

cd "$ROOT"

dispatch_files="$({
  rg -l \
    --glob '*.dart' \
    --glob '!inference_provider_adapter.dart' \
    --glob '!capsule_ai_runtime_service.dart' \
    'inferenceProviderAdapterFor|_adapterFactory\(|_providerAdapterFactory\(' \
    flutter/lib/services || true
} | sort -u)"

check_bounded_files \
  "legacy feature-owned provider dispatch" \
  0 \
  "$dispatch_files"

if rg -q 'inferenceProviderAdapterFor' \
  flutter/lib/services/capsule_ai_runtime_service.dart; then
  pass "Capsule AI Runtime owns canonical provider dispatch"
else
  fail "Capsule AI Runtime canonical provider dispatch is missing"
fi

adapter_import_files="$({
  rg -l \
    --glob '*.dart' \
    "import 'inference_provider_adapter\\.dart';" \
    flutter/lib/services || true
} | sort -u)"

check_bounded_files \
  "legacy direct inference-adapter imports" \
  3 \
  "$adapter_import_files" \
  flutter/lib/services/ai_doctor_credential_store.dart \
  flutter/lib/services/ai_doctor_provider_adapter.dart \
  flutter/lib/services/capsule_ai_runtime_service.dart

credential_reader_files="$({
  rg -l \
    --glob '*.dart' \
    --glob '!ai_doctor_credential_store.dart' \
    --glob '!capsule_ai_runtime_service.dart' \
    'loadApiKey\(|sessionApiKey\(|loadBaseUrl\(|sessionBaseUrl\(' \
    flutter/lib/services || true
} | sort -u)"

check_bounded_files \
  "legacy feature-owned credential reads" \
  0 \
  "$credential_reader_files"

if rg -q \
  "ai_doctor_credential_store\.dart|inference_provider_adapter\.dart|inferenceProviderAdapterFor|loadApiKey\(|sessionApiKey\(|loadBaseUrl\(|sessionBaseUrl\(" \
  flutter/lib/services/capsule_history_ai_advisor_service.dart; then
  fail "history advisor must remain behind Capsule AI Runtime"
else
  pass "history advisor remains behind Capsule AI Runtime"
fi

if rg -q \
  "ai_doctor_credential_store\.dart|inference_provider_adapter\.dart|InferenceProviderResponse|inferenceProviderAdapterFor|loadApiKey\(|sessionApiKey\(|loadBaseUrl\(|sessionBaseUrl\(" \
  flutter/lib/services/ai_doctor_chat_service.dart \
  flutter/lib/services/ai_doctor_prompt_service.dart; then
  fail "Capsule Analyst must remain behind Capsule AI Runtime"
else
  pass "Capsule Analyst remains behind Capsule AI Runtime"
fi

if rg -q \
  "ai_doctor_credential_store\.dart|inference_provider_adapter\.dart|inferenceProviderAdapterFor|loadApiKey\(|sessionApiKey\(|loadBaseUrl\(|sessionBaseUrl\(" \
  flutter/lib/services/ai_developer_engineer_service.dart; then
  fail "Developer Engineer must remain behind Capsule AI Runtime"
else
  pass "Developer Engineer remains behind Capsule AI Runtime"
fi

if rg -q \
  "ai_doctor_credential_store\.dart|inference_provider_adapter\.dart|InferenceProviderResponse|inferenceProviderAdapterFor|loadApiKey\(|sessionApiKey\(|loadBaseUrl\(|sessionBaseUrl\(" \
  flutter/lib/services/moltbook_public_bulletin_ai_service.dart; then
  fail "Moltbook AI must remain behind Capsule AI Runtime"
else
  pass "Moltbook AI remains behind Capsule AI Runtime"
fi

credential_import_files="$({
  rg -l \
    --glob '*.dart' \
    "import 'ai_doctor_credential_store\\.dart';" \
    flutter/lib/services || true
} | sort -u)"

check_bounded_files \
  "legacy direct credential-store imports" \
  3 \
  "$credential_import_files" \
  flutter/lib/services/ai_tooling_module_service.dart \
  flutter/lib/services/capsule_ai_runtime_service.dart \
  flutter/lib/services/plugin_runtime_module_service.dart

shared_lease_files="$({
  rg -l \
    --glob '*.dart' \
    'AiDoctorCredentialStore\.shared' \
    flutter/lib || true
} | sort -u)"

check_bounded_files \
  "legacy composition access to the shared credential lease" \
  2 \
  "$shared_lease_files" \
  flutter/lib/services/ai_tooling_module_service.dart \
  flutter/lib/services/plugin_runtime_module_service.dart

if rg -q \
  "ai_doctor_credential_store\.dart|inferenceProviderAdapterFor|loadApiKey\(|sessionApiKey\(|loadBaseUrl\(|sessionBaseUrl\(" \
  flutter/lib/screens flutter/lib/widgets; then
  fail "screens and widgets must not own AI credentials or provider dispatch"
else
  pass "screens and widgets have no AI credential or provider-dispatch path"
fi

if rg -q \
  "inference_provider_adapter\.dart|ai_doctor_credential_store\.dart" \
  core engine adapters platform; then
  fail "Core, Engine, adapters, and platform crates must not import Flutter AI runtime types"
else
  pass "Capsule AI Runtime remains outside Core, Engine, adapters, and platform crates"
fi

exit "$STATUS"
