use super::*;
use hivra_core::event_payloads::{RelationshipBrokenPayload, RelationshipEstablishedPayload};
use std::sync::Mutex;

static TEST_GUARD: Mutex<()> = Mutex::new(());

fn test_seed(byte: u8) -> Seed {
    Seed([byte; 32])
}

fn derived_pubkey(seed: &Seed) -> PubKey {
    PubKey::from(derive_root_public_key(seed).unwrap())
}

fn set_runtime_capsule(owner: PubKey, network: Network) {
    let capsule = Capsule {
        pubkey: owner,
        capsule_type: CapsuleType::Leaf,
        network,
        ledger: Ledger::new(owner),
    };

    let mut runtime = RUNTIME.lock().unwrap();
    runtime.capsule = Some(capsule);
}

fn runtime_events() -> Vec<Event> {
    let runtime = RUNTIME.lock().unwrap();
    runtime.capsule.as_ref().unwrap().ledger.events().to_vec()
}

fn runtime_capsule_state() -> hivra_core::capsule::CapsuleState {
    current_capsule_state().expect("runtime capsule state")
}

fn relationship_established_count() -> usize {
    runtime_events()
        .into_iter()
        .filter(|event| event.kind() == EventKind::RelationshipEstablished)
        .count()
}

fn relationship_broken_count() -> usize {
    runtime_events()
        .into_iter()
        .filter(|event| event.kind() == EventKind::RelationshipBroken)
        .count()
}

fn invitation_accepted_count() -> usize {
    runtime_events()
        .into_iter()
        .filter(|event| event.kind() == EventKind::InvitationAccepted)
        .count()
}

fn starter_burned_count() -> usize {
    runtime_events()
        .into_iter()
        .filter(|event| event.kind() == EventKind::StarterBurned)
        .count()
}

fn append_invitation_sent_for_test(
    invitation_id: [u8; 32],
    starter_id: [u8; 32],
    to_pubkey: [u8; 32],
    starter_slot: Option<u8>,
    from_pubkey: Option<[u8; 32]>,
) {
    let payload = InvitationSentPayload {
        invitation_id,
        starter_id: StarterId::from(starter_id),
        to_pubkey: PubKey::from(to_pubkey),
    };

    let mut bytes = payload.to_bytes();
    if let Some(slot) = starter_slot {
        bytes.push(slot);
    }
    if let Some(from) = from_pubkey {
        append_runtime_event_with_signer(EventKind::InvitationReceived, &bytes, PubKey::from(from))
            .unwrap();
    } else {
        append_runtime_event(EventKind::InvitationSent, &bytes).unwrap();
    }
}

#[test]
fn finalize_local_acceptance_creates_starter_and_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(7);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [3u8; 32];
    let invitation_id = [5u8; 32];
    let inviter_slot = 1u8;
    let peer_starter_id = derive_starter_id(&test_seed(11), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);

    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(inviter_slot),
        Some(inviter_pubkey),
    );

    let engine = build_engine(&seed);
    let acceptance_plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
    let created_starter_id = *acceptance_plan.relationship_starter_id.as_bytes();
    finalize_local_acceptance(&engine, &acceptance_plan, inviter_pubkey).unwrap();

    let events = runtime_events();
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::StarterCreated
            && StarterCreatedPayload::from_bytes(event.payload())
                .is_ok_and(|payload| payload.starter_id.as_bytes() == &created_starter_id)
    }));
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.peer_pubkey == PubKey::from(inviter_pubkey)
                    && payload.own_starter_id.as_bytes() == &created_starter_id
                    && payload.peer_starter_id.as_bytes() == &peer_starter_id
                    && payload.kind == StarterKind::Spark
                    && payload.invitation_id == invitation_id
                    && payload.sender_pubkey == PubKey::from(inviter_pubkey)
                    && payload.sender_starter_type == StarterKind::Spark
                    && payload.sender_starter_id.as_bytes() == &peer_starter_id
            })
    }));
}

