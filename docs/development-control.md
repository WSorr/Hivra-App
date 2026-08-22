# Hivra Development Control

Status date: 2026-08-22
Current released baseline: commit `2a23411` (`v1.0.3-test16`, macOS and Android manual signoff recorded)
Current development focus: Hivra 1.x product completion. The Trading Drone has
proved one bounded live order and restart reconciliation, but it is not yet an
operational product. Remote public-shadow evidence now reproduces the full
market-only live decision and exposes its exact bounded `READY`/`BLOCKED`
market proposal rather than only a reduced verdict or opaque hash. A completed
bounded composition combines that authenticated proposal with one active
mandate and one fresh transient account-risk snapshot into a non-authorizing order
candidate. VPS/24/7 execution, exchange effects, plugin ABI, Core, Ledger, tag,
Release, and 2.0 runtime work remain blocked.
The candidate now has one fail-closed adapter into the existing exact-order
payload shape, but no admission is issued and no authority or effect is added.
Scheduling, leases, multi-symbol execution, Pair Consensus, AI authority,
withdrawal/transfer endpoints, release, and 2.0 work remain unauthorized.

## 1. Read This First

Before resuming work, answer four questions in this order:

| Question | Current answer | Authority |
| --- | --- | --- |
| What product rules cannot move? | The product axis, the three laws, local-first Capsule ownership, Ledger truth, and capability isolation. | `product-axis.md`, then `specification.md` |
| Which runtime is releasable? | Hivra 1.x on `main` is the sole production line. | `specification.md`, release checklists |
| What is the next 1.x step? | Select one observed user-facing failure that blocks the next complete Chat, Moltbook, or Trading journey. No implementation unit is currently selected. | This board and the relevant product contract |
| Is 2.0 implementation work allowed? | No. Completed V2-0/V2-1 design checkpoints authorize no production path; a later unit must be selected explicitly. | `architecture-v2-blueprint.md` |

Do not infer current work from chronological history in `roadmap.md`. It is a
frozen archive, not an active backlog or status source. Start from this table,
then open only the contract and tests for the selected product outcome.

## 2. Current Development Board

| Line | State | Current unit | Completion boundary | Next boundary |
| --- | --- | --- | --- | --- |
| **1.x maintained runtime** | Trading candidate adapter complete | One fresh intact candidate maps fail-closed into the existing exact-order payload with its hash bound as the intent identity. | No provider POST, scheduler, VPS activation, signed order admission, or effect is part of this unit. | No next unit is selected automatically; issuing the existing admission remains a separate decision. |
| **1.x release** | `v1.0.3-test16` published as test prerelease | The release and its evidence remain unchanged. | No next candidate or stable `1.0` claim is selected automatically. |
| **2.0 architecture** | `V2-0` and `V2-1 / passes A-E` complete; paused | No active 2.0 unit; runtime implementation remains unauthorized. | Resume only by an explicit later decision; do not infer Pass F. |
| **Platform toolchain** | T0 reverified | The pinned baseline remains canonical. | T1 requires a dedicated selected upgrade unit. |
| **Capsule AI Runtime** | Current remediation complete | The existing credential owner and one process lease remain canonical. | No second credential owner or AI-5 is selected. |
| **Future product tracks** | Parked | Durable intent and bounded delegation, AI trading advice, distributed backup, staking, and further Moltbook authority remain unselected. | Each requires its own approved contract and capability-closure decision. |

Unchecked boxes in reusable release/smoke checklists are execution templates,
not automatically active debt. Historical pass numbering creates no future
work and is not used for ordinary product defects.

## 3. The Only Two Work Lanes

```text
1.x product work
  reproduced user-facing failure or missing journey
  -> one bounded implementation unit in the existing owner
  -> regression test + gates
  -> focused manual smoke when risk requires it
  -> one implementation PR
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

At the beginning of a development session, state only:

1. **Outcome:** the observable user journey or failure being changed.
2. **Owner:** the existing capability/module that owns the decision or effect.
3. **Exit evidence:** the smallest automated and manual evidence that proves
   the outcome without a regression.

Before packaged manual smoke begins, follow the operator-selection rule in
`docs/checklists/manual-smoke.md`: stop and ask **"Hands or automatic?"**. Do
not start interactive actions until the person chooses who drives the UI.

Documentation follows semantic change, not implementation ceremony:

| Change type | Update |
| --- | --- |
| Current behavior, protocol, invariant changed | Update its existing normative contract in the implementation PR |
| Ordinary bug fixed without a contract change | Code, regression test, and evidence only; no documentation closure |
| Current product outcome or next decision changed materially | Update the board in this file in the implementation PR |
| 2.0 ownership / contract / migration proof | `architecture-v2-blueprint.md` in its explicitly selected design PR |
| Flutter/Rust/Android/macOS toolchain contract changed | `docs/platform-toolchain-evolution.md` and release evidence |
| Release readiness | The applicable release checklist and release evidence |

`roadmap.md` is a frozen historical archive. Routine fixes MUST NOT append to
it. A separate documentation-only status, closure, remediation, or checkpoint
PR MUST NOT follow an ordinary implementation PR. Git history, the merged PR,
tests, and manual evidence already record that history. Documentation-only PRs
remain valid for real specification, architecture, migration, research, or
release-document changes.

## 5. Decision Rules

- If a proposed feature does not have one named owner and public contract, it
  is `NEEDS_CONTRACT`, not implementation work.
- If it needs a new Core fact, event, or trust meaning, it is
  `NEEDS_PROTOCOL`, not a Flutter workaround.
- If the same intent can reach an external effect through two paths, stop and
  consolidate its lifecycle before adding behavior.
- If the task cannot state what old path is removed or sealed, it must not add
  a new abstraction.
- If a manual test exposes a discrepancy, preserve the reproduction in the
  issue or implementation PR and fix it through the existing owner.
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
2. `product-axis.md`
3. the relevant specification/architecture contract and focused tests

For 2.0 design, also read `architecture-v2-blueprint.md` and use the current
code only to inventory reality. Read `roadmap.md` only when historical evidence
is specifically needed.
