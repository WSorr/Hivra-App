#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS security: %s\n' "$1"
}

warn() {
  printf 'WARN security: %s\n' "$1"
}

fail() {
  printf 'FAIL security: %s\n' "$1"
  STATUS=1
}

if git -C "$ROOT" ls-files | rg -q '(^|/)(dist/|.*\.dmg$|.*\.zip$|SHA256SUMS\.txt$)'; then
  fail "release artifacts are tracked in git"
else
  pass "release artifacts are not tracked in git"
fi

if git -C "$ROOT" ls-files | rg -q '(^|/)(ledger\.json|capsule_state\.json|capsules_index\.json|capsule_seeds\.json|capsule-backup.*\.json|hivra-ledger-.*\.json)$'; then
  fail "local backups or ledger exports are tracked in git"
else
  pass "local backups and ledger exports are not tracked in git"
fi

if rg -n '(BEGIN (RSA|EC|OPENSSH|PRIVATE KEY)|ghp_|github_pat_|AKIA|sk_live|pk_live|xoxb-|nsec1)' \
  "$ROOT" \
  --glob '!tools/review/**' \
  --glob '!dist/**' \
  --glob '!target/**' \
  --glob '!flutter/build/**' >/dev/null; then
  fail "secret-like tokens or private key material detected in repository content"
else
  pass "no obvious secret-like tokens detected in repository content"
fi

DART_LOG_PATTERN='(print|debugPrint)\s*\([^)]*(seed|mnemonic|secret|private\s*key|nsec|npub)'
RUST_LOG_PATTERN='eprintln!\s*\([^)]*(seed|mnemonic|secret|private\s*key|nsec|npub)'

SENSITIVE_MATCHES="$(
  {
    rg -n --pcre2 -i "$DART_LOG_PATTERN" "$ROOT/flutter/lib" "$ROOT/flutter/bin" 2>/dev/null || true
    rg -n --pcre2 -i "$RUST_LOG_PATTERN" "$ROOT/platform" "$ROOT/core" 2>/dev/null || true
  } | sed '/^$/d'
)"

if [ -n "$SENSITIVE_MATCHES" ]; then
  warn "possible sensitive logging patterns detected"
  printf '%s\n' "$SENSITIVE_MATCHES"
else
  pass "no obvious sensitive logging patterns detected"
fi

PLUGIN_HOST="$ROOT/flutter/lib/services/plugin_host_api_service.dart"
PLUGIN_PREFLIGHT="$ROOT/flutter/lib/services/wasm_plugin_package_preflight_service.dart"
PLUGIN_SOURCE_CATALOG="$ROOT/flutter/lib/services/wasm_plugin_source_catalog_service.dart"
PLUGIN_SOURCE_CATALOG_TEST="$ROOT/flutter/test/wasm_plugin_source_catalog_service_test.dart"
WASM_RUNTIME="$ROOT/platform/hivra-wasm-runtime/src/lib.rs"
CREDENTIAL_STORE="$ROOT/flutter/lib/services/bingx_futures_credential_store.dart"
SEED_STORE="$ROOT/flutter/lib/services/capsule_seed_store.dart"
if rg -q 'legacy installed records|Backward-compatible for legacy registry' \
  "$PLUGIN_HOST"; then
  fail "external plugin permissions contain a legacy fail-open bypass"
else
  pass "external plugin permissions have no legacy fail-open bypass"
fi
if rg -q 'Runtime contract kind is missing' "$PLUGIN_HOST" &&
   rg -q 'Runtime capabilities are missing required grants' "$PLUGIN_HOST" &&
   rg -q 'must declare at least one capability' "$PLUGIN_PREFLIGHT"; then
  pass "external plugin contract and capabilities fail closed"
else
  fail "external plugin contract and capabilities are not enforced fail closed"
fi
if rg -q "hivra_host_abi_v2" "$PLUGIN_PREFLIGHT" &&
   rg -q "consume_fuel\\(true\\)" "$WASM_RUNTIME" &&
   rg -q "ImportsNotAllowed" "$WASM_RUNTIME" &&
   rg -q "MAX_OUTPUT_BYTES" "$WASM_RUNTIME" &&
   rg -q "MAX_LINEAR_MEMORY_BYTES" "$WASM_RUNTIME"; then
  pass "semantic WASM runtime is ABI-pinned, import-free, fuel-bounded and size-bounded"
else
  fail "semantic WASM runtime safety boundaries are incomplete"
fi
if rg -q 'defaultTrustedRemoteCatalogSha256Hexes' "$PLUGIN_SOURCE_CATALOG" &&
   rg -q '_verifyRemoteCatalogDigest' "$PLUGIN_SOURCE_CATALOG" &&
   rg -q 'fetchCatalog rejects remote catalog when digest is not pinned' "$PLUGIN_SOURCE_CATALOG_TEST" &&
   rg -q 'fetchCatalog rejects remote catalog without any trusted digest pin' "$PLUGIN_SOURCE_CATALOG_TEST"; then
  pass "remote plugin catalog is pinned independently from package checksums"
else
  fail "remote plugin catalog lacks independent trust pinning"
fi

if rg -q '_writeScopeFallback|api_secret.*writeAsString|apiSecret.*writeAsString' \
  "$CREDENTIAL_STORE"; then
  fail "BingX credentials can be written to plaintext file storage"
else
  pass "BingX credentials are secure-storage only"
fi

if rg -q '_writeSeedFallback|encodedSeed.*writeAsString' "$SEED_STORE"; then
  fail "capsule recovery seed can be written to plaintext file storage"
else
  pass "capsule recovery seed is secure-storage only"
fi

exit "$STATUS"