#[test]
fn incoming_invitation_accepted_projects_outgoing_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(12);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [8u8; 32];
    let invitation_id = [4u8; 32];
    let own_starter_id = derive_starter_id(&test_seed(12), 0);
    let peer_starter_id = derive_starter_id(&test_seed(13), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let payload = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_starter_id),
    };

    let engine = build_engine(&local_seed);
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &payload).unwrap();

    let events = runtime_events();
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|projected| {
                projected.peer_pubkey == PubKey::from(peer_pubkey)
                    && projected.own_starter_id.as_bytes() == &own_starter_id
                    && projected.peer_starter_id.as_bytes() == &peer_starter_id
                    && projected.kind == StarterKind::Juice
                    && projected.invitation_id == invitation_id
                    && projected.sender_pubkey == local_pubkey
                    && projected.sender_starter_type == StarterKind::Juice
                    && projected.sender_starter_id.as_bytes() == &own_starter_id
            })
    }));
}

#[test]
fn incoming_invitation_accepted_projection_is_idempotent() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(14);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [18u8; 32];
    let invitation_id = [9u8; 32];
    let own_starter_id = derive_starter_id(&test_seed(14), 0);
    let peer_starter_id = derive_starter_id(&test_seed(15), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let payload = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_starter_id),
    };

    let engine = build_engine(&local_seed);
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &payload).unwrap();
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &payload).unwrap();

    assert_eq!(relationship_established_count(), 1);
}

#[test]
fn incoming_invitation_accepted_from_self_is_rejected() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(16);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [19u8; 32];
    let invitation_id = [10u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(17), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let payload = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_starter_id),
    };

    let engine = build_engine(&local_seed);
    let err = project_relationship_from_invitation_accepted(
        &engine,
        local_pubkey.as_bytes().to_owned(),
        &payload,
    )
    .unwrap_err();

    assert_eq!(err, "ignore self InvitationAccepted delivery");
    assert_eq!(relationship_established_count(), 0);
}

#[test]
fn incoming_empty_slot_reject_burns_sender_starter() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(21);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [8u8; 32];
    let invitation_id = [4u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(own_starter_id),
            nonce: derive_starter_nonce(&local_seed, 0),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let engine = build_engine(&local_seed);
    project_effects_from_invitation_rejected(
        &engine,
        &InvitationRejectedPayload {
            invitation_id,
            reason: RejectReason::EmptySlot,
        },
    )
    .unwrap();

    let events = runtime_events();
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::StarterBurned
            && StarterBurnedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.starter_id.as_bytes() == &own_starter_id
                    && payload.reason == RejectReason::EmptySlot as u8
            })
    }));
}

#[test]
fn burned_starter_id_is_reused_on_later_accept() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(91);
    let local_pubkey = derived_pubkey(&local_seed);
    let inviter_pubkey = [33u8; 32];
    let first_invitation_id = [41u8; 32];
    let second_invitation_id = [42u8; 32];
    let slot = 0u8;
    let local_starter_id = derive_starter_id(&local_seed, slot);
    let peer_starter_id = derive_starter_id(&test_seed(92), slot);

    set_runtime_capsule(local_pubkey, Network::Neste);

    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(local_starter_id),
            nonce: derive_starter_nonce(&local_seed, slot),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    append_invitation_sent_for_test(
        first_invitation_id,
        local_starter_id,
        inviter_pubkey,
        Some(slot),
        None,
    );

    let engine = build_engine(&local_seed);
    project_effects_from_invitation_rejected(
        &engine,
        &InvitationRejectedPayload {
            invitation_id: first_invitation_id,
            reason: RejectReason::EmptySlot,
        },
    )
    .unwrap();

    append_invitation_sent_for_test(
        second_invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(slot),
        Some(inviter_pubkey),
    );

    let acceptance_plan = resolve_local_acceptance_plan(&local_seed, second_invitation_id).unwrap();
    assert_eq!(
        acceptance_plan.relationship_starter_id.as_bytes(),
        &local_starter_id,
    );
    assert!(acceptance_plan.created_starter.is_some());

    finalize_local_acceptance(&engine, &acceptance_plan, inviter_pubkey).unwrap();

    let reused_count = runtime_events()
        .into_iter()
        .filter(|event| {
            event.kind() == EventKind::StarterCreated
                && StarterCreatedPayload::from_bytes(event.payload())
                    .is_ok_and(|payload| payload.starter_id.as_bytes() == &local_starter_id)
        })
        .count();

    assert_eq!(reused_count, 2);
}

