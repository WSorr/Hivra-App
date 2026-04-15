use super::*;
use crate::capsule_api::hivra_capsule_runtime_owner_public_key;
use crate::seed_api::{hivra_seed_nostr_public_key, hivra_seed_root_public_key};
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
    let mut ledger = Ledger::new(owner);
    ledger
        .append(Event::new(
            EventKind::CapsuleCreated,
            CapsuleCreatedPayload::new(network.to_byte(), CapsuleType::Leaf as u8, [0u8; 32])
                .to_bytes(),
            Timestamp::from(0),
            Signature::from([0u8; 64]),
            owner,
        ))
        .unwrap();
    let capsule = Capsule {
        pubkey: owner,
        capsule_type: CapsuleType::Leaf,
        network,
        ledger,
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

fn invitation_expired_count() -> usize {
    runtime_events()
        .into_iter()
        .filter(|event| event.kind() == EventKind::InvitationExpired)
        .count()
}

fn invitation_sent_count() -> usize {
    runtime_events()
        .into_iter()
        .filter(|event| event.kind() == EventKind::InvitationSent)
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
        sender_root_pubkey: None,
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

fn append_incoming_invitation_with_root_for_test(
    invitation_id: [u8; 32],
    starter_id: [u8; 32],
    to_pubkey: PubKey,
    starter_slot: u8,
    from_pubkey: [u8; 32],
    sender_root_pubkey: [u8; 32],
) {
    let payload = InvitationSentPayload {
        invitation_id,
        starter_id: StarterId::from(starter_id),
        to_pubkey,
        sender_root_pubkey: None,
    };
    let mut bytes = payload.to_bytes();
    bytes.extend_from_slice(&sender_root_pubkey);
    bytes.push(starter_slot);
    append_runtime_event_with_signer(
        EventKind::InvitationReceived,
        &bytes,
        PubKey::from(from_pubkey),
    )
    .unwrap();
}

#[test]
fn pending_outgoing_retry_candidates_include_only_unresolved_outgoing() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(201);
    let local_pubkey = derived_pubkey(&local_seed);
    let local_starter_id = derive_starter_id(&local_seed, 0);
    let accepted_id = [211u8; 32];
    let pending_id = [212u8; 32];
    let incoming_id = [213u8; 32];
    let accepted_peer = [221u8; 32];
    let pending_peer = [222u8; 32];
    let incoming_peer = [223u8; 32];

    set_runtime_capsule(local_pubkey, Network::Neste);

    append_invitation_sent_for_test(accepted_id, local_starter_id, accepted_peer, Some(0), None);
    append_invitation_sent_for_test(pending_id, local_starter_id, pending_peer, Some(0), None);
    append_invitation_sent_for_test(
        incoming_id,
        local_starter_id,
        *local_pubkey.as_bytes(),
        Some(0),
        Some(incoming_peer),
    );

    let accepted_payload = InvitationAcceptedPayload {
        invitation_id: accepted_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(derive_starter_id(&test_seed(202), 0)),
        accepter_root_pubkey: None,
    };
    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &accepted_payload.to_bytes(),
        PubKey::from(accepted_peer),
    )
    .unwrap();

    let pending =
        crate::invitation_support::pending_outgoing_invitation_deliveries_in_runtime(local_pubkey);
    let pending_ids: Vec<[u8; 32]> = pending.iter().map(|entry| entry.invitation_id).collect();

    assert_eq!(pending.len(), 1);
    assert_eq!(pending_ids, vec![pending_id]);
    assert_eq!(pending[0].to_pubkey, pending_peer);
}

#[test]
fn lookup_reads_sender_root_from_root_augmented_incoming_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(95);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [41u8; 32];
    let peer_root_pubkey = [42u8; 32];
    let invitation_id = [43u8; 32];
    let peer_starter_id = derive_starter_id(&test_seed(96), 1);

    set_runtime_capsule(local_pubkey, Network::Neste);
    let payload = InvitationSentPayload {
        invitation_id,
        starter_id: StarterId::from(peer_starter_id),
        to_pubkey: local_pubkey,
        sender_root_pubkey: None,
    };
    let mut payload_bytes = payload.to_bytes();
    payload_bytes.extend_from_slice(&peer_root_pubkey);
    payload_bytes.push(1);
    append_runtime_event_with_signer(
        EventKind::InvitationReceived,
        &payload_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    let record = find_invitation_sent_in_runtime(&invitation_id).expect("lookup record");
    assert!(record.is_incoming);
    assert_eq!(record.peer_pubkey, PubKey::from(peer_pubkey));
    assert_eq!(record.starter_id, StarterId::from(peer_starter_id));
    assert_eq!(record.starter_kind, StarterKind::Spark);
    assert_eq!(
        record.sender_root_pubkey,
        Some(PubKey::from(peer_root_pubkey))
    );
}

