#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
ENTRYPOINT="$FLUTTER_DIR/tool/trading_remote_shadow_probe.dart"
BASELINE="$ROOT/toolchains/hivra-baseline.conf"
PACKAGE_DIR="$ROOT/tools/trading/public_shadow_runner_package"
PACKAGE_LOCK="$PACKAGE_DIR/pubspec.lock"
UNIT_SOURCE="$ROOT/tools/trading/hivra-trading-public-shadow-runner.service"
SESSION_UNIT_SOURCE="$ROOT/tools/trading/hivra-trading-deterministic-session.service"
LIFECYCLE_SOURCE="$ROOT/tools/trading/public_shadow_runner_artifact.sh"
BINARY_NAME="hivra-trading-public-shadow-runner"
EFFECT_BINARY_NAME="hivra-trading-exact-order-runner"
UNIT_NAME="hivra-trading-public-shadow-runner.service"
SESSION_UNIT_NAME="hivra-trading-deterministic-session.service"
LIFECYCLE_NAME="hivra-trading-runner-lifecycle"
MANIFEST_NAME="ARTIFACT-MANIFEST.v2"
SCHEMA_VERSION="hivra-trading-public-shadow-runner-bundle-v2"
AUTHORITY_PROFILE="public-market-shadow-plus-bounded-account-read-exact-order-and-deterministic-session"
BUNDLE_INSTALL_PATH="/opt/hivra/trading-public-shadow"
BINARY_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$BINARY_NAME"
EFFECT_BINARY_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$EFFECT_BINARY_NAME"
UNIT_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$UNIT_NAME"
UNIT_LINK_PATH="/etc/systemd/system/$UNIT_NAME"
SESSION_UNIT_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$SESSION_UNIT_NAME"
SESSION_UNIT_LINK_PATH="/etc/systemd/system/$SESSION_UNIT_NAME"
LIFECYCLE_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$LIFECYCLE_NAME"
CREDENTIAL_INSTALL_PATH="/etc/credstore.encrypted/hivra-trading-public-shadow.seed"
EXCHANGE_CREDENTIAL_INSTALL_PATH="/etc/credstore.encrypted/hivra-trading-public-shadow.bingx"
STATE_DIRECTORY="/var/lib/hivra-trading-public-shadow"
ACCOUNT_READ_SCOPE_WIRE="balance,positions,open_orders"
ACCOUNT_READ_MAX_USES="1"
DETERMINISTIC_HISTORY_LIMIT="4096"
MODE=""
ARTIFACT_DIR=""
TARGET_OS=""
TARGET_ARCH=""
EXPECTED_RUNNER_KEY_ID=""
ANCHOR_OUTPUT=""
MANDATE_ARTIFACT=""
REVOCATION_ARTIFACT=""
SCHEDULER_SESSION_OPERATION_ID=""
INSTALLED_BUNDLE_MODE=0

enable_exact_installed_bundle_mode() {
  [ -n "$ARTIFACT_DIR" ] || return 0
  [ "$(readlink -f -- "${BASH_SOURCE[0]}")" = "$LIFECYCLE_INSTALL_PATH" ] ||
    return 0
  [ "$(readlink -f -- "$ARTIFACT_DIR")" = "$BUNDLE_INSTALL_PATH" ] ||
    return 0
  INSTALLED_BUNDLE_MODE=1
}

usage() {
  cat <<'EOF'
Usage:
  tools/trading/public_shadow_runner_artifact.sh --build <absolute-output-dir>
    [--target-os linux --target-arch x64]
  tools/trading/public_shadow_runner_artifact.sh --verify <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --runtime-smoke <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --install-disabled <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --initialize-disabled <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --provision-disabled <artifact-dir>
    --anchor-output <absolute-new-directory>
  tools/trading/public_shadow_runner_artifact.sh --activate <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --deactivate <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --export-anchor <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
    --anchor-output <absolute-new-directory>
  tools/trading/public_shadow_runner_artifact.sh --admit-mandate <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
    --mandate-artifact <absolute-json-file>
  tools/trading/public_shadow_runner_artifact.sh --revoke-session <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
    --revocation-artifact <absolute-json-file>
  tools/trading/public_shadow_runner_artifact.sh --provision-exchange-credential <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
    [--mandate-artifact <absolute-json-file>]
  tools/trading/public_shadow_runner_artifact.sh --apply-prepared-session <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
    --mandate-artifact <absolute-json-file>
  tools/trading/public_shadow_runner_artifact.sh --activate-prepared-session <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --run-prepared-session <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --enable-prepared-session-service <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --pause-prepared-session-service <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --prepared-session-service-status <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --probe-exchange-account <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --execute-exact-order <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --execute-deterministic-order <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --recover-deterministic-session <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --uninstall-disabled <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --ephemeral-install-smoke <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --self-test

The build mode requires a completely clean worktree and the pinned Dart SDK.
It produces two host-native executables, two exact systemd units, one lifecycle
owner, and one exact provenance manifest. Host lifecycle modes require a root
Linux systemd host. Installation requires empty canonical target paths and
leaves both exact units disabled and inactive. Initialization proves its persistent identity without
enabling it. Activation requires that exact identity. Uninstall refuses drifted
or foreign-owned paths. Anchor export atomically copies the exact latest signed
evidence and its public key; acceptance happens only after off-host verification.
Mandate admission verifies the exact Capsule signature and runner binding, then
stores one prepared artifact without activating exchange authority.
Session revocation verifies the retained admission and one separate Capsule-
signed stop artifact, then atomically stops only that exact bounded session.
Credential provisioning accepts the API key and secret only from a hidden TTY
prompt or exact two-line stdin, verifies the prepared mandate account binding,
and stores host-encrypted prepared state without exposing it to the runner.
Prepared-session apply verifies one bounded signed session, prepares its
account-bound encrypted credential first, then admits that exact session. A
crash between those commits leaves only an inert credential and exact replay
finishes the same apply; the runner stays disabled and inactive.
Prepared-session activation revalidates the retained signed session, Runner
identity, account-bound encrypted credential, time bounds, and revocation
state, then atomically creates only the canonical active session state. It does
not start or enable the public-shadow unit, schedule a cycle, read market data,
or expose the exchange credential to an effect process.
Prepared-session run holds one scheduler lock, waits only for the signed
cadence, checks revocation at least every five seconds, and serially invokes
the existing deterministic-order cycle owner. It runs in the foreground,
stops on any failure or terminal session state, and installs no timer. The
persistent session service invokes that same owner from the verified installed
bundle, has no restart policy, and requires explicit enable, pause, and status
operations.
Account probing uses one collected transient systemd unit, supplies both
encrypted credentials only to that process, permits exactly balance, positions,
and open-orders GETs, and emits only a bounded redacted verdict.
Deterministic execution first captures one operation-scoped public-market
evidence item for the signed mandate symbol without loading exchange credentials.
Exact replay reuses those retained evidence bytes before the existing effect
runner is allowed to access the exchange credential.
Session recovery reads only an existing cycle effect and reconciles its provider
outcome. It cannot capture market data, create an intent, or deliver an order.
Provisioning composes exact verification, disabled installation, one identity
initialization, and signed anchor export. The unit remains disabled and inactive;
any failed initialization or anchor export removes only the exact installed bundle.
EOF
}

canonicalize_exchange_credential_input() {
  python3 -c '
import hashlib
import json
import re
import sys

raw = sys.stdin.buffer.read(2049)
if len(raw) > 2048:
    raise SystemExit("exchange credential input exceeds the bounded size")
try:
    text = raw.decode("ascii")
except UnicodeDecodeError:
    raise SystemExit("exchange credential input must be ASCII")
lines = text.splitlines()
if len(lines) != 2 or text not in {"\n".join(lines), "\n".join(lines) + "\n"}:
    raise SystemExit("exchange credential input must contain exactly two lines")
api_key, api_secret = lines
if re.fullmatch(r"[!-~]{1,512}", api_key) is None:
    raise SystemExit("exchange API key is invalid")
if re.fullmatch(r"[!-~]{1,512}", api_secret) is None:
    raise SystemExit("exchange API secret is invalid")
sys.stdout.write(json.dumps(
    {"contract_version": "bingx-exchange-credential-v1", "api_key": api_key, "api_secret": api_secret},
    separators=(",", ":"),
))
'
}

exchange_credential_account_hash() {
  python3 -c '
import hashlib
import json
import sys

value = json.load(sys.stdin)
sys.stdout.write(hashlib.sha256(value["api_key"].encode("ascii")).hexdigest())
'
}

exchange_credential_matches_account_binding() {
  local credential_json="$1"
  local expected_account_hash="$2"
  [ "$(printf '%s' "$credential_json" | exchange_credential_account_hash)" = \
    "$expected_account_hash" ]
}

remove_exact_enablement_link() {
  local wants_path="$1"
  local expected_target="$2"
  if [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ]; then
    return
  fi
  [ -L "$wants_path" ] &&
    [ "$(readlink -f "$wants_path")" = "$(readlink -f "$expected_target")" ] ||
    die "session service refused foreign boot enablement"
  rm -f "$wants_path"
}

remove_session_boot_enablement() {
  remove_exact_enablement_link \
    "/etc/systemd/system/multi-user.target.wants/$SESSION_UNIT_NAME" \
    "$SESSION_UNIT_INSTALL_PATH"
}

session_service_pause_recovery_action() {
  case "$1" in
    inactive) printf 'none\n' ;;
    failed) printf 'reset-failed\n' ;;
    *) return 1 ;;
  esac
}

require_retained_exchange_credential_binding() {
  local expected_account_hash="$1"
  [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
    [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    die "prepared session activation requires one encrypted exchange credential"
  local credential_json
  credential_json="$(
    systemd-creds decrypt --name=bingx-exchange \
      "$EXCHANGE_CREDENTIAL_INSTALL_PATH" - 2>/dev/null
  )" || die "prepared session activation could not decrypt the exchange credential"
  exchange_credential_matches_account_binding \
    "$credential_json" "$expected_account_hash" || {
    unset credential_json
    die "prepared session activation refused the exchange account binding"
  }
  unset credential_json
}

validate_deterministic_operation_store() {
  local directory="$1"
  local operation_id="$2"
  local limit="${3:-$DETERMINISTIC_HISTORY_LIMIT}"
  local max_file_bytes="${4:-8192}"
  python3 - "$directory" "$operation_id" "$limit" "$max_file_bytes" <<'PY'
import os
import re
import stat
import sys

directory, operation_id, raw_limit, raw_max_file_bytes = sys.argv[1:]
if re.fullmatch(r"[0-9a-f]{64}", operation_id) is None:
    raise SystemExit("deterministic operation store received an invalid operation id")
try:
    limit = int(raw_limit)
    max_file_bytes = int(raw_max_file_bytes)
except ValueError:
    raise SystemExit("deterministic operation store bound is invalid")
if limit < 1 or max_file_bytes < 1:
    raise SystemExit("deterministic operation store limit is invalid")

entries = list(os.scandir(directory))
for entry in entries:
    if re.fullmatch(r"[0-9a-f]{64}\.json", entry.name) is None:
        raise SystemExit("deterministic operation store contains foreign state")
    metadata = entry.stat(follow_symlinks=False)
    mode = metadata.st_mode
    if not stat.S_ISREG(mode) or entry.is_symlink():
        raise SystemExit("deterministic operation store contains non-regular state")
    if metadata.st_size < 2 or metadata.st_size > max_file_bytes:
        raise SystemExit("deterministic operation store contains unbounded state")

target = f"{operation_id}.json"
if len(entries) > limit or (len(entries) == limit and target not in {entry.name for entry in entries}):
    raise SystemExit("deterministic operation store reached its bounded capacity")
PY
}

ensure_private_operation_store() {
  local directory="$1"
  if [ -e "$directory" ] || [ -L "$directory" ]; then
    [ -d "$directory" ] && [ ! -L "$directory" ] ||
      die "deterministic operation store is not one private directory"
  else
    install -d -m 0700 "$directory"
  fi
}

retain_completed_deterministic_mandate() {
  local incoming_artifact="$1"
  local target="$2"
  local incoming_operation="$3"
  local retained_operation="$4"
  local result_dir="$5"
  local incoming_result="$result_dir/$incoming_operation.json"
  if [ -f "$incoming_result" ] && [ ! -L "$incoming_result" ]; then
    validate_deterministic_cycle_outcome "$incoming_result" "$incoming_operation" >/dev/null ||
      die "mandate admission refused invalid retained deterministic result"
    echo "historical:$incoming_operation"
    return
  fi

  [ -n "$retained_operation" ] ||
    die "mandate admission lost the retained deterministic operation"
  local retained_result="$result_dir/$retained_operation.json"
  [ -f "$retained_result" ] && [ ! -L "$retained_result" ] ||
    die "mandate admission refused rotation before the retained cycle completed"
  validate_deterministic_cycle_outcome "$retained_result" "$retained_operation" >/dev/null ||
    die "mandate admission refused rotation after an invalid retained result"
  local replacement
  replacement="$(mktemp "$(dirname "$target")/.deterministic-order.pending.XXXXXX")"
  install -m 0600 "$incoming_artifact" "$replacement"
  mv "$replacement" "$target"
  echo "rotated:$retained_operation:$incoming_operation"
}

derive_deterministic_session_cycle_operation_id() {
  local session_operation_id="$1"
  local cycle_index="$2"
  python3 - "$session_operation_id" "$cycle_index" <<'PY'
import hashlib
import json
import re
import sys

session_operation_id, raw_cycle_index = sys.argv[1:]
if re.fullmatch(r"[0-9a-f]{64}", session_operation_id) is None:
    raise SystemExit("deterministic session id is invalid")
try:
    cycle_index = int(raw_cycle_index)
except ValueError:
    raise SystemExit("deterministic session cycle index is invalid")
if cycle_index < 0 or str(cycle_index) != raw_cycle_index:
    raise SystemExit("deterministic session cycle index is not canonical")
semantic = {
    "session_operation_id": session_operation_id,
    "cycle_index": cycle_index,
}
sys.stdout.write(hashlib.sha256(
    b"hivra:bingx-futures-remote-session-cycle:v1\n" +
    json.dumps(semantic, separators=(",", ":")).encode("utf-8")
).hexdigest())
PY
}

prepare_deterministic_session_cycle() {
  local state="$1"
  local session_operation_id="$2"
  local max_cycles="$3"
  local max_effects="$4"
  local interval_seconds="$5"
  local issued_at="$6"
  local expires_at="$7"
  local mode="${8:-cycle}"
  python3 - "$state" "$session_operation_id" "$max_cycles" "$max_effects" \
    "$interval_seconds" "$issued_at" "$expires_at" "$mode" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import re
import stat
import sys

path, session_id, raw_cycles, raw_effects, raw_interval, issued_raw, expires_raw, mode = sys.argv[1:]
hex64 = re.compile(r"[0-9a-f]{64}")
if hex64.fullmatch(session_id) is None:
    raise SystemExit("deterministic session state received an invalid session id")
try:
    max_cycles = int(raw_cycles)
    max_effects = int(raw_effects)
    interval = int(raw_interval)
except ValueError:
    raise SystemExit("deterministic session state bounds are invalid")
if not 1 <= max_cycles <= 288 or not 1 <= max_effects <= 256 or not 60 <= interval <= 3600:
    raise SystemExit("deterministic session state bounds are invalid")
if mode not in ("cycle", "activate"):
    raise SystemExit("deterministic session state mode is invalid")

def instant(raw):
    if not raw.endswith("Z"):
        raise SystemExit("deterministic session time is invalid")
    try:
        return datetime.datetime.fromisoformat(raw[:-1] + "+00:00")
    except ValueError:
        raise SystemExit("deterministic session time is invalid")

issued = instant(issued_raw)
expires = instant(expires_raw)
state_path = pathlib.Path(path)
def write_state(value):
    pending = state_path.with_name(f".{state_path.name}.pending.{os.getpid()}")
    fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(json.dumps(value, separators=(",", ":")) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(pending, state_path)
    finally:
        if pending.exists():
            pending.unlink()

expected_keys = [
    "contract_version", "session_operation_id", "next_cycle_index",
    "completed_cycles", "consumed_effects", "state",
    "last_cycle_operation_id",
]
if state_path.exists() or state_path.is_symlink():
    metadata = state_path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or state_path.is_symlink() or not 2 <= metadata.st_size <= 2048:
        raise SystemExit("deterministic session state is not one bounded regular file")
    raw = state_path.read_bytes()
    try:
        text = raw.decode("utf-8")
        value = json.loads(text)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise SystemExit("deterministic session state is not strict JSON")
    if not isinstance(value, dict) or list(value) != expected_keys:
        raise SystemExit("deterministic session state shape is invalid")
    if json.dumps(value, separators=(",", ":")) + "\n" != text:
        raise SystemExit("deterministic session state is not canonical")
else:
    if mode != "activate":
        raise SystemExit("deterministic session has not been explicitly activated")
    value = {
        "contract_version": "hivra-trading-deterministic-session-state-v1",
        "session_operation_id": session_id,
        "next_cycle_index": 0,
        "completed_cycles": 0,
        "consumed_effects": 0,
        "state": "active",
        "last_cycle_operation_id": None,
    }
    write_state(value)

if (
    value["contract_version"] != "hivra-trading-deterministic-session-state-v1"
    or value["session_operation_id"] != session_id
    or isinstance(value["next_cycle_index"], bool)
    or not isinstance(value["next_cycle_index"], int)
    or value["next_cycle_index"] < 0
    or value["next_cycle_index"] > max_cycles
    or value["completed_cycles"] != value["next_cycle_index"]
    or isinstance(value["consumed_effects"], bool)
    or not isinstance(value["consumed_effects"], int)
    or value["consumed_effects"] < 0
    or value["consumed_effects"] > max_effects
    or value["state"] not in ("active", "completed", "stopped")
):
    raise SystemExit("deterministic session state invariant failed")
index = value["next_cycle_index"]
last = value["last_cycle_operation_id"]
if index == 0:
    if last is not None:
        raise SystemExit("deterministic session initial state has a last cycle")
else:
    semantic = {"session_operation_id": session_id, "cycle_index": index - 1}
    expected_last = hashlib.sha256(
        b"hivra:bingx-futures-remote-session-cycle:v1\n" +
        json.dumps(semantic, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    if last != expected_last:
        raise SystemExit("deterministic session last cycle does not match its index")
if value["state"] == "completed" and index != max_cycles:
    raise SystemExit("deterministic session completed before its cycle bound")
now = datetime.datetime.now(datetime.timezone.utc)
if value["state"] == "active" and (
    now >= expires or value["consumed_effects"] >= max_effects
):
    value["state"] = "stopped"
    write_state(value)
if value["state"] != "active":
    print(f"terminal:{value['state']}:{index}:{value['consumed_effects']}")
    raise SystemExit(0)
if mode == "activate":
    print(f"active:{index}:{value['consumed_effects']}")
    raise SystemExit(0)
if index >= max_cycles:
    raise SystemExit("deterministic session active state exceeded its cycle bound")
if value["consumed_effects"] >= max_effects:
    raise SystemExit("deterministic session exhausted its effect bound")
eligible = issued + datetime.timedelta(seconds=interval * index)
if now < eligible:
    raise SystemExit("deterministic session next cycle is not eligible yet")
if now >= expires:
    raise SystemExit("deterministic session authority expired")
print(f"ready:{index}:{value['consumed_effects']}")
PY
}

inspect_deterministic_session_cycle() {
  local state="$1"
  local session_operation_id="$2"
  local max_cycles="$3"
  local max_effects="$4"
  python3 - "$state" "$session_operation_id" "$max_cycles" "$max_effects" <<'PY'
import json
import pathlib
import re
import stat
import sys

path, session_id, raw_cycles, raw_effects = sys.argv[1:]
state_path = pathlib.Path(path)
if not state_path.exists() or state_path.is_symlink():
    raise SystemExit("deterministic recovery requires existing session state")
metadata = state_path.lstat()
if not stat.S_ISREG(metadata.st_mode) or not 2 <= metadata.st_size <= 2048:
    raise SystemExit("deterministic recovery state is not bounded regular state")
raw = state_path.read_bytes()
try:
    text = raw.decode("utf-8")
    value = json.loads(text)
    max_cycles = int(raw_cycles)
    max_effects = int(raw_effects)
except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
    raise SystemExit("deterministic recovery state is invalid")
expected_keys = [
    "contract_version", "session_operation_id", "next_cycle_index",
    "completed_cycles", "consumed_effects", "state",
    "last_cycle_operation_id",
]
index = value.get("next_cycle_index")
consumed = value.get("consumed_effects")
if (
    not isinstance(value, dict)
    or list(value) != expected_keys
    or json.dumps(value, separators=(",", ":")) + "\n" != text
    or value.get("contract_version") != "hivra-trading-deterministic-session-state-v1"
    or value.get("session_operation_id") != session_id
    or re.fullmatch(r"[0-9a-f]{64}", session_id) is None
    or isinstance(index, bool) or not isinstance(index, int)
    or index < 0 or index > max_cycles
    or value.get("completed_cycles") != index
    or isinstance(consumed, bool) or not isinstance(consumed, int)
    or consumed < 0 or consumed > max_effects
    or value.get("state") not in ("active", "completed", "stopped")
):
    raise SystemExit("deterministic recovery state invariant failed")
last = value.get("last_cycle_operation_id")
if index == 0:
    if last is not None:
        raise SystemExit("deterministic recovery initial state has a last cycle")
else:
    import hashlib
    expected_last = hashlib.sha256(
        b"hivra:bingx-futures-remote-session-cycle:v1\n" +
        json.dumps(
            {"session_operation_id": session_id, "cycle_index": index - 1},
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()
    if last != expected_last:
        raise SystemExit("deterministic recovery last cycle is invalid")
print(f"{value['state']}:{index}:{consumed}")
PY
}

deterministic_session_scheduler_decision() {
  local session_status="$1"
  local interval_seconds="$2"
  local starts_at="$3"
  local expires_at="$4"
  local now_override="${5:-}"
  python3 - "$session_status" "$interval_seconds" "$starts_at" \
    "$expires_at" "$now_override" <<'PY'
import datetime
import math
import re
import sys

status, raw_interval, starts_raw, expires_raw, now_raw = sys.argv[1:]
match = re.fullmatch(r"(active|completed|stopped):([0-9]+):([0-9]+)", status)
if match is None:
    raise SystemExit("scheduler received invalid session status")
state, raw_index, _ = match.groups()
index = int(raw_index)
try:
    interval = int(raw_interval)
except ValueError:
    raise SystemExit("scheduler received invalid cadence")
if not 60 <= interval <= 3600:
    raise SystemExit("scheduler received invalid cadence")

def instant(raw):
    if not raw.endswith("Z"):
        raise SystemExit("scheduler received invalid time")
    try:
        return datetime.datetime.fromisoformat(raw[:-1] + "+00:00")
    except ValueError:
        raise SystemExit("scheduler received invalid time")

starts = instant(starts_raw)
expires = instant(expires_raw)
now = instant(now_raw) if now_raw else datetime.datetime.now(datetime.timezone.utc)
if starts >= expires:
    raise SystemExit("scheduler received invalid session window")
if state != "active":
    print(f"terminal:{state}:{index}")
    raise SystemExit(0)
eligible = starts + datetime.timedelta(seconds=interval * index)
if now >= expires:
    print(f"ready:{index}")
elif now >= eligible + datetime.timedelta(seconds=interval):
    print(f"stale:{index}")
elif now >= eligible:
    print(f"ready:{index}")
else:
    print(f"wait:{max(1, math.ceil((eligible - now).total_seconds()))}")
PY
}

deterministic_session_scheduler_decision_with_revocation() {
  local session_status="$1"
  local revocation_present="$2"
  local interval_seconds="$3"
  local starts_at="$4"
  local expires_at="$5"
  local now_override="${6:-}"
  case "$session_status" in
    completed:*|stopped:*)
      deterministic_session_scheduler_decision \
        "$session_status" "$interval_seconds" "$starts_at" \
        "$expires_at" "$now_override"
      ;;
    active:*)
      if [ "$revocation_present" = "true" ]; then
        echo "ready:revocation"
      elif [ "$revocation_present" = "false" ]; then
        deterministic_session_scheduler_decision \
          "$session_status" "$interval_seconds" "$starts_at" \
          "$expires_at" "$now_override"
      else
        die "scheduler received invalid revocation state"
      fi
      ;;
    *) die "scheduler received invalid session status" ;;
  esac
}

terminalize_stale_deterministic_session() {
  local state="$1"
  local session_operation_id="$2"
  [ "$(stop_deterministic_session_state "$state" "$session_operation_id")" = \
    "stopped" ] || return 1
}

advance_deterministic_session_cycle() {
  local state="$1"
  local session_operation_id="$2"
  local cycle_index="$3"
  local cycle_operation_id="$4"
  local outcome="$5"
  local max_cycles="$6"
  local max_effects="$7"
  python3 - "$state" "$session_operation_id" "$cycle_index" \
    "$cycle_operation_id" "$outcome" "$max_cycles" "$max_effects" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

path, session_id, raw_index, cycle_id, outcome, raw_cycles, raw_effects = sys.argv[1:]
index = int(raw_index)
max_cycles = int(raw_cycles)
max_effects = int(raw_effects)
state_path = pathlib.Path(path)
value = json.loads(state_path.read_text(encoding="utf-8"))
expected_cycle_id = hashlib.sha256(
    b"hivra:bingx-futures-remote-session-cycle:v1\n" +
    json.dumps(
        {"session_operation_id": session_id, "cycle_index": index},
        separators=(",", ":"),
    ).encode("utf-8")
).hexdigest()
if (
    value.get("contract_version") != "hivra-trading-deterministic-session-state-v1"
    or value.get("session_operation_id") != session_id
    or value.get("state") != "active"
    or value.get("next_cycle_index") != index
    or value.get("completed_cycles") != index
    or cycle_id != expected_cycle_id
):
    raise SystemExit("deterministic session advance refused stale state")
effect = outcome.startswith("effect:")
if not effect and not outcome.startswith("blocked:"):
    raise SystemExit("deterministic session advance received an invalid outcome")
consumed = value.get("consumed_effects")
if isinstance(consumed, bool) or not isinstance(consumed, int):
    raise SystemExit("deterministic session effect counter is invalid")
if effect:
    consumed += 1
if consumed > max_effects:
    raise SystemExit("deterministic session effect bound exceeded")
next_index = index + 1
next_state = "active"
if next_index == max_cycles:
    next_state = "completed"
elif consumed == max_effects:
    next_state = "stopped"
elif outcome.startswith("effect:unresolved:") or outcome.startswith("effect:terminal_failure:"):
    next_state = "stopped"
value = {
    "contract_version": "hivra-trading-deterministic-session-state-v1",
    "session_operation_id": session_id,
    "next_cycle_index": next_index,
    "completed_cycles": next_index,
    "consumed_effects": consumed,
    "state": next_state,
    "last_cycle_operation_id": cycle_id,
}
pending = state_path.with_name(f".{state_path.name}.pending.{os.getpid()}")
fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(json.dumps(value, separators=(",", ":")) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(pending, state_path)
finally:
    if pending.exists():
        pending.unlink()
print(f"{next_state}:{next_index}:{consumed}")
PY
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

runtime_smoke_artifact() {
  local directory="$1"
  local binary="$directory/$BINARY_NAME"
  local effect_binary="$directory/$EFFECT_BINARY_NAME"
  local manifest="$directory/$MANIFEST_NAME"
  verify_artifact "$directory" >/dev/null
  [ "$(sed -n 's/^target_os=//p' "$manifest")" = "linux" ] &&
    [ "$(sed -n 's/^target_arch=//p' "$manifest")" = "x64" ] ||
    die "runtime smoke requires a Linux x64 artifact"
  [ "$(host_os)" = "linux" ] && [ "$(host_arch)" = "x64" ] ||
    die "runtime smoke requires a Linux x64 host"

  local smoke_root
  smoke_root="$(mktemp -d)"
  local stdout_file="$smoke_root/stdout"
  local stderr_file="$smoke_root/stderr"
  if env -u HIVRA_SHADOW_RUNNER_SEED_HEX \
    "$binary" >"$stdout_file" 2>"$stderr_file"; then
    rm -rf "$smoke_root"
    die "runtime smoke accepted missing runner authority"
  fi
  [ ! -s "$stdout_file" ] || {
    rm -rf "$smoke_root"
    die "runtime smoke produced unexpected standard output"
  }
  [ "$(cat "$stderr_file")" = \
    "trading shadow probe failed: FormatException: HIVRA_SHADOW_RUNNER_SEED_HEX must be 32-byte lowercase hex" ] || {
    rm -rf "$smoke_root"
    die "runtime smoke did not reach the fail-closed probe boundary"
  }
  : >"$stdout_file"
  : >"$stderr_file"
  if "$effect_binary" >"$stdout_file" 2>"$stderr_file"; then
    rm -rf "$smoke_root"
    die "runtime smoke accepted missing exact-order authority"
  fi
  [ ! -s "$stdout_file" ] &&
    [ "$(cat "$stderr_file")" = "trading exact order failed" ] || {
    rm -rf "$smoke_root"
    die "runtime smoke did not reach the fail-closed effect boundary"
  }
  rm -rf "$smoke_root"
  echo "PASS trading-runner-artifact: Linux x64 runtime starts and rejects missing authority"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

binary_target() {
  python3 - "$1" <<'PY'
import pathlib
import struct
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()[:4096]
if len(data) >= 20 and data[:4] == b"\x7fELF" and data[4:6] == b"\x02\x01":
    machine = struct.unpack_from("<H", data, 18)[0]
    if machine == 62:
        print("linux/x64")
        raise SystemExit(0)
if len(data) >= 8 and data[:4] == b"\xcf\xfa\xed\xfe":
    cpu_type = struct.unpack_from("<I", data, 4)[0]
    if cpu_type == 0x0100000C:
        print("darwin/arm64")
        raise SystemExit(0)
    if cpu_type == 0x01000007:
        print("darwin/x64")
        raise SystemExit(0)
if len(data) >= 8 and data[:4] in {b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}:
    architecture_size = 20 if data[:4] == b"\xca\xfe\xba\xbe" else 32
    count = struct.unpack_from(">I", data, 4)[0]
    if count < 1 or count > 32 or len(data) < 8 + count * architecture_size:
        raise SystemExit("invalid universal Mach-O header")
    targets = []
    for index in range(count):
        cpu_type = struct.unpack_from(">I", data, 8 + index * architecture_size)[0]
        if cpu_type == 0x0100000C:
            targets.append("darwin/arm64")
        elif cpu_type == 0x01000007:
            targets.append("darwin/x64")
    if targets:
        print("+".join(targets))
        raise SystemExit(0)
raise SystemExit("unsupported host-native executable header")
PY
}

baseline_value() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "$BASELINE")"
  [ -n "$value" ] || die "missing baseline value: $key"
  [ "$(grep -c "^${key}=" "$BASELINE")" -eq 1 ] ||
    die "duplicate baseline value: $key"
  printf '%s\n' "$value"
}

dart_version() {
  dart --version 2>&1 | sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p'
}

host_os() {
  uname -s | tr '[:upper:]' '[:lower:]'
}

host_arch() {
  case "$(uname -m)" in
    x86_64) echo x64 ;;
    aarch64) echo arm64 ;;
    *) uname -m ;;
  esac
}

write_manifest() {
  local directory="$1"
  local source_commit="$2"
  local dart_sdk="$3"
  local target_os="$4"
  local target_arch="$5"
  local dependency_lock_sha="$6"
  local binary="$directory/$BINARY_NAME"
  local effect_binary="$directory/$EFFECT_BINARY_NAME"
  local unit="$directory/$UNIT_NAME"
  local session_unit="$directory/$SESSION_UNIT_NAME"
  local lifecycle="$directory/$LIFECYCLE_NAME"
  cat > "$directory/$MANIFEST_NAME" <<EOF
schema_version=$SCHEMA_VERSION
source_commit=$source_commit
source_tree=clean
dart_version=$dart_sdk
target_os=$target_os
target_arch=$target_arch
dependency_lock_sha256=$dependency_lock_sha
entrypoint=flutter/tool/trading_remote_shadow_probe.dart
authority_profile=$AUTHORITY_PROFILE
binary_file=$BINARY_NAME
binary_sha256=$(sha256_file "$binary")
binary_size=$(file_size "$binary")
effect_entrypoint=flutter/tool/trading_remote_exact_order.dart
effect_binary_file=$EFFECT_BINARY_NAME
effect_binary_sha256=$(sha256_file "$effect_binary")
effect_binary_size=$(file_size "$effect_binary")
unit_file=$UNIT_NAME
unit_sha256=$(sha256_file "$unit")
session_unit_file=$SESSION_UNIT_NAME
session_unit_sha256=$(sha256_file "$session_unit")
lifecycle_file=$LIFECYCLE_NAME
lifecycle_sha256=$(sha256_file "$lifecycle")
bundle_install_path=$BUNDLE_INSTALL_PATH
binary_install_path=$BINARY_INSTALL_PATH
effect_binary_install_path=$EFFECT_BINARY_INSTALL_PATH
unit_install_path=$UNIT_INSTALL_PATH
unit_link_path=$UNIT_LINK_PATH
session_unit_install_path=$SESSION_UNIT_INSTALL_PATH
session_unit_link_path=$SESSION_UNIT_LINK_PATH
lifecycle_install_path=$LIFECYCLE_INSTALL_PATH
credential_install_path=$CREDENTIAL_INSTALL_PATH
state_directory=$STATE_DIRECTORY
EOF
}

verify_artifact() {
  local directory="$1"
  local binary="$directory/$BINARY_NAME"
  local effect_binary="$directory/$EFFECT_BINARY_NAME"
  local unit="$directory/$UNIT_NAME"
  local session_unit="$directory/$SESSION_UNIT_NAME"
  local lifecycle="$directory/$LIFECYCLE_NAME"
  local manifest="$directory/$MANIFEST_NAME"
  [ -d "$directory" ] && [ ! -L "$directory" ] ||
    die "artifact directory must be a real directory"
  [ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ] ||
    die "artifact binary must be one executable regular file"
  [ -f "$effect_binary" ] && [ ! -L "$effect_binary" ] && [ -x "$effect_binary" ] ||
    die "artifact effect binary must be one executable regular file"
  [ -f "$unit" ] && [ ! -L "$unit" ] && [ ! -x "$unit" ] ||
    die "artifact unit must be one non-executable regular file"
  [ -f "$session_unit" ] && [ ! -L "$session_unit" ] && [ ! -x "$session_unit" ] ||
    die "artifact session unit must be one non-executable regular file"
  [ -f "$lifecycle" ] && [ ! -L "$lifecycle" ] && [ -x "$lifecycle" ] ||
    die "artifact lifecycle must be one executable regular file"
  [ -f "$manifest" ] && [ ! -L "$manifest" ] ||
    die "artifact manifest must be one regular file"
  [ "$(find "$directory" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')" = "6" ] ||
    die "artifact directory contains unknown entries"

  python3 - \
    "$manifest" \
    "$SCHEMA_VERSION" \
    "$AUTHORITY_PROFILE" \
    "$BINARY_NAME" \
    "$EFFECT_BINARY_NAME" \
    "$UNIT_NAME" \
    "$SESSION_UNIT_NAME" \
    "$LIFECYCLE_NAME" \
    "$BUNDLE_INSTALL_PATH" \
    "$BINARY_INSTALL_PATH" \
    "$EFFECT_BINARY_INSTALL_PATH" \
    "$UNIT_INSTALL_PATH" \
    "$UNIT_LINK_PATH" \
    "$SESSION_UNIT_INSTALL_PATH" \
    "$SESSION_UNIT_LINK_PATH" \
    "$LIFECYCLE_INSTALL_PATH" \
    "$CREDENTIAL_INSTALL_PATH" \
    "$STATE_DIRECTORY" <<'PY'
import re
import sys

(
    path,
    schema,
    authority,
    binary_name,
    effect_binary_name,
    unit_name,
    session_unit_name,
    lifecycle_name,
    bundle_install_path,
    binary_install_path,
    effect_binary_install_path,
    unit_install_path,
    unit_link_path,
    session_unit_install_path,
    session_unit_link_path,
    lifecycle_install_path,
    credential_install_path,
    state_directory,
) = sys.argv[1:]
expected = [
    "schema_version",
    "source_commit",
    "source_tree",
    "dart_version",
    "target_os",
    "target_arch",
    "dependency_lock_sha256",
    "entrypoint",
    "authority_profile",
    "binary_file",
    "binary_sha256",
    "binary_size",
    "effect_entrypoint",
    "effect_binary_file",
    "effect_binary_sha256",
    "effect_binary_size",
    "unit_file",
    "unit_sha256",
    "session_unit_file",
    "session_unit_sha256",
    "lifecycle_file",
    "lifecycle_sha256",
    "bundle_install_path",
    "binary_install_path",
    "effect_binary_install_path",
    "unit_install_path",
    "unit_link_path",
    "session_unit_install_path",
    "session_unit_link_path",
    "lifecycle_install_path",
    "credential_install_path",
    "state_directory",
]
lines = open(path, "r", encoding="utf-8").read().splitlines()
if len(lines) != len(expected):
    raise SystemExit("manifest field count mismatch")
parsed = {}
for index, line in enumerate(lines):
    if "=" not in line:
        raise SystemExit("malformed manifest line")
    key, value = line.split("=", 1)
    if key != expected[index] or not value or key in parsed:
        raise SystemExit("manifest key order or value mismatch")
    parsed[key] = value
if parsed["schema_version"] != schema:
    raise SystemExit("manifest schema mismatch")
if not re.fullmatch(r"[0-9a-f]{40}", parsed["source_commit"]):
    raise SystemExit("invalid source commit")
if parsed["source_tree"] != "clean":
    raise SystemExit("source tree is not clean")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", parsed["dart_version"]):
    raise SystemExit("invalid Dart version")
if not re.fullmatch(r"[a-z0-9._-]+", parsed["target_os"]):
    raise SystemExit("invalid target OS")
if not re.fullmatch(r"[A-Za-z0-9._-]+", parsed["target_arch"]):
    raise SystemExit("invalid target architecture")
if not re.fullmatch(r"[0-9a-f]{64}", parsed["dependency_lock_sha256"]):
    raise SystemExit("invalid dependency lock SHA-256")
if parsed["entrypoint"] != "flutter/tool/trading_remote_shadow_probe.dart":
    raise SystemExit("entrypoint mismatch")
if parsed["authority_profile"] != authority:
    raise SystemExit("authority profile mismatch")
if parsed["binary_file"] != binary_name:
    raise SystemExit("binary filename mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", parsed["binary_sha256"]):
    raise SystemExit("invalid binary SHA-256")
if not re.fullmatch(r"[1-9][0-9]*", parsed["binary_size"]):
    raise SystemExit("invalid binary size")
if parsed["effect_entrypoint"] != "flutter/tool/trading_remote_exact_order.dart":
    raise SystemExit("effect entrypoint mismatch")
if parsed["effect_binary_file"] != effect_binary_name:
    raise SystemExit("effect binary filename mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", parsed["effect_binary_sha256"]):
    raise SystemExit("invalid effect binary SHA-256")
if not re.fullmatch(r"[1-9][0-9]*", parsed["effect_binary_size"]):
    raise SystemExit("invalid effect binary size")
if parsed["unit_file"] != unit_name:
    raise SystemExit("unit filename mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", parsed["unit_sha256"]):
    raise SystemExit("invalid unit SHA-256")
if parsed["session_unit_file"] != session_unit_name:
    raise SystemExit("session unit filename mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", parsed["session_unit_sha256"]):
    raise SystemExit("invalid session unit SHA-256")
if parsed["lifecycle_file"] != lifecycle_name:
    raise SystemExit("lifecycle filename mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", parsed["lifecycle_sha256"]):
    raise SystemExit("invalid lifecycle SHA-256")
if parsed["bundle_install_path"] != bundle_install_path:
    raise SystemExit("bundle install path mismatch")
if parsed["binary_install_path"] != binary_install_path:
    raise SystemExit("binary install path mismatch")
if parsed["effect_binary_install_path"] != effect_binary_install_path:
    raise SystemExit("effect binary install path mismatch")
if parsed["unit_install_path"] != unit_install_path:
    raise SystemExit("unit install path mismatch")
if parsed["unit_link_path"] != unit_link_path:
    raise SystemExit("unit link path mismatch")
if parsed["session_unit_install_path"] != session_unit_install_path:
    raise SystemExit("session unit install path mismatch")
if parsed["session_unit_link_path"] != session_unit_link_path:
    raise SystemExit("session unit link path mismatch")
if parsed["lifecycle_install_path"] != lifecycle_install_path:
    raise SystemExit("lifecycle install path mismatch")
if parsed["credential_install_path"] != credential_install_path:
    raise SystemExit("credential install path mismatch")
if parsed["state_directory"] != state_directory:
    raise SystemExit("state directory mismatch")
PY

  local expected_sha
  local expected_size
  local expected_effect_sha
  local expected_effect_size
  local expected_lock_sha
  local expected_unit_sha
  local expected_session_unit_sha
  local expected_lifecycle_sha
  local source_commit
  local target_os
  local target_arch
  expected_sha="$(sed -n 's/^binary_sha256=//p' "$manifest")"
  expected_size="$(sed -n 's/^binary_size=//p' "$manifest")"
  expected_effect_sha="$(sed -n 's/^effect_binary_sha256=//p' "$manifest")"
  expected_effect_size="$(sed -n 's/^effect_binary_size=//p' "$manifest")"
  expected_lock_sha="$(sed -n 's/^dependency_lock_sha256=//p' "$manifest")"
  expected_unit_sha="$(sed -n 's/^unit_sha256=//p' "$manifest")"
  expected_session_unit_sha="$(sed -n 's/^session_unit_sha256=//p' "$manifest")"
  expected_lifecycle_sha="$(sed -n 's/^lifecycle_sha256=//p' "$manifest")"
  source_commit="$(sed -n 's/^source_commit=//p' "$manifest")"
  target_os="$(sed -n 's/^target_os=//p' "$manifest")"
  target_arch="$(sed -n 's/^target_arch=//p' "$manifest")"
  [ "$(sha256_file "$binary")" = "$expected_sha" ] ||
    die "artifact binary SHA-256 mismatch"
  [ "$(file_size "$binary")" = "$expected_size" ] ||
    die "artifact binary size mismatch"
  [ "$(sha256_file "$effect_binary")" = "$expected_effect_sha" ] ||
    die "artifact effect binary SHA-256 mismatch"
  [ "$(file_size "$effect_binary")" = "$expected_effect_size" ] ||
    die "artifact effect binary size mismatch"
  [ "$(sha256_file "$unit")" = "$expected_unit_sha" ] ||
    die "artifact unit SHA-256 mismatch"
  [ "$(sha256_file "$session_unit")" = "$expected_session_unit_sha" ] ||
    die "artifact session unit SHA-256 mismatch"
  [ "$(sha256_file "$lifecycle")" = "$expected_lifecycle_sha" ] ||
    die "artifact lifecycle SHA-256 mismatch"
  if [ "$INSTALLED_BUNDLE_MODE" != 1 ]; then
    cmp -s "$unit" "$UNIT_SOURCE" ||
      die "artifact unit does not match the canonical source"
    cmp -s "$session_unit" "$SESSION_UNIT_SOURCE" ||
      die "artifact session unit does not match the canonical source"
    cmp -s "$lifecycle" "$LIFECYCLE_SOURCE" ||
      die "artifact lifecycle does not match the canonical source"
    [ -f "$PACKAGE_LOCK" ] &&
      [ "$(sha256_file "$PACKAGE_LOCK")" = "$expected_lock_sha" ] ||
      die "artifact dependency lock SHA-256 mismatch"
    git -C "$ROOT" merge-base --is-ancestor "$source_commit" HEAD >/dev/null 2>&1 ||
      die "artifact source commit is not available in repository history"
  fi
  local detected_targets
  detected_targets="$(binary_target "$binary")" ||
    die "artifact is not a supported host-native executable"
  case "$target_os/$target_arch" in
    linux/x64) [[ "+$detected_targets+" = *"+linux/x64+"* ]] ||
      die "artifact binary does not match Linux x64 manifest" ;;
    darwin/arm64) [[ "+$detected_targets+" = *"+darwin/arm64+"* ]] ||
      die "artifact binary does not match Darwin arm64 manifest" ;;
    darwin/x86_64|darwin/x64) [[ "+$detected_targets+" = *"+darwin/x64+"* ]] ||
      die "artifact binary does not match Darwin x64 manifest" ;;
    *) die "artifact target is not an allowed packaging target" ;;
  esac
  local detected_effect_targets
  detected_effect_targets="$(binary_target "$effect_binary")" ||
    die "artifact effect binary is not a supported host-native executable"
  [ "$detected_effect_targets" = "$detected_targets" ] ||
    die "artifact binaries target different platforms"
  for marker in \
    'openApi/swap/v3/user/balance' \
    'openApi/swap/v2/user/positions' \
    'openApi/swap/v2/trade/openOrders' \
    'hivra-trading-account-read-evidence-v2' \
    'balance,positions,open_orders'; do
    grep -aFq "$marker" "$binary" ||
      die "artifact is missing the bounded account-read marker: $marker"
  done
  if grep -aEq \
    'openApi/swap/v2/trade/order([^s]|$)|openApi/swap/v2/trade/(leverage|marginType)|placeOrder|cancelOrder|switchLeverage|switchMarginType|ExternalEffect' \
    "$binary"; then
    die "artifact contains forbidden exchange-effect authority markers"
  fi
  for marker in \
    'openApi/swap/v2/trade/order' \
    'openApi/swap/v2/trade/order/test' \
    'hivra-trading-exact-order-evidence-v1' \
    'trading-remote-mandate-admission-v4' \
    'trading-remote-mandate-admission-v5' \
    'one_deterministic_order' \
    'bounded_deterministic_session' \
    'hivra-trading-deterministic-cycle-evidence-v1' \
    'hivra-trading-exact-order-recovery-v1'; do
    grep -aFq "$marker" "$effect_binary" ||
      die "artifact effect binary is missing exact-order marker: $marker"
  done
  if grep -aEq \
    -- '--(cancel-order|switch-leverage|switch-margin-type|withdraw|transfer)(=|[^a-z-])' \
    "$effect_binary"; then
    die "artifact effect binary exposes a forbidden widened-authority option"
  fi
  echo "PASS trading-runner-artifact: verified $directory"
}

