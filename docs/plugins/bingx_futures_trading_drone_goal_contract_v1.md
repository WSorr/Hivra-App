# BingX Futures Trading Drone — Goal Contract v1

Status: Active coordination contract  
Scope: Plugin/application trading-drone module only

---

## 1. Why This File Exists

This file is the operational anchor for trading-drone work.

It exists to prevent:

- goal drift,
- spec/runtime confusion,
- ad hoc patching without deterministic acceptance criteria.

---

## 2. Three Hivra Laws (Mandatory)

1. Modularity
   - decision/risk/execution logic stays in dedicated services.
   - UI is projection and intent dispatch only.
2. Determinism
   - identical normalized snapshot + identical policy input => identical decision payload/hash.
3. Dependencies strictly downward
   - `UI -> app services -> plugin host API -> transport adapter`.

Any change violating one of these laws is rejected.

---

## 3. Source-of-Truth Stack (Order of Authority)

1. Capsule protocol invariants: `docs/specification.md`
2. Plugin host boundary + capability contract: `docs/plugins/plugin_host_api_v1.md`
3. Drone decision/TVH contract: `docs/plugins/bingx_futures_trading_drone_spec_v1.md`
4. Runtime parity gate: `docs/checklists/trading-drone-spec-runtime-parity.md`
5. Milestone history/status log: `docs/roadmap.md` (status, not normative behavior source)

If documents disagree:

- normative behavior follows levels 1..4 above,
- roadmap text must be updated to match normative docs, not vice versa.

---

## 4. v1 Target Outcome (Definition of Success)

Trading drone must deliver:

1. Deterministic TVH decision pipeline:
   - `snapshot_normalize -> feature_extract -> rule_engine -> intent_builder`
2. Deterministic execution envelope and traceability:
   - `drone.decision.envelope`
   - `drone.execution.envelope`
3. Runtime safety controls:
   - consensus guard
   - risk governor
   - idempotency + TTL + deterministic retry class
4. Cross-platform reproducibility:
   - macOS + Android smoke evidence for the same release candidate.

---

## 5. Current Module Boundaries (Must Stay Stable)

Decision pipeline services:

- `flutter/lib/services/bingx_futures_market_snapshot_service.dart`
- `flutter/lib/services/bingx_futures_feature_extractor_service.dart`
- `flutter/lib/services/bingx_futures_tvh_rule_engine_service.dart`
- `flutter/lib/services/bingx_futures_deterministic_replay_harness_service.dart`
- `flutter/lib/services/bingx_futures_mode_orchestrator_service.dart`

Execution/safety services:

- `flutter/lib/services/bingx_futures_risk_governor_service.dart`
- `flutter/lib/services/bingx_futures_execution_queue_service.dart`
- `flutter/lib/services/bingx_futures_observability_envelope_service.dart`
- `flutter/lib/services/plugin_host_api_service.dart`
- `flutter/lib/services/wasm_plugin_capability_policy_service.dart`

UI surfaces:

- `flutter/lib/screens/trading_drone_screen.dart`
- `flutter/lib/screens/wasm_plugins_screen.dart`

Rule: UI must not fork decision semantics independently from service pipeline.

---

## 6. Work Cadence for Every Drone Change

After each logic patch:

1. Update normative docs when contract changes.
2. Run required drone tests from parity checklist.
3. Run `tools/review/release_discipline_gate.sh`.
4. Capture manual smoke evidence for affected path (`situational` / `interactive` / `risk_blocked` / retry / receipt).
5. Record unresolved gaps explicitly before next patch.

No “silent” behavior change without this cycle.

---

## 7. Acceptance Gates (Must Pass Together)

1. Spec/runtime parity checklist:
   - `docs/checklists/trading-drone-spec-runtime-parity.md`
2. Manual smoke:
   - `docs/checklists/manual-smoke.md` (Trading Drone section)
3. Release platform checklist:
   - macOS: `docs/checklists/release-macos.md`
   - Android: `docs/checklists/release-android.md`

---

## 8. Out of Scope for v1

- strategy-optimization claims beyond documented deterministic rule-set,
- unmanaged discretionary overrides hidden in UI,
- any core-ledger invariant expansion for exchange noise/events.

---

## 9. Ownership Rule

Trading-drone work is considered complete only when:

- code path,
- tests,
- docs,
- and smoke evidence

all point to the same behavior.

---

## 10. Current Status Snapshot (2026-05-18)

### 10.1 Already in Place

- Dedicated futures drone services exist for snapshot/feature/rule/replay/mode/risk/queue/observability.
- Plugin host runtime boundary exists for futures intent execution.
- Deterministic observability envelopes exist and are release-gated.
- Side/zone decision source is now service-level (`BingxFuturesZoneDecisionService`) and consumed by Trading Drone UI as a single contract.

### 10.2 Active Gaps to Close

1. End-to-end parity evidence discipline
   - Test suites exist, but per-build manual parity records are not always captured consistently across both platforms.
   - Target: mandatory build-tagged evidence for `situational`, `interactive`, `risk_blocked`, retry, receipt.

### 10.2.1 Gap Progress

- Spec/runtime wording drift is resolved in `docs/plugins/bingx_futures_trading_drone_spec_v1.md`:
  - spec now reflects runtime execution path (risk-governed runtime invoke + decision/execution envelopes).
- Evidence discipline is now scaffolded with:
  - `docs/checklists/trading-drone-evidence-log.md`
  - `tools/release/record_trading_drone_evidence.sh`
  - release checklist hooks (macOS/Android) + release-discipline gate checks.

### 10.3 Ordered Execution Plan

1. Lock deterministic replay:
   - add/extend fixtures for side/zone regressions and drift detection.
2. Update normative docs:
   - align drone spec and host-boundary wording with implemented runtime behavior.
3. Release-candidate parity run:
   - macOS + Android evidence captured with build tag/date in parity checklist.
