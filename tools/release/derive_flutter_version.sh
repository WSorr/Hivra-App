#!/usr/bin/env bash
set -euo pipefail

VERSION=""
FIELD=""

usage() {
  cat <<'EOF'
Usage:
  tools/release/derive_flutter_version.sh --version <tag> --field <name|number>

Examples:
  v1.0.3-test4 -> name 1.0.3, number 100000304
  v1.0.3       -> name 1.0.3, number 100000300
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[ -n "$VERSION" ] || die "--version is required"
[[ "$FIELD" == "name" || "$FIELD" == "number" ]] ||
  die "--field must be name or number"

if [[ ! "$VERSION" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-test([0-9]+))?$ ]]; then
  die "version must use vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-testN"
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
test_number="${BASH_REMATCH[5]:-0}"

[ "$major" -le 20 ] || die "major version exceeds Android versionCode range"
[ "$minor" -le 999 ] || die "minor version must be <= 999"
[ "$patch" -le 999 ] || die "patch version must be <= 999"
[ "$test_number" -le 99 ] || die "test iteration must be <= 99"

if [ "$FIELD" = "name" ]; then
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
  exit 0
fi

printf '%d\n' "$((major * 100000000 + minor * 100000 + patch * 100 + test_number))"