#[test]
fn lookup_root_augmented_incoming_offer_without_slot_defaults_kind_deterministically() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(97);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [46u8; 32];
    let peer_root_pubkey = [47u8; 32];
    let invitation_id = [48u8; 32];
    let peer_starter_id = derive_starter_id(&test_seed(98), 2);

    set_runtime_capsule(local_pubkey, Network::Neste);
    let payload = InvitationSentPayload {
        invitation_id,
        starter_id: StarterId::from(peer_starter_id),
        to_pubkey: local_pubkey,
        sender_root_pubkey: None,
    };
    let mut payload_bytes = payload.to_bytes();
    payload_bytes.extend_from_slice(&peer_root_pubkey);
    // Legacy-compatible root-augmented shape without trailing starter-slot byte.
    append_runtime_event_with_signer(
        EventKind::InvitationReceived,
        &payload_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    let record = find_invitation_sent_in_runtime(&invitation_id).expect("lookup record");
    assert!(record.is_incoming);
    assert_eq!(record.peer_pubkey, PubKey::from(peer_pubkey));
    assert_eq!(record.starter_id, StarterId::from(peer_starter_id));
    assert_eq!(record.starter_kind, StarterKind::Juice);
    assert_eq!(
        record.sender_root_pubkey,
        Some(PubKey::from(peer_root_pubkey))
    );
}

#[test]
fn finalize_local_acceptance_creates_starter_and_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(7);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [3u8; 32];
    let inviter_root_pubkey = [13u8; 32];
    let invitation_id = [5u8; 32];
    let inviter_slot = 1u8;
    let peer_starter_id = derive_starter_id(&test_seed(11), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);

    let invitation_payload = InvitationSentPayload {
        invitation_id,
        starter_id: StarterId::from(peer_starter_id),
        to_pubkey: local_pubkey,
        sender_root_pubkey: None,
    };
    let mut invitation_bytes = invitation_payload.to_bytes();
    invitation_bytes.extend_from_slice(&inviter_root_pubkey);
    invitation_bytes.push(inviter_slot);
    append_runtime_event_with_signer(
        EventKind::InvitationReceived,
        &invitation_bytes,
        PubKey::from(inviter_pubkey),
    )
    .unwrap();

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
                    && payload.peer_root_pubkey == Some(PubKey::from(inviter_root_pubkey))
                    && payload.sender_root_pubkey == Some(local_pubkey)
            })
    }));
}

#[test]
fn acceptance_plan_lineage_id_depends_on_invitation_id() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(207);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [31u8; 32];
    let inviter_root_pubkey = [41u8; 32];
    let first_invitation_id = [51u8; 32];
    let second_invitation_id = [52u8; 32];
    let inviter_slot = 1u8;
    let peer_starter_id = derive_starter_id(&test_seed(208), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_incoming_invitation_with_root_for_test(
        first_invitation_id,
        peer_starter_id,
        local_pubkey,
        inviter_slot,
        inviter_pubkey,
        inviter_root_pubkey,
    );
    append_incoming_invitation_with_root_for_test(
        second_invitation_id,
        peer_starter_id,
        local_pubkey,
        inviter_slot,
        inviter_pubkey,
        inviter_root_pubkey,
    );

    let first_plan = resolve_local_acceptance_plan(&seed, first_invitation_id).unwrap();
    let second_plan = resolve_local_acceptance_plan(&seed, second_invitation_id).unwrap();
    assert_ne!(
        first_plan.relationship_starter_id,
        second_plan.relationship_starter_id
    );

    let expected_first = StarterId::from(crate::runtime_support::derive_starter_id_lineage(
        &seed,
        0,
        &first_invitation_id,
        &PubKey::from(inviter_root_pubkey),
    ));
    let expected_second = StarterId::from(crate::runtime_support::derive_starter_id_lineage(
        &seed,
        0,
        &second_invitation_id,
        &PubKey::from(inviter_root_pubkey),
    ));
    let expected_first_nonce = crate::runtime_support::derive_starter_nonce_lineage(
        &seed,
        0,
        &first_invitation_id,
        &PubKey::from(inviter_root_pubkey),
    );
    let expected_second_nonce = crate::runtime_support::derive_starter_nonce_lineage(
        &seed,
        0,
        &second_invitation_id,
        &PubKey::from(inviter_root_pubkey),
    );
    assert_eq!(first_plan.relationship_starter_id, expected_first);
    assert_eq!(second_plan.relationship_starter_id, expected_second);
    let first_created = first_plan
        .created_starter
        .expect("first acceptance should create starter");
    let second_created = second_plan
        .created_starter
        .expect("second acceptance should create starter");
    assert_eq!(first_created.0, expected_first);
    assert_eq!(second_created.0, expected_second);
    assert_eq!(first_created.2, expected_first_nonce);
    assert_eq!(second_created.2, expected_second_nonce);
    assert_ne!(first_created.2, second_created.2);
}

#[test]
fn acceptance_plan_lineage_id_falls_back_to_sender_transport_pubkey_without_root() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(209);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [32u8; 32];
    let invitation_id = [53u8; 32];
    let inviter_slot = 2u8;
    let peer_starter_id = derive_starter_id(&test_seed(210), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(inviter_slot),
        Some(inviter_pubkey),
    );

    let plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
    let expected = StarterId::from(crate::runtime_support::derive_starter_id_lineage(
        &seed,
        0,
        &invitation_id,
        &PubKey::from(inviter_pubkey),
    ));
    let expected_nonce = crate::runtime_support::derive_starter_nonce_lineage(
        &seed,
        0,
        &invitation_id,
        &PubKey::from(inviter_pubkey),
    );
    assert_eq!(plan.relationship_starter_id, expected);
    let created = plan
        .created_starter
        .expect("acceptance should create lineage starter");
    assert_eq!(created.0, expected);
    assert_eq!(created.2, expected_nonce);
}

