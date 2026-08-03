# Hivra Development Control

Status date: 2026-08-03
Current released baseline: `main` at `9953b02` (`v1.0.3-test15`, macOS and Android manual signoff recorded)
Current development focus: `T0` is complete; select the next bounded debt item
from the synchronized documentation before editing. The repository-owned
baseline manifest, exact Rust toolchain/target pin, and fail-closed
static/full/self-test verifier passed all gates and fresh build `100000327`
macOS/Android artifact-layout and cold-start evidence without changing Flutter,
Rust, Android, Xcode, Core, Ledger, FFI, or runtime behavior. Release preflight,
CI, and both platform release checklists consume that one verification
contract. T1 or any other upgrade is not activated automatically.
Transactional serialized
plugin install/update/remove is complete; authenticated Nostr delivery uses
signed kind `9444` plus NIP-44 v2, while deprecated kind `4`/NIP-04 remains
isolated to guarded read-only compatibility input.

This is the short operational map for deciding what Hivra work is happening
now. It is not a second specification, backlog, or release record. It points
to the authoritative document for each kind of decision.

## 1. Read This First

Before resuming work, answer four questions in this order:

| Question | Current answer | Authority |
| --- | --- | --- |
| What product rules cannot move? | The product axis, the three laws, local-first Capsule ownership, Ledger truth, and capability isolation. | `product-axis.md`, then `specification.md` |
| Which runtime is releasable? | Hivra 1.x on `main` is the sole production line. | `specification.md`, release checklists |
| What is the next 1.x remediation step? | Select the next bounded debt item from a synchronized roadmap audit; do not infer T1 or any other upgrade from T0 completion. | `docs/platform-toolchain-evolution.md`, `docs/roadmap.md` |
| Is 2.0 implementation work allowed? | No. `V2-0` may inventory owners and generate architecture evidence only; it may not create a second production path. | `architecture-v2-blueprint.md` |

Do not start from the chronological history in `roadmap.md`. Start from this
table, then open only the linked authority for the selected work item.

## 2. Current Development Board

| Line | State | Current unit | Completion evidence | Next boundary |
| --- | --- | --- | --- | --- |
| **1.x maintained runtime** | Checkpoint complete | `12.3 / pass 18` bounded pair-attestation responses passed full gates and cross-platform cold-restart smoke. | Build `100000326`: Flutter `737/737`, Rust workspace and review gates pass; macOS schema v1→v2 with unchanged Ledger `105/62/119`; Android Ledger `v82`; repeated attestation receives store `0`. | Runtime remains unchanged while T0 closes release-environment reproducibility. |
| **1.x release** | Released | `v1.0.3-test15` is the current test release on macOS and Android. | Tag, guarded GitHub release, artifact hashes, and platform signoff are recorded. | The current Moltbook lifecycle/UI checkpoint is not a release; the next release requires a new candidate and fresh signoff. |
| **2.0 architecture** | Design-only | `V2-0`: inventory capability owners, commands, facts, projections, effects, entrypoints, and forbidden dependency edges. | A reviewed ownership/dependency baseline, generated evidence, and closure verdicts, with no 2.0 runtime path in 1.x. | `V2-1` contracts only after V2-0 exit evidence; each later migration deletes or seals its 1.x path. |
| **Platform toolchain** | Checkpoint complete | `T0`: one baseline manifest, exact Rust pin, and fail-closed verifier cover the Flutter/Dart, Rust, Android, and macOS matrix. | Build `100000327`: all gates pass; macOS universal and Android three-ABI layouts verified; both artifacts cold-start without fatal evidence. | Select any later toolchain unit explicitly; do not activate T1 by implication. |
| **Capsule AI Runtime** | 1.x convergence / 2.0 contract | 1.x has one process-scoped credential lease; existing AI consumers must migrate one at a time to one provider-independent inference port. 2.0 treats it as a first-class host capability outside Core. | Each pass deletes or seals one feature-local provider/credential/scheduler path; runtime, proposal-boundary, isolation, and hostile-input tests pass. | Freeze request/result contract and inventory remaining direct provider paths before another AI-enabled feature is added. |
| **Future product tracks** | Parked except for guarded Moltbook evolution | AI trading advice, distributed backup drone, and staking drone remain parked. Moltbook Observe/Assisted effects and a foreground bounded-reply experiment exist, but automatic modes are blocked by the canonical engagement lifecycle gates. | Their own approved contract and capability-closure result; Moltbook additionally follows `plugins/moltbook_engagement_lifecycle_v1.md`. | They do not preempt active 1.x integrity work. |

