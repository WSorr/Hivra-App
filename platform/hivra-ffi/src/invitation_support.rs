use super::*;
use crate::runtime_support::{
    derive_starter_id_lineage, derive_starter_nonce_lineage, starter_is_active_in_runtime,
};
use hivra_core::event_payloads::{RelationshipBrokenPayload, RelationshipEstablishedPayload};
use std::collections::HashSet;

#[derive(Clone, Copy)]
pub(crate) struct InvitationLookupRecord {
    pub(crate) starter_id: StarterId,
    pub(crate) starter_kind: StarterKind,
    pub(crate) peer_pubkey: PubKey,
    pub(crate) is_incoming: bool,
    pub(crate) sender_root_pubkey: Option<PubKey>,
}

pub(crate) struct PendingOutgoingInvitationDelivery {
    pub(crate) invitation_id: [u8; 32],
    pub(crate) to_pubkey: [u8; 32],
    pub(crate) payload: Vec<u8>,
    pub(crate) timestamp: u64,
}

fn invitation_payload_has_known_shape(payload: &[u8]) -> bool {
    payload.len() == 96 || payload.len() == 97 || payload.len() == 128 || payload.len() == 129
}

fn invitation_id_from_outgoing_payload(payload: &[u8]) -> Option<[u8; 32]> {
    if !invitation_payload_has_known_shape(payload) {
        return None;
    }
    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(&payload[..32]);
    Some(invitation_id)
}

fn invitation_payload_sender_root(payload: &[u8]) -> Option<PubKey> {
    if payload.len() >= 128 {
        let mut root = [0u8; 32];
        root.copy_from_slice(&payload[96..128]);
        Some(PubKey::from(root))
    } else {
        None
    }
}

fn invitation_payload_starter_kind(payload: &[u8]) -> Option<StarterKind> {
    if payload.len() == 97 {
        return starter_kind_from_slot(payload[96]);
    }
    if payload.len() == 129 {
        return starter_kind_from_slot(payload[128]);
    }
    None
}

fn find_starter_kind_by_id_in_ledger(
    ledger: &Ledger,
    starter_id: &[u8; 32],
) -> Option<StarterKind> {
    let owner = ledger.owner();
    for event in ledger.events().iter().rev() {
        if event.kind() != EventKind::StarterCreated || event.signer() != owner {
            continue;
        }
        let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) else {
            continue;
        };
        if payload.starter_id.as_bytes() == starter_id {
            return Some(payload.kind);
        }
    }
    None
}

pub(crate) fn find_invitation_sent_in_runtime(
    invitation_id: &[u8; 32],
) -> Option<InvitationLookupRecord> {
    find_invitation_sent_in_runtime_with_direction(invitation_id, None)
}

pub(crate) fn invitation_offer_exists_in_runtime(
    kind: EventKind,
    invitation_id: &[u8; 32],
    signer: PubKey,
) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule.ledger.events().iter().any(|event| {
        if event.kind() != kind || event.signer() != &signer {
            return false;
        }
        let payload = event.payload();
        if !invitation_payload_has_known_shape(payload) {
            return false;
        }
        &payload[..32] == invitation_id
    })
}

pub(crate) fn invitation_is_resolved_in_runtime(invitation_id: &[u8; 32]) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule.ledger.events().iter().any(|event| {
        let payload = event.payload();
        match event.kind() {
            EventKind::InvitationAccepted if payload.len() == 96 || payload.len() == 128 => {
                &payload[..32] == invitation_id
            }
            EventKind::InvitationRejected if payload.len() == 33 => &payload[..32] == invitation_id,
            EventKind::InvitationExpired if payload.len() == 32 => payload == invitation_id,
            _ => false,
        }
    })
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct RelationshipKey {
    peer_pubkey: PubKey,
    own_starter_id: StarterId,
}