#[test]
fn active_slot_starter_identity_tracks_reactivated_starter_after_burn() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(93);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    let slot = 0u8;
    let burned_id = StarterId::from(derive_starter_id(&seed, slot));
    let burned_nonce = derive_starter_nonce(&seed, slot);

    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: burned_id,
            nonce: burned_nonce,
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();
    append_runtime_event(
        EventKind::StarterBurned,
        &StarterBurnedPayload {
            starter_id: burned_id,
            reason: 0,
        }
        .to_bytes(),
    )
    .unwrap();

    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: burned_id,
            nonce: burned_nonce,
            kind: StarterKind::Spark,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    assert_eq!(active_starter_id_for_slot(slot), Some(burned_id));
}

#[test]
fn reactivated_starter_can_burn_again_in_new_invitation_cycle() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(94);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [44u8; 32];
    let first_invitation_id = [45u8; 32];
    let second_invitation_id = [46u8; 32];
    let slot = 0u8;
    let local_starter_id = derive_starter_id(&local_seed, slot);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(local_starter_id),
            nonce: derive_starter_nonce(&local_seed, slot),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    append_invitation_sent_for_test(
        first_invitation_id,
        local_starter_id,
        peer_pubkey,
        Some(slot),
        None,
    );
    let engine = build_engine(&local_seed);
    project_effects_from_invitation_rejected(
        &engine,
        &InvitationRejectedPayload {
            invitation_id: first_invitation_id,
            reason: RejectReason::EmptySlot,
        },
    )
    .unwrap();
    assert_eq!(starter_burned_count(), 1);

    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(local_starter_id),
            nonce: derive_starter_nonce(&local_seed, slot),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();
    assert_eq!(
        active_starter_id_for_slot(slot),
        Some(StarterId::from(local_starter_id))
    );

    append_invitation_sent_for_test(
        second_invitation_id,
        local_starter_id,
        peer_pubkey,
        Some(slot),
        None,
    );
    project_effects_from_invitation_rejected(
        &engine,
        &InvitationRejectedPayload {
            invitation_id: second_invitation_id,
            reason: RejectReason::EmptySlot,
        },
    )
    .unwrap();
    assert_eq!(starter_burned_count(), 2);
}

#[test]
fn relationship_broken_payload_tracks_specific_local_starter() {
    let payload = RelationshipBrokenPayload {
        peer_pubkey: PubKey::from([9u8; 32]),
        own_starter_id: StarterId::from([7u8; 32]),
    };

    let parsed = RelationshipBrokenPayload::from_bytes(&payload.to_bytes()).unwrap();
    assert_eq!(parsed.peer_pubkey, PubKey::from([9u8; 32]));
    assert_eq!(parsed.own_starter_id, StarterId::from([7u8; 32]));
}

#[test]
fn build_engine_uses_root_identity_for_signer() {
    let seed = test_seed(91);
    let engine = build_engine(&seed);
    let signer = engine.public_key().expect("engine pubkey");

    assert_eq!(signer, PubKey::from(derive_root_public_key(&seed).unwrap()));
    assert_ne!(
        signer,
        PubKey::from(derive_nostr_public_key(&seed).unwrap())
    );
}

