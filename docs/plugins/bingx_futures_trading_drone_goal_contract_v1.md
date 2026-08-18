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

Status: Pass D durable shadow-stream implementation and crash-atomic append
remediation are complete. Pass E authenticated bounded compaction is complete
on `main` at `8c5c644` through protected PR `#113`; required run `32042296142`
and post-merge run `32042345162` passed. Pass F public-only bounded scheduling
is complete on `main` at `712177f` through protected PR `#115`; required run
`32043346812` and post-merge run `32043400512` passed. Pass G verifiable
standalone artifact packaging is complete on `main` at `3fbe8f2` through
protected PR `#117`; required run `32044373306` and post-merge run
`32044425543` passed. Pass H pinned Linux x64 artifact evidence is complete on
`main` at `ea36a8b` through protected PR `#119`; required run `32054282257` and
post-merge run `32054365614` passed. No following pass is selected. Unbounded
daemon operation, Linux execution, transfer, installation, deployment,
external anchoring, leases, account access, remote effects, supervisor
configuration, and VPS changes remain unauthorized.

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

Every accepted public-shadow append exposes the non-secret 64-hex
`runner_key_id` already bound inside its signed evidence. Process restart must
retain that exact fingerprint; omission or change fails host continuity
evidence. The fingerprint grants no authority and is not a credential.

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

### 11.12 Pass E: Authenticated Bounded Stream Compaction

Pass E removes the finite 256-entry dead end without adding a scheduler,
daemon, receiver, deployment unit, lease, credential, account read, Capsule
state, or effect path. `BingxFuturesShadowStreamStore` remains the sole
runner-retention owner and the existing canonical signed shadow evidence
remains the only checkpoint format.

Only a full, ordered, authenticated tail may be compacted. Its final canonical
evidence is flushed and atomically committed as the next local checkpoint
before any covered evidence file is deleted. The checkpoint binds the exact
runner key, global sequence, predecessor chain head, and evidence hash. The
next append continues at `checkpoint.sequence + 1`; restart may finish an
exact committed-checkpoint overlap but rejects corruption, key confusion,
partial or conflicting overlap, non-file checkpoint state, and cleanup beyond
the checkpoint sequence. Interrupted checkpoint bytes are confined to one
fixed pending filename and grant no continuity.

The retained tail remains bounded at 256 entries while global sequence and
hash continuity can advance beyond it. A local checkpoint does not prove that
the host directory was not rolled back or deleted; rollback-resistant external
anchoring remains mandatory before any remotely authorized account or exchange
effect. Pass E therefore unlocks evaluation of a public-only bounded daemon,
not VPS deployment or trading authority.

Implementation evidence: focused store `27/27`, combined shadow/replay
`39/39`, Flutter `927/927`, analyze, Rust workspace, full review gates, clean
detached-checkout, and the checkpoint-before-cleanup negative mutation passed.
No new DTO, service, owner, journal, credential, scheduler, deployment, Capsule
state, account read, or effect route was added.

### 11.13 Pass F: Public-Only Bounded Scheduler

Pass F extends only the existing one-shot probe composition root. One command
may request between 1 and 288 strictly serial observations. Multiple
observations require an explicit fixed delay between 60 and 3600 seconds. A
delay begins only after the preceding observation and authenticated append
complete, so cycles never overlap and slow provider responses cannot create a
second in-flight observation.

The first observation, validation, append, lock, or delay failure terminates
the command with a non-zero result. There is no internal retry, backoff,
catch-up, skipped-cycle synthesis, inferred success, or endless mode. Restart
re-enters the existing authenticated stream and continues its sequence through
the existing store; it does not create scheduler state or another journal.

The probe still accepts only public market scope, runner metadata, one
runner-only seed, and the existing stream directory. It accepts no Capsule,
exchange credential, account state, mandate, approval, lease, or effect. Pass F
adds no service, DTO, receiver, supervisor, deployment unit, background OS
integration, VPS configuration, or exchange path. Its exit evidence requires
serial cadence, exact bounded-argument rejection, stop-on-first-failure,
authority and scheduler mutation tests, full local and clean-checkout gates,
protected PR, and green post-merge CI.

