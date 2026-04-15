#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
APP_PATH="$FLUTTER_DIR/build/macos/Build/Products/Release/hivra_app.app"
FFI_LIB="$APP_PATH/Contents/Frameworks/libhivra_ffi.dylib"
ANDROID_APK="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-release.apk"

STATUS=0

run_step() {
  local label="$1"
  shift

  printf '\n== %s ==\n' "$label"
  if ! "$@"; then
    STATUS=1
  fi
}

check_release_bundle() {
  if [ ! -d "$APP_PATH" ]; then
    echo "WARN: Release app bundle not found at $APP_PATH"
    echo "      Build it first with: flutter build macos --release"
    return 0
  fi

  if [ ! -f "$FFI_LIB" ]; then
    echo "FAIL: Missing bundled FFI library at $FFI_LIB"
    return 1
  fi

  echo "App bundle: $APP_PATH"
  echo "FFI library: $FFI_LIB"

  file "$FFI_LIB"

  local lipo_info
  lipo_info="$(lipo -info "$FFI_LIB" 2>/dev/null || true)"
  echo "$lipo_info"

  if [[ "$lipo_info" != *"x86_64"* ]] || [[ "$lipo_info" != *"arm64"* ]]; then
    echo "FAIL: libhivra_ffi.dylib is not universal (expected x86_64 + arm64)"
    return 1
  fi

  codesign --verify --deep --strict "$APP_PATH"

  local spctl_output
  set +e
  spctl_output="$(spctl --assess --type execute "$APP_PATH" 2>&1)"
  local spctl_status=$?
  set -e

  echo "$spctl_output"
  if [ $spctl_status -ne 0 ]; then
    echo "WARN: Gatekeeper assessment did not pass. This is expected for unsigned test builds."
  fi
}

check_android_release_bundle() {
  if [ ! -f "$ANDROID_APK" ]; then
    echo "WARN: Release APK not found at $ANDROID_APK"
    echo "      Build it first with: flutter build apk --release"
    return 0
  fi

  echo "Android APK: $ANDROID_APK"

  if ! unzip -l "$ANDROID_APK" | rg -q "lib/arm64-v8a/libhivra_ffi\\.so"; then
    echo "FAIL: Missing arm64-v8a libhivra_ffi.so in APK"
    return 1
  fi
  if ! unzip -l "$ANDROID_APK" | rg -q "lib/armeabi-v7a/libhivra_ffi\\.so"; then
    echo "FAIL: Missing armeabi-v7a libhivra_ffi.so in APK"
    return 1
  fi
  if ! unzip -l "$ANDROID_APK" | rg -q "lib/x86_64/libhivra_ffi\\.so"; then
    echo "FAIL: Missing x86_64 libhivra_ffi.so in APK"
    return 1
  fi

  echo "PASS: Android APK contains libhivra_ffi.so for required ABIs"
}

main() {
  echo "Hivra release preflight"
  echo "Workspace: $ROOT"

  run_step "Topology / Dependency / Security Review" \
    "$ROOT/tools/review/review_all.sh"

  run_step "User Lifetime Safety Pack Gate" \
    "$ROOT/tools/review/user_lifetime_safety_gate.sh"

  run_step "Rust FFI Tests" \
    cargo test -p hivra-ffi

  run_step "Flutter Analyze" \
    bash -lc "cd \"$FLUTTER_DIR\" && flutter analyze"

  run_step "Flutter Tests" \
    bash -lc "cd \"$FLUTTER_DIR\" && flutter test"

  run_step "macOS Release Bundle Checks" \
    check_release_bundle

  run_step "Android Release Bundle Checks" \
    check_android_release_bundle

  printf '\n== Result ==\n'
  if [ "$STATUS" -eq 0 ]; then
    echo "PASS: preflight checks completed"
  else
    echo "FAIL: one or more preflight checks failed"
  fi

  exit "$STATUS"
}

main "$@"
