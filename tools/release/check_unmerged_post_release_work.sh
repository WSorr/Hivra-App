#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="$ROOT"
SELF_TEST=0

usage() {
  cat <<'USAGE'
Usage:
  tools/release/check_unmerged_post_release_work.sh [--repo <path>]
  tools/release/check_unmerged_post_release_work.sh --self-test

Fails when a local branch contains a release-bearing unique commit descended
from the latest release tag that is not patch-equivalent to current main.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

affects_release() {
  local repo="$1"
  local commit="$2"
  local path

  while IFS= read -r path; do
    case "$path" in
      adapters/*|core/*|engine/*|flutter/*|platform/*|toolchains/*|tools/release/*|tools/trading/*|Cargo.toml|Cargo.lock|rust-toolchain.toml|.github/workflows/release-gates.yml)
        return 0
        ;;
    esac
  done < <(git -C "$repo" show --pretty=format: --name-only "$commit")
  return 1
}

check_repo() {
  local repo="$1"
  local main_ref="main"
  local latest_tag
  local latest_commit
  local branch
  local sign
  local commit
  local status=0

  git -C "$repo" rev-parse --verify "$main_ref^{commit}" >/dev/null
  latest_tag="$(
    git -C "$repo" tag --merged "$main_ref" --list 'v*' \
      --sort=-version:refname | head -n1
  )"
  if [ -z "$latest_tag" ]; then
    echo "FAIL: no release tag is reachable from main" >&2
    return 1
  fi
  latest_commit="$(git -C "$repo" rev-parse "$latest_tag^{commit}")"

  while IFS= read -r branch; do
    [ "$branch" = "$main_ref" ] && continue
    while read -r sign commit; do
      [ "$sign" = '+' ] || continue
      if git -C "$repo" merge-base --is-ancestor "$latest_commit" "$commit" &&
        affects_release "$repo" "$commit";
      then
        if [ "$status" -eq 0 ]; then
          echo "FAIL: unmerged post-release work exists:" >&2
        fi
        printf '  %s %s %s\n' \
          "$branch" \
          "$(git -C "$repo" rev-parse --short "$commit")" \
          "$(git -C "$repo" show -s --format=%s "$commit")" >&2
        status=1
      fi
    done < <(git -C "$repo" cherry "$main_ref" "$branch")
  done < <(
    git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/
  )

  if [ "$status" -ne 0 ]; then
    echo "Merge or explicitly discard that release-bearing work before packaging." >&2
    return 1
  fi
  echo "PASS: no unique local post-release work is missing from main"
}

self_test() {
  local fixture
  fixture="$(mktemp -d)"
  trap "rm -rf '$fixture'" EXIT

  git -C "$fixture" init -q -b main
  git -C "$fixture" config user.name 'Hivra Gate Test'
  git -C "$fixture" config user.email 'gate@example.invalid'
  printf 'baseline\n' > "$fixture/state.txt"
  git -C "$fixture" add state.txt
  git -C "$fixture" commit -qm baseline
  git -C "$fixture" tag v1.0.0-test1

  git -C "$fixture" switch -qc product/missing-capability
  mkdir -p "$fixture/flutter/lib"
  printf 'capability\n' > "$fixture/flutter/lib/capability.dart"
  git -C "$fixture" add flutter/lib/capability.dart
  git -C "$fixture" commit -qm 'feat: retain capability'
  git -C "$fixture" switch -q main

  if check_repo "$fixture" >/dev/null 2>&1; then
    echo "FAIL: self-test accepted unique post-release branch work" >&2
    return 1
  fi

  git -C "$fixture" cherry-pick product/missing-capability >/dev/null
  if ! check_repo "$fixture" >/dev/null; then
    echo "FAIL: self-test rejected patch-equivalent merged work" >&2
    return 1
  fi

  git -C "$fixture" switch -qc research/parked-note
  mkdir -p "$fixture/docs/research"
  printf 'parked\n' > "$fixture/docs/research/note.md"
  git -C "$fixture" add docs/research/note.md
  git -C "$fixture" commit -qm 'docs: park research note'
  git -C "$fixture" switch -q main
  if ! check_repo "$fixture" >/dev/null; then
    echo "FAIL: self-test treated parked documentation as release-bearing" >&2
    return 1
  fi

  echo "PASS: unmerged post-release work gate self-test"
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
else
  check_repo "$REPO"
fi