build_artifact() {
  local output="$1"
  [[ "$output" = /* ]] || die "build output must be an absolute path"
  case "$output" in
    "$ROOT"|"$ROOT"/*) die "build output must stay outside the repository" ;;
  esac
  [ ! -e "$output" ] && [ ! -L "$output" ] ||
    die "build output already exists"
  [ -z "$(git -C "$ROOT" status --porcelain)" ] ||
    die "artifact packaging requires a completely clean worktree"
  command -v dart >/dev/null 2>&1 || die "dart is required"
  [ -f "$PACKAGE_LOCK" ] || die "pinned runner dependency lock is missing"
  local expected_dart
  expected_dart="$(baseline_value DART_VERSION)"
  [ "$(dart_version)" = "$expected_dart" ] ||
    die "Dart SDK does not match the pinned baseline"
  local target_os
  local target_arch
  local compile_target=()
  if [ -n "$TARGET_OS" ] || [ -n "$TARGET_ARCH" ]; then
    [ "$TARGET_OS" = "linux" ] && [ "$TARGET_ARCH" = "x64" ] ||
      die "the only cross-build target is linux/x64"
    target_os="$TARGET_OS"
    target_arch="$TARGET_ARCH"
    compile_target=("--target-os=$target_os" "--target-arch=$target_arch")
  else
    target_os="$(host_os)"
    target_arch="$(host_arch)"
  fi

  local parent
  local name
  parent="$(dirname "$output")"
  name="$(basename "$output")"
  [ -d "$parent" ] && [ ! -L "$parent" ] ||
    die "build output parent must be an existing real directory"
  local pending
  pending="$(mktemp -d "$parent/.${name}.pending.XXXXXX")"
  trap "rm -rf '$pending'" EXIT
  (
    cd "$PACKAGE_DIR"
    dart pub get --enforce-lockfile
  )
  python3 - \
    "$PACKAGE_DIR/.dart_tool/package_config.json" \
    "$pending/package_config.json" \
    "$FLUTTER_DIR" <<'PY'
import json
import pathlib
import sys

source, output, flutter_root = sys.argv[1:]
data = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
packages = data.get("packages")
if not isinstance(packages, list) or any(item.get("name") == "hivra_app" for item in packages):
    raise SystemExit("invalid standalone package configuration")
packages.append({
    "name": "hivra_app",
    "rootUri": pathlib.Path(flutter_root).resolve().as_uri() + "/",
    "packageUri": "lib/",
    "languageVersion": "3.7",
})
pathlib.Path(output).write_text(
    json.dumps(data, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
  (
    cd "$FLUTTER_DIR"
    dart compile exe \
      --packages="$pending/package_config.json" \
      "${compile_target[@]}" \
      "tool/trading_remote_shadow_probe.dart" \
      -o "$pending/$BINARY_NAME"
    dart compile exe \
      --packages="$pending/package_config.json" \
      "${compile_target[@]}" \
      "tool/trading_remote_exact_order.dart" \
      -o "$pending/$EFFECT_BINARY_NAME"
  )
  rm -f "$pending/package_config.json"
  chmod 700 "$pending/$BINARY_NAME"
  chmod 700 "$pending/$EFFECT_BINARY_NAME"
  cp "$UNIT_SOURCE" "$pending/$UNIT_NAME"
  chmod 600 "$pending/$UNIT_NAME"
  cp "$SESSION_UNIT_SOURCE" "$pending/$SESSION_UNIT_NAME"
  chmod 600 "$pending/$SESSION_UNIT_NAME"
  cp "$LIFECYCLE_SOURCE" "$pending/$LIFECYCLE_NAME"
  chmod 700 "$pending/$LIFECYCLE_NAME"
  write_manifest \
    "$pending" \
    "$(git -C "$ROOT" rev-parse HEAD)" \
    "$expected_dart" \
    "$target_os" \
    "$target_arch" \
    "$(sha256_file "$PACKAGE_LOCK")"
  chmod 600 "$pending/$MANIFEST_NAME"
  verify_artifact "$pending"
  mv "$pending" "$output"
  trap - EXIT
  echo "PASS trading-runner-artifact: built $output"
}

wait_for_exact_unit_evidence() {
  local since="$1"
  local expected_sequence="$2"
  local log=""
  local evidence=""
  local active_state=""
  for _ in $(seq 1 120); do
    log="$(journalctl -u "$UNIT_NAME" --since "$since" --no-pager -o cat)"
    evidence="$(printf '%s\n' "$log" |
      grep "^shadow_evidence_appended=$expected_sequence " | tail -1 || true)"
    [ -z "$evidence" ] || break
    active_state="$(systemctl show -p ActiveState --value "$UNIT_NAME")"
    [ "$active_state" != "failed" ] || {
      printf '%s\n' "$log" >&2
      die "exact unit failed before evidence sequence $expected_sequence"
    }
    sleep 1
  done
  [ -n "$evidence" ] ||
    die "exact unit produced no evidence sequence $expected_sequence"
  printf '%s\n' "$evidence"
}

current_unit_journal_cursor() {
  local cursor
  cursor="$(journalctl -u "$UNIT_NAME" -n 0 --show-cursor --no-pager |
    sed -n 's/^-- cursor: //p' | tail -1)"
  [ -n "$cursor" ] || die "could not establish exact unit journal cursor"
  printf '%s\n' "$cursor"
}

wait_for_unit_evidence_after_cursor() {
  local cursor="$1"
  local log=""
  local evidence=""
  local active_state=""
  for _ in $(seq 1 120); do
    log="$(journalctl -u "$UNIT_NAME" --after-cursor="$cursor" --no-pager -o cat)"
    evidence="$(printf '%s\n' "$log" |
      grep '^shadow_evidence_appended=[1-9][0-9]* ' | tail -1 || true)"
    [ -z "$evidence" ] || break
    active_state="$(systemctl show -p ActiveState --value "$UNIT_NAME")"
    [ "$active_state" != "failed" ] || {
      printf '%s\n' "$log" >&2
      die "exact unit failed before identity evidence"
    }
    sleep 1
  done
  [ -n "$evidence" ] || die "exact unit produced no identity evidence"
  printf '%s\n' "$evidence"
}

require_install_host() {
  local directory="$1"
  verify_artifact "$directory" >/dev/null
  [ "$(sed -n 's/^target_os=//p' "$directory/$MANIFEST_NAME")" = "linux" ] &&
    [ "$(sed -n 's/^target_arch=//p' "$directory/$MANIFEST_NAME")" = "x64" ] ||
    die "host lifecycle requires a Linux x64 bundle"
  [ "$(host_os)" = "linux" ] && [ "$(host_arch)" = "x64" ] ||
    die "host lifecycle requires a Linux x64 host"
  [ "$(id -u)" = "0" ] || die "host lifecycle requires root"
  command -v flock >/dev/null 2>&1 || die "flock is required"
  command -v openssl >/dev/null 2>&1 || die "openssl is required"
  command -v systemctl >/dev/null 2>&1 || die "systemctl is required"
  command -v systemd-creds >/dev/null 2>&1 || die "systemd-creds is required"
}

require_expected_runner_key_id() {
  printf '%s' "$EXPECTED_RUNNER_KEY_ID" |
    grep -Eq '^[0-9a-f]{64}$' ||
    die "expected runner key id must be 64 lowercase hex characters"
}

require_exact_installed_bundle() {
  local directory="$1"
  require_install_host "$directory"
  local state_private="/var/lib/private/hivra-trading-public-shadow"
  [ -d "$BUNDLE_INSTALL_PATH" ] && [ ! -L "$BUNDLE_INSTALL_PATH" ] ||
    die "host lifecycle requires the canonical real bundle directory"
  verify_artifact "$BUNDLE_INSTALL_PATH" >/dev/null
  cmp -s "$BINARY_INSTALL_PATH" "$directory/$BINARY_NAME" ||
    die "host lifecycle refused a drifted runner binary"
  cmp -s "$EFFECT_BINARY_INSTALL_PATH" "$directory/$EFFECT_BINARY_NAME" ||
    die "host lifecycle refused a drifted effect binary"
  cmp -s "$UNIT_INSTALL_PATH" "$directory/$UNIT_NAME" ||
    die "host lifecycle refused a drifted runner unit"
  cmp -s "$SESSION_UNIT_INSTALL_PATH" "$directory/$SESSION_UNIT_NAME" ||
    die "host lifecycle refused a drifted session unit"
  cmp -s "$LIFECYCLE_INSTALL_PATH" "$directory/$LIFECYCLE_NAME" ||
    die "host lifecycle refused a drifted lifecycle owner"
  cmp -s "$BUNDLE_INSTALL_PATH/$MANIFEST_NAME" "$directory/$MANIFEST_NAME" ||
    die "host lifecycle refused a drifted runner manifest"
  [ -L "$UNIT_LINK_PATH" ] &&
    [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ] ||
    die "host lifecycle refused a foreign unit link"
  [ -L "$SESSION_UNIT_LINK_PATH" ] &&
    [ "$(readlink "$SESSION_UNIT_LINK_PATH")" = "$SESSION_UNIT_INSTALL_PATH" ] ||
    die "host lifecycle refused a foreign session unit link"
  [ -f "$CREDENTIAL_INSTALL_PATH" ] && [ ! -L "$CREDENTIAL_INSTALL_PATH" ] ||
    die "host lifecycle refused a foreign credential"
  if [ -e "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    [ -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ]; then
    [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
      [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
      die "host lifecycle refused a foreign exchange credential"
  fi
  if [ -L "$STATE_DIRECTORY" ]; then
    [ "$(readlink -f "$STATE_DIRECTORY")" = "$state_private" ] ||
      die "host lifecycle refused a foreign state link"
  elif [ -e "$STATE_DIRECTORY" ]; then
    [ -d "$STATE_DIRECTORY" ] || die "host lifecycle refused foreign state"
  fi
  systemctl cat "$UNIT_NAME" >/dev/null 2>&1 ||
    die "host lifecycle requires the exact loaded unit"
  systemctl cat "$SESSION_UNIT_NAME" >/dev/null 2>&1 ||
    die "host lifecycle requires the exact loaded session unit"
}

read_installed_runner_key_id() {
  local identity="$STATE_DIRECTORY/stream/stream_identity.v1.json"
  python3 - "$identity" <<'PY'
import json
import os
import pathlib
import re
import stat
import sys

path = pathlib.Path(sys.argv[1])
try:
    metadata = os.lstat(path)
except FileNotFoundError:
    raise SystemExit("runner identity is not initialized")
if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 1024:
    raise SystemExit("runner identity is not one bounded regular file")
try:
    value = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("runner identity is invalid")
if (
    not isinstance(value, dict)
    or set(value) != {"schema_version", "runner_key_id"}
    or value["schema_version"] != 1
    or not isinstance(value["runner_key_id"], str)
    or re.fullmatch(r"[0-9a-f]{64}", value["runner_key_id"]) is None
):
    raise SystemExit("runner identity is invalid")
print(value["runner_key_id"])
PY
}

evidence_runner_key_id() {
  printf '%s\n' "$1" |
    sed -n 's/.* runner_key_id=\([0-9a-f]\{64\}\) .*/\1/p'
}

initialize_disabled() {
  local directory="$1"
  require_exact_installed_bundle "$directory"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  trap "systemctl stop '$UNIT_NAME' >/dev/null 2>&1 || true; rm -f '$lock_path'" EXIT INT TERM

  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "disabled initialization refused an enabled unit" ;;
  esac
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "disabled initialization refused boot enablement"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "disabled initialization requires an inactive unit"

  local journal_cursor
  journal_cursor="$(current_unit_journal_cursor)"
  systemctl start "$UNIT_NAME"
  local evidence
  evidence="$(wait_for_unit_evidence_after_cursor "$journal_cursor")"
  [ "$(systemctl show -p NRestarts --value "$UNIT_NAME")" = "0" ] ||
    die "disabled initialization used an implicit supervisor restart"
  local evidence_key_id
  local installed_key_id
  evidence_key_id="$(evidence_runner_key_id "$evidence")"
  installed_key_id="$(read_installed_runner_key_id)"
  [ -n "$evidence_key_id" ] && [ "$evidence_key_id" = "$installed_key_id" ] ||
    die "disabled initialization produced inconsistent identity evidence"
  systemctl stop "$UNIT_NAME"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "disabled initialization did not stop"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "disabled initialization changed enablement" ;;
  esac
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "disabled initialization created boot enablement"

  trap - EXIT INT TERM
  rm -f "$lock_path"
  exec 9>&-
  printf '%s\n' "$evidence"
  echo "PASS trading-runner-artifact: initialized disabled runner_key_id=$installed_key_id"
}

provision_disabled() {
  local directory="$1"
  [ -n "$ANCHOR_OUTPUT" ] && [ "${ANCHOR_OUTPUT#/}" != "$ANCHOR_OUTPUT" ] ||
    die "disabled provisioning requires one absolute anchor output path"
  [ ! -e "$ANCHOR_OUTPUT" ] && [ ! -L "$ANCHOR_OUTPUT" ] ||
    die "disabled provisioning anchor output already exists"

  "$0" --install-disabled "$directory"
  rollback_disabled_provisioning() {
    "$0" --uninstall-disabled "$directory" >/dev/null 2>&1 || true
    die "$1"
  }
  if ! "$0" --initialize-disabled "$directory"; then
    rollback_disabled_provisioning \
      "disabled provisioning failed during identity initialization"
  fi
  local runner_key_id
  if ! runner_key_id="$(read_installed_runner_key_id)"; then
    rollback_disabled_provisioning \
      "disabled provisioning could not read initialized identity"
  fi
  if ! "$0" --export-anchor "$directory" \
    --expected-runner-key-id "$runner_key_id" \
    --anchor-output "$ANCHOR_OUTPUT"; then
    rollback_disabled_provisioning \
      "disabled provisioning failed during anchor export"
  fi
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) rollback_disabled_provisioning \
      "disabled provisioning changed unit enablement" ;;
  esac
  if [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" != "inactive" ]; then
    rollback_disabled_provisioning \
      "disabled provisioning left the runner active"
  fi
  echo "PASS trading-runner-artifact: provisioned disabled runner_key_id=$runner_key_id anchor=$ANCHOR_OUTPUT effect=false"
}

activate_identity_bound() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  rollback_identity_bound_activation() {
    set +e
    systemctl stop "$UNIT_NAME" >/dev/null 2>&1
    if [ -L "$wants_path" ] &&
      [ "$(readlink -f "$wants_path")" = "$UNIT_INSTALL_PATH" ]; then
      unlink "$wants_path"
      systemctl daemon-reload >/dev/null 2>&1
    fi
    rm -f "$lock_path"
  }
  trap rollback_identity_bound_activation EXIT INT TERM

  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "identity-bound activation requires a disabled unit" ;;
  esac
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "identity-bound activation refused pre-existing boot enablement"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "identity-bound activation requires an inactive unit"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "identity-bound activation refused the installed runner key id"

  local journal_cursor
  journal_cursor="$(current_unit_journal_cursor)"
  systemctl start "$UNIT_NAME"
  local evidence
  evidence="$(wait_for_unit_evidence_after_cursor "$journal_cursor")"
  [ "$(evidence_runner_key_id "$evidence")" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "identity-bound activation observed a different runner key id"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "active" ] ||
    die "identity-bound activation did not remain active"
  [ "$(systemctl show -p NRestarts --value "$UNIT_NAME")" = "0" ] ||
    die "identity-bound activation used an implicit supervisor restart"

  systemctl enable "$UNIT_NAME" >/dev/null
  [ "$(systemctl is-enabled "$UNIT_NAME")" = "enabled" ] ||
    die "identity-bound activation did not enable the exact unit"
  [ -L "$wants_path" ] &&
    [ "$(readlink -f "$wants_path")" = "$UNIT_INSTALL_PATH" ] ||
    die "identity-bound activation created an unexpected boot link"

  trap - EXIT INT TERM
  rm -f "$lock_path"
  exec 9>&-
  printf '%s\n' "$evidence"
  echo "PASS trading-runner-artifact: activated runner_key_id=$EXPECTED_RUNNER_KEY_ID"
}

deactivate_identity_bound() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  trap "rm -f '$lock_path'" EXIT INT TERM

  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "identity-bound deactivation refused the installed runner key id"
  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  if [ -e "$wants_path" ] || [ -L "$wants_path" ]; then
    [ -L "$wants_path" ] &&
      [ "$(readlink -f "$wants_path")" = "$UNIT_INSTALL_PATH" ] ||
      die "identity-bound deactivation refused an unexpected boot link"
    unlink "$wants_path"
  else
    [ "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" != "enabled" ] ||
      die "identity-bound deactivation found inconsistent enablement"
  fi
  systemctl daemon-reload
  systemctl stop "$UNIT_NAME"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "identity-bound deactivation left the unit enabled" ;;
  esac
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "identity-bound deactivation left the unit active"
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "identity-bound deactivation retained boot enablement"
  [ -L "$UNIT_LINK_PATH" ] &&
    [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ] ||
    die "identity-bound deactivation changed the canonical unit link"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "identity-bound deactivation changed runner identity"

  trap - EXIT INT TERM
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: deactivated runner_key_id=$EXPECTED_RUNNER_KEY_ID"
}

