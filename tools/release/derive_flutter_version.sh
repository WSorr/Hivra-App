#!/usr/bin/env bash
set -euo pipefail

VERSION=""
FIELD=""
SELF_TEST=0
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

usage() {
  cat <<'EOF'
Usage:
  tools/release/derive_flutter_version.sh --version <tag> --field <name|number>
  tools/release/derive_flutter_version.sh --self-test

Examples:
  v1.0.3-test4 -> name 1.0.3, number 100030004
  v1.0.3       -> name 1.0.3, number 100039999
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

self_test() {
  local test16 stable next_patch maximum
  test16="$("$SCRIPT_PATH" --version v1.0.3-test16 --field number)"
  stable="$("$SCRIPT_PATH" --version v1.0.3 --field number)"
  next_patch="$("$SCRIPT_PATH" --version v1.0.4-test1 --field number)"
  maximum="$("$SCRIPT_PATH" --version v20.99.99 --field number)"

  [ "$test16" -gt 100000331 ] || die "test16 must upgrade the last verified development build"
  [ "$stable" -gt "$test16" ] || die "stable must upgrade every prerelease in the same patch"
  [ "$next_patch" -gt "$stable" ] || die "the next patch prerelease must upgrade the prior stable"
  [ "$maximum" -le 2100000000 ] || die "maximum version exceeds Android versionCode"

  if "$SCRIPT_PATH" --version v1.0.3-test9999 --field number >/dev/null 2>&1; then
    die "test9999 must remain reserved for stable"
  fi
  if "$SCRIPT_PATH" --version v1.100.0-test1 --field number >/dev/null 2>&1; then
    die "minor 100 must exceed the supported versionCode layout"
  fi
  if "$SCRIPT_PATH" --version v1.0.100-test1 --field number >/dev/null 2>&1; then
    die "patch 100 must exceed the supported versionCode layout"
  fi

  printf 'PASS Flutter version derivation: monotonic prerelease/stable layout\n'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --field)
      FIELD="${2:-}"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  [ -z "$VERSION" ] && [ -z "$FIELD" ] || die "--self-test cannot be combined with version arguments"
  self_test
  exit 0
fi

[ -n "$VERSION" ] || die "--version is required"
[[ "$FIELD" == "name" || "$FIELD" == "number" ]] ||
  die "--field must be name or number"

if [[ ! "$VERSION" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-test([0-9]+))?$ ]]; then
  die "version must use vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-testN"
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
is_test="${BASH_REMATCH[4]:-}"
test_number="${BASH_REMATCH[5]:-9999}"

[ "$major" -le 20 ] || die "major version exceeds Android versionCode range"
[ "$minor" -le 99 ] || die "minor version must be <= 99"
[ "$patch" -le 99 ] || die "patch version must be <= 99"
if [ -n "$is_test" ]; then
  [ "$test_number" -le 9998 ] || die "test iteration must be <= 9998"
fi

if [ "$FIELD" = "name" ]; then
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
  exit 0
fi

printf '%d\n' "$((major * 100000000 + minor * 1000000 + patch * 10000 + test_number))"
