#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKLIST="$ROOT/docs/checklists/trading-drone-spec-runtime-parity.md"
PUBLIC_SNAPSHOT="$ROOT/flutter/lib/services/bingx_futures_live_snapshot_builder_service.dart"
PUBLIC_STRATEGY="$ROOT/flutter/lib/services/bingx_futures_live_strategy_use_case_service.dart"
SHADOW_PROBE="$ROOT/flutter/tool/trading_remote_shadow_probe.dart"
SHADOW_STREAM="$ROOT/flutter/lib/services/bingx_futures_shadow_stream_store.dart"
RUNNER_ARTIFACT="$ROOT/tools/trading/public_shadow_runner_artifact.sh"
RUNNER_PACKAGE="$ROOT/tools/trading/public_shadow_runner_package/pubspec.yaml"
RUNNER_PACKAGE_LOCK="$ROOT/tools/trading/public_shadow_runner_package/pubspec.lock"
RUNNER_SUPERVISOR="$ROOT/tools/trading/hivra-trading-public-shadow-runner.service"
CI_REPOSITORY_GATES="$ROOT/.github/workflows/release-gates.yml"
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

runner_artifact_is_verifiable() {
  [ -x "$1" ] &&
    rg -q 'SCHEMA_VERSION="hivra-trading-public-shadow-runner-bundle-v1"' "$1" &&
    rg -q 'AUTHORITY_PROFILE="public-market-shadow-only"' "$1" &&
    rg -q 'artifact packaging requires a completely clean worktree' "$1" &&
    rg -q 'build output must stay outside the repository' "$1" &&
    rg -q 'binary_sha256=' "$1" &&
    rg -q 'unit_sha256=' "$1" &&
    rg -q 'bundle_install_path=' "$1" &&
    rg -q 'unit_link_path=' "$1" &&
    rg -q 'dependency_lock_sha256=' "$1" &&
    rg -q 'dart pub get --enforce-lockfile' "$1" &&
    rg -q 'the only cross-build target is linux/x64' "$1" &&
    rg -q 'artifact binary does not match Linux x64 manifest' "$1" &&
    rg -q 'artifact binary SHA-256 mismatch' "$1" &&
    rg -q 'artifact unit does not match the canonical source' "$1" &&
    rg -q 'forbidden authenticated exchange authority markers' "$1" &&
    rg -q 'dart compile exe' "$1" &&
    rg -q '"tool/trading_remote_shadow_probe.dart"' "$1"
}

runner_bundle_install_is_fail_closed() {
  [ -x "$1" ] &&
    rg -q -- '--ephemeral-install-smoke <artifact-dir>' "$1" &&
    rg -q 'ephemeral install smoke requires root' "$1" &&
    rg -q 'another public-shadow install operation is active' "$1" &&
    rg -q '\[ ! -e "\$target" \] && \[ ! -L "\$target" \]' "$1" &&
    rg -q 'ephemeral install target already exists' "$1" &&
    rg -q 'systemd-creds encrypt --name=runner-seed' "$1" &&
    rg -q 'systemctl link "\$UNIT_INSTALL_PATH"' "$1" &&
    rg -q 'systemctl is-enabled "\$UNIT_NAME"' "$1" &&
    rg -q 'systemctl start "\$UNIT_NAME"' "$1" &&
    rg -q 'systemctl clean --what=state "\$UNIT_NAME"' "$1" &&
    rg -q 'ephemeral install cleanup retained:' "$1" &&
    rg -q 'exact unit installed, started, and removed without enablement' "$1" &&
    ! rg -q 'systemctl enable' "$1"
}

runner_package_is_pinned() {
  [ -f "$1" ] && [ -f "$2" ] &&
    rg -q '^  sdk: 3\.11\.0$' "$1" &&
    rg -q '^  crypto: 3\.0\.7$' "$1" &&
    rg -q '^  cryptography: 2\.9\.0$' "$1" &&
    rg -q '^    version: "3\.0\.7"$' "$2" &&
    rg -q '^    version: "2\.9\.0"$' "$2" &&
    rg -q '^  dart: "3\.11\.0"$' "$2"
}

