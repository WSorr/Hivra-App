#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = ROOT / "architecture/ownership-registry.v1.json"
REPORT_PATH = ROOT / "docs/generated/architecture-ownership-baseline.md"
VERDICTS = {"READY", "NEEDS_CONTRACT", "NEEDS_PROTOCOL", "REJECTED"}
EVIDENCE_KEYS = ("public_contracts", "facts", "projections", "effect_kinds")


class RegistryError(RuntimeError):
    pass


def load_registry() -> dict:
    return json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))


def require_keys(value: dict, keys: set[str], context: str) -> None:
    missing = keys - value.keys()
    extra = value.keys() - keys
    if missing or extra:
        raise RegistryError(
            f"{context}: schema mismatch; missing={sorted(missing)} extra={sorted(extra)}"
        )


def evidence_exists(item: dict, context: str) -> None:
    require_keys(item, {"id", "path", "symbol"}, context)
    path = ROOT / item["path"]
    if not path.is_file():
        raise RegistryError(f"{context}: missing path {item['path']}")
    if item["symbol"] not in path.read_text(encoding="utf-8"):
        raise RegistryError(f"{context}: missing symbol {item['symbol']} in {item['path']}")


def owner_exists(owner: dict, context: str) -> None:
    require_keys(owner, {"layer", "path", "symbol"}, context)
    path = ROOT / owner["path"]
    if not path.is_file():
        raise RegistryError(f"{context}: missing path {owner['path']}")
    if owner["symbol"] not in path.read_text(encoding="utf-8"):
        raise RegistryError(f"{context}: missing symbol {owner['symbol']} in {owner['path']}")


def cargo_metadata() -> dict:
    process = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        raise RegistryError(f"cargo metadata failed: {process.stderr.strip()}")
    return json.loads(process.stdout)


def cargo_members(metadata: dict) -> dict[str, str]:
    workspace_ids = set(metadata["workspace_members"])
    result = {}
    for package in metadata["packages"]:
        if package["id"] not in workspace_ids:
            continue
        manifest_parent = Path(package["manifest_path"]).resolve().parent
        result[package["name"]] = manifest_parent.relative_to(ROOT).as_posix()
    return result


def rust_edges(metadata: dict, members: dict[str, str]) -> list[tuple[str, str]]:
    edges = set()
    workspace_ids = set(metadata["workspace_members"])
    for package in metadata["packages"]:
        if package["id"] not in workspace_ids:
            continue
        for dependency in package["dependencies"]:
            if dependency["name"] in members:
                edges.add((package["name"], dependency["name"]))
    return sorted(edges)


def ensure_acyclic(nodes: set[str], edges: list[tuple[str, str]]) -> None:
    adjacency = {node: [] for node in nodes}
    for source, target in edges:
        adjacency[source].append(target)
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(node: str, trail: list[str]) -> None:
        if node in visiting:
            start = trail.index(node)
            raise RegistryError(f"Rust dependency cycle: {' -> '.join(trail[start:] + [node])}")
        if node in visited:
            return
        visiting.add(node)
        for target in sorted(adjacency[node]):
            visit(target, trail + [node])
        visiting.remove(node)
        visited.add(node)

    for node in sorted(nodes):
        visit(node, [])


def dart_edges() -> list[tuple[str, str]]:
    lib = ROOT / "flutter/lib"
    edges = set()
    for source in sorted(lib.rglob("*.dart")):
        source_layer = source.relative_to(lib).parts[0]
        text = source.read_text(encoding="utf-8")
        for match in re.finditer(r"^import\s+['\"]([^'\"]+)['\"]", text, re.MULTILINE):
            raw = match.group(1)
            if raw.startswith("dart:") or raw.startswith("package:"):
                continue
            target = (source.parent / raw).resolve()
            try:
                target_layer = target.relative_to(lib.resolve()).parts[0]
            except ValueError:
                continue
            if source_layer != target_layer:
                edges.add((source_layer, target_layer))
    return sorted(edges)


