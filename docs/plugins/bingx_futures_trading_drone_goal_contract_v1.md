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
- `flutter/lib/services/bingx_futures_trading_cycle_use_case_service.dart`

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
The solo limit-strategy action enters the canonical trading-cycle use case;
future headless composition must reuse that port rather than copy screen logic.

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

## 10. Current Status Snapshot (2026-06-25)

### 10.1 Already in Place

- Dedicated futures drone services exist for snapshot/feature/rule/replay/mode/risk/queue/observability.
- Semantic WASM ABI v2 is live; plugin packages own contract evaluation and signal ranking.
- Plugin host runtime boundary validates package identity, capabilities, canonical output, consensus, risk, and exchange execution.
- Deterministic observability envelopes exist and are release-gated.
- Live entry, managed-order revalidation, provenance, and deterministic replacement are wired through shared service boundaries.

### 10.2 Active Gaps to Close

1. End-to-end parity evidence discipline
   - Runtime/spec parity is complete; every release candidate still requires fresh manual records across both platforms.
   - Target: mandatory build-tagged evidence for `situational`, `interactive`, `risk_blocked`, retry, receipt.

### 10.2.1 Gap Progress

- Spec/runtime wording drift is resolved in `docs/plugins/bingx_futures_trading_drone_spec_v1.md`:
  - spec now reflects runtime execution path (risk-governed runtime invoke + decision/execution envelopes).
- Evidence discipline is now scaffolded with:
  - `docs/checklists/trading-drone-evidence-log.md`
  - `tools/release/record_trading_drone_evidence.sh`
  - release checklist hooks (macOS/Android) + release-discipline gate checks.

### 10.3 Ordered Execution Plan

1. Keep deterministic replay, ABI, risk, and managed-order regressions green.
2. Reject any runtime change that reintroduces screen-owned decision semantics or host-side plugin evaluator mirrors.
3. For every release candidate:
   - macOS + Android evidence captured with build tag/date in parity checklist.

---

## 11. Remote Runner Shadow Boundary

Status: Pass D durable shadow-stream implementation and its bounded
crash-atomic append remediation are complete. No following remote-runtime pass
is selected, and daemon, deployment, leases, account access, and remote
effects are not authorized.

### 11.1 Purpose And Sole Owner

The first remote-runner milestone exists only to prove that the current
deterministic Trading Drone can be reproduced on an unattended host without
moving Capsule authority or creating another trading path.

`TradingDroneModuleService` remains the sole local application owner of
trading intent, risk, execution, reconciliation, and user-visible state. A
future remote runner is a replaceable compute worker. It may produce shadow
evidence, but it cannot own a position, order, approval, retry, receipt,
credential, or Capsule fact.

Canonical Pass A path:

```text
public BingX market data
  -> pinned Trading Drone package and policy
  -> deterministic shadow decision
  -> signed, bounded shadow evidence
  -> local comparison and diagnostics only
```

There is no remote effect path in Pass A.

### 11.2 Permanent Authority Boundary

The remote host MUST NOT receive or derive:

- a Capsule seed, root key, transport key, backup, or unrestricted Ledger;
- the local BingX trading API key or secret;
- a user approval, consensus authority, or external-effect capability;
- permission to place, cancel, replace, amend, or reconcile an order;
- permission to mutate local tracking, risk, plugin, or Capsule state.

No result from the runner becomes a trading intent or effect merely because it
is signed, recent, or deterministic. Remote output remains untrusted evidence
until the local owner validates its exact contract and compares it with the
canonical local pipeline.

### 11.3 Pass A Input And Output Contract

Pass A uses only provider-public market endpoints. It stores no exchange or
Capsule credential on the remote host. Account balance, positions, realized
PnL, open orders, and all authenticated exchange reads remain local and are
therefore absent from remote risk and execution decisions.

Each shadow run binds at least:

- contract version and runner build identity;
- pinned plugin id, version, package digest, and host ABI;
- normalized public market snapshot and its canonical hash;
- exact deterministic policy/configuration hash;
- shadow decision payload and decision hash;
- observed-at time, bounded validity window, sequence, and previous evidence
  hash;
