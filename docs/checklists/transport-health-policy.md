# Transport Health Policy Checklist

Use this checklist before changing transport retry, receive, preflight, or
background delivery behavior.

## Boundary

- [ ] `hivra-transport` remains an adapter/provider module.
- [ ] Transport health policy lives above transport adapters and below UI
      screens.
- [ ] Core and Engine do not depend on transport health state.
- [ ] WASM drones request delivery through host APIs and do not receive direct
      transport/session/keychain access.

## Single Policy Surface

- [ ] Invitations, chat, pair attestations, relationship notifications, and
      trading signals use one shared health/backoff decision surface.
- [ ] A degraded network state is capsule-scoped, not global across unrelated
      capsules.
- [ ] Manual retry can bypass passive cooldown in a bounded, explicit way.
- [ ] A successful transport receive/send clears or relaxes the degraded state
      deterministically.

## Backoff And Circuit Breaker

- [ ] Consecutive timeout/fetch failures (`-1003`) increase cooldown.
- [ ] Cooldown prevents hidden background loops from repeatedly hitting the
      same failing transport.
- [ ] The user sees actionable degraded-transport status instead of silent
      spinner churn.
- [ ] Backoff state is diagnostic/retry policy only; it does not create ledger,
      invitation, relationship, consensus, chat, or trading truth.

## Ledger And Consensus Safety

- [ ] Ledger remains the source of confirmed domain truth.
- [ ] Pair consensus and attestation guards do not read transport-health state
      as authorization.
- [ ] Transport receipts still mean adapter acceptance only, not peer ledger
      confirmation.
- [ ] Stale transport replay cannot resurrect resolved local state.

## Verification

- [ ] Unit tests cover timeout streak -> cooldown -> manual retry -> success
      recovery.
- [ ] Tests cover that one capsule's degraded transport state does not suppress
      another capsule's eligible transport work.
- [ ] Tests cover all current consumers: invitations, chat, pair attestations,
      relationship notifications, and trading signals.
- [ ] Manual smoke includes unstable-network behavior with visible diagnostics
      and no endless spinner loop.

## Implementation Notes

- 2026-07-11 first slice:
  - `TransportHealthPolicyService` is application-level Flutter policy, not
    Core, Engine, or transport-adapter state.
  - Invitations, pair-attestation receive, chat receive, and trading-signal
    receive use shared capsule-scoped timeout cooldown.
  - Manual send paths record health outcomes but remain explicit user actions,
    not hidden background loops.
  - Relationship notifications and visible degraded-transport UI remain open.
