#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKLIST="$ROOT/docs/checklists/trading-drone-spec-runtime-parity.md"
PUBLIC_SNAPSHOT="$ROOT/flutter/lib/services/bingx_futures_live_snapshot_builder_service.dart"
PUBLIC_STRATEGY="$ROOT/flutter/lib/services/bingx_futures_live_strategy_use_case_service.dart"
SHADOW_PROBE="$ROOT/flutter/tool/trading_remote_shadow_probe.dart"
STATUS=0

pass() {
  printf 'PASS trading-drone-parity: %s\n' "$1"
}

fail() {
  printf 'FAIL trading-drone-parity: %s\n' "$1"
  STATUS=1
}

public_pipeline_has_authority() {
  rg -q 'BingxFuturesApiCredentials|bingx_futures_exchange_service\.dart' "$@"
}

shadow_probe_has_authority() {
  rg -q 'TradingDroneModuleService|BingxFuturesExchangeExecutionUseCaseService|BingxFuturesOrderTrackingStore|ExternalEffect|placeOrder|cancelOrder' "$1"
}

if [ ! -f "$CHECKLIST" ]; then
  fail "missing checklist: $CHECKLIST"
  exit "$STATUS"
fi

pass "checklist exists"

UNRESOLVED="$(awk -F'|' '
function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
BEGIN { in_table = 0; rows = 0; done_rows = 0 }
$0 ~ /^\| Area \| Status \| Runtime Evidence \| Remaining Debt \|$/ { in_table = 1; next }
in_table && $0 ~ /^\|---/ { next }
in_table && $0 !~ /^\|/ { in_table = 0; next }
in_table && $0 ~ /^\|/ {
  area = trim($2)
  status = trim($3)
  if (area == "" || status == "" || area == "Area" || status == "Status") next
  rows += 1
  if (status == "DONE") done_rows += 1
  if (status != "DONE") {
    print area " [" status "]"
  }
}
END {
  if (rows == 0) print "__NO_ROWS__"
  else if (done_rows == 0) print "__NO_DONE_ROWS__"
}
' "$CHECKLIST")"

if printf '%s\n' "$UNRESOLVED" | rg -q '^__NO_ROWS__$'; then
  fail "runtime status table is missing or unparsable"
elif printf '%s\n' "$UNRESOLVED" | rg -q '^__NO_DONE_ROWS__$'; then
  fail "runtime status table has no DONE rows"
elif [ -n "$UNRESOLVED" ]; then
  fail "runtime status table still has unresolved rows:"
  printf '%s\n' "$UNRESOLVED" | sed 's/^/  - /'
else
  pass "runtime status table contains DONE rows only"
fi

if python3 "$ROOT/tools/architecture/validate_trading_shadow_evidence_fixture.py"; then
  pass "shadow evidence cross-language fixture passes"
else
  fail "shadow evidence cross-language fixture failed"
fi

if public_pipeline_has_authority "$PUBLIC_SNAPSHOT" "$PUBLIC_STRATEGY"; then
  fail "public market pipeline regained credential or concrete exchange authority"
else
  pass "public market pipeline depends only on the public-data port"
fi

if shadow_probe_has_authority "$SHADOW_PROBE"; then
  fail "live shadow probe imports or invokes local authority/effect owners"
else
  pass "live shadow probe has no local authority or effect owner"
fi

PUBLIC_MUTATION="$(mktemp)"
PROBE_MUTATION="$(mktemp)"
trap 'rm -f "$PUBLIC_MUTATION" "$PROBE_MUTATION"' EXIT
cp "$PUBLIC_SNAPSHOT" "$PUBLIC_MUTATION"
cp "$SHADOW_PROBE" "$PROBE_MUTATION"
printf '\nBingxFuturesApiCredentials\n' >> "$PUBLIC_MUTATION"
printf '\nplaceOrder\n' >> "$PROBE_MUTATION"
if public_pipeline_has_authority "$PUBLIC_MUTATION" && \
  shadow_probe_has_authority "$PROBE_MUTATION"; then
  pass "public-only boundary negative mutations are rejected"
else
  fail "public-only boundary negative mutation self-test failed"
fi

exit "$STATUS"
