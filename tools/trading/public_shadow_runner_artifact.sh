#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
ENTRYPOINT="$FLUTTER_DIR/tool/trading_remote_shadow_probe.dart"
BASELINE="$ROOT/toolchains/hivra-baseline.conf"
PACKAGE_DIR="$ROOT/tools/trading/public_shadow_runner_package"
PACKAGE_LOCK="$PACKAGE_DIR/pubspec.lock"
UNIT_SOURCE="$ROOT/tools/trading/hivra-trading-public-shadow-runner.service"
BINARY_NAME="hivra-trading-public-shadow-runner"
UNIT_NAME="hivra-trading-public-shadow-runner.service"
MANIFEST_NAME="ARTIFACT-MANIFEST.v1"
SCHEMA_VERSION="hivra-trading-public-shadow-runner-bundle-v1"
AUTHORITY_PROFILE="public-market-shadow-plus-exact-single-use-account-read"
BUNDLE_INSTALL_PATH="/opt/hivra/trading-public-shadow"
BINARY_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$BINARY_NAME"
UNIT_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$UNIT_NAME"
UNIT_LINK_PATH="/etc/systemd/system/$UNIT_NAME"
CREDENTIAL_INSTALL_PATH="/etc/credstore.encrypted/hivra-trading-public-shadow.seed"
EXCHANGE_CREDENTIAL_INSTALL_PATH="/etc/credstore.encrypted/hivra-trading-public-shadow.bingx"
STATE_DIRECTORY="/var/lib/hivra-trading-public-shadow"
ACCOUNT_READ_SCOPE_WIRE="balance,positions,open_orders"
ACCOUNT_READ_MAX_USES="1"
MODE=""
ARTIFACT_DIR=""
TARGET_OS=""
TARGET_ARCH=""
EXPECTED_RUNNER_KEY_ID=""
ANCHOR_OUTPUT=""
MANDATE_ARTIFACT=""

usage() {
  cat <<'EOF'
Usage:
  tools/trading/public_shadow_runner_artifact.sh --build <absolute-output-dir>
    [--target-os linux --target-arch x64]
  tools/trading/public_shadow_runner_artifact.sh --verify <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --runtime-smoke <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --install-disabled <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --initialize-disabled <artifact-dir>
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
  tools/trading/public_shadow_runner_artifact.sh --provision-exchange-credential <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --probe-exchange-account <artifact-dir>
    --expected-runner-key-id <64-lowercase-hex>
  tools/trading/public_shadow_runner_artifact.sh --uninstall-disabled <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --ephemeral-install-smoke <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --self-test

The build mode requires a completely clean worktree and the pinned Dart SDK.
It produces one host-native executable, the exact systemd unit, and one exact
provenance manifest. Host lifecycle modes require a root Linux systemd host.
Installation requires empty canonical target paths and leaves the exact unit
disabled and inactive. Initialization proves its persistent identity without
enabling it. Activation requires that exact identity. Uninstall refuses drifted
or foreign-owned paths. Anchor export atomically copies the exact latest signed
evidence and its public key; acceptance happens only after off-host verification.
Mandate admission verifies the exact Capsule signature and runner binding, then
stores one prepared artifact without activating exchange authority.
Credential provisioning accepts the API key and secret only from a hidden TTY
prompt or exact two-line stdin, verifies the prepared mandate account binding,
and stores host-encrypted prepared state without exposing it to the runner.
Account probing uses one collected transient systemd unit, supplies both
encrypted credentials only to that process, permits exactly balance, positions,
and open-orders GETs, and emits only a bounded redacted verdict.
EOF
}

canonicalize_exchange_credential_input() {
  python3 -c '
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
  local unit="$directory/$UNIT_NAME"
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
unit_file=$UNIT_NAME
unit_sha256=$(sha256_file "$unit")
bundle_install_path=$BUNDLE_INSTALL_PATH
binary_install_path=$BINARY_INSTALL_PATH
unit_install_path=$UNIT_INSTALL_PATH
unit_link_path=$UNIT_LINK_PATH
credential_install_path=$CREDENTIAL_INSTALL_PATH
state_directory=$STATE_DIRECTORY
EOF
}