#[test]
fn acceptance_plan_lineage_id_prefers_sender_root_over_transport_pubkey() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(211);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [33u8; 32];
    let inviter_root_pubkey = [43u8; 32];
    let invitation_id = [54u8; 32];
    let inviter_slot = 3u8;
    let peer_starter_id = derive_starter_id(&test_seed(212), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_incoming_invitation_with_root_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey,
        inviter_slot,
        inviter_pubkey,
        inviter_root_pubkey,
    );

    let plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
    let expected_with_root = StarterId::from(crate::runtime_support::derive_starter_id_lineage(
        &seed,
        0,
        &invitation_id,
        &PubKey::from(inviter_root_pubkey),
    ));
    let fallback_transport = StarterId::from(crate::runtime_support::derive_starter_id_lineage(
        &seed,
        0,
        &invitation_id,
        &PubKey::from(inviter_pubkey),
    ));
    let expected_nonce_with_root = crate::runtime_support::derive_starter_nonce_lineage(
        &seed,
        0,
        &invitation_id,
        &PubKey::from(inviter_root_pubkey),
    );
    let fallback_transport_nonce = crate::runtime_support::derive_starter_nonce_lineage(
        &seed,
        0,
        &invitation_id,
        &PubKey::from(inviter_pubkey),
    );
    assert_eq!(plan.relationship_starter_id, expected_with_root);
    assert_ne!(plan.relationship_starter_id, fallback_transport);
    let created = plan
        .created_starter
        .expect("acceptance should create lineage starter");
    assert_eq!(created.0, expected_with_root);
    assert_eq!(created.2, expected_nonce_with_root);
    assert_ne!(created.2, fallback_transport_nonce);
}

#[test]
fn acceptance_plan_use_existing_starter_derives_created_lineage_in_empty_slot() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(213);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [34u8; 32];
    let inviter_root_pubkey = [44u8; 32];
    let invitation_id = [55u8; 32];
    let inviter_slot = 0u8;
    let peer_starter_id = derive_starter_id(&test_seed(214), inviter_slot);
    let existing_local_starter_id = StarterId::from(derive_starter_id(&seed, 0));

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: existing_local_starter_id,
            nonce: derive_starter_nonce(&seed, 0),
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    append_incoming_invitation_with_root_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey,
        inviter_slot,
        inviter_pubkey,
        inviter_root_pubkey,
    );

    let plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
    assert_eq!(plan.relationship_starter_id, existing_local_starter_id);
    assert_eq!(plan.relationship_kind, StarterKind::Juice);

    let created = plan
        .created_starter
        .expect("use-existing plan should create missing starter kind");
    let expected_created_id = StarterId::from(crate::runtime_support::derive_starter_id_lineage(
        &seed,
        1,
        &invitation_id,
        &PubKey::from(inviter_root_pubkey),
    ));
    let expected_created_nonce = crate::runtime_support::derive_starter_nonce_lineage(
        &seed,
        1,
        &invitation_id,
        &PubKey::from(inviter_root_pubkey),
    );

    assert_eq!(created.0, expected_created_id);
    assert_eq!(created.1, StarterKind::Spark);
    assert_eq!(created.2, expected_created_nonce);
    assert_ne!(created.0, existing_local_starter_id);
    assert_ne!(created.0, StarterId::from(peer_starter_id));
}

#[test]
fn acceptance_plan_use_existing_starter_without_empty_slot_creates_no_lineage_starter() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(215);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [35u8; 32];
    let inviter_root_pubkey = [45u8; 32];
    let invitation_id = [56u8; 32];
    let inviter_slot = 4u8;
    let peer_starter_id = derive_starter_id(&test_seed(216), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);

    let local_starters = [
        (0u8, StarterKind::Juice),
        (1u8, StarterKind::Spark),
        (2u8, StarterKind::Seed),
        (3u8, StarterKind::Pulse),
        (4u8, StarterKind::Kick),
    ];
    for (slot, kind) in local_starters {
        append_runtime_event(
            EventKind::StarterCreated,
            &StarterCreatedPayload {
                starter_id: StarterId::from(derive_starter_id(&seed, slot)),
                nonce: derive_starter_nonce(&seed, slot),
                kind,
                network: Network::Neste.to_byte(),
            }
            .to_bytes(),
        )
        .unwrap();
    }

    append_incoming_invitation_with_root_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey,
        inviter_slot,
        inviter_pubkey,
        inviter_root_pubkey,
    );

    let plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
    assert_eq!(plan.relationship_kind, StarterKind::Kick);
    assert_eq!(
        plan.relationship_starter_id,
        StarterId::from(derive_starter_id(&seed, 4))
    );
    assert!(plan.created_starter.is_none());
}