fn relationship_key_from_established_payload(payload: &[u8]) -> Option<RelationshipKey> {
    let parsed = RelationshipEstablishedPayload::from_bytes(payload).ok()?;
    Some(RelationshipKey {
        peer_pubkey: parsed.peer_pubkey,
        own_starter_id: parsed.own_starter_id,
    })
}

fn relationship_key_from_broken_payload(payload: &[u8]) -> Option<RelationshipKey> {
    let parsed = RelationshipBrokenPayload::from_bytes(payload).ok()?;
    Some(RelationshipKey {
        peer_pubkey: parsed.peer_pubkey,
        own_starter_id: parsed.own_starter_id,
    })
}

fn relationship_key_is_active_in_runtime(target: RelationshipKey) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    let mut active = false;
    for event in capsule.ledger.events() {
        match event.kind() {
            EventKind::RelationshipEstablished => {
                let Some(key) = relationship_key_from_established_payload(event.payload()) else {
                    continue;
                };
                if key == target {
                    active = true;
                }
            }
            EventKind::RelationshipBroken => {
                let Some(key) = relationship_key_from_broken_payload(event.payload()) else {
                    continue;
                };
                if key == target {
                    active = false;
                }
            }
            _ => {}
        }
    }

    active
}

fn relationship_established_exists_for_invitation_in_runtime(invitation_id: &[u8; 32]) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule.ledger.events().iter().any(|event| {
        if event.kind() != EventKind::RelationshipEstablished {
            return false;
        }
        RelationshipEstablishedPayload::from_bytes(event.payload())
            .is_ok_and(|payload| &payload.invitation_id == invitation_id)
    })
}

fn invitation_accepted_exists_in_runtime(invitation_id: &[u8; 32]) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule.ledger.events().iter().any(|event| {
        if event.kind() != EventKind::InvitationAccepted {
            return false;
        }
        InvitationAcceptedPayload::from_bytes(event.payload())
            .is_ok_and(|payload| &payload.invitation_id == invitation_id)
    })
}

pub(crate) fn invitation_id_from_terminal_payload(
    kind: EventKind,
    payload: &[u8],
) -> Option<[u8; 32]> {
    match kind {
        EventKind::InvitationAccepted if payload.len() == 96 || payload.len() == 128 => {
            let mut invitation_id = [0u8; 32];
            invitation_id.copy_from_slice(&payload[..32]);
            Some(invitation_id)
        }
        EventKind::InvitationRejected if payload.len() == 33 => {
            let mut invitation_id = [0u8; 32];
            invitation_id.copy_from_slice(&payload[..32]);
            Some(invitation_id)
        }
        EventKind::InvitationExpired if payload.len() == 32 => {
            let mut invitation_id = [0u8; 32];
            invitation_id.copy_from_slice(payload);
            Some(invitation_id)
        }
        _ => None,
    }
}

pub(crate) fn pending_outgoing_invitation_deliveries_in_runtime(
    local_pubkey: PubKey,
) -> Vec<PendingOutgoingInvitationDelivery> {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return Vec::new();
    };

    let mut resolved_ids: HashSet<[u8; 32]> = HashSet::new();
    for event in capsule.ledger.events() {
        if let Some(invitation_id) =
            invitation_id_from_terminal_payload(event.kind(), event.payload())
        {
            resolved_ids.insert(invitation_id);
        }
    }

    let local_bytes = local_pubkey.as_bytes();
    let mut yielded_ids: HashSet<[u8; 32]> = HashSet::new();
    let mut pending = Vec::new();
    for event in capsule.ledger.events() {
        if event.kind() != EventKind::InvitationSent {
            continue;
        }
        if event.signer().as_bytes() != local_bytes {
            continue;
        }

        let payload = event.payload();
        let Some(invitation_id) = invitation_id_from_outgoing_payload(payload) else {
            continue;
        };
        if resolved_ids.contains(&invitation_id) || !yielded_ids.insert(invitation_id) {
            continue;
        }

        let mut to_pubkey = [0u8; 32];
        to_pubkey.copy_from_slice(&payload[64..96]);
        if to_pubkey == *local_bytes {
            continue;
        }

        pending.push(PendingOutgoingInvitationDelivery {
            invitation_id,
            to_pubkey,
            payload: payload.to_vec(),
            timestamp: event.timestamp().as_u64(),
        });
    }

    pending
}

