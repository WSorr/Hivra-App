#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="$ROOT/flutter"
APP_PATH="$FLUTTER_DIR/build/macos/Build/Products/Release/hivra_app.app"
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
  verify_macos_app_bundle "$APP_PATH" "build-tree app bundle"
}

verify_macos_app_bundle() {
  local app_path="$1"
  local context="$2"
  local ffi_lib="$app_path/Contents/Frameworks/libhivra_ffi.dylib"

  if [ ! -f "$ffi_lib" ]; then
    echo "FAIL: Missing bundled FFI library at $ffi_lib ($context)"
    return 1
  fi

  echo "$context: $app_path"
  echo "FFI library: $ffi_lib"

  file "$ffi_lib"

  local lipo_info
  lipo_info="$(lipo -info "$ffi_lib" 2>/dev/null || true)"
  echo "$lipo_info"

  if [[ "$lipo_info" != *"x86_64"* ]] || [[ "$lipo_info" != *"arm64"* ]]; then
    echo "FAIL: libhivra_ffi.dylib is not universal (expected x86_64 + arm64)"
    return 1
  fi

  codesign --verify --deep --strict "$app_path"

  local spctl_output
  set +e
  spctl_output="$(spctl --assess --type execute "$app_path" 2>&1)"
  local spctl_status=$?
  set -e

  echo "$spctl_output"
  if [ $spctl_status -ne 0 ]; then
    echo "WARN: Gatekeeper assessment did not pass. This is expected for unsigned test builds."
  fi
}

check_packaged_macos_release_bundle() {
  local packaged_zip
  packaged_zip="$(ls -1t "$ROOT"/dist/*-macos/hivra_app-*-macos-universal*.zip 2>/dev/null | head -n1 || true)"
  if [ -z "$packaged_zip" ]; then
    echo "WARN: No packaged macOS ZIP artifact found in dist/"
    echo "      Build one first with: tools/release/macos_release.sh --version <v> --channel <test|public>"
    return 0
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  echo "Packaged ZIP artifact: $packaged_zip"
  ditto -x -k "$packaged_zip" "$tmp_dir"

  local extracted_app="$tmp_dir/hivra_app.app"
  if [ ! -d "$extracted_app" ]; then
    extracted_app="$(find "$tmp_dir" -maxdepth 3 -type d -name '*.app' | head -n1 || true)"
  fi
  if [ -z "$extracted_app" ]; then
    rm -rf "$tmp_dir"
    echo "FAIL: No .app bundle found after extracting $packaged_zip"
    return 1
  fi

  if ! verify_macos_app_bundle "$extracted_app" "packaged ZIP app bundle"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
}

check_android_release_bundle() {
  if [ ! -f "$ANDROID_APK" ]; then
    echo "WARN: Release APK not found at $ANDROID_APK"
    echo "      Build it first with: flutter build apk --release"
    return 0
  fi

  echo "Android APK: $ANDROID_APK"

  local apk_entries
  apk_entries="$(unzip -Z1 "$ANDROID_APK" 2>/dev/null || true)"

  if ! rg -q "lib/arm64-v8a/libhivra_ffi\\.so" <<< "$apk_entries"; then
    echo "FAIL: Missing arm64-v8a libhivra_ffi.so in APK"
    return 1
  fi
  if ! rg -q "lib/armeabi-v7a/libhivra_ffi\\.so" <<< "$apk_entries"; then
    echo "FAIL: Missing armeabi-v7a libhivra_ffi.so in APK"
    return 1
  fi
  if ! rg -q "lib/x86_64/libhivra_ffi\\.so" <<< "$apk_entries"; then
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

  run_step "Packaged macOS Artifact Checks" \
    check_packaged_macos_release_bundle

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
