#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="${1:?Usage: workspace_runner.sh <output-directory>}"

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || {
  echo 'The canonical runner builder requires Ubuntu 24.04 x86_64.' >&2
  exit 1
}
. /etc/os-release
[ "$ID" = ubuntu ] && [ "$VERSION_ID" = 24.04 ] || exit 1
[ -z "$(git -C "$ROOT" status --porcelain)" ] || {
  echo 'Runner packaging requires a clean checkout.' >&2
  exit 1
}
SOURCE="$(git -C "$ROOT" rev-parse HEAD)"
EPOCH="$(git -C "$ROOT" show -s --format=%ct HEAD)"
. "$ROOT/toolchains/hivra-baseline.conf"
[[ "$(dart --version 2>&1)" == "Dart SDK version: $DART_VERSION "* ]] || exit 1
[[ "$(rustc --version)" == "rustc $RUST_VERSION "* ]] || exit 1

mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cd "$ROOT/flutter"
flutter pub get --enforce-lockfile
dart build cli --target bin/plugin_workspace_runner.dart --output "$STAGE/dart"
mv "$STAGE/dart/bundle/bin" "$STAGE/bin"
if [ -d "$STAGE/dart/bundle/lib" ]; then
  mv "$STAGE/dart/bundle/lib" "$STAGE/lib"
fi
mv "$STAGE/bin/plugin_workspace_runner" "$STAGE/bin/hivra-workspace-runner"
rm -rf "$STAGE/dart"
cd "$ROOT"
cargo build --release -p hivra-ffi --no-default-features --locked
cp "${CARGO_TARGET_DIR:-$ROOT/target}/release/libhivra_ffi.so" "$STAGE/bin/"

cat > "$STAGE/hivra-workspace-runner.service" <<'EOF'
[Unit]
Description=Hivra installed WASM workspace
After=network-online.target
Wants=network-online.target

[Service]
User=hivra-workspace
Group=hivra-workspace
StateDirectory=hivra-workspace
StateDirectoryMode=0700
UMask=0077
ExecStart=/opt/hivra-workspace/current/bin/hivra-workspace-runner serve /var/lib/hivra-workspace
Restart=on-failure
RestartSec=15
TimeoutStopSec=90
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
EOF

[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SOURCE" ] && \
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || {
  echo 'Source changed during runner packaging; candidate rejected.' >&2
  exit 1
}
printf 'source_commit=%s\nsource_dirty=0\nplatform=linux-x64\nrust=%s\ndart=%s\n' \
  "$SOURCE" "$RUST_VERSION" "$DART_VERSION" > "$STAGE/BUILD-METADATA.txt"
ARCHIVE="hivra-workspace-runner-linux-x64.tar.gz"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$STAGE" -cf - . | gzip -n > "$OUTPUT/$ARCHIVE"
cd "$OUTPUT"
sha256sum "$ARCHIVE" > SHA256SUMS.txt
echo "Candidate runner: $OUTPUT/$ARCHIVE"