export_external_anchor() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ -n "$ANCHOR_OUTPUT" ] && [ "${ANCHOR_OUTPUT#/}" != "$ANCHOR_OUTPUT" ] ||
    die "anchor output must be one absolute path"
  [ ! -e "$ANCHOR_OUTPUT" ] && [ ! -L "$ANCHOR_OUTPUT" ] ||
    die "anchor output already exists"
  local output_parent
  local output_name
  output_parent="$(dirname "$ANCHOR_OUTPUT")"
  output_name="$(basename "$ANCHOR_OUTPUT")"
  [ -d "$output_parent" ] && [ ! -L "$output_parent" ] ||
    die "anchor output parent must be one real directory"
  [ "$output_name" != "." ] && [ "$output_name" != ".." ] ||
    die "anchor output name is invalid"

  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  pending_anchor=""
  rollback_anchor_export() {
    set +e
    [ -z "$pending_anchor" ] || rm -rf "$pending_anchor"
    rm -f "$lock_path"
  }
  trap rollback_anchor_export EXIT INT TERM
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "anchor export refused the installed runner key id"

  local log_line
  log_line="$(journalctl -u "$UNIT_NAME" --no-pager -o cat |
    grep "^shadow_evidence_appended=[1-9][0-9]* runner_key_id=$EXPECTED_RUNNER_KEY_ID " |
    tail -1 || true)"
  [ -n "$log_line" ] || die "anchor export found no matching runner evidence"
  local sequence
  local public_key_hex
  local evidence_hash
  sequence="$(printf '%s\n' "$log_line" |
    sed -n 's/^shadow_evidence_appended=\([1-9][0-9]*\) .*/\1/p')"
  public_key_hex="$(printf '%s\n' "$log_line" |
    sed -n 's/.* runner_public_key_hex=\([0-9a-f]\{64\}\) .*/\1/p')"
  evidence_hash="$(printf '%s\n' "$log_line" |
    sed -n 's/.* evidence_hash=\([0-9a-f]\{64\}\) .*/\1/p')"
  [ -n "$sequence" ] && [ "$sequence" -le 999999999999 ] &&
    [ -n "$public_key_hex" ] && [ -n "$evidence_hash" ] ||
    die "anchor export found malformed runner evidence metadata"
  python3 - "$public_key_hex" "$EXPECTED_RUNNER_KEY_ID" <<'PY'
import hashlib
import re
import sys

public_key_hex, expected_key_id = sys.argv[1:]
if re.fullmatch(r"[0-9a-f]{64}", public_key_hex) is None:
    raise SystemExit("invalid runner public key")
if hashlib.sha256(bytes.fromhex(public_key_hex)).hexdigest() != expected_key_id:
    raise SystemExit("runner public key does not match expected key id")
PY

  local evidence_name
  local evidence_path
  local evidence_size
  evidence_name="$(printf '%012d-%s.json' "$sequence" "$evidence_hash")"
  evidence_path="$STATE_DIRECTORY/stream/evidence/$evidence_name"
  [ -f "$evidence_path" ] && [ ! -L "$evidence_path" ] ||
    die "anchor export requires one committed evidence file"
  evidence_size="$(file_size "$evidence_path")"
  [ "$evidence_size" -ge 1 ] && [ "$evidence_size" -le 8192 ] ||
    die "anchor export requires one bounded committed evidence file"

  pending_anchor="$(mktemp -d "$output_parent/.${output_name}.pending.XXXXXX")"
  printf '%s\n' "$public_key_hex" > \
    "$pending_anchor/runner-public-key.ed25519.hex"
  install -m 0600 "$evidence_path" "$pending_anchor/shadow-evidence.v1.json"
  chmod 0700 "$pending_anchor"
  [ "$(find "$pending_anchor" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')" = 2 ] ||
    die "anchor export staged unexpected entries"
  mv "$pending_anchor" "$ANCHOR_OUTPUT"
  pending_anchor=""

  trap - EXIT INT TERM
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: exported untrusted anchor sequence=$sequence runner_key_id=$EXPECTED_RUNNER_KEY_ID evidence_hash=$evidence_hash"
}

verify_remote_mandate_artifact() {
  local source="$1"
  local expected_runner_key_id="$2"
  local work="$3"
  [ -f "$source" ] && [ ! -L "$source" ] ||
    die "mandate artifact must be one regular file"
  local size
  size="$(file_size "$source")"
  [ "$size" -ge 1 ] && [ "$size" -le 8192 ] ||
    die "mandate artifact must contain bounded bytes"
  if ! python3 - "$source" "$expected_runner_key_id" "$work" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import sys

source, expected_runner_key_id, work = sys.argv[1:]
raw = pathlib.Path(source).read_bytes()
try:
    text = raw.decode("utf-8")
    value = json.loads(text)
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("mandate artifact is not strict UTF-8 JSON")
version = value.get("contract_version") if isinstance(value, dict) else None
is_account_read = version == "trading-remote-mandate-admission-v2"
is_exact_order = version == "trading-remote-mandate-admission-v3"
is_deterministic_order = version == "trading-remote-mandate-admission-v4"
is_deterministic_session = version == "trading-remote-mandate-admission-v5"
if not is_account_read and not is_exact_order and not is_deterministic_order and not is_deterministic_session:
    raise SystemExit("mandate contract version mismatch")
expected_root = [
    "contract_version", "operation_id", "commitment_hash_hex",
    "runner_key_id", "operation_kind",
    *( ["read_scope"] if is_account_read else ["exact_order"] if is_exact_order else ["strategy_policy", "session_policy"] if is_deterministic_session else ["strategy_policy"] ),
    "max_uses", "mandate", "signature_suite", "signature_hex",
]
expected_mandate = [
    "version", "mandate_id", "capsule_root_hex", "account_binding_hash_hex",
    "symbol", "test_order", "issued_at_utc", "expires_at_utc",
    "max_order_notional_quote_decimal", "max_risk_per_trade_percent",
    "max_daily_loss_percent", "max_concurrent_positions",
    "cooldown_after_loss_streak", "cooldown_minutes", "max_effects",
    "revoked_at_utc",
]
if not isinstance(value, dict) or list(value) != expected_root:
    raise SystemExit("mandate artifact root shape is not canonical")
mandate = value.get("mandate")
if not isinstance(mandate, dict) or list(mandate) != expected_mandate:
    raise SystemExit("mandate shape is not canonical")
if json.dumps(value, separators=(",", ":"), ensure_ascii=False) != text:
    raise SystemExit("mandate artifact bytes are not canonical")
if value["signature_suite"] != "ed25519-v1":
    raise SystemExit("mandate signature suite mismatch")
if not is_deterministic_session and value["max_uses"] != 1:
    raise SystemExit("mandate account-read use bound mismatch" if is_account_read else "mandate order use bound mismatch")
if is_account_read:
    if value["operation_kind"] != "account_read":
        raise SystemExit("mandate operation kind mismatch")
    if value["read_scope"] != ["balance", "positions", "open_orders"]:
        raise SystemExit("mandate account-read scope mismatch")
elif is_exact_order:
    if value["operation_kind"] != "one_exact_order":
        raise SystemExit("mandate operation kind mismatch")
    expected_order = [
        "client_order_id", "symbol", "side", "order_type",
        "quantity_decimal", "limit_price_decimal", "time_in_force",
        "entry_mode", "trigger_price_decimal", "stop_loss_decimal",
        "take_profit_decimal", "intent_hash_hex", "test_order",
    ]
    exact_order = value.get("exact_order")
    if not isinstance(exact_order, dict) or list(exact_order) != expected_order:
        raise SystemExit("exact order shape is not canonical")
    if (
        re.fullmatch(r"[A-Za-z0-9_-]{1,40}", str(exact_order["client_order_id"])) is None
        or exact_order["symbol"] != mandate["symbol"]
        or exact_order["side"] not in ("buy", "sell")
        or exact_order["order_type"] != "limit"
        or exact_order["entry_mode"] != "zone_pending"
        or exact_order["time_in_force"] != "GTC"
        or exact_order["test_order"] is not mandate["test_order"]
        or not isinstance(exact_order["intent_hash_hex"], str)
        or re.fullmatch(r"[0-9a-f]{64}", exact_order["intent_hash_hex"]) is None
    ):
        raise SystemExit("exact order authority is not bounded")
    decimal = re.compile(r"(?:0|[1-9][0-9]*)(?:\.[0-9]{1,8})?")
    for key in ("quantity_decimal", "limit_price_decimal", "trigger_price_decimal"):
        if not isinstance(exact_order[key], str) or decimal.fullmatch(exact_order[key]) is None or float(exact_order[key]) <= 0:
            raise SystemExit(f"invalid exact order {key}")
    for key in ("stop_loss_decimal", "take_profit_decimal"):
        if exact_order[key] is not None and (
            not isinstance(exact_order[key], str)
            or decimal.fullmatch(exact_order[key]) is None
            or float(exact_order[key]) <= 0
        ):
            raise SystemExit(f"invalid exact order {key}")
    if float(exact_order["quantity_decimal"]) * float(exact_order["limit_price_decimal"]) > float(mandate["max_order_notional_quote_decimal"]):
        raise SystemExit("exact order exceeds mandate notional")
else:
    expected_kind = "bounded_deterministic_session" if is_deterministic_session else "one_deterministic_order"
    if value["operation_kind"] != expected_kind:
        raise SystemExit("mandate operation kind mismatch")
    policy = value.get("strategy_policy")
    expected_policy = [
        "runner_build_id", "plugin_id", "plugin_version",
        "package_digest_hex", "host_abi", "stop_loss_percent",
        "minimum_risk_reward",
    ]
    if not isinstance(policy, dict) or list(policy) != expected_policy:
        raise SystemExit("deterministic strategy policy is not canonical")
    policy_text = re.compile(r"[A-Za-z0-9._:-]{1,128}")
    for key in ("runner_build_id", "plugin_id", "plugin_version", "host_abi"):
        if not isinstance(policy[key], str) or policy_text.fullmatch(policy[key]) is None:
            raise SystemExit(f"invalid deterministic policy {key}")
    if not isinstance(policy["package_digest_hex"], str) or re.fullmatch(r"[0-9a-f]{64}", policy["package_digest_hex"]) is None:
        raise SystemExit("invalid deterministic package digest")
    for key in ("stop_loss_percent", "minimum_risk_reward"):
        number = policy[key]
        if isinstance(number, bool) or not isinstance(number, (int, float)) or number <= 0:
            raise SystemExit(f"invalid deterministic policy {key}")
    if is_deterministic_session:
        session = value.get("session_policy")
        if not isinstance(session, dict) or list(session) != ["starts_at_utc", "interval_seconds", "max_cycles", "stop_on_failure"]:
            raise SystemExit("deterministic session policy is not canonical")
        interval = session["interval_seconds"]
        cycles = session["max_cycles"]
        if (
            isinstance(interval, bool) or not isinstance(interval, int)
            or interval < 60 or interval > 3600
            or isinstance(cycles, bool) or not isinstance(cycles, int)
            or cycles < 1 or cycles > 288
            or session["stop_on_failure"] is not True
            or value["max_uses"] != cycles
        ):
            raise SystemExit("deterministic session bound is invalid")
if value["runner_key_id"] != expected_runner_key_id:
    raise SystemExit("mandate runner binding mismatch")
hex64 = re.compile(r"[0-9a-f]{64}")
hex128 = re.compile(r"[0-9a-f]{128}")
for key in ("operation_id", "commitment_hash_hex", "runner_key_id"):
    if not isinstance(value[key], str) or hex64.fullmatch(value[key]) is None:
        raise SystemExit(f"invalid {key}")
if value["operation_id"] != value["commitment_hash_hex"]:
    raise SystemExit("operation id is not the semantic commitment")
if not isinstance(value["signature_hex"], str) or hex128.fullmatch(value["signature_hex"]) is None:
    raise SystemExit("invalid signature")
if mandate["version"] != 1 or mandate["revoked_at_utc"] is not None:
    raise SystemExit("mandate is not admissible")
if not isinstance(mandate["test_order"], bool):
    raise SystemExit("mandate mode is invalid")
for key in ("capsule_root_hex", "account_binding_hash_hex", "mandate_id"):
    if not isinstance(mandate[key], str) or hex64.fullmatch(mandate[key]) is None:
        raise SystemExit(f"invalid mandate {key}")
if not isinstance(mandate["symbol"], str) or re.fullmatch(r"[A-Z0-9-]{1,32}", mandate["symbol"]) is None:
    raise SystemExit("invalid mandate symbol")
decimal_value = mandate["max_order_notional_quote_decimal"]
if (
    not isinstance(decimal_value, str)
    or re.fullmatch(r"(?:0|[1-9][0-9]*)(?:\.[0-9]{1,8})?", decimal_value) is None
    or float(decimal_value) <= 0
):
    raise SystemExit("invalid mandate notional")
for key in ("max_risk_per_trade_percent", "max_daily_loss_percent"):
    number = mandate[key]
    if isinstance(number, bool) or not isinstance(number, (int, float)) or number <= 0:
        raise SystemExit(f"invalid mandate {key}")
integer_bounds = {
    "max_concurrent_positions": (1, None),
    "cooldown_after_loss_streak": (1, None),
    "cooldown_minutes": (0, None),
    "max_effects": (1, 256),
}
for key, (minimum, maximum) in integer_bounds.items():
    number = mandate[key]
    if (
        isinstance(number, bool)
        or not isinstance(number, int)
        or number < minimum
        or (maximum is not None and number > maximum)
    ):
        raise SystemExit(f"invalid mandate {key}")
semantic = {key: mandate[key] for key in expected_mandate[2:-1]}
mandate_id = hashlib.sha256(
    b"hivra:bingx-futures-trading-mandate:v1\n" +
    json.dumps(semantic, separators=(",", ":")).encode("utf-8")
).hexdigest()
if mandate["mandate_id"] != mandate_id:
    raise SystemExit("mandate semantic id mismatch")
commitment_semantic = {
    "contract_version": value["contract_version"],
    "runner_key_id": value["runner_key_id"],
    "operation_kind": value["operation_kind"],
    **({"read_scope": value["read_scope"]} if is_account_read else {"exact_order": value["exact_order"]} if is_exact_order else {"strategy_policy": value["strategy_policy"], "session_policy": value["session_policy"]} if is_deterministic_session else {"strategy_policy": value["strategy_policy"]}),
    "max_uses": value["max_uses"],
    "mandate": mandate,
}
commitment = hashlib.sha256(
    (b"hivra:bingx-futures-remote-mandate-admission:v2\n" if is_account_read else b"hivra:bingx-futures-remote-mandate-admission:v3\n" if is_exact_order else b"hivra:bingx-futures-remote-mandate-admission:v5\n" if is_deterministic_session else b"hivra:bingx-futures-remote-mandate-admission:v4\n") +
    json.dumps(commitment_semantic, separators=(",", ":")).encode("utf-8")
).hexdigest()
if value["commitment_hash_hex"] != commitment:
    raise SystemExit("mandate commitment mismatch")
def instant(name):
    raw_value = mandate[name]
    if not isinstance(raw_value, str) or not raw_value.endswith("Z"):
        raise SystemExit(f"invalid mandate {name}")
    try:
        return datetime.datetime.fromisoformat(raw_value[:-1] + "+00:00")
    except ValueError:
        raise SystemExit(f"invalid mandate {name}")
issued = instant("issued_at_utc")
expires = instant("expires_at_utc")
if expires <= issued or expires - issued > datetime.timedelta(hours=24):
    raise SystemExit("mandate time bounds are invalid")
if is_deterministic_session:
    raw_starts = value["session_policy"]["starts_at_utc"]
    if not isinstance(raw_starts, str) or not raw_starts.endswith("Z"):
        raise SystemExit("deterministic session start is invalid")
    try:
        starts = datetime.datetime.fromisoformat(raw_starts[:-1] + "+00:00")
    except ValueError:
        raise SystemExit("deterministic session start is invalid")
    final_cycle = starts + datetime.timedelta(
        seconds=value["session_policy"]["interval_seconds"] *
        (value["session_policy"]["max_cycles"] - 1)
    )
    if starts < issued or starts >= expires or final_cycle >= expires:
        raise SystemExit("deterministic session exceeds mandate time bounds")
pathlib.Path(work, "digest.bin").write_bytes(bytes.fromhex(commitment))
pathlib.Path(work, "signature.bin").write_bytes(bytes.fromhex(value["signature_hex"]))
pathlib.Path(work, "capsule-public-key.der").write_bytes(
    bytes.fromhex("302a300506032b6570032100" + mandate["capsule_root_hex"])
)
pathlib.Path(work, "operation-id").write_text(value["operation_id"], encoding="ascii")
pathlib.Path(work, "account-binding").write_text(
    mandate["account_binding_hash_hex"], encoding="ascii"
)
pathlib.Path(work, "capsule-root").write_text(
    mandate["capsule_root_hex"], encoding="ascii"
)
pathlib.Path(work, "issued-at").write_text(mandate["issued_at_utc"], encoding="ascii")
pathlib.Path(work, "expires-at").write_text(mandate["expires_at_utc"], encoding="ascii")
pathlib.Path(work, "operation-kind").write_text(value["operation_kind"], encoding="ascii")
if is_account_read:
    pathlib.Path(work, "read-scope").write_text(
        ",".join(value["read_scope"]), encoding="ascii"
    )
elif is_exact_order:
    pathlib.Path(work, "effect-operation-id").write_text(
        value["exact_order"]["intent_hash_hex"], encoding="ascii"
    )
    pathlib.Path(work, "exact-order.json").write_text(
        json.dumps(value["exact_order"], separators=(",", ":")), encoding="utf-8"
    )
else:
    pathlib.Path(work, "strategy-policy.json").write_text(
        json.dumps(value["strategy_policy"], separators=(",", ":")), encoding="utf-8"
    )
    pathlib.Path(work, "mandate-symbol").write_text(
        mandate["symbol"], encoding="ascii"
    )
    for key in (
        "runner_build_id", "plugin_id", "plugin_version",
        "package_digest_hex", "host_abi",
    ):
        pathlib.Path(work, f"policy-{key.replace('_', '-')}").write_text(
            str(value["strategy_policy"][key]), encoding="ascii"
        )
    if is_deterministic_session:
        pathlib.Path(work, "session-starts-at").write_text(
            value["session_policy"]["starts_at_utc"], encoding="ascii"
        )
        pathlib.Path(work, "session-interval-seconds").write_text(
            str(value["session_policy"]["interval_seconds"]), encoding="ascii"
        )
        pathlib.Path(work, "session-max-cycles").write_text(
            str(value["session_policy"]["max_cycles"]), encoding="ascii"
        )
pathlib.Path(work, "max-uses").write_text(str(value["max_uses"]), encoding="ascii")
pathlib.Path(work, "mandate-max-effects").write_text(
    str(mandate["max_effects"]), encoding="ascii"
)
PY
  then
    die "mandate semantic validation failed"
  fi
  openssl pkeyutl -verify -pubin \
    -inkey "$work/capsule-public-key.der" -keyform DER -rawin \
    -in "$work/digest.bin" -sigfile "$work/signature.bin" >/dev/null 2>&1 ||
    die "mandate Capsule signature is invalid"
}

verify_remote_session_revocation_artifact() {
  local source="$1"
  local expected_runner_key_id="$2"
  local expected_session_operation_id="$3"
  local expected_capsule_root="$4"
  local work="$5"
  [ -f "$source" ] && [ ! -L "$source" ] ||
    die "session revocation artifact must be one regular file"
  local size
  size="$(file_size "$source")"
  [ "$size" -ge 1 ] && [ "$size" -le 2048 ] ||
    die "session revocation artifact must contain bounded bytes"
  python3 - "$source" "$expected_runner_key_id" \
    "$expected_session_operation_id" "$expected_capsule_root" "$work" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import sys

source, expected_runner, expected_session, expected_capsule, work = sys.argv[1:]
raw = pathlib.Path(source).read_bytes()
try:
    text = raw.decode("utf-8")
    value = json.loads(text)
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("session revocation is not strict UTF-8 JSON")
keys = [
    "contract_version", "revocation_id", "target_session_operation_id",
    "runner_key_id", "capsule_root_hex", "revoked_at_utc",
    "signature_suite", "signature_hex",
]
if not isinstance(value, dict) or list(value) != keys:
    raise SystemExit("session revocation shape is not canonical")
if json.dumps(value, separators=(",", ":"), ensure_ascii=False) != text:
    raise SystemExit("session revocation bytes are not canonical")
hex64 = re.compile(r"[0-9a-f]{64}")
hex128 = re.compile(r"[0-9a-f]{128}")
for key in ("revocation_id", "target_session_operation_id", "runner_key_id", "capsule_root_hex"):
    if not isinstance(value[key], str) or hex64.fullmatch(value[key]) is None:
        raise SystemExit(f"invalid session revocation {key}")
if value["signature_suite"] != "ed25519-v1" or hex128.fullmatch(str(value["signature_hex"])) is None:
    raise SystemExit("invalid session revocation signature")
if value["contract_version"] != "trading-remote-session-revocation-v1":
    raise SystemExit("session revocation contract mismatch")
if value["runner_key_id"] != expected_runner:
    raise SystemExit("session revocation runner mismatch")
if value["target_session_operation_id"] != expected_session:
    raise SystemExit("session revocation target mismatch")
if value["capsule_root_hex"] != expected_capsule:
    raise SystemExit("session revocation Capsule mismatch")
raw_time = value["revoked_at_utc"]
if not isinstance(raw_time, str) or not raw_time.endswith("Z"):
    raise SystemExit("session revocation time is invalid")
try:
    revoked = datetime.datetime.fromisoformat(raw_time[:-1] + "+00:00")
except ValueError:
    raise SystemExit("session revocation time is invalid")
if revoked > datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=5):
    raise SystemExit("session revocation time is in the future")
semantic = {
    "contract_version": value["contract_version"],
    "target_session_operation_id": value["target_session_operation_id"],
    "runner_key_id": value["runner_key_id"],
    "capsule_root_hex": value["capsule_root_hex"],
    "revoked_at_utc": value["revoked_at_utc"],
}
commitment = hashlib.sha256(
    b"hivra:bingx-futures-remote-session-revocation:v1\n" +
    json.dumps(semantic, separators=(",", ":")).encode("utf-8")
).hexdigest()
if value["revocation_id"] != commitment:
    raise SystemExit("session revocation commitment mismatch")
root = pathlib.Path(work)
(root / "revocation-digest.bin").write_bytes(bytes.fromhex(commitment))
(root / "revocation-signature.bin").write_bytes(bytes.fromhex(value["signature_hex"]))
(root / "revocation-capsule-public-key.der").write_bytes(
    bytes.fromhex("302a300506032b6570032100" + value["capsule_root_hex"])
)
(root / "revocation-id").write_text(commitment, encoding="ascii")
PY
  openssl pkeyutl -verify -pubin \
    -inkey "$work/revocation-capsule-public-key.der" -keyform DER -rawin \
    -in "$work/revocation-digest.bin" \
    -sigfile "$work/revocation-signature.bin" >/dev/null 2>&1 ||
    die "session revocation Capsule signature is invalid"
}

