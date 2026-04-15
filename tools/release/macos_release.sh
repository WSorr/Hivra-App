#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
APP_PATH="$FLUTTER_DIR/build/macos/Build/Products/Release/hivra_app.app"

VERSION=""
CHANNEL=""
OUTPUT_DIR=""
RUN_PREFLIGHT=1
RUN_BUILD=1

usage() {
  cat <<'EOF'
Usage:
  tools/release/macos_release.sh --version <version> --channel <test|public> [options]

Options:
  --version <version>      Required. Release version label (for example: v1.0.1-test5).
  --channel <channel>      Required. test | public.
  --output-dir <dir>       Optional. Defaults to dist/<version>-<channel>-macos.
  --skip-preflight         Optional. Skip tools/release/preflight.sh.
  --skip-build             Optional. Skip flutter build macos --release.
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

info() {
  echo "== $* =="
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
    --skip-preflight)
      RUN_PREFLIGHT=0
      shift
      ;;
    --skip-build)
      RUN_BUILD=0
      shift
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

if [ "$RUN_PREFLIGHT" -eq 1 ]; then
  info "Release preflight"
  "$ROOT/tools/release/preflight.sh"
fi

if [ "$RUN_BUILD" -eq 1 ]; then
  info "Build macOS release bundle"
  (
    cd "$FLUTTER_DIR"
    flutter build macos --release
  )
fi

[ -d "$APP_PATH" ] || die "Release app bundle not found: $APP_PATH"

if [ -n "$CODESIGN_IDENTITY" ]; then
  info "Codesign app bundle"
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH"
  SIGNED="yes"
else
  info "Codesign identity not set (unsigned build)"
fi

info "Verify bundle signature"
codesign --verify --deep --strict "$APP_PATH"

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
