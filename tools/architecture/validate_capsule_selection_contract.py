#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import re
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
except ImportError as error:
    raise SystemExit("FAIL capsule-selection-contract: install jsonschema>=4.18") from error

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "architecture/contracts/capsule-selection-v2.schema.json"
FIXTURES_PATH = ROOT / "architecture/fixtures/capsule-selection-v2-vectors.json"
BIRTH_SCHEMA_PATH = ROOT / "architecture/contracts/capsule-identity-birth-v2.schema.json"
BIRTH_VALIDATOR_PATH = ROOT / "tools/architecture/validate_capsule_identity_birth_contract.py"
BLUEPRINT_PATH = ROOT / "docs/architecture-v2-blueprint.md"
REGISTRY_PATH = ROOT / "architecture/ownership-registry.v1.json"
CONTRACT_ID = "capsule_selection_contract_v2"
DESIGN_STATUS = "design-only-no-runtime"
NORMATIVE_HEADING = "#### V2-1/E Capsule Selection and Prepared Activation Contract"
EXPECTED_RUNTIME_DEBT = "production binding to capsule_selection_contract_v2 and sealing of boolean, recursive UI, direct persistence, and broad selector compatibility routes"
ERROR_CODES = {
    "INVALID_REQUEST", "INVALID_OPERATION_ID", "OPERATION_ID_CONFLICT",
    "NETWORK_SCOPE_MISMATCH", "TARGET_NOT_IN_INVENTORY",
    "INVENTORY_STATE_CHANGED", "EXPECTED_ACTIVE_STATE_CHANGED",
    "AUTHORITY_BINDING_MISMATCH", "AUTHORIZATION_COMMITMENT_MISMATCH",
    "AUTHORIZATION_INVALID", "INVENTORY_EVIDENCE_MISMATCH",
    "PLAN_EVIDENCE_MISMATCH",
}
REQUIRED_VECTORS = {
    "switch_prepared", "empty_active_prepared", "active_target_no_change",
    "exact_replay_returns_prior_plan", "operation_id_conflict_rejected",
    "invalid_operation_id_rejected", "wrong_network_rejected",
    "target_missing_rejected", "duplicate_target_rejected",
    "inventory_revision_changed_rejected", "inventory_commitment_changed_rejected",
    "expected_active_changed_rejected", "authority_binding_rejected",
    "proof_key_binding_rejected", "authorization_commitment_rejected",
    "authorization_invalid_rejected", "inventory_evidence_mismatch_rejected",
    "plan_evidence_mismatch_rejected", "raw_seed_rejected",
    "destination_path_rejected",
}