- runner signing-key id and signature suite.

Unknown versions, stale windows, repeated sequence values with changed
content, broken previous-hash continuity, plugin/policy drift, invalid
signatures, oversized evidence, and local replay mismatch fail closed. They
produce diagnostics only and never trigger an exchange action.

### 11.4 Threat Model

Pass A must make the following failures visible:

- **host compromise:** forged or altered shadow evidence is rejected; public
  data access grants no trading authority;
- **runner spoofing/key confusion:** evidence is accepted only from the exact
  leased runner key and declared signature suite;
- **replay/fork:** sequence plus previous-evidence hash permits one ordered
  stream; conflicting reuse is quarantined;
- **package or policy substitution:** digest/ABI/config mismatch blocks parity;
- **clock manipulation:** local receipt time and bounded validity are checked
  independently of runner time;
- **provider divergence or stale data:** snapshot hashes and source times stay
  visible; missing required inputs yield `NO_SIGNAL`/`BLOCKED`, never an
  inferred trade;
- **resource exhaustion:** observation cadence, evidence size, retention, and
  concurrent runner count are bounded before ingestion;
- **downgrade:** shadow evidence cannot be translated into the existing local
  execution envelope or bypass its consensus, risk, idempotency, approval, and
  receipt owners.

### 11.5 Lease, Revocation, And Kill Switch

A later implementation may activate one short-lived, Capsule-authorized runner
lease. The lease must bind the runner key, build/package/policy digests,
observation scope, cadence, expiry, and monotonically increasing lease version.
Renewal creates a new version; it cannot extend or mutate an old lease in
place. Revocation and expiry stop local acceptance immediately.

Pass A uses no exchange key, so a compromised runner loses useful authority
when local acceptance stops. Any later account-read phase requires a separate
decision and an independently revocable, read-only, IP-bound exchange key. Any
future trading permission requires another contract and cannot reuse the
shadow lease or read-only key.

### 11.6 Exit Evidence And Sealed Paths

Pass A is complete only when a later implementation proves, over bounded
fixtures and live public observations:

1. local and remote snapshot, feature, and decision hashes match;
2. restart resumes one ordered evidence stream without duplicate acceptance;
3. expiry, revocation, wrong runner, fork, stale data, package drift, and policy
   drift fail closed;
4. zero authenticated BingX calls and zero exchange mutations occur remotely;
5. no remote output enters `BingxFuturesExchangeExecutionUseCaseService` or the
   external-effect lifecycle.

This contract seals three shortcuts: copying the Capsule to a VPS, copying the
local trading credential to a VPS, and adding a second exchange-execution
route. It does not authorize implementation, deployment, a background service,
or a 24/7 trading claim. The next step after this design checkpoint must be
selected separately.

### 11.7 Pass B Fixture-Only Evidence Harness

Pass B extends the existing
`BingxFuturesDeterministicReplayHarnessService`; it does not add another runner,
decision owner, transport, repository, or effect path. One bounded evidence
value carries the Pass A fields for deterministic fixture verification. The
canonical semantic commitment is UTF-8 over:

```text
hivra:trading-shadow-evidence:v1\n
|| canonical JSON of the suite-tagged evidence fields
```

The signature is verified over that exact commitment before evidence can be
accepted or treated as an exact replay. The evidence hash is SHA-256 over the
same domain-separated commitment. The current fixture compatibility suite is
`ed25519-v1`; the suite identifier and signature bytes remain explicit contract
fields rather than becoming Capsule identity.

Fixture acceptance is fail-closed and ordered:

1. enforce the encoded-size, contract-version, suite, shape, and validity
   bounds;
2. bind the declared runner key id to the exact trusted fixture public key and
   authenticate the semantic commitment;
3. compare runner build/ABI, plugin/version/package digest, and policy hash;
4. compare snapshot, feature, decision, and decision kind with the canonical
   local replay result;
5. enforce local receipt time, exact-repeat semantics, next sequence, and
   previous-evidence hash continuity.