stop_deterministic_session_state() {
  local state="$1"
  local session_operation_id="$2"
  python3 - "$state" "$session_operation_id" <<'PY'
import hashlib
import json
import os
import pathlib
import re
import stat
import sys

path = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
keys = [
    "contract_version", "session_operation_id", "next_cycle_index",
    "completed_cycles", "consumed_effects", "state",
    "last_cycle_operation_id",
]
if path.exists() or path.is_symlink():
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or not 2 <= metadata.st_size <= 2048:
        raise SystemExit("session revocation refused invalid session state")
    text = path.read_text(encoding="utf-8")
    value = json.loads(text)
    if not isinstance(value, dict) or list(value) != keys or json.dumps(value, separators=(",", ":")) + "\n" != text:
        raise SystemExit("session revocation refused non-canonical state")
    if value.get("contract_version") != "hivra-trading-deterministic-session-state-v1" or value.get("session_operation_id") != session_id:
        raise SystemExit("session revocation refused mismatched state")
    index = value.get("next_cycle_index")
    completed = value.get("completed_cycles")
    consumed = value.get("consumed_effects")
    state = value.get("state")
    last = value.get("last_cycle_operation_id")
    if (
        isinstance(index, bool) or not isinstance(index, int) or index < 0
        or completed != index
        or isinstance(consumed, bool) or not isinstance(consumed, int) or consumed < 0
        or state not in ("active", "completed", "stopped")
    ):
        raise SystemExit("session revocation refused invalid state invariant")
    if index == 0:
        if last is not None:
            raise SystemExit("session revocation refused invalid initial state")
    else:
        expected_last = hashlib.sha256(
            b"hivra:bingx-futures-remote-session-cycle:v1\n" +
            json.dumps(
                {"session_operation_id": session_id, "cycle_index": index - 1},
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        if not isinstance(last, str) or re.fullmatch(r"[0-9a-f]{64}", last) is None or last != expected_last:
            raise SystemExit("session revocation refused invalid cycle lineage")
    if value.get("state") == "active":
        value["state"] = "stopped"
else:
    value = {
        "contract_version": "hivra-trading-deterministic-session-state-v1",
        "session_operation_id": session_id,
        "next_cycle_index": 0,
        "completed_cycles": 0,
        "consumed_effects": 0,
        "state": "stopped",
        "last_cycle_operation_id": None,
    }
pending = path.with_name(f".{path.name}.pending.{os.getpid()}")
fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(json.dumps(value, separators=(",", ":")) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(pending, path)
finally:
    if pending.exists():
        pending.unlink()
print(value["state"])
PY
}

require_remote_mandate_execution_eligible() {
  local verified_work="$1"
  python3 - "$verified_work/issued-at" "$verified_work/expires-at" <<'PY'
import datetime
import pathlib
import sys

def instant(path):
    raw = pathlib.Path(path).read_text(encoding="ascii")
    if not raw.endswith("Z"):
        raise SystemExit("mandate execution time is invalid")
    try:
        return datetime.datetime.fromisoformat(raw[:-1] + "+00:00")
    except ValueError:
        raise SystemExit("mandate execution time is invalid")

issued = instant(sys.argv[1])
expires = instant(sys.argv[2])
now = datetime.datetime.now(datetime.timezone.utc)
if now < issued or now >= expires:
    raise SystemExit("mandate is not currently eligible for execution")
PY
}

admit_remote_mandate() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ -n "$MANDATE_ARTIFACT" ] && [ "${MANDATE_ARTIFACT#/}" != "$MANDATE_ARTIFACT" ] ||
    die "mandate artifact path must be absolute"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "mandate admission refused the installed runner key id"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work
  work="$(mktemp -d)"
  trap "rm -rf '$work'; rm -f '$lock_path'" EXIT INT TERM
  install -m 0600 "$MANDATE_ARTIFACT" "$work/input.json"
  verify_remote_mandate_artifact \
    "$work/input.json" "$EXPECTED_RUNNER_KEY_ID" "$work"
  local target_dir="$STATE_DIRECTORY/mandates"
  local legacy_target="$target_dir/prepared.v1.json"
  local operation_kind
  operation_kind="$(cat "$work/operation-kind")"
  local target
  case "$operation_kind" in
    account_read) target="$target_dir/prepared.v2.json" ;;
    one_exact_order) target="$target_dir/exact-order.v3.json" ;;
    one_deterministic_order|bounded_deterministic_session)
      target="$target_dir/deterministic-order.v4.json"
      ;;
    *) die "mandate admission produced an unsupported operation kind" ;;
  esac
  if [ -e "$target_dir" ] || [ -L "$target_dir" ]; then
    [ -d "$target_dir" ] && [ ! -L "$target_dir" ] ||
      die "mandate admission refused foreign state directory"
  else
    install -d -m 0700 "$target_dir"
  fi
  [ ! -e "$legacy_target" ] && [ ! -L "$legacy_target" ] ||
    die "mandate admission refused legacy account-read authority"
  if [ -e "$target" ] || [ -L "$target" ]; then
    [ -f "$target" ] && [ ! -L "$target" ] ||
      die "mandate admission refused foreign retained state"
    if cmp -s "$work/input.json" "$target"; then
      echo "PASS trading-runner-artifact: exact remote mandate replay is idempotent"
    elif [ "$operation_kind" = "one_deterministic_order" ] ||
      [ "$operation_kind" = "bounded_deterministic_session" ]; then
      local incoming_operation retained_operation result_dir observation_dir retained_result
      incoming_operation="$(cat "$work/operation-id")"
      result_dir="$STATE_DIRECTORY/deterministic-results"
      observation_dir="$STATE_DIRECTORY/deterministic-observations"
      ensure_private_operation_store "$result_dir"
      ensure_private_operation_store "$observation_dir"
      validate_deterministic_operation_store \
        "$result_dir" "$incoming_operation" "$DETERMINISTIC_HISTORY_LIMIT" 2048 ||
        die "mandate admission refused invalid deterministic result history"
      validate_deterministic_operation_store "$observation_dir" "$incoming_operation" ||
        die "mandate admission refused invalid deterministic observation history"

      retained_result="$result_dir/$incoming_operation.json"
      if [ -f "$retained_result" ] && [ ! -L "$retained_result" ]; then
        retain_completed_deterministic_mandate \
          "$work/input.json" "$target" "$incoming_operation" "" "$result_dir" \
          >/dev/null
        echo "PASS trading-runner-artifact: historical deterministic mandate replay is idempotent operation_id=$incoming_operation"
      else
        mkdir "$work/retained"
        verify_remote_mandate_artifact \
          "$target" "$EXPECTED_RUNNER_KEY_ID" "$work/retained"
        local retained_kind
        retained_kind="$(cat "$work/retained/operation-kind")"
        if [ "$retained_kind" = "bounded_deterministic_session" ]; then
          local session_state="$STATE_DIRECTORY/deterministic-session.v1.json"
          [ -f "$session_state" ] && [ ! -L "$session_state" ] ||
            die "mandate admission refused rotation before the retained session started"
          local session_status
          session_status="$(prepare_deterministic_session_cycle \
            "$session_state" "$(cat "$work/retained/operation-id")" \
            "$(cat "$work/retained/session-max-cycles")" \
            "$(cat "$work/retained/mandate-max-effects")" \
            "$(cat "$work/retained/session-interval-seconds")" \
            "$(cat "$work/retained/session-starts-at")" \
            "$(cat "$work/retained/expires-at")")" ||
            die "mandate admission refused invalid retained session state"
          case "$session_status" in
            terminal:completed:*|terminal:stopped:*) ;;
            *) die "mandate admission refused rotation before the retained session completed" ;;
          esac
        elif [ "$retained_kind" != "one_deterministic_order" ]; then
          die "mandate admission refused a deterministic mandate over another authority kind"
        fi
        retained_operation="$(cat "$work/retained/operation-id")"
        if [ "$retained_kind" = "one_deterministic_order" ]; then
          retain_completed_deterministic_mandate \
            "$work/input.json" "$target" "$incoming_operation" \
            "$retained_operation" "$result_dir" >/dev/null
        else
          local replacement
          replacement="$(mktemp "$target_dir/.deterministic-order.pending.XXXXXX")"
          install -m 0600 "$work/input.json" "$replacement"
          mv "$replacement" "$target"
          rm -f "$STATE_DIRECTORY/deterministic-session.v1.json"
        fi
        echo "PASS trading-runner-artifact: rotated completed deterministic mandate previous_operation_id=$retained_operation operation_id=$incoming_operation effect=false"
      fi
    else
      die "mandate admission refused conflicting retained authority"
    fi
  else
    local pending
    pending="$(mktemp "$target_dir/.prepared.pending.XXXXXX")"
    install -m 0600 "$work/input.json" "$pending"
    mv "$pending" "$target"
    echo "PASS trading-runner-artifact: admitted one prepared remote mandate operation_id=$(cat "$work/operation-id") runner_key_id=$EXPECTED_RUNNER_KEY_ID operation_kind=$operation_kind effect=false"
  fi
  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
}

revoke_remote_session() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ -n "$REVOCATION_ARTIFACT" ] &&
    [ "${REVOCATION_ARTIFACT#/}" != "$REVOCATION_ARTIFACT" ] ||
    die "session revocation artifact path must be absolute"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "session revocation refused the installed runner key id"
  local mandate="$STATE_DIRECTORY/mandates/deterministic-order.v4.json"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "session revocation requires one prepared deterministic authority"

  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work
  work="$(mktemp -d)"
  trap "rm -rf '$work'; rm -f '$lock_path'" EXIT INT TERM
  mkdir "$work/admission" "$work/revocation"
  verify_remote_mandate_artifact \
    "$mandate" "$EXPECTED_RUNNER_KEY_ID" "$work/admission"
  [ "$(cat "$work/admission/operation-kind")" = \
    "bounded_deterministic_session" ] ||
    die "session revocation requires bounded session authority"
  local session_operation_id capsule_root
  session_operation_id="$(cat "$work/admission/operation-id")"
  capsule_root="$(cat "$work/admission/capsule-root")"
  verify_remote_session_revocation_artifact \
    "$REVOCATION_ARTIFACT" "$EXPECTED_RUNNER_KEY_ID" \
    "$session_operation_id" "$capsule_root" "$work/revocation"

  local revocation_dir="$STATE_DIRECTORY/revocations"
  if [ -e "$revocation_dir" ] || [ -L "$revocation_dir" ]; then
    [ -d "$revocation_dir" ] && [ ! -L "$revocation_dir" ] ||
      die "session revocation refused foreign state directory"
  else
    install -d -m 0700 "$revocation_dir"
  fi
  [ -z "$(find "$revocation_dir" -mindepth 1 -maxdepth 1 \
    \( ! -type f -o -type l \) -print -quit)" ] ||
    die "session revocation refused invalid retained history"
  [ -z "$(find "$revocation_dir" -mindepth 1 -maxdepth 1 \
    -type f \( -size 0 -o -size +2048c \) -print -quit)" ] ||
    die "session revocation refused unbounded retained evidence"
  local revocation_count
  revocation_count="$(find "$revocation_dir" -mindepth 1 -maxdepth 1 \
    -type f | wc -l | tr -d '[:space:]')"
  [ "$revocation_count" -le "$DETERMINISTIC_HISTORY_LIMIT" ] ||
    die "session revocation history exceeds its bound"
  local retained="$revocation_dir/$session_operation_id.json"
  if [ -e "$retained" ] || [ -L "$retained" ]; then
    [ -f "$retained" ] && [ ! -L "$retained" ] &&
      cmp -s "$REVOCATION_ARTIFACT" "$retained" ||
      die "session revocation refused conflicting retained evidence"
  else
    [ "$revocation_count" -lt "$DETERMINISTIC_HISTORY_LIMIT" ] ||
      die "session revocation history is full"
    local pending
    pending="$(mktemp "$revocation_dir/.revocation.pending.XXXXXX")"
    install -m 0600 "$REVOCATION_ARTIFACT" "$pending"
    mv "$pending" "$retained"
  fi
  local terminal_state
  terminal_state="$(stop_deterministic_session_state \
    "$STATE_DIRECTORY/deterministic-session.v1.json" \
    "$session_operation_id")" ||
    die "session revocation could not stop its exact state"
  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: revoked exact deterministic session session_operation_id=$session_operation_id state=$terminal_state effect=false"
}

provision_exchange_credential() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "credential provisioning refused the installed runner key id"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "credential provisioning requires an inactive runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "credential provisioning requires a disabled runner" ;;
  esac

  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work pending
  work="$(mktemp -d /run/hivra-trading-credential.XXXXXX)"
  pending=""
  trap '
    rm -rf "$work"
    [ -z "$pending" ] || rm -f "$pending"
    rm -f "$lock_path"
  ' EXIT INT TERM

  local mandate
  if [ -n "$MANDATE_ARTIFACT" ]; then
    [ "${MANDATE_ARTIFACT#/}" != "$MANDATE_ARTIFACT" ] &&
      [ -f "$MANDATE_ARTIFACT" ] && [ ! -L "$MANDATE_ARTIFACT" ] ||
      die "credential provisioning mandate artifact must be one absolute regular file"
    mandate="$MANDATE_ARTIFACT"
  elif [ -f "$STATE_DIRECTORY/mandates/deterministic-order.v4.json" ] &&
    [ ! -L "$STATE_DIRECTORY/mandates/deterministic-order.v4.json" ]; then
    mandate="$STATE_DIRECTORY/mandates/deterministic-order.v4.json"
  elif [ -f "$STATE_DIRECTORY/mandates/exact-order.v3.json" ] &&
    [ ! -L "$STATE_DIRECTORY/mandates/exact-order.v3.json" ]; then
    mandate="$STATE_DIRECTORY/mandates/exact-order.v3.json"
  else
    mandate="$STATE_DIRECTORY/mandates/prepared.v2.json"
  fi
  [ ! -e "$STATE_DIRECTORY/mandates/prepared.v1.json" ] &&
    [ ! -L "$STATE_DIRECTORY/mandates/prepared.v1.json" ] ||
    die "credential provisioning refused legacy account-read authority"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "credential provisioning requires one prepared mandate"
  install -m 0600 "$mandate" "$work/mandate.json"
  verify_remote_mandate_artifact \
    "$work/mandate.json" "$EXPECTED_RUNNER_KEY_ID" "$work"

  local credential_json
  if [ -t 0 ]; then
    local api_key api_secret
    IFS= read -r -s -p "BingX API key: " api_key
    IFS= read -r -s -p "BingX API secret: " api_secret
    printf '\n' >&2
    credential_json="$(
      printf '%s\n%s\n' "$api_key" "$api_secret" |
        canonicalize_exchange_credential_input
    )"
    unset api_key api_secret
  else
    credential_json="$(canonicalize_exchange_credential_input)"
  fi

  local account_hash expected_account_hash credential_hash
  account_hash="$(printf '%s' "$credential_json" | exchange_credential_account_hash)"
  expected_account_hash="$(python3 - "$work/mandate.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["mandate"]["account_binding_hash_hex"])
PY
)"
  exchange_credential_matches_account_binding \
    "$credential_json" "$expected_account_hash" || {
    unset credential_json
    die "credential provisioning refused the mandate account binding"
  }
  credential_hash="$(printf '%s' "$credential_json" | sha256_stdin)"

  if [ -e "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    [ -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ]; then
    [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
      [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] || {
      unset credential_json
      die "credential provisioning refused foreign retained state"
    }
    local retained_hash
    retained_hash="$(
      systemd-creds decrypt --name=bingx-exchange \
        "$EXCHANGE_CREDENTIAL_INSTALL_PATH" - 2>/dev/null | sha256_stdin
    )" || {
      unset credential_json
      die "credential provisioning could not verify retained state"
    }
    unset credential_json
    [ "$retained_hash" = "$credential_hash" ] ||
      die "credential provisioning refused conflicting retained credential"
    echo "PASS trading-runner-artifact: exact prepared exchange credential replay is idempotent account_binding_hash=$account_hash effect=false"
  else
    pending="$(mktemp /etc/credstore.encrypted/.hivra-bingx.pending.XXXXXX)"
    printf '%s' "$credential_json" |
      systemd-creds encrypt --name=bingx-exchange - "$pending" >/dev/null
    unset credential_json
    chmod 0600 "$pending"
    mv "$pending" "$EXCHANGE_CREDENTIAL_INSTALL_PATH"
    pending=""
    echo "PASS trading-runner-artifact: provisioned one mandate-bound prepared exchange credential account_binding_hash=$account_hash effect=false"
  fi

  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
}

apply_prepared_session() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ -n "$MANDATE_ARTIFACT" ] &&
    [ "${MANDATE_ARTIFACT#/}" != "$MANDATE_ARTIFACT" ] &&
    [ -f "$MANDATE_ARTIFACT" ] && [ ! -L "$MANDATE_ARTIFACT" ] ||
    die "prepared session must be one absolute regular file"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "prepared-session apply refused the installed runner key id"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "prepared-session apply requires an inactive runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "prepared-session apply requires a disabled runner" ;;
  esac

  local work
  work="$(mktemp -d)"
  trap "rm -rf '$work'" EXIT INT TERM
  install -m 0600 "$MANDATE_ARTIFACT" "$work/input.json"
  verify_remote_mandate_artifact \
    "$work/input.json" "$EXPECTED_RUNNER_KEY_ID" "$work"
  [ "$(cat "$work/operation-kind")" = "bounded_deterministic_session" ] ||
    die "prepared-session apply requires bounded deterministic session authority"
  require_remote_mandate_execution_eligible "$work"
  trap - EXIT INT TERM
  rm -rf "$work"

  "$0" --provision-exchange-credential "$directory" \
    --expected-runner-key-id "$EXPECTED_RUNNER_KEY_ID" \
    --mandate-artifact "$MANDATE_ARTIFACT"
  if ! "$0" --admit-mandate "$directory" \
    --expected-runner-key-id "$EXPECTED_RUNNER_KEY_ID" \
    --mandate-artifact "$MANDATE_ARTIFACT"; then
    die "prepared-session admission failed; the account-bound credential remains prepared but inert"
  fi
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "prepared-session apply activated the runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "prepared-session apply enabled the runner" ;;
  esac
  echo "PASS trading-runner-artifact: applied one prepared session runner_key_id=$EXPECTED_RUNNER_KEY_ID activation=false scheduler=false effect=false"
}

activate_prepared_session() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "prepared session activation refused the installed runner key id"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "prepared session activation requires an inactive public-shadow runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "prepared session activation requires a disabled public-shadow runner" ;;
  esac
  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "prepared session activation refused boot enablement"

  local mandate="$STATE_DIRECTORY/mandates/deterministic-order.v4.json"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "prepared session activation requires one retained signed session"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work
  work="$(mktemp -d /run/hivra-trading-session-activation.XXXXXX)"
  trap "rm -rf '$work'; rm -f '$lock_path'" EXIT INT TERM
  mkdir "$work/verified"
  verify_remote_mandate_artifact \
    "$mandate" "$EXPECTED_RUNNER_KEY_ID" "$work/verified"
  [ "$(cat "$work/verified/operation-kind")" = \
    "bounded_deterministic_session" ] ||
    die "prepared session activation requires bounded session authority"
  require_remote_mandate_execution_eligible "$work/verified"
  local session_id
  session_id="$(cat "$work/verified/operation-id")"
  local retained_revocation="$STATE_DIRECTORY/revocations/$session_id.json"
  [ ! -e "$retained_revocation" ] && [ ! -L "$retained_revocation" ] ||
    die "prepared session activation refused a revoked session"
  require_retained_exchange_credential_binding \
    "$(cat "$work/verified/account-binding")"

  local session_status
  session_status="$(prepare_deterministic_session_cycle \
    "$STATE_DIRECTORY/deterministic-session.v1.json" "$session_id" \
    "$(cat "$work/verified/session-max-cycles")" \
    "$(cat "$work/verified/mandate-max-effects")" \
    "$(cat "$work/verified/session-interval-seconds")" \
    "$(cat "$work/verified/session-starts-at")" \
    "$(cat "$work/verified/expires-at")" activate)" ||
    die "prepared session activation could not create canonical state"
  case "$session_status" in
    active:*) ;;
    *) die "prepared session activation refused terminal session state" ;;
  esac
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "prepared session activation started the public-shadow runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "prepared session activation enabled the public-shadow runner" ;;
  esac

  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: activated prepared session session_operation_id=$session_id state=$session_status scheduler=false effect=false"
}

run_prepared_session_scheduler() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "prepared session scheduler refused the installed runner key id"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "prepared session scheduler requires an inactive public-shadow runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "prepared session scheduler requires a disabled public-shadow runner" ;;
  esac
  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "prepared session scheduler refused boot enablement"
  local mandate="$STATE_DIRECTORY/mandates/deterministic-order.v4.json"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "prepared session scheduler requires one retained signed session"

  local scheduler_lock="/run/lock/hivra-trading-deterministic-scheduler.lock"
  exec 8>"$scheduler_lock"
  flock -n 8 || die "another deterministic session scheduler is active"
  local work
  work="$(mktemp -d /run/hivra-trading-session-scheduler.XXXXXX)"
  trap "rm -rf '$work'" EXIT INT TERM
  mkdir "$work/verified"
  verify_remote_mandate_artifact \
    "$mandate" "$EXPECTED_RUNNER_KEY_ID" "$work/verified"
  [ "$(cat "$work/verified/operation-kind")" = \
    "bounded_deterministic_session" ] ||
    die "prepared session scheduler requires bounded session authority"
  require_retained_exchange_credential_binding \
    "$(cat "$work/verified/account-binding")"
  local session_id session_max_cycles mandate_max_effects interval_seconds
  local session_starts_at expires_at
  session_id="$(cat "$work/verified/operation-id")"
  session_max_cycles="$(cat "$work/verified/session-max-cycles")"
  mandate_max_effects="$(cat "$work/verified/mandate-max-effects")"
  interval_seconds="$(cat "$work/verified/session-interval-seconds")"
  session_starts_at="$(cat "$work/verified/session-starts-at")"
  expires_at="$(cat "$work/verified/expires-at")"
  trap - EXIT INT TERM
  rm -rf "$work"

  echo "PASS trading-runner-artifact: prepared session scheduler started session_operation_id=$session_id foreground=true serial=true"
  while true; do
    local retained_revocation="$STATE_DIRECTORY/revocations/$session_id.json"
    local decision revocation_present session_status
    revocation_present="false"
    if [ -e "$retained_revocation" ] || [ -L "$retained_revocation" ]; then
      revocation_present="true"
    fi
    session_status="$(inspect_deterministic_session_cycle \
      "$STATE_DIRECTORY/deterministic-session.v1.json" "$session_id" \
      "$session_max_cycles" "$mandate_max_effects")" ||
      die "prepared session scheduler refused invalid canonical state"
    decision="$(deterministic_session_scheduler_decision_with_revocation \
      "$session_status" "$revocation_present" "$interval_seconds" \
      "$session_starts_at" "$expires_at")" ||
      die "prepared session scheduler could not evaluate signed cadence"
    case "$decision" in
      terminal:*)
        exec 8>&-
        echo "PASS trading-runner-artifact: prepared session scheduler stopped session_operation_id=$session_id status=$decision effect_repeated=false"
        return
        ;;
      wait:*)
        local wait_seconds="${decision#wait:}"
        [ "$wait_seconds" -le 5 ] || wait_seconds=5
        sleep "$wait_seconds"
        ;;
      ready:*)
        SCHEDULER_SESSION_OPERATION_ID="$session_id"
        execute_deterministic_order_once "$directory"
        SCHEDULER_SESSION_OPERATION_ID=""
        ;;
      stale:*)
        terminalize_stale_deterministic_session \
          "$STATE_DIRECTORY/deterministic-session.v1.json" "$session_id" ||
          die "prepared session scheduler could not stop a stale session"
        die "prepared session scheduler refused a missed signed cycle window"
        ;;
      *) die "prepared session scheduler received an invalid decision" ;;
    esac
  done
}

run_installed_prepared_session() {
  [ "$INSTALLED_BUNDLE_MODE" = 1 ] ||
    die "installed session mode requires the installed lifecycle owner"
  [ "$0" = "$LIFECYCLE_INSTALL_PATH" ] ||
    die "installed session mode refused a non-canonical lifecycle path"
  ARTIFACT_DIR="$BUNDLE_INSTALL_PATH"
  EXPECTED_RUNNER_KEY_ID="$(read_installed_runner_key_id)"
  run_prepared_session_scheduler "$ARTIFACT_DIR"
}

enable_prepared_session_service() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "session service refused the installed runner key id"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "session service requires an inactive public-shadow runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "session service requires a disabled public-shadow runner" ;;
  esac
  case "$(systemctl is-enabled "$SESSION_UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "session service refused unexpected existing enablement" ;;
  esac
  local mandate="$STATE_DIRECTORY/mandates/deterministic-order.v4.json"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "session service requires one retained signed session"
  local work
  work="$(mktemp -d /run/hivra-trading-session-service.XXXXXX)"
  rollback_session_service_enablement() {
    systemctl stop "$SESSION_UNIT_NAME" >/dev/null 2>&1 || true
    remove_session_boot_enablement >/dev/null 2>&1 || true
  }
  trap "rm -rf '$work'; rollback_session_service_enablement" EXIT INT TERM
  mkdir "$work/verified"
  verify_remote_mandate_artifact \
    "$mandate" "$EXPECTED_RUNNER_KEY_ID" "$work/verified"
  [ "$(cat "$work/verified/operation-kind")" = "bounded_deterministic_session" ] ||
    die "session service requires bounded session authority"
  require_remote_mandate_execution_eligible "$work/verified"
  require_retained_exchange_credential_binding \
    "$(cat "$work/verified/account-binding")"
  local session_id
  session_id="$(cat "$work/verified/operation-id")"
  [ ! -e "$STATE_DIRECTORY/revocations/$session_id.json" ] &&
    [ ! -L "$STATE_DIRECTORY/revocations/$session_id.json" ] ||
    die "session service refused a revoked session"
  systemctl start "$SESSION_UNIT_NAME"
  [ "$(systemctl show -p ActiveState --value "$SESSION_UNIT_NAME")" = "active" ] ||
    die "session service did not remain active after validation"
  systemctl enable "$SESSION_UNIT_NAME" >/dev/null
  [ "$(systemctl is-enabled "$SESSION_UNIT_NAME")" = "enabled" ] ||
    die "session service did not become boot-enabled"
  trap - EXIT INT TERM
  rm -rf "$work"
  echo "PASS trading-runner-artifact: persistent session service enabled session_operation_id=$session_id restart=false"
}

pause_prepared_session_service() {
  local directory="$1"
  require_exact_installed_bundle "$directory"
  systemctl stop "$SESSION_UNIT_NAME" >/dev/null 2>&1 || true
  remove_session_boot_enablement
  local recovery_action
  recovery_action="$(session_service_pause_recovery_action \
    "$(systemctl show -p ActiveState --value "$SESSION_UNIT_NAME")")" ||
    die "session service did not stop"
  if [ "$recovery_action" = "reset-failed" ]; then
    systemctl reset-failed "$SESSION_UNIT_NAME" >/dev/null ||
      die "session service failed state could not be cleared"
  fi
  [ "$(systemctl show -p ActiveState --value "$SESSION_UNIT_NAME")" = "inactive" ] ||
    die "session service did not stop"
  case "$(systemctl is-enabled "$SESSION_UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "session service remained boot-enabled" ;;
  esac
  echo "PASS trading-runner-artifact: persistent session service paused signed_session_unchanged=true"
}

prepared_session_service_status() {
  local directory="$1"
  require_exact_installed_bundle "$directory"
  local active enabled runner_key
  active="$(systemctl show -p ActiveState --value "$SESSION_UNIT_NAME")"
  enabled="$(systemctl is-enabled "$SESSION_UNIT_NAME" 2>/dev/null || true)"
  runner_key="$(read_installed_runner_key_id)"
  printf 'session_unit=%s active=%s enabled=%s runner_key_id=%s restart=no\n' \
    "$SESSION_UNIT_NAME" "$active" "$enabled" "$runner_key"
}

validate_account_read_evidence() {
  local source="$1"
  local expected_operation="$2"
  local expected_runner="$3"
  local expected_account="$4"
  python3 - "$source" "$expected_operation" "$expected_runner" "$expected_account" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import sys

source, expected_operation, expected_runner, expected_account = sys.argv[1:]
raw = pathlib.Path(source).read_bytes()
if len(raw) < 2 or len(raw) > 2048 or not raw.endswith(b"\n") or raw.endswith(b"\n\n"):
    raise SystemExit("account-read evidence is not one bounded line")
try:
    text = raw[:-1].decode("utf-8")
    value = json.loads(text)
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("account-read evidence is not strict UTF-8 JSON")
expected_keys = [
    "contract_version", "account_read_operation_id", "runner_key_id",
    "account_binding_hash_hex", "read_scope", "max_uses",
    "observed_at_utc", "checks", "effect",
]
if not isinstance(value, dict) or list(value) != expected_keys:
    raise SystemExit("account-read evidence root shape is not canonical")
if json.dumps(value, separators=(",", ":"), ensure_ascii=False) != text:
    raise SystemExit("account-read evidence bytes are not canonical")
if value["contract_version"] != "hivra-trading-account-read-evidence-v2":
    raise SystemExit("account-read evidence version mismatch")
hex64 = re.compile(r"[0-9a-f]{64}")
for key, expected in (
    ("account_read_operation_id", expected_operation),
    ("runner_key_id", expected_runner),
    ("account_binding_hash_hex", expected_account),
):
    if not isinstance(value[key], str) or hex64.fullmatch(value[key]) is None or value[key] != expected:
        raise SystemExit(f"account-read evidence {key} mismatch")
if value["read_scope"] != ["balance", "positions", "open_orders"] or value["max_uses"] != 1:
    raise SystemExit("account-read evidence authority mismatch")
try:
    observed = datetime.datetime.fromisoformat(value["observed_at_utc"].replace("Z", "+00:00"))
except (AttributeError, ValueError):
    raise SystemExit("account-read evidence time is invalid")
if observed.tzinfo is None or observed.utcoffset() != datetime.timedelta(0):
    raise SystemExit("account-read evidence time is not UTC")
if value["checks"] != [
    {"name": "balance", "success": True},
    {"name": "positions", "success": True},
    {"name": "open_orders", "success": True},
] or value["effect"] is not False:
    raise SystemExit("account-read evidence is incomplete or effectful")
print(hashlib.sha256(text.encode("utf-8")).hexdigest())
PY
}

write_account_read_operation_journal() {
  local target="$1"
  local operation_id="$2"
  local runner_key_id="$3"
  local account_binding="$4"
  local state="$5"
  local evidence_source="${6:-}"
  python3 - "$target" "$operation_id" "$runner_key_id" \
    "$account_binding" "$state" "$evidence_source" <<'PY'
import json
import os
import pathlib
import re
import sys

target, operation_id, runner_key_id, account_binding, state, evidence_source = sys.argv[1:]
hex64 = re.compile(r"[0-9a-f]{64}")
if any(hex64.fullmatch(value) is None for value in (operation_id, runner_key_id, account_binding)):
    raise SystemExit("account-read journal binding is invalid")
if state not in ("pending", "completed"):
    raise SystemExit("account-read journal state is invalid")
evidence = None
if state == "completed":
    raw = pathlib.Path(evidence_source).read_bytes()
    if not raw.endswith(b"\n") or raw.endswith(b"\n\n"):
        raise SystemExit("account-read journal evidence is not one line")
    evidence = json.loads(raw[:-1].decode("utf-8"))
elif evidence_source:
    raise SystemExit("pending account-read journal cannot contain evidence")
value = {
    "contract_version": "hivra-trading-account-read-operation-v1",
    "operation_id": operation_id,
    "runner_key_id": runner_key_id,
    "account_binding_hash_hex": account_binding,
    "read_scope": ["balance", "positions", "open_orders"],
    "max_uses": 1,
    "state": state,
    "evidence": evidence,
}
with open(target, "xb") as output:
    output.write(json.dumps(value, separators=(",", ":")).encode("utf-8"))
    output.flush()
    os.fsync(output.fileno())
PY
}