pub(crate) fn should_skip_incoming_delivery_append(
    local_kind: EventKind,
    payload: &[u8],
    signer: PubKey,
) -> bool {
    if local_kind == EventKind::RelationshipEstablished {
        let Some(parsed) = RelationshipEstablishedPayload::from_bytes(payload).ok() else {
            return true;
        };
        if parsed.peer_pubkey != signer {
            return true;
        }
        if !invitation_accepted_exists_in_runtime(&parsed.invitation_id) {
            return true;
        }
        if relationship_established_exists_for_invitation_in_runtime(&parsed.invitation_id) {
            return true;
        }
        if relationship_key_is_active_in_runtime(RelationshipKey {
            peer_pubkey: parsed.peer_pubkey,
            own_starter_id: parsed.own_starter_id,
        }) {
            return true;
        }
    }

    if local_kind == EventKind::RelationshipBroken {
        let Some(parsed) = RelationshipBrokenPayload::from_bytes(payload).ok() else {
            return true;
        };
        if parsed.peer_pubkey != signer {
            return true;
        }
        if !relationship_key_is_active_in_runtime(RelationshipKey {
            peer_pubkey: parsed.peer_pubkey,
            own_starter_id: parsed.own_starter_id,
        }) {
            return true;
        }
        // Do not dedupe RelationshipBroken by raw payload/signer when the
        // pair is currently active. The same relationship key can be
        // re-established later and then broken again with identical payload.
        return false;
    }

    if local_kind == EventKind::InvitationReceived && payload.len() >= 32 {
        let mut invitation_id = [0u8; 32];
        invitation_id.copy_from_slice(&payload[..32]);
        if invitation_is_resolved_in_runtime(&invitation_id) {
            return true;
        }
        if invitation_offer_exists_in_runtime(local_kind, &invitation_id, signer) {
            return true;
        }
    }

    if let Some(invitation_id) = invitation_id_from_terminal_payload(local_kind, payload) {
        if invitation_is_resolved_in_runtime(&invitation_id) {
            return true;
        }
        if (local_kind == EventKind::InvitationAccepted
            || local_kind == EventKind::InvitationRejected
            || local_kind == EventKind::InvitationExpired)
            && find_invitation_sent_in_runtime_with_direction(&invitation_id, Some(false)).is_none()
        {
            // Terminal delivery must resolve an existing outgoing offer.
            // Otherwise we can append orphan terminal events that
            // inflate local projection without a matching InvitationSent.
            return true;
        }
    }

    event_exists_in_runtime_with_signer(local_kind, payload, signer)
}

