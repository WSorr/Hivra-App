#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKLIST="$ROOT/docs/checklists/trading-drone-spec-runtime-parity.md"
PUBLIC_SNAPSHOT="$ROOT/flutter/lib/services/bingx_futures_live_snapshot_builder_service.dart"
PUBLIC_SESSION_ACCUMULATOR="$ROOT/flutter/lib/services/bingx_futures_public_session_accumulator.dart"
PUBLIC_SESSION_STREAM="$ROOT/flutter/lib/services/bingx_futures_public_session_stream_service.dart"
PUBLIC_STRATEGY="$ROOT/flutter/lib/services/bingx_futures_live_strategy_use_case_service.dart"
SHADOW_PROBE="$ROOT/flutter/tool/trading_remote_shadow_probe.dart"
EXACT_ORDER_PROBE="$ROOT/flutter/tool/trading_remote_exact_order.dart"
SHADOW_ANCHOR_VERIFIER="$ROOT/flutter/tool/verify_trading_shadow_anchor.dart"
SHADOW_EVIDENCE="$ROOT/flutter/lib/services/bingx_futures_deterministic_replay_harness_service.dart"
SHADOW_STREAM="$ROOT/flutter/lib/services/bingx_futures_shadow_stream_store.dart"
RUNNER_ARTIFACT="$ROOT/tools/trading/public_shadow_runner_artifact.sh"
RUNNER_PACKAGE="$ROOT/tools/trading/public_shadow_runner_package/pubspec.yaml"
RUNNER_PACKAGE_LOCK="$ROOT/tools/trading/public_shadow_runner_package/pubspec.lock"
RUNNER_SUPERVISOR="$ROOT/tools/trading/hivra-trading-public-shadow-runner.service"
CI_REPOSITORY_GATES="$ROOT/.github/workflows/release-gates.yml"
EXECUTION_USE_CASE="$ROOT/flutter/lib/services/bingx_futures_exchange_execution_use_case_service.dart"
TRADING_CYCLE="$ROOT/flutter/lib/services/bingx_futures_trading_cycle_use_case_service.dart"
TVH_RULE_ENGINE="$ROOT/flutter/lib/services/bingx_futures_tvh_rule_engine_service.dart"
LIVE_DECISION="$ROOT/flutter/lib/services/bingx_futures_live_decision_service.dart"
ZONE_DECISION="$ROOT/flutter/lib/services/bingx_futures_zone_decision_service.dart"
TVH_RULE_TEST="$ROOT/flutter/test/bingx_futures_tvh_rule_engine_service_test.dart"
ZONE_DECISION_TEST="$ROOT/flutter/test/bingx_futures_zone_decision_service_test.dart"
TRADING_CYCLE_TEST="$ROOT/flutter/test/bingx_futures_trading_cycle_use_case_service_test.dart"
TRADING_MODULE="$ROOT/flutter/lib/services/trading_drone_module_service.dart"
TRADING_MODELS="$ROOT/flutter/lib/models/bingx_futures_order_tracking_models.dart"
TRADING_SCREEN="$ROOT/flutter/lib/screens/trading_drone_screen.dart"
EXCHANGE_SERVICE="$ROOT/flutter/lib/services/bingx_futures_exchange_service.dart"
REMOTE_PROBE_TEST="$ROOT/flutter/test/trading_remote_shadow_probe_test.dart"
PUBLIC_SESSION_TEST="$ROOT/flutter/test/bingx_futures_public_session_accumulator_test.dart"
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

shadow_probe_exposes_runner_identity() {
  rg -Fq 'runner_key_id=${evidence.runnerKeyId}' "$1" &&
    rg -Fq 'runner_public_key_hex=${_encodeHex(publicKey.bytes)}' "$1"
}