#[test]
fn incoming_invitation_accepted_projects_outgoing_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(12);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [8u8; 32];
    let peer_root_pubkey = [18u8; 32];
    let invitation_id = [4u8; 32];
    let own_starter_id = derive_starter_id(&test_seed(12), 0);
    let peer_starter_id = derive_starter_id(&test_seed(13), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let payload = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_starter_id),
        accepter_root_pubkey: Some(PubKey::from(peer_root_pubkey)),
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
                    && projected.peer_root_pubkey == Some(PubKey::from(peer_root_pubkey))
                    && projected.sender_root_pubkey == Some(local_pubkey)
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
        accepter_root_pubkey: None,
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
        accepter_root_pubkey: None,
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
fn incoming_empty_slot_reject_burns_sender_starter_for_root_augmented_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(121);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [54u8; 32];
    let invitation_id = [55u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 4);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(own_starter_id),
            nonce: derive_starter_nonce(&local_seed, 4),
            kind: StarterKind::Kick,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    let payload = InvitationSentPayload {
        invitation_id,
        starter_id: StarterId::from(own_starter_id),
        to_pubkey: PubKey::from(peer_pubkey),
        sender_root_pubkey: Some(local_pubkey),
    };
    let mut bytes = payload.to_bytes();
    bytes.push(4);
    append_runtime_event(EventKind::InvitationSent, &bytes).unwrap();

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
fn outgoing_direction_lookup_does_not_fallback_to_incoming_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(122);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [56u8; 32];
    let invitation_id = [57u8; 32];
    let peer_starter_id = derive_starter_id(&test_seed(123), 1);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(1),
        Some(peer_pubkey),
    );

    let outgoing = crate::invitation_support::find_invitation_sent_in_runtime_with_direction(
        &invitation_id,
        Some(false),
    );
    let incoming = crate::invitation_support::find_invitation_sent_in_runtime_with_direction(
        &invitation_id,
        Some(true),
    );

    assert!(outgoing.is_none());
    assert!(incoming.is_some_and(|record| record.is_incoming));
}

#[test]
fn burned_starter_id_is_not_reused_on_later_accept() {
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
    assert_ne!(
        acceptance_plan.relationship_starter_id.as_bytes(),
        &local_starter_id,
    );
    assert!(acceptance_plan.created_starter.is_some());

    finalize_local_acceptance(&engine, &acceptance_plan, inviter_pubkey).unwrap();

    let created_with_old_id = runtime_events()
        .into_iter()
        .filter(|event| {
            event.kind() == EventKind::StarterCreated
                && StarterCreatedPayload::from_bytes(event.payload())
                    .is_ok_and(|payload| payload.starter_id.as_bytes() == &local_starter_id)
        })
        .count();

    assert_eq!(created_with_old_id, 1);
}

#[test]
fn active_slot_starter_identity_tracks_new_starter_after_burn() {
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

    let next_cycle_id = StarterId::from(derive_starter_id(&test_seed(193), slot));
    let next_cycle_nonce = derive_starter_nonce(&test_seed(193), slot);

    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: next_cycle_id,
            nonce: next_cycle_nonce,
            kind: StarterKind::Spark,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();

    assert_eq!(active_starter_id_for_slot(slot), Some(next_cycle_id));
}

