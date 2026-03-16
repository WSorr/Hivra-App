#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)/.."
JNI_LIBS_DIR="$SCRIPT_DIR/app/build/generated/rustJniLibs"

rm -rf "$JNI_LIBS_DIR"
mkdir -p "$JNI_LIBS_DIR"

cd "$PROJECT_ROOT"

cargo ndk \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "$JNI_LIBS_DIR" \
  build --release -p hivra-ffi