def validate_registry(registry: dict) -> dict:
    require_keys(
        registry,
        {"schema_version", "registry_id", "packages", "composition_roots", "capabilities", "concrete_bindings", "forbidden_rust_edges"},
        "registry",
    )
    if registry["schema_version"] != 1:
        raise RegistryError("registry: unsupported schema_version")

    metadata = cargo_metadata()
    members = cargo_members(metadata)
    expected_packages = {(name, path, "rust") for name, path in members.items()}
    expected_packages.add(("hivra-flutter", "flutter", "flutter"))
    registered_packages = set()
    package_ids = set()
    for package in registry["packages"]:
        require_keys(package, {"id", "path", "kind", "layer"}, f"package {package.get('id')}")
        if package["id"] in package_ids:
            raise RegistryError(f"duplicate package id: {package['id']}")
        package_ids.add(package["id"])
        if not (ROOT / package["path"]).is_dir():
            raise RegistryError(f"package {package['id']}: missing path {package['path']}")
        registered_packages.add((package["id"], package["path"], package["kind"]))
    if registered_packages != expected_packages:
        raise RegistryError(
            f"package inventory mismatch; missing={sorted(expected_packages - registered_packages)} "
            f"extra={sorted(registered_packages - expected_packages)}"
        )

    for path in registry["composition_roots"]:
        if not (ROOT / path).is_file():
            raise RegistryError(f"composition root missing: {path}")

    capability_ids = set()
    owner_keys = set()
    evidence_ids = set()
    owner_sizes = []
    for capability in registry["capabilities"]:
        require_keys(
            capability,
            {"id", "owner", "public_contracts", "facts", "projections", "effect_kinds", "entrypoints", "closure"},
            f"capability {capability.get('id')}",
        )
        capability_id = capability["id"]
        if capability_id in capability_ids:
            raise RegistryError(f"duplicate capability id: {capability_id}")
        capability_ids.add(capability_id)
        owner_exists(capability["owner"], f"capability {capability_id} owner")
        owner_key = (capability["owner"]["path"], capability["owner"]["symbol"])
        if owner_key in owner_keys:
            raise RegistryError(f"duplicate capability owner: {owner_key[0]}::{owner_key[1]}")
        owner_keys.add(owner_key)
        owner_sizes.append((len((ROOT / owner_key[0]).read_text(encoding="utf-8").splitlines()), capability_id, owner_key[0], owner_key[1]))
        for key in EVIDENCE_KEYS:
            for item in capability[key]:
                evidence_exists(item, f"capability {capability_id} {key}")
                qualified_id = (key, item["id"])
                if qualified_id in evidence_ids:
                    raise RegistryError(f"duplicate {key} id: {item['id']}")
                evidence_ids.add(qualified_id)
        for entrypoint in capability["entrypoints"]:
            require_keys(entrypoint, {"id", "path", "symbol", "command_path", "command_symbol"}, f"capability {capability_id} entrypoint")
            evidence_exists({key: entrypoint[key] for key in ("id", "path", "symbol")}, f"capability {capability_id} entrypoint")
            command_path = ROOT / entrypoint["command_path"]
            if not command_path.is_file() or entrypoint["command_symbol"] not in command_path.read_text(encoding="utf-8"):
                raise RegistryError(f"capability {capability_id}: missing command {entrypoint['command_symbol']}")
            if entrypoint["command_symbol"] not in (ROOT / entrypoint["path"]).read_text(encoding="utf-8"):
                raise RegistryError(f"capability {capability_id}: entrypoint {entrypoint['id']} bypasses registered command {entrypoint['command_symbol']}")
        closure = capability["closure"]
        require_keys(closure, {"verdict", "missing_boundaries"}, f"capability {capability_id} closure")
        if closure["verdict"] not in VERDICTS:
            raise RegistryError(f"capability {capability_id}: invalid closure verdict")
        if closure["verdict"] == "READY" and closure["missing_boundaries"]:
            raise RegistryError(f"capability {capability_id}: READY cannot have missing boundaries")
        if closure["verdict"] != "READY" and not closure["missing_boundaries"]:
            raise RegistryError(f"capability {capability_id}: non-READY requires missing boundaries")

    binding_results = []
    production_suffixes = {".dart", ".rs", ".kt", ".swift"}
    for binding in registry["concrete_bindings"]:
        require_keys(binding, {"id", "pattern", "search_roots", "definition_paths", "allowed_paths"}, f"binding {binding.get('id')}")
        pattern = re.compile(binding["pattern"])
        non_composition_paths = set(binding["allowed_paths"]) - set(registry["composition_roots"])
        if non_composition_paths:
            raise RegistryError(
                f"binding {binding['id']}: allowed paths are not registered composition roots: {sorted(non_composition_paths)}"
            )
        found = set()
        for root in binding["search_roots"]:
            for path in sorted((ROOT / root).rglob("*")):
                relative = path.relative_to(ROOT).as_posix()
                if not path.is_file() or path.suffix not in production_suffixes or "/test/" in f"/{relative}/" or relative.endswith("_test.dart"):
                    continue
                if relative in binding["definition_paths"]:
                    continue
                if pattern.search(path.read_text(encoding="utf-8")):
                    found.add(relative)
        unexpected = found - set(binding["allowed_paths"])
        missing = set(binding["allowed_paths"]) - found
        if unexpected or missing:
            raise RegistryError(f"binding {binding['id']}: unexpected={sorted(unexpected)} missing={sorted(missing)}")
        binding_results.append((binding["id"], sorted(found)))

    edges = rust_edges(metadata, members)
    ensure_acyclic(set(members), edges)
    forbidden = {(item["source"], item["target"]) for item in registry["forbidden_rust_edges"]}
    violations = forbidden.intersection(edges)
    if violations:
        raise RegistryError(f"forbidden Rust dependency edges: {sorted(violations)}")
    return {
        "members": members,
        "rust_edges": edges,
        "dart_edges": dart_edges(),
        "binding_results": binding_results,
        "owner_sizes": sorted(owner_sizes, reverse=True),
    }


