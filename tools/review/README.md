# Review Checks

This directory contains deterministic repository checks for architecture and security hygiene.

Scripts:

- `topology_check.sh` validates high-level repository placement rules.
- `dependency_check.sh` validates downward dependency direction between Rust crates.
- `architecture_contract_gate.sh` validates architecture-law sync across code, docs, anti-sprawl contracts, projection-discipline rules, invitation boundary discipline, and WASM plugin-host guard boundaries.
- `ui_ffi_boundary_gate.sh` validates that Flutter UI layer (`main.dart`, `screens/`, `widgets/`, `utils/`) does not import raw `HivraBindings` directly.
- `tools/review/docs_integrity_gate.sh` validates markdown links, referenced repo paths, and stale terminology across README/docs/tools documentation.
- `release_discipline_gate.sh` validates release-discipline sync across roadmap, macOS/Android/manual/runtime-hardening checklists, preflight, and review gate wiring.
- `trading_drone_parity_gate.sh` validates that the Trading Drone parity runtime-status table has no `TODO`/`PARTIAL` rows.
- `user_lifetime_safety_gate.sh` validates presence and baseline scenario coverage of the user-lifetime safety checklist for release candidates.
- `security_check.sh` validates that common local artifacts and obvious secret-like content are not tracked.
- `review_all.sh` runs every check and returns non-zero on any failure.

Run from the repository root:

```bash
tools/review/review_all.sh
```

These checks are intentionally mechanical. They should stay simple, deterministic, and easy to audit.
