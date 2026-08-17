#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKLIST="$ROOT/docs/checklists/trading-drone-spec-runtime-parity.md"
PUBLIC_SNAPSHOT="$ROOT/flutter/lib/services/bingx_futures_live_snapshot_builder_service.dart"
PUBLIC_STRATEGY="$ROOT/flutter/lib/services/bingx_futures_live_strategy_use_case_service.dart"
SHADOW_PROBE="$ROOT/flutter/tool/trading_remote_shadow_probe.dart"
SHADOW_STREAM="$ROOT/flutter/lib/services/bingx_futures_shadow_stream_store.dart"
EXECUTION_USE_CASE="$ROOT/flutter/lib/services/bingx_futures_exchange_execution_use_case_service.dart"
TRADING_CYCLE="$ROOT/flutter/lib/services/bingx_futures_trading_cycle_use_case_service.dart"
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

shadow_probe_is_bounded_scheduler() {
  local cycle_line
  local delay_line
  cycle_line="$(rg -n 'await runOnce\(cycleNumber\);' "$1" | head -1 | cut -d: -f1)"
  delay_line="$(rg -n 'await delay\(interval!\);' "$1" | head -1 | cut -d: -f1)"
  rg -q 'const int maxScheduledRuns = 288;' "$1" &&
    rg -q 'const int minScheduleIntervalSeconds = 60;' "$1" &&
    rg -q 'const int maxScheduleIntervalSeconds = 3600;' "$1" &&
    rg -q "'run-count'" "$1" &&
    rg -q "'interval-seconds'" "$1" &&
    rg -q 'runCount < 1 \|\| runCount > maxScheduledRuns' "$1" &&
    rg -q 'runCount > 1 && interval == null' "$1" &&
    [ -n "$cycle_line" ] &&
    [ -n "$delay_line" ] &&
    [ "$cycle_line" -lt "$delay_line" ] &&
    ! rg -q 'Timer\.periodic|while \(true\)|scheduleAtFixedRate|retry' "$1"
}

shadow_stream_is_durable() {
  local unexpected_deletes
  local checkpoint_commit_line
  local checkpoint_cleanup_line
  unexpected_deletes="$(rg -n '\.delete\(' "$1" | rg -v '(interrupted|pending)\.delete\(|await entry\.delete\(\);' || true)"
  checkpoint_commit_line="$(rg -n 'await _commitCheckpoint\(checkpoint\);' "$1" | cut -d: -f1)"
  checkpoint_cleanup_line="$(rg -n 'await _deleteCheckpointedEvidence\(checkpoint\);' "$1" | head -1 | cut -d: -f1)"
  rg -q 'static const int maxEntries = 256;' "$1" &&
    rg -q 'static const int _lockAttemptLimit = 100;' "$1" &&
    rg -q "_pendingDirectoryName = 'pending'" "$1" &&
    rg -q "_pendingIdentityFileName =" "$1" &&
    rg -q 'FileLock\.exclusive' "$1" &&
    rg -q 'pending\.writeAsString\(encoded, flush: true\)' "$1" &&
    rg -q 'pending\.rename\(identity\.path\)' "$1" &&
    rg -q '_requireEmptyUnboundStream' "$1" &&
    rg -q 'ambiguous shadow stream identity state' "$1" &&
    rg -q 'pending\.create\(exclusive: true\)' "$1" &&
    rg -q 'pending\.writeAsBytes\(evidence\.wireBytes, flush: true\)' "$1" &&
    rg -q 'pending\.rename\(committed\.path\)' "$1" &&
    rg -q "_checkpointFileName = 'stream_checkpoint.v1.json'" "$1" &&
    rg -q 'evidence\.sequence % maxEntries != 0' "$1" &&
    rg -q 'shadow checkpoint overlap conflict' "$1" &&
    rg -q 'await pending\.writeAsBytes\(checkpoint\.wireBytes, flush: true\)' "$1" &&
    rg -q 'await pending\.rename\(committed\.path\)' "$1" &&
    [ -n "$checkpoint_commit_line" ] &&
    [ -n "$checkpoint_cleanup_line" ] &&
    [ "$checkpoint_commit_line" -lt "$checkpoint_cleanup_line" ] &&
    rg -q 'authenticateShadowEvidence' "$1" &&
    [ -z "$unexpected_deletes" ]
}

