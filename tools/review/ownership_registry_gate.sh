#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATOR="$ROOT/tools/architecture/generate_ownership_report.py"

python3 "$GENERATOR" --self-test
python3 "$GENERATOR" --check

rg -q 'architecture/ownership-registry.v1.json' "$ROOT/docs/architecture-v2-blueprint.md"
rg -q 'generated/architecture-ownership-baseline.md' "$ROOT/docs/README.md"
printf 'PASS ownership-registry: architecture canon and navigation reference generated evidence\n'
