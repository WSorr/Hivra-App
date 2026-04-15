use crate::event::EventKind;
use crate::event_payloads::{
    EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload, InvitationRejectedPayload,
    InvitationSentPayload, StarterBurnedPayload, StarterCreatedPayload,
};
use crate::ledger::Ledger;
use crate::primitives::{SlotIndex, StarterId, StarterKind};
use alloc::vec::Vec;

/// Projected slot state derived from the ledger.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SlotState {
    Empty,
    Occupied(StarterId),
    Locked(StarterId),
}

/// Deterministic slot projection.
///
/// Slots are positions with capacity 5. Starter kind is not tied to a slot index.
/// Projection rules:
/// - `StarterCreated` occupies the first free slot.
/// - `StarterBurned` frees the matching slot.
/// - Pending outgoing invitations lock the corresponding starter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlotLayout {
    slots: [SlotState; 5],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SlotEntry {
    pub index: SlotIndex,
    pub state: SlotState,
    pub starter_kind: Option<StarterKind>,
}

impl SlotLayout {
    pub fn empty() -> Self {
        Self {
            slots: [
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
            ],
        }
    }

    pub fn from_ledger(ledger: &Ledger) -> Self {
        let mut layout = Self::empty();
        let owner = ledger.owner();
        let mut burned_starters: Vec<StarterId> = Vec::new();

        for event in ledger.events() {
            if event.signer() != owner {
                continue;
            }

            match event.kind() {
                EventKind::StarterCreated => {
                    if let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) {
                        if burned_starters
                            .iter()
                            .any(|burned_id| *burned_id == payload.starter_id)
                        {
                            continue;
                        }

                        if layout.contains_starter(payload.starter_id) {
                            continue;
                        }

                        layout.occupy_first_free(payload.starter_id);
                    }
                }
                EventKind::StarterBurned => {
                    if let Ok(payload) = StarterBurnedPayload::from_bytes(event.payload()) {
                        layout.free_starter(payload.starter_id);

                        if !burned_starters
                            .iter()
                            .any(|burned_id| *burned_id == payload.starter_id)
                        {
                            burned_starters.push(payload.starter_id);
                        }
                    }
                }
                _ => {}
            }
        }

        for starter_id in locked_starter_ids(ledger).into_iter().flatten() {
            layout.lock_starter(starter_id);
        }

        layout
    }

    pub fn states(&self) -> &[SlotState; 5] {
        &self.slots
    }

    pub fn state_at(&self, index: SlotIndex) -> SlotState {
        self.slots[index.as_u8() as usize]
    }

    pub fn starter_id_at(&self, index: SlotIndex) -> Option<StarterId> {
        match self.state_at(index) {
            SlotState::Empty => None,
            SlotState::Occupied(id) | SlotState::Locked(id) => Some(id),
        }
    }

    pub fn starter_ids(&self) -> [Option<StarterId>; 5] {
        let mut result = [None, None, None, None, None];
        for idx in 0..5 {
            result[idx] = match self.slots[idx] {
                SlotState::Empty => None,
                SlotState::Occupied(id) | SlotState::Locked(id) => Some(id),
            };
        }
        result
    }

    pub fn entries_with_kinds(&self, ledger: &Ledger) -> [SlotEntry; 5] {
        core::array::from_fn(|idx| {
            let state = self.slots[idx];
            let starter_kind = match state {
                SlotState::Empty => None,
                SlotState::Occupied(id) | SlotState::Locked(id) => starter_kind_for_id(ledger, id),
            };

            SlotEntry {
                index: SlotIndex::new(idx as u8).expect("slot index is in range"),
                state,
                starter_kind,
            }
        })
    }

    pub fn find_first_empty(&self) -> Option<SlotIndex> {
        self.slots
            .iter()
            .position(|state| matches!(state, SlotState::Empty))
            .and_then(|idx| SlotIndex::new(idx as u8))
    }

    pub fn find_by_starter(&self, starter_id: StarterId) -> Option<SlotIndex> {
        self.slots
            .iter()
            .position(|state| match state {
                SlotState::Occupied(id) | SlotState::Locked(id) => *id == starter_id,
                SlotState::Empty => false,
            })
            .and_then(|idx| SlotIndex::new(idx as u8))
    }

    pub fn has_matching_starter(&self, ledger: &Ledger, kind: StarterKind) -> bool {
        self.entries_with_kinds(ledger)
            .iter()
            .any(|entry| entry.starter_kind == Some(kind))
    }

    fn occupy_first_free(&mut self, starter_id: StarterId) {
        if let Some(idx) = self
            .slots
            .iter()
            .position(|state| matches!(state, SlotState::Empty))
        {
            self.slots[idx] = SlotState::Occupied(starter_id);
        }
    }

    fn free_starter(&mut self, starter_id: StarterId) {
        if let Some(idx) = self
            .slots
            .iter()
            .position(|state| matches!(state, SlotState::Occupied(id) | SlotState::Locked(id) if *id == starter_id))
        {
            self.slots[idx] = SlotState::Empty;
        }
    }

    fn lock_starter(&mut self, starter_id: StarterId) {
        if let Some(idx) = self
            .slots
            .iter()
            .position(|state| matches!(state, SlotState::Occupied(id) if *id == starter_id))
        {
            self.slots[idx] = SlotState::Locked(starter_id);
        }
    }

    fn contains_starter(&self, starter_id: StarterId) -> bool {
        self.slots.iter().any(|state| match state {
            SlotState::Occupied(id) | SlotState::Locked(id) => *id == starter_id,
            SlotState::Empty => false,
        })
    }
}

