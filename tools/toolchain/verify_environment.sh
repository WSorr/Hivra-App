#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_BASELINE="$ROOT/toolchains/hivra-baseline.conf"
BASELINE="${HIVRA_TOOLCHAIN_TEST_BASELINE:-$DEFAULT_BASELINE}"
RUST_TOOLCHAIN="$ROOT/rust-toolchain.toml"
MODE="full"
SELF_TEST=0
STATUS=0

usage() {
  cat <<'USAGE'
Usage: tools/toolchain/verify_environment.sh [--full|--static|--self-test]

Modes:
  --full    Verify checked-in pins and the complete local macOS/Android toolchain.
  --static  Verify only repository-owned pins and build configuration (CI-safe).
  --self-test
            Prove that a version mismatch fails with expected and actual values.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --full)
      MODE="full"
      ;;
    --static)
      MODE="static"
      ;;
    --self-test)
      SELF_TEST=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -n "${HIVRA_TOOLCHAIN_TEST_BASELINE:-}" ] &&
   [ "${HIVRA_TOOLCHAIN_SELF_TEST:-0}" != "1" ]; then
  echo "HIVRA_TOOLCHAIN_TEST_BASELINE is reserved for verifier self-test" >&2
  exit 2
fi

pass() {
  printf 'PASS toolchain: %s\n' "$1"
}

fail() {
  printf 'FAIL toolchain: %s\n' "$1" >&2
  STATUS=1
}

warn() {
  printf 'WARN toolchain: %s\n' "$1"
}

require_file() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    pass "$label exists"
  else
    fail "$label is missing: ${path#$ROOT/}"
  fi
}

baseline_value() {
  local key="$1"
  local count
  count="$(grep -c "^${key}=" "$BASELINE" || true)"
  if [ "$count" -ne 1 ]; then
    fail "baseline key $key must appear exactly once (found $count)"
    return 1
  fi
  sed -n "s/^${key}=//p" "$BASELINE"
}

expect_equal() {
  local surface="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$surface = $actual"
  else
    fail "$surface mismatch (expected $expected, actual ${actual:-missing})"
  fi
}

expect_contains() {
  local path="$1"
  local fixed_text="$2"
  local label="$3"
  if grep -Fq -- "$fixed_text" "$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "command $command_name is available"
  else
    fail "required command is missing: $command_name"
  fi
}

source_property() {
  local path="$1"
  local key="$2"
  sed -n -E "s/^${key}[[:space:]]*=[[:space:]]*//p" "$path" | head -n1
}

verify_baseline_shape() {
  local required_keys='SCHEMA_VERSION FLUTTER_CHANNEL FLUTTER_VERSION FLUTTER_FRAMEWORK_REVISION DART_VERSION RUST_VERSION CARGO_VERSION RUST_PROFILE RUST_COMPONENTS RUST_TARGETS ANDROID_PLATFORM ANDROID_BUILD_TOOLS ANDROID_COMPILE_SDK ANDROID_TARGET_SDK ANDROID_MIN_SDK ANDROID_NDK ANDROID_GRADLE_PLUGIN GRADLE_VERSION KOTLIN_PLUGIN JDK_MAJOR XCODE_VERSION XCODE_BUILD MACOS_SDK COCOAPODS_VERSION'
  local key
  local line

  require_file "$BASELINE" "toolchain baseline"
  require_file "$RUST_TOOLCHAIN" "Rust toolchain pin"
  [ -f "$BASELINE" ] || return

  if grep -Ev '^[A-Z][A-Z0-9_]*=[A-Za-z0-9._,-]+$' "$BASELINE" | grep -q .; then
    fail "baseline contains an invalid or unsafe line"
  else
    pass "baseline uses strict non-secret KEY=value records"
  fi

  for key in $required_keys; do
    baseline_value "$key" >/dev/null || true
  done

  while IFS= read -r line; do
    key="${line%%=*}"
    case " $required_keys " in
      *" $key "*) ;;
      *) fail "baseline contains unknown key $key" ;;
    esac
  done < "$BASELINE"

  expect_equal "baseline schema" "1" "$(baseline_value SCHEMA_VERSION || true)"
}

