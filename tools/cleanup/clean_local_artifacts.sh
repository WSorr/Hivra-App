#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DRY_RUN=0
PURGE_DIST=1
KEEP_LATEST_DIST=1
KEEP_DIST=("plugins")

usage() {
  cat <<'EOF'
Usage:
  tools/cleanup/clean_local_artifacts.sh [options]

Options:
  --dry-run               Print planned deletions without removing files.
  --no-dist               Skip cleanup of dist/ artifacts.
  --keep-dist <name>      Keep an additional folder under dist/ (can repeat).
  --no-keep-latest-dist   Do not auto-keep latest dist/ folder by mtime.
  --help                  Show this help.

Default behavior:
  - remove local build caches:
      target/
      flutter/build/
      flutter/.dart_tool/
      flutter/flutter_01.log
  - cleanup dist/ while keeping:
      dist/plugins
      latest dist/* folder (by mtime)
EOF
}

log() {
  printf '[cleanup] %s\n' "$*"
}

remove_path() {
  local path="$1"
  if [ ! -e "$path" ]; then
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN remove: $path"
    return
  fi
  rm -rf "$path"
  log "removed: $path"
}

has_keep_dist_entry() {
  local name="$1"
  for keep in "${KEEP_DIST[@]}"; do
    if [ "$keep" = "$name" ]; then
      return 0
    fi
  done
  return 1
}

latest_dist_entry() {
  local latest_name=""
  local latest_mtime=0

  if [ ! -d "$ROOT/dist" ]; then
    printf '%s' "$latest_name"
    return
  fi

  while IFS= read -r -d '' path; do
    local name mtime
    name="$(basename "$path")"
    if [ "$name" = "plugins" ]; then
      continue
    fi

    mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path")"
    if [ "$mtime" -gt "$latest_mtime" ]; then
      latest_mtime="$mtime"
      latest_name="$name"
    fi
  done < <(find "$ROOT/dist" -mindepth 1 -maxdepth 1 -type d -print0)

  printf '%s' "$latest_name"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-dist)
      PURGE_DIST=0
      shift
      ;;
    --keep-dist)
      [ $# -ge 2 ] || {
        echo "ERROR: --keep-dist requires a folder name" >&2
        exit 1
      }
      KEEP_DIST+=("$2")
      shift 2
      ;;
    --no-keep-latest-dist)
      KEEP_LATEST_DIST=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

log "root: $ROOT"

remove_path "$ROOT/target"
remove_path "$ROOT/flutter/build"
remove_path "$ROOT/flutter/.dart_tool"
remove_path "$ROOT/flutter/flutter_01.log"

if [ "$PURGE_DIST" -eq 1 ] && [ -d "$ROOT/dist" ]; then
  if [ "$KEEP_LATEST_DIST" -eq 1 ]; then
    latest="$(latest_dist_entry)"
    if [ -n "$latest" ] && ! has_keep_dist_entry "$latest"; then
      KEEP_DIST+=("$latest")
    fi
  fi

  log "dist keep-list: ${KEEP_DIST[*]}"

  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    if has_keep_dist_entry "$name"; then
      log "keep: $path"
      continue
    fi
    remove_path "$path"
  done < <(find "$ROOT/dist" -mindepth 1 -maxdepth 1 -print0)
fi

if command -v du >/dev/null 2>&1; then
  if [ -d "$ROOT/dist" ]; then
    log "size dist: $(du -sh "$ROOT/dist" 2>/dev/null | awk '{print $1}')"
  fi
  if [ -d "$ROOT/flutter" ]; then
    log "size flutter: $(du -sh "$ROOT/flutter" 2>/dev/null | awk '{print $1}')"
  fi
fi

log "done"
