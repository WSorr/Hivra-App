use super::*;

/// Send invitation through transport and append InvitationSent to local ledger.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_send_invitation(to_pubkey_ptr: *const u8, starter_slot: u8) -> i32 {
    if to_pubkey_ptr.is_null() || starter_slot >= 5 {
        return -1;
    }

    let to_slice = std::slice::from_raw_parts(to_pubkey_ptr, 32);
    let mut to_pubkey = [0u8; 32];
    to_pubkey.copy_from_slice(to_slice);

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };

    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -3,
    };

    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -3,
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            return -4;
        }
    }

    let transport = match NostrTransport::new(NostrConfig::default(), &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return -5,
    };

    let engine = build_engine(&seed);
    let starter_id = StarterId::from(derive_starter_id(&seed, starter_slot));
    let prepared = match engine.prepare_invitation_sent(starter_id, PubKey::from(to_pubkey)) {
        Ok(prepared) => prepared,
        Err(_) => return -6,
    };
    let payload = match InvitationSentPayload::from_bytes(prepared.event.payload()) {
        Ok(payload) => payload,
        Err(_) => return -6,
    };
    let invitation_id = payload.invitation_id;
    let mut payload_bytes = prepared.event.payload().to_vec();
    // Include starter kind byte so receiver can render correct kind for incoming invitation.
    payload_bytes.push(starter_slot);

    let message = Message {
        from: sender_pubkey,
        to: to_pubkey,
        kind: EventKind::InvitationSent as u32,
        payload: payload_bytes.clone(),
        timestamp: prepared.event.timestamp().as_u64(),
        invitation_id: Some(invitation_id),
    };

    if transport.send(message).is_err() {
        eprintln!("[Nostr] InvitationSent publish failed");
        return -7;
    }

    eprintln!("[Nostr] InvitationSent published");

    append_prepared_event(PreparedEvent {
        event: Event::new(
            EventKind::InvitationSent,
            payload_bytes,
            prepared.event.timestamp(),
            *prepared.event.signature(),
            *prepared.event.signer(),
        ),
        recipient: prepared.recipient,
    })
    .map(|_| 0)
    .unwrap_or(-6)
}

/// Receive transport messages from relays and append supported events to local ledger.
///
/// Returns:
/// - >=0 number of newly appended events
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_transport_receive() -> i32 {
    hivra_transport_receive_with_config(NostrConfig::default())
}

#[no_mangle]
pub unsafe extern "C" fn hivra_transport_receive_quick() -> i32 {
    hivra_transport_receive_with_config(NostrConfig::quick_launch())
}

fn hivra_transport_receive_with_config(config: NostrConfig) -> i32 {
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -1,
    };

    let local_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };

    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            return -3;
        }
    }

    let transport = match NostrTransport::new(config, &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return -4,
    };

    let received = match transport.receive() {
        Ok(messages) => messages,
        Err(_) => return -5,
    };

    let mut appended: i32 = 0;
    for message in received {
        eprintln!(
            "[Nostr] Received message kind={} payload_len={} to_prefix={:02x?}",
            message.kind,
            message.payload.len(),
            &message.to[..4]
        );

        let to_matches = message.to == local_pubkey;

        let kind_u8 = match u8::try_from(message.kind) {
            Ok(value) => value,
            Err(_) => {
                eprintln!(
                    "[Nostr] Skip message: unsupported kind value {}",
                    message.kind
                );
                continue;
            }
        };

        let kind = match event_kind_from_u8(kind_u8) {
            Some(value) => value,
            None => {
                eprintln!("[Nostr] Skip message: unmapped kind {}", kind_u8);
                continue;
            }
        };

        // Fallback routing check by payload for InvitationSent in case `message.to` encoding differs.
        let payload_targets_local =
            if kind == EventKind::InvitationSent && message.payload.len() >= 96 {
                let mut to_from_payload = [0u8; 32];
                to_from_payload.copy_from_slice(&message.payload[64..96]);
                to_from_payload == local_pubkey
            } else {
                false
            };

        if !to_matches && !payload_targets_local {
            eprintln!("[Nostr] Skip message: not addressed to local capsule");
            continue;
        }

        let local_payload = message.payload.clone();
        let local_kind = if kind == EventKind::InvitationSent {
            EventKind::InvitationReceived
        } else {
            kind
        };

        let message_signer = PubKey::from(message.from);
        if local_kind == EventKind::InvitationReceived && local_payload.len() >= 32 {
            let mut invitation_id = [0u8; 32];
            invitation_id.copy_from_slice(&local_payload[..32]);
            if invitation_is_resolved_in_runtime(&invitation_id) {
                eprintln!("[Nostr] Skip message: invitation already resolved");
                continue;
            }
            if invitation_offer_exists_in_runtime(local_kind, &invitation_id, message_signer) {
                eprintln!("[Nostr] Skip message: invitation offer already exists");
                continue;
            }
        }

        let already_exists =
            event_exists_in_runtime_with_signer(local_kind, &local_payload, message_signer);
        if already_exists {
            eprintln!("[Nostr] Skip message: event already exists");
            continue;
        }

        match append_runtime_event_with_signer(local_kind, &local_payload, message_signer) {
            Ok(_) => {
                appended += 1;
            }
            Err(err) => {
                eprintln!("[Nostr] Skip message: append failed ({})", err);
                continue;
            }
        }

        if kind == EventKind::InvitationAccepted && message.payload.len() == 96 {
            let Ok(payload) = InvitationAcceptedPayload::from_bytes(&message.payload) else {
                continue;
            };

            let engine = build_engine(&seed);
            if let Err(err) =
                project_relationship_from_invitation_accepted(&engine, message.from, &payload)
            {
                eprintln!(
                    "[Nostr] Failed to project RelationshipEstablished from InvitationAccepted ({})",
                    err
                );
            }
        } else if kind == EventKind::InvitationRejected && message.payload.len() == 33 {
            let Ok(payload) = InvitationRejectedPayload::from_bytes(&message.payload) else {
                continue;
            };

            let engine = build_engine(&seed);
            if let Err(err) = project_effects_from_invitation_rejected(&engine, &payload) {
                eprintln!(
                    "[Nostr] Failed to project local effects from InvitationRejected ({})",
                    err
                );
            }
        }
    }

    appended
}

