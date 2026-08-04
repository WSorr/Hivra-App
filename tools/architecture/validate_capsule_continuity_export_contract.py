#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
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
        "FAIL capsule-continuity-export-contract: install jsonschema>=4.18"
    ) from error

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "architecture/contracts/capsule-continuity-export-v2.schema.json"
FIXTURES_PATH = ROOT / "architecture/fixtures/capsule-continuity-export-v2-vectors.json"
BIRTH_SCHEMA_PATH = ROOT / "architecture/contracts/capsule-identity-birth-v2.schema.json"
BIRTH_VALIDATOR_PATH = ROOT / "tools/architecture/validate_capsule_identity_birth_contract.py"
BLUEPRINT_PATH = ROOT / "docs/architecture-v2-blueprint.md"
CONTRACT_ID = "capsule_continuity_export_contract_v2"
DESIGN_STATUS = "design-only-no-runtime"
NORMATIVE_HEADING = "#### V2-1/C Capsule Continuity Export Contract"
PROFILE = "hivra.capsule_backup.v2"
ERROR_CODES = {
    "INVALID_REQUEST", "OPERATION_ID_CONFLICT", "CAPSULE_SCOPE_MISMATCH",
    "NETWORK_SCOPE_MISMATCH", "SNAPSHOT_STALE", "SNAPSHOT_COMMITMENT_MISMATCH",
    "AUTHORIZATION_REQUIRED", "AUTHORIZATION_SCOPE_MISMATCH",
    "PROFILE_NOT_ALLOWED", "ARTIFACT_EVIDENCE_MISMATCH",
}
REQUIRED_VECTORS = {
    "prepared_export_accepted", "exact_replay_returns_prior_evidence",
    "operation_id_conflict_rejected", "wrong_capsule_rejected",
    "wrong_network_rejected", "stale_snapshot_rejected",
    "snapshot_commitment_change_rejected", "authorization_required",
    "authorization_scope_rejected", "plaintext_profile_rejected",
    "artifact_digest_mismatch_rejected", "raw_seed_rejected",
    "destination_path_rejected",
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


def registry(birth_schema: dict) -> Registry:
    return Registry().with_resource(birth_schema["$id"], Resource.from_contents(birth_schema))


def validator_for(schema: dict, birth_schema: dict, definition: str | None = None):
    target = schema if definition is None else {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": schema["$id"] + f"#{definition}",
        "$defs": schema["$defs"],
        "$ref": f"#/$defs/{definition}",
    }
    return Draft202012Validator(target, registry=registry(birth_schema))


def snapshot_commitment(snapshot: dict, birth_contract) -> str:
    capsule = snapshot["capsule_id"]
    return birth_contract.commitment(
        "hivra/continuity-snapshot/v1", "1", str(capsule["version"]),
        capsule["scheme_id"], capsule["value_hex"], snapshot["network_id"],
        snapshot["ledger_head_commitment"], str(snapshot["ledger_event_count"]),
        snapshot["ledger_export_commitment"], snapshot["metadata_commitment"],
    )


def request_commitment(request: dict, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/continuity-export-request/v1", str(request["contract_version"]),
        request["operation_id"], snapshot_commitment(request["snapshot"], birth_contract),
        request["artifact_profile_id"],
    )


def reject(code: str) -> dict:
    return {"decision": "REJECTED", "error_code": code, "core_append_required": False, "artifact_required": False}


def expected_evidence(request: dict, artifact_hex: str, birth_contract) -> dict:
    artifact = bytes.fromhex(artifact_hex)
    return {
        "evidence_version": 1,
        "operation_id": request["operation_id"],
        "request_commitment": request_commitment(request, birth_contract),
        "snapshot_commitment": snapshot_commitment(request["snapshot"], birth_contract),
        "artifact_profile_id": PROFILE,
        "artifact_digest": {"version": 1, "suite_id": "sha256", "value_hex": hashlib.sha256(artifact).hexdigest()},
        "artifact_byte_length": len(artifact),
    }


def evaluate(vector: dict, schema: dict, birth_schema: dict, birth_contract) -> dict:
    request = vector["request"]
    request_validator = validator_for(schema, birth_schema, "ContinuityExportRequestV1")
    if not request_validator.is_valid(request):
        if isinstance(request, dict) and request.get("artifact_profile_id") != PROFILE:
            return reject("PROFILE_NOT_ALLOWED")
        return reject("INVALID_REQUEST")

    active = vector["active_snapshot"]
    if not validator_for(schema, birth_schema, "ContinuitySnapshotV1").is_valid(active):
        return reject("INVALID_REQUEST")
    requested = request["snapshot"]
    if requested["capsule_id"] != active["capsule_id"]:
        return reject("CAPSULE_SCOPE_MISMATCH")
    if requested["network_id"] != active["network_id"]:
        return reject("NETWORK_SCOPE_MISMATCH")
    if requested != active:
        return reject("SNAPSHOT_STALE")

    commitment = request_commitment(request, birth_contract)
    prior = vector.get("prior_operation")
    if prior is not None:
        if prior["request_commitment"] != commitment:
            return reject("OPERATION_ID_CONFLICT")
        if not validator_for(schema, birth_schema, "ContinuityExportResultV1").is_valid(prior["result"]):
            return reject("ARTIFACT_EVIDENCE_MISMATCH")
        if prior["result"]["artifact_evidence"] != expected_evidence(request, vector["artifact_hex"], birth_contract):
            return reject("ARTIFACT_EVIDENCE_MISMATCH")
        return {**prior["result"], "disposition": "REPLAYED"}

    command = vector.get("verified_command")
    if command is None or not validator_for(schema, birth_schema, "VerifiedContinuityExportCommandV1").is_valid(command):
        return reject("AUTHORIZATION_REQUIRED")
    if command["request"] != request or command["request_commitment"] != commitment:
        return reject("AUTHORIZATION_SCOPE_MISMATCH")
    expected_snapshot = snapshot_commitment(requested, birth_contract)
    if command["snapshot_commitment"] != expected_snapshot:
        return reject("SNAPSHOT_COMMITMENT_MISMATCH")

    evidence = vector.get("artifact_evidence")
    if evidence is None or not validator_for(schema, birth_schema, "ContinuityArtifactEvidenceV1").is_valid(evidence):
        return reject("ARTIFACT_EVIDENCE_MISMATCH")
    if evidence != expected_evidence(request, vector["artifact_hex"], birth_contract):
        return reject("ARTIFACT_EVIDENCE_MISMATCH")
    return {
        "decision": "ACCEPTED", "disposition": "PREPARED",
        "artifact_evidence": evidence, "core_append_required": False,
        "durability_claimed": False,
    }


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
    if schema["$defs"]["CapsuleIdV2"].get("$ref") != "capsule-identity-birth-v2.schema.json#/$defs/CapsuleIdV2":
        raise ContractError("continuity contract must reuse Pass A CapsuleId")
    if schema["$defs"]["ContinuityExportRequestV1"]["properties"]["artifact_profile_id"].get("const") != PROFILE:
        raise ContractError("artifact profile must remain closed to the reviewed encrypted compatibility profile")
    if schema["$defs"]["ContinuityExportResultV1"]["properties"]["durability_claimed"].get("const") is not False:
        raise ContractError("prepared continuity result must not claim downstream durability")
    if schema["$defs"]["ArtifactDigestV1"]["properties"]["value_hex"].get("pattern") != "^[0-9a-f]{64}$":
        raise ContractError("reviewed sha256 artifact evidence must remain exactly 32 bytes")
    request_text = json.dumps(schema["$defs"]["ContinuityExportRequestV1"])
    if any(field in request_text for field in ("seed", "key", "mnemonic", "path", "nonce", "salt", "ciphertext")):
        raise ContractError("continuity request acquired adapter or secret fields")
    errors = set(schema["$defs"]["ContinuityExportRejectedV1"]["properties"]["error_code"]["enum"])
    if errors != ERROR_CODES:
        raise ContractError("closed error set drifted")


def validate_blueprint(blueprint: str) -> None:
    contract = section(blueprint, NORMATIVE_HEADING)
    required = {
        f"- Contract id: `{CONTRACT_ID}`", "This section is the normative design source.",
        "Capsule Continuity owns export intent", "There is no second Ledger export route",
        "It is not a filesystem or share receipt", "No V2 runtime work is authorized",
    }
    missing = sorted(value for value in required if value not in contract)
    if missing:
        raise ContractError(f"normative blueprint contract incomplete: {missing}")
    if "This contract authorizes runtime implementation." in contract:
        raise ContractError("normative contract authorizes runtime implementation")


def validate_fixtures(schema: dict, birth_schema: dict, fixtures: dict, birth_contract) -> None:
    if set(fixtures) != {"schema_version", "contract_id", "design_status", "vectors"}:
        raise ContractError("fixture root shape mismatch")
    if fixtures["schema_version"] != 1 or fixtures["contract_id"] != CONTRACT_ID or fixtures["design_status"] != DESIGN_STATUS:
        raise ContractError("fixture identity mismatch")
    ids = set()
    root = validator_for(schema, birth_schema)
    for vector in fixtures["vectors"]:
        vector_id = vector["id"]
        if vector_id in ids:
            raise ContractError(f"duplicate vector id: {vector_id}")
        ids.add(vector_id)
        actual = evaluate(vector, schema, birth_schema, birth_contract)
        if actual != vector["expected"]:
            raise ContractError(f"vector {vector_id}: expected {vector['expected']} got {actual}")
        if not root.is_valid(actual):
            error = next(root.iter_errors(actual))
            raise ContractError(f"vector {vector_id}: result fails schema: {error.message}")
    if ids != REQUIRED_VECTORS:
        raise ContractError(f"fixture coverage mismatch; missing={sorted(REQUIRED_VECTORS - ids)} extra={sorted(ids - REQUIRED_VECTORS)}")


def self_test(schema: dict, birth_schema: dict, fixtures: dict, blueprint: str, birth_contract) -> None:
    missing_root = copy.deepcopy(schema); missing_root.pop("oneOf")
    copied_capsule = copy.deepcopy(schema); copied_capsule["$defs"]["CapsuleIdV2"] = {"type": "object"}
    plaintext = copy.deepcopy(schema); plaintext["$defs"]["ContinuityExportRequestV1"]["properties"]["artifact_profile_id"] = {"type": "string"}
    durability = copy.deepcopy(schema); durability["$defs"]["ContinuityExportResultV1"]["properties"]["durability_claimed"] = {"type": "boolean"}
    missing_vector = copy.deepcopy(fixtures); missing_vector["vectors"].pop()
    changed_result = copy.deepcopy(fixtures); changed_result["vectors"][0]["expected"] = reject("INVALID_REQUEST")
    replay_evidence_drift = copy.deepcopy(fixtures)
    replay_vector = next(vector for vector in replay_evidence_drift["vectors"] if vector["id"] == "exact_replay_returns_prior_evidence")
    replay_vector["prior_operation"]["result"]["artifact_evidence"]["artifact_digest"]["value_hex"] = "00" * 32
    malformed_active_snapshot = copy.deepcopy(fixtures)
    malformed_vector = malformed_active_snapshot["vectors"][0]
    malformed_vector["active_snapshot"]["unexpected"] = True
    missing_section = blueprint.replace(section(blueprint, NORMATIVE_HEADING), "")
    runtime_authorized = blueprint.replace(NORMATIVE_HEADING, NORMATIVE_HEADING + "\n\nThis contract authorizes runtime implementation.")
    probes = (
        ("missing root", lambda: validate_schema(missing_root, birth_schema)),
        ("copied CapsuleId", lambda: validate_schema(copied_capsule, birth_schema)),
        ("open artifact profile", lambda: validate_schema(plaintext, birth_schema)),
        ("durability claim", lambda: validate_schema(durability, birth_schema)),
        ("missing vector", lambda: validate_fixtures(schema, birth_schema, missing_vector, birth_contract)),
        ("semantic drift", lambda: validate_fixtures(schema, birth_schema, changed_result, birth_contract)),
        ("replay evidence drift", lambda: validate_fixtures(schema, birth_schema, replay_evidence_drift, birth_contract)),
        ("malformed active snapshot accepted", lambda: validate_fixtures(schema, birth_schema, malformed_active_snapshot, birth_contract)),
        ("missing canon", lambda: validate_blueprint(missing_section)),
        ("runtime authorization", lambda: validate_blueprint(runtime_authorized)),
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
        birth_contract = load_birth_contract()
        birth_contract.validate_schema(birth_schema)
        validate_schema(schema, birth_schema)
        validate_blueprint(blueprint)
        validate_fixtures(schema, birth_schema, fixtures, birth_contract)
        self_test(schema, birth_schema, fixtures, blueprint, birth_contract)
        print("PASS capsule-continuity-export-contract: snapshot, authority, replay, profile, evidence, and mutations")
        return 0
    except (ContractError, json.JSONDecodeError, OSError, KeyError, TypeError, ValueError) as error:
        print(f"FAIL capsule-continuity-export-contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
