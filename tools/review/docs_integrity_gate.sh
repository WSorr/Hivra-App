#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
md_files = [root / "README.md"]
md_files += sorted((root / "docs").rglob("*.md"))
md_files += sorted((root / "tools").rglob("*.md"))

missing_links = []
link_re = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
for path in md_files:
    text = path.read_text(errors="replace")
    for match in link_re.finditer(text):
        target = match.group(1).strip()
        if not target or target.startswith(("#", "http://", "https://", "mailto:", "app://")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        candidate = Path(target) if target.startswith("/") else path.parent / target
        if not candidate.resolve().exists():
            missing_links.append((path.relative_to(root), target))

missing_paths = []
path_re = re.compile(
    r"`((?:docs|tools|flutter|core|adapters|platform|engine|README\.md|"
    r"Cargo\.toml|Cargo\.lock)[^`\s]*)`"
)
for path in md_files:
    text = path.read_text(errors="replace")
    for raw in path_re.findall(text):
        clean = raw.strip(".,:;")
        if "<" in clean or ">" in clean or "*" in clean or clean.endswith("/"):
            continue
        clean = clean.split()[0]
        candidate = root / clean
        if not candidate.resolve().exists():
            missing_paths.append((path.relative_to(root), raw))

stale_patterns = [
    (re.compile(r"\bsocial layer\b", re.I), "social layer"),
    (re.compile(r"\bsocial graph\b", re.I), "social graph"),
    (re.compile(r"\brelationship-based app\b", re.I), "relationship-based app"),
    (re.compile(r"\bAI Doctor\b", re.I), "AI Doctor"),
    (re.compile(r"\bHivra Doctor\b", re.I), "Hivra Doctor"),
    (re.compile(r"\bbingx[_ -]spot\b", re.I), "BingX spot naming"),
    (re.compile(r"v3\.2\."), "legacy v3.2 release line"),
]
stale_hits = []
for path in md_files:
    text = path.read_text(errors="replace")
    for line_number, line in enumerate(text.splitlines(), 1):
        lowered = line.lower()
        for pattern, label in stale_patterns:
            if not pattern.search(line):
                continue
            if label in {"social graph", "social layer"} and (
                "not a social" in lowered or "no public social graph" in lowered
            ):
                continue
            stale_hits.append((path.relative_to(root), line_number, label, line.strip()))

if missing_links or missing_paths or stale_hits:
    for file_path, target in missing_links:
        print(f"FAIL docs-integrity: missing markdown link in {file_path}: {target}")
    for file_path, target in missing_paths:
        print(f"FAIL docs-integrity: missing referenced repo path in {file_path}: {target}")
    for file_path, line_number, label, line in stale_hits:
        print(
            f"FAIL docs-integrity: stale term '{label}' in "
            f"{file_path}:{line_number}: {line[:180]}"
        )
    sys.exit(1)

print(f"PASS docs-integrity: validated {len(md_files)} markdown files")
PY
