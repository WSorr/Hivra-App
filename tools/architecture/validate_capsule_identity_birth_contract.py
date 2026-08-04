#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError as error:
    raise SystemExit(
        "FAIL capsule-identity-birth-contract: install jsonschema>=4.18 for standard draft-2020-12 validation"
    ) from error

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "architecture/contracts/capsule-identity-birth-v2.schema.json"
VECTORS_PATH = ROOT / "architecture/fixtures/capsule-identity-birth-v2-vectors.json"
BLUEPRINT_PATH = ROOT / "docs/architecture-v2-blueprint.md"
CONTRACT_ID = "capsule_identity_birth_contract_v2"
DESIGN_STATUS = "design-only-no-runtime"
NORMATIVE_SOURCE = "docs/architecture-v2-blueprint.md"
NORMATIVE_HEADING = "#### V2-1/A Capsule Identity and Birth Contract"
REQUEST_KEYS = {
    "contract_version",
    "operation_id",
    "capsule_id",
    "network_id",
    "birth_mode",
    "root_authority",
    "authorization_proof",
}
CAPSULE_ID_KEYS = {"version", "scheme_id", "value_hex"}
KEY_DESCRIPTOR_KEYS = {"version", "suite_id", "key_id", "key_bytes_hex"}
PROOF_KEYS = {"version", "suite_id", "key_id", "signed_commitment", "signature_bytes_hex"}
VERIFICATION_KEYS = {"valid", "evidence_id", "verified_commitment"}
VECTOR_KEYS = {
    "id",
    "request",
    "request_schema_valid",
    "verification",
    "preexisting_capsule_ids",
    "prior_operations",
    "expected",
}
STARTER_KINDS = ["JUICE", "SPARK", "SEED", "PULSE", "KICK"]
ERROR_CODES = {
    "UNEXPECTED_FIELD",
    "UNSUPPORTED_CONTRACT_VERSION",
    "INVALID_OPERATION_ID",
    "INVALID_CAPSULE_ID",
    "CAPSULE_ID_KEY_ALIAS_FORBIDDEN",
    "UNSUPPORTED_NETWORK",
    "INVALID_BIRTH_MODE",
    "AUTHORITY_BINDING_MISMATCH",
    "AUTHORIZATION_COMMITMENT_MISMATCH",
    "AUTHORIZATION_INVALID",
    "CAPSULE_ALREADY_EXISTS",
}
REQUIRED_VECTORS = {
    "proto_classical_key_accepted",
    "genesis_variable_length_authority_accepted",
    "exact_operation_replay_is_idempotent",
    "same_operation_different_capsule_rejected",
    "same_operation_different_birth_mode_rejected",
    "same_operation_different_authority_rejected",
    "capsule_changed_after_proof_rejected",
    "network_changed_after_proof_rejected",
    "birth_mode_changed_after_proof_rejected",
    "operation_changed_after_proof_rejected",
    "authority_changed_after_proof_rejected",
    "runtime_role_is_not_birth_input",
    "leaf_is_not_a_birth_mode",
    "capsule_id_must_not_alias_root_key",
    "authority_binding_mismatch_rejected",
    "invalid_authorization_rejected",
    "duplicate_capsule_rejected",
    "unsupported_contract_version_rejected",
    "invalid_operation_id_rejected",
    "invalid_capsule_id_rejected",
    "unsupported_network_rejected",
}


class ContractError(RuntimeError):
    pass


def is_lower_hex_bytes(value: object, minimum_bytes: int = 16, maximum_bytes: int = 8192) -> bool:
    return (
        isinstance(value, str)
        and minimum_bytes * 2 <= len(value) <= maximum_bytes * 2
        and len(value) % 2 == 0
        and re.fullmatch(r"[0-9a-f]+", value) is not None
    )


