#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
APP_PATH="$FLUTTER_DIR/build/macos/Build/Products/Release/hivra_app.app"

VERSION=""
CHANNEL=""
OUTPUT_DIR=""

usage() {
  cat <<'EOF'
Usage:
  tools/release/macos_release.sh --version <version> --channel <test|public> [options]

Options:
  --version <version>      Required. Release version label (for example: v1.0.1-test5).
  --channel <channel>      Required. test | public.
  --output-dir <dir>       Optional. Defaults to dist/<version>-<channel>-macos.
  --help                   Show this help.

Environment:
  HIVRA_MAC_CODESIGN_IDENTITY   Optional for test, required for public.
                                Example: Developer ID Application: Example Org (TEAMID)
  HIVRA_MAC_NOTARY_PROFILE      Optional for test, required for public.
                                xcrun notarytool keychain profile name.

Notes:
  - public channel requires both signing and notarization.
  - output includes ZIP, SHA256SUMS.txt, and RELEASE-METADATA.txt.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_clean_tracked_worktree() {
  command -v git >/dev/null 2>&1 || die "Required command not found: git"
  git diff --quiet || die "release packaging requires a clean tracked worktree"
  git diff --cached --quiet || die "release packaging requires a clean index"
}

info() {
  echo "== $* =="
}

verify_macos_app_bundle() {
  local app_path="$1"
  local context="$2"
  local ffi_lib="$app_path/Contents/Frameworks/libhivra_ffi.dylib"

  [ -d "$app_path" ] || die "$context app bundle not found: $app_path"
  [ -f "$ffi_lib" ] || die "$context missing bundled FFI library: $ffi_lib"

  info "Verify $context app bundle"
  file "$ffi_lib"

  local lipo_info
  lipo_info="$(lipo -info "$ffi_lib" 2>/dev/null || true)"
  echo "$lipo_info"
  if [[ "$lipo_info" != *"x86_64"* ]] || [[ "$lipo_info" != *"arm64"* ]]; then
    die "$context libhivra_ffi.dylib is not universal (expected x86_64 + arm64)"
  fi

  codesign --verify --deep --strict "$app_path"
}

verify_macos_app_version() {
  local app_path="$1"
  local expected_name="$2"
  local expected_number="$3"
  local plist="$app_path/Contents/Info.plist"
  local actual_name
  local actual_number

  [ -f "$plist" ] || die "Missing Info.plist: $plist"
  actual_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  actual_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
  [ "$actual_name" = "$expected_name" ] ||
    die "Embedded macOS version is $actual_name, expected $expected_name"
  [ "$actual_number" = "$expected_number" ] ||
    die "Embedded macOS build is $actual_number, expected $expected_number"
}

verify_packaged_zip_bundle() {
  local zip_path="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  info "Verify packaged ZIP artifact"
  ditto -x -k "$zip_path" "$tmp_dir"

  local extracted_app="$tmp_dir/hivra_app.app"
  if [ ! -d "$extracted_app" ]; then
    extracted_app="$(find "$tmp_dir" -maxdepth 3 -type d -name '*.app' | head -n1 || true)"
  fi
  [ -n "$extracted_app" ] || die "No .app bundle found after extracting $zip_path"
  verify_macos_app_bundle "$extracted_app" "packaged ZIP"

  rm -rf "$tmp_dir"
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
    --output-dir)
      OUTPUT_DIR="${2:-}"
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
require_clean_tracked_worktree

FLUTTER_BUILD_NAME="$("$ROOT/tools/release/derive_flutter_version.sh" \
  --version "$VERSION" --field name)"
FLUTTER_BUILD_NUMBER="$("$ROOT/tools/release/derive_flutter_version.sh" \
  --version "$VERSION" --field number)"
SOURCE_COMMIT="$(git rev-parse HEAD)"

"$ROOT/tools/release/release_version_guard.sh" \
  --version "$VERSION" \
  --channel "$CHANNEL"

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$ROOT/dist/${VERSION}-${CHANNEL}-macos"
fi

SIGNED="no"
NOTARIZED="no"
CODESIGN_IDENTITY="${HIVRA_MAC_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${HIVRA_MAC_NOTARY_PROFILE:-}"

if [ "$CHANNEL" = "public" ]; then
  [ -n "$CODESIGN_IDENTITY" ] || die "public channel requires HIVRA_MAC_CODESIGN_IDENTITY"
  [ -n "$NOTARY_PROFILE" ] || die "public channel requires HIVRA_MAC_NOTARY_PROFILE"
fi

info "Release preflight"
"$ROOT/tools/release/preflight.sh" \
  --trading-evidence-build-tag "$VERSION"

info "Build macOS release bundle"
(
  cd "$FLUTTER_DIR"
  flutter build macos --release \
    --build-name "$FLUTTER_BUILD_NAME" \
    --build-number "$FLUTTER_BUILD_NUMBER"
)

[ -d "$APP_PATH" ] || die "Release app bundle not found: $APP_PATH"

if [ -n "$CODESIGN_IDENTITY" ]; then
  info "Codesign app bundle"
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH"
  SIGNED="yes"
else
  info "Codesign identity not set (unsigned build)"
fi

verify_macos_app_bundle "$APP_PATH" "build-tree"
verify_macos_app_version \
  "$APP_PATH" "$FLUTTER_BUILD_NAME" "$FLUTTER_BUILD_NUMBER"

info "Gatekeeper assessment (recorded)"
set +e
SPCTL_OUTPUT="$(spctl --assess --type execute "$APP_PATH" 2>&1)"
SPCTL_STATUS=$?
set -e
echo "$SPCTL_OUTPUT"

mkdir -p "$OUTPUT_DIR"
ASSET_NAME="hivra_app-${VERSION}-macos-universal.zip"
ZIP_PATH="$OUTPUT_DIR/$ASSET_NAME"
SHA_PATH="$OUTPUT_DIR/SHA256SUMS.txt"
META_PATH="$OUTPUT_DIR/RELEASE-METADATA.txt"

info "Package ZIP artifact"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
verify_packaged_zip_bundle "$ZIP_PATH"

if [ -n "$NOTARY_PROFILE" ]; then
  info "Submit for notarization"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  info "Staple notarization ticket"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"

  info "Repackage ZIP with stapled app"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
  NOTARIZED="yes"
  verify_packaged_zip_bundle "$ZIP_PATH"
else
  info "Notary profile not set (not notarized)"
fi

if [ "$CHANNEL" = "public" ]; then
  [ "$SIGNED" = "yes" ] || die "public channel must be signed"
  [ "$NOTARIZED" = "yes" ] || die "public channel must be notarized"
fi

info "Generate SHA256SUMS"
ZIP_SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$ZIP_SHA" "$ASSET_NAME" > "$SHA_PATH"

cat > "$META_PATH" <<EOF
version=$VERSION
source_commit=$SOURCE_COMMIT
source_tree_dirty=no
flutter_build_name=$FLUTTER_BUILD_NAME
flutter_build_number=$FLUTTER_BUILD_NUMBER
channel=$CHANNEL
signed=$SIGNED
notarized=$NOTARIZED
codesign_identity=${CODESIGN_IDENTITY:-none}
notary_profile=${NOTARY_PROFILE:-none}
spctl_status=$SPCTL_STATUS
spctl_output=$SPCTL_OUTPUT
asset=$ASSET_NAME
asset_sha256=$ZIP_SHA
EOF

info "Done"
echo "Output directory: $OUTPUT_DIR"
echo "Artifact: $ZIP_PATH"
echo "SHA256: $ZIP_SHA"