fn starter_kind_for_id(ledger: &Ledger, starter_id: StarterId) -> Option<StarterKind> {
    let owner = ledger.owner();

    for event in ledger.events().iter().rev() {
        if event.signer() != owner {
            continue;
        }

        if event.kind() != EventKind::StarterCreated {
            continue;
        }

        let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) else {
            continue;
        };

        if payload.starter_id == starter_id {
            return Some(payload.kind);
        }
    }

    None
}

fn locked_starter_ids(ledger: &Ledger) -> [Option<StarterId>; 5] {
    let mut pending: Vec<([u8; 32], StarterId)> = Vec::new();
    let owner = ledger.owner();

    for event in ledger.events() {
        match event.kind() {
            EventKind::InvitationSent => {
                if event.signer() != owner {
                    continue;
                }

                let Ok(payload) = InvitationSentPayload::from_bytes(event.payload()) else {
                    continue;
                };

                pending.push((payload.invitation_id, payload.starter_id));
            }
            EventKind::InvitationAccepted => {
                let Ok(payload) = InvitationAcceptedPayload::from_bytes(event.payload()) else {
                    continue;
                };
                clear_pending(&mut pending, payload.invitation_id);
            }
            EventKind::InvitationRejected => {
                let Ok(payload) = InvitationRejectedPayload::from_bytes(event.payload()) else {
                    continue;
                };
                clear_pending(&mut pending, payload.invitation_id);
            }
            EventKind::InvitationExpired => {
                let Ok(payload) = InvitationExpiredPayload::from_bytes(event.payload()) else {
                    continue;
                };
                clear_pending(&mut pending, payload.invitation_id);
            }
            _ => {}
        }
    }

    let mut unique_starters: [Option<StarterId>; 5] = [None, None, None, None, None];
    let mut cursor = 0usize;

    for (_, starter_id) in pending {
        if unique_starters
            .iter()
            .flatten()
            .any(|current| *current == starter_id)
        {
            continue;
        }

        if cursor >= unique_starters.len() {
            break;
        }

        unique_starters[cursor] = Some(starter_id);
        cursor += 1;
    }

    unique_starters
}