The canonical positive vector and negative mutations live in the existing
replay harness test. They cover downgrade, wrong runner, invalid signature,
stale evidence, changed-content sequence reuse, forked continuity, build,
plugin/package, policy, and local parity drift. An exact repeat is diagnostic
idempotency only; it grants no authority and produces no state mutation.

Pass B contains no network client, persistence, credential read, UI, VPS
deployment, lease activation, account data, exchange call, intent conversion,
or external effect. It makes the signed shadow contract executable over local
fixtures only and leaves every sealed Pass A shortcut sealed. Any live public
observation, retained acceptance journal, remote process, or account-read phase
requires a separately selected pass.

### 11.8 Pass B Remediation: Public Shadow And Canonical Wire

The remote shadow decision is computed only from the normalized public market
snapshot, extracted public features, public funding rate, and pinned public
strategy thresholds. Capsule consensus signability, blocking facts, account
risk, approval, position/order state, execution policy, and effect state are
local-only gates. They MUST NOT enter the remote input, policy commitment,
decision commitment, or wire evidence. A remote `LONG` or `SHORT` remains an
untrusted parity observation; the local owner may independently return
`BLOCKED` before any intent exists.

The version-1 wire is the UTF-8 encoding of one compact JSON object in the exact
field order defined by `BingxFuturesShadowEvidence.semanticMap`, followed by
`signature_hex`. It permits no insignificant whitespace, reordered, duplicated,
missing, or unknown fields. Identifiers are bounded canonical ASCII, hashes and
signature bytes are lowercase hexadecimal, and temporal/sequence values are
JSON integers. The parser receives bounded untrusted bytes, decodes strict
UTF-8, reconstructs the typed evidence, re-encodes it, and requires byte-for-byte
equality before authentication or parity checks.

`flutter/test/fixtures/trading_shadow_evidence_v1.json` is subordinate golden
evidence, not another semantic owner. Dart parses its exact wire and verifies
the Ed25519 signature path. The independent Python validator reconstructs the
canonical JSON, domain-separated hash, runner key id, and negative wire
mutations. The existing Trading parity gate executes that validator. This
remediation changes no application consumer, network, persistence, credential,
UI, Core, FFI, exchange, or external-effect path.

Post-remediation consolidation makes this separation structural inside the
existing TVH rule owner. `evaluateMarket()` accepts only public features,
funding, and strategy policy. The existing `evaluate()` remains the local
consensus wrapper and delegates to that same market evaluator only after its
local guard passes. The public replay harness calls `evaluateMarket()` directly;
no synthetic consensus value or disabled consensus flag remains on that path.

### 11.9 Pass C Live Public Shadow Probe

Pass C adds one bounded, one-shot headless probe. It is an observation tool,
not a daemon, scheduler, acceptance journal, lease, deployment unit, or trading
runtime. `BingxFuturesDeterministicReplayHarnessService` remains the shadow
evidence owner and produces the existing canonical wire. The probe adds no
second evidence contract or decision implementation.

The live market pipeline depends on `BingxFuturesPublicMarketDataPort`, whose
surface contains only the public quote, candle, depth, trade, funding, and open
interest reads required by the existing snapshot builder. Credentials are not
accepted by the live snapshot or strategy command. The concrete BingX adapter
may implement both public and authenticated provider operations for the local
application, but the shadow composition receives only the public port.

One invocation:

1. fetches one bounded public snapshot for one explicit symbol;
2. runs the existing public market replay and policy;
3. binds build, plugin, package, ABI, policy, snapshot, feature, decision,
   validity, runner key, sequence `1`, and the empty predecessor hash;
4. signs the canonical commitment with a runner-only Ed25519 compatibility
   key supplied through process environment;
5. writes one new canonical evidence file and refuses to overwrite it.

The probe cannot accept a Capsule, account, exchange credential, mandate,
approval, consensus fact, order state, or effect request. Public input failure,
invalid metadata, invalid runner seed, invalid validity, or an existing output
path fails closed without evidence. Pass C has no retained sequence state, so
it proves only a single live observation. Restart continuity, scheduling,
deployment, lease activation, account reads, and remote execution remain
separate unauthorized decisions.

