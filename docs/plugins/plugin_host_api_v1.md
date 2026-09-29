# Plugin Host API v1 (WASM Execution Boundary)

This document defines version 1 of the deterministic plugin request/response
contract. It is not the WASM ABI version: current external packages use
`hivra_host_abi_v2` and the `hivra_*_v1` exports below.

## Scope

- WASM bytecode execution through the bounded `wasmi_v1` runtime for resolved
  external packages.
- Explicit method and capability checks before invocation.
- Pair-scoped calls blocked unless the local pair snapshot is signable and the
  required attestations bind both roots to that snapshot.

The host does not grant plugin storage, Ledger writes, transport access, or
provider effects merely because a WASM call succeeds.

## Supported Contracts

- `hivra.contract.capsule-chat.v1`
  - `post_capsule_chat_message`
- `hivra.contract.moltbook-ambassador.v1`
  - `prepare_moltbook_draft`
  - `plan_moltbook_heartbeat`
  - `plan_moltbook_engagement`
  - `prepare_moltbook_reply`
  - `authorize_moltbook_delegated_reply`

## Request Shape

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.capsule-chat.v1",
  "method": "post_capsule_chat_message",
  "args": {
    "peer_hex": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "client_message_id": "msg-1",
    "message_text": "hello",
    "created_at_utc": "2026-04-04T10:00:00Z"
  }
}
```

## Response Shape

- `status`: `executed | blocked | rejected`;
- `result`: present only for `executed`;
- `blocking_facts`: present for `blocked`;
- `error_code` and `error_message`: present for `rejected`;
- `canonical_json` and `response_hash_hex`: deterministic for identical
  request and runtime inputs;
- runtime evidence:
  - execution source and package identity;
  - package, module, and invocation digests;
  - contract kind and normalized capabilities;
  - runtime mode, ABI, entry export, and selected module path.

## Error Codes

- `invalid_schema_version`
- `unsupported_plugin`
- `unsupported_method`
- `invalid_args`
- `runtime_invoke_invalid`
- `runtime_invoke_failed`
- `runtime_invoke_unavailable`
- `runtime_binding_invalid`
- `runtime_contract_kind_mismatch`
- `runtime_capability_mismatch`

## Runtime Boundary

External execution is fail-closed:

- package id and kind are required;
- package bytes must match the resolved digest;
- contract kind and required method capabilities must match the manifest;
- runtime ABI is `hivra_host_abi_v2`;
- runtime entry export is `hivra_evaluate_v1`;
- zip module paths cannot traverse parents;
- modules cannot import host functions;
- module, input, output, linear memory, and fuel are bounded;
- missing exports, signature mismatch, traps, invalid UTF-8, malformed
  envelopes, and output-hash mismatch are rejected;
- no legacy fail-open path exists for missing contract or capability metadata.

ABI exports:

- `hivra_alloc_v1(len: u32) -> u32`
- `hivra_evaluate_v1(ptr: u32, len: u32) -> u64`
- `hivra_dealloc_v1(ptr: u32, len: u32)`

The packed evaluate result is `(output_ptr << 32) | output_len`.

## Capability Ownership

- Chat requires `consensus_guard.read`, returns plugin-owned canonical message
  bytes, and leaves pair consensus and transport delivery to the host.
- Moltbook draft, planning, reply, and delegated-reply methods require their
  corresponding `content.*` capabilities. WASM output is proposal or bounded
  authorization evidence, not a network publication receipt.
- Host fallback is retained only for explicitly allowed compatibility methods.
  It is not a second WASM evaluator and must not duplicate plugin semantics.

## Consensus Scopes

- Solo methods do not read pair consensus.
- Pair-scoped methods require a valid `peer_hex` and the attested host guard.
- `ConsensusRuntimeService.signable(peer_hex)` is only a local snapshot
  precondition; it is not sufficient authorization.
- The host never substitutes a missing peer with an arbitrary signable peer.