#[test]
fn resolved_invitation_blocks_replayed_incoming_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(31);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [17u8; 32];
    let invitation_id = [22u8; 32];
    let peer_starter_id = derive_starter_id(&test_seed(41), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(0),
        Some(peer_pubkey),
    );

    let accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(derive_starter_id(&local_seed, 0)),
    };
    append_runtime_event(EventKind::InvitationAccepted, &accepted.to_bytes()).unwrap();

    assert!(invitation_is_resolved_in_runtime(&invitation_id));
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationReceived,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_conflicting_terminal_event_for_resolved_invitation() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(40);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [25u8; 32];
    let invitation_id = [47u8; 32];
    let peer_starter_id = derive_starter_id(&test_seed(41), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(0),
        Some(peer_pubkey),
    );

    append_runtime_event(
        EventKind::InvitationRejected,
        &InvitationRejectedPayload {
            invitation_id,
            reason: RejectReason::Other,
        }
        .to_bytes(),
    )
    .unwrap();

    let conflicting_accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(derive_starter_id(&local_seed, 0)),
    };

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &conflicting_accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_allows_first_terminal_event_for_unresolved_invitation() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(41);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [26u8; 32];
    let invitation_id = [48u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_created_starter_id = derive_starter_id(&test_seed(42), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_created_starter_id),
    };

    assert!(!should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replayed_invitation_accepted_is_skipped_after_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(33);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [19u8; 32];
    let invitation_id = [23u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_created_starter_id = derive_starter_id(&test_seed(34), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_created_starter_id),
    };
    let accepted_bytes = accepted.to_bytes();

    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &accepted_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    let engine = build_engine(&local_seed);
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &accepted).unwrap();

    assert_eq!(invitation_accepted_count(), 1);
    assert_eq!(relationship_established_count(), 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert!(event_exists_in_runtime_with_signer(
        EventKind::InvitationAccepted,
        &accepted_bytes,
        PubKey::from(peer_pubkey),
    ));

    // Mimic delivery replay guard path: duplicate accepted message must be ignored.
    if !event_exists_in_runtime_with_signer(
        EventKind::InvitationAccepted,
        &accepted_bytes,
        PubKey::from(peer_pubkey),
    ) {
        append_runtime_event_with_signer(
            EventKind::InvitationAccepted,
            &accepted_bytes,
            PubKey::from(peer_pubkey),
        )
        .unwrap();
        project_relationship_from_invitation_accepted(&engine, peer_pubkey, &accepted).unwrap();
    }

    assert_eq!(invitation_accepted_count(), 1);
    assert_eq!(relationship_established_count(), 1);
}