Implementation evidence: scheduler `4/4`, combined scheduler/shadow/replay
`45/45`, Flutter `931/931`, analyze, Rust workspace, full review gates, clean
detached-checkout, and scheduler/authority negative mutations passed. No new
service, DTO, journal, receiver, supervisor, deployment unit, credential,
account read, Capsule state, lease, or effect route was added.

### 11.14 Pass G: Verifiable Standalone Host Artifact

Pass G packages the existing public-only probe entrypoint as one host-native
executable. Packaging requires a completely clean Git tree and the exact Dart
SDK version pinned by the repository. The output stays outside the repository
and contains only the fixed executable name plus one ordered version-1
manifest.

The manifest binds the source commit, clean-tree claim, Dart version, target OS
and architecture, canonical entrypoint, `public-market-shadow-only` authority
profile, binary filename, exact byte length, and SHA-256. Verification rejects
missing, duplicate, reordered, unknown, malformed, linked, non-executable, or
hash/size-conflicting state and scans the final binary for authenticated BingX
effect markers. The package is verified before its pending directory is
atomically promoted to the requested output path; existing output is never
overwritten.

Two consecutive Dart AOT builds from the same source produced different bytes
during audit. Pass G therefore makes no reproducible-build claim. It binds and
verifies one exact artifact instead of pretending that source identity alone
proves binary identity.

This pass adds no runtime service, DTO, scheduler, receiver, deployment unit,
credential, account read, Capsule state, lease, external anchor, or effect
route. It does not transfer an artifact, build Linux evidence, install on the
VPS, configure systemd/Docker, touch the existing site or Amnezia service, or
claim unattended operation. Those remain separate decisions after protected
packaging evidence.

Implementation evidence: the post-merge Darwin arm64 artifact built from
`3fbe8f2` is 6,917,488 bytes with SHA-256
`4782f3f119f1975dc4ed7005f94ad96526ae6f9753377483102e0c1adf498282`.
Verifier negative tests, dirty-tree rejection, Flutter `931/931`, analyze, Rust
workspace, full review gates, clean detached-checkout packaging, protected PR,
and green post-merge CI passed. No new runtime owner or path was added.

### 11.15 Pass H: Pinned Linux x64 Artifact Evidence

Pass H proves that the existing public-only entrypoint can become one Linux
x86-64 executable without downloading the 1.5 GB Flutter Linux archive or
creating a second implementation. A temporary package map resolves the existing
canonical `hivra_app` imports without changing the Flutter source contract. One
packaging-only pubspec and exact lock pin the minimal `crypto` and
`cryptography` dependency closure; the manifest binds the lockfile SHA-256.

Cross-compilation accepts only the explicit pair `linux/x64`. Verification
requires the produced bytes to be an ELF 64-bit x86-64 executable and rejects
a manifest whose target does not match the binary. Host-native Darwin
packaging remains available through the same owner. No generic target matrix,
package resolver service, alternate entrypoint, or second runner is added.

This pass does not execute the Linux binary, prove VPS libc compatibility,
transfer or install files, create a user or directory, configure systemd,
Docker, firewall, DNS, ports, CPU/memory limits, restart policy, or logging, or
touch the existing site and Amnezia service. It adds no credential, account
read, Capsule state, lease, external anchor, or exchange effect. Those require
separate host evidence and deployment decisions.

Implementation evidence: the post-merge ELF x86-64 artifact built from
`ea36a8b` is 7,807,720 bytes with SHA-256
`8c31e006535227088ea4b9ff63f162d06760f37c28bd18072a6f18fcee1f34b6`.
The dependency-lock SHA-256 is
`f5443e020cbafc892fb75080be84899d3d7f6196be1dc0f7525d73f1eac789ac`.
Target, source, lock, byte, shape, and authority negative tests, Flutter
`931/931`, analyze, Rust workspace, full review gates, clean detached-checkout
packaging, protected PR, and post-merge CI passed. No runtime owner or path was
added.

### 11.16 Pass I: Linux Runtime Startup Evidence

