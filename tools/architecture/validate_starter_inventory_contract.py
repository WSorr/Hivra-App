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
    raise SystemExit(
        "FAIL starter-inventory-contract: install jsonschema>=4.18 for standard draft-2020-12 validation"
    ) from error

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "architecture/contracts/starter-inventory-v2.schema.json"
FIXTURES_PATH = ROOT / "architecture/fixtures/starter-inventory-v2-vectors.json"
BIRTH_SCHEMA_PATH = ROOT / "architecture/contracts/capsule-identity-birth-v2.schema.json"
BIRTH_FIXTURES_PATH = ROOT / "architecture/fixtures/capsule-identity-birth-v2-vectors.json"
BIRTH_VALIDATOR_PATH = ROOT / "tools/architecture/validate_capsule_identity_birth_contract.py"
BLUEPRINT_PATH = ROOT / "docs/architecture-v2-blueprint.md"
CONTRACT_ID = "starter_inventory_contract_v2"
DESIGN_STATUS = "design-only-no-runtime"
NORMATIVE_SOURCE = "docs/architecture-v2-blueprint.md"
NORMATIVE_HEADING = "#### V2-1/B Starter Inventory and Genesis Seed Contract"
KINDS = ["JUICE", "SPARK", "SEED", "PULSE", "KICK"]
ERROR_CODES = {
    "INVALID_GENESIS_PLAN",
    "INVALID_STARTER_ID",
    "INVALID_STARTER_FACT",
    "CAPSULE_SCOPE_MISMATCH",
    "NETWORK_SCOPE_MISMATCH",
    "DUPLICATE_STARTER_ID",
    "SLOT_OCCUPIED",
    "STARTER_NOT_FOUND",
    "STARTER_ALREADY_BURNED",
    "NON_ATOMIC_BIRTH_BATCH",
}
REQUIRED_VECTORS = {
    "genesis_seed_plan_accepted",
    "proto_empty_plan_accepted",
    "genesis_wrong_order_rejected",
    "genesis_wrong_id_rejected",
    "genesis_capsule_scope_rejected",
    "genesis_network_scope_rejected",
    "genesis_atomic_batch_accepted",
    "genesis_partial_batch_rejected",
    "genesis_exact_replay_appends_nothing",
    "proto_atomic_birth_only_accepted",
    "genesis_inventory_view_accepted",
    "burn_frees_slot",
    "duplicate_slot_rejected",
    "burned_id_reactivation_rejected",
    "unknown_burn_reason_rejected",
    "foreign_scope_fact_rejected",
}


class ContractError(RuntimeError):
    pass


