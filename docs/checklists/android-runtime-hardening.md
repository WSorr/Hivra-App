# Android Runtime Hardening Checklist

Use this checklist to validate Android runtime behavior against the same ledger-truth rules used on other platforms.

## Bootstrap

- [ ] Runtime bootstrap source selection on Android matches ledger-first policy (`ledger` -> `backup` fallback).
- [ ] Restart/reopen preserves active capsule selection and does not switch capsules unexpectedly.
- [ ] Seed-to-capsule binding remains stable across app restart.

## Storage

- [ ] Keystore-backed seed access is validated after cold restart.
- [ ] Reinstall path does not silently reuse stale app-private seed state.
- [ ] Backup import path reconstructs the same ledger truth as before reinstall.

## Transport Diagnostics

- [ ] Outbound relay write failures surface actionable diagnostics (not generic UI-only errors).
- [ ] Receive path diagnostics distinguish transport failure from projection/ledger failure.

## Parity

- [ ] Android invitation send/accept projections match macOS for the same ledger history.
- [ ] Android relationship break/re-invite projections match macOS for the same ledger history.