validate_account_read_operation_journal() {
  local source="$1"
  local expected_operation="$2"
  local expected_runner="$3"
  local expected_account="$4"
  local evidence_output="$5"
  python3 - "$source" "$expected_operation" "$expected_runner" \
    "$expected_account" "$evidence_output" <<'PY'
import json
import os
import pathlib
import re
import sys

source, expected_operation, expected_runner, expected_account, evidence_output = sys.argv[1:]
path = pathlib.Path(source)
if path.is_symlink() or not path.is_file():
    raise SystemExit("account-read journal is not one regular file")
raw = path.read_bytes()
if len(raw) < 2 or len(raw) > 16384:
    raise SystemExit("account-read journal bytes are not bounded")
try:
    text = raw.decode("utf-8")
    value = json.loads(text)
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("account-read journal is not strict UTF-8 JSON")
expected_keys = [
    "contract_version", "operation_id", "runner_key_id",
    "account_binding_hash_hex", "read_scope", "max_uses", "state", "evidence",
]
if not isinstance(value, dict) or list(value) != expected_keys:
    raise SystemExit("account-read journal root shape is not canonical")
if json.dumps(value, separators=(",", ":")) != text:
    raise SystemExit("account-read journal bytes are not canonical")
if value["contract_version"] != "hivra-trading-account-read-operation-v1":
    raise SystemExit("account-read journal version mismatch")
hex64 = re.compile(r"[0-9a-f]{64}")
for key, expected in (
    ("operation_id", expected_operation),
    ("runner_key_id", expected_runner),
    ("account_binding_hash_hex", expected_account),
):
    if not isinstance(value[key], str) or hex64.fullmatch(value[key]) is None or value[key] != expected:
        raise SystemExit(f"account-read journal {key} mismatch")
if value["read_scope"] != ["balance", "positions", "open_orders"] or value["max_uses"] != 1:
    raise SystemExit("account-read journal authority mismatch")
state = value["state"]
if state == "pending":
    if value["evidence"] is not None:
        raise SystemExit("pending account-read journal contains evidence")
elif state == "completed":
    if not isinstance(value["evidence"], dict):
        raise SystemExit("completed account-read journal lacks evidence")
    evidence = json.dumps(value["evidence"], separators=(",", ":")).encode("utf-8") + b"\n"
    with open(evidence_output, "xb") as output:
        output.write(evidence)
        output.flush()
        os.fsync(output.fileno())
else:
    raise SystemExit("account-read journal state is invalid")
print(state)
PY
}

commit_account_read_operation_journal() {
  local target="$1"
  local operation_id="$2"
  local runner_key_id="$3"
  local account_binding="$4"
  local state="$5"
  local evidence_source="${6:-}"
  local directory
  local pending
  directory="$(dirname "$target")"
  pending="$(mktemp "$directory/.operation.pending.XXXXXX")"
  rm -f "$pending"
  if ! write_account_read_operation_journal \
    "$pending" "$operation_id" "$runner_key_id" "$account_binding" \
    "$state" "$evidence_source"; then
    rm -f "$pending"
    return 1
  fi
  chmod 0600 "$pending"
  mv "$pending" "$target"
  python3 - "$directory" <<'PY'
import os
import sys

descriptor = os.open(sys.argv[1], os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY
}

resolve_account_read_operation_before_provider() {
  local journal_dir="$1"
  local journal="$2"
  local operation_id="$3"
  local runner_key_id="$4"
  local account_binding="$5"
  local verified_work="$6"
  local replay_evidence="$7"
  [ -z "$(find "$journal_dir" -mindepth 1 -maxdepth 1 ! -name "$operation_id.json" -print -quit)" ] ||
    die "account probe found conflicting operation journal state"
  if [ -e "$journal" ] || [ -L "$journal" ]; then
    local journal_state
    journal_state="$(validate_account_read_operation_journal \
      "$journal" "$operation_id" "$runner_key_id" \
      "$account_binding" "$replay_evidence")" ||
      die "account probe retained operation journal is invalid"
    if [ "$journal_state" = "completed" ]; then
      local replay_hash
      replay_hash="$(validate_account_read_evidence \
        "$replay_evidence" "$operation_id" "$runner_key_id" \
        "$account_binding")"
      echo "completed:$replay_hash"
      return
    fi
    die "account probe operation is unresolved after an interrupted attempt"
  fi
  require_remote_mandate_execution_eligible "$verified_work" ||
    die "account probe authority is not currently eligible for execution"
  echo eligible
}

probe_exchange_account_once() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  command -v systemd-run >/dev/null 2>&1 || die "systemd-run is required"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "account probe refused the installed runner key id"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "account probe requires an inactive public-shadow runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "account probe requires a disabled public-shadow runner" ;;
  esac
  [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
    [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    die "account probe requires one prepared exchange credential"

  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work
  work="$(mktemp -d /run/hivra-trading-account-read.XXXXXX)"
  trap "rm -rf '$work'; rm -f '$lock_path'" EXIT INT TERM

  local mandate="$STATE_DIRECTORY/mandates/prepared.v2.json"
  [ ! -e "$STATE_DIRECTORY/mandates/prepared.v1.json" ] &&
    [ ! -L "$STATE_DIRECTORY/mandates/prepared.v1.json" ] ||
    die "account probe refused legacy account-read authority"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "account probe requires one prepared mandate"
  install -m 0600 "$mandate" "$work/mandate.json"
  mkdir "$work/verified"
  verify_remote_mandate_artifact \
    "$work/mandate.json" "$EXPECTED_RUNNER_KEY_ID" "$work/verified"

  local operation_id account_binding expires_at read_scope max_uses
  operation_id="$(cat "$work/verified/operation-id")"
  account_binding="$(cat "$work/verified/account-binding")"
  expires_at="$(cat "$work/verified/expires-at")"
  read_scope="$(cat "$work/verified/read-scope")"
  max_uses="$(cat "$work/verified/max-uses")"
  [ "$read_scope" = "$ACCOUNT_READ_SCOPE_WIRE" ] &&
    [ "$max_uses" = "$ACCOUNT_READ_MAX_USES" ] ||
    die "account probe verified authority is not exact"

  local journal_dir="$STATE_DIRECTORY/account-read-operations"
  if [ -e "$journal_dir" ] || [ -L "$journal_dir" ]; then
    [ -d "$journal_dir" ] && [ ! -L "$journal_dir" ] ||
      die "account probe refused foreign operation journal"
  else
    install -d -m 0700 "$journal_dir"
  fi
  local journal="$journal_dir/$operation_id.json"
  local replay_evidence="$work/replay-evidence.json"
  local resolution
  resolution="$(resolve_account_read_operation_before_provider \
    "$journal_dir" "$journal" "$operation_id" "$EXPECTED_RUNNER_KEY_ID" \
    "$account_binding" "$work/verified" "$replay_evidence")"
  if [[ "$resolution" == completed:* ]]; then
    local replay_hash="${resolution#completed:}"
    trap - EXIT INT TERM
    rm -rf "$work"
    rm -f "$lock_path"
    exec 9>&-
    echo "PASS trading-runner-artifact: exact account-read replay returned retained redacted evidence evidence_hash=$replay_hash effect=false"
    return
  fi
  [ "$resolution" = eligible ] || die "account probe resolution is invalid"
  commit_account_read_operation_journal \
    "$journal" "$operation_id" "$EXPECTED_RUNNER_KEY_ID" \
    "$account_binding" pending

  local transient_name="hivra-trading-account-read-${operation_id:0:12}-$$"
  local credential_dir="/run/credentials/$transient_name.service"
  [ "$(systemctl show -p LoadState --value "$transient_name.service" 2>/dev/null || true)" = "not-found" ] ||
    die "account probe transient unit already exists"

  if ! systemd-run \
    --unit="$transient_name" \
    --service-type=exec \
    --wait --pipe --collect --quiet \
    --property=DynamicUser=yes \
    --property=LoadCredentialEncrypted="runner-seed:$CREDENTIAL_INSTALL_PATH" \
    --property=LoadCredentialEncrypted="bingx-exchange:$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    --property=RuntimeMaxSec=60s \
    --property=TimeoutStartSec=60s \
    --property=TimeoutStopSec=10s \
    --property=KillMode=mixed \
    --property=OOMPolicy=stop \
    --property=MemoryMax=128M \
    --property=MemorySwapMax=0 \
    --property=TasksMax=16 \
    --property=CPUWeight=10 \
    --property=IOWeight=10 \
    --property=Nice=10 \
    --property=UMask=0077 \
    --property=NoNewPrivileges=yes \
    --property=PrivateTmp=yes \
    --property=PrivateDevices=yes \
    --property=ProtectSystem=strict \
    --property=ProtectHome=yes \
    --property=ProtectProc=invisible \
    --property=ProcSubset=pid \
    --property=ProtectKernelTunables=yes \
    --property=ProtectKernelModules=yes \
    --property=ProtectKernelLogs=yes \
    --property=ProtectControlGroups=yes \
    --property=ProtectClock=yes \
    --property=ProtectHostname=yes \
    --property=RestrictRealtime=yes \
    --property=RestrictSUIDSGID=yes \
    --property=RestrictNamespaces=yes \
    --property=LockPersonality=yes \
    --property=MemoryDenyWriteExecute=yes \
    --property=CapabilityBoundingSet= \
    --property=AmbientCapabilities= \
    --property=SystemCallArchitectures=native \
    --property=SystemCallFilter=@system-service \
    --property="RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6" \
    --property=SocketBindDeny=any \
    --property=IPAccounting=yes \
    "$BINARY_INSTALL_PATH" \
      --mode account-read \
      --runner-seed-file "$credential_dir/runner-seed" \
      --account-read-credential-file "$credential_dir/bingx-exchange" \
      --expected-runner-key-id "$EXPECTED_RUNNER_KEY_ID" \
      --expected-account-binding-hash "$account_binding" \
      --account-read-operation-id "$operation_id" \
      --account-read-scope "$read_scope" \
      --account-read-max-uses "$max_uses" \
      --account-read-expires-at-utc "$expires_at" \
      >"$work/stdout" 2>"$work/stderr"; then
    die "account probe failed without exposing provider output"
  fi
  [ ! -s "$work/stderr" ] || die "account probe produced unexpected standard error"
  local evidence_hash
  evidence_hash="$(validate_account_read_evidence \
    "$work/stdout" "$operation_id" "$EXPECTED_RUNNER_KEY_ID" "$account_binding")"
  commit_account_read_operation_journal \
    "$journal" "$operation_id" "$EXPECTED_RUNNER_KEY_ID" \
    "$account_binding" completed "$work/stdout"
  for _ in $(seq 1 50); do
    [ "$(systemctl show -p LoadState --value "$transient_name.service" 2>/dev/null || true)" = "not-found" ] && break
    sleep 0.1
  done
  [ "$(systemctl show -p LoadState --value "$transient_name.service" 2>/dev/null || true)" = "not-found" ] ||
    die "account probe retained its transient unit"

  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: completed one Capsule-authorized single-use account read evidence_hash=$evidence_hash effect=false"
}

validate_exact_order_evidence() {
  local source="$1"
  local expected_operation="$2"
  python3 - "$source" "$expected_operation" <<'PY'
import json
import pathlib
import re
import sys

source, expected_operation = sys.argv[1:]
raw = pathlib.Path(source).read_bytes()
if len(raw) < 2 or len(raw) > 2048 or not raw.endswith(b"\n") or raw.endswith(b"\n\n"):
    raise SystemExit("exact-order evidence is not one bounded line")
try:
    text = raw[:-1].decode("utf-8")
    value = json.loads(text)
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("exact-order evidence is not strict UTF-8 JSON")
expected_keys = [
    "contract_version", "operation_id", "state", "attempt_count",
    "provider_reference_id", "receipt_evidence_hash_hex", "test_order",
]
if not isinstance(value, dict) or list(value) != expected_keys:
    raise SystemExit("exact-order evidence shape is not canonical")
if json.dumps(value, separators=(",", ":"), ensure_ascii=False) != text:
    raise SystemExit("exact-order evidence bytes are not canonical")
if value["contract_version"] != "hivra-trading-exact-order-evidence-v1":
    raise SystemExit("exact-order evidence version mismatch")
if value["operation_id"] != expected_operation:
    raise SystemExit("exact-order evidence operation mismatch")
if value["state"] not in ("succeeded", "unresolved", "terminal_failure"):
    raise SystemExit("exact-order evidence state is invalid")
if not isinstance(value["attempt_count"], int) or value["attempt_count"] != 1:
    raise SystemExit("exact-order evidence use bound mismatch")
if value["provider_reference_id"] is not None and not isinstance(value["provider_reference_id"], str):
    raise SystemExit("exact-order evidence provider reference is invalid")
receipt = value["receipt_evidence_hash_hex"]
if receipt is not None and (not isinstance(receipt, str) or re.fullmatch(r"[0-9a-f]{64}", receipt) is None):
    raise SystemExit("exact-order evidence receipt is invalid")
if value["state"] == "succeeded" and receipt is None:
    raise SystemExit("successful exact-order evidence lacks receipt")
if not isinstance(value["test_order"], bool):
    raise SystemExit("exact-order evidence mode is invalid")
print(value["state"])
PY
}

validate_deterministic_cycle_outcome() {
  local source="$1"
  local expected_operation="$2"
  python3 - "$source" "$expected_operation" <<'PY'
import json
import pathlib
import re
import sys

source, expected_operation = sys.argv[1:]
raw = pathlib.Path(source).read_bytes()
if len(raw) < 2 or len(raw) > 2048 or not raw.endswith(b"\n") or raw.endswith(b"\n\n"):
    raise SystemExit("deterministic cycle outcome is not one bounded line")
try:
    text = raw[:-1].decode("utf-8")
    value = json.loads(text)
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("deterministic cycle outcome is not strict UTF-8 JSON")
if json.dumps(value, separators=(",", ":"), ensure_ascii=False) != text:
    raise SystemExit("deterministic cycle outcome bytes are not canonical")
contract = value.get("contract_version")
if contract == "hivra-trading-deterministic-cycle-evidence-v1":
    if list(value) != ["contract_version", "operation_id", "state", "reason_code", "effect"]:
        raise SystemExit("deterministic blocked outcome shape is invalid")
    reason = value.get("reason_code")
    if (
        value.get("operation_id") != expected_operation
        or value.get("state") != "blocked"
        or not isinstance(reason, str)
        or re.fullmatch(r"[a-z0-9_]{1,96}", reason) is None
        or value.get("effect") is not False
    ):
        raise SystemExit("deterministic blocked outcome is invalid")
    print(f"blocked:{reason}")
elif contract == "hivra-trading-exact-order-evidence-v1":
    expected_keys = [
        "contract_version", "operation_id", "state", "attempt_count",
        "provider_reference_id", "receipt_evidence_hash_hex", "test_order",
    ]
    if list(value) != expected_keys or value.get("operation_id") != expected_operation:
        raise SystemExit("deterministic effect outcome identity is invalid")
    state = value.get("state")
    if state not in ("succeeded", "unresolved", "terminal_failure"):
        raise SystemExit("deterministic effect outcome state is invalid")
    if value.get("attempt_count") != 1 or not isinstance(value.get("test_order"), bool):
        raise SystemExit("deterministic effect outcome use bound is invalid")
    provider = value.get("provider_reference_id")
    if provider is not None and (
        not isinstance(provider, str) or not 1 <= len(provider) <= 256
    ):
        raise SystemExit("deterministic effect provider reference is invalid")
    receipt = value.get("receipt_evidence_hash_hex")
    if receipt is not None and (
        not isinstance(receipt, str) or re.fullmatch(r"[0-9a-f]{64}", receipt) is None
    ):
        raise SystemExit("deterministic effect receipt is invalid")
    if state == "succeeded" and receipt is None:
        raise SystemExit("successful deterministic effect lacks receipt")
    print(f"effect:{state}:test={str(value['test_order']).lower()}")
else:
    raise SystemExit("deterministic cycle outcome version mismatch")
PY
}

validate_deterministic_recovery_outcome() {
  local source="$1"
  local expected_operation="$2"
  if validate_deterministic_cycle_outcome \
    "$source" "$expected_operation" 2>/dev/null; then
    return
  fi
  python3 - "$source" "$expected_operation" <<'PY'
import json
import pathlib
import sys

source, expected_operation = sys.argv[1:]
raw = pathlib.Path(source).read_bytes()
if len(raw) < 2 or len(raw) > 512 or not raw.endswith(b"\n") or raw.endswith(b"\n\n"):
    raise SystemExit("deterministic recovery outcome is not one bounded line")
try:
    text = raw[:-1].decode("utf-8")
    value = json.loads(text)
except (UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit("deterministic recovery outcome is not strict JSON")
if (
    not isinstance(value, dict)
    or list(value) != ["contract_version", "operation_id", "state", "effect"]
    or json.dumps(value, separators=(",", ":")) != text
    or value.get("contract_version") != "hivra-trading-exact-order-recovery-v1"
    or value.get("operation_id") != expected_operation
    or value.get("state") not in ("absent", "not_delivered")
    or value.get("effect") is not False
):
    raise SystemExit("deterministic recovery outcome is invalid")
print(f"no_effect:{value['state']}")
PY
}

select_deterministic_recovery_cycle() {
  local session_status="$1"
  local session_id="$2"
  local result_dir="$3"
  local has_revocation="$4"
  local index="${session_status#*:}"
  index="${index%%:*}"
  if [[ "$session_status" != stopped:* ]] || [ "$index" -eq 0 ] ||
    [ "$has_revocation" = "true" ]; then
    echo "$index"
    return
  fi
  local previous_index previous_operation previous_result previous_outcome
  previous_index="$((index - 1))"
  previous_operation="$(derive_deterministic_session_cycle_operation_id \
    "$session_id" "$previous_index")" || return 1
  previous_result="$result_dir/$previous_operation.json"
  if [ -f "$previous_result" ] && [ ! -L "$previous_result" ]; then
    previous_outcome="$(validate_deterministic_cycle_outcome \
      "$previous_result" "$previous_operation")" || return 1
    case "$previous_outcome" in
      effect:unresolved:*|effect:terminal_failure:*)
        echo "$previous_index"
        return
        ;;
    esac
  fi
  echo "$index"
}

execute_exact_order_once() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  command -v systemd-run >/dev/null 2>&1 || die "systemd-run is required"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "exact order refused the installed runner key id"
  [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
    [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    die "exact order requires one prepared exchange credential"
  local mandate="$STATE_DIRECTORY/mandates/exact-order.v3.json"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "exact order requires one prepared exact authority"

  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work
  work="$(mktemp -d /run/hivra-trading-exact-order.XXXXXX)"
  trap "rm -rf '$work'; rm -f '$lock_path'" EXIT INT TERM
  mkdir "$work/verified"
  verify_remote_mandate_artifact \
    "$mandate" "$EXPECTED_RUNNER_KEY_ID" "$work/verified"
  [ "$(cat "$work/verified/operation-kind")" = "one_exact_order" ] ||
    die "exact order authority kind mismatch"
  local admission_operation_id effect_operation_id
  admission_operation_id="$(cat "$work/verified/operation-id")"
  effect_operation_id="$(cat "$work/verified/effect-operation-id")"
  local transient_name="hivra-trading-exact-order-${effect_operation_id:0:12}-$$"
  local credential_dir="/run/credentials/$transient_name.service"
  if ! systemd-run \
    --unit="$transient_name" \
    --service-type=exec \
    --wait --pipe --collect --quiet \
    --property=DynamicUser=yes \
    --property=StateDirectory=hivra-trading-public-shadow \
    --property=StateDirectoryMode=0700 \
    --property=LoadCredentialEncrypted="runner-seed:$CREDENTIAL_INSTALL_PATH" \
    --property=LoadCredentialEncrypted="bingx-exchange:$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    --property="LoadCredential=exact-order-admission:$mandate" \
    --property=RuntimeMaxSec=60s \
    --property=TimeoutStartSec=60s \
    --property=TimeoutStopSec=10s \
    --property=KillMode=mixed \
    --property=OOMPolicy=stop \
    --property=MemoryMax=128M \
    --property=MemorySwapMax=0 \
    --property=TasksMax=16 \
    --property=NoNewPrivileges=yes \
    --property=PrivateTmp=yes \
    --property=PrivateDevices=yes \
    --property=ProtectSystem=strict \
    --property=ProtectHome=yes \
    --property=ProtectProc=invisible \
    --property=ProcSubset=pid \
    --property=ProtectKernelTunables=yes \
    --property=ProtectKernelModules=yes \
    --property=ProtectKernelLogs=yes \
    --property=ProtectControlGroups=yes \
    --property=RestrictSUIDSGID=yes \
    --property=RestrictNamespaces=yes \
    --property=LockPersonality=yes \
    --property=MemoryDenyWriteExecute=yes \
    --property=CapabilityBoundingSet= \
    --property=AmbientCapabilities= \
    --property=SystemCallArchitectures=native \
    --property=SystemCallFilter=@system-service \
    --property="RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6" \
    --property=SocketBindDeny=any \
    --property=IPAccounting=yes \
    "$EFFECT_BINARY_INSTALL_PATH" \
      --mode exact-order \
      --runner-seed-file "$credential_dir/runner-seed" \
      --exact-order-credential-file "$credential_dir/bingx-exchange" \
      --exact-order-admission-file "$credential_dir/exact-order-admission" \
      --exact-order-state-home "$STATE_DIRECTORY/exact-order-runtime" \
      --expected-runner-key-id "$EXPECTED_RUNNER_KEY_ID" \
      >"$work/stdout" 2>"$work/stderr"; then
    die "exact order failed without exposing provider output"
  fi
  [ ! -s "$work/stderr" ] || die "exact order produced unexpected standard error"
  local state
  state="$(validate_exact_order_evidence "$work/stdout" "$effect_operation_id")"
  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: exact order lifecycle state=$state effect_operation_id=$effect_operation_id admission_operation_id=$admission_operation_id"
}

capture_deterministic_market_evidence_once() {
  local verified_work="$1"
  local operation_id="$2"
  local retained_evidence="$3"
  local work="$4"
  local observation_dir="$5"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "deterministic observation requires an inactive public-shadow runner"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "deterministic observation requires a disabled public-shadow runner" ;;
  esac

  local stream_dir="$STATE_DIRECTORY/stream/evidence"
  [ -d "$stream_dir" ] && [ ! -L "$stream_dir" ] ||
    die "deterministic observation requires the canonical evidence stream"
  local previous_evidence
  previous_evidence="$(find "$stream_dir" -maxdepth 1 -type f \
    -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*.json' \
    -print | LC_ALL=C sort | tail -1)"
  local previous_sequence=0
  local previous_hash="0000000000000000000000000000000000000000000000000000000000000000"
  if [ -n "$previous_evidence" ]; then
    read -r previous_sequence previous_hash <<<"$(python3 - "$previous_evidence" <<'PY'
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
sequence = value.get("sequence")
match = re.fullmatch(r"([0-9]{12})-([0-9a-f]{64})\.json", path.name)
if (
    not isinstance(sequence, int)
    or sequence < 1
    or match is None
    or int(match.group(1)) != sequence
):
    raise SystemExit("existing market evidence identity is invalid")
print(sequence, match.group(2))
PY
)" || die "deterministic observation found invalid stream continuity"
  fi

  local symbol runner_build_id plugin_id plugin_version package_digest host_abi
  symbol="$(cat "$verified_work/mandate-symbol")"
  runner_build_id="$(cat "$verified_work/policy-runner-build-id")"
  plugin_id="$(cat "$verified_work/policy-plugin-id")"
  plugin_version="$(cat "$verified_work/policy-plugin-version")"
  package_digest="$(cat "$verified_work/policy-package-digest-hex")"
  host_abi="$(cat "$verified_work/policy-host-abi")"
  local transient_name="hivra-trading-market-${operation_id:0:12}-$$"
  local credential_dir="/run/credentials/$transient_name.service"
  if ! systemd-run \
    --unit="$transient_name" \
    --service-type=exec \
    --wait --pipe --collect --quiet \
    --property=DynamicUser=yes \
    --property=StateDirectory=hivra-trading-public-shadow \
    --property=StateDirectoryMode=0700 \
    --property=LoadCredentialEncrypted="runner-seed:$CREDENTIAL_INSTALL_PATH" \
    --property=RuntimeMaxSec=90s \
    --property=TimeoutStartSec=90s \
    --property=TimeoutStopSec=10s \
    --property=KillMode=mixed \
    --property=OOMPolicy=stop \
    --property=MemoryMax=128M \
    --property=MemorySwapMax=0 \
    --property=TasksMax=16 \
    --property=CPUWeight=10 \
    --property=IOWeight=10 \
    --property=Nice=10 \
    --property=UMask=0077 \
    --property=NoNewPrivileges=yes \
    --property=PrivateTmp=yes \
    --property=PrivateDevices=yes \
    --property=ProtectSystem=strict \
    --property=ProtectHome=yes \
    --property=ProtectProc=invisible \
    --property=ProcSubset=pid \
    --property=ProtectKernelTunables=yes \
    --property=ProtectKernelModules=yes \
    --property=ProtectKernelLogs=yes \
    --property=ProtectControlGroups=yes \
    --property=ProtectClock=yes \
    --property=ProtectHostname=yes \
    --property=RestrictRealtime=yes \
    --property=RestrictSUIDSGID=yes \
    --property=RestrictNamespaces=yes \
    --property=LockPersonality=yes \
    --property=MemoryDenyWriteExecute=yes \
    --property=CapabilityBoundingSet= \
    --property=AmbientCapabilities= \
    --property=SystemCallArchitectures=native \
    --property=SystemCallFilter=@system-service \
    --property="RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6" \
    --property=SocketBindDeny=any \
    --property=IPAccounting=yes \
    "$BINARY_INSTALL_PATH" \
      --runner-seed-file "$credential_dir/runner-seed" \
      --symbol "$symbol" \
      --runner-build-id "$runner_build_id" \
      --plugin-id "$plugin_id" \
      --plugin-version "$plugin_version" \
      --package-digest-hex "$package_digest" \
      --host-abi "$host_abi" \
      --stream-dir "$STATE_DIRECTORY/stream" \
      --run-count 1 \
      >"$work/market-stdout" 2>"$work/market-stderr"; then
    die "deterministic public-market observation failed"
  fi
  [ ! -s "$work/market-stderr" ] ||
    die "deterministic public-market observation produced unexpected standard error"
  for _ in $(seq 1 50); do
    [ "$(systemctl show -p LoadState --value "$transient_name.service" 2>/dev/null || true)" = "not-found" ] && break
    sleep 0.1
  done
  [ "$(systemctl show -p LoadState --value "$transient_name.service" 2>/dev/null || true)" = "not-found" ] ||
    die "deterministic public-market observation retained its transient unit"

  local evidence
  evidence="$(find "$stream_dir" -maxdepth 1 -type f \
    -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*.json' \
    -print | LC_ALL=C sort | tail -1)"
  [ -n "$evidence" ] && [ "$evidence" != "$previous_evidence" ] ||
    die "deterministic observation produced no new market evidence"
  python3 - "$evidence" "$((previous_sequence + 1))" "$previous_hash" \
    "$EXPECTED_RUNNER_KEY_ID" "$symbol" "$runner_build_id" "$plugin_id" \
    "$plugin_version" "$package_digest" "$host_abi" <<'PY'
import json
import pathlib
import re
import sys

(
    source, expected_sequence, previous_hash, runner_key_id, symbol,
    runner_build_id, plugin_id, plugin_version, package_digest, host_abi,
) = sys.argv[1:]
raw = pathlib.Path(source).read_bytes()
if len(raw) < 2 or len(raw) > 8192:
    raise SystemExit("captured market evidence is not bounded")
value = json.loads(raw.decode("utf-8"))
expected = {
    "contract_version": "trading-shadow-evidence-v2",
    "runner_build_id": runner_build_id,
    "plugin_id": plugin_id,
    "plugin_version": plugin_version,
    "package_digest_hex": package_digest,
    "host_abi": host_abi,
    "market_symbol": symbol,
    "sequence": int(expected_sequence),
    "previous_evidence_hash_hex": previous_hash,
    "runner_key_id": runner_key_id,
    "signature_suite": "ed25519-v1",
}
for key, expected_value in expected.items():
    if value.get(key) != expected_value:
        raise SystemExit(f"captured market evidence {key} mismatch")
if value.get("market_proposal_status") not in ("READY", "BLOCKED"):
    raise SystemExit("captured market evidence proposal status is invalid")
if re.fullmatch(r"[0-9a-f]{128}", str(value.get("signature_hex"))) is None:
    raise SystemExit("captured market evidence signature is invalid")
PY
  pending_observation="$(mktemp "$observation_dir/.observation.pending.XXXXXX")"
  install -m 0600 "$evidence" "$pending_observation"
  mv "$pending_observation" "$retained_evidence"
  pending_observation=""
}

execute_deterministic_order_once() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  command -v systemd-run >/dev/null 2>&1 || die "systemd-run is required"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "deterministic order refused the installed runner key id"
  [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
    [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    die "deterministic order requires one prepared exchange credential"
  local mandate="$STATE_DIRECTORY/mandates/deterministic-order.v4.json"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "deterministic order requires one prepared deterministic authority"

  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work pending_observation pending_result
  work="$(mktemp -d /run/hivra-trading-deterministic-order.XXXXXX)"
  pending_observation=""
  pending_result=""
  trap '
    rm -rf "$work"
    [ -z "$pending_observation" ] || rm -f "$pending_observation"
    [ -z "$pending_result" ] || rm -f "$pending_result"
    rm -f "$lock_path"
  ' EXIT INT TERM
  mkdir "$work/verified"
  verify_remote_mandate_artifact \
    "$mandate" "$EXPECTED_RUNNER_KEY_ID" "$work/verified"
  local operation_kind admission_operation_id operation_id cycle_index
  operation_kind="$(cat "$work/verified/operation-kind")"
  admission_operation_id="$(cat "$work/verified/operation-id")"
  if [ -n "$SCHEDULER_SESSION_OPERATION_ID" ] &&
    [ "$admission_operation_id" != "$SCHEDULER_SESSION_OPERATION_ID" ]; then
    die "deterministic scheduler refused mandate rotation during its session"
  fi
  cycle_index=""
  case "$operation_kind" in
    one_deterministic_order)
      operation_id="$admission_operation_id"
      ;;
    bounded_deterministic_session)
      local session_state session_status retained_revocation
      session_state="$STATE_DIRECTORY/deterministic-session.v1.json"
      retained_revocation="$STATE_DIRECTORY/revocations/$admission_operation_id.json"
      if [ -e "$retained_revocation" ] || [ -L "$retained_revocation" ]; then
        [ -f "$retained_revocation" ] && [ ! -L "$retained_revocation" ] ||
          die "deterministic session retained revocation is invalid"
        mkdir "$work/revocation"
        verify_remote_session_revocation_artifact \
          "$retained_revocation" "$EXPECTED_RUNNER_KEY_ID" \
          "$admission_operation_id" "$(cat "$work/verified/capsule-root")" \
          "$work/revocation"
        stop_deterministic_session_state \
          "$session_state" "$admission_operation_id" >/dev/null ||
          die "deterministic session could not apply retained revocation"
      fi
      session_status="$(prepare_deterministic_session_cycle \
        "$session_state" "$admission_operation_id" \
        "$(cat "$work/verified/session-max-cycles")" \
        "$(cat "$work/verified/mandate-max-effects")" \
        "$(cat "$work/verified/session-interval-seconds")" \
        "$(cat "$work/verified/session-starts-at")" \
        "$(cat "$work/verified/expires-at")")" ||
        die "deterministic session is not eligible for its next cycle"
      case "$session_status" in
        ready:*) cycle_index="${session_status#ready:}"; cycle_index="${cycle_index%%:*}" ;;
        terminal:*)
          trap - EXIT INT TERM
          rm -rf "$work"
          rm -f "$lock_path"
          exec 9>&-
          echo "PASS trading-runner-artifact: deterministic session already terminal session_operation_id=$admission_operation_id status=$session_status effect_repeated=false"
          return
          ;;
        *) die "deterministic session returned an invalid state" ;;
      esac
      operation_id="$(derive_deterministic_session_cycle_operation_id \
        "$admission_operation_id" "$cycle_index")" ||
        die "deterministic session cycle identity derivation failed"
      ;;
    *) die "deterministic order authority kind mismatch" ;;
  esac
  local result_dir="$STATE_DIRECTORY/deterministic-results"
  ensure_private_operation_store "$result_dir"
  validate_deterministic_operation_store \
    "$result_dir" "$operation_id" "$DETERMINISTIC_HISTORY_LIMIT" 2048 ||
    die "deterministic order refused invalid or full result history"
  local retained_result="$result_dir/$operation_id.json"
  if [ -e "$retained_result" ] || [ -L "$retained_result" ]; then
    [ -f "$retained_result" ] && [ ! -L "$retained_result" ] ||
      die "deterministic order retained result is invalid"
    local replay_outcome
    replay_outcome="$(validate_deterministic_cycle_outcome "$retained_result" "$operation_id")" ||
      die "deterministic order retained result validation failed"
    local replay_session_status=""
    if [ "$operation_kind" = "bounded_deterministic_session" ]; then
      replay_session_status="$(advance_deterministic_session_cycle \
        "$STATE_DIRECTORY/deterministic-session.v1.json" \
        "$admission_operation_id" "$cycle_index" "$operation_id" \
        "$replay_outcome" "$(cat "$work/verified/session-max-cycles")" \
        "$(cat "$work/verified/mandate-max-effects")")" ||
        die "deterministic session could not reconcile its retained cycle"
    fi
    trap - EXIT INT TERM
    rm -rf "$work"
    rm -f "$lock_path"
    exec 9>&-
    echo "PASS trading-runner-artifact: replayed deterministic order cycle operation_id=$operation_id outcome=$replay_outcome session_status=${replay_session_status:-single_use} effect_repeated=false"
    return
  fi
  if [ "$operation_kind" = "one_deterministic_order" ]; then
    require_remote_mandate_execution_eligible "$work/verified" ||
      die "deterministic order authority is not currently eligible for execution"
  fi

  local observation_dir="$STATE_DIRECTORY/deterministic-observations"
  ensure_private_operation_store "$observation_dir"
  validate_deterministic_operation_store "$observation_dir" "$operation_id" ||
    die "deterministic order refused invalid or full observation history"
  local retained_evidence="$observation_dir/$operation_id.json"
  if [ -e "$retained_evidence" ] || [ -L "$retained_evidence" ]; then
    [ -f "$retained_evidence" ] && [ ! -L "$retained_evidence" ] ||
      die "deterministic order retained evidence is invalid"
    [ "$(file_size "$retained_evidence")" -le 8192 ] ||
      die "deterministic order retained evidence is oversized"
  else
    capture_deterministic_market_evidence_once \
      "$work/verified" "$operation_id" "$retained_evidence" "$work" \
      "$observation_dir"
  fi

  local evidence="$retained_evidence"
  [ -n "$evidence" ] && [ -f "$evidence" ] && [ ! -L "$evidence" ] ||
    die "deterministic order requires one committed market evidence"
  [ "$(file_size "$evidence")" -le 8192 ] ||
    die "deterministic market evidence is oversized"
  local continuity
  continuity="$(python3 - "$evidence" <<'PY'
