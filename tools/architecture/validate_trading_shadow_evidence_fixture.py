#!/usr/bin/env python3
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "flutter/test/fixtures/trading_shadow_evidence_v1.json"
SEMANTIC_KEYS = [
    "contract_version",
    "runner_build_id",
    "plugin_id",
    "plugin_version",
    "package_digest_hex",
    "host_abi",
    "policy_hash_hex",
    "market_snapshot_hash_hex",
    "feature_hash_hex",
    "decision_hash_hex",
    "decision",
    "observed_at_epoch_ms",
    "valid_until_epoch_ms",
    "sequence",
    "previous_evidence_hash_hex",
    "runner_key_id",
    "signature_suite",
]
WIRE_KEYS = [*SEMANTIC_KEYS, "signature_hex"]
NEGATIVE_MUTATIONS = {
    "pretty_whitespace",
    "reordered_fields",
    "unknown_field",
    "duplicate_field",
    "local_consensus_field",
}
ASCII_ID = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
LOWER_HEX = re.compile(r"^[0-9a-f]+$")


def canonical_json(value: dict) -> str:
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"))


def parse_canonical_wire(raw: str) -> dict:
    pairs = json.loads(raw, object_pairs_hook=lambda value: value)
    if not isinstance(pairs, list) or [key for key, _ in pairs] != WIRE_KEYS:
        raise ValueError("wire keys are missing, duplicated, reordered, or unknown")
    value = dict(pairs)
    if canonical_json(value) != raw:
        raise ValueError("wire bytes are not canonical JSON")
    for key in (
        "contract_version",
        "runner_build_id",
        "plugin_id",
        "plugin_version",
        "host_abi",
        "decision",
        "runner_key_id",
        "signature_suite",
    ):
        if not isinstance(value[key], str) or not ASCII_ID.fullmatch(value[key]):
            raise ValueError(f"{key} is not canonical ASCII")
    for key in (
        "package_digest_hex",
        "policy_hash_hex",
        "market_snapshot_hash_hex",
        "feature_hash_hex",
        "decision_hash_hex",
        "previous_evidence_hash_hex",
        "signature_hex",
    ):
        if not isinstance(value[key], str) or not LOWER_HEX.fullmatch(value[key]):
            raise ValueError(f"{key} is not lowercase hex")
    for key in ("observed_at_epoch_ms", "valid_until_epoch_ms", "sequence"):
        if isinstance(value[key], bool) or not isinstance(value[key], int):
            raise ValueError(f"{key} is not an integer")
    return value


def expect_rejected(identifier: str, raw: str) -> None:
    try:
        parse_canonical_wire(raw)
    except (ValueError, json.JSONDecodeError):
        return
    raise ValueError(f"negative mutation unexpectedly accepted: {identifier}")


def main() -> None:
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    semantic = fixture["semantic_fields"]
    if list(semantic) != SEMANTIC_KEYS:
        raise ValueError("semantic field order drifted")
    if any("consensus" in key or "risk" in key or "effect" in key for key in semantic):
        raise ValueError("local authority field escaped into remote evidence")

    semantic_json = canonical_json(semantic)
    if semantic_json != fixture["expected_semantic_json"]:
        raise ValueError("independent canonical semantic JSON mismatch")
    payload = (fixture["domain_separator"] + semantic_json).encode("utf-8")
    if hashlib.sha256(payload).hexdigest() != fixture["expected_evidence_hash_hex"]:
        raise ValueError("independent evidence hash mismatch")

    public_key = bytes.fromhex(fixture["runner_public_key_hex"])
    if hashlib.sha256(public_key).hexdigest() != semantic["runner_key_id"]:
        raise ValueError("runner key id mismatch")

    wire = {**semantic, "signature_hex": fixture["signature_hex"]}
    wire_json = canonical_json(wire)
    if wire_json != fixture["expected_wire_utf8"]:
        raise ValueError("independent canonical wire mismatch")
    parse_canonical_wire(wire_json)

    mutations = set(fixture["negative_mutations"])
    if mutations != NEGATIVE_MUTATIONS:
        raise ValueError("negative mutation inventory drifted")
    expect_rejected("pretty_whitespace", json.dumps(wire, indent=2))
    expect_rejected(
        "reordered_fields",
        canonical_json(dict(reversed(list(wire.items())))),
    )
    expect_rejected("unknown_field", canonical_json({**wire, "extra": True}))
    expect_rejected("duplicate_field", wire_json[:-1] + ',"decision":"short"}')
    expect_rejected(
        "local_consensus_field",
        canonical_json({**wire, "is_consensus_signable": True}),
    )
    print("PASS trading-shadow-evidence: canonical wire, hash, scope, and mutations")


if __name__ == "__main__":
    main()
