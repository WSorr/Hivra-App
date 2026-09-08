# Hivra Development Control

Status date: 2026-09-08

## Current State

- Maintained runtime: Hivra 1.x.
- Published prerelease: `v1.0.3-test19` at `dabeaa7`; exact macOS and Android
  artifacts have manual signoff.
- Current source baseline: manifest-bound plugin workspaces opened through one
  App Shell navigation path, with Chat UI, Moltbook lifecycle, and the local
  Trading intent route assigned to dedicated capability owners; Capsule
  Analyst is the sole in-app diagnostic AI surface.
- Trading Remote Runner acceptance remains complete at `b88a886`.
- The Trading workspace now derives the visible VPS instrument, mode, limits,
  and authority fingerprints from the verified retained signed session. Pause
  and resume reuse that exact session; an active session cannot be replaced by
  an accidental second Start action. Technical reconciliation records remain
  available on demand instead of flooding the primary product surface.
- Canonical Capsule-scoped BingX credentials are read without a redundant
  Keychain rewrite. Legacy split-key records migrate once into the existing
  credential owner and are removed, so opening Trading does not repeat the
  former read-then-write authorization cycle.
- Trading now separates VPS installation, bounded session authorization or
  resume, and destructive uninstall in the product surface. Local Trading does
  not need to be paused before VPS setup, does not stop an active VPS session,
  and no longer blocks resume of the same retained signed session.
- A user without a VPS can run the same canonical Trading cycle every five
  minutes while the Trading workspace stays open and the computer is awake.
  This local cadence and the VPS session are mutually exclusive; both delegate
  effects, claims, receipts, and reconciliation to the existing owners.
- Packaged macOS smoke proved one local live-authority cycle reached the
  canonical market decision and stopped without an effect when liquidity was
  blocked. A paused VPS session now settles elapsed signed slots as retained
  no-effect outcomes before continuing from the current slot; it neither
  catches up provider requests nor extends the signed session bounds.
- Trading entry, exact-effect identity, and restart reconciliation remain owned
  by the existing execution use case. BingX may replace a triggered order ID;
  terminal evidence is accepted only when the retained client order ID, account,
  symbol, and side remain exact. The original effect identity is preserved.
- A filled managed entry is no longer presented as the final trade result. The
  same owner now retains BingX `positionID`, reconciles an exact open or fully
  closed position, and keeps realized/net PnL across restart. Ambiguous or
  delayed provider evidence remains unresolved rather than guessed.
- Packaged macOS evidence confirms the executed DOGE effect reconciles from
  unresolved to filled after restart without creating or adopting another
  managed order. Provider-created protection and operator-modified orders remain
  exchange-only unless exact ownership evidence exists. Android is unverified.
- Hivra 2.0 remains design-only. No 2.0 runtime or UI implementation is
  authorized.

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
anything. Chat and consensus attestation resolve invitation root-to-transport
identity through the canonical invitation projection. Starter labels consume
the version-matched Core Capsule projection rather than replaying
`StarterCreated` events in Flutter. The local invitation remediation derives exact
offer and terminal references from that same versioned invitation projection;
the Capsule-scoped outbox remains the sole relay-retry owner.

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
closed without duplicating capability UI or runtime ownership. No runtime unit
beyond the selected Trading work is authorized. Secure seed access failures remain distinct from a missing
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