Pass I executes the exact verified Linux x64 artifact inside the existing
required Ubuntu repository-gate job. The existing artifact script remains the
sole packaging and host-compatibility evidence owner, and the existing probe
remains the sole executable entrypoint. No runner, deployment, or process
supervisor owner is added.

Runtime startup evidence is deliberately authority-free and network-free. The
smoke removes `HIVRA_SHADOW_RUNNER_SEED_HEX` from the child environment, starts
the verified ELF on a matching Linux x64 host, and accepts only the probe's
exact application-level missing-authority rejection. A loader failure,
unexpected standard output, success exit, different error, target mismatch, or
inherited runner seed fails the gate. Reaching the exact rejection proves that
the Linux binary entered the canonical probe before any stream path or public
provider call could be selected.

The CI job builds from its clean checkout with the exact Dart SDK and pinned
dependency lock, verifies the manifest and bytes, executes the smoke, then
deletes the ephemeral output. It does not upload or publish the artifact. This
pass does not prove live provider compatibility or VPS compatibility, and it
does not transfer, install, supervise, schedule, or configure the process. VPS,
SSH, site and Amnezia configuration, credentials, account reads, external
anchoring, Capsule state, leases, remote effects, tags, and Releases remain
sealed.

Implementation evidence: protected PR `#121`, required run `32057547066`, and
post-merge run `32057670511` passed. The required Ubuntu job built and verified
the ephemeral Linux x64 artifact, entered the canonical probe, observed the
exact missing-authority rejection, preserved a clean checkout after repository
review, and uploaded nothing. No runtime owner or effect path was added.

### 11.17 Pass J: Ephemeral VPS Public Observation Evidence

Pass J proves one live public observation on the audited target host without
installing or supervising the runner. The exact manifest-verified Linux x64
artifact is copied only into one unique temporary directory. The host generates
one ephemeral runner-only signing seed, runs one low-priority bounded cycle,
captures process resource evidence, and removes the seed from the environment.
Cleanup removes the process output, shadow stream, manifest, binary, and
temporary directory.

The smoke accepts no BingX API key, Capsule key, account identifier, mandate,
approval, consensus fact, order state, or effect request. It creates no user,
service, container, listener, firewall rule, nginx route, package installation,
or persistent host path. Website health and every pre-existing VPN container
must remain unchanged before and after the cycle. A transfer mismatch, wrong
binary hash or size, timeout, runner error, missing evidence append, service
regression, residual process, or residual temporary path fails the smoke.

Evidence from clean source `12c8f30`: artifact SHA-256
`8c31e006535227088ea4b9ff63f162d06760f37c28bd18072a6f18fcee1f34b6`;
one `BTC-USDT` public cycle completed in 3.213 seconds with peak RSS 24,072 KiB,
appended sequence `1`, and emitted evidence hash
`5c8f75b6b7fb32b9f09e4c2b1a33ceec16d18068a0144eb0ca7d06f21986013b`.
There was no stderr. The website remained healthy, all existing VPN containers
remained running, no listener changed, and final process/path cleanup was
confirmed. This evidence permits a later consolidation decision about one
isolated resource-bounded supervisor contract; it does not authorize that
contract, durable runner identity, deployment, credentials, account reads,
external anchoring, leases, or effects.

### 11.18 Pass K: Ephemeral VPS Resource Soak Evidence

Pass K characterizes the existing public-only runner under an enforced host
resource ceiling without installing a service or adding another runtime owner.
The exact manifest-verified Linux x64 artifact runs 60 strictly serial public
observations through the existing bounded scheduler and shadow store. One
transient cgroup supplies `MemoryMax=128 MiB`, zero swap, `TasksMax=16`, low CPU
scheduling weight, a finite runtime, and process cleanup. It is evidence
containment only, not a supervisor or deployment contract.

The soak fails closed on a non-zero runner result, stderr, missing or duplicate
cycle, sequence discontinuity, cgroup limit breach, website regression, VPN
container replacement or restart, residual unit, residual process, or residual
temporary path. It accepts no BingX API key, Capsule material, account state,
mandate, approval, order, listener, or effect request. The runner-only signing
seed is generated inside the temporary host path, exists only in the child
environment, and is removed with the process and directory.

