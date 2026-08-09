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

## Capsule Basics

- [ ] Create a new genesis capsule.
- [ ] Create or recover a second capsule.
- [ ] Switch between capsules successfully.
- [ ] Capsule selector shows expected summaries.
- [ ] Export a user-visible Capsule backup and confirm the JSON identifies
      `hivra.capsule_backup` version `2` without visible Ledger `owner` or
      `events` fields.
- [ ] Recover with the matching seed and encrypted backup; confirm owner and
      Ledger history match the source Capsule.
- [ ] Confirm a wrong seed or modified ciphertext fails without importing any
      Capsule, then confirm no `hivra-backup-share-*` directory remains after
      share success or cancellation.
- [ ] On Android, confirm a fresh install/profile starts without any Capsule
      restored by OS backup or device transfer; Capsule state appears only
      after explicit seed + authenticated v2 backup recovery.
- [ ] On Android, complete explicit recovery in a fresh secondary profile and
      confirm seed persistence uses that profile's app-private path.

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

## Trading Drone (Observability Gate)

- [ ] `situational` run produces deterministic decision envelope hash (`drone.decision.envelope`).
- [ ] `interactive` cycle on same fixture input produces matching decision hash (no drift).
- [ ] Risk-block path is exercised and logs `risk_blocked` with deterministic reason code.
- [ ] Retry path is exercised (transient failure) and execution envelope is written.
- [ ] Receipt path is visible (`drone.execution.envelope`) and hash is traceable in logs.
- [ ] Trading drone parity checklist is completed: `docs/checklists/trading-drone-spec-runtime-parity.md`.

## Moltbook Ambassador

- [ ] Moltbook release smoke checklist is completed: `docs/checklists/moltbook-release-smoke.md`.
- [ ] One semantic operation survives duplicate click, restart, timeout, and
      challenge handling without duplicate publication.
