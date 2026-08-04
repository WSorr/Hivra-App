# Hivra Development Control

Status date: 2026-08-04
Current released baseline: `main` at `9953b02` (`v1.0.3-test15`, macOS and Android manual signoff recorded)
Current development focus: `V2-1 / pass C`, design-only Capsule continuity
export contract. V2-0 passes A-E completed one repository ownership registry,
deterministic
current-architecture evidence, owner discovery, explicit UI/Flutter-FFI
surface mappings, bounded identity-family decomposition, exit audit, and
fail-closed gates; they changed no runtime path. Pass A completed exact
proof/request binding, deterministic operation identity, idempotent replay,
standard schema validation, and fail-closed blueprint ownership. Pass B closed
one Starter inventory owner, deterministic Genesis seed plan, atomic birth
boundary, and current-view contract. Post-Pass B consolidation separated
design completion from production-path closure and selected only continuity
export intent/result/evidence semantics for Pass C. Recovery protocol, a new
backup wire format, and runtime implementation remain unauthorized. The post-AI-4 audit found no active 1.x integrity
finding: Capsule AI Runtime convergence is complete, feature-owned provider
dispatch and credential reads remain zero, and the full T0 environment verifier
matches every repository pin. No AI-5, release candidate, T1, or other runtime
upgrade is implied.
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
| What is the next 1.x remediation step? | No active 1.x remediation finding is selected. A new runtime pass requires a named failure or review finding. | `docs/roadmap.md`, applicable architecture contract |
| Is 2.0 implementation work allowed? | No. Completed V2-0/V2-1 design checkpoints authorize no production path; a later unit must be selected explicitly. | `architecture-v2-blueprint.md` |

Do not start from the chronological history in `roadmap.md`. Start from this
table, then open only the linked authority for the selected work item.

## 2. Current Development Board

| Line | State | Current unit | Completion evidence | Next boundary |
| --- | --- | --- | --- | --- |
| **1.x maintained runtime** | Checkpoint complete; no active finding | `12.3 / pass 18` and `12.5 / AI-4` are complete; no later remediation is inferred. | Latest build `100000331`: Flutter `760/760`, Rust workspace and review gates pass; macOS universal and Android three-ABI artifacts cold-start without fatal evidence. | Select a new runtime pass only from a named failure or review finding. |
| **1.x release** | Released | `v1.0.3-test15` is the current test release on macOS and Android. | Tag, guarded GitHub release, artifact hashes, and platform signoff are recorded. | The current Moltbook lifecycle/UI checkpoint is not a release; the next release requires a new candidate and fresh signoff. |
| **2.0 architecture** | `V2-0` and `V2-1 / passes A-C` complete; no next pass selected | Capsule continuity export now has one design-only intent/result/evidence contract above existing codec/filesystem adapters; runtime implementation remains unauthorized. | Schema, semantic vectors, and negative mutations bind exact snapshot, authority, replay, reviewed encrypted profile, and artifact evidence without adding a runtime path. | Run a short consolidation decision before selecting another contract; do not infer recovery, runtime binding, or a second backup format from Pass C completion. |
| **Platform toolchain** | T0 reverified | One baseline manifest, exact Rust pin, and fail-closed verifier cover the Flutter/Dart, Rust, Android, and macOS matrix. | Full verification on 2026-08-04 matches every pin; only the documented simulator-discovery and host-evidence warnings remain outside macOS/Android packaging scope. | T1 remains unselected; select a dedicated upgrade unit only after V2-0/pass A or a release-blocking toolchain finding. |
| **Capsule AI Runtime** | AI-4 convergence complete | History Advisor, Developer Engineer, Capsule Analyst, and Moltbook use one canonical runtime; feature-owned dispatch and credential reads are zero. | Build `100000331`: focused AI/Moltbook/cycle regressions `53/53`, Flutter `760/760`, Rust workspace, analyze, and review gates pass; macOS universal and Android three-ABI artifacts cold-start without fatal evidence. | No AI-5. Re-audit the ordered debt tail before selecting another implementation unit. |
| **Future product tracks** | Parked except for guarded Moltbook evolution | AI trading advice, distributed backup drone, and staking drone remain parked. Moltbook Observe/Assisted effects and a foreground bounded-reply experiment exist, but automatic modes are blocked by the canonical engagement lifecycle gates. | Their own approved contract and capability-closure result; Moltbook additionally follows `plugins/moltbook_engagement_lifecycle_v1.md`. | They do not preempt active 1.x integrity work. |

`12.3` passes 1-18 are complete. Any later transport remediation requires a
new named finding and bounded pass; no pass is inferred merely because a screen
appears to work in one manual run.

### Ordered Tail

This is the current execution order, not a second backlog:

1. **P1 — post-Pass C consolidation decision:** verify that blueprint, schema,
   fixtures, validator, roadmap, and generated evidence have one owner per fact;
   select no later contract without a separately named ambiguity.
2. **P1 — release decision:** only a named release candidate may trigger fresh
   macOS and Android packaged-artifact signoff.
3. **P2 — parked work:** crypto-agility protocol design, dependency upgrades,
   AI trading advice, distributed backup, and staking remain non-runtime or
   parked until the active design unit or a named release decision permits
   selection.

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

## 6. Repository Integration Gate

Repository integration and product release are separate processes.

- `.github/workflows/release-gates.yml` is the repository push/PR workflow
  displayed as `Hivra Repository Gates`. Its required GitHub status context is
  the stable job name `review-gates`.
- `main` accepts changes only through a pull request. Branch protection requires
  `review-gates` on the current head, requires the branch to be up to date,
  applies to administrators, and forbids force pushes and branch deletion.
- The repository workflow validates a commit; it does not create a tag, build a
  release candidate, publish artifacts, or replace the explicit release
  scripts, checklists, manual signoff, and guarded publication process.
- A green local `tools/review/review_all.sh` is necessary but not sufficient
  when CI, review gates, documentation integrity, toolchains, or generated and
  ignored paths change. Those changes must also pass from a clean detached
  checkout and then pass the GitHub `review-gates` check on the pushed branch.
- After every push, inspect the corresponding GitHub Actions run and wait for a
  terminal green result. Do not merge, push another pass, or call the commit
  complete while that run or the previous repository-gate run is red.
- Required checks, pull-request enforcement, administrator enforcement, and
  force-push/deletion restrictions have no repository-local bypass. If GitHub
  cannot enforce them, work stops at a documented external limitation rather
  than substituting a script that direct pushes can bypass.

## 7. Practical Reading Set

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
