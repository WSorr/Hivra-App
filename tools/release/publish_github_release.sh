#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${HIVRA_RELEASE_REPO:-WSorr/Hivra-App}"
MANUAL_SIGNOFF_LOG="${HIVRA_MANUAL_SIGNOFF_LOG:-$ROOT/docs/checklists/release-manual-signoff-log.md}"

VERSION=""
CHANNEL=""
TITLE=""
NOTES_FILE=""

usage() {
  cat <<'USAGE'
Usage:
  tools/release/publish_github_release.sh --version <version> --channel <test|public> [options]
  tools/release/publish_github_release.sh --self-test

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

field_value() {
  local row="$1"
  local index="$2"
  awk -F'|' -v idx="$index" '{
    gsub(/^[ \t]+|[ \t]+$/, "", $idx)
    print $idx
  }' <<< "$row"
}

find_signoff_row() {
  local platform="$1"
  awk -F'|' -v tag="$VERSION" -v platform="$platform" '
    $0 ~ /^\|/ {
      original = $0
      for (i = 1; i <= NF; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i)
      }
      if ($2 == tag && $4 == platform) {
        print original
        exit
      }
    }
  ' "$MANUAL_SIGNOFF_LOG"
}

require_signoff_artifact_sha() {
  local platform="$1"
  local artifact_path="$2"
  local row
  local expected_name expected_sha actual_sha

  row="$(find_signoff_row "$platform")"
  [ -n "$row" ] || die "missing $platform signoff row for $VERSION"

  expected_name="$(field_value "$row" 5)"
  expected_sha="$(field_value "$row" 6)"
  if [ -z "$expected_name" ] || [ -z "$expected_sha" ]; then
    die "$platform signoff row missing artifact name or artifact SHA-256"
  fi

  if [ "${artifact_path##*/}" != "$expected_name" ]; then
    die "$platform signoff artifact mismatch (expected $expected_name, got ${artifact_path##*/})"
  fi
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die "$platform signoff artifact sha-256 must be a lowercase 64-hex digest"

  actual_sha="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"
  if [ "$actual_sha" != "$expected_sha" ]; then
    die "$platform artifact sha mismatch (expected $expected_sha, got $actual_sha)"
  fi
}

self_test() {
  local test_dir artifact artifact_copy artifact_sha
  test_dir="$(mktemp -d)"
  artifact="$test_dir/hivra_app-v-selftest-macos-universal.zip"
  artifact_copy="$test_dir/hivra_app-v-selftest-macos-other.zip"

  printf 'verified release bytes' > "$artifact"
  artifact_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
  MANUAL_SIGNOFF_LOG="$test_dir/signoff.md"
  VERSION="v-selftest"
  printf '| v-selftest | 2026-01-01T00:00:00Z | macOS | %s | %s | PASS | PASS | PASS | PASS | PASS | codex | self-test |\n' \
    "${artifact##*/}" "$artifact_sha" > "$MANUAL_SIGNOFF_LOG"

  require_signoff_artifact_sha macOS "$artifact"

  printf 'mutated release bytes' > "$artifact"
  if (require_signoff_artifact_sha macOS "$artifact" >/dev/null 2>&1); then
    rm -f "$artifact" "$MANUAL_SIGNOFF_LOG"
    rmdir "$test_dir"
    die "artifact digest mutation was accepted"
  fi

  printf 'verified release bytes' > "$artifact_copy"
  if (require_signoff_artifact_sha macOS "$artifact_copy" >/dev/null 2>&1); then
    rm -f "$artifact" "$artifact_copy" "$MANUAL_SIGNOFF_LOG"
    rmdir "$test_dir"
    die "artifact name mutation was accepted"
  fi

  rm -f "$artifact" "$artifact_copy" "$MANUAL_SIGNOFF_LOG"
  rmdir "$test_dir"
  echo "PASS release-publication: self-test"
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

require_release_only_changes_after_build() {
  local source_commit="$1"
  local changed_file

  git merge-base --is-ancestor "$source_commit" HEAD ||
    die "Artifact source commit $source_commit is not an ancestor of release HEAD"

  while IFS= read -r changed_file; do
    [ -z "$changed_file" ] && continue
    case "$changed_file" in
      docs/checklists/release-manual-signoff-log.md)
        ;;
      *)
        die "Runtime-affecting file changed after artifact build: $changed_file"
        ;;
    esac
  done < <(git diff --name-only "$source_commit"..HEAD)
}

verify_release_metadata() {
  local file="$1"
  local platform="$2"
  local version
  local source_commit
  local source_tree_dirty

  version="$(metadata_value "$file" version)"
  source_commit="$(metadata_value "$file" source_commit)"
  source_tree_dirty="$(metadata_value "$file" source_tree_dirty)"

  [ "$version" = "$VERSION" ] ||
    die "$platform metadata version is ${version:-missing}, expected $VERSION"
  git cat-file -e "$source_commit^{commit}" 2>/dev/null ||
    die "$platform metadata source_commit is missing or invalid: ${source_commit:-missing}"
  [ "$source_tree_dirty" = "no" ] ||
    die "$platform metadata source_tree_dirty must be no"
  require_release_only_changes_after_build "$source_commit"
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
    --self-test)
      require_cmd shasum
      self_test
      exit 0
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

require_signoff_artifact_sha macOS "$MAC_ASSET"
require_signoff_artifact_sha Android "$ANDROID_ASSET"

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
