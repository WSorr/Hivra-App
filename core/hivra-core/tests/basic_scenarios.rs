//! Basic integration tests for core domain.
//!
//! These tests verify complete scenarios using only the public API.

use hivra_core::capsule::{Capsule, CapsuleState, CapsuleType};
use hivra_core::slot::{SlotLayout, SlotState};
use hivra_core::{
    invitation_status, pending_invitation_count, plan_accept_for_kind, AcceptPlan, Event,
    EventKind, EventPayload, InvitationAcceptedPayload, InvitationRejectedPayload,
    InvitationSentPayload, InvitationStatus, Ledger, Network, PubKey, RejectReason, Signature,
    StarterBurnedPayload, StarterCreatedPayload, StarterId, StarterKind, Timestamp,
};

fn append_owner_event(ledger: &mut Ledger, kind: EventKind, payload: Vec<u8>, ts: u64) {
    let owner = *ledger.owner();
    ledger
        .append(Event::new(
            kind,
            payload,
            Timestamp::from(ts),
            Signature::from([0u8; 64]),
            owner,
        ))
        .expect("owner event append must succeed");
}

fn starter_created_payload(starter_id: StarterId, kind: StarterKind) -> Vec<u8> {
    StarterCreatedPayload {
        starter_id,
        nonce: *starter_id.as_bytes(),
        kind,
        network: Network::Neste.to_byte(),
    }
    .to_bytes()
}

#[test]
fn genesis_capsule_projection_tracks_full_slots_and_version() {
    let owner = PubKey::from([1u8; 32]);
    let mut ledger = Ledger::new(owner);

    for (idx, kind) in [
        StarterKind::Juice,
        StarterKind::Spark,
        StarterKind::Seed,
        StarterKind::Pulse,
        StarterKind::Kick,
    ]
    .into_iter()
    .enumerate()
    {
        append_owner_event(
            &mut ledger,
            EventKind::StarterCreated,
            starter_created_payload(StarterId::from([(idx + 1) as u8; 32]), kind),
            (idx + 1) as u64,
        );
    }

    let capsule = Capsule {
        pubkey: owner,
        capsule_type: CapsuleType::Leaf,
        network: Network::Neste,
        ledger,
    };
    let state = CapsuleState::from_capsule(&capsule);

    assert_eq!(state.public_key, [1u8; 32]);
    assert_eq!(state.capsule_type, CapsuleType::Leaf as u8);
    assert_eq!(state.network, Network::Neste as u8);
    assert_eq!(state.version, 5);
    assert_eq!(state.relationships_count, 0);
    assert_eq!(
        state.slots,
        [
            Some([1u8; 32]),
            Some([2u8; 32]),
            Some([3u8; 32]),
            Some([4u8; 32]),
            Some([5u8; 32]),
        ]
    );
}

#[test]
fn invitation_flow_locks_unlocks_and_burns_starter_deterministically() {
    let owner = PubKey::from([7u8; 32]);
    let peer = PubKey::from([9u8; 32]);
    let mut ledger = Ledger::new(owner);

    let starter = StarterId::from([3u8; 32]);
    let invitation_a = [10u8; 32];
    let invitation_b = [11u8; 32];

    append_owner_event(
        &mut ledger,
        EventKind::StarterCreated,
        starter_created_payload(starter, StarterKind::Juice),
        1,
    );

    append_owner_event(
        &mut ledger,
        EventKind::InvitationSent,
        InvitationSentPayload {
            invitation_id: invitation_a,
            starter_id: starter,
            to_pubkey: peer,
        }
        .to_bytes(),
        2,
    );

    let layout = SlotLayout::from_ledger(&ledger);
    assert_eq!(
        layout.state_at(hivra_core::primitives::SlotIndex::new(0).unwrap()),
        SlotState::Locked(starter)
    );
    assert_eq!(pending_invitation_count(&ledger), 1);
    assert_eq!(
        invitation_status(&ledger, invitation_a),
        InvitationStatus::Pending
    );

    append_owner_event(
        &mut ledger,
        EventKind::InvitationAccepted,
        InvitationAcceptedPayload {
            invitation_id: invitation_a,
            from_pubkey: peer,
            created_starter_id: StarterId::from([12u8; 32]),
        }
        .to_bytes(),
        3,
    );

    let layout_after_accept = SlotLayout::from_ledger(&ledger);
    assert_eq!(
        layout_after_accept.state_at(hivra_core::primitives::SlotIndex::new(0).unwrap()),
        SlotState::Occupied(starter)
    );
    assert_eq!(pending_invitation_count(&ledger), 0);
    assert!(matches!(
        invitation_status(&ledger, invitation_a),
        InvitationStatus::Accepted { .. }
    ));

    append_owner_event(
        &mut ledger,
        EventKind::InvitationSent,
        InvitationSentPayload {
            invitation_id: invitation_b,
            starter_id: starter,
            to_pubkey: peer,
        }
        .to_bytes(),
        4,
    );
    append_owner_event(
        &mut ledger,
        EventKind::InvitationRejected,
        InvitationRejectedPayload {
            invitation_id: invitation_b,
            reason: RejectReason::EmptySlot,
        }
        .to_bytes(),
        5,
    );
    append_owner_event(
        &mut ledger,
        EventKind::StarterBurned,
        StarterBurnedPayload {
            starter_id: starter,
            reason: 0,
        }
        .to_bytes(),
        6,
    );

    let layout_after_burn = SlotLayout::from_ledger(&ledger);
    assert_eq!(
        layout_after_burn.state_at(hivra_core::primitives::SlotIndex::new(0).unwrap()),
        SlotState::Empty
    );
    assert_eq!(pending_invitation_count(&ledger), 0);
    assert_eq!(
        invitation_status(&ledger, invitation_b),
        InvitationStatus::Rejected {
            reason: RejectReason::EmptySlot
        }
    );
}

#[test]
fn proto_accept_plan_is_stable_for_same_ledger_truth() {
    let owner = PubKey::from([33u8; 32]);
    let mut ledger = Ledger::new(owner);

    let empty_slots = SlotLayout::from_ledger(&ledger);
    assert_eq!(
        plan_accept_for_kind(&ledger, &empty_slots, StarterKind::Spark),
        AcceptPlan::CreateStarterInEmptySlot {
            slot: hivra_core::primitives::SlotIndex::new(0).unwrap(),
            kind: StarterKind::Spark,
        }
    );

    append_owner_event(
        &mut ledger,
        EventKind::StarterCreated,
        starter_created_payload(StarterId::from([55u8; 32]), StarterKind::Spark),
        1,
    );

    let slots_after_create = SlotLayout::from_ledger(&ledger);
    let plan = plan_accept_for_kind(&ledger, &slots_after_create, StarterKind::Spark);

    assert_eq!(
        plan,
        AcceptPlan::UseExistingStarter {
            relationship_starter_id: StarterId::from([55u8; 32]),
            created_starter: Some(hivra_core::PlannedStarterCreation {
                slot: hivra_core::primitives::SlotIndex::new(1).unwrap(),
                kind: StarterKind::Juice,
            }),
        }
    );

    // Same ledger -> same plan.
    let replayed = plan_accept_for_kind(&ledger, &slots_after_create, StarterKind::Spark);
    assert_eq!(plan, replayed);
}
