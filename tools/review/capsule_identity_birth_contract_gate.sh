#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 "$ROOT/tools/architecture/validate_capsule_identity_birth_contract.py"
rg -q '^#### V2-1/A Capsule Identity and Birth Contract' "$ROOT/docs/architecture-v2-blueprint.md"
rg -q 'capsule_identity_birth_contract_v2' "$ROOT/docs/architecture-v2-blueprint.md"
rg -q 'No runtime implementation is authorized' "$ROOT/docs/architecture-v2-blueprint.md"
printf 'PASS capsule-identity-birth-contract: canonical blueprint contract remains design-only\n'