Evidence from clean source `f98ce25`: the artifact SHA-256 remained
`8c31e006535227088ea4b9ff63f162d06760f37c28bd18072a6f18fcee1f34b6`;
60 `BTC-USDT` observations completed in 3,740 seconds; all 60 signed evidence
entries committed in order; the final evidence hash was
`68915ba57a35e92d50003492030e48ef5c27394d2842b0442b0a783725547945`;
and stderr remained empty. Peak sampled cgroup memory was 66,367,488 bytes
(63.29 MiB). After the initial allocation ramp and collection, sampled current
memory stayed between 47,095,808 and 52,887,552 bytes, with a 50,786,304-byte
median. The website remained HTTP `200`, all existing VPN container identities
and start times were unchanged, and final unit/process/path cleanup was exact.

A preliminary `MemoryHigh=48 MiB` run produced sustained reclaim pressure and
cadence degradation, so that threshold is rejected. Because the natural peak
left less than 1 MiB beneath a 64 MiB hard ceiling, Pass K does not authorize a
64 MiB production budget. A future supervisor contract must begin at a
fail-closed 128 MiB ceiling; any tighter claim, including 96 MiB, requires a
separate longer-duration soak. This evidence permits that supervisor contract
to be evaluated separately. It does not authorize installation, durable runner
identity, external anchoring, credentials, account reads, leases, remote
effects, tags, or Releases.

### 11.19 Pass L: Fail-Closed Public-Shadow Supervisor Contract

Pass L defines one executable systemd contract for the existing public-only
runner without installing or enabling it. Systemd owns only process lifecycle
and resource containment. The existing probe remains the sole composition
root, and `BingxFuturesShadowStreamStore` remains the sole evidence continuity
owner. No scheduler, stream, credential, account, decision, or effect owner is
duplicated.

The unit starts one bounded 288-cycle batch at a fixed 300-second cadence. A
successful batch may restart after 60 seconds; any provider, validation,
append, cadence, timeout, signal, or OOM failure remains stopped. Start limits
also stop accidental rapid successful exits. `Restart=always`,
`Restart=on-failure`, internal retry, catch-up, and inferred success are
forbidden.

The runner seed is a runner-only evidence-signing identity. The probe accepts
it from exactly one source: the existing ephemeral environment boundary or one
absolute regular credential file. Ordinary files grant no group or other
permissions; the canonical protected systemd credential path accepts only the
exact root-owned `0440` delivery produced for `DynamicUser=`. The two sources
are mutually exclusive, and linked, relative, broadly readable, malformed, or
missing files fail before stream or network access. The
supervisor uses `LoadCredentialEncrypted=` plus `%d/runner-seed`; it contains no
seed, environment secret, Capsule material, or exchange credential.

The unit fixes `MemoryMax=128M`, `MemorySwapMax=0`, `TasksMax=16`, low CPU and
I/O weights, a 25-hour runtime ceiling, a dynamic user, a private 0700 state
directory, an empty capability set, read-only system/home boundaries, process
and kernel isolation, native system calls, bounded journal rate, and
`SocketBindDeny=any`. It permits only Unix, IPv4, and IPv6 client address
families needed for public HTTPS and DNS. Its exact symbol, plugin identity,
package digest, ABI, stream path, run count, and cadence are fixed rather than
loaded from a mutable environment file.

The existing trading parity gate semantically parses the unit and its exact
command, verifies the seed-file ingress and protected systemd credential mode
in the probe, and rejects independent mutations to restart policy, memory
ceiling, credential delivery, and listener denial. Focused Dart tests cover
valid ordinary/systemd delivery plus ambiguous, relative, linked, and
permissive negative cases. Debian systemd 257 accepted the unit
syntax; offline `systemd-analyze security` reported exposure `1.5 OK`. The only
exact-unit verify failure was the expected absence of the not-yet-installed
binary.