def load_birth_contract():
    spec = importlib.util.spec_from_file_location("hivra_birth_contract", BIRTH_VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise ContractError("cannot load Pass A validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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


def schema_registry(birth_schema: dict) -> Registry:
    return Registry().with_resource(birth_schema["$id"], Resource.from_contents(birth_schema))


def validator_for(schema: dict, birth_schema: dict, definition: str | None = None) -> Draft202012Validator:
    target = schema if definition is None else {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": schema["$id"] + f"#{definition}",
        "$defs": schema["$defs"],
        "$ref": f"#/$defs/{definition}",
    }
    return Draft202012Validator(target, registry=schema_registry(birth_schema))


def birth_vectors_by_id(fixtures: dict) -> dict:
    return {vector["id"]: vector for vector in fixtures["vectors"]}


def verified_birth(vector_id: str, birth_vectors: dict, birth_contract) -> dict:
    vector = birth_vectors.get(vector_id)
    if vector is None:
        raise ContractError(f"unknown Pass A vector: {vector_id}")
    result = birth_contract.evaluate(vector)
    if result.get("decision") != "ACCEPTED":
        raise ContractError(f"Pass A vector is not accepted: {vector_id}")
    request = vector["request"]
    return {
        "contract_version": request["contract_version"],
        "operation_id": request["operation_id"],
        "semantic_commitment": birth_contract.semantic_commitment(request),
        "capsule_id": request["capsule_id"],
        "network_id": request["network_id"],
        "birth_mode": request["birth_mode"],
    }


def starter_id(command: dict, slot: int, kind: str, birth_contract) -> dict:
    capsule = command["capsule_id"]
    value = birth_contract.commitment(
        "hivra/starter-id/genesis/v1",
        "1",
        str(capsule["version"]),
        capsule["scheme_id"],
        capsule["value_hex"],
        command["network_id"],
        command["semantic_commitment"],
        command["operation_id"],
        str(slot),
        kind,
    )
    return {"version": 1, "scheme_id": "hivra.starter-id.genesis.v1", "value_hex": value}


def genesis_plan(command: dict, birth_contract) -> dict:
    entries = []
    if command["birth_mode"] == "GENESIS":
        entries = [
            {"ordinal": index, "slot_index": index, "kind": kind, "starter_id": starter_id(command, index, kind, birth_contract)}
            for index, kind in enumerate(KINDS)
        ]
    return {
        "plan_version": 1,
        "birth_operation_id": command["operation_id"],
        "birth_semantic_commitment": command["semantic_commitment"],
        "capsule_id": command["capsule_id"],
        "network_id": command["network_id"],
        "entries": entries,
    }


def created_facts(command: dict, plan: dict) -> list[dict]:
    return [
        {
            "fact_version": 1,
            "starter_id": entry["starter_id"],
            "capsule_id": command["capsule_id"],
            "network_id": command["network_id"],
            "slot_index": entry["slot_index"],
            "kind": entry["kind"],
            "creation_operation_id": command["operation_id"],
        }
        for entry in plan["entries"]
    ]


def reject(error_code: str) -> dict:
    return {"decision": "REJECTED", "error_code": error_code, "ledger_append_required": False}


def validate_plan(candidate: object, command: dict, schema: dict, birth_schema: dict, birth_contract) -> dict | None:
    if not validator_for(schema, birth_schema, "GenesisSeedPlanV1").is_valid(candidate):
        return reject("INVALID_GENESIS_PLAN")
    expected = genesis_plan(command, birth_contract)
    if candidate["capsule_id"] != command["capsule_id"]:
        return reject("CAPSULE_SCOPE_MISMATCH")
    if candidate["network_id"] != command["network_id"]:
        return reject("NETWORK_SCOPE_MISMATCH")
    if candidate["birth_operation_id"] != command["operation_id"] or candidate["birth_semantic_commitment"] != command["semantic_commitment"]:
        return reject("INVALID_GENESIS_PLAN")
    if len(candidate["entries"]) != len(expected["entries"]):
        return reject("INVALID_GENESIS_PLAN")
    for actual, planned in zip(candidate["entries"], expected["entries"]):
        if actual["starter_id"] != planned["starter_id"]:
            return reject("INVALID_STARTER_ID")
        if actual != planned:
            return reject("INVALID_GENESIS_PLAN")
    return None


def validate_created_fact_batch(
    command: dict,
    plan: dict,
    facts: object,
    schema: dict,
    birth_schema: dict,
) -> dict | None:
    if not isinstance(facts, list) or len(facts) != len(plan["entries"]):
        return reject("NON_ATOMIC_BIRTH_BATCH")
    fact_validator = validator_for(schema, birth_schema, "StarterCreatedFactV2")
    expected = created_facts(command, plan)
    for actual, planned in zip(facts, expected):
        if not fact_validator.is_valid(actual):
            return reject("INVALID_STARTER_FACT")
        if actual["capsule_id"] != command["capsule_id"]:
            return reject("CAPSULE_SCOPE_MISMATCH")
        if actual["network_id"] != command["network_id"]:
            return reject("NETWORK_SCOPE_MISMATCH")
        if actual["starter_id"] != planned["starter_id"]:
            return reject("INVALID_STARTER_ID")
        if actual != planned:
            return reject("INVALID_STARTER_FACT")
    return None


def evaluate(vector: dict, schema: dict, birth_schema: dict, birth_vectors: dict, birth_contract) -> dict:
    scenario = vector["scenario"]
    command = verified_birth(vector["birth_vector_id"], birth_vectors, birth_contract)
    if scenario in {"PLAN", "ATOMIC"}:
        rejection = validate_plan(vector["candidate_plan"], command, schema, birth_schema, birth_contract)
        if rejection is not None:
            return rejection
    if scenario == "PLAN":
        return {"decision": "ACCEPTED", "plan": vector["candidate_plan"]}
    if scenario == "ATOMIC":
        facts = created_facts(command, vector["candidate_plan"])
        rejection = validate_created_fact_batch(
            command,
            vector["candidate_plan"],
            facts,
            schema,
            birth_schema,
        )
        if rejection is not None:
            return rejection
        expected_kinds = ["CapsuleBornFactV2"] + ["StarterCreatedFactV2"] * len(vector["candidate_plan"]["entries"])
        attempted = vector["candidate_append_fact_kinds"]
        if vector["prior_transaction_applied"]:
            if attempted:
                return reject("NON_ATOMIC_BIRTH_BATCH")
            return {"decision": "ACCEPTED", "disposition": "REPLAYED", "ledger_append_required": False, "append_fact_kinds": []}
        if attempted != expected_kinds:
            return reject("NON_ATOMIC_BIRTH_BATCH")
        return {"decision": "ACCEPTED", "disposition": "CREATED", "ledger_append_required": True, "append_fact_kinds": expected_kinds}
    if scenario != "PROJECTION":
        raise ContractError(f"vector {vector['id']}: unsupported scenario {scenario}")
    return project_view(vector, command, schema, birth_schema)


def project_view(vector: dict, command: dict, schema: dict, birth_schema: dict) -> dict:
    slots = [None] * 5
    active = {}
    burned = set()
    created_validator = validator_for(schema, birth_schema, "StarterCreatedFactV2")
    burned_validator = validator_for(schema, birth_schema, "StarterBurnedFactV2")
    for fact in vector["facts"]:
        is_created = created_validator.is_valid(fact)
        is_burned = burned_validator.is_valid(fact)
        if not is_created and not is_burned:
            return reject("INVALID_STARTER_FACT")
        if fact["capsule_id"] != command["capsule_id"]:
            return reject("CAPSULE_SCOPE_MISMATCH")
        if fact["network_id"] != command["network_id"]:
            return reject("NETWORK_SCOPE_MISMATCH")
        identifier = fact["starter_id"]["value_hex"]
        if is_created:
            if identifier in burned:
                return reject("STARTER_ALREADY_BURNED")
            if identifier in active:
                return reject("DUPLICATE_STARTER_ID")
            slot = fact["slot_index"]
            if slots[slot] is not None:
                return reject("SLOT_OCCUPIED")
            slots[slot] = fact
            active[identifier] = slot
        else:
            if identifier in burned:
                return reject("STARTER_ALREADY_BURNED")
            slot = active.pop(identifier, None)
            if slot is None:
                return reject("STARTER_NOT_FOUND")
            slots[slot] = None
            burned.add(identifier)
    view = {
        "view_version": 1,
        "capsule_id": command["capsule_id"],
        "network_id": command["network_id"],
        "ledger_head_commitment": vector["ledger_head_commitment"],
        "slots": [
            {"slot_index": index, "state": "EMPTY", "starter_id": None, "kind": None}
            if fact is None else
            {"slot_index": index, "state": "ACTIVE", "starter_id": fact["starter_id"], "kind": fact["kind"]}
            for index, fact in enumerate(slots)
        ],
    }
    return {"decision": "ACCEPTED", "view": view}


def validate_schema(schema: dict, birth_schema: dict) -> None:
    Draft202012Validator.check_schema(schema)
    if schema.get("x-hivra-contract-id") != CONTRACT_ID or schema.get("x-hivra-contract-version") != 1:
        raise ContractError("schema identity mismatch")
    if schema.get("x-hivra-design-status") != DESIGN_STATUS:
        raise ContractError("schema must remain design-only")
    if schema.get("x-hivra-normative-source") != NORMATIVE_SOURCE or schema.get("x-hivra-normative-heading") != NORMATIVE_HEADING:
        raise ContractError("schema normative owner drifted")
    expected_refs = {
        "#/$defs/GenesisSeedPlanV1",
        "#/$defs/StarterCreatedFactV2",
        "#/$defs/StarterBurnedFactV2",
        "#/$defs/StarterInventoryViewV1",
        "#/$defs/StarterInventoryRejectedV1",
    }
    if {item.get("$ref") for item in schema.get("oneOf", [])} != expected_refs:
        raise ContractError("root artifact contract drifted")
    if validator_for(schema, birth_schema).is_valid({}):
        raise ContractError("root schema accepts empty object")
    if schema["$defs"]["CapsuleIdV2"].get("$ref") != "capsule-identity-birth-v2.schema.json#/$defs/CapsuleIdV2":
        raise ContractError("Starter contract must reuse the Pass A CapsuleId schema")
    if schema["$defs"]["GenesisSeedEntryV1"]["properties"]["starter_id"].get("$ref") != "#/$defs/GenesisStarterIdV1":
        raise ContractError("Genesis plan must require the reviewed Genesis Starter id scheme")
    if "LOCKED" in json.dumps(schema["$defs"]):
        raise ContractError("Starter inventory must not own invitation lock state")
    error_codes = set(schema["$defs"]["StarterInventoryRejectedV1"]["properties"]["error_code"]["enum"])
    if error_codes != ERROR_CODES:
        raise ContractError("closed error set drifted")


def validate_blueprint(schema: dict, blueprint: str) -> None:
    contract = section(blueprint, NORMATIVE_HEADING)
    required = {
        f"- Contract id: `{CONTRACT_ID}`",
        "This section is the normative design source.",
        "Starter Inventory is the sole owner",
        "There is no `SeedStartersCommand`, second operation id, second birth result, or",
        "`LOCKED` is not a Starter lifecycle state.",
        "commits zero facts.",
        "No V2 runtime work is",
    }
    missing = sorted(value for value in required if value not in contract)
    if missing:
        raise ContractError(f"normative blueprint contract incomplete: {missing}")
    if "This contract authorizes runtime implementation." in contract:
        raise ContractError("normative contract authorizes runtime implementation")


def validate_fixtures(schema: dict, birth_schema: dict, fixtures: dict, birth_fixtures: dict, birth_contract) -> None:
    if set(fixtures) != {"schema_version", "contract_id", "design_status", "vectors"}:
        raise ContractError("fixture root shape mismatch")
    if fixtures["schema_version"] != 1 or fixtures["contract_id"] != CONTRACT_ID or fixtures["design_status"] != DESIGN_STATUS:
        raise ContractError("fixture identity mismatch")
    ids = set()
    birth_vectors = birth_vectors_by_id(birth_fixtures)
    root_validator = validator_for(schema, birth_schema)
    for vector in fixtures["vectors"]:
        vector_id = vector.get("id")
        if vector_id in ids:
            raise ContractError(f"duplicate vector id: {vector_id}")
        ids.add(vector_id)
        actual = evaluate(vector, schema, birth_schema, birth_vectors, birth_contract)
        if actual != vector["expected"]:
            raise ContractError(f"vector {vector_id}: expected {json.dumps(vector['expected'], sort_keys=True)} but got {json.dumps(actual, sort_keys=True)}")
        artifact = actual.get("plan") or actual.get("view") or (actual if actual.get("decision") == "REJECTED" else None)
        if artifact is not None and not root_validator.is_valid(artifact):
            error = next(root_validator.iter_errors(artifact))
            raise ContractError(f"vector {vector_id}: artifact fails standard schema: {error.message}")
    if ids != REQUIRED_VECTORS:
        raise ContractError(f"fixture coverage mismatch; missing={sorted(REQUIRED_VECTORS - ids)} extra={sorted(ids - REQUIRED_VECTORS)}")


def self_test(schema: dict, birth_schema: dict, fixtures: dict, birth_fixtures: dict, blueprint: str, birth_contract) -> None:
    missing_root = copy.deepcopy(schema)
    missing_root.pop("oneOf")
    locked_view = copy.deepcopy(schema)
    locked_view["$defs"]["ActiveStarterSlotV1"]["properties"]["state"] = {"enum": ["ACTIVE", "LOCKED"]}
    wrong_capsule_ref = copy.deepcopy(schema)
    wrong_capsule_ref["$defs"]["CapsuleIdV2"] = {"type": "object"}
    generic_genesis_id = copy.deepcopy(schema)
    generic_genesis_id["$defs"]["GenesisSeedEntryV1"]["properties"]["starter_id"] = {"$ref": "#/$defs/StarterIdV2"}
    missing_vector = copy.deepcopy(fixtures)
    missing_vector["vectors"].pop()
    changed_result = copy.deepcopy(fixtures)
    changed_result["vectors"][0]["expected"] = reject("INVALID_GENESIS_PLAN")
    missing_section = blueprint.replace(section(blueprint, NORMATIVE_HEADING), "")
    runtime_authorized = blueprint.replace(
        NORMATIVE_HEADING,
        NORMATIVE_HEADING + "\n\nThis contract authorizes runtime implementation.",
    )
    birth_vectors = birth_vectors_by_id(birth_fixtures)
    genesis_command = verified_birth(
        "genesis_variable_length_authority_accepted",
        birth_vectors,
        birth_contract,
    )
    genesis_plan_value = genesis_plan(genesis_command, birth_contract)
    wrong_scope_facts = created_facts(genesis_command, genesis_plan_value)
    wrong_scope_facts[0]["capsule_id"] = copy.deepcopy(
        birth_vectors["proto_classical_key_accepted"]["request"]["capsule_id"]
    )

    def validate_wrong_scope_fact_batch() -> None:
        rejection = validate_created_fact_batch(
            genesis_command,
            genesis_plan_value,
            wrong_scope_facts,
            schema,
            birth_schema,
        )
        if rejection == reject("CAPSULE_SCOPE_MISMATCH"):
            raise ContractError("expected rejection: foreign Capsule scope")

    probes = (
        ("missing root contract", lambda: validate_schema(missing_root, birth_schema)),
        ("invitation lock ownership", lambda: validate_schema(locked_view, birth_schema)),
        ("duplicated CapsuleId schema", lambda: validate_schema(wrong_capsule_ref, birth_schema)),
        ("generic Genesis Starter id", lambda: validate_schema(generic_genesis_id, birth_schema)),
        ("missing vector", lambda: validate_fixtures(schema, birth_schema, missing_vector, birth_fixtures, birth_contract)),
        ("semantic result drift", lambda: validate_fixtures(schema, birth_schema, changed_result, birth_fixtures, birth_contract)),
        ("missing normative section", lambda: validate_blueprint(schema, missing_section)),
        ("runtime authorization", lambda: validate_blueprint(schema, runtime_authorized)),
        ("foreign-scope atomic Starter fact", validate_wrong_scope_fact_batch),
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
        birth_fixtures = json.loads(BIRTH_FIXTURES_PATH.read_text(encoding="utf-8"))
        blueprint = BLUEPRINT_PATH.read_text(encoding="utf-8")
        birth_contract = load_birth_contract()
        birth_contract.validate_schema(birth_schema)
        birth_contract.validate_blueprint_contract(birth_schema, blueprint)
        birth_contract.validate_vectors(birth_schema, birth_fixtures)
        validate_schema(schema, birth_schema)
        validate_blueprint(schema, blueprint)
        validate_fixtures(schema, birth_schema, fixtures, birth_fixtures, birth_contract)
        self_test(schema, birth_schema, fixtures, birth_fixtures, blueprint, birth_contract)
        print("PASS starter-inventory-contract: Pass A reuse, atomic seed plan, current view, and mutations")
        return 0
    except (ContractError, json.JSONDecodeError, OSError, KeyError, TypeError) as error:
        print(f"FAIL starter-inventory-contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