#[test]
fn next_cycle_starter_can_burn_again_in_new_invitation_cycle() {
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

    let next_cycle_starter_id = derive_starter_id(&test_seed(194), slot);
    let next_cycle_nonce = derive_starter_nonce(&test_seed(194), slot);

    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(next_cycle_starter_id),
            nonce: next_cycle_nonce,
            kind: StarterKind::Juice,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();
    assert_eq!(
        active_starter_id_for_slot(slot),
        Some(StarterId::from(next_cycle_starter_id))
    );

    append_invitation_sent_for_test(
        second_invitation_id,
        next_cycle_starter_id,
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
        peer_root_pubkey: None,
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
fn ffi_identity_boundary_keeps_root_and_transport_split() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(92);
    let seed_bytes = seed.as_bytes();
    let mut root_pubkey = [0u8; 32];
    let mut nostr_pubkey = [0u8; 32];

    unsafe {
        assert_eq!(
            hivra_seed_root_public_key(seed_bytes.as_ptr(), root_pubkey.as_mut_ptr()),
            0
        );
        assert_eq!(
            hivra_seed_nostr_public_key(seed_bytes.as_ptr(), nostr_pubkey.as_mut_ptr()),
            0
        );
    }
    assert_ne!(root_pubkey, nostr_pubkey);

    init_runtime_state(
        &seed,
        Network::Neste,
        CapsuleType::Leaf,
        CapsuleOwnerMode::Root,
    )
    .expect("init runtime root owner");
    let mut runtime_owner_root = [0u8; 32];
    unsafe {
        assert_eq!(
            hivra_capsule_runtime_owner_public_key(runtime_owner_root.as_mut_ptr()),
            0
        );
    }
    assert_eq!(runtime_owner_root, root_pubkey);
    clear_runtime_state();

    init_runtime_state(
        &seed,
        Network::Neste,
        CapsuleType::Leaf,
        CapsuleOwnerMode::LegacyNostr,
    )
    .expect("init runtime legacy nostr owner");
    let mut runtime_owner_legacy = [0u8; 32];
    unsafe {
        assert_eq!(
            hivra_capsule_runtime_owner_public_key(runtime_owner_legacy.as_mut_ptr()),
            0
        );
    }
    assert_eq!(runtime_owner_legacy, nostr_pubkey);
    clear_runtime_state();
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
        accepter_root_pubkey: None,
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
        accepter_root_pubkey: None,
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
        accepter_root_pubkey: None,
    };

    assert!(!should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_terminal_event_without_matching_outgoing_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(141);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [126u8; 32];
    let invitation_id = [148u8; 32];
    let peer_created_starter_id = derive_starter_id(&test_seed(142), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);

    let accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_created_starter_id),
        accepter_root_pubkey: None,
    };

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_rejected_without_matching_outgoing_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(142);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [127u8; 32];
    let invitation_id = [149u8; 32];

    set_runtime_capsule(local_pubkey, Network::Neste);

    let rejected = InvitationRejectedPayload {
        invitation_id,
        reason: RejectReason::Other,
    };

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationRejected,
        &rejected.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_expired_without_matching_outgoing_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(145);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [129u8; 32];
    let invitation_id = [151u8; 32];

    set_runtime_capsule(local_pubkey, Network::Neste);

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_allows_first_expired_for_unresolved_outgoing_invitation() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(146);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [130u8; 32];
    let invitation_id = [152u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    assert!(!should_skip_incoming_delivery_append(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_conflicting_rejected_after_accepted_resolution() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(143);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [128u8; 32];
    let invitation_id = [150u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_created_starter_id = derive_starter_id(&test_seed(144), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);
    append_runtime_event(
        EventKind::InvitationAccepted,
        &InvitationAcceptedPayload {
            invitation_id,
            from_pubkey: local_pubkey,
            created_starter_id: StarterId::from(peer_created_starter_id),
            accepter_root_pubkey: None,
        }
        .to_bytes(),
    )
    .unwrap();

    let rejected = InvitationRejectedPayload {
        invitation_id,
        reason: RejectReason::Other,
    };

    assert!(invitation_is_resolved_in_runtime(&invitation_id));
    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationRejected,
        &rejected.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_conflicting_expired_after_accepted_resolution() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(147);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [131u8; 32];
    let invitation_id = [153u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_created_starter_id = derive_starter_id(&test_seed(148), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);
    append_runtime_event(
        EventKind::InvitationAccepted,
        &InvitationAcceptedPayload {
            invitation_id,
            from_pubkey: local_pubkey,
            created_starter_id: StarterId::from(peer_created_starter_id),
            accepter_root_pubkey: None,
        }
        .to_bytes(),
    )
    .unwrap();

    assert!(invitation_is_resolved_in_runtime(&invitation_id));
    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_conflicting_accepted_after_expired_resolution() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(151);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [135u8; 32];
    let invitation_id = [157u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_created_starter_id = derive_starter_id(&test_seed(152), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);
    append_runtime_event(EventKind::InvitationExpired, &invitation_id).unwrap();

    let accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_created_starter_id),
        accepter_root_pubkey: None,
    };

    assert!(invitation_is_resolved_in_runtime(&invitation_id));
    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &accepted.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_stays_stable_on_long_lived_history_after_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(173);
    let local_pubkey = derived_pubkey(&local_seed);
    let local_starter_id = derive_starter_id(&local_seed, 0);
    let accepted_id = [180u8; 32];
    let rejected_id = [181u8; 32];
    let expired_id = [182u8; 32];
    let pending_id = [183u8; 32];
    let accepted_peer = [84u8; 32];
    let rejected_peer = [85u8; 32];
    let expired_peer = [86u8; 32];
    let pending_peer = [87u8; 32];

    set_runtime_capsule(local_pubkey, Network::Neste);

    append_invitation_sent_for_test(accepted_id, local_starter_id, accepted_peer, Some(0), None);
    append_invitation_sent_for_test(rejected_id, local_starter_id, rejected_peer, Some(0), None);
    append_invitation_sent_for_test(expired_id, local_starter_id, expired_peer, Some(0), None);
    append_invitation_sent_for_test(pending_id, local_starter_id, pending_peer, Some(0), None);

    let accepted_payload = InvitationAcceptedPayload {
        invitation_id: accepted_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(derive_starter_id(&test_seed(174), 0)),
        accepter_root_pubkey: None,
    };
    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &accepted_payload.to_bytes(),
        PubKey::from(accepted_peer),
    )
    .unwrap();

    let rejected_payload = InvitationRejectedPayload {
        invitation_id: rejected_id,
        reason: RejectReason::Other,
    };
    append_runtime_event(EventKind::InvitationRejected, &rejected_payload.to_bytes()).unwrap();
    append_runtime_event(EventKind::InvitationExpired, &expired_id).unwrap();

    for offset in 0u8..20u8 {
        let invitation_id = [190u8.wrapping_add(offset); 32];
        let peer_pubkey = [100u8.wrapping_add(offset); 32];
        append_invitation_sent_for_test(
            invitation_id,
            local_starter_id,
            peer_pubkey,
            Some(0),
            None,
        );
        match offset % 4 {
            0 => {
                let payload = InvitationAcceptedPayload {
                    invitation_id,
                    from_pubkey: local_pubkey,
                    created_starter_id: StarterId::from(derive_starter_id(
                        &test_seed(200u8.wrapping_add(offset)),
                        0,
                    )),
                    accepter_root_pubkey: None,
                };
                append_runtime_event_with_signer(
                    EventKind::InvitationAccepted,
                    &payload.to_bytes(),
                    PubKey::from(peer_pubkey),
                )
                .unwrap();
            }
            1 => {
                append_runtime_event(
                    EventKind::InvitationRejected,
                    &InvitationRejectedPayload {
                        invitation_id,
                        reason: RejectReason::Other,
                    }
                    .to_bytes(),
                )
                .unwrap();
            }
            2 => {
                append_runtime_event(EventKind::InvitationExpired, &invitation_id).unwrap();
            }
            _ => {}
        }
    }

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert!(invitation_is_resolved_in_runtime(&accepted_id));
    assert!(invitation_is_resolved_in_runtime(&rejected_id));
    assert!(invitation_is_resolved_in_runtime(&expired_id));
    assert!(!invitation_is_resolved_in_runtime(&pending_id));

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &accepted_payload.to_bytes(),
        PubKey::from(accepted_peer),
    ));
    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationRejected,
        &rejected_payload.to_bytes(),
        PubKey::from(rejected_peer),
    ));
    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationExpired,
        &expired_id,
        PubKey::from(expired_peer),
    ));

    let conflicting_accepted_for_rejected = InvitationAcceptedPayload {
        invitation_id: rejected_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(derive_starter_id(&test_seed(175), 0)),
        accepter_root_pubkey: None,
    };
    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &conflicting_accepted_for_rejected.to_bytes(),
        PubKey::from(rejected_peer),
    ));

    let conflicting_rejected_for_accepted = InvitationRejectedPayload {
        invitation_id: accepted_id,
        reason: RejectReason::Other,
    };
    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationRejected,
        &conflicting_rejected_for_accepted.to_bytes(),
        PubKey::from(accepted_peer),
    ));

    let first_terminal_for_pending = InvitationAcceptedPayload {
        invitation_id: pending_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(derive_starter_id(&test_seed(176), 0)),
        accepter_root_pubkey: None,
    };
    assert!(!should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &first_terminal_for_pending.to_bytes(),
        PubKey::from(pending_peer),
    ));
}