import json
import pathlib
import re
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
sequence = value.get("sequence")
previous = value.get("previous_evidence_hash_hex")
if not isinstance(sequence, int) or sequence < 1:
    raise SystemExit("invalid market evidence sequence")
if not isinstance(previous, str) or re.fullmatch(r"[0-9a-f]{64}", previous) is None:
    raise SystemExit("invalid market evidence continuity")
print(f"{sequence - 1} {previous}")
PY
)" || die "deterministic market evidence continuity is invalid"
  local last_sequence last_hash
  read -r last_sequence last_hash <<<"$continuity"
  local -a session_cycle_args=()
  if [ -n "$cycle_index" ]; then
    session_cycle_args=(--session-cycle-index "$cycle_index")
  fi
  local transient_name="hivra-trading-deterministic-${operation_id:0:12}-$$"
  local credential_dir="/run/credentials/$transient_name.service"
  if ! systemd-run \
    --unit="$transient_name" \
    --service-type=exec \
    --wait --pipe --collect --quiet \
    --property=DynamicUser=yes \
    --property=StateDirectory=hivra-trading-public-shadow \
    --property=StateDirectoryMode=0700 \
    --property=LoadCredentialEncrypted="runner-seed:$CREDENTIAL_INSTALL_PATH" \
    --property=LoadCredentialEncrypted="bingx-exchange:$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    --property="LoadCredential=deterministic-admission:$mandate" \
    --property="LoadCredential=market-evidence:$evidence" \
    --property=RuntimeMaxSec=90s \
    --property=TimeoutStartSec=90s \
    --property=TimeoutStopSec=10s \
    --property=KillMode=mixed \
    --property=OOMPolicy=stop \
    --property=MemoryMax=160M \
    --property=MemorySwapMax=0 \
    --property=TasksMax=16 \
    --property=NoNewPrivileges=yes \
    --property=PrivateTmp=yes \
    --property=PrivateDevices=yes \
    --property=ProtectSystem=strict \
    --property=ProtectHome=yes \
    --property=ProtectProc=invisible \
    --property=ProcSubset=pid \
    --property=ProtectKernelTunables=yes \
    --property=ProtectKernelModules=yes \
    --property=ProtectKernelLogs=yes \
    --property=ProtectControlGroups=yes \
    --property=RestrictSUIDSGID=yes \
    --property=RestrictNamespaces=yes \
    --property=LockPersonality=yes \
    --property=MemoryDenyWriteExecute=yes \
    --property=CapabilityBoundingSet= \
    --property=AmbientCapabilities= \
    --property=SystemCallArchitectures=native \
    --property=SystemCallFilter=@system-service \
    --property="RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6" \
    --property=SocketBindDeny=any \
    --property=IPAccounting=yes \
    "$EFFECT_BINARY_INSTALL_PATH" \
      --mode deterministic-order \
      --runner-seed-file "$credential_dir/runner-seed" \
      --deterministic-credential-file "$credential_dir/bingx-exchange" \
      --deterministic-admission-file "$credential_dir/deterministic-admission" \
      --market-evidence-file "$credential_dir/market-evidence" \
      --deterministic-state-home "$STATE_DIRECTORY/deterministic-order-runtime" \
      --last-accepted-sequence "$last_sequence" \
      --last-accepted-evidence-hash "$last_hash" \
      "${session_cycle_args[@]}" \
      >"$work/stdout" 2>"$work/stderr"; then
    die "deterministic order failed without exposing provider output"
  fi
  [ ! -s "$work/stderr" ] ||
    die "deterministic order produced unexpected standard error"
  local outcome
  outcome="$(validate_deterministic_cycle_outcome "$work/stdout" "$operation_id")" ||
    die "deterministic order outcome validation failed"
  pending_result="$(mktemp "$result_dir/.result.pending.XXXXXX")"
  install -m 0600 "$work/stdout" "$pending_result"
  mv "$pending_result" "$retained_result"
  pending_result=""
  local session_status="single_use"
  if [ "$operation_kind" = "bounded_deterministic_session" ]; then
    session_status="$(advance_deterministic_session_cycle \
      "$STATE_DIRECTORY/deterministic-session.v1.json" \
      "$admission_operation_id" "$cycle_index" "$operation_id" "$outcome" \
      "$(cat "$work/verified/session-max-cycles")" \
      "$(cat "$work/verified/mandate-max-effects")")" ||
      die "deterministic session could not commit its completed cycle"
  fi
  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: completed one deterministic order cycle operation_id=$operation_id outcome=$outcome session_status=$session_status"
}

recover_deterministic_session_once() {
  local directory="$1"
  require_expected_runner_key_id
  require_exact_installed_bundle "$directory"
  command -v systemd-run >/dev/null 2>&1 || die "systemd-run is required"
  [ "$(read_installed_runner_key_id)" = "$EXPECTED_RUNNER_KEY_ID" ] ||
    die "deterministic recovery refused the installed runner key id"
  [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
    [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    die "deterministic recovery requires one prepared exchange credential"
  local mandate="$STATE_DIRECTORY/mandates/deterministic-order.v4.json"
  [ -f "$mandate" ] && [ ! -L "$mandate" ] ||
    die "deterministic recovery requires one prepared authority"

  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  local work pending_result
  work="$(mktemp -d /run/hivra-trading-deterministic-recovery.XXXXXX)"
  pending_result=""
  trap '
    rm -rf "$work"
    [ -z "$pending_result" ] || rm -f "$pending_result"
    rm -f "$lock_path"
  ' EXIT INT TERM
  mkdir "$work/verified"
  verify_remote_mandate_artifact \
    "$mandate" "$EXPECTED_RUNNER_KEY_ID" "$work/verified"
  [ "$(cat "$work/verified/operation-kind")" = "bounded_deterministic_session" ] ||
    die "deterministic recovery requires bounded session authority"
  local session_id session_state session_status cycle_index operation_id
  session_id="$(cat "$work/verified/operation-id")"
  session_state="$STATE_DIRECTORY/deterministic-session.v1.json"
  session_status="$(inspect_deterministic_session_cycle \
    "$session_state" "$session_id" \
    "$(cat "$work/verified/session-max-cycles")" \
    "$(cat "$work/verified/mandate-max-effects")")" ||
    die "deterministic recovery refused invalid session state"
  local has_revocation="false"
  [ ! -e "$STATE_DIRECTORY/revocations/$session_id.json" ] ||
    has_revocation="true"
  cycle_index="$(select_deterministic_recovery_cycle \
    "$session_status" "$session_id" \
    "$STATE_DIRECTORY/deterministic-results" "$has_revocation")" ||
    die "deterministic recovery cycle selection failed"
  if [ "$cycle_index" = "$(cat "$work/verified/session-max-cycles")" ]; then
    echo "PASS trading-runner-artifact: deterministic recovery found no current cycle effect=false"
    return
  fi
  local result_dir="$STATE_DIRECTORY/deterministic-results"
  ensure_private_operation_store "$result_dir"
  operation_id="$(derive_deterministic_session_cycle_operation_id \
    "$session_id" "$cycle_index")" ||
    die "deterministic recovery cycle identity derivation failed"
  validate_deterministic_operation_store \
    "$result_dir" "$operation_id" "$DETERMINISTIC_HISTORY_LIMIT" 2048 ||
    die "deterministic recovery refused invalid result history"
  local retained_result="$result_dir/$operation_id.json"
  if [ -f "$retained_result" ] && [ ! -L "$retained_result" ]; then
    local retained_outcome
    retained_outcome="$(validate_deterministic_cycle_outcome \
      "$retained_result" "$operation_id")" ||
      die "deterministic recovery retained result is invalid"
    case "$retained_outcome" in
      effect:unresolved:*|effect:terminal_failure:*) ;;
      *)
        if [[ "$session_status" == active:* ]]; then
          advance_deterministic_session_cycle \
            "$session_state" "$session_id" "$cycle_index" "$operation_id" \
            "$retained_outcome" "$(cat "$work/verified/session-max-cycles")" \
            "$(cat "$work/verified/mandate-max-effects")" >/dev/null ||
            die "deterministic recovery could not commit retained cycle"
        fi
        echo "PASS trading-runner-artifact: deterministic recovery committed retained result operation_id=$operation_id outcome=$retained_outcome effect_repeated=false"
        return
        ;;
    esac
  fi

  local transient_name="hivra-trading-recovery-${operation_id:0:12}-$$"
  local credential_dir="/run/credentials/$transient_name.service"
  if ! systemd-run \
    --unit="$transient_name" \
    --service-type=exec \
    --wait --pipe --collect --quiet \
    --property=DynamicUser=yes \
    --property=StateDirectory=hivra-trading-public-shadow \
    --property=StateDirectoryMode=0700 \
    --property=LoadCredentialEncrypted="runner-seed:$CREDENTIAL_INSTALL_PATH" \
    --property=LoadCredentialEncrypted="bingx-exchange:$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    --property="LoadCredential=deterministic-admission:$mandate" \
    --property=RuntimeMaxSec=90s \
    --property=TimeoutStartSec=90s \
    --property=TimeoutStopSec=10s \
    --property=KillMode=mixed \
    --property=OOMPolicy=stop \
    --property=MemoryMax=160M \
    --property=MemorySwapMax=0 \
    --property=TasksMax=16 \
    --property=NoNewPrivileges=yes \
    --property=PrivateTmp=yes \
    --property=PrivateDevices=yes \
    --property=ProtectSystem=strict \
    --property=ProtectHome=yes \
    --property=ProtectProc=invisible \
    --property=ProcSubset=pid \
    --property=ProtectKernelTunables=yes \
    --property=ProtectKernelModules=yes \
    --property=ProtectKernelLogs=yes \
    --property=ProtectControlGroups=yes \
    --property=RestrictSUIDSGID=yes \
    --property=RestrictNamespaces=yes \
    --property=LockPersonality=yes \
    --property=MemoryDenyWriteExecute=yes \
    --property=CapabilityBoundingSet= \
    --property=AmbientCapabilities= \
    --property=SystemCallArchitectures=native \
    --property=SystemCallFilter=@system-service \
    --property="RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6" \
    --property=SocketBindDeny=any \
    --property=IPAccounting=yes \
    "$EFFECT_BINARY_INSTALL_PATH" \
      --mode deterministic-order-recovery \
      --runner-seed-file "$credential_dir/runner-seed" \
      --deterministic-credential-file "$credential_dir/bingx-exchange" \
      --deterministic-admission-file "$credential_dir/deterministic-admission" \
      --deterministic-state-home "$STATE_DIRECTORY/deterministic-order-runtime" \
      --session-cycle-index "$cycle_index" \
      >"$work/stdout" 2>"$work/stderr"; then
    die "deterministic recovery failed without exposing provider output"
  fi
  [ ! -s "$work/stderr" ] ||
    die "deterministic recovery produced unexpected standard error"
  local outcome
  outcome="$(validate_deterministic_recovery_outcome \
    "$work/stdout" "$operation_id")" ||
    die "deterministic recovery outcome validation failed"
  case "$outcome" in
    no_effect:*) ;;
    effect:*)
      pending_result="$(mktemp "$result_dir/.result.pending.XXXXXX")"
      install -m 0600 "$work/stdout" "$pending_result"
      mv "$pending_result" "$retained_result"
      pending_result=""
      if [[ "$session_status" == active:* ]]; then
        advance_deterministic_session_cycle \
          "$session_state" "$session_id" "$cycle_index" "$operation_id" \
          "$outcome" "$(cat "$work/verified/session-max-cycles")" \
          "$(cat "$work/verified/mandate-max-effects")" >/dev/null ||
          die "deterministic recovery could not commit its cycle"
      fi
      ;;
    *) die "deterministic recovery returned an unsupported outcome" ;;
  esac
  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: deterministic recovery completed operation_id=$operation_id outcome=$outcome effect_repeated=false"
}

install_disabled() {
  local directory="$1"
  require_install_host "$directory"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  trap "rm -f '$lock_path'" EXIT

  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  local session_wants_path="/etc/systemd/system/multi-user.target.wants/$SESSION_UNIT_NAME"
  local state_private="/var/lib/private/hivra-trading-public-shadow"
  for target in \
    "$BUNDLE_INSTALL_PATH" \
    "$UNIT_LINK_PATH" \
    "$SESSION_UNIT_LINK_PATH" \
    "$CREDENTIAL_INSTALL_PATH" \
    "$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    "$STATE_DIRECTORY" \
    "$state_private" \
    "$wants_path"; do
    [ ! -e "$target" ] && [ ! -L "$target" ] ||
      die "disabled install target already exists: $target"
  done
  [ ! -e "$session_wants_path" ] && [ ! -L "$session_wants_path" ] ||
    die "disabled install target already exists: $session_wants_path"
  if systemctl cat "$UNIT_NAME" >/dev/null 2>&1; then
    die "disabled install unit is already loaded"
  fi
  if systemctl cat "$SESSION_UNIT_NAME" >/dev/null 2>&1; then
    die "disabled install session unit is already loaded"
  fi

  local opt_parent_created=0
  local credential_parent_created=0
  local bundle_installed=0
  local credential_installed=0
  local unit_linked=0
  local session_unit_linked=0
  local unit_loaded=0
  pending_bundle=""
  pending_credential=""
  rollback_disabled_install() {
    set +e
    if [ "$unit_loaded" = 1 ]; then
      systemctl stop "$UNIT_NAME" >/dev/null 2>&1
      systemctl stop "$SESSION_UNIT_NAME" >/dev/null 2>&1
      systemctl clean --what=state "$UNIT_NAME" >/dev/null 2>&1
    fi
    if [ "$unit_linked" = 1 ] && [ -L "$UNIT_LINK_PATH" ] &&
      [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ]; then
      rm -f "$UNIT_LINK_PATH"
    fi
    if [ "$session_unit_linked" = 1 ] && [ -L "$SESSION_UNIT_LINK_PATH" ] &&
      [ "$(readlink "$SESSION_UNIT_LINK_PATH")" = "$SESSION_UNIT_INSTALL_PATH" ]; then
      rm -f "$SESSION_UNIT_LINK_PATH"
    fi
    systemctl daemon-reload >/dev/null 2>&1
    [ "$credential_installed" = 1 ] && rm -f "$CREDENTIAL_INSTALL_PATH"
    [ "$bundle_installed" = 1 ] && rm -rf "$BUNDLE_INSTALL_PATH"
    [ -z "$pending_bundle" ] || rm -rf "$pending_bundle"
    [ -z "$pending_credential" ] || rm -f "$pending_credential"
    if [ "$credential_parent_created" = 1 ]; then
      rmdir /etc/credstore.encrypted >/dev/null 2>&1
    fi
    if [ "$opt_parent_created" = 1 ]; then
      rmdir /opt/hivra >/dev/null 2>&1
    fi
    rm -f "$lock_path"
  }
  trap rollback_disabled_install EXIT INT TERM

  if [ ! -d /opt/hivra ]; then
    install -d -m 0755 /opt/hivra
    opt_parent_created=1
  fi
  [ ! -L /opt/hivra ] || die "/opt/hivra must not be a symlink"
  pending_bundle="$(mktemp -d /opt/hivra/.trading-public-shadow.pending.XXXXXX)"
  install -m 0755 "$directory/$BINARY_NAME" "$pending_bundle/$BINARY_NAME"
  install -m 0755 "$directory/$EFFECT_BINARY_NAME" "$pending_bundle/$EFFECT_BINARY_NAME"
  install -m 0644 "$directory/$UNIT_NAME" "$pending_bundle/$UNIT_NAME"
  install -m 0644 "$directory/$SESSION_UNIT_NAME" "$pending_bundle/$SESSION_UNIT_NAME"
  install -m 0755 "$directory/$LIFECYCLE_NAME" "$pending_bundle/$LIFECYCLE_NAME"
  install -m 0600 "$directory/$MANIFEST_NAME" "$pending_bundle/$MANIFEST_NAME"
  chmod 0755 "$pending_bundle"
  [ "$(sha256_file "$pending_bundle/$BINARY_NAME")" = \
    "$(sed -n 's/^binary_sha256=//p' "$directory/$MANIFEST_NAME")" ] ||
    die "staged binary hash mismatch"
  [ "$(sha256_file "$pending_bundle/$EFFECT_BINARY_NAME")" = \
    "$(sed -n 's/^effect_binary_sha256=//p' "$directory/$MANIFEST_NAME")" ] ||
    die "staged effect binary hash mismatch"
  [ "$(sha256_file "$pending_bundle/$UNIT_NAME")" = \
    "$(sed -n 's/^unit_sha256=//p' "$directory/$MANIFEST_NAME")" ] ||
    die "staged unit hash mismatch"
  [ "$(sha256_file "$pending_bundle/$SESSION_UNIT_NAME")" = \
    "$(sed -n 's/^session_unit_sha256=//p' "$directory/$MANIFEST_NAME")" ] ||
    die "staged session unit hash mismatch"
  [ "$(sha256_file "$pending_bundle/$LIFECYCLE_NAME")" = \
    "$(sed -n 's/^lifecycle_sha256=//p' "$directory/$MANIFEST_NAME")" ] ||
    die "staged lifecycle hash mismatch"
  mv "$pending_bundle" "$BUNDLE_INSTALL_PATH"
  pending_bundle=""
  bundle_installed=1

  if [ ! -d /etc/credstore.encrypted ]; then
    install -d -m 0700 /etc/credstore.encrypted
    credential_parent_created=1
  fi
  [ ! -L /etc/credstore.encrypted ] ||
    die "/etc/credstore.encrypted must not be a symlink"
  pending_credential="$(mktemp /etc/credstore.encrypted/.hivra-shadow.pending.XXXXXX)"
  openssl rand -hex 32 | tr -d '\n' |
    systemd-creds encrypt --name=runner-seed - "$pending_credential" >/dev/null
  chmod 0600 "$pending_credential"
  mv "$pending_credential" "$CREDENTIAL_INSTALL_PATH"
  pending_credential=""
  credential_installed=1

  systemctl link "$UNIT_INSTALL_PATH" >/dev/null
  unit_linked=1
  systemctl link "$SESSION_UNIT_INSTALL_PATH" >/dev/null
  session_unit_linked=1
  [ -L "$UNIT_LINK_PATH" ] &&
    [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ] ||
    die "systemd unit link mismatch"
  [ -L "$SESSION_UNIT_LINK_PATH" ] &&
    [ "$(readlink "$SESSION_UNIT_LINK_PATH")" = "$SESSION_UNIT_INSTALL_PATH" ] ||
    die "systemd session unit link mismatch"
  systemctl daemon-reload
  unit_loaded=1
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "disabled install became enabled" ;;
  esac
  case "$(systemctl is-enabled "$SESSION_UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "disabled install session unit became enabled" ;;
  esac
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "disabled install became active"
  [ "$(systemctl show -p ActiveState --value "$SESSION_UNIT_NAME")" = "inactive" ] ||
    die "disabled install session unit became active"
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "disabled install created boot enablement"
  [ ! -e "$session_wants_path" ] && [ ! -L "$session_wants_path" ] ||
    die "disabled install created session boot enablement"

  trap - EXIT INT TERM
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: installed exact unit disabled and inactive"
}

uninstall_disabled() {
  local directory="$1"
  require_install_host "$directory"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  trap "rm -f '$lock_path'" EXIT INT TERM

  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  local session_wants_path="/etc/systemd/system/multi-user.target.wants/$SESSION_UNIT_NAME"
  local state_private="/var/lib/private/hivra-trading-public-shadow"
  [ -d "$BUNDLE_INSTALL_PATH" ] && [ ! -L "$BUNDLE_INSTALL_PATH" ] ||
    die "uninstall requires the canonical real bundle directory"
  verify_artifact "$BUNDLE_INSTALL_PATH" >/dev/null
  cmp -s "$BINARY_INSTALL_PATH" "$directory/$BINARY_NAME" ||
    die "uninstall refused a drifted runner binary"
  cmp -s "$EFFECT_BINARY_INSTALL_PATH" "$directory/$EFFECT_BINARY_NAME" ||
    die "uninstall refused a drifted effect binary"
  cmp -s "$UNIT_INSTALL_PATH" "$directory/$UNIT_NAME" ||
    die "uninstall refused a drifted runner unit"
  cmp -s "$SESSION_UNIT_INSTALL_PATH" "$directory/$SESSION_UNIT_NAME" ||
    die "uninstall refused a drifted session unit"
  cmp -s "$LIFECYCLE_INSTALL_PATH" "$directory/$LIFECYCLE_NAME" ||
    die "uninstall refused a drifted lifecycle owner"
  cmp -s "$BUNDLE_INSTALL_PATH/$MANIFEST_NAME" "$directory/$MANIFEST_NAME" ||
    die "uninstall refused a drifted runner manifest"
  if [ -e "$UNIT_LINK_PATH" ] || [ -L "$UNIT_LINK_PATH" ]; then
    [ -L "$UNIT_LINK_PATH" ] &&
      [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ] ||
      die "uninstall refused a foreign unit link"
  fi
  if [ -e "$SESSION_UNIT_LINK_PATH" ] || [ -L "$SESSION_UNIT_LINK_PATH" ]; then
    [ -L "$SESSION_UNIT_LINK_PATH" ] &&
      [ "$(readlink "$SESSION_UNIT_LINK_PATH")" = "$SESSION_UNIT_INSTALL_PATH" ] ||
      die "uninstall refused a foreign session unit link"
  fi
  if [ -e "$CREDENTIAL_INSTALL_PATH" ] || [ -L "$CREDENTIAL_INSTALL_PATH" ]; then
    [ -f "$CREDENTIAL_INSTALL_PATH" ] && [ ! -L "$CREDENTIAL_INSTALL_PATH" ] ||
      die "uninstall refused a foreign credential"
  fi
  if [ -e "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
    [ -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ]; then
    [ -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] &&
      [ ! -L "$EXCHANGE_CREDENTIAL_INSTALL_PATH" ] ||
      die "uninstall refused a foreign exchange credential"
  fi
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled|not-found) ;;
    *) die "uninstall refused an enabled unit" ;;
  esac
  case "$(systemctl is-enabled "$SESSION_UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled|not-found) ;;
    *) die "uninstall refused an enabled session unit" ;;
  esac
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "uninstall refused boot enablement"
  [ ! -e "$session_wants_path" ] && [ ! -L "$session_wants_path" ] ||
    die "uninstall refused session boot enablement"
  if [ -L "$STATE_DIRECTORY" ]; then
    [ "$(readlink -f "$STATE_DIRECTORY")" = "$state_private" ] ||
      die "uninstall refused a foreign state link"
  elif [ -e "$STATE_DIRECTORY" ]; then
    [ -d "$STATE_DIRECTORY" ] || die "uninstall refused foreign state"
  fi

  if systemctl cat "$UNIT_NAME" >/dev/null 2>&1; then
    systemctl stop "$UNIT_NAME"
    systemctl clean --what=state "$UNIT_NAME"
  fi
  if systemctl cat "$SESSION_UNIT_NAME" >/dev/null 2>&1; then
    systemctl stop "$SESSION_UNIT_NAME"
  fi
  rm -f "$UNIT_LINK_PATH" "$SESSION_UNIT_LINK_PATH"
  systemctl daemon-reload
  rm -f "$CREDENTIAL_INSTALL_PATH"
  rm -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH"
  rm -rf "$STATE_DIRECTORY" "$state_private"
  rm -rf "$BUNDLE_INSTALL_PATH"

  for target in \
    "$BUNDLE_INSTALL_PATH" \
    "$UNIT_LINK_PATH" \
    "$SESSION_UNIT_LINK_PATH" \
    "$CREDENTIAL_INSTALL_PATH" \
    "$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    "$STATE_DIRECTORY" \
    "$state_private" \
    "$wants_path"; do
    [ ! -e "$target" ] && [ ! -L "$target" ] ||
      die "disabled uninstall retained: $target"
  done
  [ ! -e "$session_wants_path" ] && [ ! -L "$session_wants_path" ] ||
    die "disabled uninstall retained: $session_wants_path"
  systemctl cat "$UNIT_NAME" >/dev/null 2>&1 &&
    die "disabled uninstall retained the loaded unit"
  systemctl cat "$SESSION_UNIT_NAME" >/dev/null 2>&1 &&
    die "disabled uninstall retained the loaded session unit"

  trap - EXIT INT TERM
  rm -f "$lock_path"
  exec 9>&-
  echo "PASS trading-runner-artifact: uninstalled exact disabled unit"
}

