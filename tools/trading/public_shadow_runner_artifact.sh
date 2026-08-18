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
AUTHORITY_PROFILE="public-market-shadow-only"
BUNDLE_INSTALL_PATH="/opt/hivra/trading-public-shadow"
BINARY_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$BINARY_NAME"
UNIT_INSTALL_PATH="$BUNDLE_INSTALL_PATH/$UNIT_NAME"
UNIT_LINK_PATH="/etc/systemd/system/$UNIT_NAME"
CREDENTIAL_INSTALL_PATH="/etc/credstore.encrypted/hivra-trading-public-shadow.seed"
STATE_DIRECTORY="/var/lib/hivra-trading-public-shadow"
MODE=""
ARTIFACT_DIR=""
TARGET_OS=""
TARGET_ARCH=""
EXPECTED_RUNNER_KEY_ID=""

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
  tools/trading/public_shadow_runner_artifact.sh --uninstall-disabled <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --ephemeral-install-smoke <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --self-test

The build mode requires a completely clean worktree and the pinned Dart SDK.
It produces one host-native executable, the exact systemd unit, and one exact
provenance manifest. Host lifecycle modes require a root Linux systemd host.
Installation requires empty canonical target paths and leaves the exact unit
disabled and inactive. Initialization proves its persistent identity without
enabling it. Activation requires that exact identity. Uninstall refuses drifted
or foreign-owned paths.
EOF
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
  if grep -aEq \
    'openApi/swap/v2/trade/(order|leverage|marginType)|BingxFuturesApiCredentials|placeOrder|cancelOrder' \
    "$binary"; then
    die "artifact contains forbidden authenticated exchange authority markers"
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
  rm -rf "$STATE_DIRECTORY" "$state_private"
  rm -rf "$BUNDLE_INSTALL_PATH"

  for target in \
    "$BUNDLE_INSTALL_PATH" \
    "$UNIT_LINK_PATH" \
    "$CREDENTIAL_INSTALL_PATH" \
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
  chmod 700 "$artifact/$BINARY_NAME"
  cp "$UNIT_SOURCE" "$artifact/$UNIT_NAME"
  chmod 600 "$artifact/$UNIT_NAME"
  write_manifest "$artifact" "$(git -C "$ROOT" rev-parse HEAD)" "3.11.0" "$(host_os)" "$(host_arch)" "$(sha256_file "$PACKAGE_LOCK")"
  verify_artifact "$artifact" >/dev/null

  if (runtime_smoke_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a non-runner executable for runtime smoke"
  fi

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
    die "self-test accepted an authenticated authority marker"
  fi
  echo "PASS trading-runner-artifact: negative self-tests"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build|--verify|--runtime-smoke|--install-disabled|--initialize-disabled|--activate|--deactivate|--uninstall-disabled|--ephemeral-install-smoke)
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
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$MODE" in
  build) build_artifact "$ARTIFACT_DIR" ;;
  verify)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] ||
      die "verify reads the target only from the manifest"
    verify_artifact "$ARTIFACT_DIR"
    ;;
  runtime-smoke)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] ||
      die "runtime smoke reads the target only from the manifest"
    runtime_smoke_artifact "$ARTIFACT_DIR"
    ;;
  install-disabled)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] ||
      die "disabled install reads the target only from the manifest"
    install_disabled "$ARTIFACT_DIR"
    ;;
  initialize-disabled)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] ||
      die "disabled initialization reads identity from exact evidence"
    initialize_disabled "$ARTIFACT_DIR"
    ;;
  activate)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] ||
      die "activation reads the target only from the manifest"
    activate_identity_bound "$ARTIFACT_DIR"
    ;;
  deactivate)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] ||
      die "deactivation reads the target only from the manifest"
    deactivate_identity_bound "$ARTIFACT_DIR"
    ;;
  uninstall-disabled)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] ||
      die "disabled uninstall reads the target only from the manifest"
    uninstall_disabled "$ARTIFACT_DIR"
    ;;
  ephemeral-install-smoke)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] ||
      die "ephemeral install smoke reads the target only from the manifest"
    ephemeral_install_smoke "$ARTIFACT_DIR"
    ;;
  self-test)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] &&
      [ -z "$EXPECTED_RUNNER_KEY_ID" ] ||
      die "self-test does not accept a target"
    self_test
    ;;
  *) usage >&2; exit 2 ;;
esac