verify_artifact() {
  local directory="$1"
  local binary="$directory/$BINARY_NAME"
  local unit="$directory/$UNIT_NAME"
  local manifest="$directory/$MANIFEST_NAME"
  [ -d "$directory" ] && [ ! -L "$directory" ] ||
    die "artifact directory must be a real directory"
  [ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ] ||
    die "artifact binary must be one executable regular file"
  [ -f "$unit" ] && [ ! -L "$unit" ] && [ ! -x "$unit" ] ||
    die "artifact unit must be one non-executable regular file"
  [ -f "$manifest" ] && [ ! -L "$manifest" ] ||
    die "artifact manifest must be one regular file"
  [ "$(find "$directory" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')" = "3" ] ||
    die "artifact directory contains unknown entries"

  python3 - \
    "$manifest" \
    "$SCHEMA_VERSION" \
    "$AUTHORITY_PROFILE" \
    "$BINARY_NAME" \
    "$UNIT_NAME" \
    "$BUNDLE_INSTALL_PATH" \
    "$BINARY_INSTALL_PATH" \
    "$UNIT_INSTALL_PATH" \
    "$UNIT_LINK_PATH" \
    "$CREDENTIAL_INSTALL_PATH" \
    "$STATE_DIRECTORY" <<'PY'
import re
import sys

(
    path,
    schema,
    authority,
    binary_name,
    unit_name,
    bundle_install_path,
    binary_install_path,
    unit_install_path,
    unit_link_path,
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
    "unit_file",
    "unit_sha256",
    "bundle_install_path",
    "binary_install_path",
    "unit_install_path",
    "unit_link_path",
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
if parsed["unit_file"] != unit_name:
    raise SystemExit("unit filename mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", parsed["unit_sha256"]):
    raise SystemExit("invalid unit SHA-256")
if parsed["bundle_install_path"] != bundle_install_path:
    raise SystemExit("bundle install path mismatch")
if parsed["binary_install_path"] != binary_install_path:
    raise SystemExit("binary install path mismatch")
if parsed["unit_install_path"] != unit_install_path:
    raise SystemExit("unit install path mismatch")
if parsed["unit_link_path"] != unit_link_path:
    raise SystemExit("unit link path mismatch")
if parsed["credential_install_path"] != credential_install_path:
    raise SystemExit("credential install path mismatch")
if parsed["state_directory"] != state_directory:
    raise SystemExit("state directory mismatch")
PY

  local expected_sha
  local expected_size
  local expected_lock_sha
  local expected_unit_sha
  local source_commit
  local target_os
  local target_arch
  expected_sha="$(sed -n 's/^binary_sha256=//p' "$manifest")"
  expected_size="$(sed -n 's/^binary_size=//p' "$manifest")"
  expected_lock_sha="$(sed -n 's/^dependency_lock_sha256=//p' "$manifest")"
  expected_unit_sha="$(sed -n 's/^unit_sha256=//p' "$manifest")"
  source_commit="$(sed -n 's/^source_commit=//p' "$manifest")"
  target_os="$(sed -n 's/^target_os=//p' "$manifest")"
  target_arch="$(sed -n 's/^target_arch=//p' "$manifest")"
  [ "$(sha256_file "$binary")" = "$expected_sha" ] ||
    die "artifact binary SHA-256 mismatch"
  [ "$(file_size "$binary")" = "$expected_size" ] ||
    die "artifact binary size mismatch"
  [ "$(sha256_file "$unit")" = "$expected_unit_sha" ] ||
    die "artifact unit SHA-256 mismatch"
  cmp -s "$unit" "$UNIT_SOURCE" ||
    die "artifact unit does not match the canonical source"
  [ -f "$PACKAGE_LOCK" ] &&
    [ "$(sha256_file "$PACKAGE_LOCK")" = "$expected_lock_sha" ] ||
    die "artifact dependency lock SHA-256 mismatch"
  git -C "$ROOT" merge-base --is-ancestor "$source_commit" HEAD >/dev/null 2>&1 ||
    die "artifact source commit is not available in repository history"
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
  for marker in \
    'openApi/swap/v2/user/balance' \
    'openApi/swap/v2/user/positions' \
    'openApi/swap/v2/trade/openOrders' \
    'hivra-trading-account-read-evidence-v2' \
    'balance,positions,open_orders'; do
    grep -aFq "$marker" "$binary" ||
      die "artifact is missing the bounded account-read marker: $marker"
  done
  if grep -aEq \
    'openApi/swap/v2/trade/order([^s]|$)|openApi/swap/v2/trade/(leverage|marginType)|placeOrder|cancelOrder|switchLeverage|switchMarginType' \
    "$binary"; then
    die "artifact contains forbidden exchange-effect authority markers"
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
  )
  rm -f "$pending/package_config.json"
  chmod 700 "$pending/$BINARY_NAME"
  cp "$UNIT_SOURCE" "$pending/$UNIT_NAME"
  chmod 600 "$pending/$UNIT_NAME"
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
  cmp -s "$UNIT_INSTALL_PATH" "$directory/$UNIT_NAME" ||
    die "host lifecycle refused a drifted runner unit"
  cmp -s "$BUNDLE_INSTALL_PATH/$MANIFEST_NAME" "$directory/$MANIFEST_NAME" ||
    die "host lifecycle refused a drifted runner manifest"
  [ -L "$UNIT_LINK_PATH" ] &&
    [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ] ||
    die "host lifecycle refused a foreign unit link"
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
  trap 'systemctl stop "$UNIT_NAME" >/dev/null 2>&1 || true; rm -f "$lock_path"' EXIT INT TERM

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
  trap 'rm -f "$lock_path"' EXIT INT TERM

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
expected_root = [
    "contract_version", "operation_id", "commitment_hash_hex",
    "runner_key_id", "operation_kind", "read_scope", "max_uses",
    "mandate", "signature_suite", "signature_hex",
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
if value["contract_version"] != "trading-remote-mandate-admission-v2":
    raise SystemExit("mandate contract version mismatch")
if value["signature_suite"] != "ed25519-v1":
    raise SystemExit("mandate signature suite mismatch")
if value["operation_kind"] != "account_read":
    raise SystemExit("mandate operation kind mismatch")
if value["read_scope"] != ["balance", "positions", "open_orders"]:
    raise SystemExit("mandate account-read scope mismatch")
if value["max_uses"] != 1:
    raise SystemExit("mandate account-read use bound mismatch")
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
    "read_scope": value["read_scope"],
    "max_uses": value["max_uses"],
    "mandate": mandate,
}
commitment = hashlib.sha256(
    b"hivra:bingx-futures-remote-mandate-admission:v2\n" +
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
now = datetime.datetime.now(datetime.timezone.utc)
if expires <= issued or expires - issued > datetime.timedelta(hours=24):
    raise SystemExit("mandate time bounds are invalid")
if now < issued or now >= expires:
    raise SystemExit("mandate is not currently active")
pathlib.Path(work, "digest.bin").write_bytes(bytes.fromhex(commitment))
pathlib.Path(work, "signature.bin").write_bytes(bytes.fromhex(value["signature_hex"]))
pathlib.Path(work, "capsule-public-key.der").write_bytes(
    bytes.fromhex("302a300506032b6570032100" + mandate["capsule_root_hex"])
)
pathlib.Path(work, "operation-id").write_text(value["operation_id"], encoding="ascii")
pathlib.Path(work, "account-binding").write_text(
    mandate["account_binding_hash_hex"], encoding="ascii"
)
pathlib.Path(work, "expires-at").write_text(mandate["expires_at_utc"], encoding="ascii")
pathlib.Path(work, "read-scope").write_text(
    ",".join(value["read_scope"]), encoding="ascii"
)
pathlib.Path(work, "max-uses").write_text(str(value["max_uses"]), encoding="ascii")
PY
  then
    die "mandate semantic validation failed"
  fi
  openssl pkeyutl -verify -pubin \
    -inkey "$work/capsule-public-key.der" -keyform DER -rawin \
    -in "$work/digest.bin" -sigfile "$work/signature.bin" >/dev/null 2>&1 ||
    die "mandate Capsule signature is invalid"
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
  trap 'rm -rf "$work"; rm -f "$lock_path"' EXIT INT TERM
  install -m 0600 "$MANDATE_ARTIFACT" "$work/input.json"
  verify_remote_mandate_artifact \
    "$work/input.json" "$EXPECTED_RUNNER_KEY_ID" "$work"
  local target_dir="$STATE_DIRECTORY/mandates"
  local legacy_target="$target_dir/prepared.v1.json"
  local target="$target_dir/prepared.v2.json"
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
    cmp -s "$work/input.json" "$target" ||
      die "mandate admission refused conflicting retained authority"
    echo "PASS trading-runner-artifact: exact remote mandate replay is idempotent"
  else
    local pending
    pending="$(mktemp "$target_dir/.prepared.pending.XXXXXX")"
    install -m 0600 "$work/input.json" "$pending"
    mv "$pending" "$target"
    echo "PASS trading-runner-artifact: admitted one prepared remote mandate operation_id=$(cat "$work/operation-id") runner_key_id=$EXPECTED_RUNNER_KEY_ID effect=false"
  fi
  trap - EXIT INT TERM
  rm -rf "$work"
  rm -f "$lock_path"
  exec 9>&-
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

  local mandate="$STATE_DIRECTORY/mandates/prepared.v2.json"
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
  trap 'rm -rf "$work"; rm -f "$lock_path"' EXIT INT TERM

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
  [ -z "$(find "$journal_dir" -mindepth 1 -maxdepth 1 ! -name "$operation_id.json" -print -quit)" ] ||
    die "account probe found conflicting operation journal state"
  if [ -e "$journal" ] || [ -L "$journal" ]; then
    local replay_evidence="$work/replay-evidence.json"
    local journal_state
    journal_state="$(validate_account_read_operation_journal \
      "$journal" "$operation_id" "$EXPECTED_RUNNER_KEY_ID" \
      "$account_binding" "$replay_evidence")" ||
      die "account probe retained operation journal is invalid"
    if [ "$journal_state" = "completed" ]; then
      local replay_hash
      replay_hash="$(validate_account_read_evidence \
        "$replay_evidence" "$operation_id" "$EXPECTED_RUNNER_KEY_ID" \
        "$account_binding")"
      trap - EXIT INT TERM
      rm -rf "$work"
      rm -f "$lock_path"
      exec 9>&-
      echo "PASS trading-runner-artifact: exact account-read replay returned retained redacted evidence evidence_hash=$replay_hash effect=false"
      return
    fi
    die "account probe operation is unresolved after an interrupted attempt"
  fi
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
  echo "PASS trading-runner-artifact: completed one signed single-use account read evidence_hash=$evidence_hash effect=false"
}

install_disabled() {
  local directory="$1"
  require_install_host "$directory"
  local lock_path="/run/lock/hivra-trading-public-shadow-install.lock"
  exec 9>"$lock_path"
  flock -n 9 || die "another public-shadow install operation is active"
  trap 'rm -f "$lock_path"' EXIT

  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  local state_private="/var/lib/private/hivra-trading-public-shadow"
  for target in \
    "$BUNDLE_INSTALL_PATH" \
    "$UNIT_LINK_PATH" \
    "$CREDENTIAL_INSTALL_PATH" \
    "$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    "$STATE_DIRECTORY" \
    "$state_private" \
    "$wants_path"; do
    [ ! -e "$target" ] && [ ! -L "$target" ] ||
      die "disabled install target already exists: $target"
  done
  if systemctl cat "$UNIT_NAME" >/dev/null 2>&1; then
    die "disabled install unit is already loaded"
  fi

  local opt_parent_created=0
  local credential_parent_created=0
  local bundle_installed=0
  local credential_installed=0
  local unit_linked=0
  local unit_loaded=0
  pending_bundle=""
  pending_credential=""
  rollback_disabled_install() {
    set +e
    if [ "$unit_loaded" = 1 ]; then
      systemctl stop "$UNIT_NAME" >/dev/null 2>&1
      systemctl clean --what=state "$UNIT_NAME" >/dev/null 2>&1
    fi
    if [ "$unit_linked" = 1 ] && [ -L "$UNIT_LINK_PATH" ] &&
      [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ]; then
      rm -f "$UNIT_LINK_PATH"
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
  install -m 0644 "$directory/$UNIT_NAME" "$pending_bundle/$UNIT_NAME"
  install -m 0600 "$directory/$MANIFEST_NAME" "$pending_bundle/$MANIFEST_NAME"
  chmod 0755 "$pending_bundle"
  [ "$(sha256_file "$pending_bundle/$BINARY_NAME")" = \
    "$(sed -n 's/^binary_sha256=//p' "$directory/$MANIFEST_NAME")" ] ||
    die "staged binary hash mismatch"
  [ "$(sha256_file "$pending_bundle/$UNIT_NAME")" = \
    "$(sed -n 's/^unit_sha256=//p' "$directory/$MANIFEST_NAME")" ] ||
    die "staged unit hash mismatch"
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
  [ -L "$UNIT_LINK_PATH" ] &&
    [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ] ||
    die "systemd unit link mismatch"
  systemctl daemon-reload
  unit_loaded=1
  case "$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)" in
    linked|disabled) ;;
    *) die "disabled install became enabled" ;;
  esac
  [ "$(systemctl show -p ActiveState --value "$UNIT_NAME")" = "inactive" ] ||
    die "disabled install became active"
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "disabled install created boot enablement"

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
  trap 'rm -f "$lock_path"' EXIT INT TERM

  local wants_path="/etc/systemd/system/multi-user.target.wants/$UNIT_NAME"
  local state_private="/var/lib/private/hivra-trading-public-shadow"
  [ -d "$BUNDLE_INSTALL_PATH" ] && [ ! -L "$BUNDLE_INSTALL_PATH" ] ||
    die "uninstall requires the canonical real bundle directory"
  verify_artifact "$BUNDLE_INSTALL_PATH" >/dev/null
  cmp -s "$BINARY_INSTALL_PATH" "$directory/$BINARY_NAME" ||
    die "uninstall refused a drifted runner binary"
  cmp -s "$UNIT_INSTALL_PATH" "$directory/$UNIT_NAME" ||
    die "uninstall refused a drifted runner unit"
  cmp -s "$BUNDLE_INSTALL_PATH/$MANIFEST_NAME" "$directory/$MANIFEST_NAME" ||
    die "uninstall refused a drifted runner manifest"
  if [ -e "$UNIT_LINK_PATH" ] || [ -L "$UNIT_LINK_PATH" ]; then
    [ -L "$UNIT_LINK_PATH" ] &&
      [ "$(readlink "$UNIT_LINK_PATH")" = "$UNIT_INSTALL_PATH" ] ||
      die "uninstall refused a foreign unit link"
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
  [ ! -e "$wants_path" ] && [ ! -L "$wants_path" ] ||
    die "uninstall refused boot enablement"
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
  rm -f "$UNIT_LINK_PATH"
  systemctl daemon-reload
  rm -f "$CREDENTIAL_INSTALL_PATH"
  rm -f "$EXCHANGE_CREDENTIAL_INSTALL_PATH"
  rm -rf "$STATE_DIRECTORY" "$state_private"
  rm -rf "$BUNDLE_INSTALL_PATH"

  for target in \
    "$BUNDLE_INSTALL_PATH" \
    "$UNIT_LINK_PATH" \
    "$CREDENTIAL_INSTALL_PATH" \
    "$EXCHANGE_CREDENTIAL_INSTALL_PATH" \
    "$STATE_DIRECTORY" \
    "$state_private" \
    "$wants_path"; do
    [ ! -e "$target" ] && [ ! -L "$target" ] ||
      die "disabled uninstall retained: $target"
  done
  systemctl cat "$UNIT_NAME" >/dev/null 2>&1 &&
    die "disabled uninstall retained the loaded unit"

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
  local artifact="$root/artifact"
  mkdir "$artifact"
  cp /bin/echo "$artifact/$BINARY_NAME"
  printf '%s\n' \
    'openApi/swap/v2/user/balance' \
    'openApi/swap/v2/user/positions' \
    'openApi/swap/v2/trade/openOrders' \
    'hivra-trading-account-read-evidence-v2' \
    'balance,positions,open_orders' >> "$artifact/$BINARY_NAME"
  chmod 700 "$artifact/$BINARY_NAME"
  cp "$UNIT_SOURCE" "$artifact/$UNIT_NAME"
  chmod 600 "$artifact/$UNIT_NAME"
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

  printf '\nplaceOrder\n' >> "$artifact/$BINARY_NAME"
  write_manifest "$artifact" "$(git -C "$ROOT" rev-parse HEAD)" "3.11.0" "$(host_os)" "$(host_arch)" "$(sha256_file "$PACKAGE_LOCK")"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted an exchange-effect authority marker"
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
issued = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=1)
expires = issued + datetime.timedelta(hours=1)
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
(root / "digest.bin").write_bytes(bytes.fromhex(commitment))
(root / "metadata.json").write_text(json.dumps({
    "runner": runner,
    "commitment": commitment,
    "mandate": mandate,
}, separators=(",", ":")), encoding="utf-8")
PY
  openssl pkeyutl -sign -inkey "$mandate_test/capsule.pem" -rawin \
    -in "$mandate_test/digest.bin" -out "$mandate_test/signature.bin"
  python3 - "$mandate_test" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "metadata.json").read_text())
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
    "signature_hex": (root / "signature.bin").read_bytes().hex(),
}
(root / "admission.json").write_text(
    json.dumps(artifact, separators=(",", ":")), encoding="utf-8"
)
PY
  local expected_runner
  expected_runner="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runner_key_id"])' "$mandate_test/admission.json")"
  mkdir "$mandate_test/verified"
  verify_remote_mandate_artifact \
    "$mandate_test/admission.json" "$expected_runner" "$mandate_test/verified"
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
    --build|--verify|--runtime-smoke|--install-disabled|--initialize-disabled|--activate|--deactivate|--export-anchor|--admit-mandate|--provision-exchange-credential|--probe-exchange-account|--uninstall-disabled|--ephemeral-install-smoke)
      [ -z "$MODE" ] && [ $# -ge 2 ] || die "invalid mode arguments"
      MODE="${1#--}"
      ARTIFACT_DIR="$2"
      shift 2
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
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [ "$MODE" != "admit-mandate" ] && [ -n "$MANDATE_ARTIFACT" ]; then
  die "mandate-artifact is accepted only by mandate admission"
fi

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
  provision-exchange-credential)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "credential provisioning requires only runner identity and stdin"
    provision_exchange_credential "$ARTIFACT_DIR"
    ;;
  probe-exchange-account)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$ANCHOR_OUTPUT" ] && [ -z "$MANDATE_ARTIFACT" ] ||
      die "account probe requires only runner identity and prepared host state"
    probe_exchange_account_once "$ARTIFACT_DIR"
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
      [ -z "$MANDATE_ARTIFACT" ] ||
      die "self-test does not accept a target"
    self_test
    ;;
  *) usage >&2; exit 2 ;;
esac
