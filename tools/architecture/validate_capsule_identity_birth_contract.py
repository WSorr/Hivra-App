#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "architecture/contracts/capsule-identity-birth-v2.schema.json"
VECTORS_PATH = ROOT / "architecture/fixtures/capsule-identity-birth-v2-vectors.json"
CONTRACT_ID = "capsule_identity_birth_contract_v2"
DESIGN_STATUS = "design-complete-no-runtime"
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
PROOF_KEYS = {"version", "suite_id", "key_id", "signature_bytes_hex"}
VECTOR_KEYS = {"id", "request", "verification", "preexisting_capsule_ids", "expected"}
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
    "AUTHORIZATION_INVALID",
    "CAPSULE_ALREADY_EXISTS",
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


def reject(error_code: str) -> dict:
    return {
        "decision": "REJECTED",
        "error_code": error_code,
        "fact": None,
        "initial_starter_kinds": [],
    }


def evaluate(vector: dict) -> dict:
    if set(vector) != VECTOR_KEYS:
        raise ContractError(f"vector {vector.get('id')}: vector schema mismatch")
    request = vector["request"]
    if not isinstance(request, dict):
        return reject("UNEXPECTED_FIELD")
    if set(request) != REQUEST_KEYS:
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
    if not is_commitment32(request["operation_id"]):
        return reject("INVALID_OPERATION_ID")
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
        or proof["suite_id"] != authority["suite_id"]
        or proof["key_id"] != authority["key_id"]
    ):
        return reject("AUTHORITY_BINDING_MISMATCH")
    if capsule_id["value_hex"] == authority["key_bytes_hex"]:
        return reject("CAPSULE_ID_KEY_ALIAS_FORBIDDEN")

    verification = vector["verification"]
    if set(verification) != {"valid", "evidence_id"} or not is_commitment32(verification["evidence_id"]):
        raise ContractError(f"vector {vector['id']}: invalid verification evidence shape")
    if verification["valid"] is not True:
        return reject("AUTHORIZATION_INVALID")
    if capsule_id["value_hex"] in vector["preexisting_capsule_ids"]:
        return reject("CAPSULE_ALREADY_EXISTS")

    authority_ref = {
        "descriptor_version": authority["version"],
        "suite_id": authority["suite_id"],
        "key_id": authority["key_id"],
    }
    return {
        "decision": "ACCEPTED",
        "fact": {
            "fact_version": 1,
            "capsule_id": capsule_id,
            "network_id": request["network_id"],
            "birth_mode": request["birth_mode"],
            "birth_operation_id": request["operation_id"],
            "root_authority_ref": authority_ref,
        },
        "initial_starter_kinds": STARTER_KINDS if request["birth_mode"] == "GENESIS" else [],
    }


def validate_schema(schema: dict) -> None:
    if schema.get("x-hivra-contract-id") != CONTRACT_ID:
        raise ContractError("schema contract id mismatch")
    if schema.get("x-hivra-contract-version") != 1:
        raise ContractError("schema contract version mismatch")
    if schema.get("x-hivra-design-status") != DESIGN_STATUS:
        raise ContractError("schema must remain design-only")
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
    if request["properties"]["birth_mode"].get("enum") != ["GENESIS", "PROTO"]:
        raise ContractError("BirthRequestV2 birth modes drifted")
    if request["properties"]["network_id"].get("enum") != ["hivra.neste"]:
        raise ContractError("BirthRequestV2 network scope drifted")
    if definitions["CapsuleIdV2"]["properties"]["value_hex"].get("$ref") != "#/$defs/CapsuleIdBytes":
        raise ContractError("CapsuleIdV2 must use its bounded opaque byte shape")
    if definitions["KeyDescriptorV1"]["properties"]["key_bytes_hex"].get("$ref") != "#/$defs/LowerHexBytes":
        raise ContractError("KeyDescriptorV1 must keep variable-length key bytes")
    if definitions["SignatureProofV1"]["properties"]["signature_bytes_hex"].get("$ref") != "#/$defs/LowerHexBytes":
        raise ContractError("SignatureProofV1 must keep variable-length signature bytes")
    if not definitions["BirthAcceptedV2"].get("allOf"):
        raise ContractError("BirthAcceptedV2 must bind exact Starter plans to birth mode")
    error_codes = set(definitions["BirthRejectedV2"]["properties"]["error_code"].get("enum", []))
    if error_codes != ERROR_CODES:
        raise ContractError(f"BirthRejectedV2 error codes drifted: {sorted(error_codes)}")
    for name in ("BirthRequestV2", "VerifiedBirthCommandV2", "CapsuleBornFactV2"):
        properties = definitions[name]["properties"]
        if "runtime_role" in properties:
            raise ContractError(f"schema definition {name} must not couple runtime role to birth")
    verified_properties = definitions["VerifiedBirthCommandV2"]["properties"]
    if {"root_authority", "authorization_proof", "key_bytes_hex", "signature_bytes_hex"}.intersection(verified_properties):
        raise ContractError("VerifiedBirthCommandV2 must not carry raw key or proof bytes")


def validate_vectors(vectors: dict) -> None:
    if set(vectors) != {"schema_version", "contract_id", "design_status", "vectors"}:
        raise ContractError("fixture root schema mismatch")
    if vectors["schema_version"] != 1 or vectors["contract_id"] != CONTRACT_ID:
        raise ContractError("fixture identity mismatch")
    if vectors["design_status"] != DESIGN_STATUS:
        raise ContractError("fixtures must remain design-only")
    ids = set()
    for vector in vectors["vectors"]:
        if vector.get("id") in ids:
            raise ContractError(f"duplicate vector id: {vector.get('id')}")
        ids.add(vector.get("id"))
        actual = evaluate(vector)
        if actual != vector["expected"]:
            raise ContractError(
                f"vector {vector.get('id')}: expected {json.dumps(vector['expected'], sort_keys=True)} "
                f"but evaluated {json.dumps(actual, sort_keys=True)}"
            )
    required_vectors = {
        "proto_classical_key_accepted",
        "genesis_variable_length_authority_accepted",
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
    if ids != required_vectors:
        raise ContractError(f"fixture coverage mismatch; missing={sorted(required_vectors - ids)} extra={sorted(ids - required_vectors)}")


def self_test(schema: dict, vectors: dict) -> None:
    runtime_schema = copy.deepcopy(schema)
    runtime_schema["x-hivra-design-status"] = "production"
    missing_vector = copy.deepcopy(vectors)
    missing_vector["vectors"].pop()
    changed_result = copy.deepcopy(vectors)
    changed_result["vectors"][0]["expected"]["initial_starter_kinds"] = ["JUICE"]
    weakened_schema = copy.deepcopy(schema)
    weakened_schema["$defs"]["BirthAcceptedV2"].pop("allOf")
    probes = (
        ("runtime authorization", lambda: validate_schema(runtime_schema)),
        ("weakened Starter plan schema", lambda: validate_schema(weakened_schema)),
        ("missing vector", lambda: validate_vectors(missing_vector)),
        ("semantic result drift", lambda: validate_vectors(changed_result)),
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
        vectors = json.loads(VECTORS_PATH.read_text(encoding="utf-8"))
        validate_schema(schema)
        validate_vectors(vectors)
        self_test(schema, vectors)
        print("PASS capsule-identity-birth-contract: schema, vectors, and negative self-tests")
        return 0
    except (ContractError, json.JSONDecodeError, OSError) as error:
        print(f"FAIL capsule-identity-birth-contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
