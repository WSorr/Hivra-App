#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${HIVRA_RELEASE_REPO:-WSorr/Hivra-App}"

VERSION=""
CHANNEL=""
TITLE=""
NOTES_FILE=""

usage() {
  cat <<'USAGE'
Usage:
  tools/release/publish_github_release.sh --version <version> --channel <test|public> [options]

Options:
  --version <version>      Required. Existing Git tag and artifact version.
  --channel <channel>      Required. test | public.
  --title <title>          Optional GitHub release title.
  --notes-file <path>      Optional release notes file.

This is the only approved GitHub publication path. It refuses to publish unless:
  - automated preflight passes for the exact build tag;
  - manual signoff log has PASS rows for macOS and Android;
  - local release artifacts and checksums exist.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "== $* =="
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

metadata_value() {
  local file="$1"
  local key="$2"
  awk -F'=' -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$file"
}

require_clean_tracked_worktree() {
  git diff --quiet || die "GitHub publication requires a clean tracked worktree"
  git diff --cached --quiet || die "GitHub publication requires a clean index"
}

require_tag_points_to_head() {
  local tag_commit
  local head_commit
  tag_commit="$(git rev-list -n 1 "$VERSION")"
  head_commit="$(git rev-parse HEAD)"
  [ "$tag_commit" = "$head_commit" ] ||
    die "Git tag $VERSION points to $tag_commit, but HEAD is $head_commit"
}

verify_release_metadata() {
  local file="$1"
  local platform="$2"
  local version
  local source_commit
  local source_tree_dirty
  local head_commit

  version="$(metadata_value "$file" version)"
  source_commit="$(metadata_value "$file" source_commit)"
  source_tree_dirty="$(metadata_value "$file" source_tree_dirty)"
  head_commit="$(git rev-parse HEAD)"

  [ "$version" = "$VERSION" ] ||
    die "$platform metadata version is ${version:-missing}, expected $VERSION"
  [ "$source_commit" = "$head_commit" ] ||
    die "$platform metadata source_commit is ${source_commit:-missing}, expected $head_commit"
  [ "$source_tree_dirty" = "no" ] ||
    die "$platform metadata source_tree_dirty must be no"
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
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --notes-file)
      NOTES_FILE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[ -n "$VERSION" ] || die "--version is required"
[ -n "$CHANNEL" ] || die "--channel is required"
[[ "$CHANNEL" == "test" || "$CHANNEL" == "public" ]] || die "--channel must be test or public"

require_cmd gh
require_cmd git
require_cmd shasum
require_clean_tracked_worktree

"$ROOT/tools/release/release_version_guard.sh" \
  --version "$VERSION" \
  --channel "$CHANNEL" \
  --allow-existing-remote-tag

info "Automated preflight"
"$ROOT/tools/release/preflight.sh" \
  --trading-evidence-build-tag "$VERSION"

info "Manual signoff gate"
"$ROOT/tools/release/check_manual_release_signoff.sh" \
  --build-tag "$VERSION" \
  --platform all

git rev-parse --verify "$VERSION^{tag}" >/dev/null 2>&1 ||
  git rev-parse --verify "$VERSION^{commit}" >/dev/null 2>&1 ||
  die "Git tag not found locally: $VERSION"
require_tag_points_to_head

if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  die "GitHub Release already exists for $VERSION"
fi

MAC_DIR="$ROOT/dist/${VERSION}-${CHANNEL}-macos"
ANDROID_DIR="$ROOT/dist/${VERSION}-${CHANNEL}-android"
MAC_ASSET="$MAC_DIR/hivra_app-${VERSION}-macos-universal.zip"
ANDROID_ASSET="$ANDROID_DIR/hivra_app-${VERSION}-android-universal.apk"
MAC_META="$MAC_DIR/RELEASE-METADATA.txt"
ANDROID_META="$ANDROID_DIR/RELEASE-METADATA.txt"

[ -f "$MAC_ASSET" ] || die "Missing macOS artifact: $MAC_ASSET"
[ -f "$ANDROID_ASSET" ] || die "Missing Android artifact: $ANDROID_ASSET"
[ -f "$MAC_META" ] || die "Missing macOS metadata: $MAC_META"
[ -f "$ANDROID_META" ] || die "Missing Android metadata: $ANDROID_META"
verify_release_metadata "$MAC_META" "macOS"
verify_release_metadata "$ANDROID_META" "Android"

PUBLISH_DIR="$ROOT/dist/${VERSION}-${CHANNEL}-publish"
mkdir -p "$PUBLISH_DIR"
CHECKSUMS="$PUBLISH_DIR/SHA256SUMS-${VERSION}.txt"
MAC_META_PUBLISH="$PUBLISH_DIR/RELEASE-METADATA-macos.txt"
ANDROID_META_PUBLISH="$PUBLISH_DIR/RELEASE-METADATA-android.txt"
cp "$MAC_META" "$MAC_META_PUBLISH"
cp "$ANDROID_META" "$ANDROID_META_PUBLISH"

{
  printf '%s  %s\n' \
    "$(shasum -a 256 "$MAC_ASSET" | awk '{print $1}')" \
    "$(basename "$MAC_ASSET")"
  printf '%s  %s\n' \
    "$(shasum -a 256 "$ANDROID_ASSET" | awk '{print $1}')" \
    "$(basename "$ANDROID_ASSET")"
  printf '%s  %s\n' \
    "$(shasum -a 256 "$MAC_META_PUBLISH" | awk '{print $1}')" \
    "$(basename "$MAC_META_PUBLISH")"
  printf '%s  %s\n' \
    "$(shasum -a 256 "$ANDROID_META_PUBLISH" | awk '{print $1}')" \
    "$(basename "$ANDROID_META_PUBLISH")"
} > "$CHECKSUMS"

if [ -z "$TITLE" ]; then
  TITLE="Hivra ${VERSION} (${CHANNEL})"
fi

if [ -n "$NOTES_FILE" ]; then
  [ -f "$NOTES_FILE" ] || die "Release notes file not found: $NOTES_FILE"
else
  NOTES_FILE="$(mktemp)"
  cat > "$NOTES_FILE" <<EOF
Hivra ${VERSION} ${CHANNEL} release.

Manual signoff required by docs/checklists/release-manual-signoff-log.md.
Automated preflight required by tools/release/preflight.sh.
EOF
fi

PRERELEASE_FLAG=()
if [ "$CHANNEL" = "test" ]; then
  PRERELEASE_FLAG=(--prerelease)
fi

info "Publish GitHub Release"
gh release create "$VERSION" \
  --repo "$REPO" \
  --title "$TITLE" \
  --notes-file "$NOTES_FILE" \
  "${PRERELEASE_FLAG[@]}" \
  "$MAC_ASSET" \
  "$ANDROID_ASSET" \
  "$CHECKSUMS" \
  "$MAC_META_PUBLISH" \
  "$ANDROID_META_PUBLISH"

echo "Published: https://github.com/$REPO/releases/tag/$VERSION"
