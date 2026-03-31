# Plugin Host API v1 (Pre-WASM Execution)

This document defines the first deterministic host API boundary used before wasm runtime execution is mounted.

## Scope

- No wasm bytecode execution.
- Explicit API boundary for plugin calls.
- Guard-first behavior:
  - pair-scoped calls are blocked when consensus is not signable.

## Request Shape

```json
{
  "schema_version": 1,
  "plugin_id": "hivra.contract.temperature-li.tomorrow.v1",
  "method": "settle_temperature_tomorrow",
  "args": {
    "target_date_utc": "2026-04-01",
    "threshold_deci_celsius": 85,
    "proposer_rule": "above",
    "draw_on_equal": true,
    "location_code": "LI",
    "observed_deci_celsius": 90,
    "oracle_source_id": "oracle.mock.weather.v1",
    "oracle_event_id": "evt-1",
    "oracle_recorded_at_utc": "2026-04-01T12:00:00Z"
  }
}
```

## Response Shape

- `status`: `executed | blocked | rejected`
- `result`: present only for `executed`
- `blocking_facts`: present for `blocked`
- `error_code`/`error_message`: present for `rejected`
- `canonical_json` + `response_hash_hex`:
  - deterministic for identical request + runtime inputs

## Error Codes

- `invalid_schema_version`
- `unsupported_plugin`
- `unsupported_method`
- `invalid_args`

## Notes

- This API is an application-layer boundary and does not grant plugin storage or ledger-write privileges.
- It exists to lock deterministic host semantics before introducing wasm runtime execution.
