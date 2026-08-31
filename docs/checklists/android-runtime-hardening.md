# Android Runtime Hardening Checklist

Use this checklist to validate Android runtime behavior against the same ledger-truth rules used on other platforms.

## Bootstrap

- [x] Runtime bootstrap source selection on Android matches ledger-first policy (`ledger` -> `backup` fallback).
- [x] Restart/reopen preserves active capsule selection and does not switch capsules unexpectedly.
- [x] Seed-to-capsule binding remains stable across app restart.

## Storage

- [x] Keystore-backed seed access is validated after cold restart.
- [x] Unavailable Keystore fails closed and does not create `capsule_seeds.json`
      (automated secure-storage failure regression).
- [ ] Any legacy plaintext seed file is migrated completely into Keystore and deleted.
- [x] Reinstall path does not silently reuse stale app-private seed state.
- [x] Backup import path reconstructs the same ledger truth as before reinstall.

## Transport Diagnostics

- [ ] Outbound relay write failures surface actionable diagnostics (not generic UI-only errors).
- [ ] Receive path diagnostics distinguish transport failure from projection/ledger failure.

## Parity

- [ ] Android invitation send/accept projections match macOS for the same ledger history.
- [ ] Android relationship break/re-invite projections match macOS for the same ledger history.

## Current Evidence

- 2026-08-01, commit `39ba870`, local Android tablet smoke build
  `versionCode=100000317`:
  - the pre-uninstall backup contained owner
    `5996bcbeb387...f39120d6e`, ledger `v74`, and 74 events;
  - uninstall/reinstall did not recover stale app-private state;
  - seed plus the selected backup reconstructed the same owner, ledger `v74`,
    head display `782013f5...0d12`, five starters, three relationships, and one
    pending invitation;
  - a cold restart preserved the same identity and projection;
  - Android document import opened at local Downloads and returned to Hivra
    without inheriting the prior OneDrive folder history.
- This is development smoke evidence, not packaged release signoff. Unchecked
  failure-path and cross-platform parity items remain release blockers.