Pass L removes environment-secret supervisor designs, hidden failure retry,
unbounded memory/swap/tasks, and listener-capable service defaults from the
design space. It adds one justified process-lifecycle contract and no domain or
effect path. Artifact/unit bundling, atomic installation, credential creation,
enablement, boot persistence, exact-unit runtime smoke, external anchoring,
leases, account reads, remote effects, tags, and Releases remain separate and
unauthorized.

### 11.20 Pass M: Verifiable Bundle and Ephemeral Exact-Unit Install

Pass M extends the existing runner artifact owner rather than creating an
installer or deployment service. One bundle contains exactly the Linux runner,
the canonical systemd unit, and one ordered manifest. The manifest binds the
binary and unit SHA-256 values, source commit, dependency lock, target,
authority profile, atomic bundle destination, binary and unit paths, systemd
link path, encrypted credential path, and state directory. Unknown entries,
unit substitution, binary mutation, target drift, source drift, authority
markers, or alternate install paths fail verification.

The bundle directory is staged beside its final `/opt` destination and enters
that destination through one rename. The systemd unit is linked from that
immutable bundle only after every staged byte is verified. The smoke path
requires root, Linux x64, an exclusive host lock, and the complete absence of
all canonical bundle, unit-link, credential, state, and enablement paths. It
refuses to adopt, overwrite, back up, repair, or delete pre-existing host state.
This makes bundle publication atomic and leaves every later host mutation
non-enabled and safely removable; it does not claim a cross-filesystem
transaction that Linux cannot provide.

The exact checked-in unit receives one temporary runner-only signing seed via
`systemd-creds` and `LoadCredentialEncrypted=`. Plaintext seed bytes are piped
directly into encryption and are never written to a file or process
environment. The smoke starts the linked unit without `enable`, waits for the
first authenticated public-shadow evidence append, verifies zero restarts and
the fixed resource/network boundaries, then stops the unit, asks systemd to
clean its state, removes only paths created by this invocation, reloads systemd,
and proves that no canonical path or loaded unit remains.

Threats closed by this pass are binary/unit mix-and-match, manifest path
confusion, symlink or pre-existing-path adoption, concurrent install races,
plaintext credential persistence, accidental boot enablement, false success
before evidence append, and cleanup that silently leaves authority or service
state behind. Negative self-tests independently mutate unit bytes, install
paths, collision guards, enablement, and state cleanup. The existing parity
gate remains the sole review owner.

This pass proves only installation mechanics for the public-market shadow
runner. It creates no account read, exchange credential, Capsule authority,
mandate, lease, order/effect route, listener, persistent service, external
anchor, release artifact, tag, or Release. A persistent host identity and
boot-enabled observation service require a separate decision after this smoke
evidence is closed.

### 11.21 Pass N: Encrypted Identity Restart Continuity

Pass N strengthens the existing exact-unit smoke without adding an installer,
credential owner, stream, or supervisor. The same encrypted runner-only
credential and the same private systemd state directory must survive one
explicit stop/start boundary. The first process must append sequence `1`; the
second must append sequence `2` through the existing authenticated stream.
Sequence reset, repeated first evidence, missing credential, missing committed
identity, implicit supervisor restart, or cleanup residue fails the smoke.

The existing stream store remains the identity and evidence owner. Its
committed `runner_key_id` rejects a missing or foreign seed before the public
provider producer is invoked, while exact same-key restart continues the
sequence and predecessor chain. The artifact script only orchestrates evidence
for that existing contract; it does not define a second recovery mechanism.

This pass proves process-restart continuity, not durable production recovery.
Credential rotation, replacement after loss, boot enablement, persistent
installation, rollback-resistant external anchoring, account reads, leases,
exchange effects, tags, and Releases remain unauthorized. On the audited VPS,
host-root or offline-disk compromise remains outside this runner-only evidence
boundary and cannot be promoted into Capsule or trading authority.

### 11.22 Pass P: Persistent Disabled Install And Exact Uninstall

The existing artifact owner provides the only host installation lifecycle. It
may atomically persist the verified bundle, exact linked unit, encrypted
runner-only credential, and systemd-owned private state. A successful install
ends `disabled` and `inactive`; it never creates a boot target link and never
starts the runner implicitly.

