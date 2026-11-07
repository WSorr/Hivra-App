# Manual Smoke Checklist

Use this checklist for interactive validation after packaging and before GitHub
release publication. Automated preflight and deterministic fixtures do not
replace this manual smoke pass.

## Choose The Operator

After the exact packaged artifacts are ready and before the first interactive
step, the agent MUST stop and ask the person exactly: **"Hands or automatic?"**
The agent must not infer the answer from a connected device, an open app, or a
prior smoke pass.

- **Hands:** the person drives the UI. The agent may prepare and launch the
  exact artifact, watch terminal/device logs, identify the next high-signal
  action, and record evidence. It must not click through the scenario itself.
- **Automatic:** the agent may drive the scenario with available tools. The
  person handles only credentials, OS security prompts, physical-device
  approvals, and actions that tooling cannot perform safely.

The selected mode applies to the current smoke pass until the person changes
it explicitly. Changing operator does not reuse evidence from a different
artifact or source commit. Record the mode in the task conversation before
continuing.

After completing this checklist, record the result in:

```bash
docs/checklists/release-manual-signoff-log.md
```

Use the approved Capsule/data scope; this checklist does not itself authorize
extra test Capsules, backups, emulators or changes to working owner data. Record
which stages are actually in scope under the existing release policy. For
Android, follow the required matrix in `release-android.md`; a connected tablet
is not required and physical-device evidence must name its actual API/ABI.

## Capsule Basics

- [ ] Create a new genesis capsule.
- [ ] Create or recover a second capsule.
- [ ] Switch between capsules successfully.
- [ ] Capsule selector shows expected summaries.
- [ ] Export a user-visible Capsule backup and confirm the JSON identifies
      `hivra.capsule_backup` version `3` without visible Ledger `owner` or
      `events` fields.
- [ ] On Android, Save Backup opens the system document-creation dialog without
      requiring a Share receiver. Cancel leaves no saved-success claim; save
      creates a file that remains available after Hivra restarts and can be
      selected for authenticated recovery. Capsule selector Export Backup uses
      the same save flow.
- [ ] Confirm saved/shared names contain the public Capsule ID and UTC date.
- [ ] Confirm the new v3 payload contains Core Ledger/type/network metadata only:
      no Chat content, operational pair attestations, contact labels, delivery
      queues, opaque package state, installed ZIPs or vault credentials.
- [ ] Recover that backup into an approved empty destination; confirm identity,
      signed history and relationships, including restart. Reinstall/reconnect
      packages normally; no previous execution lease or application data resumes.
      Existing destination Capsule data must remain untouched on conflict.
- [ ] Separately verify local Chat and package-state retention across ordinary
      restart and package replacement with a different private state shape.
      This is local continuity, not new-backup recovery.
- [ ] Exercise an existing legacy full-state v3 fixture only when that read-only
      compatibility path is in scope. Do not generate a new full-state export or
      treat its retained operational data as a promise for Core-only backups.
- [ ] Recover with the matching seed and encrypted backup; confirm owner and
      Ledger history match the source Capsule.
- [ ] Confirm a wrong seed or modified ciphertext fails without importing any
      Capsule, then confirm no `hivra-backup-share-*` directory remains after
      share success or cancellation.
- [ ] On Android, confirm a fresh install/profile starts without any Capsule
      restored by OS backup or device transfer; Capsule state appears only
      after explicit seed + authenticated v2/v3 backup recovery.
- [ ] On Android, complete explicit recovery in a separate clean AVD userdata
      root and confirm seed persistence uses that runtime's app-private path.

## Invitation Flow

- [ ] Send invitation from capsule A to capsule B.
- [ ] Accept invitation on capsule B.
- [ ] Verify sender ledger records `InvitationSent`.
- [ ] Verify recipient ledger records `InvitationReceived`.
- [ ] Verify recipient ledger records `InvitationAccepted`.
- [ ] Verify relationship appears on both sides after receive/switch completes.

## Relationship Flow

- [ ] Break relationship from one side.
- [ ] Verify `RelationshipBroken` is recorded locally.
- [ ] Verify peer receives `RelationshipBroken`.
- [ ] Re-invite after break.
- [ ] Re-accept after break.
- [ ] Reverse direction: send invitation from the other capsule back.

## Starter Rules

- [ ] Recipient generates a starter only on `accept`.
- [ ] New starter uses an empty slot.
- [ ] If the same starter kind already exists, recipient gets a missing kind when possible.
- [ ] Header relationship count reflects unique peer keys, not raw relationship branches.

## Ledger Truth

- [ ] Screens match local ledger projections.
- [ ] Old resolved invitations do not resurrect as pending after launch receive.
- [ ] Switching capsules does not mix ledgers.

## Moltbook Ambassador

- [ ] Optional: complete the Moltbook smoke checklist when live access is
      available; otherwise record `N/A` in the release signoff row.
- [ ] When live access is available, one semantic operation survives duplicate
      click, restart, timeout, and challenge handling without duplicate
      publication. When it is unavailable, verify visible deferral with no
      provider effect and record `N/A` with the reason.
