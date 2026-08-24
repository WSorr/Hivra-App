# Hivra Engineering Instructions

These instructions apply to every change in this repository. Read the actual
Git state and `docs/development-control.md` before selecting work.

## Product And Complexity

Hivra optimizes for product capability per unit of structural complexity.
Green tests do not justify architectural growth.

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
7. **Prefer impossible states over more guards.** Preserve fail-closed security
   and financial boundaries, but simplify the model when that can eliminate an
   invalid state or execution path.
8. **Tests enforce semantics.** Do not bind gates to incidental filenames,
   source line positions, exact prose, or method placement.
9. **Documentation has one owner per fact.** Update an existing canonical
   document instead of creating implementation diaries or pass narratives.
10. **V2 is design-only until explicitly activated.** Only reference-grade 1.x
    mechanisms may inform V2; do not copy temporary 1.x structure into it.

## Change Discipline

Before editing, trace the complete input-to-effect path and identify its
canonical owner, duplicates, compatibility paths, and existing tests. If the
proposed change adds more owners or execution paths than it removes, redesign
it before editing unless the user-visible capability cannot reuse an existing
owner.

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