execution_outcome_is_truthful() {
  rg -q 'final executionSucceeded = queued\.execution\.isSuccess;' "$1" &&
    rg -q 'BingxFuturesExchangeExecutionUseCaseStatus\.executionFailed' "$1" &&
    rg -q "errorCode: executionSucceeded \? null : 'exchange_effect_failed'" "$1" &&
    rg -q 'execution\.queuedExecution\?\.execution\.isSuccess == true' "$2"
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

if shadow_probe_is_bounded_scheduler "$SHADOW_PROBE"; then
  pass "live shadow probe scheduler is bounded, serial, and retry-free"
else
  fail "live shadow probe scheduler lost bounded cadence or serial execution"
fi

if rg -q "BingxFuturesShadowStreamStore" "$SHADOW_PROBE" &&
  rg -q "'stream-dir'" "$SHADOW_PROBE" &&
  ! rg -q "'output'" "$SHADOW_PROBE" &&
  shadow_stream_is_durable "$SHADOW_STREAM" &&
  ! shadow_probe_has_authority "$SHADOW_STREAM"; then
  pass "shadow stream is authenticated, bounded, checkpointed, and authority-free"
else
  fail "shadow stream lost restart, retention, or authority boundaries"
fi

if execution_outcome_is_truthful "$EXECUTION_USE_CASE" "$TRADING_CYCLE"; then
  pass "executed outcome requires explicit provider success"
else
  fail "execution owner or cycle can report success without provider success"
fi

PUBLIC_MUTATION="$(mktemp)"
PROBE_MUTATION="$(mktemp)"
STREAM_MUTATION="$(mktemp)"
CHECKPOINT_MUTATION="$(mktemp)"
SCHEDULER_MUTATION="$(mktemp)"
EXECUTION_MUTATION="$(mktemp)"
CYCLE_MUTATION="$(mktemp)"
trap 'rm -f "$PUBLIC_MUTATION" "$PROBE_MUTATION" "$STREAM_MUTATION" "$CHECKPOINT_MUTATION" "$SCHEDULER_MUTATION" "$EXECUTION_MUTATION" "$CYCLE_MUTATION"' EXIT
cp "$PUBLIC_SNAPSHOT" "$PUBLIC_MUTATION"
cp "$SHADOW_PROBE" "$PROBE_MUTATION"
printf '\nBingxFuturesApiCredentials\n' >> "$PUBLIC_MUTATION"
printf '\nplaceOrder\n' >> "$PROBE_MUTATION"
sed -e 's/static const int _lockAttemptLimit = 100;/static const int _lockAttemptLimit = 0;/' \
  -e 's/await pending\.rename(identity\.path);/await identity.writeAsString(encoded, flush: true);/' \
  "$SHADOW_STREAM" > "$STREAM_MUTATION"
printf '\nvoid deleteEvidence(File committed) => committed.delete();\n' >> "$STREAM_MUTATION"
sed 's/await _commitCheckpoint(checkpoint);/await Future<void>.value();/' \
  "$SHADOW_STREAM" > "$CHECKPOINT_MUTATION"
sed 's/await runOnce(cycleNumber);/await Future<void>.value();/' \
  "$SHADOW_PROBE" > "$SCHEDULER_MUTATION"
sed 's/final executionSucceeded = queued\.execution\.isSuccess;/final executionSucceeded = true;/' \
  "$EXECUTION_USE_CASE" > "$EXECUTION_MUTATION"
sed 's/execution\.queuedExecution?\.execution\.isSuccess == true/true/' \
  "$TRADING_CYCLE" > "$CYCLE_MUTATION"
if public_pipeline_has_authority "$PUBLIC_MUTATION" && \
  shadow_probe_has_authority "$PROBE_MUTATION" && \
  ! shadow_probe_is_bounded_scheduler "$SCHEDULER_MUTATION" && \
  ! shadow_stream_is_durable "$STREAM_MUTATION" && \
  ! shadow_stream_is_durable "$CHECKPOINT_MUTATION" && \
  ! execution_outcome_is_truthful "$EXECUTION_MUTATION" "$CYCLE_MUTATION"; then
  pass "public-only, scheduler, durable-stream, and execution-outcome mutations are rejected"
else
  fail "public-only, scheduler, durable-stream, or execution-outcome mutation self-test failed"
fi

exit "$STATUS"
