#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
ENTRYPOINT="$FLUTTER_DIR/tool/trading_remote_shadow_probe.dart"
BASELINE="$ROOT/toolchains/hivra-baseline.conf"
PACKAGE_DIR="$ROOT/tools/trading/public_shadow_runner_package"
PACKAGE_LOCK="$PACKAGE_DIR/pubspec.lock"
BINARY_NAME="hivra-trading-public-shadow-runner"
MANIFEST_NAME="ARTIFACT-MANIFEST.v1"
SCHEMA_VERSION="hivra-trading-public-shadow-runner-artifact-v1"
AUTHORITY_PROFILE="public-market-shadow-only"
MODE=""
ARTIFACT_DIR=""
TARGET_OS=""
TARGET_ARCH=""

usage() {
  cat <<'EOF'
Usage:
  tools/trading/public_shadow_runner_artifact.sh --build <absolute-output-dir>
    [--target-os linux --target-arch x64]
  tools/trading/public_shadow_runner_artifact.sh --verify <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --runtime-smoke <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --self-test

The build mode requires a completely clean worktree and the pinned Dart SDK.
It produces one host-native executable and one exact provenance manifest.
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
EOF
}

verify_artifact() {
  local directory="$1"
  local binary="$directory/$BINARY_NAME"
  local manifest="$directory/$MANIFEST_NAME"
  [ -d "$directory" ] && [ ! -L "$directory" ] ||
    die "artifact directory must be a real directory"
  [ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ] ||
    die "artifact binary must be one executable regular file"
  [ -f "$manifest" ] && [ ! -L "$manifest" ] ||
    die "artifact manifest must be one regular file"
  [ "$(find "$directory" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')" = "2" ] ||
    die "artifact directory contains unknown entries"

  python3 - "$manifest" "$SCHEMA_VERSION" "$AUTHORITY_PROFILE" "$BINARY_NAME" <<'PY'
import re
import sys

path, schema, authority, binary_name = sys.argv[1:]
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
PY

  local expected_sha
  local expected_size
  local expected_lock_sha
  local source_commit
  local target_os
  local target_arch
  expected_sha="$(sed -n 's/^binary_sha256=//p' "$manifest")"
  expected_size="$(sed -n 's/^binary_size=//p' "$manifest")"
  expected_lock_sha="$(sed -n 's/^dependency_lock_sha256=//p' "$manifest")"
  source_commit="$(sed -n 's/^source_commit=//p' "$manifest")"
  target_os="$(sed -n 's/^target_os=//p' "$manifest")"
  target_arch="$(sed -n 's/^target_arch=//p' "$manifest")"
  [ "$(sha256_file "$binary")" = "$expected_sha" ] ||
    die "artifact binary SHA-256 mismatch"
  [ "$(file_size "$binary")" = "$expected_size" ] ||
    die "artifact binary size mismatch"
  [ -f "$PACKAGE_LOCK" ] &&
    [ "$(sha256_file "$PACKAGE_LOCK")" = "$expected_lock_sha" ] ||
    die "artifact dependency lock SHA-256 mismatch"
  git -C "$ROOT" merge-base --is-ancestor "$source_commit" HEAD >/dev/null 2>&1 ||
    die "artifact source commit is not available in repository history"
  local file_description
  file_description="$(file "$binary")"
  printf '%s\n' "$file_description" | grep -q 'executable' ||
    die "artifact is not a host-native executable"
  case "$target_os/$target_arch" in
    linux/x64)
      printf '%s\n' "$file_description" | grep -Eq 'ELF 64-bit.*x86-64' ||
        die "artifact binary does not match Linux x64 manifest"
      ;;
    darwin/arm64)
      printf '%s\n' "$file_description" | grep -Eq 'Mach-O 64-bit executable arm64' ||
        die "artifact binary does not match Darwin arm64 manifest"
      ;;
    darwin/x86_64|darwin/x64)
      printf '%s\n' "$file_description" | grep -Eq 'Mach-O 64-bit executable x86_64' ||
        die "artifact binary does not match Darwin x64 manifest"
      ;;
    *)
      die "artifact target is not an allowed packaging target"
      ;;
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

self_test() {
  local root
  root="$(mktemp -d)"
  trap "rm -rf '$root'" EXIT
  local artifact="$root/artifact"
  mkdir "$artifact"
  cp /bin/echo "$artifact/$BINARY_NAME"
  chmod 700 "$artifact/$BINARY_NAME"
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
    --build|--verify|--runtime-smoke)
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
  self-test)
    [ -z "$TARGET_OS" ] && [ -z "$TARGET_ARCH" ] ||
      die "self-test does not accept a target"
    self_test
    ;;
  *) usage >&2; exit 2 ;;
esac
