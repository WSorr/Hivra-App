# Hivra Development Control

Status date: 2026-08-22
Current released baseline: commit `2a23411` (`v1.0.3-test16`, macOS and Android manual signoff recorded)
Current development focus: `1.x BingX Provider Contract Conformance + Minimal
Live Vertical` is active. Sanitized read-only evidence from the dedicated
futures subaccount established the current balance, contract-rule, empty
realized-PnL, empty-position, and empty-open-order response shapes. The existing
exchange adapter and execution/reconciliation lifecycle remain the sole owners.
Provider conformance and trigger-bound sizing are merged and green. A packaged
build then placed exactly one bounded live trigger order, retained the provider
identity, reconciled it while open, cancelled it through the existing
revalidation lifecycle, and restored the exact terminal claim after restart
without a duplicate provider effect. Protected PR `#182` closed the resulting
side-locked revalidation and prepared-label remediation at `657a482`. A later
packaged SOL run exposed a separate freshness defect: the same executable
liquidity event was rejected after a later closed bar and an approximately
0.00023% zone-boundary adjustment. Stable-event freshness is merged and green
at `1eccd22`: it keeps exact event, side, anchor, lifecycle, and monotonic-time
binding while allowing at most 1 bp of derived boundary drift, and mandate
re-authorization clears the previous prepared intent. Packaged smoke then found
that a blocked SOL zone-conflict decision still populated executable pending-
zone fields. The active bounded UI remediation projects those fields only for a
prepared executable decision and otherwise retains only the blocking notice.
Until then the Trading Drone is not operational and VPS/24/7 execution remains
blocked. No plugin ABI, Core, Ledger, tag, or Release is authorized.
Scheduling, leases, multi-symbol execution, Pair Consensus, AI authority,
withdrawal/transfer endpoints, release, and 2.0 work remain unauthorized.

## 1. Read This First

Before resuming work, answer four questions in this order:

| Question | Current answer | Authority |
| --- | --- | --- |
| What product rules cannot move? | The product axis, the three laws, local-first Capsule ownership, Ledger truth, and capability isolation. | `product-axis.md`, then `specification.md` |
| Which runtime is releasable? | Hivra 1.x on `main` is the sole production line. | `specification.md`, release checklists |
| What is the next 1.x step? | Complete the bounded Trading blocked-zone projection remediation through protected gates. Do not alter the existing live order, repeat the proven live effect, or start VPS/24/7 execution. | This board; detailed history remains in `roadmap.md` |
| Is 2.0 implementation work allowed? | No. Completed V2-0/V2-1 design checkpoints authorize no production path; a later unit must be selected explicitly. | `architecture-v2-blueprint.md` |

Do not infer current work from chronological history in `roadmap.md`. Start
from this table, then open only the linked authority for the selected unit.

## 2. Current Development Board

| Line | State | Current unit | Completion boundary | Next boundary |
| --- | --- | --- | --- | --- |
| **1.x maintained runtime** | Trading blocked-zone projection remediation active | The existing Trading screen remains the sole projection owner and may display executable order fields only for a prepared decision whose `canPrepareIntent` flag is true. | Provider conformance, trigger sizing, one packaged live effect, restart restoration, side-locked revalidation, prepared-label remediation, and stable-event freshness are proven. | Merge the UI projection regression through protected gates; VPS, scheduler, release, and any additional effect remain blocked. |
| **1.x release** | `v1.0.3-test16` published as test prerelease | The release and its evidence remain unchanged. | No next candidate or stable `1.0` claim is selected automatically. |
| **2.0 architecture** | `V2-0` and `V2-1 / passes A-E` complete; paused | No active 2.0 unit; runtime implementation remains unauthorized. | Resume only by an explicit later decision; do not infer Pass F. |
| **Platform toolchain** | T0 reverified | The pinned baseline remains canonical. | T1 requires a dedicated selected upgrade unit. |
| **Capsule AI Runtime** | Current remediation complete | The existing credential owner and one process lease remain canonical. | No second credential owner or AI-5 is selected. |
| **Future product tracks** | Parked | Durable intent and bounded delegation, AI trading advice, distributed backup, staking, and further Moltbook authority remain unselected. | Each requires its own approved contract and capability-closure decision. |

`12.3` passes 1-18 are complete. Any later transport remediation requires a
new named finding and bounded pass; no pass is inferred from one manual run.
Unchecked boxes in reusable release/smoke checklists are execution templates,
not automatically active debt.

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

Before packaged manual smoke begins, follow the operator-selection rule in
`docs/checklists/manual-smoke.md`: stop and ask **"Hands or automatic?"**. Do
not start interactive actions until the person chooses who drives the UI.

At the end of a meaningful pass, update only the source that owns its status:

| Change type | Update |
| --- | --- |
| Current behavior, protocol, invariant | `specification.md` and, if user-visible, `hivra-conceptual-model.md` |
| Engineering history and debt | `roadmap.md` |
| Current unit and next decision | The board in this file |
| 2.0 ownership / contract / migration proof | `architecture-v2-blueprint.md` and the board in this file |
| Flutter/Rust/Android/macOS toolchain update | `docs/platform-toolchain-evolution.md`, the roadmap, and release evidence |
| Release readiness | The applicable release checklist and release evidence |

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
forgetting the product's hard rules.