ephemeral_install_smoke() {
  local directory="$1"
  install_disabled "$directory"
  trap 'uninstall_disabled "$directory" >/dev/null 2>&1 || true' EXIT INT TERM
  local started_at
  started_at="$(date --iso-8601=seconds)"
  systemctl start "$UNIT_NAME"
  local first_evidence
  first_evidence="$(wait_for_exact_unit_evidence "$started_at" 1)"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "active" ] ||
    die "ephemeral exact unit is not active after first cycle"
  [ "$(systemctl show -p NRestarts --value "$UNIT_NAME")" = "0" ] ||
    die "ephemeral exact unit restarted unexpectedly"

  systemctl stop "$UNIT_NAME"
  [ -f "$CREDENTIAL_INSTALL_PATH" ] ||
    die "encrypted runner credential disappeared across stop"
  [ -f "$STATE_DIRECTORY/stream/stream_identity.v1.json" ] ||
    die "runner identity state disappeared across stop"
  local restarted_at
  restarted_at="$(date --iso-8601=seconds)"
  systemctl start "$UNIT_NAME"
  local second_evidence
  second_evidence="$(wait_for_exact_unit_evidence "$restarted_at" 2)"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "active" ] ||
    die "ephemeral exact unit is not active after restart continuity"
  [ "$(systemctl show -p NRestarts --value "$UNIT_NAME")" = "0" ] ||
    die "restart continuity used an implicit supervisor restart"
  [ "$first_evidence" != "$second_evidence" ] ||
    die "restart continuity repeated the first evidence"
  local first_runner_key_id
  local second_runner_key_id
  first_runner_key_id="$(printf '%s\n' "$first_evidence" |
    sed -n 's/.* runner_key_id=\([0-9a-f]\{64\}\) .*/\1/p')"
  second_runner_key_id="$(printf '%s\n' "$second_evidence" |
    sed -n 's/.* runner_key_id=\([0-9a-f]\{64\}\) .*/\1/p')"
  [ -n "$first_runner_key_id" ] &&
    [ "$first_runner_key_id" = "$second_runner_key_id" ] ||
    die "restart continuity changed or omitted the runner key id"
  printf '%s\n%s\n' "$first_evidence" "$second_evidence"
  systemctl show "$UNIT_NAME" \
    -p MemoryMax \
    -p MemorySwapMax \
    -p TasksMax \
    -p DynamicUser \
    -p SocketBindDeny \
    -p RestrictAddressFamilies \
    -p NRestarts \
    --no-pager

  systemctl stop "$UNIT_NAME"
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "persistent disabled unit did not stop"
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "persistent disabled unit became enabled" ;;
  esac
  [ -f "$CREDENTIAL_INSTALL_PATH" ] ||
    die "persistent disabled credential disappeared after stop"
  [ -f "$STATE_DIRECTORY/stream/stream_identity.v1.json" ] ||
    die "persistent disabled state disappeared after stop"

  uninstall_disabled "$directory"
  trap - EXIT INT TERM
  echo "PASS trading-runner-artifact: exact disabled install retained identity and uninstalled without enablement"
}

self_test() {
  local root
  root="$(mktemp -d)"
  trap "rm -rf '$root'" EXIT

  local unit_target="$root/session-unit"
  local unit_link="$root/session-unit-link"
  local wants_link="$root/session-wants-link"
  : >"$unit_target"
  ln -s "$unit_target" "$unit_link"
  ln -s "$unit_target" "$wants_link"
  remove_exact_enablement_link "$wants_link" "$unit_target"
  [ ! -e "$wants_link" ] && [ ! -L "$wants_link" ] ||
    die "self-test retained session boot enablement"
  [ -L "$unit_link" ] &&
    [ "$(readlink -f "$unit_link")" = "$(readlink -f "$unit_target")" ] ||
    die "self-test removed the canonical session unit link"
  : >"$root/foreign-unit"
  ln -s "$root/foreign-unit" "$wants_link"
  if (remove_exact_enablement_link "$wants_link" "$unit_target") \
    >/dev/null 2>&1; then
    die "self-test removed foreign session boot enablement"
  fi
  rm -f "$wants_link"
  unset unit_target unit_link wants_link
  [ "$(session_service_pause_recovery_action inactive)" = "none" ] ||
    die "self-test changed inactive session pause semantics"
  [ "$(session_service_pause_recovery_action failed)" = "reset-failed" ] ||
    die "self-test did not recover a failed session pause"
  if session_service_pause_recovery_action active >/dev/null 2>&1; then
    die "self-test accepted an active session after stop"
  fi
  echo "PASS trading-runner-artifact: persistent session ownership and pause boundary"

  local operation_store="$root/deterministic-operation-store"
  local operation_a operation_b operation_c
  operation_a="$(printf 'operation-a' | sha256_stdin)"
  operation_b="$(printf 'operation-b' | sha256_stdin)"
  operation_c="$(printf 'operation-c' | sha256_stdin)"
  mkdir "$operation_store"
  printf '{}\n' >"$operation_store/$operation_a.json"
  validate_deterministic_operation_store "$operation_store" "$operation_b" 2
  printf '{}\n' >"$operation_store/$operation_b.json"
  validate_deterministic_operation_store "$operation_store" "$operation_a" 2
  if (validate_deterministic_operation_store \
    "$operation_store" "$operation_c" 2) >/dev/null 2>&1; then
    die "self-test allowed deterministic history beyond its bounded capacity"
  fi
  printf '{}\n' >"$operation_store/foreign.json"
  if (validate_deterministic_operation_store \
    "$operation_store" "$operation_a" 3) >/dev/null 2>&1; then
    die "self-test accepted foreign deterministic history state"
  fi
  rm "$operation_store/foreign.json"
  printf 'oversized\n' >"$operation_store/$operation_a.json"
  if (validate_deterministic_operation_store \
    "$operation_store" "$operation_a" 2 2) >/dev/null 2>&1; then
    die "self-test accepted oversized deterministic history state"
  fi
  printf '{}\n' >"$operation_store/$operation_a.json"
  echo "PASS trading-runner-artifact: bounded multi-cycle operation history"

  local lifecycle_store="$root/deterministic-lifecycle-results"
  local lifecycle_target="$root/deterministic-order.v4.json"
  local lifecycle_incoming="$root/deterministic-order-next.v4.json"
  mkdir "$lifecycle_store"
  printf 'mandate-a\n' >"$lifecycle_target"
  printf 'mandate-b\n' >"$lifecycle_incoming"
  printf '%s\n' \
    "{\"contract_version\":\"hivra-trading-deterministic-cycle-evidence-v1\",\"operation_id\":\"$operation_a\",\"state\":\"blocked\",\"reason_code\":\"market_evidence_stale\",\"effect\":false}" \
    >"$lifecycle_store/$operation_a.json"
  [ "$(retain_completed_deterministic_mandate \
    "$lifecycle_incoming" "$lifecycle_target" "$operation_b" \
    "$operation_a" "$lifecycle_store")" = \
    "rotated:$operation_a:$operation_b" ] ||
    die "self-test did not rotate a completed deterministic mandate"
  cmp -s "$lifecycle_incoming" "$lifecycle_target" ||
    die "self-test did not retain the next deterministic mandate"
  printf '%s\n' \
    "{\"contract_version\":\"hivra-trading-deterministic-cycle-evidence-v1\",\"operation_id\":\"$operation_b\",\"state\":\"blocked\",\"reason_code\":\"market_evidence_stale\",\"effect\":false}" \
    >"$lifecycle_store/$operation_b.json"
  printf 'historical-mandate-a\n' >"$lifecycle_incoming"
  [ "$(retain_completed_deterministic_mandate \
    "$lifecycle_incoming" "$lifecycle_target" "$operation_a" "" \
    "$lifecycle_store")" = "historical:$operation_a" ] ||
    die "self-test did not recognize historical deterministic replay"
  printf 'mandate-b\n' | cmp -s - "$lifecycle_target" ||
    die "self-test changed the active mandate during historical replay"
  rm "$lifecycle_store/$operation_b.json"
  printf 'mandate-c\n' >"$lifecycle_incoming"
  if (retain_completed_deterministic_mandate \
    "$lifecycle_incoming" "$lifecycle_target" "$operation_c" \
    "$operation_b" "$lifecycle_store") >/dev/null 2>&1; then
    die "self-test rotated an unresolved deterministic mandate"
  fi
  printf 'mandate-b\n' | cmp -s - "$lifecycle_target" ||
    die "self-test changed the active mandate after refused rotation"
  echo "PASS trading-runner-artifact: deterministic mandate lifecycle"

  local session_state="$root/deterministic-session.v1.json"
  local session_id session_cycle_0 session_cycle_1 session_status
  session_id="$(printf 'bounded-session' | sha256_stdin)"
  session_cycle_0="$(derive_deterministic_session_cycle_operation_id "$session_id" 0)"
  [ "$session_cycle_0" = "$(python3 - "$session_id" <<'PY'
import hashlib
import json
import sys
print(hashlib.sha256(
    b"hivra:bingx-futures-remote-session-cycle:v1\n" +
    json.dumps({"session_operation_id": sys.argv[1], "cycle_index": 0}, separators=(",", ":")).encode()
).hexdigest())
PY
  )" ] || die "self-test found cross-language deterministic session identity drift"
  if prepare_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1 60 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z" \
    >/dev/null 2>&1; then
    die "self-test executed a deterministic session before explicit activation"
  fi
  [ "$(prepare_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1 60 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z" \
    activate)" = "active:0:0" ] ||
    die "self-test did not explicitly activate deterministic session state"
  [ "$(prepare_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1 60 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z" \
    activate)" = "active:0:0" ] ||
    die "self-test did not replay deterministic session activation"
  session_status="$(prepare_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1 60 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z")"
  [ "$session_status" = "ready:0:0" ] ||
    die "self-test did not initialize a deterministic session"
  [ "$(advance_deterministic_session_cycle \
    "$session_state" "$session_id" 0 "$session_cycle_0" \
    "blocked:market_evidence_stale" 4 1)" = "active:1:0" ] ||
    die "self-test did not advance a blocked deterministic session cycle"
  if advance_deterministic_session_cycle \
    "$session_state" "$session_id" 0 "$session_cycle_0" \
    "blocked:market_evidence_stale" 4 1 >/dev/null 2>&1; then
    die "self-test replayed an already committed deterministic session cycle"
  fi
  session_cycle_1="$(derive_deterministic_session_cycle_operation_id "$session_id" 1)"
  [ "$(prepare_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1 60 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z")" = \
    "ready:1:0" ] || die "self-test did not recover deterministic session state"
  if advance_deterministic_session_cycle \
    "$session_state" "$session_id" 1 "$session_cycle_0" \
    "effect:succeeded:test=true" 4 1 >/dev/null 2>&1; then
    die "self-test accepted a caller-selected deterministic session cycle id"
  fi
  [ "$(advance_deterministic_session_cycle \
    "$session_state" "$session_id" 1 "$session_cycle_1" \
    "effect:succeeded:test=true" 4 1)" = "stopped:2:1" ] ||
    die "self-test did not stop at the deterministic session effect bound"
  [ "$(prepare_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1 60 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z")" = \
    "terminal:stopped:2:1" ] ||
    die "self-test resurrected a terminal deterministic session"
  [ "$(inspect_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1)" = "stopped:2:1" ] ||
    die "self-test did not inspect terminal session state without mutation"
  python3 - "$session_state" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text())
value["last_cycle_operation_id"] = "0" * 64
path.write_text(json.dumps(value, separators=(",", ":")) + "\n")
PY
  if prepare_deterministic_session_cycle \
    "$session_state" "$session_id" 4 1 60 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z" \
    >/dev/null 2>&1; then
    die "self-test accepted mutated deterministic session state"
  fi
  local future_session_state="$root/future-deterministic-session.v1.json"
  [ "$(prepare_deterministic_session_cycle \
    "$future_session_state" "$(printf 'future-session' | sha256_stdin)" \
    2 1 300 "2998-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z" \
    activate)" = "active:0:0" ] ||
    die "self-test did not activate a future bounded session without execution"
  if prepare_deterministic_session_cycle \
    "$future_session_state" "$(printf 'future-session' | sha256_stdin)" \
    2 1 300 "2998-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z" \
    >/dev/null 2>&1; then
    die "self-test executed a deterministic session cycle before its signed start"
  fi
  [ "$(deterministic_session_scheduler_decision \
    "active:0:0" 300 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T01:00:00.000Z" "2000-01-01T00:00:00.000Z")" = \
    "ready:0" ] || die "self-test scheduler missed an eligible first cycle"
  [ "$(deterministic_session_scheduler_decision \
    "active:1:0" 300 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T01:00:00.000Z" "2000-01-01T00:00:00.000Z")" = \
    "wait:300" ] || die "self-test scheduler changed the signed cadence"
  [ "$(deterministic_session_scheduler_decision \
    "active:1:0" 300 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T00:04:00.000Z" "2000-01-01T00:04:00.000Z")" = \
    "ready:1" ] || die "self-test scheduler did not settle an expired session"
  [ "$(deterministic_session_scheduler_decision \
    "active:0:0" 300 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T01:00:00.000Z" "2000-01-01T00:05:00.000Z")" = \
    "stale:0" ] || die "self-test scheduler attempted cadence catch-up"
  local stale_session_state="$root/stale-deterministic-session.v1.json"
  local stale_session_id
  stale_session_id="$(printf 'stale-session' | sha256_stdin)"
  [ "$(prepare_deterministic_session_cycle \
    "$stale_session_state" "$stale_session_id" 2 1 300 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z" activate)" = \
    "active:0:0" ] || die "self-test did not activate stale session state"
  terminalize_stale_deterministic_session \
    "$stale_session_state" "$stale_session_id" ||
    die "self-test did not terminalize stale session state"
  [ "$(prepare_deterministic_session_cycle \
    "$stale_session_state" "$stale_session_id" 2 1 300 \
    "2000-01-01T00:00:00.000Z" "2999-01-01T00:00:00.000Z")" = \
    "terminal:stopped:0:0" ] ||
    die "self-test resurrected terminalized stale session state"
  [ "$(deterministic_session_scheduler_decision \
    "stopped:1:0" 300 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T01:00:00.000Z" "2000-01-01T00:00:00.000Z")" = \
    "terminal:stopped:1" ] || die "self-test scheduler resurrected terminal state"
  [ "$(deterministic_session_scheduler_decision_with_revocation \
    "active:1:0" true 300 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T01:00:00.000Z" "2000-01-01T00:00:00.000Z")" = \
    "ready:revocation" ] || die "self-test scheduler ignored active revocation"
  [ "$(deterministic_session_scheduler_decision_with_revocation \
    "stopped:1:0" true 300 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T01:00:00.000Z" "2000-01-01T00:00:00.000Z")" = \
    "terminal:stopped:1" ] ||
    die "self-test scheduler looped on retained terminal revocation"
  if deterministic_session_scheduler_decision \
    "active:1:0" 30 "2000-01-01T00:00:00.000Z" \
    "2000-01-01T01:00:00.000Z" "2000-01-01T00:00:00.000Z" \
    >/dev/null 2>&1; then
    die "self-test scheduler accepted an invalid cadence"
  fi
  echo "PASS trading-runner-artifact: bounded restart-safe deterministic session"
  unset session_state session_id session_cycle_0 session_cycle_1 session_status future_session_state stale_session_state stale_session_id

  local artifact="$root/artifact"
  mkdir "$artifact"
  cp /bin/echo "$artifact/$BINARY_NAME"
  cp /bin/echo "$artifact/$EFFECT_BINARY_NAME"
  printf '%s\n' \
    'openApi/swap/v3/user/balance' \
    'openApi/swap/v2/user/positions' \
    'openApi/swap/v2/trade/openOrders' \
    'hivra-trading-account-read-evidence-v2' \
    'balance,positions,open_orders' >> "$artifact/$BINARY_NAME"
  printf '%s\n' \
    'openApi/swap/v2/trade/order' \
    'openApi/swap/v2/trade/order/test' \
    'hivra-trading-exact-order-evidence-v1' \
    'trading-remote-mandate-admission-v4' \
    'trading-remote-mandate-admission-v5' \
    'one_deterministic_order' \
    'bounded_deterministic_session' \
    'hivra-trading-deterministic-cycle-evidence-v1' \
    'hivra-trading-exact-order-recovery-v1' >> "$artifact/$EFFECT_BINARY_NAME"
  chmod 700 "$artifact/$BINARY_NAME"
  chmod 700 "$artifact/$EFFECT_BINARY_NAME"
  cp "$UNIT_SOURCE" "$artifact/$UNIT_NAME"
  chmod 600 "$artifact/$UNIT_NAME"
  cp "$SESSION_UNIT_SOURCE" "$artifact/$SESSION_UNIT_NAME"
  chmod 600 "$artifact/$SESSION_UNIT_NAME"
  cp "$LIFECYCLE_SOURCE" "$artifact/$LIFECYCLE_NAME"
  chmod 700 "$artifact/$LIFECYCLE_NAME"
  write_manifest "$artifact" "$(git -C "$ROOT" rev-parse HEAD)" "3.11.0" "$(host_os)" "$(host_arch)" "$(sha256_file "$PACKAGE_LOCK")"
  verify_artifact "$artifact" >/dev/null

  if (runtime_smoke_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a non-runner executable for runtime smoke"
  fi

  local credential_json
  credential_json="$(printf 'bounded-api-key\nbounded-api-secret\n' |
    canonicalize_exchange_credential_input)"
  [ "$credential_json" = \
    '{"contract_version":"bingx-exchange-credential-v1","api_key":"bounded-api-key","api_secret":"bounded-api-secret"}' ] ||
    die "self-test did not produce canonical exchange credential bytes"
  [ "$(printf '%s' "$credential_json" | exchange_credential_account_hash)" = \
    "$(printf 'bounded-api-key' | sha256_stdin)" ] ||
    die "self-test produced the wrong exchange account binding"
  exchange_credential_matches_account_binding \
    "$credential_json" "$(printf 'bounded-api-key' | sha256_stdin)" ||
    die "self-test rejected the exact exchange account binding"
  if exchange_credential_matches_account_binding \
    "$credential_json" "$(printf 'wrong-api-key' | sha256_stdin)"; then
    die "self-test accepted the wrong exchange account binding"
  fi
  if (printf 'only-one-line\n' | canonicalize_exchange_credential_input) >/dev/null 2>&1; then
    die "self-test accepted missing exchange credential input"
  fi
  if (printf 'key\nsecret\nextra\n' | canonicalize_exchange_credential_input) >/dev/null 2>&1; then
    die "self-test accepted extra exchange credential input"
  fi
  if (printf 'key with space\nsecret\n' | canonicalize_exchange_credential_input) >/dev/null 2>&1; then
    die "self-test accepted malformed exchange credential input"
  fi
  unset credential_json

  local deterministic_operation_id deterministic_outcome
  deterministic_operation_id="$(printf 'deterministic-outcome' | sha256_stdin)"
  deterministic_outcome="$root/deterministic-blocked.json"
  printf '%s\n' \
    "{\"contract_version\":\"hivra-trading-deterministic-cycle-evidence-v1\",\"operation_id\":\"$deterministic_operation_id\",\"state\":\"blocked\",\"reason_code\":\"account_risk_incomplete\",\"effect\":false}" \
    >"$deterministic_outcome"
  [ "$(validate_deterministic_cycle_outcome \
    "$deterministic_outcome" "$deterministic_operation_id")" = \
    "blocked:account_risk_incomplete" ] ||
    die "self-test rejected a canonical deterministic blocked outcome"
  if validate_deterministic_cycle_outcome \
    "$deterministic_outcome" "$(printf 'foreign-operation' | sha256_stdin)" \
    >/dev/null 2>&1; then
    die "self-test accepted a blocked deterministic outcome for another operation"
  fi
  printf '%s\n' \
    "{\"contract_version\":\"hivra-trading-exact-order-evidence-v1\",\"operation_id\":\"$deterministic_operation_id\",\"state\":\"succeeded\",\"attempt_count\":1,\"provider_reference_id\":\"test-endpoint\",\"receipt_evidence_hash_hex\":\"$(printf 'receipt' | sha256_stdin)\",\"test_order\":true}" \
    >"$root/deterministic-effect.json"
  [ "$(validate_deterministic_cycle_outcome \
    "$root/deterministic-effect.json" "$deterministic_operation_id")" = \
    "effect:succeeded:test=true" ] ||
    die "self-test rejected a canonical deterministic effect outcome"
  printf '%s\n' \
    "{\"contract_version\":\"hivra-trading-exact-order-recovery-v1\",\"operation_id\":\"$deterministic_operation_id\",\"state\":\"absent\",\"effect\":false}" \
    >"$root/deterministic-recovery-empty.json"
  [ "$(validate_deterministic_recovery_outcome \
    "$root/deterministic-recovery-empty.json" "$deterministic_operation_id")" = \
    "no_effect:absent" ] ||
    die "self-test rejected canonical no-effect recovery evidence"
  local recovery_store="$root/deterministic-recovery-results"
  local recovery_session recovery_operation
  mkdir "$recovery_store"
  recovery_session="$(printf 'recovery-session' | sha256_stdin)"
  recovery_operation="$(derive_deterministic_session_cycle_operation_id \
    "$recovery_session" 0)"
  printf '%s\n' \
    "{\"contract_version\":\"hivra-trading-exact-order-evidence-v1\",\"operation_id\":\"$recovery_operation\",\"state\":\"unresolved\",\"attempt_count\":1,\"provider_reference_id\":null,\"receipt_evidence_hash_hex\":null,\"test_order\":false}" \
    >"$recovery_store/$recovery_operation.json"
  [ "$(select_deterministic_recovery_cycle \
    'stopped:1:1' "$recovery_session" "$recovery_store" false)" = 0 ] ||
    die "self-test did not select the stopped unresolved cycle"
  [ "$(select_deterministic_recovery_cycle \
    'stopped:1:1' "$recovery_session" "$recovery_store" true)" = 1 ] ||
    die "self-test crossed an explicit session revocation"
  if validate_deterministic_cycle_outcome \
    "$root/deterministic-effect.json" "$(printf 'foreign-operation' | sha256_stdin)" \
    >/dev/null 2>&1; then
    die "self-test accepted a deterministic outcome for another operation"
  fi
  printf '%s\n' \
    "{\"contract_version\":\"hivra-trading-deterministic-cycle-evidence-v1\",\"operation_id\":\"$deterministic_operation_id\",\"state\":\"blocked\",\"reason_code\":\"Account Risk\",\"effect\":false}" \
    >"$root/deterministic-mutated.json"
  if validate_deterministic_cycle_outcome \
    "$root/deterministic-mutated.json" "$deterministic_operation_id" \
    >/dev/null 2>&1; then
    die "self-test accepted a non-canonical deterministic reason code"
  fi
  unset deterministic_operation_id deterministic_outcome recovery_store recovery_session recovery_operation

  sed -i.bak 's/^binary_sha256=./binary_sha256=0/' "$artifact/$MANIFEST_NAME"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a changed binary hash"
  fi
  mv "$artifact/$MANIFEST_NAME.bak" "$artifact/$MANIFEST_NAME"

  printf '\n# mutation\n' >> "$artifact/$UNIT_NAME"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a changed supervisor unit"
  fi
  cp "$UNIT_SOURCE" "$artifact/$UNIT_NAME"
  chmod 600 "$artifact/$UNIT_NAME"

  sed -i.bak \
    's#^binary_install_path=.*#binary_install_path=/tmp/runner#' \
    "$artifact/$MANIFEST_NAME"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted an alternate install path"
  fi
  mv "$artifact/$MANIFEST_NAME.bak" "$artifact/$MANIFEST_NAME"

  sed -i.bak \
    's/^dependency_lock_sha256=./dependency_lock_sha256=0/' \
    "$artifact/$MANIFEST_NAME"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a changed dependency lock hash"
  fi
  mv "$artifact/$MANIFEST_NAME.bak" "$artifact/$MANIFEST_NAME"

  sed -i.bak \
    's/^source_commit=.*/source_commit=0000000000000000000000000000000000000000/' \
    "$artifact/$MANIFEST_NAME"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted an unavailable source commit"
  fi
  mv "$artifact/$MANIFEST_NAME.bak" "$artifact/$MANIFEST_NAME"

  touch "$artifact/unexpected"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted an unknown artifact entry"
  fi
  rm -f "$artifact/unexpected"

  if [ "$(host_os)" = "darwin" ]; then
    sed -i.bak \
      -e 's/^target_os=.*/target_os=linux/' \
      -e 's/^target_arch=.*/target_arch=x64/' \
      "$artifact/$MANIFEST_NAME"
  else
    sed -i.bak \
      -e 's/^target_os=.*/target_os=darwin/' \
      -e 's/^target_arch=.*/target_arch=arm64/' \
      "$artifact/$MANIFEST_NAME"
  fi
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a target/binary mismatch"
  fi
  mv "$artifact/$MANIFEST_NAME.bak" "$artifact/$MANIFEST_NAME"

  printf '\n--cancel-order forbidden\n' >> "$artifact/$EFFECT_BINARY_NAME"
  write_manifest "$artifact" "$(git -C "$ROOT" rev-parse HEAD)" "3.11.0" "$(host_os)" "$(host_arch)" "$(sha256_file "$PACKAGE_LOCK")"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a widened-authority option"
  fi

  local account_evidence="$root/account-read-evidence.json"
  local account_operation account_runner account_binding
  account_operation="$(printf 'operation' | sha256_stdin)"
  account_runner="$(printf 'runner' | sha256_stdin)"
  account_binding="$(printf 'account' | sha256_stdin)"
  python3 - "$account_evidence" "$account_operation" "$account_runner" "$account_binding" <<'PY'
import datetime
import json
import pathlib
import sys

path, operation, runner, account = sys.argv[1:]
value = {
    "contract_version": "hivra-trading-account-read-evidence-v2",
    "account_read_operation_id": operation,
    "runner_key_id": runner,
    "account_binding_hash_hex": account,
    "read_scope": ["balance", "positions", "open_orders"],
    "max_uses": 1,
    "observed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "checks": [
        {"name": "balance", "success": True},
        {"name": "positions", "success": True},
        {"name": "open_orders", "success": True},
    ],
    "effect": False,
}
pathlib.Path(path).write_text(json.dumps(value, separators=(",", ":")) + "\n", encoding="utf-8")
PY
  validate_account_read_evidence \
    "$account_evidence" "$account_operation" "$account_runner" "$account_binding" >/dev/null
  sed -i.bak 's/"effect":false/"effect":true/' "$account_evidence"
  if (validate_account_read_evidence \
    "$account_evidence" "$account_operation" "$account_runner" "$account_binding") >/dev/null 2>&1; then
    die "self-test accepted effectful account-read evidence"
  fi
  mv "$account_evidence.bak" "$account_evidence"

  local account_journal_dir="$root/account-read-journal"
  local account_journal="$account_journal_dir/$account_operation.json"
  local account_replay="$account_journal_dir/replay.json"
  mkdir "$account_journal_dir"
  commit_account_read_operation_journal \
    "$account_journal" "$account_operation" "$account_runner" \
    "$account_binding" pending
  [ "$(validate_account_read_operation_journal \
    "$account_journal" "$account_operation" "$account_runner" \
    "$account_binding" "$account_replay")" = pending ] ||
    die "self-test lost pending account-read operation"
  [ ! -e "$account_replay" ] ||
    die "self-test projected evidence from a pending account-read operation"
  commit_account_read_operation_journal \
    "$account_journal" "$account_operation" "$account_runner" \
    "$account_binding" completed "$account_evidence"
  [ "$(validate_account_read_operation_journal \
    "$account_journal" "$account_operation" "$account_runner" \
    "$account_binding" "$account_replay")" = completed ] ||
    die "self-test lost completed account-read operation"
  [ "$(validate_account_read_evidence \
    "$account_replay" "$account_operation" "$account_runner" \
    "$account_binding")" = "$(validate_account_read_evidence \
    "$account_evidence" "$account_operation" "$account_runner" \
    "$account_binding")" ] ||
    die "self-test changed retained account-read evidence"
  cp "$account_journal" "$account_journal.mutated"
  sed -i.bak 's/"max_uses":1/"max_uses":2/' "$account_journal.mutated"
  if (validate_account_read_operation_journal \
    "$account_journal.mutated" "$account_operation" "$account_runner" \
    "$account_binding" "$account_journal_dir/mutated-evidence.json") >/dev/null 2>&1; then
    die "self-test accepted widened account-read journal authority"
  fi

  local mandate_test="$root/mandate-test"
  mkdir "$mandate_test"
  openssl genpkey -algorithm ED25519 -out "$mandate_test/capsule.pem" >/dev/null 2>&1
  openssl pkey -in "$mandate_test/capsule.pem" -pubout -outform DER \
    -out "$mandate_test/capsule.der" >/dev/null 2>&1
  tail -c 32 "$mandate_test/capsule.der" | xxd -p -c 64 > "$mandate_test/capsule.hex"
  python3 - "$mandate_test" <<'PY'
import datetime
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
capsule = (root / "capsule.hex").read_text(encoding="ascii").strip()
runner = hashlib.sha256(b"pass-s-runner").hexdigest()
now = datetime.datetime.now(datetime.timezone.utc)