/// Send and append InvitationAccepted through transport + local ledger.
#[no_mangle]
pub unsafe extern "C" fn hivra_accept_invitation(
    invitation_id_ptr: *const u8,
    from_pubkey_ptr: *const u8,
    _created_starter_id_ptr: *const u8,
) -> i32 {
    if invitation_id_ptr.is_null() || from_pubkey_ptr.is_null() {
        return -1;
    }

    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let mut from_pubkey = [0u8; 32];
    from_pubkey.copy_from_slice(std::slice::from_raw_parts(from_pubkey_ptr, 32));

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };

    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -4,
    };

    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -4,
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            return -5;
        }
    }

    let engine = build_engine(&seed);
    let acceptance_plan = match resolve_local_acceptance_plan(&seed, invitation_id) {
        Ok(plan) => plan,
        Err("matching incoming invitation not found") => {
            eprintln!(
                "[Accept] abort invitation={:02x?}: matching incoming invitation not found",
                &invitation_id[..4]
            );
            return -8;
        }
        Err("no capacity to accept invitation") => {
            eprintln!(
                "[Accept] abort invitation={:02x?}: no capacity",
                &invitation_id[..4]
            );
            return -9;
        }
        Err(err) => {
            eprintln!(
                "[Accept] abort invitation={:02x?}: {}",
                &invitation_id[..4],
                err
            );
            return -10;
        }
    };
    eprintln!(
        "[Accept] prepared local plan invitation={:02x?} relationship_starter={:02x?} created={}",
        &invitation_id[..4],
        &acceptance_plan.relationship_starter_id.as_bytes()[..4],
        acceptance_plan.created_starter.is_some()
    );
    let prepared = match engine.prepare_invitation_accepted(
        invitation_id,
        PubKey::from(from_pubkey),
        acceptance_plan.relationship_starter_id,
    ) {
        Ok(prepared) => prepared,
        Err(_) => {
            eprintln!(
                "[Accept] prepare_invitation_accepted failed invitation={:02x?}",
                &invitation_id[..4]
            );
            return -3;
        }
    };
    let payload_bytes = prepared.event.payload().to_vec();

    let message = Message {
        from: sender_pubkey,
        to: from_pubkey,
        kind: EventKind::InvitationAccepted as u32,
        payload: payload_bytes.clone(),
        timestamp: prepared.event.timestamp().as_u64(),
        invitation_id: Some(invitation_id),
    };

    eprintln!(
        "[Nostr] Sending InvitationAccepted to_prefix={:02x?} invitation_prefix={:02x?}",
        &from_pubkey[..4],
        &invitation_id[..4]
    );

    let transport = match NostrTransport::new(NostrConfig::default(), &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return -6,
    };

    if transport.send(message).is_err() {
        eprintln!(
            "[Accept] transport send failed invitation={:02x?}",
            &invitation_id[..4]
        );
        return -7;
    }

    if append_prepared_event(prepared).is_err() {
        eprintln!(
            "[Accept] local InvitationAccepted append failed invitation={:02x?}",
            &invitation_id[..4]
        );
        return -3;
    }
    eprintln!(
        "[Accept] local InvitationAccepted append ok invitation={:02x?}",
        &invitation_id[..4]
    );

    finalize_local_acceptance(&engine, &acceptance_plan, from_pubkey)
        .map(|_| {
            eprintln!(
                "[Accept] finalize ok invitation={:02x?}",
                &invitation_id[..4]
            );
            0
        })
        .unwrap_or_else(|err| {
            eprintln!(
                "[Accept] finalize failed invitation={:02x?}: {}",
                &invitation_id[..4],
                err
            );
            -10
        })
}

/// Append InvitationRejected through Engine orchestration.
#[no_mangle]
pub unsafe extern "C" fn hivra_reject_invitation(invitation_id_ptr: *const u8, reason: u8) -> i32 {
    if invitation_id_ptr.is_null() {
        return -1;
    }

    let reject_reason = match reason {
        0 => RejectReason::EmptySlot,
        1 => RejectReason::Other,
        _ => return -2,
    };

    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -3,
    };
    let engine = build_engine(&seed);
    let peer_pubkey = match find_invitation_sent_in_runtime(&invitation_id) {
        Some((_, _, peer_pubkey, _)) => peer_pubkey,
        None => return -4,
    };
    let prepared =
        match engine.prepare_invitation_rejected(invitation_id, peer_pubkey, reject_reason) {
            Ok(prepared) => prepared,
            Err(_) => return -4,
        };

    match append_prepared_event(prepared) {
        Ok(_) => 0,
        Err(_) => -4,
    }
}

/// Append InvitationExpired through Engine orchestration.
#[no_mangle]
pub unsafe extern "C" fn hivra_expire_invitation(invitation_id_ptr: *const u8) -> i32 {
    if invitation_id_ptr.is_null() {
        return -1;
    }

    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };
    let engine = build_engine(&seed);
    let prepared = match engine.prepare_invitation_expired(invitation_id) {
        Ok(prepared) => prepared,
        Err(_) => return -3,
    };
    match append_prepared_event(prepared) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}
