# Hivra Development Control

Status date: 2026-07-24
Current released baseline: `main` at `f18a490` (`v1.0.3-test13`, Android manual signoff recorded)

This is the short operational map for deciding what Hivra work is happening
now. It is not a second specification, backlog, or release record. It points
to the authoritative document for each kind of decision.

## 1. Read This First

Before resuming work, answer four questions in this order:

| Question | Current answer | Authority |
| --- | --- | --- |
| What product rules cannot move? | The product axis, the three laws, local-first Capsule ownership, Ledger truth, and capability isolation. | `product-axis.md`, then `specification.md` |
| Which runtime is releasable? | Hivra 1.x on `main` is the sole production line. | `specification.md`, release checklists |
| What is the next 1.x remediation pass? | `12.3 / pass 3`: cryptographically continuous ledger protocol. `5.1` remains the mandatory projection boundary before any new lifecycle UI or consensus semantics. | `roadmap.md`, `specification.md` |
| Is 2.0 implementation work allowed? | No. `V2-0` may inventory owners and generate architecture evidence only; it may not create a second production path. | `architecture-v2-blueprint.md` |

Do not start from the chronological history in `roadmap.md`. Start from this
table, then open only the linked authority for the selected work item.

## 2. Current Development Board

| Line | State | Current unit | Completion evidence | Next boundary |
| --- | --- | --- | --- | --- |
| **1.x maintained runtime** | Active | `12.3 / pass 3`: cryptographically continuous ledger. `5.1` is a cross-cutting projection blocker, not a reason to add another Flutter reducer. | Current release baseline is `f18a490`; automated gates and packaged macOS/Android smoke passed for `v1.0.3-test13`. The current delivery/identity commit is not a release candidate until fresh platform smoke is recorded. | Close pass 3, then move lifecycle readers to the canonical Core projection before event-scoped delivery records. Do not blend these with feature work or redesign. |
| **1.x release** | Released | `v1.0.3-test13` is the current test release on macOS and Android. | Tag, guarded GitHub release, clean worktree, platform signoff, and artifact evidence are recorded. | A commit is not automatically a release; the next release requires a new candidate and fresh signoff. |
| **2.0 architecture** | Design-only | `V2-0`: inventory capability owners, commands, facts, projections, effects, entrypoints, and forbidden dependency edges. | A reviewed ownership/dependency baseline, generated evidence, and closure verdicts, with no 2.0 runtime path in 1.x. | `V2-1` contracts only after V2-0 exit evidence; each later migration deletes or seals its 1.x path. |
| **Future product tracks** | Parked | AI trading advice, distributed backup drone, staking drone, Moltbook agent drone. | Their own approved contract and capability-closure result. | They do not preempt active 1.x integrity work. |

`12.3` is deliberately an ordered remediation program, not a grab bag. Its
remaining protocol and reliability passes are selected one at a time from
`roadmap.md`; no pass is considered complete merely because a screen appears to
work in one manual run.

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
