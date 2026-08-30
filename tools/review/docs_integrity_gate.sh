#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import subprocess
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


def is_git_ignored(repo_path: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(root), "check-ignore", "--quiet", "--", repo_path],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


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
        if not candidate.resolve().exists() and not is_git_ignored(clean):
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

cyrillic_re = re.compile(r"[\u0400-\u052f]")
cyrillic_hits = []
tracked = subprocess.run(
    ["git", "-C", str(root), "ls-files", "-z"],
    check=True,
    capture_output=True,
).stdout.split(b"\0")
for raw_path in tracked:
    if not raw_path:
        continue
    relative = raw_path.decode("utf-8", errors="replace")
    path = root / relative
    try:
        payload = path.read_bytes()
    except OSError:
        continue
    if b"\0" in payload:
        continue
    text = payload.decode("utf-8", errors="replace")
    for line_number, line in enumerate(text.splitlines(), 1):
        if cyrillic_re.search(line):
            cyrillic_hits.append((relative, line_number, line.strip()))

if missing_links or missing_paths or stale_hits or cyrillic_hits:
    for file_path, target in missing_links:
        print(f"FAIL docs-integrity: missing markdown link in {file_path}: {target}")
    for file_path, target in missing_paths:
        print(f"FAIL docs-integrity: missing referenced repo path in {file_path}: {target}")
    for file_path, line_number, label, line in stale_hits:
        print(
            f"FAIL docs-integrity: stale term '{label}' in "
            f"{file_path}:{line_number}: {line[:180]}"
        )
    for file_path, line_number, line in cyrillic_hits:
        print(
            f"FAIL docs-integrity: Cyrillic text is forbidden in tracked files: "
            f"{file_path}:{line_number}: {line[:180]}"
        )
    sys.exit(1)

print(f"PASS docs-integrity: validated {len(md_files)} markdown files")
PY