#[test]
fn replayed_invitation_rejected_is_skipped_after_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(35);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [20u8; 32];
    let invitation_id = [24u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(own_starter_id),
            nonce: derive_starter_nonce(&local_seed, 0),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let rejected = InvitationRejectedPayload {
        invitation_id,
        reason: RejectReason::EmptySlot,
    };
    let rejected_bytes = rejected.to_bytes();

    append_runtime_event_with_signer(
        EventKind::InvitationRejected,
        &rejected_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    let engine = build_engine(&local_seed);
    project_effects_from_invitation_rejected(&engine, &rejected).unwrap();

    assert_eq!(starter_burned_count(), 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert!(event_exists_in_runtime_with_signer(
        EventKind::InvitationRejected,
        &rejected_bytes,
        PubKey::from(peer_pubkey),
    ));

    // Mimic delivery replay guard path: duplicate rejected message must be ignored.
    if !event_exists_in_runtime_with_signer(
        EventKind::InvitationRejected,
        &rejected_bytes,
        PubKey::from(peer_pubkey),
    ) {
        append_runtime_event_with_signer(
            EventKind::InvitationRejected,
            &rejected_bytes,
            PubKey::from(peer_pubkey),
        )
        .unwrap();
        project_effects_from_invitation_rejected(&engine, &rejected).unwrap();
    }

    assert_eq!(starter_burned_count(), 1);
}

#[test]
fn replayed_relationship_established_is_skipped_after_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(36);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [22u8; 32];
    let invitation_id = [25u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(37), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    let established = RelationshipEstablishedPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_starter_id: StarterId::from(peer_starter_id),
        kind: StarterKind::Juice,
        invitation_id,
        sender_pubkey: PubKey::from(peer_pubkey),
        sender_starter_type: StarterKind::Juice,
        sender_starter_id: StarterId::from(peer_starter_id),
    };
    let established_bytes = established.to_bytes();

    append_runtime_event_with_signer(
        EventKind::RelationshipEstablished,
        &established_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    assert_eq!(relationship_established_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    if !event_exists_in_runtime_with_signer(
        EventKind::RelationshipEstablished,
        &established_bytes,
        PubKey::from(peer_pubkey),
    ) {
        append_runtime_event_with_signer(
            EventKind::RelationshipEstablished,
            &established_bytes,
            PubKey::from(peer_pubkey),
        )
        .unwrap();
    }

    assert_eq!(relationship_established_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 1);
}

#[test]
fn replayed_relationship_broken_is_skipped_after_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(38);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [24u8; 32];
    let invitation_id = [26u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(39), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    let established = RelationshipEstablishedPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_starter_id: StarterId::from(peer_starter_id),
        kind: StarterKind::Juice,
        invitation_id,
        sender_pubkey: PubKey::from(peer_pubkey),
        sender_starter_type: StarterKind::Juice,
        sender_starter_id: StarterId::from(peer_starter_id),
    };
    append_runtime_event_with_signer(
        EventKind::RelationshipEstablished,
        &established.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    let broken = RelationshipBrokenPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
    };
    let broken_bytes = broken.to_bytes();
    append_runtime_event_with_signer(
        EventKind::RelationshipBroken,
        &broken_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    assert_eq!(relationship_broken_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 0);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    if !event_exists_in_runtime_with_signer(
        EventKind::RelationshipBroken,
        &broken_bytes,
        PubKey::from(peer_pubkey),
    ) {
        append_runtime_event_with_signer(
            EventKind::RelationshipBroken,
            &broken_bytes,
            PubKey::from(peer_pubkey),
        )
        .unwrap();
    }

    assert_eq!(relationship_broken_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 0);
}

#[test]
fn exported_ledger_roundtrips_same_event_count() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(51);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    append_runtime_event(EventKind::CapsuleCreated, &[]).unwrap();
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(derive_starter_id(&seed, 0)),
            nonce: [1u8; 32],
            kind: StarterKind::Spark,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    let before = runtime_events();
    let exported = export_runtime_ledger().unwrap();

    clear_runtime_state();
    set_runtime_capsule(owner, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    let after = runtime_events();
    assert_eq!(after.len(), before.len());
    assert_eq!(
        after.last().map(|event| event.kind()),
        before.last().map(|event| event.kind())
    );
}

#[test]
fn import_runtime_ledger_observes_tail_timestamp_for_future_prepared_events() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(95);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    let mut imported = Ledger::new(owner);
    imported
        .append(Event::new(
            EventKind::CapsuleCreated,
            CapsuleCreatedPayload::new(
                Network::Neste.to_byte(),
                CapsuleType::Leaf as u8,
                [0u8; 32],
            )
            .to_bytes(),
            Timestamp::from(9_999_999_999_000u64),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();

    let imported_json = serde_json::to_string(&imported).unwrap();
    import_runtime_ledger(&imported_json).unwrap();

    let engine = build_engine(&seed);
    let prepared = engine.prepare_invitation_expired([77u8; 32]).unwrap();
    assert!(append_prepared_event(prepared).is_ok());
}

#[test]
fn import_runtime_ledger_rejects_inconsistent_hash_chain() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(96);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    let mut imported = Ledger::new(owner);
    imported
        .append(Event::new(
            EventKind::CapsuleCreated,
            CapsuleCreatedPayload::new(
                Network::Neste.to_byte(),
                CapsuleType::Leaf as u8,
                [0u8; 32],
            )
            .to_bytes(),
            Timestamp::from(0),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();

    let mut json_value = serde_json::to_value(&imported).unwrap();
    let bumped_hash = imported.last_hash().saturating_add(1);
    json_value.as_object_mut().unwrap().insert(
        "last_hash".to_string(),
        serde_json::Value::Number(bumped_hash.into()),
    );
    let imported_json = serde_json::to_string(&json_value).unwrap();

    let err = import_runtime_ledger(&imported_json).unwrap_err();
    assert_eq!(err, "ledger inconsistent");
}

#[test]
fn import_runtime_ledger_allows_legacy_history_without_capsule_birth() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(97);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    let to_pubkey = PubKey::from([44u8; 32]);
    let starter_id = StarterId::from(derive_starter_id(&seed, 0));
    let invitation_payload = InvitationSentPayload {
        invitation_id: [55u8; 32],
        starter_id,
        to_pubkey,
    };

    let mut imported = Ledger::new(owner);
    imported
        .append(Event::new(
            EventKind::InvitationSent,
            invitation_payload.to_bytes(),
            Timestamp::from(1),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();

    let imported_json = serde_json::to_string(&imported).unwrap();
    import_runtime_ledger(&imported_json).unwrap();
}

#[test]
fn import_runtime_ledger_rejects_capsule_birth_signed_by_foreign_key() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(98);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    let mut imported = Ledger::new(owner);
    imported
        .append(Event::new(
            EventKind::CapsuleCreated,
            CapsuleCreatedPayload::new(
                Network::Neste.to_byte(),
                CapsuleType::Leaf as u8,
                [0u8; 32],
            )
            .to_bytes(),
            Timestamp::from(0),
            Signature::from([0u8; 64]),
            PubKey::from([123u8; 32]),
        ))
        .unwrap();

    let imported_json = serde_json::to_string(&imported).unwrap();
    let err = import_runtime_ledger(&imported_json).unwrap_err();
    assert_eq!(err, "capsule birth signer mismatch");
}

#[test]
fn import_runtime_ledger_rejects_misplaced_capsule_birth() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(99);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    let mut imported = Ledger::new(owner);
    imported
        .append(Event::new(
            EventKind::InvitationSent,
            InvitationSentPayload {
                invitation_id: [1u8; 32],
                starter_id: StarterId::from(derive_starter_id(&seed, 1)),
                to_pubkey: PubKey::from([2u8; 32]),
            }
            .to_bytes(),
            Timestamp::from(1),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();
    imported
        .append(Event::new(
            EventKind::CapsuleCreated,
            CapsuleCreatedPayload::new(
                Network::Neste.to_byte(),
                CapsuleType::Leaf as u8,
                [0u8; 32],
            )
            .to_bytes(),
            Timestamp::from(2),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();

    let imported_json = serde_json::to_string(&imported).unwrap();
    let err = import_runtime_ledger(&imported_json).unwrap_err();
    assert_eq!(err, "capsule birth misplaced");
}

#[test]
fn import_runtime_ledger_rejects_duplicate_capsule_birth() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(100);
    let owner = derived_pubkey(&seed);
    set_runtime_capsule(owner, Network::Neste);

    let mut imported = Ledger::new(owner);
    imported
        .append(Event::new(
            EventKind::CapsuleCreated,
            CapsuleCreatedPayload::new(
                Network::Neste.to_byte(),
                CapsuleType::Leaf as u8,
                [0u8; 32],
            )
            .to_bytes(),
            Timestamp::from(0),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();
    imported
        .append(Event::new(
            EventKind::CapsuleCreated,
            CapsuleCreatedPayload::new(
                Network::Neste.to_byte(),
                CapsuleType::Leaf as u8,
                [0u8; 32],
            )
            .to_bytes(),
            Timestamp::from(1),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();

    let imported_json = serde_json::to_string(&imported).unwrap();
    let err = import_runtime_ledger(&imported_json).unwrap_err();
    assert_eq!(err, "duplicate capsule birth");
}

#[test]
fn accepted_relationship_survives_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(61);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [13u8; 32];
    let invitation_id = [19u8; 32];
    let inviter_slot = 0u8;
    let peer_starter_id = derive_starter_id(&test_seed(62), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(inviter_slot),
        Some(inviter_pubkey),
    );

    let engine = build_engine(&seed);
    let acceptance_plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
    finalize_local_acceptance(&engine, &acceptance_plan, inviter_pubkey).unwrap();

    assert_eq!(relationship_established_count(), 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert_eq!(relationship_established_count(), 1);
    assert!(runtime_events().iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.peer_pubkey == PubKey::from(inviter_pubkey)
                    && payload.peer_starter_id.as_bytes() == &peer_starter_id
                    && payload.invitation_id == invitation_id
                    && payload.sender_pubkey == PubKey::from(inviter_pubkey)
                    && payload.sender_starter_type == StarterKind::Juice
                    && payload.sender_starter_id.as_bytes() == &peer_starter_id
            })
    }));
}

#[test]
fn broken_relationship_survives_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(63);
    let local_pubkey = derived_pubkey(&seed);
    let peer_pubkey = [15u8; 32];
    let invitation_id = [21u8; 32];
    let own_starter_id = derive_starter_id(&seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(64), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::RelationshipEstablished,
        &RelationshipEstablishedPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(own_starter_id),
            peer_starter_id: StarterId::from(peer_starter_id),
            kind: StarterKind::Juice,
            invitation_id,
            sender_pubkey: PubKey::from(peer_pubkey),
            sender_starter_type: StarterKind::Juice,
            sender_starter_id: StarterId::from(peer_starter_id),
        }
        .to_bytes(),
    )
    .unwrap();
    append_runtime_event(
        EventKind::RelationshipBroken,
        &RelationshipBrokenPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(own_starter_id),
        }
        .to_bytes(),
    )
    .unwrap();

    assert_eq!(runtime_capsule_state().relationships_count, 0);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert_eq!(runtime_capsule_state().relationships_count, 0);
    assert!(runtime_events().iter().any(|event| {
        event.kind() == EventKind::RelationshipBroken
            && RelationshipBrokenPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.peer_pubkey == PubKey::from(peer_pubkey)
                    && payload.own_starter_id.as_bytes() == &own_starter_id
            })
    }));
}

#[test]
fn reinvite_same_starter_type_survives_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(65);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [16u8; 32];
    let first_invitation_id = [27u8; 32];
    let second_invitation_id = [28u8; 32];
    let local_starter_id = derive_starter_id(&local_seed, 0);
    let peer_first_starter_id = derive_starter_id(&test_seed(66), 0);
    let peer_second_starter_id = derive_starter_id(&test_seed(67), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(local_starter_id),
            nonce: derive_starter_nonce(&local_seed, 0),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    append_invitation_sent_for_test(
        first_invitation_id,
        local_starter_id,
        peer_pubkey,
        Some(0),
        None,
    );
    let first_accepted = InvitationAcceptedPayload {
        invitation_id: first_invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_first_starter_id),
    };
    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &first_accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    let engine = build_engine(&local_seed);
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &first_accepted).unwrap();

    append_runtime_event(
        EventKind::RelationshipBroken,
        &RelationshipBrokenPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(local_starter_id),
        }
        .to_bytes(),
    )
    .unwrap();

    append_invitation_sent_for_test(
        second_invitation_id,
        local_starter_id,
        peer_pubkey,
        Some(0),
        None,
    );
    let second_accepted = InvitationAcceptedPayload {
        invitation_id: second_invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_second_starter_id),
    };
    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &second_accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &second_accepted).unwrap();

    assert_eq!(relationship_established_count(), 2);
    assert_eq!(relationship_broken_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert_eq!(relationship_established_count(), 2);
    assert_eq!(relationship_broken_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 1);
    assert!(runtime_events().iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.invitation_id == first_invitation_id
                    && payload.own_starter_id.as_bytes() == &local_starter_id
                    && payload.kind == StarterKind::Juice
            })
    }));
    assert!(runtime_events().iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.invitation_id == second_invitation_id
                    && payload.own_starter_id.as_bytes() == &local_starter_id
                    && payload.kind == StarterKind::Juice
            })
    }));
}