Uninstall requires the exact verified bundle as its ownership anchor. Any
present binary, manifest, unit, link, credential, or state path must match its
canonical type and binding before deletion begins. The bundle is removed last,
so an interrupted uninstall remains retryable. Drift, symlink substitution,
foreign state, boot enablement, or a concurrent lifecycle operation fails
closed instead of deleting or adopting ambiguous host state.

The host smoke uses this same install and uninstall path, explicitly starts the
unit twice, verifies one stable `runner_key_id`, stops it, proves that identity
state remains while disabled, and then removes every canonical runner path.
Boot enablement, credential rotation or replacement, external anchoring,
account reads, leases, exchange effects, listeners, tags, and Releases remain
unauthorized.

### 11.23 Pass Q: Explicit Identity-Bound Activation

The existing artifact owner remains the only host lifecycle owner. An exact
persistent installation may first run while disabled only to commit and expose
its authenticated `runner_key_id`; this initialization must finish disabled
and inactive and must not create a boot target link. Repeating initialization
continues the same authenticated stream and cannot replace its identity.

Boot activation is a separate explicit operation. It requires the operator's
expected 64-character lowercase-hex `runner_key_id`, the exact verified bundle,
the exact linked unit, the encrypted runner-only credential, and the committed
identity. The unit starts while still disabled, produces authenticated evidence
after a pre-start journal cursor for that same identity, and only then may the
existing owner create the exact
`multi-user.target` enablement link. Missing or mismatched identity, bundle
drift, foreign paths, prior enablement, concurrent lifecycle activity, failed
startup, stale journal evidence, unexpected restart, or a different evidence key fails closed and
rolls the unit back to disabled and inactive.

Deactivation requires the same exact artifact and expected identity. It
removes boot enablement before stopping the process, preserves the encrypted
credential and authenticated stream for an exact later activation, and refuses
to adopt or disable an ambiguous installation. Interrupted deactivation is
retryable and never removes the canonical linked unit. Host reboot is not required as
evidence because the audited VPS carries unrelated production workloads; exact
target wiring plus active/inactive lifecycle evidence proves this boundary
without risking those workloads.

This pass authorizes only persistent public-market shadow observation. It does
not make remote evidence rollback-resistant and does not authorize Capsule or
exchange credentials, account reads, mandate delivery, leases, trading
decisions, orders, cancellation, reconciliation, listeners, tags, or Releases.

### 11.24 Pass R: Portable External Evidence Anchor

The existing artifact owner may atomically export exactly two files from the
installed public-shadow stream: the exact committed signed evidence bytes and
the Ed25519 public key whose SHA-256 is the operator-confirmed
`runner_key_id`. The output path must be absolute, new, and collision-free;
the host export remains explicitly untrusted until verified away from that
host. It does not define a second evidence format, receiver, transport, or
state owner.

The existing deterministic replay harness remains the sole semantic verifier.
It parses bounded canonical `trading-shadow-evidence-v1` bytes, authenticates
their suite and runner binding, accepts an exact retained replay or the exact
next sequence linked to the retained evidence hash, and rejects rollback,
sequence conflict, chain fork, malformed bytes, wrong identity, and invalid
signature. Rollback detection therefore depends on retaining an accepted
anchor outside the VPS; copying a first anchor alone is not a claim of host
integrity or historical completeness.

This pass only makes existing public observation evidence portable and
independently checkable. It grants no network listener, Capsule or exchange
credential, account read, mandate, lease, trading decision, order, cancel,
reconciliation, tag, or Release authority. Credential loss/rotation and remote
effects remain separate blocked product decisions.

## 12. Local Bounded Mandate Boundary

The normative mandate contract is section 5.3.3 of
`bingx_futures_trading_drone_spec_v1.md`. The local product proves that contract
before any headless-host pass: one Capsule-scoped operational owner, one
exchange-effect owner, exact account/symbol/mode/time/notional/risk/effect
bounds, explicit revocation, and fail-closed restart behavior. This section
does not duplicate those semantics and authorizes no Remote Runner or VPS.