pub(crate) fn find_invitation_sent_in_runtime_with_direction(
    invitation_id: &[u8; 32],
    expect_incoming: Option<bool>,
) -> Option<InvitationLookupRecord> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref()?;
    let local_pubkey = capsule.pubkey;

    for event in capsule.ledger.events() {
        let event_kind = event.kind();
        if event_kind != EventKind::InvitationSent && event_kind != EventKind::InvitationReceived {
            continue;
        }

        let payload = event.payload();
        if !invitation_payload_has_known_shape(payload) {
            continue;
        }

        let mut current_invitation_id = [0u8; 32];
        current_invitation_id.copy_from_slice(&payload[..32]);
        if current_invitation_id != *invitation_id {
            continue;
        }

        let mut starter_id = [0u8; 32];
        starter_id.copy_from_slice(&payload[32..64]);

        let mut addressed_to = [0u8; 32];
        addressed_to.copy_from_slice(&payload[64..96]);
        let signer = *event.signer().as_bytes();

        let is_incoming = event_kind == EventKind::InvitationReceived
            || (addressed_to == local_pubkey.as_bytes().to_owned()
                && signer != local_pubkey.as_bytes().to_owned());

        let mut peer_pubkey = [0u8; 32];
        if is_incoming {
            peer_pubkey.copy_from_slice(&signer);
        } else {
            peer_pubkey.copy_from_slice(&addressed_to);
        }

        let kind = invitation_payload_starter_kind(payload).unwrap_or_else(|| {
            find_starter_kind_by_id_in_ledger(&capsule.ledger, &starter_id)
                .unwrap_or(StarterKind::Juice)
        });
        let candidate = InvitationLookupRecord {
            starter_id: StarterId::from(starter_id),
            starter_kind: kind,
            peer_pubkey: PubKey::from(peer_pubkey),
            is_incoming,
            sender_root_pubkey: invitation_payload_sender_root(payload),
        };
        match expect_incoming {
            Some(expected) if expected == is_incoming => return Some(candidate),
            Some(_) => {}
            None => return Some(candidate),
        }
    }

    None
}

pub(crate) fn debug_log_invitation_sent_candidates(label: &str, target_invitation_id: &[u8; 32]) {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        eprintln!("[InviteLookup] {} no capsule", label);
        return;
    };
    let local_pubkey = capsule.pubkey;

    eprintln!(
        "[InviteLookup] {} target={:02x?} local={:02x?}",
        label,
        &target_invitation_id[..4],
        &local_pubkey.as_bytes()[..4]
    );

    for event in capsule.ledger.events() {
        let event_kind = event.kind();
        if event_kind != EventKind::InvitationSent && event_kind != EventKind::InvitationReceived {
            continue;
        }

        let payload = event.payload();
        if !invitation_payload_has_known_shape(payload) {
            continue;
        }

        let mut current_invitation_id = [0u8; 32];
        current_invitation_id.copy_from_slice(&payload[..32]);

        let mut addressed_to = [0u8; 32];
        addressed_to.copy_from_slice(&payload[64..96]);
        let signer = *event.signer().as_bytes();
        let is_incoming = event_kind == EventKind::InvitationReceived
            || (addressed_to == local_pubkey.as_bytes().to_owned()
                && signer != local_pubkey.as_bytes().to_owned());

        eprintln!(
            "[InviteLookup] candidate id={:02x?} signer={:02x?} to={:02x?} incoming={} len={}",
            &current_invitation_id[..4],
            &signer[..4],
            &addressed_to[..4],
            is_incoming,
            payload.len()
        );
    }
}

fn append_starter_created_if_missing(
    engine: &FfiEngine,
    starter_id: StarterId,
    kind: StarterKind,
    network: Network,
    nonce: [u8; 32],
) -> Result<(), &'static str> {
    let prepared = engine
        .prepare_starter_created(starter_id, nonce, kind, network)
        .map_err(|_| "prepare failed")?;
    if starter_is_active_in_runtime(starter_id) {
        return Ok(());
    }

    append_prepared_event(prepared)
}

fn append_relationship_established_if_missing(
    engine: &FfiEngine,
    peer_pubkey: PubKey,
    own_starter_id: StarterId,
    peer_starter_id: StarterId,
    kind: StarterKind,
    invitation_id: [u8; 32],
    sender_pubkey: PubKey,
    sender_starter_type: StarterKind,
    sender_starter_id: StarterId,
    peer_root_pubkey: Option<PubKey>,
    sender_root_pubkey: Option<PubKey>,
) -> Result<(), &'static str> {
    let prepared = engine
        .prepare_relationship_established(
            peer_pubkey,
            own_starter_id,
            peer_starter_id,
            kind,
            invitation_id,
            sender_pubkey,
            sender_starter_type,
            sender_starter_id,
            peer_root_pubkey,
            sender_root_pubkey,
        )
        .map_err(|_| "prepare failed")?;
    let payload_bytes = prepared.event.payload().to_vec();

    if event_exists_in_runtime(EventKind::RelationshipEstablished, &payload_bytes) {
        return Ok(());
    }

    append_prepared_event(prepared)
}

