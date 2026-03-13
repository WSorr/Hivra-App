# Device Migration Checklist

Use this checklist when validating restore, recovery, and first launch on a different Mac.

## Fresh Machine Setup

- [ ] Install the app on a machine that does not already contain local capsule state.
- [ ] Confirm app launches to expected first-run or selection flow.

## Restore by Seed

- [ ] Restore capsule using seed phrase.
- [ ] Derived pubkey matches the expected capsule identity.
- [ ] Restored capsule opens with correct local ledger after import/bootstrap.

## Restore by Backup

- [ ] Import backup JSON.
- [ ] Imported capsule dir is created under the correct pubkey.
- [ ] Index entry and local seed storage match the restored capsule.

## Launch Receive Safety

- [ ] Local ledger is imported before transport receive runs.
- [ ] Old resolved invitations do not reappear as pending.
- [ ] Existing relationships remain visible after first launch receive.
- [ ] Existing starters remain visible after first launch receive.

## Cross-Device Truth

- [ ] Sender-side accepted relationships still appear after restore.
- [ ] Recipient-side accepted relationships still appear after restore.
- [ ] Break events remain reflected after restore.
- [ ] Reverse-direction invitations still work after restore.

