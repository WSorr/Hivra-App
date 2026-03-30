# Temperature Tomorrow (Liechtenstein) Test Plugin v1

This is the first test smart-contract plugin shape for Hivra.

Purpose:
- deterministic winner resolution for a simple dispute:
- "tomorrow daily average temperature in Liechtenstein is above/below threshold"

Status:
- pre-host contract model (no wasm execution yet)
- used to lock manifest and settlement semantics before WASM host rollout

## Manifest (v1 draft)

```json
{
  "schema": "hivra.plugin.manifest",
  "version": 1,
  "plugin_id": "hivra.contract.temperature-li.tomorrow.v1",
  "contract": {
    "kind": "temperature_tomorrow_liechtenstein",
    "location_code": "LI",
    "target_date_utc": "2026-03-31",
    "threshold_deci_celsius": 85,
    "proposer_rule": "above",
    "draw_on_equal": true
  }
}
```

## Deterministic Inputs

- `peer_hex` (pair participant)
- manifest-derived contract settings
- oracle observation:
  - `source_id`
  - `event_id`
  - `location_code`
  - `target_date_utc`
  - `recorded_at_utc` (ISO UTC)
  - `observed_deci_celsius` (integer)

## Settlement Rule

Given:
- threshold `T`
- observed value `O`
- proposer rule (`above` or `below`)

Outcome:
- if `O == T` and `draw_on_equal == true` -> `draw`
- else proposer wins when condition from `proposer_rule` is true
- otherwise counterparty wins

Canonical settlement JSON is hashed by SHA-256.

## Guard Requirement

Pair-scoped contract execution must remain blocked when consensus is not signable.
The runtime contract service calls `ConsensusRuntimeService.signable(peerHex)` before settlement.
