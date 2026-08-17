#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
ENTRYPOINT="$FLUTTER_DIR/tool/trading_remote_shadow_probe.dart"
BASELINE="$ROOT/toolchains/hivra-baseline.conf"
BINARY_NAME="hivra-trading-public-shadow-runner"
MANIFEST_NAME="ARTIFACT-MANIFEST.v1"
SCHEMA_VERSION="hivra-trading-public-shadow-runner-artifact-v1"
AUTHORITY_PROFILE="public-market-shadow-only"
MODE=""
ARTIFACT_DIR=""

usage() {
  cat <<'EOF'
Usage:
  tools/trading/public_shadow_runner_artifact.sh --build <absolute-output-dir>
  tools/trading/public_shadow_runner_artifact.sh --verify <artifact-dir>
  tools/trading/public_shadow_runner_artifact.sh --self-test

The build mode requires a completely clean worktree and the pinned Dart SDK.
It produces one host-native executable and one exact provenance manifest.
EOF
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

write_manifest() {
  local directory="$1"
  local source_commit="$2"
  local dart_sdk="$3"
  local target_os="$4"
  local target_arch="$5"
  local binary="$directory/$BINARY_NAME"
  cat > "$directory/$MANIFEST_NAME" <<EOF
schema_version=$SCHEMA_VERSION
source_commit=$source_commit
source_tree=clean
dart_version=$dart_sdk
target_os=$target_os
target_arch=$target_arch
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
  expected_sha="$(sed -n 's/^binary_sha256=//p' "$manifest")"
  expected_size="$(sed -n 's/^binary_size=//p' "$manifest")"
  [ "$(sha256_file "$binary")" = "$expected_sha" ] ||
    die "artifact binary SHA-256 mismatch"
  [ "$(file_size "$binary")" = "$expected_size" ] ||
    die "artifact binary size mismatch"
  file "$binary" | grep -q 'executable' ||
    die "artifact is not a host-native executable"
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
  local expected_dart
  expected_dart="$(baseline_value DART_VERSION)"
  [ "$(dart_version)" = "$expected_dart" ] ||
    die "Dart SDK does not match the pinned baseline"

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
    cd "$FLUTTER_DIR"
    dart compile exe "tool/trading_remote_shadow_probe.dart" \
      -o "$pending/$BINARY_NAME"
  )
  chmod 700 "$pending/$BINARY_NAME"
  write_manifest \
    "$pending" \
    "$(git -C "$ROOT" rev-parse HEAD)" \
    "$expected_dart" \
    "$(uname -s | tr '[:upper:]' '[:lower:]')" \
    "$(uname -m)"
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
  write_manifest "$artifact" "$(printf 'a%.0s' {1..40})" "3.11.0" "test-os" "test-arch"
  verify_artifact "$artifact" >/dev/null

  sed -i.bak 's/^binary_sha256=./binary_sha256=0/' "$artifact/$MANIFEST_NAME"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted a changed binary hash"
  fi
  mv "$artifact/$MANIFEST_NAME.bak" "$artifact/$MANIFEST_NAME"

  printf '\nplaceOrder\n' >> "$artifact/$BINARY_NAME"
  write_manifest "$artifact" "$(printf 'a%.0s' {1..40})" "3.11.0" "test-os" "test-arch"
  if (verify_artifact "$artifact") >/dev/null 2>&1; then
    die "self-test accepted an authenticated authority marker"
  fi
  echo "PASS trading-runner-artifact: negative self-tests"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build|--verify)
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
  verify) verify_artifact "$ARTIFACT_DIR" ;;
  self-test) self_test ;;
  *) usage >&2; exit 2 ;;
esac