def write_case(name, issued, expires):
    semantic = {
        "capsule_root_hex": capsule,
        "account_binding_hash_hex": hashlib.sha256(b"account").hexdigest(),
        "symbol": "BTC-USDT",
        "test_order": True,
        "issued_at_utc": issued.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "expires_at_utc": expires.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "max_order_notional_quote_decimal": "100",
        "max_risk_per_trade_percent": 2.0,
        "max_daily_loss_percent": 5.0,
        "max_concurrent_positions": 3,
        "cooldown_after_loss_streak": 2,
        "cooldown_minutes": 60,
        "max_effects": 32,
    }
    mandate_id = hashlib.sha256(
        b"hivra:bingx-futures-trading-mandate:v1\n" +
        json.dumps(semantic, separators=(",", ":")).encode()
    ).hexdigest()
    mandate = {"version": 1, "mandate_id": mandate_id, **semantic, "revoked_at_utc": None}
    commitment_semantic = {
        "contract_version": "trading-remote-mandate-admission-v2",
        "runner_key_id": runner,
        "operation_kind": "account_read",
        "read_scope": ["balance", "positions", "open_orders"],
        "max_uses": 1,
        "mandate": mandate,
    }
    commitment = hashlib.sha256(
        b"hivra:bingx-futures-remote-mandate-admission:v2\n" +
        json.dumps(commitment_semantic, separators=(",", ":")).encode()
    ).hexdigest()
    (root / f"{name}digest.bin").write_bytes(bytes.fromhex(commitment))
    (root / f"{name}metadata.json").write_text(json.dumps({
        "runner": runner,
        "commitment": commitment,
        "mandate": mandate,
    }, separators=(",", ":")), encoding="utf-8")

write_case("", now - datetime.timedelta(minutes=1), now + datetime.timedelta(minutes=59))
write_case("expired-", now - datetime.timedelta(hours=2), now - datetime.timedelta(hours=1))
PY
  openssl pkeyutl -sign -inkey "$mandate_test/capsule.pem" -rawin \
    -in "$mandate_test/digest.bin" -out "$mandate_test/signature.bin"
  openssl pkeyutl -sign -inkey "$mandate_test/capsule.pem" -rawin \
    -in "$mandate_test/expired-digest.bin" -out "$mandate_test/expired-signature.bin"
  python3 - "$mandate_test" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for name in ("", "expired-"):
    metadata = json.loads((root / f"{name}metadata.json").read_text())
    artifact = {
        "contract_version": "trading-remote-mandate-admission-v2",
        "operation_id": metadata["commitment"],
        "commitment_hash_hex": metadata["commitment"],
        "runner_key_id": metadata["runner"],
        "operation_kind": "account_read",
        "read_scope": ["balance", "positions", "open_orders"],
        "max_uses": 1,
        "mandate": metadata["mandate"],
        "signature_suite": "ed25519-v1",
        "signature_hex": (root / f"{name}signature.bin").read_bytes().hex(),
    }
    (root / f"{name}admission.json").write_text(
        json.dumps(artifact, separators=(",", ":")), encoding="utf-8"
    )
PY
  local expected_runner
  expected_runner="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runner_key_id"])' "$mandate_test/admission.json")"
  python3 - "$mandate_test" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "metadata.json").read_text())
exact_order = {
    "client_order_id": "hivra-self-test-1",
    "symbol": "BTC-USDT",
    "side": "buy",
    "order_type": "limit",
    "quantity_decimal": "0.01",
    "limit_price_decimal": "100",
    "time_in_force": "GTC",
    "entry_mode": "zone_pending",
    "trigger_price_decimal": "99",
    "stop_loss_decimal": None,
    "take_profit_decimal": None,
    "intent_hash_hex": hashlib.sha256(b"intent").hexdigest(),
    "test_order": True,
}
semantic = {
    "contract_version": "trading-remote-mandate-admission-v3",
    "runner_key_id": metadata["runner"],
    "operation_kind": "one_exact_order",
    "exact_order": exact_order,
    "max_uses": 1,
    "mandate": metadata["mandate"],
}
commitment = hashlib.sha256(
    b"hivra:bingx-futures-remote-mandate-admission:v3\n" +
    json.dumps(semantic, separators=(",", ":")).encode()
).hexdigest()
(root / "exact-digest.bin").write_bytes(bytes.fromhex(commitment))
(root / "exact-metadata.json").write_text(json.dumps({
    "commitment": commitment,
    "semantic": semantic,
}, separators=(",", ":")), encoding="utf-8")
PY
  openssl pkeyutl -sign -inkey "$mandate_test/capsule.pem" -rawin \
    -in "$mandate_test/exact-digest.bin" -out "$mandate_test/exact-signature.bin"
  python3 - "$mandate_test" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "exact-metadata.json").read_text())
semantic = metadata["semantic"]
artifact = {
    "contract_version": semantic["contract_version"],
    "operation_id": metadata["commitment"],
    "commitment_hash_hex": metadata["commitment"],
    "runner_key_id": semantic["runner_key_id"],
    "operation_kind": semantic["operation_kind"],
    "exact_order": semantic["exact_order"],
    "max_uses": semantic["max_uses"],
    "mandate": semantic["mandate"],
    "signature_suite": "ed25519-v1",
    "signature_hex": (root / "exact-signature.bin").read_bytes().hex(),
}
(root / "exact-admission.json").write_text(
    json.dumps(artifact, separators=(",", ":")), encoding="utf-8"
)
PY
  mkdir "$mandate_test/exact-verified"
  verify_remote_mandate_artifact \
    "$mandate_test/exact-admission.json" "$expected_runner" \
    "$mandate_test/exact-verified"
  [ "$(cat "$mandate_test/exact-verified/operation-kind")" = "one_exact_order" ] ||
    die "self-test lost exact-order operation kind"
  local expected_exact_effect
  expected_exact_effect="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["exact_order"]["intent_hash_hex"])' "$mandate_test/exact-admission.json")"
  [ "$(cat "$mandate_test/exact-verified/effect-operation-id")" = "$expected_exact_effect" ] ||
    die "self-test lost exact-order effect identity"
  cp "$mandate_test/exact-admission.json" "$mandate_test/exact-mutated.json"
  sed -i.bak 's/"quantity_decimal":"0.01"/"quantity_decimal":"0.02"/' \
    "$mandate_test/exact-mutated.json"
  mkdir "$mandate_test/exact-mutated-verified"
  if (verify_remote_mandate_artifact \
    "$mandate_test/exact-mutated.json" "$expected_runner" \
    "$mandate_test/exact-mutated-verified") >/dev/null 2>&1; then
    die "self-test accepted mutated exact-order semantics"
  fi
  python3 - "$mandate_test" <<'PY'
import datetime
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "metadata.json").read_text())
starts = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
strategy = {
    "runner_build_id": "systemd-public-shadow-v1",
    "plugin_id": "hivra.bingx-futures-trading",
    "plugin_version": "0.2.3",
    "package_digest_hex": "2cb440885a2fa473971364fb26cce304d079d393832b2b5bed6fd95517e61889",
    "host_abi": "wasm32-wasi-preview1",
    "stop_loss_percent": 5.0,
    "minimum_risk_reward": 2.0,
}
session = {
    "starts_at_utc": starts,
    "interval_seconds": 300,
    "max_cycles": 12,
    "stop_on_failure": True,
}
semantic = {
    "contract_version": "trading-remote-mandate-admission-v5",
    "runner_key_id": metadata["runner"],
    "operation_kind": "bounded_deterministic_session",
    "strategy_policy": strategy,
    "session_policy": session,
    "max_uses": 12,
    "mandate": metadata["mandate"],
}
commitment = hashlib.sha256(
    b"hivra:bingx-futures-remote-mandate-admission:v5\n" +
    json.dumps(semantic, separators=(",", ":")).encode()
).hexdigest()
(root / "session-digest.bin").write_bytes(bytes.fromhex(commitment))
(root / "session-metadata.json").write_text(json.dumps({
    "commitment": commitment,
    "semantic": semantic,
}, separators=(",", ":")), encoding="utf-8")
PY
  openssl pkeyutl -sign -inkey "$mandate_test/capsule.pem" -rawin \
    -in "$mandate_test/session-digest.bin" -out "$mandate_test/session-signature.bin"
  python3 - "$mandate_test" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "session-metadata.json").read_text())
semantic = metadata["semantic"]
artifact = {
    "contract_version": semantic["contract_version"],
    "operation_id": metadata["commitment"],
    "commitment_hash_hex": metadata["commitment"],
    "runner_key_id": semantic["runner_key_id"],
    "operation_kind": semantic["operation_kind"],
    "strategy_policy": semantic["strategy_policy"],
    "session_policy": semantic["session_policy"],
    "max_uses": semantic["max_uses"],
    "mandate": semantic["mandate"],
    "signature_suite": "ed25519-v1",
    "signature_hex": (root / "session-signature.bin").read_bytes().hex(),
}
(root / "session-admission.json").write_text(
    json.dumps(artifact, separators=(",", ":")), encoding="utf-8"
)
PY
  mkdir "$mandate_test/session-verified"
  verify_remote_mandate_artifact \
    "$mandate_test/session-admission.json" "$expected_runner" \
    "$mandate_test/session-verified"
  [ "$(cat "$mandate_test/session-verified/operation-kind")" = \
    "bounded_deterministic_session" ] ||
    die "self-test lost deterministic session operation kind"
  [ "$(cat "$mandate_test/session-verified/session-max-cycles")" = 12 ] ||
    die "self-test lost deterministic session cycle bound"
  cp "$mandate_test/session-admission.json" "$mandate_test/session-mutated.json"
  sed -i.bak 's/"max_cycles":12/"max_cycles":13/' \
    "$mandate_test/session-mutated.json"
  mkdir "$mandate_test/session-mutated-verified"
  if (verify_remote_mandate_artifact \
    "$mandate_test/session-mutated.json" "$expected_runner" \
    "$mandate_test/session-mutated-verified") >/dev/null 2>&1; then
    die "self-test accepted mutated deterministic session semantics"
  fi
  python3 - "$mandate_test" <<'PY'
import datetime
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
session = json.loads((root / "session-admission.json").read_text())
semantic = {
    "contract_version": "trading-remote-session-revocation-v1",
    "target_session_operation_id": session["operation_id"],
    "runner_key_id": session["runner_key_id"],
    "capsule_root_hex": session["mandate"]["capsule_root_hex"],
    "revoked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z"),
}
commitment = hashlib.sha256(
    b"hivra:bingx-futures-remote-session-revocation:v1\n" +
    json.dumps(semantic, separators=(",", ":")).encode()
).hexdigest()
(root / "revocation-digest.bin").write_bytes(bytes.fromhex(commitment))
(root / "revocation-metadata.json").write_text(json.dumps({
    "commitment": commitment,
    "semantic": semantic,
}, separators=(",", ":")), encoding="utf-8")
PY
  openssl pkeyutl -sign -inkey "$mandate_test/capsule.pem" -rawin \
    -in "$mandate_test/revocation-digest.bin" \
    -out "$mandate_test/revocation-signature.bin"
  python3 - "$mandate_test" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "revocation-metadata.json").read_text())
semantic = metadata["semantic"]
artifact = {
    **semantic,
    "revocation_id": metadata["commitment"],
}
artifact = {
    "contract_version": semantic["contract_version"],
    "revocation_id": metadata["commitment"],
    "target_session_operation_id": semantic["target_session_operation_id"],
    "runner_key_id": semantic["runner_key_id"],
    "capsule_root_hex": semantic["capsule_root_hex"],
    "revoked_at_utc": semantic["revoked_at_utc"],
    "signature_suite": "ed25519-v1",
    "signature_hex": (root / "revocation-signature.bin").read_bytes().hex(),
}
(root / "session-revocation.json").write_text(
    json.dumps(artifact, separators=(",", ":")), encoding="utf-8"
)
PY
  mkdir "$mandate_test/revocation-verified"
  verify_remote_session_revocation_artifact \
    "$mandate_test/session-revocation.json" "$expected_runner" \
    "$(cat "$mandate_test/session-verified/operation-id")" \
    "$(cat "$mandate_test/session-verified/capsule-root")" \
    "$mandate_test/revocation-verified"
  cp "$mandate_test/session-revocation.json" \
    "$mandate_test/session-revocation-mutated.json"
  sed -i.bak 's/"runner_key_id":"[0-9a-f]*"/"runner_key_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"/' \
    "$mandate_test/session-revocation-mutated.json"
  mkdir "$mandate_test/revocation-mutated-verified"
  if (verify_remote_session_revocation_artifact \
    "$mandate_test/session-revocation-mutated.json" "$expected_runner" \
    "$(cat "$mandate_test/session-verified/operation-id")" \
    "$(cat "$mandate_test/session-verified/capsule-root")" \
    "$mandate_test/revocation-mutated-verified") >/dev/null 2>&1; then
    die "self-test accepted mutated session revocation"
  fi
  local revoked_state="$mandate_test/revoked-session-state.json"
  prepare_deterministic_session_cycle \
    "$revoked_state" "$(cat "$mandate_test/session-verified/operation-id")" \
    12 32 300 \
    "$(cat "$mandate_test/session-verified/session-starts-at")" \
    "$(cat "$mandate_test/session-verified/expires-at")" activate >/dev/null
  [ "$(stop_deterministic_session_state \
    "$revoked_state" "$(cat "$mandate_test/session-verified/operation-id")")" = \
    stopped ] || die "self-test did not stop deterministic session"
  [ "$(stop_deterministic_session_state \
    "$revoked_state" "$(cat "$mandate_test/session-verified/operation-id")")" = \
    stopped ] || die "self-test lost idempotent session revocation"
  case "$(prepare_deterministic_session_cycle \
    "$revoked_state" "$(cat "$mandate_test/session-verified/operation-id")" \
    12 32 300 \
    "$(cat "$mandate_test/session-verified/session-starts-at")" \
    "$(cat "$mandate_test/session-verified/expires-at")")" in
    terminal:stopped:0:0) ;;
    *) die "self-test resumed revoked deterministic session" ;;
  esac
  cp "$revoked_state" "$mandate_test/revoked-session-state-mutated.json"
  sed -i.bak 's/"consumed_effects":0/"consumed_effects":-1/' \
    "$mandate_test/revoked-session-state-mutated.json"
  if (stop_deterministic_session_state \
    "$mandate_test/revoked-session-state-mutated.json" \
    "$(cat "$mandate_test/session-verified/operation-id")") >/dev/null 2>&1; then
    die "self-test accepted malformed session state during revocation"
  fi
  mkdir "$mandate_test/verified"
  verify_remote_mandate_artifact \
    "$mandate_test/admission.json" "$expected_runner" "$mandate_test/verified"
  require_remote_mandate_execution_eligible "$mandate_test/verified"
  mkdir "$mandate_test/expired-verified"
  verify_remote_mandate_artifact \
    "$mandate_test/expired-admission.json" "$expected_runner" \
    "$mandate_test/expired-verified"
  if (require_remote_mandate_execution_eligible \
    "$mandate_test/expired-verified") >/dev/null 2>&1; then
    die "self-test accepted expired unused account-read authority"
  fi
  local expired_operation expired_account expired_journal_dir expired_journal
  local expired_replay expired_evidence
  expired_operation="$(cat "$mandate_test/expired-verified/operation-id")"
  expired_account="$(cat "$mandate_test/expired-verified/account-binding")"
  expired_journal_dir="$mandate_test/expired-journal"
  expired_journal="$expired_journal_dir/$expired_operation.json"
  expired_replay="$mandate_test/expired-replay.json"
  expired_evidence="$mandate_test/expired-evidence.json"
  mkdir "$expired_journal_dir"
  if (resolve_account_read_operation_before_provider \
    "$expired_journal_dir" "$expired_journal" "$expired_operation" \
    "$expected_runner" "$expired_account" "$mandate_test/expired-verified" \
    "$expired_replay") >/dev/null 2>&1; then
    die "self-test allowed an expired unused account read to reach the provider boundary"
  fi
  commit_account_read_operation_journal \
    "$expired_journal" "$expired_operation" "$expected_runner" \
    "$expired_account" pending
  if (resolve_account_read_operation_before_provider \
    "$expired_journal_dir" "$expired_journal" "$expired_operation" \
    "$expected_runner" "$expired_account" "$mandate_test/expired-verified" \
    "$expired_replay") >/dev/null 2>&1; then
    die "self-test retried an expired pending account read"
  fi
  python3 - "$expired_evidence" "$expired_operation" "$expected_runner" \
    "$expired_account" <<'PY'
import datetime
import json
import pathlib
import sys

path, operation, runner, account = sys.argv[1:]
value = {
    "contract_version": "hivra-trading-account-read-evidence-v2",
    "account_read_operation_id": operation,
    "runner_key_id": runner,
    "account_binding_hash_hex": account,
    "read_scope": ["balance", "positions", "open_orders"],
    "max_uses": 1,
    "observed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "checks": [
        {"name": "balance", "success": True},
        {"name": "positions", "success": True},
        {"name": "open_orders", "success": True},
    ],
    "effect": False,
}
pathlib.Path(path).write_text(json.dumps(value, separators=(",", ":")) + "\n", encoding="utf-8")
PY
  commit_account_read_operation_journal \
    "$expired_journal" "$expired_operation" "$expected_runner" \
    "$expired_account" completed "$expired_evidence"
  local expired_resolution expired_evidence_hash
  expired_resolution="$(resolve_account_read_operation_before_provider \
    "$expired_journal_dir" "$expired_journal" "$expired_operation" \
    "$expected_runner" "$expired_account" "$mandate_test/expired-verified" \
    "$expired_replay")"
  expired_evidence_hash="$(validate_account_read_evidence \
    "$expired_evidence" "$expired_operation" "$expected_runner" \
    "$expired_account")"
  [ "$expired_resolution" = "completed:$expired_evidence_hash" ] ||
    die "self-test could not inspect exact completed evidence after expiry"
  cmp -s "$expired_evidence" "$expired_replay" ||
    die "self-test changed completed evidence after expiry"
  cp "$mandate_test/expired-admission.json" \
    "$mandate_test/expired-completed-mutated.json"
  python3 - "$mandate_test/expired-completed-mutated.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
signature = value["signature_hex"]
value["signature_hex"] = ("0" if signature[0] != "0" else "1") + signature[1:]
path.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")
PY
  mkdir "$mandate_test/expired-mutated-verified"
  if (verify_remote_mandate_artifact \
    "$mandate_test/expired-completed-mutated.json" "$expected_runner" \
    "$mandate_test/expired-mutated-verified") >/dev/null 2>&1; then
    die "self-test accepted invalid authority for expired completed replay"
  fi
  mkdir "$mandate_test/expired-wrong-runner-verified"
  if (verify_remote_mandate_artifact \
    "$mandate_test/expired-admission.json" "$(printf '0%.0s' {1..64})" \
    "$mandate_test/expired-wrong-runner-verified") >/dev/null 2>&1; then
    die "self-test accepted wrong binding for expired completed replay"
  fi
  cp "$mandate_test/admission.json" "$mandate_test/mutated.json"
  sed -i.bak 's/"symbol":"BTC-USDT"/"symbol":"ETH-USDT"/' "$mandate_test/mutated.json"
  if (verify_remote_mandate_artifact "$mandate_test/mutated.json" "$expected_runner" "$mandate_test/verified") >/dev/null 2>&1; then
    die "self-test accepted mutated mandate semantics"
  fi
  mv "$mandate_test/mutated.json.bak" "$mandate_test/mutated.json"
  cp "$mandate_test/admission.json" "$mandate_test/mutated.json"
  sed -i.bak 's/"open_orders"/"all_orders"/' "$mandate_test/mutated.json"
  if (verify_remote_mandate_artifact "$mandate_test/mutated.json" "$expected_runner" "$mandate_test/verified") >/dev/null 2>&1; then
    die "self-test accepted widened account-read scope"
  fi
  mv "$mandate_test/mutated.json.bak" "$mandate_test/mutated.json"
  cp "$mandate_test/admission.json" "$mandate_test/mutated.json"
  sed -i.bak 's/"max_uses":1/"max_uses":2/' "$mandate_test/mutated.json"
  if (verify_remote_mandate_artifact "$mandate_test/mutated.json" "$expected_runner" "$mandate_test/verified") >/dev/null 2>&1; then
    die "self-test accepted reusable account-read authority"
  fi
  mv "$mandate_test/mutated.json.bak" "$mandate_test/mutated.json"
  cp "$mandate_test/admission.json" "$mandate_test/mutated.json"
  sed -i.bak 's/trading-remote-mandate-admission-v2/trading-remote-mandate-admission-v1/g' "$mandate_test/mutated.json"
  if (verify_remote_mandate_artifact "$mandate_test/mutated.json" "$expected_runner" "$mandate_test/verified") >/dev/null 2>&1; then
    die "self-test accepted legacy v1 account-read authority"
  fi
  mv "$mandate_test/mutated.json.bak" "$mandate_test/mutated.json"
  cp "$mandate_test/admission.json" "$mandate_test/mutated.json"
  sed -i.bak 's/"operation_kind":"account_read"/"operation_kind":"account_write"/' "$mandate_test/mutated.json"
  if (verify_remote_mandate_artifact "$mandate_test/mutated.json" "$expected_runner" "$mandate_test/verified") >/dev/null 2>&1; then
    die "self-test accepted an account-write operation kind"
  fi
  mv "$mandate_test/mutated.json.bak" "$mandate_test/mutated.json"
  cp "$mandate_test/mutated.json" "$mandate_test/mutated.json.bak"
  python3 - "$mandate_test/mutated.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
signature = value["signature_hex"]
value["signature_hex"] = ("0" if signature[0] != "0" else "1") + signature[1:]
path.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")
PY
  if (verify_remote_mandate_artifact "$mandate_test/mutated.json" "$expected_runner" "$mandate_test/verified") >/dev/null 2>&1; then
    die "self-test accepted invalid Capsule signature"
  fi
  mv "$mandate_test/mutated.json.bak" "$mandate_test/mutated.json"
  if (verify_remote_mandate_artifact "$mandate_test/admission.json" "$(printf '0%.0s' {1..64})" "$mandate_test/verified") >/dev/null 2>&1; then
    die "self-test accepted wrong runner binding"
  fi
  echo "PASS trading-runner-artifact: negative self-tests"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build|--verify|--runtime-smoke|--install-disabled|--initialize-disabled|--provision-disabled|--activate|--deactivate|--export-anchor|--admit-mandate|--revoke-session|--provision-exchange-credential|--apply-prepared-session|--activate-prepared-session|--run-prepared-session|--enable-prepared-session-service|--pause-prepared-session-service|--prepared-session-service-status|--probe-exchange-account|--execute-exact-order|--execute-deterministic-order|--recover-deterministic-session|--uninstall-disabled|--ephemeral-install-smoke)
      [ -z "$MODE" ] && [ $# -ge 2 ] || die "invalid mode arguments"
      MODE="${1#--}"
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --run-installed-prepared-session)
      [ -z "$MODE" ] || die "multiple modes are not allowed"
      MODE="run-installed-prepared-session"
      INSTALLED_BUNDLE_MODE=1
      shift
      ;;
    --self-test)
      [ -z "$MODE" ] || die "multiple modes are not allowed"
      MODE="self-test"
      shift
      ;;
    --target-os)
      [ $# -ge 2 ] && [ -z "$TARGET_OS" ] || die "invalid target-os arguments"
      TARGET_OS="$2"
      shift 2
      ;;
    --target-arch)
      [ $# -ge 2 ] && [ -z "$TARGET_ARCH" ] || die "invalid target-arch arguments"
      TARGET_ARCH="$2"
      shift 2
      ;;
    --expected-runner-key-id)
      [ $# -ge 2 ] && [ -z "$EXPECTED_RUNNER_KEY_ID" ] ||
        die "invalid expected-runner-key-id arguments"
      EXPECTED_RUNNER_KEY_ID="$2"
      shift 2
      ;;
    --anchor-output)
      [ $# -ge 2 ] && [ -z "$ANCHOR_OUTPUT" ] ||
        die "invalid anchor-output arguments"
      ANCHOR_OUTPUT="$2"
      shift 2
      ;;
    --mandate-artifact)
      [ $# -ge 2 ] && [ -z "$MANDATE_ARTIFACT" ] ||
        die "invalid mandate-artifact arguments"
      MANDATE_ARTIFACT="$2"
      shift 2
      ;;
    --revocation-artifact)
      [ $# -ge 2 ] && [ -z "$REVOCATION_ARTIFACT" ] ||
        die "invalid revocation-artifact arguments"
      REVOCATION_ARTIFACT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [ "$MODE" != "admit-mandate" ] &&
  [ "$MODE" != "provision-exchange-credential" ] &&
  [ "$MODE" != "apply-prepared-session" ] &&
  [ -n "$MANDATE_ARTIFACT" ]; then
  die "mandate-artifact is accepted only by mandate preparation"
fi
if [ "$MODE" != "revoke-session" ] && [ -n "$REVOCATION_ARTIFACT" ]; then
  die "revocation-artifact is accepted only by session revocation"
fi

# The installed lifecycle has no repository checkout to compare against. Exact
# self-location enables manifest-based verification for every controller action.
enable_exact_installed_bundle_mode

case "$MODE" in
  build)
    [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] ||
      die "build does not accept identity or anchor options"
    build_artifact "$ARTIFACT_DIR"
    ;;
  verify)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] ||
      die "verify reads the target only from the manifest"
    verify_artifact "$ARTIFACT_DIR"
    ;;
  runtime-smoke)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] ||
      die "runtime smoke reads the target only from the manifest"
    runtime_smoke_artifact "$ARTIFACT_DIR"
    ;;
  install-disabled)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] ||
      die "disabled install reads the target only from the manifest"
    install_disabled "$ARTIFACT_DIR"
    ;;
  initialize-disabled)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] ||
      die "disabled initialization reads identity from exact evidence"
    initialize_disabled "$ARTIFACT_DIR"
    ;;
  provision-disabled)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -n "$ANCHOR_OUTPUT" ] ||
      die "disabled provisioning accepts only one anchor output"
    provision_disabled "$ARTIFACT_DIR"
    ;;
  activate)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] ||
      die "activation reads the target only from the manifest"
    activate_identity_bound "$ARTIFACT_DIR"
    ;;
  deactivate)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] ||
      die "deactivation reads the target only from the manifest"
    deactivate_identity_bound "$ARTIFACT_DIR"
    ;;
  export-anchor)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$MANDATE_ARTIFACT" ] ||
      die "anchor export reads the target only from the manifest"
    export_external_anchor "$ARTIFACT_DIR"
    ;;
  admit-mandate)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -n "$MANDATE_ARTIFACT" ] ||
      die "mandate admission requires only runner identity and artifact"
    admit_remote_mandate "$ARTIFACT_DIR"
    ;;
  revoke-session)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] &&
      [ -n "$REVOCATION_ARTIFACT" ] ||
      die "session revocation requires only runner identity and artifact"
    revoke_remote_session "$ARTIFACT_DIR"
    ;;
  provision-exchange-credential)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] ||
      die "credential provisioning requires runner identity, optional mandate, and stdin"
    provision_exchange_credential "$ARTIFACT_DIR"
    ;;
  apply-prepared-session)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -n "$MANDATE_ARTIFACT" ] ||
      die "prepared-session apply requires runner identity and one mandate artifact"
    apply_prepared_session "$ARTIFACT_DIR"
    ;;
  activate-prepared-session)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "prepared-session activation requires only runner identity and prepared host state"
    activate_prepared_session "$ARTIFACT_DIR"
    ;;
  run-prepared-session)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "prepared-session scheduler requires only runner identity and prepared host state"
    run_prepared_session_scheduler "$ARTIFACT_DIR"
    ;;
  run-installed-prepared-session)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] &&
      [ -z "$MANDATE_ARTIFACT" ] ||
      die "installed session mode accepts no external arguments"
    run_installed_prepared_session
    ;;
  enable-prepared-session-service)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "session service enable requires only runner identity and prepared host state"
    enable_prepared_session_service "$ARTIFACT_DIR"
    ;;
  pause-prepared-session-service)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] &&
      [ -z "$MANDATE_ARTIFACT" ] ||
      die "session service pause accepts no identity or mandate input"
    pause_prepared_session_service "$ARTIFACT_DIR"
    ;;
  prepared-session-service-status)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] &&
      [ -z "$MANDATE_ARTIFACT" ] ||
      die "session service status accepts no identity or mandate input"
    prepared_session_service_status "$ARTIFACT_DIR"
    ;;
  probe-exchange-account)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "account probe requires only runner identity and prepared host state"
    probe_exchange_account_once "$ARTIFACT_DIR"
    ;;
  execute-exact-order)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "exact order requires only runner identity and prepared host state"
    execute_exact_order_once "$ARTIFACT_DIR"
    ;;
  execute-deterministic-order)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "deterministic order requires only runner identity and prepared host state"
    execute_deterministic_order_once "$ARTIFACT_DIR"
    ;;
  recover-deterministic-session)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "deterministic recovery requires only runner identity and prepared host state"
    recover_deterministic_session_once "$ARTIFACT_DIR"
    ;;
  uninstall-disabled)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] ||
      die "disabled uninstall reads the target only from the manifest"
    uninstall_disabled "$ARTIFACT_DIR"
    ;;
  ephemeral-install-smoke)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] ||
      die "ephemeral install smoke reads the target only from the manifest"
    ephemeral_install_smoke "$ARTIFACT_DIR"
    ;;
  self-test)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] && [ -z "$ANCHOR_OUTPUT" ] &&
      [ -z "$MANDATE_ARTIFACT" ] && [ -z "$REVOCATION_ARTIFACT" ] ||
      die "self-test does not accept a target"
    self_test
    ;;
  *) usage >&2; exit 2 ;;
esac