#[test]
fn replay_policy_skips_out_of_order_accepted_before_outgoing_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(148);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [132u8; 32];
    let invitation_id = [154u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_created_starter_id = derive_starter_id(&test_seed(149), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);

    let accepted = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_created_starter_id),
        accepter_root_pubkey: None,
    };
    let accepted_bytes = accepted.to_bytes();

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationAccepted,
        &accepted_bytes,
        PubKey::from(peer_pubkey),
    ));
    if !should_skip_incoming_delivery_append(
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
        let engine = build_engine(&local_seed);
        project_relationship_from_invitation_accepted(&engine, peer_pubkey, &accepted).unwrap();
    }

    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    assert_eq!(invitation_accepted_count(), 0);
    assert_eq!(relationship_established_count(), 0);
    assert!(!invitation_is_resolved_in_runtime(&invitation_id));
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationSent,
        &invitation_id,
        local_pubkey,
    ));
}

#[test]
fn replay_policy_skips_out_of_order_rejected_before_outgoing_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(149);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [133u8; 32];
    let invitation_id = [155u8; 32];
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

    let rejected = InvitationRejectedPayload {
        invitation_id,
        reason: RejectReason::EmptySlot,
    };
    let rejected_bytes = rejected.to_bytes();

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationRejected,
        &rejected_bytes,
        PubKey::from(peer_pubkey),
    ));
    if !should_skip_incoming_delivery_append(
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
        let engine = build_engine(&local_seed);
        project_effects_from_invitation_rejected(&engine, &rejected).unwrap();
    }

    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    assert_eq!(starter_burned_count(), 0);
    assert!(!invitation_is_resolved_in_runtime(&invitation_id));
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationSent,
        &invitation_id,
        local_pubkey,
    ));
}

#[test]
fn replay_policy_skips_out_of_order_expired_before_outgoing_offer() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(150);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [134u8; 32];
    let invitation_id = [156u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);

    assert!(should_skip_incoming_delivery_append(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));
    if !should_skip_incoming_delivery_append(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ) {
        append_runtime_event_with_signer(
            EventKind::InvitationExpired,
            &invitation_id,
            PubKey::from(peer_pubkey),
        )
        .unwrap();
    }

    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    assert!(!invitation_is_resolved_in_runtime(&invitation_id));
    assert!(invitation_offer_exists_in_runtime(
        EventKind::InvitationSent,
        &invitation_id,
        local_pubkey,
    ));
}