shadow_probe_is_bounded_scheduler() {
  local cycle_line
  local delay_line
  cycle_line="$(rg -n 'await runOnce\(cycleNumber\);' "$1" | head -1 | cut -d: -f1)"
  delay_line="$(rg -n 'await delay\(interval!\);' "$1" | head -1 | cut -d: -f1)"
  rg -q 'const int maxScheduledRuns = 8928;' "$1" &&
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

public_session_stream_is_fail_closed() {
  rg -q 'class BingxFuturesPublicSessionAccumulator' "$1" &&
    rg -q '_latestBySession\.clear\(\);' "$1" &&
    rg -q 'maxMessageSilence = Duration\(seconds: 90\)' "$1" &&
    rg -q 'maxTradesPerMessage = 256' "$1" &&
    rg -q 'final trades = rows' "$1" &&
    rg -q "evidenceSource: 'public_trade_stream'" "$1" &&
    rg -q '!bucketStart\.isBefore\(connectedAt\)' "$1" &&
    ! rg -q 'dart:io|File\(|Directory\(|RandomAccessFile' "$1" &&
    rg -q 'wss://open-api-swap\.bingx\.com/swap-market' "$2" &&
    rg -q "message == 'Ping'" "$2" &&
    rg -q "send\('Pong'\)" "$2" &&
    rg -q 'accumulator\.markDisconnected\(\);' "$2" &&
    rg -q 'public trade frame expands beyond limit' "$2" &&
    rg -q 'coverage becomes complete only for buckets observed after connect' "$3" &&
    rg -q 'stale heartbeat and disconnect invalidate all coverage' "$3" &&
    rg -q 'bounded trade batch is validated before aggregate mutation' "$3"
}

local_session_stream_is_wired() {
  rg -q 'final BingxFuturesPublicSessionStreamService publicSessionStream;' "$1" &&
    rg -q 'publicSessionStream\.snapshotFor\(symbol\)' "$1" &&
    rg -q 'publicSessionStream\.ensureConnected\(normalized\)' "$2" &&
    rg -q 'publicSessionStream\.disconnect\(\)' "$2"
}

liquidity_sequence_is_canonical() {
  rg -q "final longReady = longTradeOk && normalizedRequiredSide != 'sell';" "$1" &&
    rg -q "final shortReady = shortTradeOk && normalizedRequiredSide != 'buy';" "$1" &&
    ! rg -q 'minAbsSessionImbalanceRatio|requireWhaleActivation' "$1" &&
    rg -q "'liquidation_proxy'" "$2" &&
    rg -q '_applyLiquidationConfluence' "$3" &&
    rg -q 'level\.weight \+ bonus' "$3" &&
    ! rg -q 'anchorSource = "liquidation_proxy"' "$3" &&
    rg -q "code: 'market_volume_activation_unavailable'" "$4" &&
    rg -q 'volume activation does not require trend or whale alignment' "$5" &&
    rg -q 'opposite trade flow cannot flip a constrained liquidity side' "$5" &&
    rg -q 'incomplete session evidence remains context, not authority' "$5" &&
    rg -q 'liquidation proxy ranks fresh structure without becoming anchor' "$6" &&
    rg -q 'projects the exact market blocker without preparing an effect' "$7"
}

runner_artifact_is_verifiable() {
  [ -x "$1" ] &&
    rg -q 'SCHEMA_VERSION="hivra-trading-public-shadow-runner-bundle-v1"' "$1" &&
    rg -q 'AUTHORITY_PROFILE="public-market-shadow-plus-single-use-account-read-and-exact-order"' "$1" &&
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
    rg -q 'unsupported host-native executable header' "$1" &&
    rg -q 'machine == 62' "$1" &&
    rg -q 'artifact binary SHA-256 mismatch' "$1" &&
    rg -q 'artifact unit does not match the canonical source' "$1" &&
    rg -q 'forbidden exchange-effect authority markers' "$1" &&
    rg -q 'dart compile exe' "$1" &&
    rg -q '"tool/trading_remote_shadow_probe.dart"' "$1" &&
    rg -q '"tool/trading_remote_exact_order.dart"' "$1"
}

runner_bundle_install_is_fail_closed() {
  local start_count
  local bundle_remove_count
  local final_bundle_remove_line
  local final_state_remove_line
  start_count="$(rg -c 'systemctl start "\$UNIT_NAME"' "$1")"
  bundle_remove_count="$(rg -c 'rm -rf "\$BUNDLE_INSTALL_PATH"' "$1")"
  final_bundle_remove_line="$(rg -n 'rm -rf "\$BUNDLE_INSTALL_PATH"' "$1" | tail -1 | cut -d: -f1)"
  final_state_remove_line="$(rg -n 'rm -rf "\$STATE_DIRECTORY" "\$state_private"' "$1" | tail -1 | cut -d: -f1)"
  [ -x "$1" ] &&
    rg -q -- '--ephemeral-install-smoke <artifact-dir>' "$1" &&
    rg -q -- '--install-disabled <artifact-dir>' "$1" &&
    rg -q -- '--initialize-disabled <artifact-dir>' "$1" &&
    rg -q -- '--activate <artifact-dir>' "$1" &&
    rg -q -- '--deactivate <artifact-dir>' "$1" &&
    rg -q -- '--uninstall-disabled <artifact-dir>' "$1" &&
    rg -q 'host lifecycle requires root' "$1" &&
    rg -q 'another public-shadow install operation is active' "$1" &&
    rg -q '\[ ! -e "\$target" \] && \[ ! -L "\$target" \]' "$1" &&
    rg -q 'disabled install target already exists' "$1" &&
    rg -q 'systemd-creds encrypt --name=runner-seed' "$1" &&
    rg -q 'chmod 0755 "\$pending_bundle"' "$1" &&
    rg -q 'systemctl link "\$UNIT_INSTALL_PATH"' "$1" &&
    rg -q 'systemctl is-enabled "\$UNIT_NAME"' "$1" &&
    rg -q 'disabled install became active' "$1" &&
    rg -q 'disabled install created boot enablement' "$1" &&
    rg -q 'cmp -s "\$BINARY_INSTALL_PATH" "\$directory/\$BINARY_NAME"' "$1" &&
    rg -q 'uninstall refused a drifted runner manifest' "$1" &&
    rg -q 'uninstall refused a foreign unit link' "$1" &&
    rg -q 'uninstall refused a foreign state link' "$1" &&
    rg -q 'uninstall refused an enabled unit' "$1" &&
    [ "$bundle_remove_count" = "2" ] &&
    [ -n "$final_bundle_remove_line" ] &&
    [ -n "$final_state_remove_line" ] &&
    [ "$final_bundle_remove_line" -gt "$final_state_remove_line" ] &&
    [ "$start_count" = "4" ] &&
    rg -q '^  install_disabled "\$directory"$' "$1" &&
    rg -q '^  uninstall_disabled "\$directory"$' "$1" &&
    rg -q 'wait_for_exact_unit_evidence "\$started_at" 1' "$1" &&
    rg -q 'wait_for_exact_unit_evidence "\$restarted_at" 2' "$1" &&
    rg -q 'runner identity state disappeared across stop' "$1" &&
    rg -q 'restart continuity used an implicit supervisor restart' "$1" &&
    rg -q 'restart continuity changed or omitted the runner key id' "$1" &&
    rg -q 'systemctl clean --what=state "\$UNIT_NAME"' "$1" &&
    rg -q 'disabled uninstall retained:' "$1" &&
    rg -q 'exact disabled install retained identity and uninstalled without enablement' "$1"
}

runner_activation_is_identity_bound() {
  python3 - "$1" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

def body(name: str) -> str:
    match = re.search(
        rf"^{re.escape(name)}\(\) \{{\n(.*?)(?=^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{{|\Z)",
        source,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise SystemExit(1)
    return match.group(1)

install = body("install_disabled")
initialize = body("initialize_disabled")
activate = body("activate_identity_bound")
deactivate = body("deactivate_identity_bound")

if "systemctl enable" in install or "systemctl enable" in initialize:
    raise SystemExit(1)

initialize_required = [
    'require_exact_installed_bundle "$directory"',
    'disabled initialization refused an enabled unit',
    'journal_cursor="$(current_unit_journal_cursor)"',
    'systemctl start "$UNIT_NAME"',
    'evidence="$(wait_for_unit_evidence_after_cursor "$journal_cursor")"',
    'installed_key_id="$(read_installed_runner_key_id)"',
    '[ "$evidence_key_id" = "$installed_key_id" ]',
    'systemctl stop "$UNIT_NAME"',
    'disabled initialization created boot enablement',
]
if not all(value in initialize for value in initialize_required):
    raise SystemExit(1)

activate_required = [
    "require_expected_runner_key_id",
    'require_exact_installed_bundle "$directory"',
    "rollback_identity_bound_activation",
    'unlink "$wants_path"',
    '[ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ]',
    'journal_cursor="$(current_unit_journal_cursor)"',
    'systemctl start "$UNIT_NAME"',
    'evidence="$(wait_for_unit_evidence_after_cursor "$journal_cursor")"',
    '[ "$(evidence_runner_key_id "$evidence")" = "$EXPECTED_RUNNER_KEY_ID" ]',
    'systemctl enable "$UNIT_NAME"',
    '[ "$(readlink -f "$wants_path")" = "$UNIT_INSTALL_PATH" ]',
]
if not all(value in activate for value in activate_required):
    raise SystemExit(1)
if not (
    activate.index('read_installed_runner_key_id')
    < activate.index('systemctl start "$UNIT_NAME"')
    < activate.index('wait_for_unit_evidence_after_cursor')
    < activate.index('systemctl enable "$UNIT_NAME"')
):
    raise SystemExit(1)

deactivate_required = [
    "require_expected_runner_key_id",
    'require_exact_installed_bundle "$directory"',
    '[ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ]',
    '[ "$(readlink -f "$wants_path")" = "$UNIT_INSTALL_PATH" ]',
    'unlink "$wants_path"',
    'identity-bound deactivation found inconsistent enablement',
    'systemctl daemon-reload',
    'systemctl stop "$UNIT_NAME"',
    'identity-bound deactivation retained boot enablement',
    'identity-bound deactivation changed the canonical unit link',
    'identity-bound deactivation changed runner identity',
]
if not all(value in deactivate for value in deactivate_required):
    raise SystemExit(1)
if not (
    deactivate.index('read_installed_runner_key_id')
    < deactivate.index('unlink "$wants_path"')
    < deactivate.index('systemctl stop "$UNIT_NAME"')
):
    raise SystemExit(1)
if "systemctl disable" in activate or "systemctl disable" in deactivate:
    raise SystemExit(1)
PY
}

runner_external_anchor_is_fail_closed() {
  [ -f "$2" ] &&
    rg -q -- '--export-anchor <artifact-dir>' "$1" &&
    rg -q -- '--anchor-output <absolute-new-directory>' "$1" &&
    rg -Fq '[ ! -e "$ANCHOR_OUTPUT" ] && [ ! -L "$ANCHOR_OUTPUT" ] ||' "$1" &&
    rg -q 'anchor output already exists' "$1" &&
    rg -q 'anchor output parent must be one real directory' "$1" &&
    rg -q 'anchor export refused the installed runner key id' "$1" &&
    rg -Fq 'if hashlib.sha256(bytes.fromhex(public_key_hex)).hexdigest() != expected_key_id:' "$1" &&
    rg -q 'runner public key does not match expected key id' "$1" &&
    rg -q 'anchor export requires one bounded committed evidence file' "$1" &&
    rg -q 'runner-public-key\.ed25519\.hex' "$1" &&
    rg -q 'shadow-evidence\.v1\.json' "$1" &&
    rg -q 'exported untrusted anchor' "$1" &&
    rg -q 'verifyShadowEvidenceContinuity' "$2" &&
    rg -q 'anchor public key does not match runner id' "$2" &&
    rg -q 'anchorVerdict != BingxFuturesShadowEvidenceVerdict\.exactReplay' "$2" &&
    rg -q 'candidateVerdict != BingxFuturesShadowEvidenceVerdict\.accepted' "$2" &&
    rg -q 'anchor directory has unexpected entries' "$2" &&
    rg -q 'anchor evidence is not one bounded file' "$2" &&
    rg -q 'Future<BingxFuturesShadowEvidenceVerdict> verifyShadowEvidenceContinuity' "$3" &&
    rg -q 'authenticateShadowEvidence' "$3" &&
    rg -q 'evidence.sequence != lastAcceptedSequence \+ 1' "$3" &&
    rg -q 'evidence.previousEvidenceHashHex != expectedPreviousHash' "$3" &&
    ! rg -q 'BingxFuturesApiCredentials|placeOrder|cancelOrder|HttpClient|WebSocket' "$2"
}

runner_mandate_admission_is_fail_closed() {
  rg -q 'class BingxFuturesRemoteMandateAdmission' "$2" &&
    rg -q 'hivra:bingx-futures-remote-mandate-admission:v2' "$2" &&
    rg -q "operationKind = 'account_read'" "$2" &&
    rg -q 'accountReadScope = <String>' "$2" &&
    rg -q 'maxUses = 1' "$2" &&
    rg -q 'raw != admission\.canonicalJson' "$2" &&
    rg -q 'mandate\.revokedAtUtc != null' "$2" &&
    rg -q 'verifySignature' "$2" &&
    rg -q 'Export Remote Mandate' "$3" &&
    rg -q -- '--admit-mandate <artifact-dir>' "$1" &&
    rg -q 'mandate artifact must contain bounded bytes' "$1" &&
    rg -q 'mandate artifact bytes are not canonical' "$1" &&
    rg -q 'mandate semantic id mismatch' "$1" &&
    rg -q 'mandate commitment mismatch' "$1" &&
    rg -q 'mandate account-read scope mismatch' "$1" &&
    rg -q 'mandate account-read use bound mismatch' "$1" &&
    rg -q 'mandate Capsule signature is invalid' "$1" &&
    rg -Fq 'value["runner_key_id"] != expected_runner_key_id' "$1" &&
    rg -q 'mandate admission refused conflicting retained authority' "$1" &&
    rg -q 'exact remote mandate replay is idempotent' "$1" &&
    rg -q 'effect=false' "$1" &&
    ! rg -q 'placeOrder|cancelOrder|BingxFuturesApiCredentials' "$2"
}

runner_exchange_credential_is_prepared_only() {
  rg -q -- '--provision-exchange-credential <artifact-dir>' "$1" &&
    rg -q 'canonicalize_exchange_credential_input' "$1" &&
    rg -q 'exchange credential input must contain exactly two lines' "$1" &&
    rg -Fq 'IFS= read -r -s -p "BingX API key: " api_key' "$1" &&
    rg -Fq 'IFS= read -r -s -p "BingX API secret: " api_secret' "$1" &&
    rg -q 'exchange_credential_matches_account_binding' "$1" &&
    rg -Fq '"$expected_account_hash" ]' "$1" &&
    rg -q 'credential provisioning refused the mandate account binding' "$1" &&
    rg -q 'credential provisioning requires one prepared mandate' "$1" &&
    rg -q 'verify_remote_mandate_artifact' "$1" &&
    rg -q 'systemd-creds encrypt --name=bingx-exchange' "$1" &&
    rg -q 'systemd-creds decrypt --name=bingx-exchange' "$1" &&
    rg -Fq '[ -z "$pending" ] || rm -f "$pending"' "$1" &&
    rg -q 'credential provisioning refused conflicting retained credential' "$1" &&
    rg -q 'exact prepared exchange credential replay is idempotent' "$1" &&
    rg -q 'self-test accepted the wrong exchange account binding' "$1" &&
    rg -q 'effect=false' "$1" &&
    ! rg -q 'LoadCredentialEncrypted=.*bingx|LoadCredential=.*bingx' "$2" &&
    ! rg -q 'BINGX_API|api[_-]?secret|api[_-]?key' "$2"
}

runner_account_read_probe_is_fail_closed() {
  local pending_commit_line
  local resolution_line
  local replay_return_line
  local provider_start_line
  local completed_commit_line
  pending_commit_line="$(rg -n -F '"$account_binding" pending' "$1" | head -1 | cut -d: -f1)"
  resolution_line="$(rg -n 'resolution=.*resolve_account_read_operation_before_provider' "$1" | head -1 | cut -d: -f1)"
  replay_return_line="$(rg -n 'exact account-read replay returned retained redacted evidence' "$1" | head -1 | cut -d: -f1)"
  provider_start_line="$(rg -n 'if ! systemd-run' "$1" | head -1 | cut -d: -f1)"
  completed_commit_line="$(rg -n -F '"$account_binding" completed "$work/stdout"' "$1" | head -1 | cut -d: -f1)"
  rg -q -- '--probe-exchange-account <artifact-dir>' "$1" &&
    rg -q 'probe_exchange_account_once' "$1" &&
    rg -q 'account probe requires an inactive public-shadow runner' "$1" &&
    rg -q 'account probe requires a disabled public-shadow runner' "$1" &&
    rg -q 'account probe requires one prepared mandate' "$1" &&
    rg -q 'account probe requires one prepared exchange credential' "$1" &&
    rg -q 'verify_remote_mandate_artifact' "$1" &&
    rg -q 'systemd-run' "$1" &&
    rg -q -- '--wait --pipe --collect --quiet' "$1" &&
    rg -q 'LoadCredentialEncrypted="runner-seed:' "$1" &&
    rg -q 'LoadCredentialEncrypted="bingx-exchange:' "$1" &&
    rg -q 'RuntimeMaxSec=60s' "$1" &&
    rg -q 'MemoryMax=128M' "$1" &&
    rg -q 'MemorySwapMax=0' "$1" &&
    rg -q 'SocketBindDeny=any' "$1" &&
    rg -q -- '--mode account-read' "$1" &&
    rg -q 'validate_account_read_evidence' "$1" &&
    rg -q 'commit_account_read_operation_journal' "$1" &&
    rg -q 'validate_account_read_operation_journal' "$1" &&
    rg -Fq 'require_remote_mandate_execution_eligible "$verified_work"' "$1" &&
    rg -q 'resolve_account_read_operation_before_provider' "$1" &&
    rg -q 'account probe authority is not currently eligible for execution' "$1" &&
    rg -q 'account probe operation is unresolved after an interrupted attempt' "$1" &&
    rg -q 'exact account-read replay returned retained redacted evidence' "$1" &&
    rg -q '"hivra-trading-account-read-operation-v1"' "$1" &&
    rg -q '"read_scope": \["balance", "positions", "open_orders"\]' "$1" &&
    rg -q '"max_uses": 1' "$1" &&
    rg -Fq '"$account_binding" pending' "$1" &&
    rg -Fq '"$account_binding" completed "$work/stdout"' "$1" &&
    [ -n "$pending_commit_line" ] &&
    [ -n "$resolution_line" ] &&
    [ -n "$replay_return_line" ] &&
    [ -n "$provider_start_line" ] &&
    [ -n "$completed_commit_line" ] &&
    [ "$resolution_line" -lt "$pending_commit_line" ] &&
    [ "$resolution_line" -lt "$provider_start_line" ] &&
    [ "$pending_commit_line" -lt "$provider_start_line" ] &&
    [ "$replay_return_line" -lt "$provider_start_line" ] &&
    [ "$completed_commit_line" -gt "$provider_start_line" ] &&
    rg -q 'account-read evidence bytes are not canonical' "$1" &&
    rg -q 'account-read evidence is incomplete or effectful' "$1" &&
    rg -q 'account probe retained its transient unit' "$1" &&
    rg -q 'effect=false' "$1" &&
    rg -q "const String accountReadMode = 'account-read';" "$2" &&
    rg -q "const String accountReadScopeWire = 'balance,positions,open_orders';" "$2" &&
    rg -q 'const int accountReadMaxUses = 1;' "$2" &&
    rg -q 'account read authority is not exact' "$2" &&
    rg -q 'runMandateBoundAccountRead' "$2" &&
    rg -q 'readExchangeCredentialFile' "$2" &&
    rg -q 'exchange account binding mismatch' "$2" &&
    rg -q 'mandate is expired' "$2" &&
    rg -q 'getUserBalance' "$2" &&
    rg -q 'getUserPositions' "$2" &&
    rg -q 'getOpenOrders' "$2" &&
    rg -q "'effect': false" "$2" &&
    ! rg -q 'responseBody|accountEquityQuoteDecimal|quantityDecimal|orderId' "$2" &&
    ! shadow_probe_has_authority "$2" &&
    ! rg -q 'LoadCredentialEncrypted=.*bingx|LoadCredential=.*bingx' "$3"
}

runner_exact_order_is_fail_closed() {
  local artifact="$1"
  local probe="$2"
  local models="$3"
  local exchange="$4"
  local tests="$5"
  rg -q -- '--execute-exact-order <artifact-dir>' "$artifact" &&
    rg -q 'execute_exact_order_once' "$artifact" &&
    rg -q 'LoadCredentialEncrypted="bingx-exchange:' "$artifact" &&
    rg -q 'LoadCredential=exact-order-admission:' "$artifact" &&
    rg -q 'MemoryMax=128M' "$artifact" &&
    rg -q 'exact-order.v3.json' "$artifact" &&
    rg -q 'mutated exact-order semantics' "$artifact" &&
    rg -q 'const String exactOrderMode = .exact-order.' "$probe" &&
    rg -q 'ExternalEffectService' "$probe" &&
    rg -q 'approvalEvidenceHashHex: admission.commitmentHashHex' "$probe" &&
    rg -q 'exact order authority expired before delivery' "$probe" &&
    rg -q 'exactOrderContractVersion' "$models" &&
    rg -q "exactOrderOperationKind = 'one_exact_order'" "$models" &&
    rg -q 'class BingxFuturesExternalEffectAdapter' "$exchange" &&
    rg -q 'test_order_outcome_ambiguous' "$exchange" &&
    rg -q 'order_not_confirmed' "$exchange" &&
    rg -q 'exact test order replay never issues a second POST' "$tests" &&
    rg -q 'ambiguous test order remains unresolved without blind retry' "$tests" &&
    rg -q 'live timeout reconciles by client id after restart' "$tests" &&
    "$artifact" --self-test >/dev/null
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
    "StartLimitIntervalSec": "32d",
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
    "RuntimeMaxSec": "31d",
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
    "--run-count", "8928",
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

if shadow_probe_exposes_runner_identity "$SHADOW_PROBE"; then
  pass "public shadow evidence exposes its non-secret runner identity fingerprint"
else
  fail "public shadow evidence lost its runner identity fingerprint"
fi

if shadow_probe_is_bounded_scheduler "$SHADOW_PROBE"; then
  pass "live shadow probe scheduler is bounded, serial, and retry-free"
else
  fail "live shadow probe scheduler lost bounded cadence or serial execution"
fi

if public_session_stream_is_fail_closed "$PUBLIC_SESSION_ACCUMULATOR" "$PUBLIC_SESSION_STREAM" "$PUBLIC_SESSION_TEST" &&
  local_session_stream_is_wired "$TRADING_MODULE" "$TRADING_SCREEN"; then
  pass "public session stream is bounded, gap-resetting, process-scoped, and authority-free"
else
  fail "public session stream lost bounded fail-closed coverage semantics"
fi

if liquidity_sequence_is_canonical \
  "$TVH_RULE_ENGINE" "$LIVE_DECISION" "$ZONE_DECISION" "$TRADING_CYCLE" \
  "$TVH_RULE_TEST" "$ZONE_DECISION_TEST" "$TRADING_CYCLE_TEST"; then
  pass "liquidity sequence keeps volume authority, structural anchors, proxy ranking, and exact blockers"
else
  fail "liquidity sequence drifted into indicator conjunction, proxy authority, or generic blockers"
fi

if runner_artifact_is_verifiable "$RUNNER_ARTIFACT" &&
  runner_package_is_pinned "$RUNNER_PACKAGE" "$RUNNER_PACKAGE_LOCK" &&
  "$RUNNER_ARTIFACT" --self-test >/dev/null; then
  pass "standalone runner bundle binds pinned dependencies, binary, unit, target, paths, and bounded read-only authority"
else
  fail "standalone runner bundle lost dependency, unit, target, path, provenance, or authority verification"
fi

if runner_bundle_install_is_fail_closed "$RUNNER_ARTIFACT"; then
  pass "runner bundle exact-unit smoke is collision-safe, encrypted, non-enabled, and self-cleaning"
else
  fail "runner bundle exact-unit smoke lost collision, credential, enablement, or cleanup safety"
fi

if runner_activation_is_identity_bound "$RUNNER_ARTIFACT"; then
  pass "runner activation is explicit, identity-bound, rollback-safe, and exactly reversible"
else
  fail "runner activation lost identity binding, rollback, or exact deactivation"
fi

if runner_external_anchor_is_fail_closed \
  "$RUNNER_ARTIFACT" "$SHADOW_ANCHOR_VERIFIER" "$SHADOW_EVIDENCE"; then
  pass "portable shadow anchor preserves exact signed bytes and verifies off-host continuity"
else
  fail "portable shadow anchor lost exact export, authentication, or continuity rejection"
fi

if runner_mandate_admission_is_fail_closed \
  "$RUNNER_ARTIFACT" "$TRADING_MODELS" "$TRADING_SCREEN"; then
  pass "remote mandate admission binds exact Capsule semantics to one runner without effect authority"
else
  fail "remote mandate admission lost canonical proof, runner binding, or prepared-only semantics"
fi

if runner_exchange_credential_is_prepared_only \
  "$RUNNER_ARTIFACT" "$RUNNER_SUPERVISOR"; then
  pass "exchange credential provisioning is mandate-bound, host-encrypted, and unavailable to the runner"
else
  fail "exchange credential provisioning leaked authority or lost mandate/account binding"
fi

if runner_account_read_probe_is_fail_closed \
  "$RUNNER_ARTIFACT" "$SHADOW_PROBE" "$RUNNER_SUPERVISOR"; then
  pass "mandate-bound account read is transient, redacted, and effect-free"
else
  fail "mandate-bound account read lost transient, redaction, or no-effect boundaries"
fi

if runner_exact_order_is_fail_closed \
  "$RUNNER_ARTIFACT" "$EXACT_ORDER_PROBE" "$TRADING_MODELS" \
  "$EXCHANGE_SERVICE" "$REMOTE_PROBE_TEST"; then
pass "exact remote order uses one signed operation, durable effect journal, and reconciliation-only replay"

if rg -n \
  '\.(cancelOrder|switchLeverage|switchMarginType)\s*\(' \
  "$ROOT/flutter/tool/trading_remote_exact_order.dart" >/dev/null || \
  rg -n \
    -- '--(cancel-order|switch-leverage|switch-margin-type|withdraw|transfer)' \
    "$ROOT/flutter/tool/trading_remote_exact_order.dart" >/dev/null; then
  fail "exact remote order executable exposes widened exchange authority"
fi
pass "exact remote order executable exposes no cancel, leverage, margin, transfer, or withdrawal path"
else
  fail "exact remote order lost signed binding, durable handoff, or no-duplicate reconciliation"
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
BUNDLE_TRAP_SCOPE_MUTATION="$(mktemp)"
BUNDLE_RESTART_MUTATION="$(mktemp)"
PROBE_IDENTITY_MUTATION="$(mktemp)"
BUNDLE_IDENTITY_MUTATION="$(mktemp)"
BUNDLE_FOREIGN_STATE_MUTATION="$(mktemp)"
BUNDLE_EARLY_ANCHOR_MUTATION="$(mktemp)"
ACTIVATION_IDENTITY_MUTATION="$(mktemp)"
ACTIVATION_ROLLBACK_MUTATION="$(mktemp)"
INITIALIZATION_ENABLE_MUTATION="$(mktemp)"
DEACTIVATION_IDENTITY_MUTATION="$(mktemp)"
ACTIVATION_STALE_LOG_MUTATION="$(mktemp)"
ANCHOR_OVERWRITE_MUTATION="$(mktemp)"
ANCHOR_KEY_MUTATION="$(mktemp)"
ANCHOR_VERIFIER_MUTATION="$(mktemp)"
ANCHOR_CONTINUITY_MUTATION="$(mktemp)"
MANDATE_RUNNER_BINDING_MUTATION="$(mktemp)"
MANDATE_SCOPE_MUTATION="$(mktemp)"
EXCHANGE_ACCOUNT_BINDING_MUTATION="$(mktemp)"
EXCHANGE_RUNNER_ACCESS_MUTATION="$(mktemp)"
EXCHANGE_ROLLBACK_MUTATION="$(mktemp)"
EXCHANGE_VISIBLE_KEY_MUTATION="$(mktemp)"
ACCOUNT_READ_TRANSIENT_MUTATION="$(mktemp)"
ACCOUNT_READ_EFFECT_MUTATION="$(mktemp)"
ACCOUNT_READ_RAW_OUTPUT_MUTATION="$(mktemp)"
ACCOUNT_READ_JOURNAL_MUTATION="$(mktemp)"
ACCOUNT_READ_ELIGIBILITY_MUTATION="$(mktemp)"
PUBLIC_SESSION_GAP_MUTATION="$(mktemp)"
LOCAL_SESSION_WIRING_MUTATION="$(mktemp)"
LIQUIDITY_AUTHORITY_MUTATION="$(mktemp)"
LIQUIDATION_ANCHOR_MUTATION="$(mktemp)"
trap 'rm -f "$PUBLIC_MUTATION" "$PROBE_MUTATION" "$STREAM_MUTATION" "$CHECKPOINT_MUTATION" "$SCHEDULER_MUTATION" "$ARTIFACT_MUTATION" "$RUNTIME_SMOKE_MUTATION" "$CI_CLEAN_MUTATION" "$EXECUTION_MUTATION" "$CYCLE_MUTATION" "$SUPERVISOR_RESTART_MUTATION" "$SUPERVISOR_MEMORY_MUTATION" "$SUPERVISOR_CREDENTIAL_MUTATION" "$SUPERVISOR_LISTENER_MUTATION" "$BUNDLE_UNIT_MUTATION" "$BUNDLE_ENABLE_MUTATION" "$BUNDLE_COLLISION_MUTATION" "$BUNDLE_CLEANUP_MUTATION" "$BUNDLE_TRAP_SCOPE_MUTATION" "$BUNDLE_RESTART_MUTATION" "$PROBE_IDENTITY_MUTATION" "$BUNDLE_IDENTITY_MUTATION" "$BUNDLE_FOREIGN_STATE_MUTATION" "$BUNDLE_EARLY_ANCHOR_MUTATION" "$ACTIVATION_IDENTITY_MUTATION" "$ACTIVATION_ROLLBACK_MUTATION" "$INITIALIZATION_ENABLE_MUTATION" "$DEACTIVATION_IDENTITY_MUTATION" "$ACTIVATION_STALE_LOG_MUTATION" "$ANCHOR_OVERWRITE_MUTATION" "$ANCHOR_KEY_MUTATION" "$ANCHOR_VERIFIER_MUTATION" "$ANCHOR_CONTINUITY_MUTATION" "$MANDATE_RUNNER_BINDING_MUTATION" "$MANDATE_SCOPE_MUTATION" "$EXCHANGE_ACCOUNT_BINDING_MUTATION" "$EXCHANGE_RUNNER_ACCESS_MUTATION" "$EXCHANGE_ROLLBACK_MUTATION" "$EXCHANGE_VISIBLE_KEY_MUTATION" "$ACCOUNT_READ_TRANSIENT_MUTATION" "$ACCOUNT_READ_EFFECT_MUTATION" "$ACCOUNT_READ_RAW_OUTPUT_MUTATION" "$ACCOUNT_READ_JOURNAL_MUTATION" "$ACCOUNT_READ_ELIGIBILITY_MUTATION" "$PUBLIC_SESSION_GAP_MUTATION" "$LOCAL_SESSION_WIRING_MUTATION" "$LIQUIDITY_AUTHORITY_MUTATION" "$LIQUIDATION_ANCHOR_MUTATION"' EXIT
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
sed 's#cmp -s "$BINARY_INSTALL_PATH" "$directory/$BINARY_NAME"#true#' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_TRAP_SCOPE_MUTATION"
sed 's/wait_for_exact_unit_evidence "$restarted_at" 2/wait_for_exact_unit_evidence "$restarted_at" 1/' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_RESTART_MUTATION"
sed '/runner_key_id=\${evidence\.runnerKeyId}/d' \
  "$SHADOW_PROBE" > "$PROBE_IDENTITY_MUTATION"
sed 's/\[ "$first_runner_key_id" = "$second_runner_key_id" \]/true/' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_IDENTITY_MUTATION"
sed '/uninstall refused a foreign state link/d' \
  "$RUNNER_ARTIFACT" > "$BUNDLE_FOREIGN_STATE_MUTATION"
awk '{
  if ($0 ~ /rm -f "\$CREDENTIAL_INSTALL_PATH"/) {
    print "  rm -rf \"$BUNDLE_INSTALL_PATH\""
  }
  print
}' "$RUNNER_ARTIFACT" > "$BUNDLE_EARLY_ANCHOR_MUTATION"
sed 's/\[ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" \]/true/' \
  "$RUNNER_ARTIFACT" > "$ACTIVATION_IDENTITY_MUTATION"
sed '/unlink "\$wants_path"/d' \
  "$RUNNER_ARTIFACT" > "$ACTIVATION_ROLLBACK_MUTATION"
sed '/^initialize_disabled() {/a\
  systemctl enable "$UNIT_NAME"' \
  "$RUNNER_ARTIFACT" > "$INITIALIZATION_ENABLE_MUTATION"
sed '/identity-bound deactivation changed runner identity/d' \
  "$RUNNER_ARTIFACT" > "$DEACTIVATION_IDENTITY_MUTATION"
sed 's/wait_for_unit_evidence_after_cursor "\$journal_cursor"/wait_for_unit_evidence "\$started_at"/' \
  "$RUNNER_ARTIFACT" > "$ACTIVATION_STALE_LOG_MUTATION"
sed 's/\[ ! -e "$ANCHOR_OUTPUT" \] && \[ ! -L "$ANCHOR_OUTPUT" \]/true/' \
  "$RUNNER_ARTIFACT" > "$ANCHOR_OVERWRITE_MUTATION"
sed 's/hashlib\.sha256(bytes\.fromhex(public_key_hex))\.hexdigest() != expected_key_id/False/' \
  "$RUNNER_ARTIFACT" > "$ANCHOR_KEY_MUTATION"
sed 's/anchorVerdict != BingxFuturesShadowEvidenceVerdict\.exactReplay/false/' \
  "$SHADOW_ANCHOR_VERIFIER" > "$ANCHOR_VERIFIER_MUTATION"
sed 's/evidence\.sequence != lastAcceptedSequence + 1/false/' \
  "$SHADOW_EVIDENCE" > "$ANCHOR_CONTINUITY_MUTATION"
sed 's/value\["runner_key_id"\] != expected_runner_key_id/False/' \
  "$RUNNER_ARTIFACT" > "$MANDATE_RUNNER_BINDING_MUTATION"
sed '/accountReadScope = <String>/,+4d' \
  "$TRADING_MODELS" > "$MANDATE_SCOPE_MUTATION"
sed 's/    "$expected_account_hash" ]/    "bypassed" ]/' \
  "$RUNNER_ARTIFACT" > "$EXCHANGE_ACCOUNT_BINDING_MUTATION"
printf '%s\n' 'LoadCredentialEncrypted=bingx-exchange:/etc/credstore.encrypted/hivra-trading-public-shadow.bingx' \
  >> "$EXCHANGE_RUNNER_ACCESS_MUTATION"
cat "$RUNNER_SUPERVISOR" >> "$EXCHANGE_RUNNER_ACCESS_MUTATION"
sed '/\[ -z "\$pending" \] || rm -f "\$pending"/d' \
  "$RUNNER_ARTIFACT" > "$EXCHANGE_ROLLBACK_MUTATION"
sed 's/IFS= read -r -s -p "BingX API key: "/IFS= read -r -p "BingX API key: "/' \
  "$RUNNER_ARTIFACT" > "$EXCHANGE_VISIBLE_KEY_MUTATION"
sed 's/--wait --pipe --collect --quiet/--wait --pipe --quiet/' \
  "$RUNNER_ARTIFACT" > "$ACCOUNT_READ_TRANSIENT_MUTATION"
sed "s/'effect': false/'effect': true/" \
  "$SHADOW_PROBE" > "$ACCOUNT_READ_EFFECT_MUTATION"
cp "$SHADOW_PROBE" "$ACCOUNT_READ_RAW_OUTPUT_MUTATION"
printf '%s\n' 'responseBody' >> "$ACCOUNT_READ_RAW_OUTPUT_MUTATION"
sed '/account_binding" pending/d' \
  "$RUNNER_ARTIFACT" > "$ACCOUNT_READ_JOURNAL_MUTATION"
sed '/require_remote_mandate_execution_eligible "\$verified_work"/d' \
  "$RUNNER_ARTIFACT" > "$ACCOUNT_READ_ELIGIBILITY_MUTATION"
sed 's/accumulator\.markDisconnected();/accumulator.acceptHeartbeat();/' \
  "$PUBLIC_SESSION_STREAM" > "$PUBLIC_SESSION_GAP_MUTATION"
sed 's/publicSessionStream\.snapshotFor(symbol)/null/' \
  "$TRADING_MODULE" > "$LOCAL_SESSION_WIRING_MUTATION"
sed "s/final longReady = longTradeOk && normalizedRequiredSide != 'sell';/final longReady = longTradeOk \&\& longSessionAligned \&\& normalizedRequiredSide != 'sell';/" \
  "$TVH_RULE_ENGINE" > "$LIQUIDITY_AUTHORITY_MUTATION"
sed 's/anchorSource = externalBuyRetest\.source;/anchorSource = "liquidation_proxy";/' \
  "$ZONE_DECISION" > "$LIQUIDATION_ANCHOR_MUTATION"
if public_pipeline_has_authority "$PUBLIC_MUTATION" && \
  shadow_probe_has_authority "$PROBE_MUTATION" && \
  ! shadow_probe_exposes_runner_identity "$PROBE_IDENTITY_MUTATION" && \
  ! shadow_probe_is_bounded_scheduler "$SCHEDULER_MUTATION" && \
  ! public_session_stream_is_fail_closed "$PUBLIC_SESSION_ACCUMULATOR" "$PUBLIC_SESSION_GAP_MUTATION" "$PUBLIC_SESSION_TEST" && \
  ! local_session_stream_is_wired "$LOCAL_SESSION_WIRING_MUTATION" "$TRADING_SCREEN" && \
  ! liquidity_sequence_is_canonical "$LIQUIDITY_AUTHORITY_MUTATION" "$LIVE_DECISION" "$ZONE_DECISION" "$TRADING_CYCLE" "$TVH_RULE_TEST" "$ZONE_DECISION_TEST" "$TRADING_CYCLE_TEST" && \
  ! liquidity_sequence_is_canonical "$TVH_RULE_ENGINE" "$LIVE_DECISION" "$LIQUIDATION_ANCHOR_MUTATION" "$TRADING_CYCLE" "$TVH_RULE_TEST" "$ZONE_DECISION_TEST" "$TRADING_CYCLE_TEST" && \
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
  ! runner_bundle_install_is_fail_closed "$BUNDLE_CLEANUP_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_TRAP_SCOPE_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_RESTART_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_IDENTITY_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_FOREIGN_STATE_MUTATION" && \
  ! runner_bundle_install_is_fail_closed "$BUNDLE_EARLY_ANCHOR_MUTATION" && \
  ! runner_activation_is_identity_bound "$ACTIVATION_IDENTITY_MUTATION" && \
  ! runner_activation_is_identity_bound "$ACTIVATION_ROLLBACK_MUTATION" && \
  ! runner_activation_is_identity_bound "$INITIALIZATION_ENABLE_MUTATION" && \
  ! runner_activation_is_identity_bound "$DEACTIVATION_IDENTITY_MUTATION" && \
  ! runner_activation_is_identity_bound "$ACTIVATION_STALE_LOG_MUTATION" && \
  ! runner_external_anchor_is_fail_closed "$ANCHOR_OVERWRITE_MUTATION" "$SHADOW_ANCHOR_VERIFIER" "$SHADOW_EVIDENCE" && \
  ! runner_external_anchor_is_fail_closed "$ANCHOR_KEY_MUTATION" "$SHADOW_ANCHOR_VERIFIER" "$SHADOW_EVIDENCE" && \
  ! runner_external_anchor_is_fail_closed "$RUNNER_ARTIFACT" "$ANCHOR_VERIFIER_MUTATION" "$SHADOW_EVIDENCE" && \
  ! runner_external_anchor_is_fail_closed "$RUNNER_ARTIFACT" "$SHADOW_ANCHOR_VERIFIER" "$ANCHOR_CONTINUITY_MUTATION" && \
  ! runner_mandate_admission_is_fail_closed "$MANDATE_RUNNER_BINDING_MUTATION" "$TRADING_MODELS" "$TRADING_SCREEN" && \
  ! runner_mandate_admission_is_fail_closed "$RUNNER_ARTIFACT" "$MANDATE_SCOPE_MUTATION" "$TRADING_SCREEN" && \
  ! runner_exchange_credential_is_prepared_only "$EXCHANGE_ACCOUNT_BINDING_MUTATION" "$RUNNER_SUPERVISOR" && \
  ! runner_exchange_credential_is_prepared_only "$RUNNER_ARTIFACT" "$EXCHANGE_RUNNER_ACCESS_MUTATION" && \
  ! runner_exchange_credential_is_prepared_only "$EXCHANGE_ROLLBACK_MUTATION" "$RUNNER_SUPERVISOR" && \
  ! runner_exchange_credential_is_prepared_only "$EXCHANGE_VISIBLE_KEY_MUTATION" "$RUNNER_SUPERVISOR" && \
  ! runner_account_read_probe_is_fail_closed "$ACCOUNT_READ_TRANSIENT_MUTATION" "$SHADOW_PROBE" "$RUNNER_SUPERVISOR" && \
  ! runner_account_read_probe_is_fail_closed "$RUNNER_ARTIFACT" "$ACCOUNT_READ_EFFECT_MUTATION" "$RUNNER_SUPERVISOR" && \
  ! runner_account_read_probe_is_fail_closed "$RUNNER_ARTIFACT" "$ACCOUNT_READ_RAW_OUTPUT_MUTATION" "$RUNNER_SUPERVISOR" && \
  ! runner_account_read_probe_is_fail_closed "$ACCOUNT_READ_JOURNAL_MUTATION" "$SHADOW_PROBE" "$RUNNER_SUPERVISOR" && \
  ! runner_account_read_probe_is_fail_closed "$ACCOUNT_READ_ELIGIBILITY_MUTATION" "$SHADOW_PROBE" "$RUNNER_SUPERVISOR"; then
  pass "public, scheduler, bundle, activation, anchor, credential, account-read, durable-stream, and execution-outcome mutations are rejected"
else
  fail "public, scheduler, bundle, activation, anchor, credential, account-read, durable-stream, or execution-outcome mutation self-test failed"
fi

exit "$STATUS"
