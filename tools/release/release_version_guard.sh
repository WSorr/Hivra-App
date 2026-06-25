#!/usr/bin/env bash
set -euo pipefail

EXPECTED_REPOSITORY="WSorr/Hivra-App"
VERSION=""
CHANNEL=""
SUGGEST=0

usage() {
  cat <<'EOF'
Usage:
  tools/release/release_version_guard.sh --version <tag> --channel <test|public>
  tools/release/release_version_guard.sh --suggest

The guard reads the published Hivra-App release line from GitHub. Local legacy
tags are deliberately ignored.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

published_tags() {
  gh release list \
    --repo "$EXPECTED_REPOSITORY" \
    --limit 100 \
    --json tagName \
    --jq '.[].tagName'
}

latest_published_tag() {
  published_tags |
    rg '^v[0-9]+\.[0-9]+\.[0-9]+(?:-test[0-9]+)?$' |
    sort -V |
    tail -n1
}

suggest_next_tag() {
  local latest="$1"
  if [[ "$latest" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+)-test([0-9]+)$ ]]; then
    printf '%s-test%s\n' "${BASH_REMATCH[1]}" "$((BASH_REMATCH[2] + 1))"
    return
  fi
  printf '%s-test1\n' "$latest"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --suggest)
      SUGGEST=1
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

require_cmd git
require_cmd gh
require_cmd rg

remote_url="$(git remote get-url origin 2>/dev/null || true)"
case "$remote_url" in
  git@github.com:WSorr/Hivra-App.git|https://github.com/WSorr/Hivra-App.git)
    ;;
  *)
    die "origin must point to $EXPECTED_REPOSITORY, got: ${remote_url:-missing}"
    ;;
esac

latest="$(latest_published_tag)"
[ -n "$latest" ] || die "No published Hivra-App release tag found"

if [ "$SUGGEST" -eq 1 ]; then
  suggest_next_tag "$latest"
  exit 0
fi

[ -n "$VERSION" ] || die "--version is required"
[[ "$CHANNEL" == "test" || "$CHANNEL" == "public" ]] ||
  die "--channel must be test or public"

if [ "$CHANNEL" = "test" ]; then
  [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-test[0-9]+$ ]] ||
    die "test releases must use vMAJOR.MINOR.PATCH-testN"
  expected_test_version="$(suggest_next_tag "$latest")"
  [ "$VERSION" = "$expected_test_version" ] ||
    die "next test release after $latest must be exactly $expected_test_version"
else
  [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "public releases must use vMAJOR.MINOR.PATCH"
fi

latest_major="${latest#v}"
latest_major="${latest_major%%.*}"
candidate_major="${VERSION#v}"
candidate_major="${candidate_major%%.*}"
[ "$candidate_major" = "$latest_major" ] ||
  die "candidate $VERSION leaves published major line v$latest_major (latest: $latest)"

if published_tags | rg -Fxq "$VERSION"; then
  die "GitHub Release already exists for $VERSION"
fi

if git ls-remote --exit-code --tags origin "refs/tags/$VERSION" >/dev/null 2>&1; then
  die "remote tag already exists: $VERSION"
fi

if [ "$(printf '%s\n%s\n' "$latest" "$VERSION" | sort -V | tail -n1)" != "$VERSION" ] ||
   [ "$VERSION" = "$latest" ]; then
  die "candidate $VERSION must be newer than latest published release $latest"
fi

echo "PASS: release version $VERSION follows $latest in $EXPECTED_REPOSITORY"