verify_static_contract() {
  local rust_version
  local rust_profile
  local rust_components
  local rust_targets
  local agp_version
  local kotlin_version
  local gradle_version
  local actual_rust_version
  local actual_rust_profile

  rust_version="$(baseline_value RUST_VERSION || true)"
  rust_profile="$(baseline_value RUST_PROFILE || true)"
  rust_components="$(baseline_value RUST_COMPONENTS || true)"
  rust_targets="$(baseline_value RUST_TARGETS || true)"
  actual_rust_version="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$RUST_TOOLCHAIN")"
  actual_rust_profile="$(sed -n 's/^profile = "\([^"]*\)"/\1/p' "$RUST_TOOLCHAIN")"
  expect_equal "rust-toolchain channel" "$rust_version" "$actual_rust_version"
  expect_equal "rust-toolchain profile" "$rust_profile" "$actual_rust_profile"
  expect_contains "$RUST_TOOLCHAIN" "components = [\"$rust_components\"]" \
    "rust-toolchain pins components $rust_components"
  expect_contains "$RUST_TOOLCHAIN" \
    "targets = [\"${rust_targets//,/\", \"}\"]" \
    "rust-toolchain pins every required target"

  agp_version="$(baseline_value ANDROID_GRADLE_PLUGIN || true)"
  kotlin_version="$(baseline_value KOTLIN_PLUGIN || true)"
  gradle_version="$(baseline_value GRADLE_VERSION || true)"
  expect_contains "$ROOT/flutter/android/settings.gradle.kts" \
    "id(\"com.android.application\") version \"$agp_version\" apply false" \
    "Android Gradle Plugin matches baseline"
  expect_contains "$ROOT/flutter/android/settings.gradle.kts" \
    "id(\"org.jetbrains.kotlin.android\") version \"$kotlin_version\" apply false" \
    "Kotlin plugin matches baseline"
  expect_contains "$ROOT/flutter/android/gradle/wrapper/gradle-wrapper.properties" \
    "gradle-${gradle_version}-all.zip" \
    "Gradle wrapper matches baseline"
  expect_contains "$ROOT/flutter/android/app/build.gradle.kts" \
    "compileSdk = flutter.compileSdkVersion" \
    "Android compile SDK remains owned by the pinned Flutter toolchain"
  expect_contains "$ROOT/flutter/android/app/build.gradle.kts" \
    "ndkVersion = flutter.ndkVersion" \
    "Android NDK remains owned by the pinned Flutter toolchain"
  expect_contains "$ROOT/flutter/android/app/build.gradle.kts" \
    "targetSdk = flutter.targetSdkVersion" \
    "Android target SDK remains owned by the pinned Flutter toolchain"
  expect_contains "$ROOT/flutter/android/app/build.gradle.kts" \
    "minSdk = flutter.minSdkVersion" \
    "Android min SDK remains owned by the pinned Flutter toolchain"
}

verify_flutter_and_dart() {
  local flutter_machine
  local actual_flutter
  local actual_channel
  local actual_revision
  local actual_dart

  flutter_machine="$(flutter --version --machine 2>/dev/null || true)"
  actual_flutter="$(printf '%s\n' "$flutter_machine" | sed -n 's/.*"frameworkVersion": "\([^"]*\)".*/\1/p' | head -n1)"
  actual_channel="$(printf '%s\n' "$flutter_machine" | sed -n 's/.*"channel": "\([^"]*\)".*/\1/p' | head -n1)"
  actual_revision="$(printf '%s\n' "$flutter_machine" | sed -n 's/.*"frameworkRevision": "\([^"]*\)".*/\1/p' | head -n1)"
  actual_dart="$(printf '%s\n' "$flutter_machine" | sed -n 's/.*"dartSdkVersion": "\([^"]*\)".*/\1/p' | head -n1)"
  expect_equal "Flutter" "$(baseline_value FLUTTER_VERSION)" "$actual_flutter"
  expect_equal "Flutter channel" "$(baseline_value FLUTTER_CHANNEL)" "$actual_channel"
  expect_equal "Flutter framework revision" \
    "$(baseline_value FLUTTER_FRAMEWORK_REVISION)" "$actual_revision"
  expect_equal "Dart" "$(baseline_value DART_VERSION)" "$actual_dart"
}

verify_rust() {
  local actual_rust
  local actual_cargo
  local installed_targets
  local required_targets
  local target

  actual_rust="$(rustc --version 2>/dev/null | awk '{print $2}')"
  actual_cargo="$(cargo --version 2>/dev/null | awk '{print $2}')"
  expect_equal "Rust" "$(baseline_value RUST_VERSION)" "$actual_rust"
  expect_equal "Cargo" "$(baseline_value CARGO_VERSION)" "$actual_cargo"

  installed_targets="$(rustup target list --installed 2>/dev/null || true)"
  required_targets="$(baseline_value RUST_TARGETS)"
  for target in ${required_targets//,/ }; do
    if printf '%s\n' "$installed_targets" | grep -Fxq "$target"; then
      pass "Rust target $target is installed"
    else
      fail "Rust target is missing: $target"
    fi
  done
}

verify_android() {
  local local_properties="$ROOT/flutter/android/local.properties"
  local sdk_dir
  local flutter_root
  local platform
  local build_tools
  local ndk
  local flutter_extension
  local flutter_doctor
  local java_binary
  local java_home
  local java_major
  local gradle_output
  local actual_gradle
  local gradle_jvm

  if [ ! -f "$local_properties" ]; then
    fail "flutter/android/local.properties is missing; configure local SDK paths"
    return
  fi
  sdk_dir="$(sed -n 's/^sdk.dir=//p' "$local_properties" | head -n1)"
  flutter_root="$(sed -n 's/^flutter.sdk=//p' "$local_properties" | head -n1)"
  if [ -z "$sdk_dir" ] || [ ! -d "$sdk_dir" ]; then
    fail "local Android SDK path is missing or invalid"
    return
  fi
  if [ -z "$flutter_root" ] || [ ! -d "$flutter_root" ]; then
    fail "local Flutter SDK path is missing or invalid"
    return
  fi
  pass "local SDK paths resolve without entering repository pins"

  platform="$(baseline_value ANDROID_PLATFORM)"
  build_tools="$(baseline_value ANDROID_BUILD_TOOLS)"
  ndk="$(baseline_value ANDROID_NDK)"
  expect_equal "Android build tools" "$build_tools" \
    "$(source_property "$sdk_dir/build-tools/$build_tools/source.properties" Pkg.Revision 2>/dev/null || true)"
  if [ -f "$sdk_dir/platforms/$platform/source.properties" ]; then
    pass "Android platform $platform is installed"
  else
    fail "Android platform is missing: $platform"
  fi
  expect_equal "Android NDK" "$ndk" \
    "$(source_property "$sdk_dir/ndk/$ndk/source.properties" Pkg.Revision 2>/dev/null || true)"

  flutter_extension="$flutter_root/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
  if [ ! -f "$flutter_extension" ]; then
    fail "pinned Flutter Gradle defaults are unavailable"
  else
    expect_contains "$flutter_extension" \
      "val compileSdkVersion: Int = $(baseline_value ANDROID_COMPILE_SDK)" \
      "Flutter compile SDK default matches baseline"
    expect_contains "$flutter_extension" \
      "val targetSdkVersion: Int = $(baseline_value ANDROID_TARGET_SDK)" \
      "Flutter target SDK default matches baseline"
    expect_contains "$flutter_extension" \
      "val minSdkVersion: Int = $(baseline_value ANDROID_MIN_SDK)" \
      "Flutter min SDK default matches baseline"
    expect_contains "$flutter_extension" \
      "val ndkVersion: String = \"$ndk\"" \
      "Flutter NDK default matches baseline"
  fi

  flutter_doctor="$(flutter doctor -v 2>&1 || true)"
  java_binary="$(printf '%s\n' "$flutter_doctor" | sed -n 's/.*Java binary at: //p' | head -n1)"
  if [ -z "$java_binary" ] || [ ! -x "$java_binary" ]; then
    fail "Flutter-resolved JDK binary is unavailable"
    return
  fi
  java_home="$(cd "$(dirname "$java_binary")/.." && pwd)"
  java_major="$("$java_binary" -version 2>&1 | sed -n '1s/.*version "\([0-9]*\).*/\1/p')"
  expect_equal "Flutter-resolved JDK major" "$(baseline_value JDK_MAJOR)" "$java_major"

  gradle_output="$(cd "$ROOT/flutter/android" && JAVA_HOME="$java_home" ./gradlew --version 2>/dev/null || true)"
  actual_gradle="$(printf '%s\n' "$gradle_output" | sed -n 's/^Gradle //p' | head -n1)"
  gradle_jvm="$(printf '%s\n' "$gradle_output" | sed -n 's/^Launcher JVM:[[:space:]]*\([0-9]*\).*/\1/p' | head -n1)"
  expect_equal "Gradle" "$(baseline_value GRADLE_VERSION)" "$actual_gradle"
  expect_equal "Gradle canonical JDK major" "$(baseline_value JDK_MAJOR)" "$gradle_jvm"
  warn "direct ./gradlew is noncanonical; release authority is Flutter-resolved JDK $java_major"
}

verify_apple() {
  local actual_xcode
  local actual_xcode_build
  local actual_macos_sdk
  local actual_pods
  local doctor_output

  if [ "$(uname -s)" != "Darwin" ]; then
    fail "full verification requires macOS for Xcode and CocoaPods evidence"
    return
  fi
  actual_xcode="$(xcodebuild -version 2>/dev/null | sed -n '1s/^Xcode //p')"
  actual_xcode_build="$(xcodebuild -version 2>/dev/null | sed -n '2s/^Build version //p')"
  actual_macos_sdk="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
  actual_pods="$(pod --version 2>/dev/null || true)"
  expect_equal "Xcode" "$(baseline_value XCODE_VERSION)" "$actual_xcode"
  expect_equal "Xcode build" "$(baseline_value XCODE_BUILD)" "$actual_xcode_build"
  expect_equal "macOS SDK" "$(baseline_value MACOS_SDK)" "$actual_macos_sdk"
  expect_equal "CocoaPods" "$(baseline_value COCOAPODS_VERSION)" "$actual_pods"

  doctor_output="$(flutter doctor -v 2>&1 || true)"
  if printf '%s\n' "$doctor_output" | grep -Fq 'Unable to get list of installed Simulator runtimes'; then
    warn "simulator runtime discovery is unhealthy; macOS packaging remains the T0 scope"
  fi
  warn "host macOS $(sw_vers -productVersion) ($(uname -m)) is evidence, not a repository pin"
}

run_self_test() {
  local temp_dir
  local mismatch_baseline
  local output
  local child_status
  local actual_channel

  temp_dir="$(mktemp -d)"
  mismatch_baseline="$temp_dir/hivra-baseline.conf"
  actual_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$RUST_TOOLCHAIN")"
  sed 's/^RUST_VERSION=.*/RUST_VERSION=0.0.0/' \
    "$DEFAULT_BASELINE" > "$mismatch_baseline"
  set +e
  output="$(HIVRA_TOOLCHAIN_SELF_TEST=1 \
    HIVRA_TOOLCHAIN_TEST_BASELINE="$mismatch_baseline" \
    "$0" --static 2>&1)"
  child_status=$?
  set -e
  rm -rf "$temp_dir"

  if [ "$child_status" -ne 0 ] &&
     printf '%s\n' "$output" | grep -Fq \
       "rust-toolchain channel mismatch (expected 0.0.0, actual $actual_channel)"; then
    pass "version mismatch reports expected and actual values"
    return 0
  fi
  printf '%s\n' "$output" >&2
  fail "version mismatch self-test did not fail precisely"
  return 1
}

if [ "$SELF_TEST" -eq 1 ]; then
  run_self_test
  exit "$STATUS"
fi

verify_baseline_shape
if [ -f "$BASELINE" ] && [ -f "$RUST_TOOLCHAIN" ]; then
  verify_static_contract
fi

if [ "$MODE" = "full" ]; then
  for command_name in flutter dart rustc cargo rustup xcodebuild xcrun pod; do
    require_command "$command_name"
  done
  if [ "$STATUS" -eq 0 ]; then
    verify_flutter_and_dart
    verify_rust
    verify_android
    verify_apple
  fi
fi

if [ "$STATUS" -eq 0 ]; then
  printf 'PASS toolchain: Hivra T0 %s verification completed\n' "$MODE"
else
  printf 'FAIL toolchain: Hivra T0 %s verification failed\n' "$MODE" >&2
fi

exit "$STATUS"
