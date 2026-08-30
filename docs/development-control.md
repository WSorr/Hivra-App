# Hivra Development Control

Status date: 2026-08-30

## Current State

- Maintained runtime: Hivra 1.x.
- Published prerelease: `v1.0.3-test18` at `9cd70cc`; exact macOS and Android
  artifacts have manual signoff.
- Current source baseline: manifest-bound plugin workspace activation; Capsule
  Analyst is the sole in-app diagnostic AI surface.
- Trading Remote Runner acceptance remains complete at `b88a886`.
- Hivra 2.0 remains design-only. No 2.0 runtime or UI implementation is
  authorized.
- Current selected runtime unit: none. Manifest-driven plugin activation is
  complete.

## Product Direction

Hivra 1.x now converges from an application with embedded plugin products into
a Person Runtime with installable capabilities. The target boundary is defined
in `product-axis.md`:

```text
Core + Ledger
  -> Person Runtime API / Plugin Host
  -> installed Chat, Moltbook, and Trading capabilities
  -> thin App Shell
```

Plugin workspaces are now activated by the installed package's exact manifest
profile rather than product-id routing. The direct Trading workspace route was
removed, so a workspace cannot bypass package installation.

Chat, Moltbook, and Trading then migrate one vertical capability at a time.
Each pass reuses the existing delivery/effect owners and deletes the host logic
it replaces. A plugin ABI change, universal agent runtime, new Core fact, V2
UI, release, VPS mutation, or live financial effect requires a separate
decision.

## Authority

1. `product-axis.md` contains the three permanent laws and target runtime
   shape.
2. `specification.md` is normative for the maintained 1.x protocol.
3. A focused architecture or plugin contract owns its capability semantics.
4. This file owns only current state and the next decision boundary.
5. `roadmap.md` is a milestone index; Git, merged PRs, releases, tests, and
   evidence logs retain detailed history.

## Integration Boundary

`main` changes only through a pull request with the required `review-gates`
check. Repository validation and product release remain separate. No tag,
Release, packaged smoke, VPS change, or external effect is implied by a green
repository gate.