`12.3` is deliberately an ordered remediation program, not a grab bag. Its
remaining protocol and reliability passes are selected one at a time from
`roadmap.md`; no pass is considered complete merely because a screen appears to
work in one manual run.

### Ordered Tail

This is the current execution order, not a second backlog:

1. **P1 — bounded debt selection:** audit synchronized roadmap and architecture
   evidence, then name one owner, invariant, exit gate, and removal/sealing
   target before implementation. T1 is not selected.
2. **P1 — release decision:** only a named release candidate may trigger fresh
   macOS and Android packaged-artifact signoff.
3. **P2 — design and parked work:** `V2-0`, crypto-agility protocol design,
   dependency upgrades, AI trading advice, distributed backup, and staking
   remain non-runtime or parked until the P0 sequence permits selection.

Unchecked boxes in reusable release/smoke checklists are execution templates,
not automatically active debt. A checklist becomes active only for a named
candidate or selected pass recorded here and in `roadmap.md`.

## 3. The Only Two Work Lanes

```text
1.x maintenance
  reported failure or review finding
  -> one scoped remediation pass
  -> regression test + gates
  -> focused manual smoke when risk requires it
  -> commit
  -> optional release decision

2.0 design
  capability inventory or future requirement
  -> owner + public contract + dependency proof
  -> migration/removal target + compatibility decision
  -> design review
  -> no 1.x runtime code until the 2.0 exit rule permits it
```

A task must name exactly one primary lane. A 1.x fix may add a test or a gate
that helps 2.0 later; it must not add speculative v2 events, DTOs, services, or
parallel execution paths. A 2.0 design task may use 1.x code as evidence; it
must not change 1.x behavior merely to make a diagram look cleaner.

## 4. Session Protocol

At the beginning of a development session, record the following in the task
conversation before editing:

1. **Lane and item:** for example, `1.x / 12.3 pass 3` or `2.0 / V2-0`.
2. **Invariant:** the one product-axis invariant being strengthened.
3. **Owner:** the sole capability/module allowed to own the decision or effect.
4. **Exit evidence:** exact tests, gates, and manual smoke required.
5. **Removal/sealing:** the old path, ambiguity, or forbidden edge that will
   disappear or be made unreachable.

At the end of a meaningful pass, update only the source that owns its status:

| Change type | Update |
| --- | --- |
| Current behavior, protocol, invariant | `specification.md` and, if user-visible, `hivra-conceptual-model.md` |
| Engineering item state / next pass | `roadmap.md` and the board in this file |
| 2.0 ownership / contract / migration proof | `architecture-v2-blueprint.md` and the board in this file |
| Flutter/Rust/Android/macOS toolchain update | `docs/platform-toolchain-evolution.md`, the roadmap, and release evidence |
| Release readiness | the applicable release checklist and release evidence |

No status update means the work is not ready to be called complete.

## 5. Decision Rules

- If a proposed feature does not have one named owner and public contract, it
  is `NEEDS_CONTRACT`, not implementation work.
- If it needs a new Core fact, event, or trust meaning, it is
  `NEEDS_PROTOCOL`, not a Flutter workaround.
- If the same intent can reach an external effect through two paths, stop and
  consolidate its lifecycle before adding behavior.
- If the task cannot state what old path is removed or sealed, it must not add
  a new abstraction.
- If a manual test exposes a discrepancy, record the reproduction and route it
  into one active 1.x remediation pass rather than creating an untracked fix.
- If a task is not needed for the next 1.x release and changes ownership or
  contracts, it belongs in the 2.0 design line first.

## 6. Practical Reading Set

For a normal 1.x repair, read only:

1. `development-control.md`
2. the relevant `roadmap.md` item
3. `product-axis.md`
4. the relevant specification/architecture contract and focused tests

For 2.0 design, replace item 2 with `architecture-v2-blueprint.md` and use the
current code only to inventory reality. This keeps the context small without
forgetting the product's hard rules. `V2-0` may start once the current baseline
and ordered 1.x debt are reflected consistently in this document and the
roadmap; it remains design evidence only until the blueprint exit criteria are
satisfied.
