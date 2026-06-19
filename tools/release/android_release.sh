#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
APK_SOURCE_PATH="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-release.apk"

VERSION=""
CHANNEL=""
OUTPUT_DIR=""

usage() {
  cat <<'EOF'
Usage:
  tools/release/android_release.sh --version <version> --channel <test|public> [options]

Options:
  --version <version>      Required. Release version label (for example: v1.0.1-test5).
  --channel <channel>      Required. test | public.
  --output-dir <dir>       Optional. Defaults to dist/<version>-<channel>-android.
  --help                   Show this help.

Notes:
  - This script packages one universal APK artifact.
  - Output includes APK, SHA256SUMS.txt, and RELEASE-METADATA.txt.
EOF
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

FLUTTER_BUILD_NAME="$("$ROOT/tools/release/derive_flutter_version.sh" \
  --version "$VERSION" --field name)"
FLUTTER_BUILD_NUMBER="$("$ROOT/tools/release/derive_flutter_version.sh" \
  --version "$VERSION" --field number)"

"$ROOT/tools/release/release_version_guard.sh" \
  --version "$VERSION" \
  --channel "$CHANNEL"

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$ROOT/dist/${VERSION}-${CHANNEL}-android"
fi

require_cmd flutter
require_cmd unzip
require_cmd shasum

info "Release preflight"
"$ROOT/tools/release/preflight.sh" \
  --trading-evidence-build-tag "$VERSION"

info "Build Android release APK"
(
  cd "$FLUTTER_DIR"
  flutter build apk --release \
    --build-name "$FLUTTER_BUILD_NAME" \
    --build-number "$FLUTTER_BUILD_NUMBER"
)

[ -f "$APK_SOURCE_PATH" ] || die "Release APK not found at $APK_SOURCE_PATH"

info "Validate bundled FFI libraries in APK"
apk_entries="$(unzip -Z1 "$APK_SOURCE_PATH")"
for abi in arm64-v8a armeabi-v7a x86_64; do
  if ! grep -Fq "lib/${abi}/libhivra_ffi.so" <<< "$apk_entries"; then
    die "Missing libhivra_ffi.so for ABI ${abi} in release APK"
  fi
done

mkdir -p "$OUTPUT_DIR"
ASSET_NAME="hivra_app-${VERSION}-android-universal.apk"
APK_PATH="$OUTPUT_DIR/$ASSET_NAME"
SHA_PATH="$OUTPUT_DIR/SHA256SUMS.txt"
META_PATH="$OUTPUT_DIR/RELEASE-METADATA.txt"

info "Package APK artifact"
cp "$APK_SOURCE_PATH" "$APK_PATH"

info "Generate SHA256SUMS"
APK_SHA="$(shasum -a 256 "$APK_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$APK_SHA" "$ASSET_NAME" > "$SHA_PATH"

cat > "$META_PATH" <<EOF
version=$VERSION
flutter_build_name=$FLUTTER_BUILD_NAME
flutter_build_number=$FLUTTER_BUILD_NUMBER
channel=$CHANNEL
pre_release_expected=$([ "$CHANNEL" = "test" ] && echo "yes" || echo "no")
asset=$ASSET_NAME
asset_sha256=$APK_SHA
source_apk=$APK_SOURCE_PATH
EOF

info "Done"
echo "Output directory: $OUTPUT_DIR"
echo "Artifact: $APK_PATH"
echo "SHA256: $APK_SHA"
