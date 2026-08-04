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
DISCOVERY_CLASSIFICATIONS = {
    "CAPABILITY_OWNER",
    "REGISTERED_EVIDENCE",
    "REGISTERED_ENTRYPOINT",
    "COMPOSITION_SUPPORT",
    "SUPPORTING_COMPONENT",
    "COMPATIBILITY_DEBT",
}


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


def flutter_sources(roots: list[str]) -> list[Path]:
    sources = set()
    for root in roots:
        for path in (ROOT / root).rglob("*.dart"):
            relative = path.relative_to(ROOT).as_posix()
            if "/test/" in f"/{relative}/" or relative.endswith("_test.dart"):
                continue
            sources.add(path)
    return sorted(sources)


def discover_owners(registry: dict) -> dict:
    discovery = registry["owner_discovery"]
    require_keys(
        discovery,
        {
            "flutter_roots",
            "owner_suffixes",
            "screen_suffix",
            "classification_rules",
            "composition_builder_return_suffixes",
            "generic_locator_patterns",
            "generic_locator_allowed_paths",
            "oversized_owner_line_threshold",
        },
        "owner_discovery",
    )
    rules = []
    for rule in discovery["classification_rules"]:
        require_keys(
            rule,
            {"id", "classification", "path_pattern", "symbol_pattern", "rationale"},
            f"owner discovery rule {rule.get('id')}",
        )
        if rule["classification"] not in DISCOVERY_CLASSIFICATIONS:
            raise RegistryError(f"owner discovery rule {rule['id']}: invalid classification")
        rules.append((rule, re.compile(rule["path_pattern"]), re.compile(rule["symbol_pattern"])))

    registered: dict[tuple[str, str], str] = {}
    for capability in registry["capabilities"]:
        owner = capability["owner"]
        registered[(owner["path"], owner["symbol"])] = "CAPABILITY_OWNER"
        for key in EVIDENCE_KEYS:
            for item in capability[key]:
                registered.setdefault((item["path"], item["symbol"]), "REGISTERED_EVIDENCE")
        for item in capability["entrypoints"]:
            registered.setdefault((item["path"], item["symbol"]), "REGISTERED_ENTRYPOINT")
    surface_mappings = {}
    for mapping in registry["surface_mappings"]:
        key = (mapping.get("path"), mapping.get("symbol"))
        if key in surface_mappings:
            raise RegistryError(f"duplicate surface mapping: {key[0]}::{key[1]}")
        surface_mappings[key] = mapping

    suffixes = tuple(discovery["owner_suffixes"])
    screen_suffix = discovery["screen_suffix"]
    declaration = re.compile(r"^(?:abstract\s+(?:interface\s+)?class|class)\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.MULTILINE)
    candidates = []
    sources = flutter_sources(discovery["flutter_roots"])
    for path in sources:
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in declaration.finditer(text):
            symbol = match.group(1)
            if not symbol.endswith(suffixes) and not symbol.endswith(screen_suffix):
                continue
            key = (relative, symbol)
            classification = registered.get(key)
            rationale = "Declared by the canonical ownership registry."
            rule_id = "registry"
            mapping = surface_mappings.get(key)
            if classification is None and mapping is not None:
                classification = (
                    "REGISTERED_ENTRYPOINT"
                    if mapping.get("status") == "CANONICAL"
                    else "COMPATIBILITY_DEBT"
                )
                rationale = mapping.get("rationale", "")
                rule_id = f"surface_mapping:{mapping.get('id')}"
            if classification is None and relative in registry["composition_roots"]:
                classification = "COMPOSITION_SUPPORT"
                rationale = "Registered composition root; constructs downward capability dependencies."
                rule_id = "composition_root"
            if classification is None:
                matched_rules = [rule for rule, path_pattern, symbol_pattern in rules if path_pattern.search(relative) and symbol_pattern.fullmatch(symbol)]
                if len(matched_rules) != 1:
                    raise RegistryError(
                        f"owner candidate {relative}::{symbol}: expected one classification rule, found {len(matched_rules)}"
                    )
                rule = matched_rules[0]
                classification = rule["classification"]
                rationale = rule["rationale"]
                rule_id = rule["id"]
            candidates.append(
                {
                    "path": relative,
                    "symbol": symbol,
                    "line": text.count("\n", 0, match.start()) + 1,
                    "classification": classification,
                    "rule_id": rule_id,
                    "rationale": rationale,
                }
            )

    return_suffixes = tuple(discovery["composition_builder_return_suffixes"])
    builder_pattern = re.compile(
        r"^\s{2}([A-Za-z][A-Za-z0-9_]*)\s+(build[A-Za-z0-9_]*)\s*\(",
        re.MULTILINE,
    )
    builders = []
    for path in sources:
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in builder_pattern.finditer(text):
            return_type, symbol = match.groups()
            if not return_type.endswith(return_suffixes):
                continue
            if relative not in registry["composition_roots"]:
                raise RegistryError(
                    f"composition builder {relative}::{symbol} returns {return_type} outside a registered composition root"
                )
            builders.append(
                {
                    "path": relative,
                    "symbol": symbol,
                    "return_type": return_type,
                    "line": text.count("\n", 0, match.start()) + 1,
                }
            )

    allowed_locator_paths = set(discovery["generic_locator_allowed_paths"])
    locator_occurrences = []
    for raw_pattern in discovery["generic_locator_patterns"]:
        pattern = re.compile(raw_pattern)
        for path in sources:
            relative = path.relative_to(ROOT).as_posix()
            text = path.read_text(encoding="utf-8")
            if pattern.search(text):
                locator_occurrences.append((raw_pattern, relative))
                if relative not in allowed_locator_paths:
                    raise RegistryError(
                        f"generic service locator pattern {raw_pattern!r} escaped its allowance in {relative}"
                    )

    threshold = discovery["oversized_owner_line_threshold"]
    if not isinstance(threshold, int) or threshold < 1:
        raise RegistryError("owner_discovery: oversized_owner_line_threshold must be positive")
    candidate_paths = {candidate["path"] for candidate in candidates}
    oversized = []
    for relative in sorted(candidate_paths):
        line_count = len((ROOT / relative).read_text(encoding="utf-8").splitlines())
        if line_count >= threshold:
            oversized.append((line_count, relative))

    return {
        "candidates": sorted(candidates, key=lambda item: (item["path"], item["line"], item["symbol"])),
        "builders": sorted(builders, key=lambda item: (item["path"], item["line"], item["symbol"])),
        "locator_occurrences": sorted(set(locator_occurrences)),
        "oversized": sorted(oversized, reverse=True),
    }


def validate_surface_mappings(registry: dict, capability_ids: set[str], discovery: dict) -> None:
    policy = registry["surface_mapping_policy"]
    require_keys(
        policy,
        {"forbidden_catch_all_capability_ids", "required_bounded_capability_ids"},
        "surface_mapping_policy",
    )
    forbidden_catch_all = set(policy["forbidden_catch_all_capability_ids"])
    unknown_forbidden = forbidden_catch_all - capability_ids
    if unknown_forbidden:
        raise RegistryError(
            f"surface_mapping_policy: unknown forbidden capability ids {sorted(unknown_forbidden)}"
        )
    required_bounded = set(policy["required_bounded_capability_ids"])
    unknown_required = required_bounded - capability_ids
    if unknown_required:
        raise RegistryError(
            f"surface_mapping_policy: unknown required bounded capability ids {sorted(unknown_required)}"
        )
    mapping_ids = set()
    mapping_keys = set()
    registered_entrypoints = {
        (entrypoint["path"], entrypoint["symbol"]): (
            capability["id"],
            entrypoint["command_symbol"],
        )
        for capability in registry["capabilities"]
        for entrypoint in capability["entrypoints"]
    }
    required_keys = {"id", "kind", "path", "symbol", "capability_id", "status", "target", "rationale"}
    for mapping in registry["surface_mappings"]:
        require_keys(mapping, required_keys, f"surface mapping {mapping.get('id')}")
        if mapping["id"] in mapping_ids:
            raise RegistryError(f"duplicate surface mapping id: {mapping['id']}")
        mapping_ids.add(mapping["id"])
        key = (mapping["path"], mapping["symbol"])
        if key in mapping_keys:
            raise RegistryError(f"duplicate surface mapping: {key[0]}::{key[1]}")
        mapping_keys.add(key)
        evidence_exists(
            {"id": mapping["id"], "path": mapping["path"], "symbol": mapping["symbol"]},
            f"surface mapping {mapping['id']}",
        )
        if mapping["capability_id"] not in capability_ids:
            raise RegistryError(f"surface mapping {mapping['id']}: unknown capability {mapping['capability_id']}")
        if mapping["capability_id"] in forbidden_catch_all:
            raise RegistryError(
                f"surface mapping {mapping['id']}: broad catch-all capability {mapping['capability_id']} is forbidden"
            )
        if mapping["kind"] not in {"ui_entrypoint", "ffi_runtime_port"}:
            raise RegistryError(f"surface mapping {mapping['id']}: invalid kind")
        if mapping["status"] not in {"CANONICAL", "COMPATIBILITY_DEBT"}:
            raise RegistryError(f"surface mapping {mapping['id']}: invalid status")
        if not mapping["target"].startswith(f"{mapping['capability_id']}."):
            raise RegistryError(f"surface mapping {mapping['id']}: target must be capability-qualified")
        if not mapping["rationale"].strip():
            raise RegistryError(f"surface mapping {mapping['id']}: rationale is required")
        if mapping["kind"] == "ui_entrypoint":
            if not mapping["path"].startswith("flutter/lib/screens/") or not mapping["symbol"].endswith("Screen"):
                raise RegistryError(f"surface mapping {mapping['id']}: invalid UI surface")
            registered_entrypoint = registered_entrypoints.get(key)
            if mapping["status"] == "CANONICAL":
                if registered_entrypoint is None:
                    raise RegistryError(f"surface mapping {mapping['id']}: CANONICAL UI must be a registered capability entrypoint")
                expected_capability, expected_command = registered_entrypoint
                if mapping["capability_id"] != expected_capability:
                    raise RegistryError(f"surface mapping {mapping['id']}: canonical capability does not match its entrypoint owner")
                if mapping["target"] != f"{expected_capability}.{expected_command}":
                    raise RegistryError(f"surface mapping {mapping['id']}: canonical target does not match its registered command")
            elif registered_entrypoint is not None:
                raise RegistryError(f"surface mapping {mapping['id']}: registered entrypoint cannot be downgraded to compatibility debt")
        elif not mapping["path"].startswith("flutter/lib/ffi/") or not mapping["symbol"].endswith("Runtime"):
            raise RegistryError(f"surface mapping {mapping['id']}: invalid FFI runtime surface")
        if mapping["kind"] == "ffi_runtime_port" and mapping["status"] != "COMPATIBILITY_DEBT":
            raise RegistryError(f"surface mapping {mapping['id']}: 1.x Flutter/FFI ports remain compatibility debt")

    discovered_keys = {
        (candidate["path"], candidate["symbol"])
        for candidate in discovery["candidates"]
        if (
            candidate["path"].startswith("flutter/lib/screens/")
            and candidate["symbol"].endswith("Screen")
        )
        or (
            candidate["path"].startswith("flutter/lib/ffi/")
            and candidate["symbol"].endswith("Runtime")
        )
    }
    if mapping_keys != discovered_keys:
        raise RegistryError(
            f"surface mapping coverage mismatch; missing={sorted(discovered_keys - mapping_keys)} "
            f"extra={sorted(mapping_keys - discovered_keys)}"
        )
    mapped_capabilities = {mapping["capability_id"] for mapping in registry["surface_mappings"]}
    missing_bounded = required_bounded - mapped_capabilities
    if missing_bounded:
        raise RegistryError(
            f"surface mapping policy: bounded capabilities without surfaces {sorted(missing_bounded)}"
        )


def validate_registry(registry: dict) -> dict:
    require_keys(
        registry,
        {"schema_version", "registry_id", "packages", "composition_roots", "owner_discovery", "surface_mappings", "surface_mapping_policy", "capabilities", "concrete_bindings", "forbidden_rust_edges"},
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
    discovery = discover_owners(registry)
    validate_surface_mappings(registry, capability_ids, discovery)
    return {
        "members": members,
        "rust_edges": edges,
        "dart_edges": dart_edges(),
        "binding_results": binding_results,
        "owner_sizes": sorted(owner_sizes, reverse=True),
        "discovery": discovery,
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
        f"- Discovered owner candidates: `{len(evidence['discovery']['candidates'])}`",
        f"- Composition builders: `{len(evidence['discovery']['builders'])}`",
        f"- Explicit UI/FFI surface mappings: `{len(registry['surface_mappings'])}`",
        f"- Forbidden surface catch-all capabilities: `{len(registry['surface_mapping_policy']['forbidden_catch_all_capability_ids'])}`",
        f"- Required bounded surface capabilities: `{len(registry['surface_mapping_policy']['required_bounded_capability_ids'])}`",
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
    lines.extend(["", "## Owner Discovery", ""])
    counts = {}
    for candidate in evidence["discovery"]["candidates"]:
        counts[candidate["classification"]] = counts.get(candidate["classification"], 0) + 1
    for classification in sorted(counts):
        lines.append(f"- `{classification}`: `{counts[classification]}`")
    lines.extend(["", "### Classification Rules", ""])
    for rule in registry["owner_discovery"]["classification_rules"]:
        lines.append(
            f"- `{rule['id']}` → `{rule['classification']}` — path `{rule['path_pattern']}`, "
            f"symbol `{rule['symbol_pattern']}` — {rule['rationale']}"
        )
    lines.extend(["", "### Candidate Inventory", ""])
    for candidate in evidence["discovery"]["candidates"]:
        lines.append(
            f"- `{candidate['classification']}` — `{candidate['path']}` line `{candidate['line']}` "
            f"(`{candidate['symbol']}`) — rule `{candidate['rule_id']}`"
        )
    lines.extend(["", "### Composition Builders", ""])
    for builder in evidence["discovery"]["builders"]:
        lines.append(
            f"- `{builder['path']}` line `{builder['line']}` (`{builder['symbol']}` → `{builder['return_type']}`)"
        )
    lines.extend(["", "### Generic Service Locator Evidence", ""])
    if evidence["discovery"]["locator_occurrences"]:
        for pattern, path in evidence["discovery"]["locator_occurrences"]:
            lines.append(f"- `{pattern}` in `{path}`")
    else:
        lines.append("- No registered or unregistered generic service-locator pattern was found.")
    lines.extend(["", "### Oversized Candidate Surfaces", ""])
    for line_count, path in evidence["discovery"]["oversized"]:
        lines.append(f"- `{line_count}` lines — `{path}`")
    lines.extend(["", "## UI and Flutter/FFI Boundary Map", ""])
    lines.extend([
        "| Surface | Kind | Capability | Status | Named target | Rationale |",
        "| --- | --- | --- | --- | --- | --- |",
    ])
    for mapping in sorted(registry["surface_mappings"], key=lambda item: item["id"]):
        lines.append(
            f"| `{mapping['path']}` (`{mapping['symbol']}`) | `{mapping['kind']}` | "
            f"`{mapping['capability_id']}` | `{mapping['status']}` | `{mapping['target']}` | {mapping['rationale']} |"
        )
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
    invitation_capability = next(
        capability for capability in bypass["capabilities"]
        if capability["id"] == "invitations"
    )
    invitation_capability["entrypoints"][0]["command_symbol"] = "commandThatDoesNotExist"
    cases.append(("entrypoint bypass", bypass))
    unclassified = copy.deepcopy(registry)
    unclassified["owner_discovery"]["classification_rules"] = []
    cases.append(("unclassified owner candidate", unclassified))
    hidden_builder = copy.deepcopy(registry)
    hidden_builder["composition_roots"].remove("flutter/lib/services/app_runtime_service.dart")
    cases.append(("builder outside composition", hidden_builder))
    locator_escape = copy.deepcopy(registry)
    locator_escape["owner_discovery"]["generic_locator_patterns"] = ["class "]
    cases.append(("generic locator escape", locator_escape))
    missing_surface = copy.deepcopy(registry)
    missing_surface["surface_mappings"].pop()
    cases.append(("missing UI or FFI surface mapping", missing_surface))
    duplicate_surface = copy.deepcopy(registry)
    duplicate_surface["surface_mappings"].append(copy.deepcopy(duplicate_surface["surface_mappings"][0]))
    cases.append(("duplicate UI or FFI surface mapping", duplicate_surface))
    wrong_surface_capability = copy.deepcopy(registry)
    wrong_surface_capability["surface_mappings"][0]["capability_id"] = "unknown_capability"
    cases.append(("unknown surface capability", wrong_surface_capability))
    canonical_target_drift = copy.deepcopy(registry)
    canonical_mapping = next(
        mapping for mapping in canonical_target_drift["surface_mappings"]
        if mapping["status"] == "CANONICAL"
    )
    canonical_mapping["target"] = f"{canonical_mapping['capability_id']}.wrongCommand"
    cases.append(("canonical surface target drift", canonical_target_drift))
    catch_all_return = copy.deepcopy(registry)
    catch_all_return["surface_mappings"][0]["capability_id"] = "capsule_identity"
    catch_all_return["surface_mappings"][0]["target"] = "capsule_identity.catch_all"
    cases.append(("broad identity catch-all return", catch_all_return))
    missing_bounded_capability = copy.deepcopy(registry)
    removed_capability = "capsule_continuity"
    for mapping in missing_bounded_capability["surface_mappings"]:
        if mapping["capability_id"] == removed_capability:
            mapping["capability_id"] = "capsule_selection"
            mapping["target"] = "capsule_selection.compatibility_probe"
    cases.append(("bounded capability without surface", missing_bounded_capability))
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
