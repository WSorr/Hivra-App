# Hivra Development Control

Status date: 2026-08-31

## Current State

- Maintained runtime: Hivra 1.x.
- Published prerelease: `v1.0.3-test18` at `9cd70cc`; exact macOS and Android
  artifacts have manual signoff.
- Current source baseline: manifest-bound plugin workspaces opened through one
  App Shell navigation path, with Chat UI, Moltbook lifecycle, and the local
  Trading intent route assigned to dedicated capability owners; Capsule
  Analyst is the sole in-app diagnostic AI surface.
- Trading Remote Runner acceptance remains complete at `b88a886`.
- Hivra 2.0 remains design-only. No 2.0 runtime or UI implementation is
  authorized.
- Current selected runtime unit: none. Manifest-driven activation and Chat,
  Moltbook, and Trading capability ownership are complete.

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

Plugin workspaces are activated by the installed package's exact manifest
profile rather than product-id routing. The App Shell owns the single workspace
navigation decision; the generic Plugins screen owns package/catalog UI and
cannot construct product screens or a second runtime module. The direct
Trading route and the legacy Settings plugin route are sealed, so a workspace
cannot bypass package installation.

Chat remains pair-consensus-bound: the capability screen calls the existing
runtime module, which ensures attestation and passes through the canonical host
consensus guard before the existing delivery owner can send or acknowledge
anything.

Moltbook owns its observation, AI proposal, publication, receipt,
reconciliation, and restart lifecycle in one capability module. New Moltbook
configurations default to one foreground session catch-up; leaving the active
Capsule runtime stops that trigger and clears its process-scoped AI unlock.
Existing saved trigger choices remain unchanged. Trading now
prepares pending liquidity-zone intents through one Capsule-local cycle and
reuses the accepted execution, reconciliation, and Remote Runner owners.
Unavailable equity, realized PnL, or position evidence remains absent and
blocks both test and live execution before the risk governor. The
former peer-selected intent route, Chat signal inbox, and Trading-side Pair
Consensus dependencies are removed. The thin App Shell navigation boundary is
closed without duplicating capability UI or runtime ownership. No next runtime
unit is selected. Secure seed access failures remain distinct from a missing
seed and cannot open the recovery path; irreversible Capsule deletion verifies
the active native seed, Capsule-scoped secure seed, and known legacy seed
locations before removing local history. A plugin ABI change, universal agent
runtime, new Core fact, V2 UI, release, VPS mutation, or live financial effect
requires a separate decision.

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
