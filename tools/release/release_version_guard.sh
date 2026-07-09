#!/usr/bin/env bash
set -euo pipefail

EXPECTED_REPOSITORY="WSorr/Hivra-App"
VERSION=""
CHANNEL=""
SUGGEST=0
SELF_TEST=0
ALLOW_EXISTING_REMOTE_TAG=0

usage() {
  cat <<'EOF'
Usage:
  tools/release/release_version_guard.sh --version <tag> --channel <test|public>
  tools/release/release_version_guard.sh --suggest
  tools/release/release_version_guard.sh --self-test

Options:
  --allow-existing-remote-tag
      Publication-only mode. Allows an already-pushed tag while still rejecting
      already-published GitHub releases and invalid version progression.

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
  printf '%s-test1\n' "$(next_patch_base "$latest")"
}

base_tag() {
  local tag="$1"
  if [[ "$tag" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+)-test[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  printf '%s\n' "$tag"
}

next_patch_base() {
  local tag
  tag="$(base_tag "$1")"
  if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    printf 'v%s.%s.%s\n' \
      "${BASH_REMATCH[1]}" \
      "${BASH_REMATCH[2]}" \
      "$((BASH_REMATCH[3] + 1))"
    return
  fi
  die "cannot derive next patch from $1"
}

allowed_next_test_versions() {
  local latest="$1"
  if [[ "$latest" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+)-test([0-9]+)$ ]]; then
    printf '%s-test%s\n' "${BASH_REMATCH[1]}" "$((BASH_REMATCH[2] + 1))"
    printf '%s-test1\n' "$(next_patch_base "${BASH_REMATCH[1]}")"
    return
  fi
  printf '%s-test1\n' "$(next_patch_base "$latest")"
}

is_allowed_next_test_version() {
  local latest="$1"
  local candidate="$2"
  allowed_next_test_versions "$latest" | rg -Fxq "$candidate"
}

self_test() {
  [ "$(suggest_next_tag v1.0.3)" = "v1.0.4-test1" ] ||
    die "self-test: stable latest must suggest next patch test1"
  [ "$(suggest_next_tag v1.0.3-test8)" = "v1.0.3-test9" ] ||
    die "self-test: test latest must suggest next test in same patch train"

  is_allowed_next_test_version v1.0.3-test8 v1.0.3-test9 ||
    die "self-test: current patch train continuation must be allowed"
  is_allowed_next_test_version v1.0.3-test8 v1.0.4-test1 ||
    die "self-test: next patch test train must be allowed"
  if is_allowed_next_test_version v1.0.3-test8 v1.0.5-test1; then
    die "self-test: skipped patch train must be rejected"
  fi
  if is_allowed_next_test_version v1.0.3-test8 v1.0.3-test10; then
    die "self-test: skipped test number must be rejected"
  fi

  echo "PASS: release version guard self-test"
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
    --self-test)
      SELF_TEST=1
      shift
      ;;
    --allow-existing-remote-tag)
      ALLOW_EXISTING_REMOTE_TAG=1
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
  require_cmd rg
  self_test
  exit 0
fi

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
  if ! is_allowed_next_test_version "$latest" "$VERSION"; then
    expected_test_versions="$(allowed_next_test_versions "$latest" | paste -sd ', ' -)"
    die "next test release after $latest must be one of: $expected_test_versions"
  fi
else
  [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "public releases must use vMAJOR.MINOR.PATCH"
  latest_base="$(base_tag "$latest")"
  [ "$VERSION" = "$latest_base" ] ||
    [ "$(printf '%s\n%s\n' "$latest_base" "$VERSION" | sort -V | tail -n1)" = "$VERSION" ] ||
    die "public release $VERSION must be at or above latest published base $latest_base (latest: $latest)"
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

if [ "$ALLOW_EXISTING_REMOTE_TAG" -eq 0 ] &&
   git ls-remote --exit-code --tags origin "refs/tags/$VERSION" >/dev/null 2>&1; then
  die "remote tag already exists: $VERSION"
fi

if [ "$CHANNEL" = "test" ]; then
  if [ "$(printf '%s\n%s\n' "$latest" "$VERSION" | sort -V | tail -n1)" != "$VERSION" ] ||
     [ "$VERSION" = "$latest" ]; then
    die "candidate $VERSION must be newer than latest published release $latest"
  fi
elif [ "$VERSION" = "$latest" ]; then
  die "candidate $VERSION must be newer than latest published release $latest"
fi

echo "PASS: release version $VERSION follows $latest in $EXPECTED_REPOSITORY"
