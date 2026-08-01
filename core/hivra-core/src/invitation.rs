use crate::event::EventKind;
use crate::event_payloads::{
    EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload, InvitationRejectedPayload,
    InvitationSentPayload, RejectReason,
};
use crate::ledger::Ledger;
use crate::primitives::SlotIndex;
use crate::slot::SlotLayout;
use crate::{PubKey, StarterId, StarterKind};
use alloc::vec::Vec;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InvitationStatus {
    Pending,
    Accepted {
        created_starter_id: StarterId,
        from_pubkey: PubKey,
    },
    Rejected {
        reason: RejectReason,
    },
    Expired,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InvitationDirection {
    Outgoing,
    Incoming,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InvitationRecord {
    pub invitation_id: [u8; 32],
    pub starter_id: StarterId,
    pub starter_kind_hint: Option<StarterKind>,
    pub peer_pubkey: PubKey,
    pub direction: InvitationDirection,
    pub offer_signer: PubKey,
    pub status: InvitationStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlannedStarterCreation {
    pub slot: SlotIndex,
    pub kind: StarterKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AcceptPlan {
    UseExistingStarter {
        relationship_starter_id: StarterId,
        created_starter: Option<PlannedStarterCreation>,
    },
    CreateStarterInEmptySlot {
        slot: SlotIndex,
        kind: StarterKind,
    },
    NoCapacity,
}

pub fn pending_invitations(ledger: &Ledger) -> Vec<InvitationRecord> {
    invitations_with_status(ledger)
        .into_iter()
        .filter(|invitation| invitation.status == InvitationStatus::Pending)
        .collect()
}

pub fn pending_invitation_count(ledger: &Ledger) -> usize {
    pending_invitations(ledger).len()
}

pub fn find_invitation(ledger: &Ledger, invitation_id: [u8; 32]) -> Option<InvitationRecord> {
    invitations_with_status(ledger)
        .into_iter()
        .find(|invitation| invitation.invitation_id == invitation_id)
}

pub fn find_invitation_by_direction(
    ledger: &Ledger,
    invitation_id: [u8; 32],
    direction: InvitationDirection,
) -> Option<InvitationRecord> {
    invitations_with_status(ledger)
        .into_iter()
        .find(|invitation| {
            invitation.invitation_id == invitation_id && invitation.direction == direction
        })
}

pub fn plan_accept_for_kind(ledger: &Ledger, slots: &SlotLayout, kind: StarterKind) -> AcceptPlan {
    let starter_kinds = active_starter_kinds(slots, ledger);
    let matching_starter_id = slots
        .entries_with_kinds(ledger)
        .iter()
        .find_map(|entry| (entry.starter_kind == Some(kind)).then_some(entry.state))
        .and_then(|state| match state {
            crate::slot::SlotState::Occupied(id) | crate::slot::SlotState::Locked(id) => Some(id),
            crate::slot::SlotState::Empty => None,
        });
    let empty_slot = slots.find_first_empty();

    if let Some(relationship_starter_id) = matching_starter_id {
        let created_starter = empty_slot.and_then(|slot| {
            first_missing_kind(&starter_kinds).map(|kind| PlannedStarterCreation { slot, kind })
        });

        return AcceptPlan::UseExistingStarter {
            relationship_starter_id,
            created_starter,
        };
    }

    if let Some(slot) = empty_slot {
        AcceptPlan::CreateStarterInEmptySlot { slot, kind }
    } else {
        AcceptPlan::NoCapacity
    }
}

pub fn invitations_with_status(ledger: &Ledger) -> Vec<InvitationRecord> {
    let mut invitations = Vec::new();

    for event in ledger.events() {
        match event.kind() {
            EventKind::InvitationSent | EventKind::InvitationReceived => {
                let Ok(payload) = InvitationSentPayload::from_bytes(event.payload()) else {
                    continue;
                };
                let direction = if event.kind() == EventKind::InvitationReceived {
                    InvitationDirection::Incoming
                } else {
                    InvitationDirection::Outgoing
                };
                if invitations
                    .iter()
                    .any(|record: &InvitationRecord| record.invitation_id == payload.invitation_id)
                {
                    continue;
                }
                invitations.push(InvitationRecord {
                    invitation_id: payload.invitation_id,
                    starter_id: payload.starter_id,
                    starter_kind_hint: invitation_starter_kind_hint(event.payload()),
                    peer_pubkey: if direction == InvitationDirection::Incoming {
                        *event.signer()
                    } else {
                        payload.to_pubkey
                    },
                    direction,
                    offer_signer: *event.signer(),
                    status: InvitationStatus::Pending,
                });
            }
            EventKind::InvitationAccepted
            | EventKind::InvitationRejected
            | EventKind::InvitationExpired => {
                let Some((invitation_id, terminal)) =
                    terminal_status(event.kind(), event.payload())
                else {
                    continue;
                };
                let Some(record) = invitations
                    .iter_mut()
                    .find(|record| record.invitation_id == invitation_id)
                else {
                    // A terminal before its offer is orphan history forever.
                    continue;
                };
                if terminal == InvitationStatus::Expired
                    && !valid_expiry_signer(ledger, record, event.signer())
                {
                    continue;
                }
                if record.status == InvitationStatus::Pending {
                    record.status = terminal;
                } else if record.direction == InvitationDirection::Incoming
                    && matches!(record.status, InvitationStatus::Accepted { .. })
                    && terminal == InvitationStatus::Expired
                {
                    // The original sender may revoke an incoming offer after a
                    // recipient-local optimistic acceptance.
                    record.status = InvitationStatus::Expired;
                }
            }
            _ => {}
        }
    }

    invitations
}

pub fn invitation_status(ledger: &Ledger, invitation_id: [u8; 32]) -> InvitationStatus {
    find_invitation(ledger, invitation_id)
        .map(|record| record.status)
        .unwrap_or(InvitationStatus::Pending)
}

fn terminal_status(kind: EventKind, bytes: &[u8]) -> Option<([u8; 32], InvitationStatus)> {
    match kind {
        EventKind::InvitationAccepted => {
            let payload = InvitationAcceptedPayload::from_bytes(bytes).ok()?;
            Some((
                payload.invitation_id,
                InvitationStatus::Accepted {
                    created_starter_id: payload.created_starter_id,
                    from_pubkey: payload.from_pubkey,
                },
            ))
        }
        EventKind::InvitationRejected => {
            let payload = InvitationRejectedPayload::from_bytes(bytes).ok()?;
            Some((
                payload.invitation_id,
                InvitationStatus::Rejected {
                    reason: payload.reason,
                },
            ))
        }
        EventKind::InvitationExpired => {
            let payload = InvitationExpiredPayload::from_bytes(bytes).ok()?;
            Some((payload.invitation_id, InvitationStatus::Expired))
        }
        _ => None,
    }
}

fn invitation_starter_kind_hint(bytes: &[u8]) -> Option<StarterKind> {
    let offset = match bytes.len() {
        97 => 96,
        129 | 161 | 225 => 128,
        _ => return None,
    };
    StarterKind::from_u8(bytes[offset])
}

fn valid_expiry_signer(ledger: &Ledger, record: &InvitationRecord, signer: &PubKey) -> bool {
    match record.direction {
        InvitationDirection::Outgoing => signer == ledger.owner(),
        InvitationDirection::Incoming => signer == &record.offer_signer,
    }
}

fn active_starter_kinds(slots: &SlotLayout, ledger: &Ledger) -> [bool; 5] {
    let mut kinds = [false; 5];

    for entry in slots.entries_with_kinds(ledger) {
        if let Some(kind) = entry.starter_kind {
            kinds[kind.to_byte() as usize] = true;
        }
    }

    kinds
}

fn first_missing_kind(active_kinds: &[bool; 5]) -> Option<StarterKind> {
    [
        StarterKind::Juice,
        StarterKind::Spark,
        StarterKind::Seed,
        StarterKind::Pulse,
        StarterKind::Kick,
    ]
    .into_iter()
    .find(|kind| !active_kinds[kind.to_byte() as usize])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::Event;
    use crate::event_payloads::StarterCreatedPayload;
    use crate::slot::SlotLayout;
    use crate::{Network, Signature, Timestamp};

    fn append_event(ledger: &mut Ledger, kind: EventKind, payload: &[u8], timestamp: u64) {
        let owner = *ledger.owner();
        append_event_with_signer(ledger, kind, payload, timestamp, owner);
    }

    fn append_event_with_signer(
        ledger: &mut Ledger,
        kind: EventKind,
        payload: &[u8],
        timestamp: u64,
        signer: PubKey,
    ) {
        ledger
            .append(Event::new(
                kind,
                payload.to_vec(),
                Timestamp::from(timestamp),
                Signature::from([0u8; 64]),
                signer,
            ))
            .expect("append succeeds");
    }

    fn starter_created(starter_byte: u8, kind: StarterKind) -> Vec<u8> {
        StarterCreatedPayload {
            starter_id: StarterId::from([starter_byte; 32]),
            nonce: [starter_byte; 32],
            kind,
            network: Network::Neste.to_byte(),
        }
        .to_bytes()
    }

    #[test]
    fn invitation_projection_tracks_pending_and_resolution() {
        let owner = PubKey::from([1u8; 32]);
        let peer = PubKey::from([2u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [9u8; 32],
                starter_id: StarterId::from([3u8; 32]),
                to_pubkey: peer,
                sender_root_pubkey: None,
            }
            .to_bytes(),
            1,
        );

        assert_eq!(pending_invitation_count(&ledger), 1);
        assert_eq!(
            invitation_status(&ledger, [9u8; 32]),
            InvitationStatus::Pending
        );

        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id: [9u8; 32],
                reason: RejectReason::Other,
            }
            .to_bytes(),
            2,
        );

        assert_eq!(pending_invitation_count(&ledger), 0);
        assert_eq!(
            invitation_status(&ledger, [9u8; 32]),
            InvitationStatus::Rejected {
                reason: RejectReason::Other,
            }
        );
    }

    #[test]
    fn golden_first_valid_terminal_wins() {
        let owner = PubKey::from([7u8; 32]);
        let peer = PubKey::from([8u8; 32]);
        let invitation_id = [42u8; 32];
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id,
                starter_id: StarterId::from([9u8; 32]),
                to_pubkey: peer,
                sender_root_pubkey: None,
            }
            .to_bytes(),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id,
                reason: RejectReason::EmptySlot,
            }
            .to_bytes(),
            2,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationAccepted,
            &InvitationAcceptedPayload {
                invitation_id,
                created_starter_id: StarterId::from([10u8; 32]),
                from_pubkey: peer,
                accepter_root_pubkey: None,
            }
            .to_bytes(),
            3,
        );

        assert_eq!(
            invitation_status(&ledger, invitation_id),
            InvitationStatus::Rejected {
                reason: RejectReason::EmptySlot,
            }
        );
    }

    #[test]
    fn golden_incoming_sender_revoke_supersedes_optimistic_acceptance() {
        let owner = PubKey::from([11u8; 32]);
        let peer = PubKey::from([12u8; 32]);
        let invitation_id = [43u8; 32];
        let mut ledger = Ledger::new(owner);

        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationReceived,
            &InvitationSentPayload {
                invitation_id,
                starter_id: StarterId::from([13u8; 32]),
                to_pubkey: owner,
                sender_root_pubkey: Some(peer),
            }
            .to_bytes(),
            1,
            peer,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationAccepted,
            &InvitationAcceptedPayload {
                invitation_id,
                created_starter_id: StarterId::from([14u8; 32]),
                from_pubkey: peer,
                accepter_root_pubkey: None,
            }
            .to_bytes(),
            2,
        );
        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationExpired,
            &InvitationExpiredPayload { invitation_id }.to_bytes(),
            3,
            peer,
        );

        assert_eq!(
            invitation_status(&ledger, invitation_id),
            InvitationStatus::Expired
        );
    }

    #[test]
    fn golden_wrong_signer_cannot_revoke_incoming_offer() {
        let owner = PubKey::from([21u8; 32]);
        let peer = PubKey::from([22u8; 32]);
        let attacker = PubKey::from([23u8; 32]);
        let invitation_id = [44u8; 32];
        let mut ledger = Ledger::new(owner);

        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationReceived,
            &InvitationSentPayload {
                invitation_id,
                starter_id: StarterId::from([24u8; 32]),
                to_pubkey: owner,
                sender_root_pubkey: Some(peer),
            }
            .to_bytes(),
            1,
            peer,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationAccepted,
            &InvitationAcceptedPayload {
                invitation_id,
                created_starter_id: StarterId::from([25u8; 32]),
                from_pubkey: owner,
                accepter_root_pubkey: None,
            }
            .to_bytes(),
            2,
        );
        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationExpired,
            &InvitationExpiredPayload { invitation_id }.to_bytes(),
            3,
            attacker,
        );

        assert!(matches!(
            invitation_status(&ledger, invitation_id),
            InvitationStatus::Accepted { .. }
        ));
    }

    #[test]
    fn golden_orphan_terminal_does_not_resolve_later_offer() {
        let owner = PubKey::from([31u8; 32]);
        let peer = PubKey::from([32u8; 32]);
        let invitation_id = [45u8; 32];
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id,
                reason: RejectReason::Other,
            }
            .to_bytes(),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id,
                starter_id: StarterId::from([33u8; 32]),
                to_pubkey: peer,
                sender_root_pubkey: Some(owner),
            }
            .to_bytes(),
            2,
        );

        assert_eq!(
            invitation_status(&ledger, invitation_id),
            InvitationStatus::Pending
        );
    }

    #[test]
    fn golden_offer_direction_and_peer_are_canonical() {
        let owner = PubKey::from([41u8; 32]);
        let outgoing_peer = PubKey::from([42u8; 32]);
        let incoming_peer = PubKey::from([43u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [46u8; 32],
                starter_id: StarterId::from([44u8; 32]),
                to_pubkey: outgoing_peer,
                sender_root_pubkey: Some(owner),
            }
            .to_bytes(),
            1,
        );
        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationReceived,
            &{
                let mut payload = InvitationSentPayload {
                    invitation_id: [47u8; 32],
                    starter_id: StarterId::from([45u8; 32]),
                    to_pubkey: owner,
                    sender_root_pubkey: Some(incoming_peer),
                }
                .to_bytes();
                payload.push(StarterKind::Pulse.to_byte());
                payload
            },
            2,
            incoming_peer,
        );

        let projected = invitations_with_status(&ledger);
        assert_eq!(projected.len(), 2);
        assert_eq!(projected[0].direction, InvitationDirection::Outgoing);
        assert_eq!(projected[0].peer_pubkey, outgoing_peer);
        assert_eq!(projected[1].direction, InvitationDirection::Incoming);
        assert_eq!(projected[1].peer_pubkey, incoming_peer);
        assert_eq!(projected[1].offer_signer, incoming_peer);
        assert_eq!(projected[1].starter_kind_hint, Some(StarterKind::Pulse));
    }

    #[test]
    fn golden_invitation_id_has_one_lifecycle_across_directions() {
        let owner = PubKey::from([51u8; 32]);
        let outgoing_peer = PubKey::from([52u8; 32]);
        let incoming_peer = PubKey::from([53u8; 32]);
        let invitation_id = [48u8; 32];
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id,
                starter_id: StarterId::from([54u8; 32]),
                to_pubkey: outgoing_peer,
                sender_root_pubkey: Some(owner),
            }
            .to_bytes(),
            1,
        );
        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationReceived,
            &InvitationSentPayload {
                invitation_id,
                starter_id: StarterId::from([55u8; 32]),
                to_pubkey: owner,
                sender_root_pubkey: Some(incoming_peer),
            }
            .to_bytes(),
            2,
            incoming_peer,
        );

        let projected = invitations_with_status(&ledger);
        assert_eq!(projected.len(), 1);
        assert_eq!(projected[0].direction, InvitationDirection::Outgoing);
        assert_eq!(projected[0].peer_pubkey, outgoing_peer);
    }

    #[test]
    fn accept_plan_prefers_existing_matching_starter() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(4, StarterKind::Seed),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(5, StarterKind::Juice),
            2,
        );

        let slots = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Seed),
            AcceptPlan::UseExistingStarter {
                relationship_starter_id: StarterId::from([4u8; 32]),
                created_starter: Some(PlannedStarterCreation {
                    slot: SlotIndex::new(2).unwrap(),
                    kind: StarterKind::Spark,
                }),
            }
        );
    }

    #[test]
    fn accept_plan_uses_empty_slot_when_kind_is_missing() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );

        let slots = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Kick),
            AcceptPlan::CreateStarterInEmptySlot {
                slot: SlotIndex::new(1).unwrap(),
                kind: StarterKind::Kick,
            }
        );
    }

    #[test]
    fn accept_plan_detects_full_capsule_without_matching_kind() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(2, StarterKind::Spark),
            2,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(3, StarterKind::Seed),
            3,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(4, StarterKind::Pulse),
            4,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(5, StarterKind::Kick),
            5,
        );

        let slots = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Juice),
            AcceptPlan::UseExistingStarter {
                relationship_starter_id: StarterId::from([1u8; 32]),
                created_starter: None,
            }
        );
        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Kick),
            AcceptPlan::UseExistingStarter {
                relationship_starter_id: StarterId::from([5u8; 32]),
                created_starter: None,
            }
        );
    }
}