fn clear_pending(pending: &mut Vec<([u8; 32], StarterId)>, invitation_id: [u8; 32]) {
    pending.retain(|(current_invitation_id, _)| *current_invitation_id != invitation_id);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::Event;
    use crate::event_payloads::{RejectReason, StarterCreatedPayload};
    use crate::primitives::{Network, PubKey, Signature, Timestamp};
    use alloc::vec::Vec;

    fn append_event(ledger: &mut Ledger, kind: EventKind, payload: &[u8], timestamp: u64) {
        let owner = *ledger.owner();
        ledger
            .append(Event::new(
                kind,
                payload.to_vec(),
                Timestamp::from(timestamp),
                Signature::from([0u8; 64]),
                owner,
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

    #[test]
    fn projects_slots_by_creation_order_not_kind() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Kick),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(2, StarterKind::Juice),
            2,
        );

        let layout = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            layout.starter_ids(),
            [
                Some(StarterId::from([1u8; 32])),
                Some(StarterId::from([2u8; 32])),
                None,
                None,
                None,
            ]
        );
        assert!(layout.has_matching_starter(&ledger, StarterKind::Kick));
        assert!(layout.has_matching_starter(&ledger, StarterKind::Juice));
    }

    #[test]
    fn burns_free_slot_and_reuses_first_empty_position() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Spark),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(2, StarterKind::Pulse),
            2,
        );
        append_event(
            &mut ledger,
            EventKind::StarterBurned,
            &StarterBurnedPayload {
                starter_id: StarterId::from([1u8; 32]),
                reason: 0,
            }
            .to_bytes(),
            3,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(3, StarterKind::Seed),
            4,
        );

        let layout = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            layout.starter_ids(),
            [
                Some(StarterId::from([3u8; 32])),
                Some(StarterId::from([2u8; 32])),
                None,
                None,
                None,
            ]
        );
    }

    #[test]
    fn ignores_duplicate_starter_created_for_active_id() {
        let owner = PubKey::from([7u8; 32]);
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
            &starter_created(1, StarterKind::Juice),
            2,
        );

        let layout = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            layout.starter_ids(),
            [Some(StarterId::from([1u8; 32])), None, None, None, None,]
        );
    }

    #[test]
    fn ignores_starter_reactivation_after_burn_for_same_id() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterBurned,
            &StarterBurnedPayload {
                starter_id: StarterId::from([1u8; 32]),
                reason: 0,
            }
            .to_bytes(),
            2,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            3,
        );

        let layout = SlotLayout::from_ledger(&ledger);

        assert_eq!(layout.starter_ids(), [None, None, None, None, None,]);
        assert!(!layout.has_matching_starter(&ledger, StarterKind::Juice));
    }

    #[test]
    fn marks_pending_outgoing_invitation_as_locked_until_finalized() {
        let owner = PubKey::from([7u8; 32]);
        let peer = PubKey::from([8u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [9u8; 32],
                starter_id: StarterId::from([1u8; 32]),
                to_pubkey: peer,
                sender_root_pubkey: None,
            }
            .to_bytes(),
            2,
        );

        let locked_layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            locked_layout.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Locked(StarterId::from([1u8; 32]))
        );

        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id: [9u8; 32],
                reason: RejectReason::Other,
            }
            .to_bytes(),
            3,
        );

        let unlocked_layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            unlocked_layout.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Occupied(StarterId::from([1u8; 32]))
        );
    }

    #[test]
    fn keeps_starter_locked_when_more_than_five_pending_invites_exist() {
        let owner = PubKey::from([7u8; 32]);
        let peer = PubKey::from([8u8; 32]);
        let mut ledger = Ledger::new(owner);
        let starter_id = StarterId::from([1u8; 32]);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );

        for invitation_idx in 0u8..6u8 {
            append_event(
                &mut ledger,
                EventKind::InvitationSent,
                &InvitationSentPayload {
                    invitation_id: [invitation_idx + 1; 32],
                    starter_id,
                    to_pubkey: peer,
                    sender_root_pubkey: None,
                }
                .to_bytes(),
                invitation_idx as u64 + 2,
            );
        }

        for invitation_idx in 0u8..5u8 {
            append_event(
                &mut ledger,
                EventKind::InvitationAccepted,
                &InvitationAcceptedPayload {
                    invitation_id: [invitation_idx + 1; 32],
                    created_starter_id: StarterId::from([9u8; 32]),
                    from_pubkey: peer,
                    accepter_root_pubkey: None,
                }
                .to_bytes(),
                invitation_idx as u64 + 10,
            );
        }

        let layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            layout.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Locked(starter_id)
        );
    }

    #[test]
    fn keeps_lock_until_last_pending_for_same_starter_is_resolved() {
        let owner = PubKey::from([7u8; 32]);
        let peer = PubKey::from([8u8; 32]);
        let mut ledger = Ledger::new(owner);
        let starter_id = StarterId::from([1u8; 32]);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [11u8; 32],
                starter_id,
                to_pubkey: peer,
                sender_root_pubkey: None,
            }
            .to_bytes(),
            2,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [12u8; 32],
                starter_id,
                to_pubkey: peer,
                sender_root_pubkey: None,
            }
            .to_bytes(),
            3,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id: [11u8; 32],
                reason: RejectReason::Other,
            }
            .to_bytes(),
            4,
        );

        let still_locked = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            still_locked.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Locked(starter_id)
        );

        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id: [12u8; 32],
                reason: RejectReason::Other,
            }
            .to_bytes(),
            5,
        );

        let unlocked = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            unlocked.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Occupied(starter_id)
        );
    }

    #[test]
    fn starter_kind_lookup_covers_full_history_beyond_first_five_creations() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::new(owner);

        for idx in 1u8..=5u8 {
            append_event(
                &mut ledger,
                EventKind::StarterCreated,
                &starter_created(idx, StarterKind::Juice),
                idx as u64,
            );
        }

        append_event(
            &mut ledger,
            EventKind::StarterBurned,
            &StarterBurnedPayload {
                starter_id: StarterId::from([1u8; 32]),
                reason: 0,
            }
            .to_bytes(),
            6,
        );

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(6, StarterKind::Kick),
            7,
        );

        let layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            layout.starter_ids(),
            [
                Some(StarterId::from([6u8; 32])),
                Some(StarterId::from([2u8; 32])),
                Some(StarterId::from([3u8; 32])),
                Some(StarterId::from([4u8; 32])),
                Some(StarterId::from([5u8; 32])),
            ]
        );

        let entries = layout.entries_with_kinds(&ledger);
        assert_eq!(entries[0].starter_kind, Some(StarterKind::Kick));
        assert!(layout.has_matching_starter(&ledger, StarterKind::Kick));
    }

    #[test]
    fn ignores_foreign_signed_invitation_for_slot_locking() {
        let owner = PubKey::from([7u8; 32]);
        let peer = PubKey::from([8u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [9u8; 32],
                starter_id: StarterId::from([42u8; 32]),
                to_pubkey: owner,
                sender_root_pubkey: None,
            }
            .to_bytes(),
            2,
            peer,
        );

        let layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            layout.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Occupied(StarterId::from([1u8; 32]))
        );
        assert_eq!(layout.find_first_empty(), SlotIndex::new(1));
    }
}
