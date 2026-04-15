#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS security: %s\n' "$1"
}

warn() {
  printf 'WARN security: %s\n' "$1"
}

fail() {
  printf 'FAIL security: %s\n' "$1"
  STATUS=1
}

if git -C "$ROOT" ls-files | rg -q '(^|/)(dist/|.*\.dmg$|.*\.zip$|SHA256SUMS\.txt$)'; then
  fail "release artifacts are tracked in git"
else
  pass "release artifacts are not tracked in git"
fi

if git -C "$ROOT" ls-files | rg -q '(^|/)(ledger\.json|capsule_state\.json|capsules_index\.json|capsule_seeds\.json|capsule-backup.*\.json|hivra-ledger-.*\.json)$'; then
  fail "local backups or ledger exports are tracked in git"
else
  pass "local backups and ledger exports are not tracked in git"
fi

if rg -n '(BEGIN (RSA|EC|OPENSSH|PRIVATE KEY)|ghp_|github_pat_|AKIA|sk_live|pk_live|xoxb-|nsec1)' \
  "$ROOT" \
  --glob '!tools/review/**' \
  --glob '!dist/**' \
  --glob '!target/**' \
  --glob '!flutter/build/**' >/dev/null; then
  fail "secret-like tokens or private key material detected in repository content"
else
  pass "no obvious secret-like tokens detected in repository content"
fi

DART_LOG_PATTERN='(print|debugPrint)\s*\([^)]*(seed|mnemonic|secret|private\s*key|nsec|npub)'
RUST_LOG_PATTERN='eprintln!\s*\([^)]*(seed|mnemonic|secret|private\s*key|nsec|npub)'

SENSITIVE_MATCHES="$(
  {
    rg -n --pcre2 -i "$DART_LOG_PATTERN" "$ROOT/flutter/lib" "$ROOT/flutter/bin" 2>/dev/null || true
    rg -n --pcre2 -i "$RUST_LOG_PATTERN" "$ROOT/platform" "$ROOT/core" 2>/dev/null || true
  } | sed '/^$/d'
)"

if [ -n "$SENSITIVE_MATCHES" ]; then
  warn "possible sensitive logging patterns detected"
  printf '%s\n' "$SENSITIVE_MATCHES"
else
  pass "no obvious sensitive logging patterns detected"
fi

exit "$STATUS"