class ContractError(RuntimeError):
    pass


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ContractError(f"cannot load {name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def section(text: str, heading: str) -> str:
    lines = text.splitlines()
    matches = [index for index, line in enumerate(lines) if line == heading]
    if len(matches) != 1:
        raise ContractError(f"normative heading must occur exactly once: {heading}")
    level = len(heading) - len(heading.lstrip("#"))
    end = len(lines)
    for index in range(matches[0] + 1, len(lines)):
        match = re.match(r"^(#+)\s", lines[index])
        if match and len(match.group(1)) <= level:
            end = index
            break
    return "\n".join(lines[matches[0]:end])


def registry_for(birth_schema: dict) -> Registry:
    return Registry().with_resource(
        birth_schema["$id"], Resource.from_contents(birth_schema),
    )


def validator_for(schema: dict, birth_schema: dict, definition: str | None = None):
    target = schema if definition is None else {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": schema["$id"] + f"#{definition}",
        "$defs": schema["$defs"],
        "$ref": f"#/$defs/{definition}",
    }
    return Draft202012Validator(target, registry=registry_for(birth_schema))


def reject(code: str) -> dict:
    return {
        "decision": "REJECTED", "error_code": code,
        "core_append_required": False, "persistence_required": False,
        "activation_required": False,
    }


def descriptor_commitment(authority: dict, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/key-descriptor/v1", str(authority["version"]),
        authority["suite_id"], authority["key_id"], authority["key_bytes_hex"],
    )


def active_commitment(active: dict, birth_contract) -> str:
    if active["state"] == "NONE":
        return birth_contract.commitment("hivra/capsule-selection/active/v1", "NONE")
    return birth_contract.commitment(
        "hivra/capsule-selection/active/v1", "ACTIVE", canonical(active["capsule_id"]),
    )


def inventory_entry_commitment(entry: dict, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/capsule-selection/inventory-entry/v1",
        canonical(entry["capsule_id"]),
        descriptor_commitment(entry["root_authority"], birth_contract),
    )


def inventory_commitment(inventory: dict, birth_contract) -> str:
    entries = sorted(
        (inventory_entry_commitment(entry, birth_contract) for entry in inventory["capsules"]),
    )
    return birth_contract.commitment(
        "hivra/capsule-selection/inventory/v1", str(inventory["inventory_version"]),
        inventory["network_id"], str(inventory["inventory_revision"]),
        active_commitment(inventory["active"], birth_contract), *entries,
    )


def context_commitment(context: dict, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/capsule-selection/context/v1", str(context["context_version"]),
        context["network_id"], str(context["inventory_revision"]),
        context["inventory_commitment"],
        active_commitment(context["expected_active"], birth_contract),
        canonical(context["target_capsule_id"]),
        descriptor_commitment(context["target_root_authority"], birth_contract),
    )


def semantic_commitment(request: dict, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/capsule-selection/semantic/v1", str(request["contract_version"]),
        context_commitment(request["context"], birth_contract),
    )


def operation_id_for(semantic: str, birth_contract) -> str:
    return birth_contract.commitment("hivra/capsule-selection/operation/v1", semantic)


def authorization_commitment(semantic: str, operation_id: str, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/capsule-selection/authorization/v1", semantic, operation_id,
    )


def request_commitment(request: dict, birth_contract) -> str:
    proof = request["authorization_proof"]
    return birth_contract.commitment(
        "hivra/capsule-selection/request/v1",
        semantic_commitment(request, birth_contract), request["operation_id"],
        proof["suite_id"], proof["key_id"], proof["signed_commitment"],
    )


def transition_for(context: dict) -> str:
    active = context["expected_active"]
    if active["state"] == "ACTIVE" and active["capsule_id"] == context["target_capsule_id"]:
        return "NO_CHANGE"
    return "ACTIVATE_TARGET"


def expected_inventory_verification(request: dict, inventory: dict, birth_contract) -> dict:
    context = request["context"]
    target = next(
        entry for entry in inventory["capsules"]
        if entry["capsule_id"] == context["target_capsule_id"]
    )
    context_id = context_commitment(context, birth_contract)
    return {
        "evidence_id": birth_contract.commitment(
            "hivra/capsule-selection/inventory-evidence/v1", context_id,
            inventory_commitment(inventory, birth_contract),
            inventory_entry_commitment(target, birth_contract),
        ),
        "context_commitment": context_id,
        "inventory_commitment": inventory_commitment(inventory, birth_contract),
        "inventory_revision": inventory["inventory_revision"],
        "expected_active_commitment": active_commitment(inventory["active"], birth_contract),
        "target_entry_commitment": inventory_entry_commitment(target, birth_contract),
        "valid": True,
    }


def expected_authorization_verification(request: dict, birth_contract) -> dict:
    semantic = semantic_commitment(request, birth_contract)
    verified = authorization_commitment(semantic, request["operation_id"], birth_contract)
    authority = request["context"]["target_root_authority"]
    return {
        "evidence_id": birth_contract.commitment(
            "hivra/capsule-selection/authorization-evidence/v1", verified,
            authority["suite_id"], authority["key_id"],
        ),
        "verified_commitment": verified,
        "suite_id": authority["suite_id"],
        "key_id": authority["key_id"],
        "valid": True,
    }


def expected_command(request: dict, inventory: dict, birth_contract) -> dict:
    context = request["context"]
    inventory_evidence = expected_inventory_verification(request, inventory, birth_contract)
    authorization_evidence = expected_authorization_verification(request, birth_contract)
    return {
        "command_version": 1,
        "operation_id": request["operation_id"],
        "request_commitment": request_commitment(request, birth_contract),
        "context_commitment": context_commitment(context, birth_contract),
        "network_id": context["network_id"],
        "inventory_revision": context["inventory_revision"],
        "inventory_commitment": context["inventory_commitment"],
        "expected_active_commitment": active_commitment(context["expected_active"], birth_contract),
        "target_capsule_id": context["target_capsule_id"],
        "target_authority_commitment": descriptor_commitment(context["target_root_authority"], birth_contract),
        "transition": transition_for(context),
        "inventory_verification_evidence_id": inventory_evidence["evidence_id"],
        "authorization_evidence_id": authorization_evidence["evidence_id"],
    }


def expected_plan(request: dict, birth_contract) -> dict:
    context = request["context"]
    return {
        "plan_version": 1,
        "operation_id": request["operation_id"],
        "request_commitment": request_commitment(request, birth_contract),
        "context_commitment": context_commitment(context, birth_contract),
        "network_id": context["network_id"],
        "inventory_revision": context["inventory_revision"],
        "inventory_commitment": context["inventory_commitment"],
        "expected_active_commitment": active_commitment(context["expected_active"], birth_contract),
        "target_capsule_id": context["target_capsule_id"],
        "target_authority_commitment": descriptor_commitment(context["target_root_authority"], birth_contract),
        "transition": transition_for(context),
    }


def accepted(request: dict, birth_contract, disposition: str = "PREPARED") -> dict:
    return {
        "decision": "ACCEPTED", "disposition": disposition,
        "plan_evidence": expected_plan(request, birth_contract),
        "core_append_required": False, "persistence_claimed": False,
        "activation_claimed": False,
    }


def capsule_id(byte: str) -> dict:
    return {
        "version": 1, "scheme_id": "hivra.capsule-id.opaque.v1",
        "value_hex": byte * 32,
    }


def authority(key_id: str, byte: str) -> dict:
    return {
        "version": 1, "suite_id": "ed25519", "key_id": key_id,
        "key_bytes_hex": byte * 32,
    }


def rebind_vector(vector: dict, birth_contract) -> None:
    request = vector["request"]
    context = request["context"]
    inventory = vector["actual_inventory"]
    context["inventory_revision"] = inventory["inventory_revision"]
    context["inventory_commitment"] = inventory_commitment(inventory, birth_contract)
    semantic = semantic_commitment(request, birth_contract)
    request["operation_id"] = operation_id_for(semantic, birth_contract)
    proof = request["authorization_proof"]
    authority_value = context["target_root_authority"]
    proof["suite_id"] = authority_value["suite_id"]
    proof["key_id"] = authority_value["key_id"]
    proof["signed_commitment"] = authorization_commitment(
        semantic, request["operation_id"], birth_contract,
    )
    vector["inventory_verification"] = expected_inventory_verification(
        request, inventory, birth_contract,
    )
    vector["authorization_verification"] = expected_authorization_verification(
        request, birth_contract,
    )
    vector["verified_command"] = expected_command(request, inventory, birth_contract)


def base_vector(scenario: str, birth_contract) -> dict:
    capsule_a, capsule_b, capsule_c = capsule_id("a1"), capsule_id("b2"), capsule_id("c3")
    authority_a, authority_b, authority_c = (
        authority("root-a", "a3"), authority("root-b", "b4"), authority("root-c", "c5"),
    )
    active = {"state": "NONE"} if scenario == "empty" else {"state": "ACTIVE", "capsule_id": capsule_a}
    if scenario in {"empty", "no_change"}:
        target, target_authority = capsule_a, authority_a
    else:
        target, target_authority = capsule_b, authority_b
    inventory = {
        "inventory_version": 1, "network_id": "hivra.neste",
        "inventory_revision": 7, "active": active,
        "capsules": [
            {"capsule_id": capsule_a, "root_authority": authority_a},
            {"capsule_id": capsule_b, "root_authority": authority_b},
            {"capsule_id": capsule_c, "root_authority": authority_c},
        ],
    }
    request = {
        "contract_version": 1, "operation_id": "00" * 32,
        "context": {
            "context_version": 1, "network_id": "hivra.neste",
            "inventory_revision": inventory["inventory_revision"],
            "inventory_commitment": "00" * 32,
            "expected_active": copy.deepcopy(active),
            "target_capsule_id": copy.deepcopy(target),
            "target_root_authority": copy.deepcopy(target_authority),
        },
        "authorization_proof": {
            "version": 1, "suite_id": target_authority["suite_id"],
            "key_id": target_authority["key_id"],
            "signed_commitment": "00" * 32, "signature_bytes_hex": "ee" * 64,
        },
    }
    vector = {"request": request, "actual_inventory": inventory}
    rebind_vector(vector, birth_contract)
    return vector


def set_path(value: object, path: str, replacement: object) -> None:
    parts = path.split(".")
    current = value
    for part in parts[:-1]:
        if isinstance(current, list):
            current = current[int(part)]
        else:
            current = current[part]
    last = parts[-1]
    if isinstance(current, list):
        current[int(last)] = replacement
    else:
        current[last] = replacement


def materialize(case: dict, birth_contract) -> dict:
    vector = base_vector(case["scenario"], birth_contract)
    vector["id"] = case["id"]
    for mutation in case.get("mutations", []):
        action = mutation.get("action", "set")
        if action == "set":
            set_path(vector, mutation["path"], copy.deepcopy(mutation["value"]))
        elif action == "append":
            target = vector
            for part in mutation["path"].split("."):
                target = target[int(part)] if isinstance(target, list) else target[part]
            target.append(copy.deepcopy(mutation["value"]))
        elif action == "delete":
            target = vector
            parts = mutation["path"].split(".")
            for part in parts[:-1]:
                target = target[int(part)] if isinstance(target, list) else target[part]
            if isinstance(target, list):
                del target[int(parts[-1])]
            else:
                del target[parts[-1]]
        else:
            raise ContractError(f"vector {case['id']}: unknown mutation action {action}")
    if case.get("rebind") is True:
        rebind_vector(vector, birth_contract)
    prior_kind = case.get("prior")
    if prior_kind is not None:
        prior_request = base_vector(prior_kind, birth_contract)["request"]
        prior = {
            "operation_id": prior_request["operation_id"],
            "request_commitment": request_commitment(prior_request, birth_contract),
            "result": accepted(prior_request, birth_contract),
        }
        vector["prior_operation"] = prior
        for mutation in case.get("prior_mutations", []):
            set_path(vector["prior_operation"], mutation["path"], copy.deepcopy(mutation["value"]))
    return vector


def result_summary(result: dict) -> dict:
    if result["decision"] == "REJECTED":
        return {"decision": "REJECTED", "error_code": result["error_code"]}
    return {
        "decision": "ACCEPTED", "disposition": result["disposition"],
        "transition": result["plan_evidence"]["transition"],
    }


def evaluate(vector: dict, schema: dict, birth_schema: dict, birth_contract) -> dict:
    request = vector["request"]
    if not validator_for(schema, birth_schema, "CapsuleSelectionRequestV1").is_valid(request):
        return reject("INVALID_REQUEST")

    context = request["context"]
    inventory = vector["actual_inventory"]
    if context["network_id"] != inventory["network_id"]:
        return reject("NETWORK_SCOPE_MISMATCH")
    if context["inventory_revision"] != inventory["inventory_revision"]:
        return reject("INVENTORY_STATE_CHANGED")

    targets = [
        entry for entry in inventory["capsules"]
        if entry["capsule_id"] == context["target_capsule_id"]
    ]
    if len(targets) != 1:
        return reject("TARGET_NOT_IN_INVENTORY")
    if targets[0]["root_authority"] != context["target_root_authority"]:
        return reject("AUTHORITY_BINDING_MISMATCH")
    if inventory["active"] != context["expected_active"]:
        return reject("EXPECTED_ACTIVE_STATE_CHANGED")
    if context["inventory_commitment"] != inventory_commitment(inventory, birth_contract):
        return reject("INVENTORY_STATE_CHANGED")

    prior = vector.get("prior_operation")
    request_id = request_commitment(request, birth_contract)
    if prior is not None and prior["operation_id"] == request["operation_id"] and prior["request_commitment"] != request_id:
        return reject("OPERATION_ID_CONFLICT")

    semantic = semantic_commitment(request, birth_contract)
    expected_operation = operation_id_for(semantic, birth_contract)
    if request["operation_id"] != expected_operation:
        return reject("INVALID_OPERATION_ID")

    proof = request["authorization_proof"]
    authority = context["target_root_authority"]
    if proof["suite_id"] != authority["suite_id"] or proof["key_id"] != authority["key_id"]:
        return reject("AUTHORITY_BINDING_MISMATCH")
    expected_authorization = authorization_commitment(semantic, expected_operation, birth_contract)
    if proof["signed_commitment"] != expected_authorization:
        return reject("AUTHORIZATION_COMMITMENT_MISMATCH")
    authorization = vector.get("authorization_verification")
    if not isinstance(authorization, dict) or authorization.get("valid") is not True:
        return reject("AUTHORIZATION_INVALID")
    if authorization != expected_authorization_verification(request, birth_contract):
        return reject("AUTHORIZATION_COMMITMENT_MISMATCH")

    inventory_verification = vector.get("inventory_verification")
    if inventory_verification != expected_inventory_verification(request, inventory, birth_contract):
        return reject("INVENTORY_EVIDENCE_MISMATCH")

    if prior is not None:
        if prior["operation_id"] != request["operation_id"]:
            raise ContractError(f"vector {vector['id']}: prior operation lookup is not operation-scoped")
        if prior["result"] != accepted(request, birth_contract):
            return reject("PLAN_EVIDENCE_MISMATCH")
        return accepted(request, birth_contract, "REPLAYED")

    command = vector.get("verified_command")
    if command != expected_command(request, inventory, birth_contract):
        return reject("INVENTORY_EVIDENCE_MISMATCH")
    if not validator_for(schema, birth_schema, "VerifiedSelectionCommandV1").is_valid(command):
        return reject("INVALID_REQUEST")
    return accepted(request, birth_contract)


def validate_schema(schema: dict, birth_schema: dict) -> None:
    Draft202012Validator.check_schema(schema)
    if schema.get("x-hivra-contract-id") != CONTRACT_ID or schema.get("x-hivra-contract-version") != 1:
        raise ContractError("schema identity mismatch")
    if schema.get("x-hivra-design-status") != DESIGN_STATUS:
        raise ContractError("schema must remain design-only")
    if schema.get("x-hivra-normative-source") != "docs/architecture-v2-blueprint.md" or schema.get("x-hivra-normative-heading") != NORMATIVE_HEADING:
        raise ContractError("schema normative owner drifted")
    if validator_for(schema, birth_schema).is_valid({}):
        raise ContractError("root schema accepts empty object")
    definitions = schema["$defs"]
    expected_refs = {
        "CapsuleIdV2": "capsule-identity-birth-v2.schema.json#/$defs/CapsuleIdV2",
        "KeyDescriptorV1": "capsule-identity-birth-v2.schema.json#/$defs/KeyDescriptorV1",
        "SignatureProofV1": "capsule-identity-birth-v2.schema.json#/$defs/SignatureProofV1",
    }
    for name, ref in expected_refs.items():
        if definitions[name].get("$ref") != ref:
            raise ContractError(f"{name} must reuse the reviewed upstream contract")
    context_required = set(definitions["SelectionContextV1"]["required"])
    if {"network_id", "inventory_revision", "inventory_commitment", "expected_active", "target_capsule_id", "target_root_authority"} - context_required:
        raise ContractError("selection context lost exact semantic binding")
    request_required = set(definitions["CapsuleSelectionRequestV1"]["required"])
    if {"operation_id", "context", "authorization_proof"} - request_required:
        raise ContractError("selection request lost operation or proof binding")
    verified_text = canonical(definitions["VerifiedSelectionCommandV1"])
    if any(value in verified_text for value in ("seed", "mnemonic", "signature_bytes", "key_bytes", "path", "backup", "ledger", "storage")):
        raise ContractError("verified selection command acquired secret or foreign fields")
    result = definitions["SelectionAcceptedV1"]["properties"]
    if result["core_append_required"].get("const") is not False or result["persistence_claimed"].get("const") is not False or result["activation_claimed"].get("const") is not False:
        raise ContractError("prepared selection result acquired mutation or completion claim")
    errors = set(definitions["SelectionRejectedV1"]["properties"]["error_code"]["enum"])
    if errors != ERROR_CODES:
        raise ContractError("closed error set drifted")


def validate_blueprint(blueprint: str) -> None:
    contract = section(blueprint, NORMATIVE_HEADING)
    required = {
        f"- Contract id: `{CONTRACT_ID}`", "This section is the normative design source.",
        "There is no second selection route through a screen, recovery, import, or",
        "If the verified target already equals the expected active Capsule, the plan is",
        "A future V2-2 activation owner must atomically re-check",
        "No V2 runtime work is authorized",
    }
    missing = sorted(value for value in required if value not in contract)
    if missing:
        raise ContractError(f"normative blueprint contract incomplete: {missing}")
    if "This contract authorizes runtime implementation." in contract:
        raise ContractError("normative contract authorizes runtime implementation")


def validate_registry(registry: dict) -> None:
    capability = next(
        (item for item in registry.get("capabilities", []) if item.get("id") == "capsule_selection"),
        None,
    )
    if capability is None:
        raise ContractError("ownership registry lost capsule_selection")
    closure = capability.get("closure")
    if closure != {"verdict": "NEEDS_CONTRACT", "missing_boundaries": [EXPECTED_RUNTIME_DEBT]}:
        raise ContractError("selection registry debt must name production binding and sealed 1.x routes")


def validate_fixtures(schema: dict, birth_schema: dict, fixtures: dict, birth_contract) -> None:
    if set(fixtures) != {"schema_version", "contract_id", "design_status", "vectors"}:
        raise ContractError("fixture root shape mismatch")
    if fixtures["schema_version"] != 1 or fixtures["contract_id"] != CONTRACT_ID or fixtures["design_status"] != DESIGN_STATUS:
        raise ContractError("fixture identity mismatch")
    ids = set()
    root = validator_for(schema, birth_schema)
    for case in fixtures["vectors"]:
        vector_id = case["id"]
        if vector_id in ids:
            raise ContractError(f"duplicate vector id: {vector_id}")
        ids.add(vector_id)
        vector = materialize(case, birth_contract)
        actual = evaluate(vector, schema, birth_schema, birth_contract)
        if result_summary(actual) != case["expected"]:
            raise ContractError(f"vector {vector_id}: expected {case['expected']} got {result_summary(actual)}")
        if not root.is_valid(actual):
            error = next(root.iter_errors(actual))
            raise ContractError(f"vector {vector_id}: result fails schema: {error.message}")
    if ids != REQUIRED_VECTORS:
        raise ContractError(f"fixture coverage mismatch; missing={sorted(REQUIRED_VECTORS - ids)} extra={sorted(ids - REQUIRED_VECTORS)}")


def self_test(schema: dict, birth_schema: dict, fixtures: dict, blueprint: str, registry: dict, birth_contract) -> None:
    missing_root = copy.deepcopy(schema); missing_root.pop("oneOf")
    copied_capsule = copy.deepcopy(schema); copied_capsule["$defs"]["CapsuleIdV2"] = {"type": "object"}
    optional_proof = copy.deepcopy(schema); optional_proof["$defs"]["CapsuleSelectionRequestV1"]["required"].remove("authorization_proof")
    activation_claim = copy.deepcopy(schema); activation_claim["$defs"]["SelectionAcceptedV1"]["properties"]["activation_claimed"] = {"type": "boolean"}
    raw_seed_command = copy.deepcopy(schema); raw_seed_command["$defs"]["VerifiedSelectionCommandV1"]["properties"]["seed"] = {"type": "string"}
    missing_vector = copy.deepcopy(fixtures); missing_vector["vectors"].pop()
    changed_result = copy.deepcopy(fixtures); changed_result["vectors"][0]["expected"] = {"decision": "REJECTED", "error_code": "TARGET_NOT_IN_INVENTORY"}
    changed_proof = copy.deepcopy(fixtures)
    changed_proof["vectors"][0].setdefault("mutations", []).append({"path": "request.authorization_proof.signed_commitment", "value": "00" * 32})
    replay_drift = copy.deepcopy(fixtures)
    replay = next(case for case in replay_drift["vectors"] if case["id"] == "exact_replay_returns_prior_plan")
    replay.setdefault("prior_mutations", []).append({"path": "result.plan_evidence.inventory_commitment", "value": "00" * 32})
    no_change_drift = copy.deepcopy(fixtures)
    no_change = next(case for case in no_change_drift["vectors"] if case["id"] == "active_target_no_change")
    no_change["expected"]["transition"] = "ACTIVATE_TARGET"
    missing_section = blueprint.replace(section(blueprint, NORMATIVE_HEADING), "")
    runtime_authorized = blueprint.replace(NORMATIVE_HEADING, NORMATIVE_HEADING + "\n\nThis contract authorizes runtime implementation.")
    stale_registry = copy.deepcopy(registry)
    selection = next(item for item in stale_registry["capabilities"] if item["id"] == "capsule_selection")
    selection["closure"]["missing_boundaries"] = ["one serialized Capsule selection and activation command"]
    probes = (
        ("missing root", lambda: validate_schema(missing_root, birth_schema)),
        ("copied CapsuleId", lambda: validate_schema(copied_capsule, birth_schema)),
        ("optional proof", lambda: validate_schema(optional_proof, birth_schema)),
        ("activation claim", lambda: validate_schema(activation_claim, birth_schema)),
        ("raw seed command", lambda: validate_schema(raw_seed_command, birth_schema)),
        ("missing vector", lambda: validate_fixtures(schema, birth_schema, missing_vector, birth_contract)),
        ("semantic drift", lambda: validate_fixtures(schema, birth_schema, changed_result, birth_contract)),
        ("proof rebinding", lambda: validate_fixtures(schema, birth_schema, changed_proof, birth_contract)),
        ("replay plan drift", lambda: validate_fixtures(schema, birth_schema, replay_drift, birth_contract)),
        ("no-change effect drift", lambda: validate_fixtures(schema, birth_schema, no_change_drift, birth_contract)),
        ("missing canon", lambda: validate_blueprint(missing_section)),
        ("runtime authorization", lambda: validate_blueprint(runtime_authorized)),
        ("stale runtime debt", lambda: validate_registry(stale_registry)),
    )
    for name, probe in probes:
        try:
            probe()
        except ContractError:
            continue
        raise ContractError(f"self-test failed to reject {name}")


def main() -> int:
    try:
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        fixtures = json.loads(FIXTURES_PATH.read_text(encoding="utf-8"))
        birth_schema = json.loads(BIRTH_SCHEMA_PATH.read_text(encoding="utf-8"))
        blueprint = BLUEPRINT_PATH.read_text(encoding="utf-8")
        registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        birth_contract = load_module(BIRTH_VALIDATOR_PATH, "hivra_birth_contract")
        birth_contract.validate_schema(birth_schema)
        validate_schema(schema, birth_schema)
        validate_blueprint(blueprint)
        validate_registry(registry)
        validate_fixtures(schema, birth_schema, fixtures, birth_contract)
        self_test(schema, birth_schema, fixtures, blueprint, registry, birth_contract)
        print("PASS capsule-selection-contract: inventory, active state, authority, replay, prepared activation, and mutations")
        return 0
    except (ContractError, json.JSONDecodeError, OSError, KeyError, StopIteration, TypeError, ValueError) as error:
        print(f"FAIL capsule-selection-contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