runner_linux_smoke_is_fail_closed() {
  local build_line
  local review_line
  local clean_line
  build_line="$(rg -n 'name: Prove Linux x64 runner startup boundary' "$2" | cut -d: -f1)"
  review_line="$(rg -n 'name: Review gates' "$2" | cut -d: -f1)"
  clean_line="$(rg -n 'name: Verify review gates preserve clean checkout' "$2" | cut -d: -f1)"
  rg -q -- '--runtime-smoke <artifact-dir>' "$1" &&
    rg -q 'runtime smoke requires a Linux x64 artifact' "$1" &&
    rg -q 'runtime smoke requires a Linux x64 host' "$1" &&
    rg -q 'env -u HIVRA_SHADOW_RUNNER_SEED_HEX' "$1" &&
    rg -q 'runtime smoke did not reach the fail-closed probe boundary' "$1" &&
    rg -q 'dart-lang/setup-dart@65eb853c7ba17dde3be364c3d2858773e7144260' "$2" &&
    rg -q 'sdk: 3\.11\.0' "$2" &&
    rg -q 'public_shadow_runner_artifact\.sh --build "\$artifact" --target-os linux --target-arch x64' "$2" &&
    rg -q 'public_shadow_runner_artifact\.sh --runtime-smoke "\$artifact"' "$2" &&
    rg -q 'git status --porcelain' "$2" &&
    [ -n "$build_line" ] && [ -n "$review_line" ] && [ -n "$clean_line" ] &&
    [ "$build_line" -lt "$review_line" ] && [ "$review_line" -lt "$clean_line" ] &&
    ! rg -q 'upload-artifact' "$2"
}

