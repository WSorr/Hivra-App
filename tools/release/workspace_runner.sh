#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHIVE="hivra-workspace-runner-linux-x64.tar.gz"
ASSETS="$ROOT/flutter/assets/workspace_runner"
. "$ROOT/toolchains/hivra-baseline.conf"

verify_distribution() {
  local directory="$1" expected="$2" archive="$1/$ARCHIVE" metadata actual entries
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  [ -f "$archive" ] && [ ! -L "$archive" ] || return 1
  [ "$(wc -c < "$archive" | tr -d ' ')" -le 16777216 ] || return 1
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || { echo 'Runner digest mismatch.' >&2; return 1; }
  entries="$(tar -tzf "$archive" | LC_ALL=C sort)"
  [ "$entries" = "$(printf '%s\n' ./ ./BUILD-METADATA.txt ./bin/ ./bin/hivra-workspace-runner ./bin/libhivra_ffi.so ./hivra-workspace-runner.service | LC_ALL=C sort)" ] || return 1
  tar -tvzf "$archive" | awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" {exit 1}' || return 1
  metadata="$(tar -xOzf "$archive" ./BUILD-METADATA.txt | head -c 8193)"
  [ "${#metadata}" -le 8192 ] || return 1
  [ "$(printf '%s\n' "$metadata" | cut -d= -f1 | LC_ALL=C sort)" = "$(printf '%s\n' source_commit source_tree source_dirty platform workspace_protocol rust dart | LC_ALL=C sort)" ] || return 1
  [[ "$(printf '%s\n' "$metadata" | sed -n 's/^source_commit=//p')" =~ ^[0-9a-f]{40}$ ]] || return 1
  grep -Fxq "source_tree=$(git -C "$ROOT" rev-parse 'HEAD^{tree}')" <<< "$metadata" || {
    echo 'Runner source tree differs from Capsule; obtain the matching canonical CI artifact.' >&2
    return 1
  }
  for value in source_dirty=0 platform=linux-x64 workspace_protocol=1 "rust=$RUST_VERSION" "dart=$DART_VERSION"; do
    grep -Fxq "$value" <<< "$metadata" || return 1
  done
}

case "${1:-}" in
  --prepare-assets)
    [ "$#" = 3 ] || { echo 'Usage: workspace_runner.sh --prepare-assets <CI-artifact-directory> <verified-archive-sha256>' >&2; exit 1; }
    git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet || {
      echo 'Prepare runner assets only for a clean tracked source tree.' >&2; exit 1;
    }
    verify_distribution "$2" "$3"
    mkdir -p "$ASSETS"
    [ ! -L "$ASSETS" ] || exit 1
    [ ! -L "$ASSETS/$ARCHIVE.next" ] && [ ! -L "$ASSETS/SHA256SUMS.txt.next" ] || exit 1
    trap 'rm -f "$ASSETS/$ARCHIVE.next" "$ASSETS/SHA256SUMS.txt.next"' EXIT
    cp "$2/$ARCHIVE" "$ASSETS/$ARCHIVE.next"
    printf '%s  %s\n' "$3" "$ARCHIVE" > "$ASSETS/SHA256SUMS.txt.next"
    mv -f "$ASSETS/$ARCHIVE.next" "$ASSETS/$ARCHIVE"
    mv -f "$ASSETS/SHA256SUMS.txt.next" "$ASSETS/SHA256SUMS.txt"
    printf '%s\n' "$3"
    exit 0
    ;;
  --verify-assets)
    [ "$#" -le 2 ] || exit 1
    directory="${2:-$ASSETS}"
    [ -f "$directory/SHA256SUMS.txt" ] && [ ! -L "$directory/SHA256SUMS.txt" ] || {
      echo 'Canonical workspace runner assets are missing; prepare the matching CI artifact before packaging.' >&2; exit 1;
    }
    [ "$(wc -c < "$directory/SHA256SUMS.txt" | tr -d ' ')" -le 256 ] || exit 1
    expected="$(cat "$directory/SHA256SUMS.txt")"
    digest="${expected%% *}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] && [ "$expected" = "$digest  $ARCHIVE" ] || exit 1
    expected="$digest"
    verify_distribution "$directory" "$expected"
    printf '%s\n' "$expected"
    exit 0
    ;;
esac

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
printf 'source_commit=%s\nsource_tree=%s\nsource_dirty=0\nplatform=linux-x64\nworkspace_protocol=1\nrust=%s\ndart=%s\n' \
  "$SOURCE" "$(git -C "$ROOT" rev-parse 'HEAD^{tree}')" "$RUST_VERSION" "$DART_VERSION" > "$STAGE/BUILD-METADATA.txt"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$STAGE" -cf - . | gzip -n > "$OUTPUT/$ARCHIVE"
cd "$OUTPUT"
sha256sum "$ARCHIVE" > SHA256SUMS.txt
echo "Candidate runner: $OUTPUT/$ARCHIVE"