def render_report(registry: dict, evidence: dict) -> str:
    canonical = json.dumps(registry, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    digest = hashlib.sha256(canonical).hexdigest()
    capabilities = sorted(registry["capabilities"], key=lambda item: item["id"])
    lines = [
        "# Architecture Ownership Baseline",
        "",
        "Generated by `tools/architecture/generate_ownership_report.py`; do not edit manually.",
        "",
        f"- Registry: `architecture/ownership-registry.v1.json`",
        f"- Schema: `{registry['schema_version']}`",
        f"- Canonical registry SHA-256: `{digest}`",
        f"- Packages: `{len(registry['packages'])}`",
        f"- Capabilities: `{len(capabilities)}`",
        f"- Rust dependency edges: `{len(evidence['rust_edges'])}`",
        f"- Dart layer import edges: `{len(evidence['dart_edges'])}`",
        "",
        "## Closure Verdicts",
        "",
        "| Capability | Owner | Verdict | Missing boundary |",
        "| --- | --- | --- | --- |",
    ]
    for capability in capabilities:
        owner = capability["owner"]
        missing = "; ".join(capability["closure"]["missing_boundaries"]) or "—"
        lines.append(f"| `{capability['id']}` | `{owner['path']}` (`{owner['symbol']}`) | `{capability['closure']['verdict']}` | {missing} |")
    lines.extend(["", "## Package Inventory", ""])
    for package in sorted(registry["packages"], key=lambda item: item["id"]):
        lines.append(
            f"- `{package['id']}` — `{package['path']}` — `{package['kind']}` / `{package['layer']}`"
        )
    lines.extend(["", "## Capability Evidence", ""])
    for capability in capabilities:
        lines.append(f"### `{capability['id']}`")
        for label, key in (("Contracts", "public_contracts"), ("Facts", "facts"), ("Projections", "projections"), ("Effects", "effect_kinds")):
            values = capability[key]
            rendered = ", ".join(f"`{item['path']}` (`{item['symbol']}`)" for item in values) or "—"
            lines.append(f"- {label}: {rendered}")
        entries = capability["entrypoints"]
        rendered_entries = ", ".join(f"`{item['path']}` (`{item['symbol']}`) → `{item['command_path']}` (`{item['command_symbol']}`)" for item in entries) or "—"
        lines.append(f"- Entrypoints: {rendered_entries}")
        lines.append("")
    lines.extend(["## Package Dependency Evidence", "", "### Rust", ""])
    for source, target in evidence["rust_edges"]:
        lines.append(f"- `{source}` → `{target}`")
    lines.extend(["", "### Flutter layer imports", ""])
    for source, target in evidence["dart_edges"]:
        lines.append(f"- `{source}` → `{target}`")
    lines.extend(["", "## Composition Bindings", ""])
    for binding_id, paths in evidence["binding_results"]:
        lines.append(f"- `{binding_id}`: {', '.join(f'`{path}`' for path in paths)}")
    lines.extend(["", "## Owner Surface Entropy", "", "Largest registered owner files by line count:", ""])
    for line_count, capability_id, path, symbol in evidence["owner_sizes"]:
        lines.append(f"- `{line_count}` lines — `{capability_id}` — `{path}` (`{symbol}`)")
    lines.append("")
    return "\n".join(lines)


def self_test(registry: dict) -> None:
    cases = []
    duplicate = copy.deepcopy(registry)
    duplicate["capabilities"].append(copy.deepcopy(duplicate["capabilities"][0]))
    cases.append(("duplicate capability", duplicate))
    duplicate_owner = copy.deepcopy(registry)
    copied_owner = copy.deepcopy(duplicate_owner["capabilities"][0])
    copied_owner["id"] = "duplicate_owner_probe"
    duplicate_owner["capabilities"].append(copied_owner)
    cases.append(("duplicate owner", duplicate_owner))
    missing_package = copy.deepcopy(registry)
    missing_package["packages"].pop()
    cases.append(("missing package", missing_package))
    invalid_closure = copy.deepcopy(registry)
    invalid_closure["capabilities"][0]["closure"] = {"verdict": "READY", "missing_boundaries": ["not allowed"]}
    cases.append(("invalid closure", invalid_closure))
    bypass = copy.deepcopy(registry)
    bypass["capabilities"][2]["entrypoints"][0]["command_symbol"] = "commandThatDoesNotExist"
    cases.append(("entrypoint bypass", bypass))
    for name, mutated in cases:
        try:
            validate_registry(mutated)
        except RegistryError:
            continue
        raise RegistryError(f"self-test failed to reject {name}")


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        registry = load_registry()
        if args.self_test:
            validate_registry(registry)
            self_test(registry)
            print("PASS ownership-registry: fail-closed self-test")
            return 0
        report = render_report(registry, validate_registry(registry))
        if args.write:
            REPORT_PATH.write_text(report, encoding="utf-8")
            print(f"WROTE {REPORT_PATH.relative_to(ROOT)}")
            return 0
        if not REPORT_PATH.is_file() or REPORT_PATH.read_text(encoding="utf-8") != report:
            raise RegistryError("generated report is stale; run generate_ownership_report.py --write")
        print("PASS ownership-registry: registry and generated report are current")
        return 0
    except (RegistryError, json.JSONDecodeError, OSError, ValueError) as error:
        print(f"FAIL ownership-registry: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