def is_commitment32(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def encode_field(value: bytes) -> bytes:
    return len(value).to_bytes(4, "big") + value


def commitment(domain: str, *values: str) -> str:
    payload = encode_field(domain.encode("utf-8"))
    for value in values:
        payload += encode_field(value.encode("utf-8"))
    return hashlib.sha256(payload).hexdigest()


def authority_commitment(authority: dict) -> str:
    return commitment(
        "hivra/key-descriptor/commitment/v1",
        str(authority["version"]),
        authority["suite_id"],
        authority["key_id"],
        authority["key_bytes_hex"],
    )


def semantic_commitment(request: dict) -> str:
    capsule_id = request["capsule_id"]
    return commitment(
        "hivra/capsule-birth/semantic/v1",
        str(request["contract_version"]),
        str(capsule_id["version"]),
        capsule_id["scheme_id"],
        capsule_id["value_hex"],
        request["network_id"],
        request["birth_mode"],
        authority_commitment(request["root_authority"]),
    )


def operation_id_for(semantic: str) -> str:
    return commitment("hivra/capsule-birth/operation/v1", semantic)


def authorization_commitment(semantic: str, operation_id: str) -> str:
    return commitment("hivra/capsule-birth/authorization/v1", semantic, operation_id)


def reject(error_code: str) -> dict:
    return {
        "decision": "REJECTED",
        "error_code": error_code,
        "ledger_append_required": False,
        "fact": None,
        "initial_starter_kinds": [],
    }


def evaluate(vector: dict) -> dict:
    if set(vector) != VECTOR_KEYS:
        raise ContractError(f"vector {vector.get('id')}: vector shape mismatch")
    request = vector["request"]
    if not isinstance(request, dict) or set(request) != REQUEST_KEYS:
        return reject("UNEXPECTED_FIELD")
    if request["contract_version"] != 1:
        return reject("UNSUPPORTED_CONTRACT_VERSION")
    capsule_id = request["capsule_id"]
    if not isinstance(capsule_id, dict) or set(capsule_id) != CAPSULE_ID_KEYS:
        return reject("INVALID_CAPSULE_ID")
    if (
        capsule_id["version"] != 1
        or capsule_id["scheme_id"] != "hivra.capsule-id.opaque.v1"
        or not is_lower_hex_bytes(capsule_id["value_hex"])
    ):
        return reject("INVALID_CAPSULE_ID")
    if request["network_id"] != "hivra.neste":
        return reject("UNSUPPORTED_NETWORK")
    if request["birth_mode"] not in {"GENESIS", "PROTO"}:
        return reject("INVALID_BIRTH_MODE")

    authority = request["root_authority"]
    proof = request["authorization_proof"]
    if not isinstance(authority, dict) or set(authority) != KEY_DESCRIPTOR_KEYS:
        return reject("AUTHORITY_BINDING_MISMATCH")
    if not isinstance(proof, dict) or set(proof) != PROOF_KEYS:
        return reject("AUTHORITY_BINDING_MISMATCH")
    if (
        authority["version"] != 1
        or proof["version"] != 1
        or not authority["suite_id"]
        or not authority["key_id"]
        or not is_lower_hex_bytes(authority["key_bytes_hex"])
        or not is_lower_hex_bytes(proof["signature_bytes_hex"])
        or not is_commitment32(proof["signed_commitment"])
        or proof["suite_id"] != authority["suite_id"]
        or proof["key_id"] != authority["key_id"]
    ):
        return reject("AUTHORITY_BINDING_MISMATCH")
    if capsule_id["value_hex"] == authority["key_bytes_hex"]:
        return reject("CAPSULE_ID_KEY_ALIAS_FORBIDDEN")

    semantic = semantic_commitment(request)
    expected_operation_id = operation_id_for(semantic)
    if request["operation_id"] != expected_operation_id:
        return reject("INVALID_OPERATION_ID")
    expected_authorization = authorization_commitment(semantic, expected_operation_id)
    verification = vector["verification"]
    if not isinstance(verification, dict) or set(verification) != VERIFICATION_KEYS:
        raise ContractError(f"vector {vector['id']}: invalid verification evidence shape")
    if not is_commitment32(verification["evidence_id"]) or not is_commitment32(verification["verified_commitment"]):
        raise ContractError(f"vector {vector['id']}: invalid verification commitments")
    if proof["signed_commitment"] != expected_authorization or verification["verified_commitment"] != expected_authorization:
        return reject("AUTHORIZATION_COMMITMENT_MISMATCH")
    if verification["valid"] is not True:
        return reject("AUTHORIZATION_INVALID")

    prior = next(
        (item for item in vector["prior_operations"] if item["operation_id"] == expected_operation_id),
        None,
    )
    if prior is not None:
        if prior["semantic_commitment"] != semantic:
            return reject("INVALID_OPERATION_ID")
        replay = copy.deepcopy(prior["result"])
        replay["disposition"] = "REPLAYED"
        replay["ledger_append_required"] = False
        return replay
    if capsule_id["value_hex"] in vector["preexisting_capsule_ids"]:
        return reject("CAPSULE_ALREADY_EXISTS")

    authority_ref = {
        "descriptor_version": authority["version"],
        "suite_id": authority["suite_id"],
        "key_id": authority["key_id"],
        "descriptor_commitment": authority_commitment(authority),
    }
    return {
        "decision": "ACCEPTED",
        "disposition": "CREATED",
        "ledger_append_required": True,
        "fact": {
            "fact_version": 1,
            "capsule_id": capsule_id,
            "network_id": request["network_id"],
            "birth_mode": request["birth_mode"],
            "birth_operation_id": expected_operation_id,
            "birth_semantic_commitment": semantic,
            "root_authority_ref": authority_ref,
        },
        "initial_starter_kinds": STARTER_KINDS if request["birth_mode"] == "GENESIS" else [],
    }


def artifact_validator(schema: dict, definition: str | None = None) -> Draft202012Validator:
    if definition is None:
        return Draft202012Validator(schema)
    return Draft202012Validator(
        {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$defs": schema["$defs"],
            "$ref": f"#/$defs/{definition}",
        }
    )


def normative_section(blueprint: str, heading: str) -> str:
    lines = blueprint.splitlines()
    matches = [index for index, line in enumerate(lines) if line == heading]
    if len(matches) != 1:
        raise ContractError(f"normative blueprint heading must occur exactly once: {heading}")
    start = matches[0]
    heading_level = len(heading) - len(heading.lstrip("#"))
    end = len(lines)
    for index in range(start + 1, len(lines)):
        match = re.match(r"^(#+)\s", lines[index])
        if match and len(match.group(1)) <= heading_level:
            end = index
            break
    return "\n".join(lines[start:end])


def validate_blueprint_contract(schema: dict, blueprint: str) -> None:
    if schema.get("x-hivra-normative-source") != NORMATIVE_SOURCE:
        raise ContractError("schema normative source must remain the architecture V2 blueprint")
    if schema.get("x-hivra-normative-heading") != NORMATIVE_HEADING:
        raise ContractError("schema normative heading drifted")
    section = normative_section(blueprint, NORMATIVE_HEADING)
    required_statements = {
        f"- Contract id: `{CONTRACT_ID}`",
        "- Contract version: `1`",
        "- Contract boundary: design-only; no production wire format or runtime binding.",
        "This section is the normative design source.",
        "- No runtime implementation is authorized by this contract design.",
    }
    missing = sorted(statement for statement in required_statements if statement not in section)
    if missing:
        raise ContractError(f"normative blueprint contract is incomplete: {missing}")
    forbidden_authorizations = {
        "Runtime implementation is authorized by this contract design.",
        "Production implementation is authorized by this contract design.",
        "This contract authorizes runtime implementation.",
    }
    present = sorted(statement for statement in forbidden_authorizations if statement in section)
    if present:
        raise ContractError(f"normative blueprint contract authorizes runtime implementation: {present}")


def validate_schema(schema: dict) -> None:
    Draft202012Validator.check_schema(schema)
    if schema.get("x-hivra-contract-id") != CONTRACT_ID:
        raise ContractError("schema contract id mismatch")
    if schema.get("x-hivra-contract-version") != 1:
        raise ContractError("schema contract version mismatch")
    if schema.get("x-hivra-design-status") != DESIGN_STATUS:
        raise ContractError("schema must remain design-only without runtime authorization")
    root_refs = {entry.get("$ref") for entry in schema.get("oneOf", [])}
    expected_refs = {
        "#/$defs/BirthRequestV2",
        "#/$defs/VerifiedBirthCommandV2",
        "#/$defs/CapsuleBornFactV2",
        "#/$defs/BirthAcceptedV2",
        "#/$defs/BirthRejectedV2",
    }
    if root_refs != expected_refs:
        raise ContractError("root schema must validate exactly the five public artifacts")
    root_validator = artifact_validator(schema)
    if root_validator.is_valid({}):
        raise ContractError("root schema accepts an empty object")
    required_defs = {
        "CapsuleIdV2",
        "KeyDescriptorV1",
        "SignatureProofV1",
        "RootAuthorityRefV1",
        "BirthRequestV2",
        "VerifiedBirthCommandV2",
        "CapsuleBornFactV2",
        "BirthAcceptedV2",
        "BirthRejectedV2",
    }
    definitions = schema.get("$defs", {})
    if not required_defs.issubset(definitions):
        raise ContractError(f"schema missing definitions: {sorted(required_defs - set(definitions))}")
    for name in required_defs:
        if definitions[name].get("additionalProperties") is not False:
            raise ContractError(f"schema definition {name} must fail closed on unknown fields")
    request = definitions["BirthRequestV2"]
    if set(request.get("required", [])) != REQUEST_KEYS or set(request.get("properties", {})) != REQUEST_KEYS:
        raise ContractError("BirthRequestV2 fields drifted")
    proof_required = set(definitions["SignatureProofV1"].get("required", []))
    if "signed_commitment" not in proof_required:
        raise ContractError("SignatureProofV1 must bind the authorization commitment")
    verified_properties = definitions["VerifiedBirthCommandV2"]["properties"]
    if "semantic_commitment" not in verified_properties:
        raise ContractError("VerifiedBirthCommandV2 must carry the verified semantic commitment")
    if {"root_authority", "authorization_proof", "key_bytes_hex", "signature_bytes_hex"}.intersection(verified_properties):
        raise ContractError("VerifiedBirthCommandV2 must not carry raw key or proof bytes")
    if not definitions["BirthAcceptedV2"].get("allOf"):
        raise ContractError("BirthAcceptedV2 must bind replay and Starter semantics")
    error_codes = set(definitions["BirthRejectedV2"]["properties"]["error_code"].get("enum", []))
    if error_codes != ERROR_CODES:
        raise ContractError(f"BirthRejectedV2 error codes drifted: {sorted(error_codes)}")


def validate_vectors(schema: dict, fixtures: dict) -> None:
    if set(fixtures) != {"schema_version", "contract_id", "design_status", "vectors"}:
        raise ContractError("fixture root shape mismatch")
    if fixtures["schema_version"] != 1 or fixtures["contract_id"] != CONTRACT_ID:
        raise ContractError("fixture identity mismatch")
    if fixtures["design_status"] != DESIGN_STATUS:
        raise ContractError("fixtures must remain design-only")
    request_validator = artifact_validator(schema, "BirthRequestV2")
    root_validator = artifact_validator(schema)
    ids = set()
    for vector in fixtures["vectors"]:
        vector_id = vector.get("id")
        if vector_id in ids:
            raise ContractError(f"duplicate vector id: {vector_id}")
        ids.add(vector_id)
        schema_valid = request_validator.is_valid(vector.get("request"))
        if schema_valid is not vector.get("request_schema_valid"):
            raise ContractError(f"vector {vector_id}: standard request schema expectation drifted")
        actual = evaluate(vector)
        if actual != vector["expected"]:
            raise ContractError(
                f"vector {vector_id}: expected {json.dumps(vector['expected'], sort_keys=True)} "
                f"but evaluated {json.dumps(actual, sort_keys=True)}"
            )
        errors = list(root_validator.iter_errors(actual))
        if errors:
            raise ContractError(f"vector {vector_id}: result fails standard root schema: {errors[0].message}")
    if ids != REQUIRED_VECTORS:
        raise ContractError(
            f"fixture coverage mismatch; missing={sorted(REQUIRED_VECTORS - ids)} extra={sorted(ids - REQUIRED_VECTORS)}"
        )


def self_test(schema: dict, fixtures: dict, blueprint: str) -> None:
    missing_root = copy.deepcopy(schema)
    missing_root.pop("oneOf")
    weakened_proof = copy.deepcopy(schema)
    weakened_proof["$defs"]["SignatureProofV1"]["required"].remove("signed_commitment")
    missing_vector = copy.deepcopy(fixtures)
    missing_vector["vectors"].pop()
    changed_result = copy.deepcopy(fixtures)
    changed_result["vectors"][0]["expected"]["initial_starter_kinds"] = ["JUICE"]
    changed_commitment = copy.deepcopy(fixtures)
    changed_commitment["vectors"][0]["request"]["authorization_proof"]["signed_commitment"] = "00" * 32
    wrong_schema_expectation = copy.deepcopy(fixtures)
    wrong_schema_expectation["vectors"][0]["request_schema_valid"] = False
    wrong_result_type = copy.deepcopy(fixtures)
    wrong_result_type["vectors"][0]["expected"]["fact"] = "not-a-fact"
    wrong_normative_source = copy.deepcopy(schema)
    wrong_normative_source["x-hivra-normative-source"] = "docs/roadmap.md"
    missing_blueprint_section = blueprint.replace(normative_section(blueprint, NORMATIVE_HEADING), "")
    runtime_authorized_blueprint = blueprint.replace(
        "- No runtime implementation is authorized by this contract design.",
        "- No runtime implementation is authorized by this contract design.\n"
        "- Runtime implementation is authorized by this contract design.",
    )
    probes = (
        ("missing root artifact contract", lambda: validate_schema(missing_root)),
        ("proof commitment weakening", lambda: validate_schema(weakened_proof)),
        ("missing semantic vector", lambda: validate_vectors(schema, missing_vector)),
        ("semantic result drift", lambda: validate_vectors(schema, changed_result)),
        ("authorization commitment mutation", lambda: validate_vectors(schema, changed_commitment)),
        ("standard schema expectation mutation", lambda: validate_vectors(schema, wrong_schema_expectation)),
        ("wrong result type", lambda: validate_vectors(schema, wrong_result_type)),
        ("normative source drift", lambda: validate_blueprint_contract(wrong_normative_source, blueprint)),
        ("missing normative section", lambda: validate_blueprint_contract(schema, missing_blueprint_section)),
        ("runtime authorization", lambda: validate_blueprint_contract(schema, runtime_authorized_blueprint)),
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
        fixtures = json.loads(VECTORS_PATH.read_text(encoding="utf-8"))
        blueprint = BLUEPRINT_PATH.read_text(encoding="utf-8")
        validate_schema(schema)
        validate_blueprint_contract(schema, blueprint)
        validate_vectors(schema, fixtures)
        self_test(schema, fixtures, blueprint)
        print("PASS capsule-identity-birth-contract: blueprint owner, draft-2020-12 schema, vectors, and mutations")
        return 0
    except (ContractError, json.JSONDecodeError, OSError) as error:
        print(f"FAIL capsule-identity-birth-contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
