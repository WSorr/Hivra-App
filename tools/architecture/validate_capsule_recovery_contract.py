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
    raise SystemExit("FAIL capsule-recovery-contract: install jsonschema>=4.18") from error

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "architecture/contracts/capsule-recovery-v2.schema.json"
FIXTURES_PATH = ROOT / "architecture/fixtures/capsule-recovery-v2-vectors.json"
BIRTH_SCHEMA_PATH = ROOT / "architecture/contracts/capsule-identity-birth-v2.schema.json"
CONTINUITY_SCHEMA_PATH = ROOT / "architecture/contracts/capsule-continuity-export-v2.schema.json"
BIRTH_VALIDATOR_PATH = ROOT / "tools/architecture/validate_capsule_identity_birth_contract.py"
CONTINUITY_VALIDATOR_PATH = ROOT / "tools/architecture/validate_capsule_continuity_export_contract.py"
BLUEPRINT_PATH = ROOT / "docs/architecture-v2-blueprint.md"
CONTRACT_ID = "capsule_recovery_protocol_v2"
DESIGN_STATUS = "design-only-no-runtime"
NORMATIVE_HEADING = "#### V2-1/D Capsule Recovery Authorization and History Anchoring Protocol"
PROFILE = "hivra.capsule_backup.v2"
ERROR_CODES = {
    "INVALID_REQUEST", "INVALID_OPERATION_ID", "OPERATION_ID_CONFLICT",
    "CAPSULE_SCOPE_MISMATCH", "NETWORK_SCOPE_MISMATCH",
    "ARTIFACT_AUTHENTICATION_FAILED", "ARTIFACT_EVIDENCE_MISMATCH",
    "AUTHORITY_BINDING_MISMATCH", "AUTHORIZATION_COMMITMENT_MISMATCH",
    "AUTHORIZATION_INVALID", "HISTORY_SCOPE_MISMATCH", "HISTORY_ROLLBACK",
    "HISTORY_FORK", "BASE_STATE_CHANGED", "PLAN_EVIDENCE_MISMATCH",
}
REQUIRED_VECTORS = {
    "empty_base_prepared", "exact_history_prepared", "descendant_history_prepared",
    "exact_replay_returns_prior_plan", "operation_id_conflict_rejected",
    "invalid_operation_id_rejected",
    "wrong_capsule_rejected", "wrong_network_rejected",
    "artifact_authentication_rejected", "artifact_evidence_mismatch_rejected",
    "authority_binding_rejected", "authorization_commitment_rejected",
    "authorization_invalid_rejected", "history_rollback_rejected",
    "history_fork_rejected", "history_evidence_mismatch_rejected",
    "base_state_changed_rejected",
    "seed_only_recovery_rejected", "raw_seed_rejected", "destination_path_rejected",
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


def registry_for(birth_schema: dict, continuity_schema: dict) -> Registry:
    return (
        Registry()
        .with_resource(birth_schema["$id"], Resource.from_contents(birth_schema))
        .with_resource(continuity_schema["$id"], Resource.from_contents(continuity_schema))
    )


def validator_for(schema: dict, birth_schema: dict, continuity_schema: dict, definition: str | None = None):
    target = schema if definition is None else {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": schema["$id"] + f"#{definition}",
        "$defs": schema["$defs"],
        "$ref": f"#/$defs/{definition}",
    }
    return Draft202012Validator(target, registry=registry_for(birth_schema, continuity_schema))


def reject(code: str) -> dict:
    return {
        "decision": "REJECTED", "error_code": code,
        "core_append_required": False, "persistence_required": False,
        "activation_required": False,
    }


def descriptor_commitment(authority: dict, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/key-descriptor/v1", str(authority["version"]), authority["suite_id"],
        authority["key_id"], authority["key_bytes_hex"],
    )


def history_snapshot(history: dict, birth_contract) -> dict:
    events = history["events"]
    if not events:
        raise ContractError("history fixture must contain at least one event")
    authority = history["root_authority"]
    capsule = history["capsule_id"]
    network = history["network_id"]
    return {
        "snapshot_version": 1,
        "capsule_id": capsule,
        "network_id": network,
        "ledger_head_commitment": events[-1],
        "ledger_event_count": len(events),
        "ledger_export_commitment": birth_contract.commitment(
            "hivra/ledger-export/v1", *events,
        ),
        "metadata_commitment": birth_contract.commitment(
            "hivra/recovery-metadata/v1", canonical(capsule), network,
            descriptor_commitment(authority, birth_contract),
        ),
    }


def snapshot_commitment(snapshot: dict, continuity_contract, birth_contract) -> str:
    return continuity_contract.snapshot_commitment(snapshot, birth_contract)


def artifact_commitment(evidence: dict, birth_contract) -> str:
    return birth_contract.commitment("hivra/recovery-artifact-evidence/v1", canonical(evidence))


def local_state_commitment(state: dict, continuity_contract, birth_contract) -> str:
    if state["state"] == "EMPTY":
        return birth_contract.commitment("hivra/recovery-local-state/v1", "EMPTY")
    return birth_contract.commitment(
        "hivra/recovery-local-state/v1", "PRESENT",
        snapshot_commitment(state["snapshot"], continuity_contract, birth_contract),
    )


def semantic_commitment(request: dict, continuity_contract, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/capsule-recovery/semantic/v1", str(request["contract_version"]),
        canonical(request["capsule_id"]), request["network_id"],
        artifact_commitment(request["artifact_evidence"], birth_contract),
        snapshot_commitment(request["candidate_snapshot"], continuity_contract, birth_contract),
        local_state_commitment(request["expected_local_state"], continuity_contract, birth_contract),
        descriptor_commitment(request["root_authority"], birth_contract),
    )


def operation_id_for(semantic: str, birth_contract) -> str:
    return birth_contract.commitment("hivra/capsule-recovery/operation/v1", semantic)


def authorization_commitment(semantic: str, operation_id: str, birth_contract) -> str:
    return birth_contract.commitment(
        "hivra/capsule-recovery/authorization/v1", semantic, operation_id,
    )


def request_commitment(request: dict, continuity_contract, birth_contract) -> str:
    semantic = semantic_commitment(request, continuity_contract, birth_contract)
    return birth_contract.commitment(
        "hivra/capsule-recovery/request/v1", semantic, request["operation_id"],
    )


def expected_local_state(history: dict | None, birth_contract) -> dict:
    if history is None:
        return {"state": "EMPTY"}
    return {"state": "PRESENT", "snapshot": history_snapshot(history, birth_contract)}


def history_relation(candidate: dict, current: dict | None) -> str:
    if current is None:
        return "EMPTY_BASE"
    candidate_events = candidate["events"]
    current_events = current["events"]
    if candidate_events == current_events:
        return "EXACT"
    if len(candidate_events) > len(current_events) and candidate_events[:len(current_events)] == current_events:
        return "DESCENDANT"
    if len(candidate_events) < len(current_events) and current_events[:len(candidate_events)] == candidate_events:
        return "ROLLBACK"
    return "FORK"


def expected_artifact_verification(request: dict, artifact_hex: str, continuity_contract, birth_contract) -> dict:
    artifact = bytes.fromhex(artifact_hex)
    evidence_commitment = artifact_commitment(request["artifact_evidence"], birth_contract)
    return {
        "evidence_id": birth_contract.commitment(
            "hivra/recovery/artifact-verification-evidence/v1",
            hashlib.sha256(artifact).hexdigest(), str(len(artifact)),
            snapshot_commitment(request["candidate_snapshot"], continuity_contract, birth_contract),
            evidence_commitment,
        ),
        "artifact_profile_id": PROFILE,
        "artifact_digest": {"version": 1, "suite_id": "sha256", "value_hex": hashlib.sha256(artifact).hexdigest()},
        "artifact_byte_length": len(artifact),
        "snapshot_commitment": snapshot_commitment(request["candidate_snapshot"], continuity_contract, birth_contract),
        "artifact_evidence_commitment": evidence_commitment,
        "valid": True,
    }


def expected_authorization_verification(request: dict, continuity_contract, birth_contract) -> dict:
    semantic = semantic_commitment(request, continuity_contract, birth_contract)
    verified = authorization_commitment(semantic, request["operation_id"], birth_contract)
    return {
        "evidence_id": birth_contract.commitment(
            "hivra/recovery/authorization-evidence/v1", verified,
            request["root_authority"]["suite_id"], request["root_authority"]["key_id"],
        ),
        "verified_commitment": verified,
        "suite_id": request["root_authority"]["suite_id"],
        "key_id": request["root_authority"]["key_id"],
        "valid": True,
    }


def expected_history_verification(request: dict, relation: str, continuity_contract, birth_contract) -> dict:
    candidate = snapshot_commitment(request["candidate_snapshot"], continuity_contract, birth_contract)
    local = local_state_commitment(request["expected_local_state"], continuity_contract, birth_contract)
    return {
        "evidence_id": birth_contract.commitment(
            "hivra/recovery/history-evidence/v1", candidate, local, relation,
        ),
        "candidate_snapshot_commitment": candidate,
        "local_state_commitment": local,
        "relation": relation,
        "valid": True,
    }


def expected_command(request: dict, vector: dict, relation: str, continuity_contract, birth_contract) -> dict:
    artifact = expected_artifact_verification(request, vector["artifact_hex"], continuity_contract, birth_contract)
    authorization = expected_authorization_verification(request, continuity_contract, birth_contract)
    history = expected_history_verification(request, relation, continuity_contract, birth_contract)
    return {
        "command_version": 1,
        "operation_id": request["operation_id"],
        "request_commitment": request_commitment(request, continuity_contract, birth_contract),
        "capsule_id": request["capsule_id"],
        "network_id": request["network_id"],
        "artifact_evidence_commitment": artifact_commitment(request["artifact_evidence"], birth_contract),
        "candidate_snapshot_commitment": history["candidate_snapshot_commitment"],
        "local_state_commitment": history["local_state_commitment"],
        "history_relation": relation,
        "artifact_verification_evidence_id": artifact["evidence_id"],
        "authorization_evidence_id": authorization["evidence_id"],
        "history_verification_evidence_id": history["evidence_id"],
    }


def expected_plan(request: dict, relation: str, continuity_contract, birth_contract) -> dict:
    return {
        "plan_version": 1,
        "operation_id": request["operation_id"],
        "request_commitment": request_commitment(request, continuity_contract, birth_contract),
        "capsule_id": request["capsule_id"],
        "network_id": request["network_id"],
        "artifact_evidence_commitment": artifact_commitment(request["artifact_evidence"], birth_contract),
        "candidate_snapshot_commitment": snapshot_commitment(request["candidate_snapshot"], continuity_contract, birth_contract),
        "local_state_commitment": local_state_commitment(request["expected_local_state"], continuity_contract, birth_contract),
        "history_relation": relation,
    }


def accepted(request: dict, relation: str, continuity_contract, birth_contract, disposition: str = "PREPARED") -> dict:
    return {
        "decision": "ACCEPTED", "disposition": disposition,
        "plan_evidence": expected_plan(request, relation, continuity_contract, birth_contract),
        "core_append_required": False, "durability_claimed": False,
        "activation_claimed": False,
    }


def evaluate(vector: dict, schema: dict, birth_schema: dict, continuity_schema: dict, birth_contract, continuity_contract) -> dict:
    request = vector["request"]
    if not validator_for(schema, birth_schema, continuity_schema, "RecoveryRequestV1").is_valid(request):
        return reject("INVALID_REQUEST")

    candidate_snapshot = request["candidate_snapshot"]
    if request["capsule_id"] != candidate_snapshot["capsule_id"]:
        return reject("CAPSULE_SCOPE_MISMATCH")
    if request["network_id"] != candidate_snapshot["network_id"]:
        return reject("NETWORK_SCOPE_MISMATCH")

    candidate_history = vector["candidate_history"]
    if candidate_history["capsule_id"] != request["capsule_id"] or candidate_history["network_id"] != request["network_id"]:
        return reject("HISTORY_SCOPE_MISMATCH")
    if history_snapshot(candidate_history, birth_contract) != candidate_snapshot:
        return reject("HISTORY_SCOPE_MISMATCH")
    if candidate_history["root_authority"] != request["root_authority"]:
        return reject("AUTHORITY_BINDING_MISMATCH")

    expected_artifact = expected_artifact_verification(request, vector["artifact_hex"], continuity_contract, birth_contract)
    artifact_verification = vector.get("artifact_verification")
    if not isinstance(artifact_verification, dict) or artifact_verification.get("valid") is not True:
        return reject("ARTIFACT_AUTHENTICATION_FAILED")
    if artifact_verification != expected_artifact:
        return reject("ARTIFACT_EVIDENCE_MISMATCH")
    artifact_evidence = request["artifact_evidence"]
    if (
        artifact_evidence["artifact_profile_id"] != expected_artifact["artifact_profile_id"]
        or artifact_evidence["artifact_digest"] != expected_artifact["artifact_digest"]
        or artifact_evidence["artifact_byte_length"] != expected_artifact["artifact_byte_length"]
        or artifact_evidence["snapshot_commitment"] != expected_artifact["snapshot_commitment"]
    ):
        return reject("ARTIFACT_EVIDENCE_MISMATCH")

    semantic = semantic_commitment(request, continuity_contract, birth_contract)
    expected_operation = operation_id_for(semantic, birth_contract)
    if request["operation_id"] != expected_operation:
        return reject("INVALID_OPERATION_ID")
    proof = request["authorization_proof"]
    authority = request["root_authority"]
    if proof["suite_id"] != authority["suite_id"] or proof["key_id"] != authority["key_id"]:
        return reject("AUTHORITY_BINDING_MISMATCH")
    expected_authorization = authorization_commitment(semantic, expected_operation, birth_contract)
    if proof["signed_commitment"] != expected_authorization:
        return reject("AUTHORIZATION_COMMITMENT_MISMATCH")
    authorization_verification = vector.get("authorization_verification")
    if not isinstance(authorization_verification, dict) or authorization_verification.get("valid") is not True:
        return reject("AUTHORIZATION_INVALID")
    if authorization_verification != expected_authorization_verification(request, continuity_contract, birth_contract):
        return reject("AUTHORIZATION_COMMITMENT_MISMATCH")

    current_history = vector.get("current_history")
    actual_local_state = expected_local_state(current_history, birth_contract)
    if request["expected_local_state"] != actual_local_state:
        return reject("BASE_STATE_CHANGED")
    relation = history_relation(candidate_history, current_history)
    if relation == "ROLLBACK":
        return reject("HISTORY_ROLLBACK")
    if relation == "FORK":
        return reject("HISTORY_FORK")

    history_verification = vector.get("history_verification")
    if history_verification != expected_history_verification(request, relation, continuity_contract, birth_contract):
        return reject("HISTORY_SCOPE_MISMATCH")

    request_id = request_commitment(request, continuity_contract, birth_contract)
    prior = vector.get("prior_operation")
    if prior is not None:
        if prior["operation_id"] != request["operation_id"]:
            raise ContractError(f"vector {vector['id']}: prior operation lookup is not operation-scoped")
        if prior["request_commitment"] != request_id:
            return reject("OPERATION_ID_CONFLICT")
        expected_replay = accepted(request, relation, continuity_contract, birth_contract, "REPLAYED")
        if prior["result"] != accepted(request, relation, continuity_contract, birth_contract):
            return reject("PLAN_EVIDENCE_MISMATCH")
        return expected_replay

    command = vector.get("verified_command")
    if command != expected_command(request, vector, relation, continuity_contract, birth_contract):
        return reject("HISTORY_SCOPE_MISMATCH")
    if not validator_for(schema, birth_schema, continuity_schema, "VerifiedRecoveryCommandV1").is_valid(command):
        return reject("INVALID_REQUEST")
    return accepted(request, relation, continuity_contract, birth_contract)


def validate_schema(schema: dict, birth_schema: dict, continuity_schema: dict) -> None:
    Draft202012Validator.check_schema(schema)
    if schema.get("x-hivra-contract-id") != CONTRACT_ID or schema.get("x-hivra-contract-version") != 1:
        raise ContractError("schema identity mismatch")
    if schema.get("x-hivra-design-status") != DESIGN_STATUS:
        raise ContractError("schema must remain design-only")
    if schema.get("x-hivra-normative-source") != "docs/architecture-v2-blueprint.md" or schema.get("x-hivra-normative-heading") != NORMATIVE_HEADING:
        raise ContractError("schema normative owner drifted")
    if validator_for(schema, birth_schema, continuity_schema).is_valid({}):
        raise ContractError("root schema accepts empty object")
    definitions = schema["$defs"]
    expected_refs = {
        "CapsuleIdV2": "capsule-identity-birth-v2.schema.json#/$defs/CapsuleIdV2",
        "KeyDescriptorV1": "capsule-identity-birth-v2.schema.json#/$defs/KeyDescriptorV1",
        "SignatureProofV1": "capsule-identity-birth-v2.schema.json#/$defs/SignatureProofV1",
        "ContinuitySnapshotV1": "capsule-continuity-export-v2.schema.json#/$defs/ContinuitySnapshotV1",
        "ContinuityArtifactEvidenceV1": "capsule-continuity-export-v2.schema.json#/$defs/ContinuityArtifactEvidenceV1",
    }
    for name, ref in expected_refs.items():
        if definitions[name].get("$ref") != ref:
            raise ContractError(f"{name} must reuse the reviewed upstream contract")
    request_required = set(definitions["RecoveryRequestV1"]["required"])
    if {"artifact_evidence", "candidate_snapshot", "expected_local_state", "root_authority", "authorization_proof"} - request_required:
        raise ContractError("recovery request lost required semantic binding")
    verified_text = canonical(definitions["VerifiedRecoveryCommandV1"])
    if any(value in verified_text for value in ("seed", "mnemonic", "signature_bytes", "key_bytes", "path", "artifact_bytes", "events")):
        raise ContractError("verified recovery command acquired secret or adapter fields")
    result = definitions["RecoveryAcceptedV1"]["properties"]
    if result["core_append_required"].get("const") is not False or result["durability_claimed"].get("const") is not False or result["activation_claimed"].get("const") is not False:
        raise ContractError("prepared recovery result acquired mutation or completion claim")
    errors = set(definitions["RecoveryRejectedV1"]["properties"]["error_code"]["enum"])
    if errors != ERROR_CODES:
        raise ContractError("closed error set drifted")


def validate_blueprint(blueprint: str) -> None:
    contract = section(blueprint, NORMATIVE_HEADING)
    required = {
        f"- Contract id: `{CONTRACT_ID}`", "This section is the normative design source.",
        "There is no second recovery route through Capsule selection or persistence.",
        "A mnemonic or key without authenticated continuity",
        "Recovery never rewrites, re-signs, truncates, or heuristically",
        "No V2 runtime work is authorized",
    }
    missing = sorted(value for value in required if value not in contract)
    if missing:
        raise ContractError(f"normative blueprint contract incomplete: {missing}")
    if "This contract authorizes runtime implementation." in contract:
        raise ContractError("normative contract authorizes runtime implementation")


def validate_fixtures(schema: dict, birth_schema: dict, continuity_schema: dict, fixtures: dict, birth_contract, continuity_contract) -> None:
    if set(fixtures) != {"schema_version", "contract_id", "design_status", "vectors"}:
        raise ContractError("fixture root shape mismatch")
    if fixtures["schema_version"] != 1 or fixtures["contract_id"] != CONTRACT_ID or fixtures["design_status"] != DESIGN_STATUS:
        raise ContractError("fixture identity mismatch")
    ids = set()
    root = validator_for(schema, birth_schema, continuity_schema)
    for vector in fixtures["vectors"]:
        vector_id = vector["id"]
        if vector_id in ids:
            raise ContractError(f"duplicate vector id: {vector_id}")
        ids.add(vector_id)
        actual = evaluate(vector, schema, birth_schema, continuity_schema, birth_contract, continuity_contract)
        if actual != vector["expected"]:
            raise ContractError(f"vector {vector_id}: expected {vector['expected']} got {actual}")
        if not root.is_valid(actual):
            error = next(root.iter_errors(actual))
            raise ContractError(f"vector {vector_id}: result fails schema: {error.message}")
    if ids != REQUIRED_VECTORS:
        raise ContractError(f"fixture coverage mismatch; missing={sorted(REQUIRED_VECTORS - ids)} extra={sorted(ids - REQUIRED_VECTORS)}")


def self_test(schema: dict, birth_schema: dict, continuity_schema: dict, fixtures: dict, blueprint: str, birth_contract, continuity_contract) -> None:
    missing_root = copy.deepcopy(schema); missing_root.pop("oneOf")
    copied_capsule = copy.deepcopy(schema); copied_capsule["$defs"]["CapsuleIdV2"] = {"type": "object"}
    seed_optional = copy.deepcopy(schema); seed_optional["$defs"]["RecoveryRequestV1"]["required"].remove("artifact_evidence")
    activation_claim = copy.deepcopy(schema); activation_claim["$defs"]["RecoveryAcceptedV1"]["properties"]["activation_claimed"] = {"type": "boolean"}
    raw_seed_command = copy.deepcopy(schema); raw_seed_command["$defs"]["VerifiedRecoveryCommandV1"]["properties"]["seed"] = {"type": "string"}
    missing_vector = copy.deepcopy(fixtures); missing_vector["vectors"].pop()
    changed_result = copy.deepcopy(fixtures); changed_result["vectors"][0]["expected"] = reject("HISTORY_FORK")
    changed_proof = copy.deepcopy(fixtures); changed_proof["vectors"][0]["request"]["authorization_proof"]["signed_commitment"] = "00" * 32
    replay_drift = copy.deepcopy(fixtures)
    replay = next(vector for vector in replay_drift["vectors"] if vector["id"] == "exact_replay_returns_prior_plan")
    replay["prior_operation"]["result"]["plan_evidence"]["candidate_snapshot_commitment"] = "00" * 32
    missing_section = blueprint.replace(section(blueprint, NORMATIVE_HEADING), "")
    runtime_authorized = blueprint.replace(NORMATIVE_HEADING, NORMATIVE_HEADING + "\n\nThis contract authorizes runtime implementation.")
    probes = (
        ("missing root", lambda: validate_schema(missing_root, birth_schema, continuity_schema)),
        ("copied CapsuleId", lambda: validate_schema(copied_capsule, birth_schema, continuity_schema)),
        ("optional artifact", lambda: validate_schema(seed_optional, birth_schema, continuity_schema)),
        ("activation claim", lambda: validate_schema(activation_claim, birth_schema, continuity_schema)),
        ("raw seed command", lambda: validate_schema(raw_seed_command, birth_schema, continuity_schema)),
        ("missing vector", lambda: validate_fixtures(schema, birth_schema, continuity_schema, missing_vector, birth_contract, continuity_contract)),
        ("semantic drift", lambda: validate_fixtures(schema, birth_schema, continuity_schema, changed_result, birth_contract, continuity_contract)),
        ("proof rebinding", lambda: validate_fixtures(schema, birth_schema, continuity_schema, changed_proof, birth_contract, continuity_contract)),
        ("replay plan drift", lambda: validate_fixtures(schema, birth_schema, continuity_schema, replay_drift, birth_contract, continuity_contract)),
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
        continuity_schema = json.loads(CONTINUITY_SCHEMA_PATH.read_text(encoding="utf-8"))
        blueprint = BLUEPRINT_PATH.read_text(encoding="utf-8")
        birth_contract = load_module(BIRTH_VALIDATOR_PATH, "hivra_birth_contract")
        continuity_contract = load_module(CONTINUITY_VALIDATOR_PATH, "hivra_continuity_contract")
        birth_contract.validate_schema(birth_schema)
        continuity_contract.validate_schema(continuity_schema, birth_schema)
        validate_schema(schema, birth_schema, continuity_schema)
        validate_blueprint(blueprint)
        validate_fixtures(schema, birth_schema, continuity_schema, fixtures, birth_contract, continuity_contract)
        self_test(schema, birth_schema, continuity_schema, fixtures, blueprint, birth_contract, continuity_contract)
        print("PASS capsule-recovery-contract: scope, artifact, authority, history, replay, and mutations")
        return 0
    except (ContractError, json.JSONDecodeError, OSError, KeyError, TypeError, ValueError) as error:
        print(f"FAIL capsule-recovery-contract: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
