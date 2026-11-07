# Device Migration Checklist

Use this checklist when validating restore, recovery, and first launch on a different Mac.

## Fresh Machine Setup

- [ ] Install the app on a machine that does not already contain local capsule state.
- [ ] Confirm app launches to expected first-run or selection flow.

## Identity From Seed

- [ ] Derive Capsule identity using the seed phrase and compatible derivation.
- [ ] Derived pubkey matches the expected Capsule identity.
- [ ] Do not present seed-only identity recovery as restoration of unavailable
      signed history or relationships; use the authenticated Ledger backup below.

## Restore by Backup

- [ ] Import an authenticated backup using the matching seed; reject wrong-seed
      and modified envelopes without changing existing Capsule data.
- [ ] Imported capsule dir is created under the correct pubkey.
- [ ] Index entry and local seed storage match the restored Capsule.
- [ ] New Core-only v3 backups restore Ledger/history/relationships and Capsule
      type/network metadata, with no application content, installed ZIPs,
      checkpoints or service credentials. Reinstall/reconnect normally.
- [ ] Distinguish read-only legacy full-state import from the new export scope;
      the maintained format belongs to `../specification.md`.

## Launch Receive Safety

- [ ] Local ledger is imported before transport receive runs.
- [ ] Old resolved invitations do not reappear as pending.
- [ ] Existing relationships remain visible after first launch receive.
- [ ] Existing starters remain visible after first launch receive.
- [ ] Reacquire operational pair attestations through the existing peer exchange.
      An unavailable peer may block a pair action without erasing relationship
      truth or silently granting authority.

## Cross-Device Truth

- [ ] Sender-side accepted relationships still appear after restore.
- [ ] Recipient-side accepted relationships still appear after restore.
- [ ] Break events remain reflected after restore.
- [ ] Reverse-direction invitations still work after restore.

