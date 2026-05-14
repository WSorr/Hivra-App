# Manual Smoke Checklist

Use this checklist for interactive validation before or after a release build.

## Capsule Basics

- [ ] Create a new genesis capsule.
- [ ] Create or recover a second capsule.
- [ ] Switch between capsules successfully.
- [ ] Capsule selector shows expected summaries.

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
