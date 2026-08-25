#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSET_DIR="$ROOT/flutter/assets/runner"
BUNDLE_ASSET="$ASSET_DIR/runner-bundle-linux-x64.tar.gz"
MANIFEST_ASSET="$ASSET_DIR/runner-bundle-release.json"
CONTROL_SOURCE="$ROOT/tools/trading/hivra-trading-runner-control"
CONTROL_ASSET="$ASSET_DIR/runner-control"
MODE="prepare"

usage() {
  cat <<'EOF'
Usage:
  tools/release/prepare_embedded_runner_bundle.sh [--clean]

Builds the exact Linux x64 Trading Runner bundle from the current clean commit
and writes the two ignored Flutter assets consumed by release packaging.
--clean removes only those generated assets.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --clean)
      MODE="clean"
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

if [ "$MODE" = "clean" ]; then
  rm -f "$BUNDLE_ASSET" "$MANIFEST_ASSET" "$CONTROL_ASSET"
  exit 0
fi

command -v git >/dev/null 2>&1 || die "Required command not found: git"
command -v python3 >/dev/null 2>&1 || die "Required command not found: python3"
command -v shasum >/dev/null 2>&1 || die "Required command not found: shasum"
command -v tar >/dev/null 2>&1 || die "Required command not found: tar"

git -C "$ROOT" diff --quiet || die "runner embedding requires a clean tracked worktree"
git -C "$ROOT" diff --cached --quiet || die "runner embedding requires a clean index"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
bundle="$work/linux-x64"
archive="$work/runner-bundle-linux-x64.tar.gz"

bash "$ROOT/tools/trading/public_shadow_runner_artifact.sh" \
  --build "$bundle" --target-os linux --target-arch x64
bash "$ROOT/tools/trading/public_shadow_runner_artifact.sh" --verify "$bundle"

tar -C "$work" -czf "$archive" linux-x64
archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
archive_size="$(wc -c < "$archive" | tr -d ' ')"
control_sha="$(shasum -a 256 "$CONTROL_SOURCE" | awk '{print $1}')"
control_size="$(wc -c < "$CONTROL_SOURCE" | tr -d ' ')"
source_commit="$(git -C "$ROOT" rev-parse HEAD)"

mkdir -p "$ASSET_DIR"
install -m 0644 "$archive" "$BUNDLE_ASSET"
install -m 0644 "$CONTROL_SOURCE" "$CONTROL_ASSET"
python3 - "$MANIFEST_ASSET" "$archive_sha" "$archive_size" "$control_sha" "$control_size" "$source_commit" <<'PY'
import json
import os
import sys
import tempfile

target, digest, size, control_digest, control_size, source_commit = sys.argv[1:]
payload = {
    "schema_version": "hivra-embedded-runner-release-v1",
    "target": "linux/x64",
    "archive_asset": "assets/runner/runner-bundle-linux-x64.tar.gz",
    "archive_sha256": digest,
    "archive_size": int(size),
    "control_asset": "assets/runner/runner-control",
    "control_sha256": control_digest,
    "control_size": int(control_size),
    "source_commit": source_commit,
}
directory = os.path.dirname(target)
fd, pending = tempfile.mkstemp(prefix=".runner-release.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(pending, 0o644)
    os.replace(pending, target)
finally:
    if os.path.exists(pending):
        os.unlink(pending)
PY

echo "PASS embedded-runner: target=linux/x64 sha256=$archive_sha size=$archive_size source_commit=$source_commit"