#[test]
fn reinvite_different_starter_type_survives_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(68);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [17u8; 32];
    let first_invitation_id = [30u8; 32];
    let second_invitation_id = [31u8; 32];
    let local_starter_id_juice = derive_starter_id(&local_seed, 0);
    let local_starter_id_spark = derive_starter_id(&local_seed, 1);
    let peer_first_starter_id = derive_starter_id(&test_seed(69), 0);
    let peer_second_starter_id = derive_starter_id(&test_seed(70), 1);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(local_starter_id_juice),
            nonce: derive_starter_nonce(&local_seed, 0),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(local_starter_id_spark),
            nonce: derive_starter_nonce(&local_seed, 1),
            kind: StarterKind::Spark,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    append_invitation_sent_for_test(
        first_invitation_id,
        local_starter_id_juice,
        peer_pubkey,
        Some(0),
        None,
    );
    let first_accepted = InvitationAcceptedPayload {
        invitation_id: first_invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_first_starter_id),
    };
    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &first_accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    let engine = build_engine(&local_seed);
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &first_accepted).unwrap();

    append_runtime_event(
        EventKind::RelationshipBroken,
        &RelationshipBrokenPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(local_starter_id_juice),
        }
        .to_bytes(),
    )
    .unwrap();

    append_invitation_sent_for_test(
        second_invitation_id,
        local_starter_id_spark,
        peer_pubkey,
        Some(1),
        None,
    );
    let second_accepted = InvitationAcceptedPayload {
        invitation_id: second_invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_second_starter_id),
    };
    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &second_accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &second_accepted).unwrap();

    assert_eq!(relationship_established_count(), 2);
    assert_eq!(relationship_broken_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert_eq!(relationship_established_count(), 2);
    assert_eq!(relationship_broken_count(), 1);
    assert_eq!(runtime_capsule_state().relationships_count, 1);
    assert!(runtime_events().iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.invitation_id == first_invitation_id
                    && payload.own_starter_id.as_bytes() == &local_starter_id_juice
                    && payload.kind == StarterKind::Juice
            })
    }));
    assert!(runtime_events().iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.invitation_id == second_invitation_id
                    && payload.own_starter_id.as_bytes() == &local_starter_id_spark
                    && payload.kind == StarterKind::Spark
            })
    }));
}