pub(crate) fn project_relationship_from_invitation_accepted(
    engine: &FfiEngine,
    message_from: [u8; 32],
    payload: &InvitationAcceptedPayload,
) -> Result<(), &'static str> {
    let local_pubkey = {
        let runtime = RUNTIME.lock().unwrap();
        let capsule = runtime.capsule.as_ref().ok_or("no capsule")?;
        *capsule.pubkey.as_bytes()
    };
    if message_from == local_pubkey {
        return Err("ignore self InvitationAccepted delivery");
    }

    debug_log_invitation_sent_candidates("incoming_accept", &payload.invitation_id);
    let Some(record) =
        find_invitation_sent_in_runtime_with_direction(&payload.invitation_id, Some(false))
    else {
        return Err("matching outgoing invitation not found");
    };
    if record.is_incoming {
        return Err("matching outgoing invitation not found");
    }
    let local_root_pubkey = engine.public_key().map_err(|_| "prepare failed")?;

    append_relationship_established_if_missing(
        engine,
        PubKey::from(message_from),
        record.starter_id,
        payload.created_starter_id,
        record.starter_kind,
        payload.invitation_id,
        payload.from_pubkey,
        record.starter_kind,
        record.starter_id,
        payload.accepter_root_pubkey,
        Some(local_root_pubkey),
    )
}

pub(crate) fn project_effects_from_invitation_rejected(
    engine: &FfiEngine,
    payload: &InvitationRejectedPayload,
) -> Result<(), &'static str> {
    let Some(record) =
        find_invitation_sent_in_runtime_with_direction(&payload.invitation_id, Some(false))
    else {
        return Err("matching outgoing invitation not found");
    };
    if record.is_incoming {
        return Err("matching outgoing invitation not found");
    }

    match payload.reason {
        RejectReason::EmptySlot => {
            if !starter_is_active_in_runtime(record.starter_id) {
                return Ok(());
            }

            let prepared = engine
                .prepare_starter_burned(record.starter_id, payload.reason as u8)
                .map_err(|_| "prepare failed")?;

            append_prepared_event(prepared)
        }
        RejectReason::Other => Ok(()),
    }
}

pub(crate) struct LocalAcceptancePlan {
    pub(crate) invitation_id: [u8; 32],
    pub(crate) sender_pubkey: PubKey,
    pub(crate) sender_root_pubkey: Option<PubKey>,
    pub(crate) sender_starter_id: StarterId,
    pub(crate) sender_starter_type: StarterKind,
    pub(crate) relationship_starter_id: StarterId,
    pub(crate) relationship_kind: StarterKind,
    pub(crate) peer_starter_id: StarterId,
    pub(crate) created_starter: Option<(StarterId, StarterKind, [u8; 32])>,
}

