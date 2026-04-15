# User Lifetime Safety Pack

Use this checklist to validate the real-world path where a person uses one or two capsules for years.

Run it on the release candidate build.

## Scope

- [ ] Test includes one main capsule and one peer capsule (max two capsules in scope).
- [ ] Test starts from clean local state for this release candidate.

## Scenario 1: First Capsule Birth

- [ ] Create first capsule and verify app reaches normal starters/invitations/relationships screens.
- [ ] Close and relaunch app.
- [ ] Same capsule is selected and header counters remain stable.

## Scenario 2: First Relationship

- [ ] Create or recover second capsule.
- [ ] Send invitation from capsule A to capsule B.
- [ ] Accept on capsule B and verify relationship appears on both capsules after receive/switch.
- [ ] No self-invite artifacts appear as pending on sender.

## Scenario 3: Recovery On New Device Path

- [ ] Export backup for capsule A.
- [ ] On clean runtime (or clean machine/profile), recover capsule A using seed + backup.
- [ ] Recovered capsule shows the same ledger truth (starters, relationships, pending counts) as before recovery.

## Scenario 4: Update Truth Preservation

- [ ] Keep capsule data from previous build.
- [ ] Launch new build on same data.
- [ ] Same ledger reconstructs the same visible truth.
- [ ] Previously resolved invitations do not reappear as pending.
- [ ] Deleting a capsule in canonical storage does not get silently undone by legacy-container migration on next launch.

## Scenario 5: Long-Pending Invitation Stability

- [ ] Create one pending invitation and leave it unresolved.
- [ ] After restart/switch, invitation state is still coherent (no duplicate lineage or phantom pending rows).
- [ ] Timeout/burn behavior follows specification once terminal event is appended.