The Trading parity gate structurally rejects credential/full-adapter authority
in the public pipeline and local authority/effect owners in the probe. Its
negative mutation self-test proves those checks fail closed. Pass C exit
evidence requires focused regressions, full repository gates, one live public
probe, independent signature verification, protected PR gates, and green
post-merge CI. It seals direct reuse of the app-wide Trading module as a remote
host and still seals Capsule-on-VPS, trading-key-on-VPS, and remote effects.

### 11.10 Pass D Durable Shadow Stream And Restart Continuity

Pass D gives the existing one-shot probe one runner-only persistence owner. It
does not add a scheduler, daemon, receiver, lease, deployment unit, account
read, Capsule state, or effect path. `BingxFuturesDeterministicReplayHarnessService`
continues to own evidence semantics and authentication;
`BingxFuturesShadowStreamStore` owns only durable ordered retention.

The store binds one immutable stream identity to the exact runner key. Under a
process-local mutation tail and a bounded inter-process file-lock acquisition,
every append authenticates all retained canonical evidence, reconstructs the
exact sequence and predecessor hash, produces the next evidence through the
existing harness, and creates one new evidence file exclusively. Restart
therefore continues the same authenticated hash chain. A public observation
failure or exhausted lock budget creates no evidence.

Retention is bounded at 256 entries and has no committed-evidence deletion,
eviction, repair, rotation, or reset API. Full capacity, malformed or truncated
evidence, an invalid retained signature, key confusion, unknown files,
non-canonical wire, sequence reuse, predecessor conflict, linked stream paths,
and concurrent append conflict fail closed. Recovery never guesses a
predecessor and never rewrites retained evidence. Deleting or rolling back the
complete stream directory remains a host-integrity event that cannot be
distinguished without a separately authorized external anchor.

Pass D exit evidence requires restart continuation, same-process and actual
cross-process concurrency, exhausted lock budget, producer failure,
corruption/signature mutation, key confusion, sequence/predecessor conflict,
unknown-entry, and bounded-full negative tests plus the existing public-only
structural mutation gate. It
seals stateless sequence reuse by the probe. Scheduling, stream rotation,
transport/ingestion, local acceptance state, VPS deployment, lease activation,
account reads, and remote exchange effects remain separate decisions.

### 11.11 Pass D Remediation: Crash-Atomic Append Commit

The committed filename is the sole append commit point. The existing stream
store writes canonical evidence to one exclusive pending file, flushes its
bytes, and atomically renames it into the committed evidence directory while
holding the existing bounded inter-process lock. A crash before rename leaves
no committed entry; restart may remove only one regular pending file whose
name exactly matches the canonical pending pattern. Unknown, linked, or
multiple pending entries fail closed.

Committed evidence is never deleted, replaced, rewritten, or repaired. A
pre-existing committed target is a conflict, not permission to overwrite it.
This remediation seals the crash window in which a final evidence filename
could become visible before its bytes were durable. It adds no owner, DTO,
scheduler, receiver, credential, Capsule state, or effect path. Exit evidence
requires interrupted-pending recovery, unknown-pending rejection,
committed-target conflict rejection, retained-corruption rejection, structural
negative mutation, full local and clean-checkout gates, protected PR gates,
and green post-merge CI.

The remediation completed on `main` at `ede2eb3` through protected PR `#101`.
Required run `32021137109` and post-merge run `32021215679` passed together
with Flutter `910/910`, analyze, Rust workspace, full review gates, clean
checkout, and `15/15` focused crash-atomic adverse tests. No following pass is
selected automatically.

## 12. Local Bounded Mandate Boundary

The normative mandate contract is section 5.3.3 of
`bingx_futures_trading_drone_spec_v1.md`. The local product proves that contract
before any headless-host pass: one Capsule-scoped operational owner, one
exchange-effect owner, exact account/symbol/mode/time/notional/risk/effect
bounds, explicit revocation, and fail-closed restart behavior. This section
does not duplicate those semantics and authorizes no Remote Runner or VPS.