pub(crate) fn resolve_local_acceptance_plan(
    seed: &Seed,
    invitation_id: [u8; 32],
) -> Result<LocalAcceptancePlan, &'static str> {
    let Some(record) = find_invitation_sent_in_runtime_with_direction(&invitation_id, Some(true))
    else {
        eprintln!(
            "[Accept] resolve plan failed: invitation {:02x?} not found as incoming",
            &invitation_id[..4]
        );
        return Err("matching incoming invitation not found");
    };
    if !record.is_incoming {
        return Err("matching incoming invitation not found");
    }
    let peer_starter_id = record.starter_id;
    let invited_kind = record.starter_kind;
    let sender_pubkey = record.peer_pubkey;
    let sender_root_pubkey = record.sender_root_pubkey;
    let inviter_anchor = sender_root_pubkey.unwrap_or(sender_pubkey);

    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref().ok_or("no capsule")?;
    let slots = hivra_core::slot::SlotLayout::from_ledger(&capsule.ledger);
    let plan = hivra_core::plan_accept_for_kind(&capsule.ledger, &slots, invited_kind);
    eprintln!(
        "[Accept] planning invitation={:02x?} invited_kind={:?} peer_starter={:02x?} slots={:?} plan={:?}",
        &invitation_id[..4],
        invited_kind,
        &peer_starter_id.as_bytes()[..4],
        slots.states(),
        plan
    );
    drop(runtime);

    match plan {
        hivra_core::AcceptPlan::UseExistingStarter {
            relationship_starter_id,
            created_starter,
        } => {
            let created_starter = created_starter.map(|planned| {
                let slot = planned.slot.as_u8();
                (
                    StarterId::from(derive_starter_id_lineage(
                        seed,
                        slot,
                        &invitation_id,
                        &inviter_anchor,
                    )),
                    planned.kind,
                    derive_starter_nonce_lineage(seed, slot, &invitation_id, &inviter_anchor),
                )
            });

            Ok(LocalAcceptancePlan {
                invitation_id,
                sender_pubkey,
                sender_root_pubkey,
                sender_starter_id: peer_starter_id,
                sender_starter_type: invited_kind,
                relationship_starter_id,
                relationship_kind: invited_kind,
                peer_starter_id,
                created_starter,
            })
        }
        hivra_core::AcceptPlan::CreateStarterInEmptySlot { slot, kind } => {
            let slot_u8 = slot.as_u8();
            let created_starter_id = StarterId::from(derive_starter_id_lineage(
                seed,
                slot_u8,
                &invitation_id,
                &inviter_anchor,
            ));
            Ok(LocalAcceptancePlan {
                invitation_id,
                sender_pubkey,
                sender_root_pubkey,
                sender_starter_id: peer_starter_id,
                sender_starter_type: invited_kind,
                relationship_starter_id: created_starter_id,
                relationship_kind: invited_kind,
                peer_starter_id,
                created_starter: Some((
                    created_starter_id,
                    kind,
                    derive_starter_nonce_lineage(seed, slot_u8, &invitation_id, &inviter_anchor),
                )),
            })
        }
        hivra_core::AcceptPlan::NoCapacity => Err("no capacity to accept invitation"),
    }
}

pub(crate) fn finalize_local_acceptance(
    engine: &FfiEngine,
    plan: &LocalAcceptancePlan,
    from_pubkey: [u8; 32],
) -> Result<(), &'static str> {
    let network = capsule_network()?;
    eprintln!(
        "[Accept] finalize from={:02x?} relationship_starter={:02x?} peer_starter={:02x?} kind={:?} created={}",
        &from_pubkey[..4],
        &plan.relationship_starter_id.as_bytes()[..4],
        &plan.peer_starter_id.as_bytes()[..4],
        plan.relationship_kind,
        plan.created_starter.is_some()
    );

    if let Some((created_starter_id, created_kind, created_nonce)) = plan.created_starter {
        eprintln!(
            "[Accept] append StarterCreated starter={:02x?} kind={:?}",
            &created_starter_id.as_bytes()[..4],
            created_kind
        );
        append_starter_created_if_missing(
            engine,
            created_starter_id,
            created_kind,
            network,
            created_nonce,
        )?;
        eprintln!("[Accept] StarterCreated append ok");
    }

    eprintln!("[Accept] append RelationshipEstablished");
    append_relationship_established_if_missing(
        engine,
        PubKey::from(from_pubkey),
        plan.relationship_starter_id,
        plan.peer_starter_id,
        plan.relationship_kind,
        plan.invitation_id,
        plan.sender_pubkey,
        plan.sender_starter_type,
        plan.sender_starter_id,
        plan.sender_root_pubkey,
        Some(engine.public_key().map_err(|_| "prepare failed")?),
    )?;
    eprintln!("[Accept] RelationshipEstablished append ok");
    Ok(())
}
