# Hivra Engineering Instructions

These instructions apply to every change in this repository. Read the actual
Git state, `docs/product-axis.md`, and `docs/development-control.md` before
selecting work.

## Model Before Mechanism

Derive a change from the person's ownership and the object's possible behavior.
Use the model-first workflow in `docs/development-control.md`: establish states,
transitions, invariants, authority and boundaries before choosing a mechanism,
library or familiar application pattern. Current code is evidence, not proof
that its restrictions are necessary. Compare upstream implementations after
forming the model; reuse their mechanisms without importing their ownership,
account, synchronization or lifecycle assumptions.

Ask what the person gains and retains when the application, package, model,
provider or device changes. Distinguish owner choices, delegated permissions,
Core invariants, external-system constraints and current implementation limits.
A restriction must protect a named property at its canonical boundary; neither
"security" nor "usual practice" alone justifies it. The existing truth, secret,
financial and effect boundaries remain binding until an authorized replacement
preserves their guarantees. Do not add a framework or report to enforce this.

## Product And Complexity

Hivra optimizes for product capability per unit of structural complexity.
Green tests do not justify architectural growth.
An implemented component is not a completed product journey.

1. **One effect, one use case, one owner.** Different inputs that produce the
   same state change or external effect must converge before execution.
2. **Reuse before adding.** Before adding a file, service, DTO, command, gate,
   schema, compatibility path, or document, find the canonical owner and first
   consider merging, deleting, or simplifying.
3. **No parallel truth.** Ledger owns historical facts. Canonical projections
   own current state. UI, plugins, transports, and adapters must not replay or
   reinterpret domain truth independently.
4. **Dependencies stay downward.** Do not introduce pass-through DTOs, shadow
   owners, duplicate reducers, alternate lifecycle paths, or upward imports.
5. **Replace in the same pass.** A replacement must remove or seal the path it
   supersedes. Compatibility code requires an explicit removal condition.
6. **Product outcome is mandatory.** A pass must improve a user-visible
   capability, close a concrete security/correctness defect, or measurably
   reduce complexity. Process machinery alone is not a product outcome.
   Distinguish a repaired application journey from a completed architectural
   debt; a working reference plugin does not establish a reusable runtime ability.
7. **Prefer impossible states over more guards.** Preserve fail-closed security
   at the isolation and owner-authorization boundary. Do not duplicate package
   business rules in the host as additional safety policy. Existing financial
   guarantees remain enforced until their replacement is explicitly implemented
   and its changed guarantees are visible to the owner.
8. **Tests enforce semantics.** Do not bind gates to incidental filenames,
   source line positions, exact prose, or method placement.
9. **Documentation has one owner per fact.** Update an existing canonical
   document instead of creating implementation diaries or pass narratives.
10. **V2 is design-only until explicitly activated.** Only reference-grade 1.x
    mechanisms may inform V2; do not copy temporary 1.x structure into it.
11. **Design for package replacement before implementation.** Within supported
    capabilities, a package must be replaceable without rebuilding Capsule.
    Capsule owns identity, authority and relationships; isolated packages own
    product capabilities. Service protocols, response interpretation, strategy,
    workflow, reconciliation and private state belong to the package. The host
    enforces owner-granted access and supplies network/crypto execution, secret
    application, scheduling and optional opaque storage. It does not become a
    second product controller. A new service using supported primitives must
    not require a host adapter; a genuinely missing system primitive may extend
    the common contract. See `docs/plugins/plugin_host_api_v1.md` for the target
    boundary and the implemented v1 differences.
    A compatible model version or package presentation is not by itself a new
    host capability; product policy stays with the owner/package.

## Change Discipline

When selecting a debt, read its accepted product scope in
`docs/development-control.md`. Preserve its stated retention, allowed data loss,
reconnection behavior and non-goals through implementation and acceptance.
Tests, libraries and current code must not silently add archival, migration,
synchronization or approval requirements. A real contradiction reopens the
product decision explicitly; it does not justify an unannounced larger scope.

Before editing, trace the complete input-to-effect path and identify its
canonical owner, duplicates, compatibility paths, and existing tests. If the
proposed change adds more owners or execution paths than it removes, redesign
it before editing unless the user-visible capability cannot reuse an existing
owner.

For plugin work, define the host/package boundary before editing. Ask whether a
replacement package with a different private state shape can use the same host
contract. Verify that boundary with existing tests, including package replacement
or removal during an action; a working single-package journey alone is not proof
of replaceability. Do not add a framework, registry, or gate merely to enforce this.

Owner configuration and Start may authorize a complete autonomous workflow;
do not insert per-step product approvals into that grant. The host still checks
the requesting package, permitted service/credential scope, current grant and
sandbox boundary before dispatch. Stop/revocation semantics must be explicit;
revocation cannot undo requests already accepted by a service.

Before adding persistence, classify the data: Core fact, host permission,
package-owned irrecoverable decision, or reconstructible service observation.
Use the service for its account facts; do not build a host mirror or mandatory
effect-history archive. Keep only necessary package checkpoints through the
existing opaque store. Never remove unresolved delivery evidence before the
replacement can recover it without duplicating an external action.

Optimize for a small Core and a small reusable host, not a host implementation
of each installed product. Library conventions and client/server patterns do
not override these ownership rules. Complexity reduction must be demonstrated
by removed responsibilities and paths, not claimed as an unmeasured speedup.

For product work, state the user journey, its observable end result, and the
evidence that would prove it works on the supported runtime. Implement and
verify that journey end to end, including restart and failure recovery where
relevant. A green CI run, fixture, provider acceptance receipt, or running
service alone is not product acceptance. Do not split one journey into a chain
of status-only passes or release candidates; fix findings within the same
bounded outcome before selecting another.

Keep each implementation bounded to one product outcome. Do not perform
unrelated cleanup, invent speculative extension points, or create a new process
document for routine work.

After implementation, report only:

- Product outcome
- Added
- Removed or consolidated
- Owner/path count before and after
- Remaining risk and required manual smoke

Do not commit, push, tag, release, mutate VPS state, or begin another pass
without explicit approval. Before manual smoke, ask exactly: `Hands or automatic?`