#[test]
fn replay_policy_skips_relationship_established_without_accepted_anchor() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(153);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [137u8; 32];
    let invitation_id = [159u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(154), 0);

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
        peer_root_pubkey: None,
        sender_root_pubkey: None,
    };

    assert!(should_skip_incoming_delivery_append(
        EventKind::RelationshipEstablished,
        &established.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_out_of_order_relationship_broken_without_active_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(154);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [138u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);

    let broken = RelationshipBrokenPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_root_pubkey: None,
    };

    assert!(should_skip_incoming_delivery_append(
        EventKind::RelationshipBroken,
        &broken.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_allows_first_relationship_broken_for_active_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(155);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [139u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(156), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event_with_signer(
        EventKind::RelationshipEstablished,
        &RelationshipEstablishedPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(own_starter_id),
            peer_starter_id: StarterId::from(peer_starter_id),
            kind: StarterKind::Juice,
            invitation_id: [160u8; 32],
            sender_pubkey: PubKey::from(peer_pubkey),
            sender_starter_type: StarterKind::Juice,
            sender_starter_id: StarterId::from(peer_starter_id),
            peer_root_pubkey: None,
            sender_root_pubkey: None,
        }
        .to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    let broken = RelationshipBrokenPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_root_pubkey: None,
    };

    assert!(!should_skip_incoming_delivery_append(
        EventKind::RelationshipBroken,
        &broken.to_bytes(),
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_allows_relationship_broken_after_reestablish_with_same_payload() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(255);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [201u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(206), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);

    let established = RelationshipEstablishedPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_starter_id: StarterId::from(peer_starter_id),
        kind: StarterKind::Juice,
        invitation_id: [202u8; 32],
        sender_pubkey: PubKey::from(peer_pubkey),
        sender_starter_type: StarterKind::Juice,
        sender_starter_id: StarterId::from(peer_starter_id),
        peer_root_pubkey: None,
        sender_root_pubkey: None,
    };
    let broken = RelationshipBrokenPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_root_pubkey: None,
    };
    let broken_bytes = broken.to_bytes();

    // Episode 1: establish -> break.
    append_runtime_event_with_signer(
        EventKind::RelationshipEstablished,
        &established.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    append_runtime_event_with_signer(
        EventKind::RelationshipBroken,
        &broken_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    // Episode 2: re-establish same relationship key.
    append_runtime_event_with_signer(
        EventKind::RelationshipEstablished,
        &established.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    // Incoming second break must be allowed even with identical payload+signer.
    assert!(!should_skip_incoming_delivery_append(
        EventKind::RelationshipBroken,
        &broken_bytes,
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_duplicate_relationship_broken_without_reestablish() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(207);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [203u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(208), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);

    let established = RelationshipEstablishedPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_starter_id: StarterId::from(peer_starter_id),
        kind: StarterKind::Kick,
        invitation_id: [204u8; 32],
        sender_pubkey: PubKey::from(peer_pubkey),
        sender_starter_type: StarterKind::Kick,
        sender_starter_id: StarterId::from(peer_starter_id),
        peer_root_pubkey: None,
        sender_root_pubkey: None,
    };
    let broken = RelationshipBrokenPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_root_pubkey: None,
    };
    let broken_bytes = broken.to_bytes();

    append_runtime_event_with_signer(
        EventKind::RelationshipEstablished,
        &established.to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    append_runtime_event_with_signer(
        EventKind::RelationshipBroken,
        &broken_bytes,
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    // Same break replay while key is not active is still a duplicate.
    assert!(should_skip_incoming_delivery_append(
        EventKind::RelationshipBroken,
        &broken_bytes,
        PubKey::from(peer_pubkey),
    ));
}

#[test]
fn replay_policy_skips_replayed_relationship_established_after_local_break() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(156);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [140u8; 32];
    let invitation_id = [161u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(157), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event_with_signer(
        EventKind::InvitationAccepted,
        &InvitationAcceptedPayload {
            invitation_id,
            from_pubkey: local_pubkey,
            created_starter_id: StarterId::from(peer_starter_id),
            accepter_root_pubkey: None,
        }
        .to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    append_runtime_event_with_signer(
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
            peer_root_pubkey: None,
            sender_root_pubkey: None,
        }
        .to_bytes(),
        PubKey::from(peer_pubkey),
    )
    .unwrap();
    append_runtime_event(
        EventKind::RelationshipBroken,
        &RelationshipBrokenPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(own_starter_id),
            peer_root_pubkey: None,
        }
        .to_bytes(),
    )
    .unwrap();

    let replayed_established_with_variant_payload = RelationshipEstablishedPayload {
        peer_pubkey: PubKey::from(peer_pubkey),
        own_starter_id: StarterId::from(own_starter_id),
        peer_starter_id: StarterId::from(peer_starter_id),
        kind: StarterKind::Juice,
        invitation_id,
        sender_pubkey: PubKey::from(peer_pubkey),
        sender_starter_type: StarterKind::Juice,
        sender_starter_id: StarterId::from(peer_starter_id),
        peer_root_pubkey: Some(PubKey::from([7u8; 32])),
        sender_root_pubkey: Some(PubKey::from([8u8; 32])),
    };
    assert!(should_skip_incoming_delivery_append(
        EventKind::RelationshipEstablished,
        &replayed_established_with_variant_payload.to_bytes(),
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
        accepter_root_pubkey: None,
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
fn replayed_invitation_expired_is_skipped_after_export_import() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(153);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [136u8; 32];
    let invitation_id = [158u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    append_runtime_event_with_signer(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    )
    .unwrap();

    assert_eq!(invitation_expired_count(), 1);

    let exported = export_runtime_ledger().unwrap();
    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    assert!(event_exists_in_runtime_with_signer(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ));

    // Mimic delivery replay guard path: duplicate expired message must be ignored.
    if !event_exists_in_runtime_with_signer(
        EventKind::InvitationExpired,
        &invitation_id,
        PubKey::from(peer_pubkey),
    ) {
        append_runtime_event_with_signer(
            EventKind::InvitationExpired,
            &invitation_id,
            PubKey::from(peer_pubkey),
        )
        .unwrap();
    }

    assert_eq!(invitation_expired_count(), 1);
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
        peer_root_pubkey: None,
        sender_root_pubkey: None,
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
        peer_root_pubkey: None,
        sender_root_pubkey: None,
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
        peer_root_pubkey: None,
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
fn repeated_import_of_same_ledger_keeps_projection_stable() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(201);
    let local_pubkey = derived_pubkey(&local_seed);
    let first_peer_pubkey = [141u8; 32];
    let second_peer_pubkey = [142u8; 32];
    let resolved_invitation_id = [171u8; 32];
    let pending_invitation_id = [172u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_runtime_event(
        EventKind::StarterCreated,
        &StarterCreatedPayload {
            starter_id: StarterId::from(own_starter_id),
            nonce: derive_starter_nonce(&local_seed, 0),
            kind: StarterKind::Kick,
            network: Network::Neste.to_byte(),
        }
        .to_bytes(),
    )
    .unwrap();
    append_invitation_sent_for_test(
        resolved_invitation_id,
        own_starter_id,
        first_peer_pubkey,
        Some(0),
        None,
    );
    append_runtime_event_with_signer(
        EventKind::InvitationRejected,
        &InvitationRejectedPayload {
            invitation_id: resolved_invitation_id,
            reason: RejectReason::Other,
        }
        .to_bytes(),
        PubKey::from(first_peer_pubkey),
    )
    .unwrap();
    append_invitation_sent_for_test(
        pending_invitation_id,
        own_starter_id,
        second_peer_pubkey,
        Some(0),
        None,
    );

    let exported = export_runtime_ledger().unwrap();

    clear_runtime_state();
    set_runtime_capsule(local_pubkey, Network::Neste);
    import_runtime_ledger(&exported).unwrap();

    let first_import_events = runtime_events();
    let first_import_state = runtime_capsule_state();
    assert!(invitation_is_resolved_in_runtime(&resolved_invitation_id));
    assert!(!invitation_is_resolved_in_runtime(&pending_invitation_id));

    import_runtime_ledger(&exported).unwrap();

    let second_import_events = runtime_events();
    let second_import_state = runtime_capsule_state();
    assert_eq!(second_import_events.len(), first_import_events.len());
    assert_eq!(second_import_state.version, first_import_state.version);
    assert_eq!(
        second_import_state.ledger_hash,
        first_import_state.ledger_hash
    );
    assert_eq!(
        second_import_state.relationships_count,
        first_import_state.relationships_count
    );
    assert_eq!(second_import_state.slots, first_import_state.slots);
    assert!(invitation_is_resolved_in_runtime(&resolved_invitation_id));
    assert!(!invitation_is_resolved_in_runtime(&pending_invitation_id));

    let re_exported = export_runtime_ledger().unwrap();
    let exported_value: serde_json::Value = serde_json::from_str(&exported).unwrap();
    let re_exported_value: serde_json::Value = serde_json::from_str(&re_exported).unwrap();
    assert_eq!(re_exported_value, exported_value);
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
fn import_runtime_ledger_rejects_history_without_capsule_birth() {
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
        sender_root_pubkey: None,
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
    let err = import_runtime_ledger(&imported_json).unwrap_err();
    assert_eq!(err, "ledger missing capsule birth");
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
                sender_root_pubkey: None,
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
    assert_eq!(err, "ledger missing capsule birth");
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
            peer_root_pubkey: None,
            sender_root_pubkey: None,
        }
        .to_bytes(),
    )
    .unwrap();
    append_runtime_event(
        EventKind::RelationshipBroken,
        &RelationshipBrokenPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(own_starter_id),
            peer_root_pubkey: None,
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
        accepter_root_pubkey: None,
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
            peer_root_pubkey: None,
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
        accepter_root_pubkey: None,
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
        accepter_root_pubkey: None,
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
            peer_root_pubkey: None,
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
        accepter_root_pubkey: None,
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
fn sending_reinvite_to_active_peer_does_not_append_hidden_break_events() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(171);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [71u8; 32];
    let invitation_id = [72u8; 32];
    let local_starter_id = derive_starter_id(&local_seed, 0);
    let peer_starter_id = derive_starter_id(&test_seed(172), 0);

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
    append_runtime_event(
        EventKind::RelationshipEstablished,
        &RelationshipEstablishedPayload {
            peer_pubkey: PubKey::from(peer_pubkey),
            own_starter_id: StarterId::from(local_starter_id),
            peer_starter_id: StarterId::from(peer_starter_id),
            kind: StarterKind::Juice,
            invitation_id,
            sender_pubkey: PubKey::from(peer_pubkey),
            sender_starter_type: StarterKind::Juice,
            sender_starter_id: StarterId::from(peer_starter_id),
            peer_root_pubkey: None,
            sender_root_pubkey: Some(local_pubkey),
        }
        .to_bytes(),
    )
    .unwrap();

    let baseline_relationship_count = runtime_capsule_state().relationships_count;
    let baseline_broken_count = relationship_broken_count();
    let baseline_invitation_sent_count = invitation_sent_count();

    let engine = build_engine(&local_seed);
    let prepared = engine
        .prepare_invitation_sent(StarterId::from(local_starter_id), PubKey::from(peer_pubkey))
        .unwrap();
    append_prepared_event(prepared).unwrap();

    assert_eq!(relationship_broken_count(), baseline_broken_count);
    assert_eq!(
        runtime_capsule_state().relationships_count,
        baseline_relationship_count
    );
    assert_eq!(invitation_sent_count(), baseline_invitation_sent_count + 1);
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
        accepter_root_pubkey: None,
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