runner_supervisor_is_fail_closed() {
  python3 - "$1" "$2" <<'PY'
import configparser
import pathlib
import shlex
import sys

unit_path, probe_path = sys.argv[1:]
parser = configparser.ConfigParser(interpolation=None, strict=True)
parser.optionxform = str
try:
    with open(unit_path, "r", encoding="utf-8") as handle:
        parser.read_file(handle)
except (OSError, configparser.Error):
    raise SystemExit(1)

if parser.sections() != ["Unit", "Service", "Install"]:
    raise SystemExit(1)
unit = parser["Unit"]
service = parser["Service"]
install = parser["Install"]
required_unit = {
    "Description": "Hivra Trading public-market shadow runner",
    "Documentation": "https://github.com/WSorr/Hivra-App",
    "Wants": "network-online.target",
    "After": "network-online.target",
    "StartLimitIntervalSec": "26h",
    "StartLimitBurst": "2",
}
required_service = {
    "Type": "exec",
    "DynamicUser": "yes",
    "StateDirectory": "hivra-trading-public-shadow",
    "StateDirectoryMode": "0700",
    "WorkingDirectory": "/var/lib/hivra-trading-public-shadow",
    "LoadCredentialEncrypted": "runner-seed:/etc/credstore.encrypted/hivra-trading-public-shadow.seed",
    "Restart": "on-success",
    "RestartSec": "60s",
    "RuntimeMaxSec": "25h",
    "TimeoutStartSec": "30s",
    "TimeoutStopSec": "30s",
    "KillMode": "mixed",
    "OOMPolicy": "stop",
    "MemoryMax": "128M",
    "MemorySwapMax": "0",
    "TasksMax": "16",
    "CPUWeight": "10",
    "IOWeight": "10",
    "Nice": "10",
    "UMask": "0077",
    "NoNewPrivileges": "yes",
    "PrivateTmp": "yes",
    "PrivateDevices": "yes",
    "ProtectSystem": "strict",
    "ProtectHome": "yes",
    "ProtectProc": "invisible",
    "ProcSubset": "pid",
    "ProtectKernelTunables": "yes",
    "ProtectKernelModules": "yes",
    "ProtectKernelLogs": "yes",
    "ProtectControlGroups": "yes",
    "ProtectClock": "yes",
    "ProtectHostname": "yes",
    "RestrictRealtime": "yes",
    "RestrictSUIDSGID": "yes",
    "RestrictNamespaces": "yes",
    "LockPersonality": "yes",
    "MemoryDenyWriteExecute": "yes",
    "CapabilityBoundingSet": "",
    "AmbientCapabilities": "",
    "SystemCallArchitectures": "native",
    "SystemCallFilter": "@system-service",
    "RestrictAddressFamilies": "AF_UNIX AF_INET AF_INET6",
    "SocketBindDeny": "any",
    "IPAccounting": "yes",
    "StandardOutput": "journal",
    "StandardError": "journal",
    "LogRateLimitIntervalSec": "1h",
    "LogRateLimitBurst": "400",
}
allowed_service = set(required_service) | {"ExecStartPre", "ExecStart"}
if set(unit) != set(required_unit) or set(service) != allowed_service:
    raise SystemExit(1)
if any(unit.get(key) != value for key, value in required_unit.items()):
    raise SystemExit(1)
if any(service.get(key) != value for key, value in required_service.items()):
    raise SystemExit(1)
if set(install) != {"WantedBy"} or install.get("WantedBy") != "multi-user.target":
    raise SystemExit(1)
if "Environment" in service or "EnvironmentFile" in service or "MemoryHigh" in service:
    raise SystemExit(1)

expected_binary = "/opt/hivra/trading-public-shadow/hivra-trading-public-shadow-runner"
if service.get("ExecStartPre") != f"/usr/bin/test -x {expected_binary}":
    raise SystemExit(1)
command = shlex.split(service.get("ExecStart", ""))
expected = [
    expected_binary,
    "--runner-seed-file", "%d/runner-seed",
    "--symbol", "BTC-USDT",
    "--runner-build-id", "systemd-public-shadow-v1",
    "--plugin-id", "hivra.bingx-futures-trading",
    "--plugin-version", "0.2.3",
    "--package-digest-hex", "2cb440885a2fa473971364fb26cce304d079d393832b2b5bed6fd95517e61889",
    "--host-abi", "wasm32-wasi-preview1",
    "--stream-dir", "/var/lib/hivra-trading-public-shadow/stream",
    "--run-count", "288",
    "--interval-seconds", "300",
]
if command != expected:
    raise SystemExit(1)

probe = pathlib.Path(probe_path).read_text(encoding="utf-8")
required_probe = [
    "'runner-seed-file'",
    "runner seed sources are ambiguous",
    "followLinks: false",
    "runnerSeedFilePermissionsAreSafe(seedFilePath, stat.mode)",
    "^/run/credentials/[A-Za-z0-9_.@-]+\\.service/runner-seed$",
    "permissions == 0x120",
]
if any(fragment not in probe for fragment in required_probe):
    raise SystemExit(1)
PY
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

if runner_artifact_is_verifiable "$RUNNER_ARTIFACT" &&
  runner_package_is_pinned "$RUNNER_PACKAGE" "$RUNNER_PACKAGE_LOCK" &&
  "$RUNNER_ARTIFACT" --self-test >/dev/null; then
  pass "standalone runner bundle binds pinned dependencies, binary, unit, target, paths, and public-only authority"
else
  fail "standalone runner bundle lost dependency, unit, target, path, provenance, or authority verification"
fi

if runner_bundle_install_is_fail_closed "$RUNNER_ARTIFACT"; then
  pass "runner bundle exact-unit smoke is collision-safe, encrypted, non-enabled, and self-cleaning"
else
  fail "runner bundle exact-unit smoke lost collision, credential, enablement, or cleanup safety"
fi

if runner_linux_smoke_is_fail_closed "$RUNNER_ARTIFACT" "$CI_REPOSITORY_GATES"; then
  pass "required CI builds and starts the verified Linux runner without authority or artifact publication"
else
  fail "required CI lost the fail-closed Linux runtime startup evidence"
fi

if runner_supervisor_is_fail_closed "$RUNNER_SUPERVISOR" "$SHADOW_PROBE"; then
  pass "public-shadow supervisor is resource-bounded, credential-file-only, and failure-stopping"
else
  fail "public-shadow supervisor lost resource, credential, or restart boundaries"
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
ARTIFACT_MUTATION="$(mktemp)"
RUNTIME_SMOKE_MUTATION="$(mktemp)"
CI_CLEAN_MUTATION="$(mktemp)"
EXECUTION_MUTATION="$(mktemp)"
CYCLE_MUTATION="$(mktemp)"
SUPERVISOR_RESTART_MUTATION="$(mktemp)"
SUPERVISOR_MEMORY_MUTATION="$(mktemp)"
SUPERVISOR_CREDENTIAL_MUTATION="$(mktemp)"
SUPERVISOR_LISTENER_MUTATION="$(mktemp)"
BUNDLE_UNIT_MUTATION="$(mktemp)"
BUNDLE_ENABLE_MUTATION="$(mktemp)"
BUNDLE_COLLISION_MUTATION="$(mktemp)"
BUNDLE_CLEANUP_MUTATION="$(mktemp)"
trap 'rm -f "$PUBLIC_MUTATION" "$PROBE_MUTATION" "$STREAM_MUTATION" "$CHECKPOINT_MUTATION" "$SCHEDULER_MUTATION" "$ARTIFACT_MUTATION" "$RUNTIME_SMOKE_MUTATION" "$CI_CLEAN_MUTATION" "$EXECUTION_MUTATION" "$CYCLE_MUTATION" "$SUPERVISOR_RESTART_MUTATION" "$SUPERVISOR_MEMORY_MUTATION" "$SUPERVISOR_CREDENTIAL_MUTATION" "$SUPERVISOR_LISTENER_MUTATION" "$BUNDLE_UNIT_MUTATION" "$BUNDLE_ENABLE_MUTATION" "$BUNDLE_COLLISION_MUTATION" "$BUNDLE_CLEANUP_MUTATION"' EXIT
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
sed 's/AUTHORITY_PROFILE="public-market-shadow-only"/AUTHORITY_PROFILE="full-exchange-authority"/' \
  "$RUNNER_ARTIFACT" > "$ARTIFACT_MUTATION"
sed 's/env -u HIVRA_SHADOW_RUNNER_SEED_HEX/env/' \
  "$RUNNER_ARTIFACT" > "$RUNTIME_SMOKE_MUTATION"
sed '/name: Verify review gates preserve clean checkout/,+6d' \
  "$CI_REPOSITORY_GATES" > "$CI_CLEAN_MUTATION"
sed 's/final executionSucceeded = queued\.execution\.isSuccess;/final executionSucceeded = true;/' \
  "$EXECUTION_USE_CASE" > "$EXECUTION_MUTATION"
sed 's/execution\.queuedExecution?\.execution\.isSuccess == true/true/' \
  "$TRADING_CYCLE" > "$CYCLE_MUTATION"
sed 's/^Restart=on-success$/Restart=always/' \
  "$RUNNER_SUPERVISOR" > "$SUPERVISOR_RESTART_MUTATION"
sed 's/^MemoryMax=128M$/MemoryMax=64M/' \
  "$RUNNER_SUPERVISOR" > "$SUPERVISOR_MEMORY_MUTATION"
sed 's#^LoadCredentialEncrypted=.*#Environment=HIVRA_SHADOW_RUNNER_SEED_HEX=unsafe#' \
  "$RUNNER_SUPERVISOR" > "$SUPERVISOR_CREDENTIAL_MUTATION"
sed '/^SocketBindDeny=any$/d' \
  "$RUNNER_SUPERVISOR" > "$SUPERVISOR_LISTENER_MUTATION"
sed '/artifact unit does not match the canonical source/d' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_UNIT_MUTATION"
sed 's/systemctl link "\$UNIT_INSTALL_PATH"/systemctl enable "\$UNIT_NAME"/' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_ENABLE_MUTATION"
sed 's/\[ ! -e "\$target" \] && \[ ! -L "\$target" \]/true/' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_COLLISION_MUTATION"
sed '/systemctl clean --what=state "\$UNIT_NAME"/d' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_CLEANUP_MUTATION"
if public_pipeline_has_authority "$PUBLIC_MUTATION" && \
  shadow_probe_has_authority "$PROBE_MUTATION" && \
  ! shadow_probe_is_bounded_scheduler "$SCHEDULER_MUTATION" && \
  ! runner_artifact_is_verifiable "$ARTIFACT_MUTATION" && \
  ! runner_linux_smoke_is_fail_closed "$RUNTIME_SMOKE_MUTATION" "$CI_REPOSITORY_GATES" && \
  ! runner_linux_smoke_is_fail_closed "$RUNNER_ARTIFACT" "$CI_CLEAN_MUTATION" && \
  ! shadow_stream_is_durable "$STREAM_MUTATION" && \
  ! shadow_stream_is_durable "$CHECKPOINT_MUTATION" && \
  ! execution_outcome_is_truthful "$EXECUTION_MUTATION" "$CYCLE_MUTATION" && \
  ! runner_supervisor_is_fail_closed "$SUPERVISOR_RESTART_MUTATION" "$SHADOW_PROBE" && \
  ! runner_supervisor_is_fail_closed "$SUPERVISOR_MEMORY_MUTATION" "$SHADOW_PROBE" && \
  ! runner_supervisor_is_fail_closed "$SUPERVISOR_CREDENTIAL_MUTATION" "$SHADOW_PROBE" && \
  ! runner_supervisor_is_fail_closed "$SUPERVISOR_LISTENER_MUTATION" "$SHADOW_PROBE" && \
  ! runner_artifact_is_verifiable "$BUNDLE_UNIT_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_ENABLE_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_COLLISION_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_CLEANUP_MUTATION"; then
  pass "public-only, scheduler, bundle, install, supervisor, durable-stream, and execution-outcome mutations are rejected"
else
  fail "public-only, scheduler, bundle, install, supervisor, durable-stream, or execution-outcome mutation self-test failed"
fi

exit "$STATUS"