#[test]
fn reverse_direction_pending_invitations_survive_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(83);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [32u8; 32];
    let outgoing_invitation_id = [38u8; 32];
    let incoming_invitation_id = [39u8; 32];
    let local_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(84), 1);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        outgoing_invitation_id,
        local_starter_id,
        peer_pubkey,
        Some(0),
        None,
    );
    append_invitation_sent_for_test(
        incoming_invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(1),
        Some(peer_pubkey),
    );

    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationSent,
        &outgoing_invitation_id,
        local_pubkey,
    ));
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationReceived,
        &incoming_invitation_id,
        PubKey::from(peer_pubkey),
    ));

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationSent,
        &outgoing_invitation_id,
        local_pubkey,
    ));
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationReceived,
        &incoming_invitation_id,
        PubKey::from(peer_pubkey),
    ));
    assert!(!invitation_is_resolved_in_runtime(&outgoing_invitation_id));
    assert!(!invitation_is_resolved_in_runtime(&incoming_invitation_id));
}

#[test]
fn resolved_invitation_stays_resolved_after_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(71);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [23u8; 32];
    let invitation_id = [29u8; 32];
    let peer_starter_id = derive_starter_id(&test_seed(72), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(0),
        Some(peer_pubkey),
    );

    let accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(derive_starter_id(&local_seed, 0)),
    };
    append_runtime_event(EventKind::InvitationAccepted, &accepted.to_bytes()).unwrap();

    assert!(invitation_is_resolved_in_runtime(&invitation_id));
    assert_eq!(invitation_accepted_count(), 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert!(invitation_is_resolved_in_runtime(&invitation_id));
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationReceived,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));
    assert_eq!(invitation_accepted_count(), 1);
}

#[test]
fn capsule_state_and_incoming_offer_truth_survive_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(81);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [31u8; 32];
    let invitation_id = [37u8; 32];
    let peer_starter_id = derive_starter_id(&test_seed(82), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(0),
        Some(peer_pubkey),
    );

    let before_state = runtime_capsule_state();
    let exported = export_runtime_ledger().unwrap();

    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    let after_state = runtime_capsule_state();
    assert_eq!(after_state.public_key, before_state.public_key);
    assert_eq!(after_state.capsule_type, before_state.capsule_type);
    assert_eq!(after_state.network, before_state.network);
    assert_eq!(after_state.slots, before_state.slots);
    assert_eq!(after_state.ledger_hash, before_state.ledger_hash);
    assert_eq!(
        after_state.relationships_count,
        before_state.relationships_count
    );
    assert_eq!(after_state.version, before_state.version);
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationReceived,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));
}
