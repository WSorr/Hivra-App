use super::*;

fn map_delivery_error(err: TransportError, default_code: i32) -> i32 {
    match err {
        TransportError::ConnectionFailed => -11,
        TransportError::Timeout => -12,
        TransportError::Other(reason) => {
            let lower = reason.to_lowercase();
            if lower.contains("auth") {
                -14
            } else if lower.contains("timeout") || lower.contains("timed out") {
                -12
            } else {
                -13
            }
        }
        _ => default_code,
    }
}

fn load_invitation_delivery_context(seed: &Seed) -> Result<([u8; 32], [u8; 32]), i32> {
    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return Err(-3),
    };

    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return Err(-3),
    };

    Ok((sender_secret, sender_pubkey))
}

fn send_delivery_message(
    transport: &NostrTransport,
    message: Message,
    failure_code: i32,
    debug_label: &str,
) -> Result<(), i32> {
    if let Err(err) = transport.send(message) {
        eprintln!("[Delivery/Nostr] {} failed: {:?}", debug_label, err);
        return Err(map_delivery_error(err, failure_code));
    }

    eprintln!("[Delivery/Nostr] {} delivered", debug_label);
    Ok(())
}

/// Deliver an invitation and append `InvitationSent` to the local ledger.
///
/// Exported symbol remains stable for existing bindings.
#[no_mangle]
pub unsafe extern "C" fn hivra_send_invitation(to_pubkey_ptr: *const u8, starter_slot: u8) -> i32 {
    clear_last_error();
    if to_pubkey_ptr.is_null() || starter_slot >= 5 {
        set_last_error("Send invitation failed: invalid arguments");
        return -1;
    }

    let to_slice = std::slice::from_raw_parts(to_pubkey_ptr, 32);
    let mut to_pubkey = [0u8; 32];
    to_pubkey.copy_from_slice(to_slice);

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Send invitation failed: seed not found");
            return -2;
        }
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            set_last_error("Send invitation failed: capsule runtime is not initialized");
            return -4;
        }
    }

    let (sender_secret, sender_pubkey) = match load_invitation_delivery_context(&seed) {
        Ok(context) => context,
        Err(code) => {
            set_last_error(format!(
                "Send invitation failed: delivery context initialization failed (code {code})"
            ));
            return code;
        }
    };
    let engine = build_engine(&seed);
    let starter_id = match active_starter_id_for_slot(starter_slot) {
        Some(id) => id,
        None => {
            set_last_error("Send invitation failed: selected starter slot is empty");
            return -6;
        }
    };
    let starter_kind = match find_starter_kind_by_id_in_runtime(starter_id.as_bytes()) {
        Some(kind) => kind,
        None => {
            set_last_error("Send invitation failed: starter kind resolution failed");
            return -6;
        }
    };
    let prepared = match engine.prepare_invitation_sent(starter_id, PubKey::from(to_pubkey)) {
        Ok(prepared) => prepared,
        Err(_) => {
            set_last_error("Send invitation failed: prepare_invitation_sent failed");
            return -6;
        }
    };
    let payload = match InvitationSentPayload::from_bytes(prepared.event.payload()) {
        Ok(payload) => payload,
        Err(_) => {
            set_last_error("Send invitation failed: InvitationSent payload encoding failed");
            return -6;
        }
    };
    let invitation_id = payload.invitation_id;
    let mut payload_bytes = prepared.event.payload().to_vec();
    if payload_bytes.len() == 96 {
        if let Ok(sender_root_pubkey) = derive_root_public_key(&seed) {
            payload_bytes.extend_from_slice(&sender_root_pubkey);
        }
    }
    // Include starter kind byte so receiver can render correct kind for incoming invitation.
    payload_bytes.push(starter_kind.to_byte());

    let message = Message {
        from: sender_pubkey,
        to: to_pubkey,
        kind: EventKind::InvitationSent as u32,
        payload: payload_bytes.clone(),
        timestamp: prepared.event.timestamp().as_u64(),
        invitation_id: Some(invitation_id),
    };

    match append_prepared_event(PreparedEvent {
        event: Event::new(
            EventKind::InvitationSent,
            payload_bytes.clone(),
            prepared.event.timestamp(),
            *prepared.event.signature(),
            *prepared.event.signer(),
        ),
        recipient: prepared.recipient,
    }) {
        Ok(_) => {}
        Err(_) => {
            set_last_error("Send invitation failed: append InvitationSent to local ledger failed");
            return -6;
        }
    };

    if let Err(code) =
        with_cached_nostr_transport(sender_secret, TransportProfile::Default, -5, |transport| {
            send_delivery_message(transport, message, -7, "InvitationSent")
        })
    {
        set_last_error(format!(
            "Send invitation failed: delivery transport rejected message (code {code})"
        ));
        return code;
    }

    0
}

/// Receive invitation deliveries from transport and append supported events to local ledger.
///
/// Returns:
/// - >=0 number of newly appended events
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_transport_receive() -> i32 {
    hivra_transport_receive_with_profile(TransportProfile::Default)
}

#[no_mangle]
pub unsafe extern "C" fn hivra_transport_receive_quick() -> i32 {
    hivra_transport_receive_with_profile(TransportProfile::Quick)
}

fn hivra_transport_receive_with_profile(profile: TransportProfile) -> i32 {
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

    let received = match with_cached_nostr_transport(sender_secret, profile, -4, |transport| {
        transport.receive().map_err(|_| -5)
    }) {
        Ok(messages) => messages,
        Err(code) => return code,
    };

    let mut appended: i32 = 0;
    for message in received {
        eprintln!(
            "[Delivery/Nostr] Received message kind={} payload_len={} to_prefix={:02x?}",
            message.kind,
            message.payload.len(),
            &message.to[..4]
        );

        if message.from == local_pubkey {
            eprintln!(
                "[Delivery/Nostr] Skip loopback message kind={} from local pubkey",
                message.kind
            );
            continue;
        }

        let to_matches = message.to == local_pubkey;

        let kind_u8 = match u8::try_from(message.kind) {
            Ok(value) => value,
            Err(_) => {
                eprintln!(
                    "[Delivery/Nostr] Skip message: unsupported kind value {}",
                    message.kind
                );
                continue;
            }
        };

        let kind = match event_kind_from_u8(kind_u8) {
            Some(value) => value,
            None => {
                eprintln!("[Delivery/Nostr] Skip message: unmapped kind {}", kind_u8);
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
            eprintln!("[Delivery/Nostr] Skip message: not addressed to local capsule");
            continue;
        }

        let local_payload = message.payload.clone();
        let local_kind = if kind == EventKind::InvitationSent {
            EventKind::InvitationReceived
        } else {
            kind
        };

        let message_signer = PubKey::from(message.from);
        if should_skip_incoming_delivery_append(local_kind, &local_payload, message_signer) {
            eprintln!("[Delivery/Nostr] Skip message: event already exists");
            continue;
        }

        match append_runtime_event_with_signer(local_kind, &local_payload, message_signer) {
            Ok(_) => {
                appended += 1;
            }
            Err(err) => {
                eprintln!("[Delivery/Nostr] Skip message: append failed ({})", err);
                continue;
            }
        }

        if kind == EventKind::InvitationAccepted
            && (message.payload.len() == 96 || message.payload.len() == 128)
        {
            let Ok(payload) = InvitationAcceptedPayload::from_bytes(&message.payload) else {
                continue;
            };

            let engine = build_engine(&seed);
            if let Err(err) =
                project_relationship_from_invitation_accepted(&engine, message.from, &payload)
            {
                eprintln!(
                    "[Delivery/Nostr] Failed to project RelationshipEstablished from InvitationAccepted ({})",
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
                    "[Delivery/Nostr] Failed to project local effects from InvitationRejected ({})",
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
    clear_last_error();
    if invitation_id_ptr.is_null() || from_pubkey_ptr.is_null() {
        set_last_error("Accept invitation failed: invalid arguments");
        return -1;
    }

    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let mut from_pubkey = [0u8; 32];
    from_pubkey.copy_from_slice(std::slice::from_raw_parts(from_pubkey_ptr, 32));

    if invitation_is_resolved_in_runtime(&invitation_id) {
        eprintln!(
            "[Accept] skip resolved invitation={:02x?}",
            &invitation_id[..4]
        );
        return 0;
    }

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Accept invitation failed: seed not found");
            return -2;
        }
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            set_last_error("Accept invitation failed: capsule runtime is not initialized");
            return -5;
        }
    }

    let (sender_secret, sender_pubkey) = match load_invitation_delivery_context(&seed) {
        Ok(context) => context,
        Err(-3) => {
            set_last_error("Accept invitation failed: sender key derivation failed");
            return -4;
        }
        Err(_) => {
            set_last_error("Accept invitation failed: delivery context initialization failed");
            return -6;
        }
    };
    if from_pubkey == sender_pubkey {
        eprintln!(
            "[Accept] abort invitation={:02x?}: self-target from={:02x?}",
            &invitation_id[..4],
            &from_pubkey[..4]
        );
        set_last_error("Accept invitation failed: self invitation target is not allowed");
        return -11;
    }

    let engine = build_engine(&seed);
    let acceptance_plan = match resolve_local_acceptance_plan(&seed, invitation_id) {
        Ok(plan) => plan,
        Err("matching incoming invitation not found") => {
            eprintln!(
                "[Accept] abort invitation={:02x?}: matching incoming invitation not found",
                &invitation_id[..4]
            );
            set_last_error("Accept invitation failed: matching incoming invitation not found");
            return -8;
        }
        Err("no capacity to accept invitation") => {
            eprintln!(
                "[Accept] abort invitation={:02x?}: no capacity",
                &invitation_id[..4]
            );
            set_last_error("Accept invitation failed: no capacity to accept invitation");
            return -9;
        }
        Err(err) => {
            eprintln!(
                "[Accept] abort invitation={:02x?}: {}",
                &invitation_id[..4],
                err
            );
            set_last_error(format!(
                "Accept invitation failed: finalize plan error ({err})"
            ));
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
            set_last_error("Accept invitation failed: append InvitationAccepted");
            return -3;
        }
    };
    let payload_bytes = prepared.event.payload().to_vec();

    if event_exists_in_runtime(EventKind::InvitationAccepted, &payload_bytes) {
        eprintln!(
            "[Accept] skip duplicate local InvitationAccepted invitation={:02x?}",
            &invitation_id[..4]
        );
        return 0;
    }

    let message = Message {
        from: sender_pubkey,
        to: from_pubkey,
        kind: EventKind::InvitationAccepted as u32,
        payload: payload_bytes.clone(),
        timestamp: prepared.event.timestamp().as_u64(),
        invitation_id: Some(invitation_id),
    };

    eprintln!(
        "[Delivery/Nostr] Sending InvitationAccepted to_prefix={:02x?} invitation_prefix={:02x?}",
        &from_pubkey[..4],
        &invitation_id[..4]
    );

    if let Err(code) =
        with_cached_nostr_transport(sender_secret, TransportProfile::Default, -6, |transport| {
            send_delivery_message(transport, message, -7, "InvitationAccepted")
        })
    {
        eprintln!(
            "[Accept] delivery send failed invitation={:02x?}: code {}",
            &invitation_id[..4],
            code
        );
        set_last_error(format!(
            "Accept invitation failed: delivery transport rejected message (code {code})"
        ));
        return code;
    }

    if append_prepared_event(prepared).is_err() {
        eprintln!(
            "[Accept] local InvitationAccepted append failed invitation={:02x?}",
            &invitation_id[..4]
        );
        set_last_error("Accept invitation failed: append InvitationAccepted");
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
            set_last_error(format!(
                "Accept invitation failed: finalize local acceptance failed ({err})"
            ));
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

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            return -4;
        }
    }

    let engine = build_engine(&seed);
    let peer_pubkey = match find_invitation_sent_in_runtime(&invitation_id) {
        Some(record) => record.peer_pubkey,
        None => return -4,
    };
    let prepared =
        match engine.prepare_invitation_rejected(invitation_id, peer_pubkey, reject_reason) {
            Ok(prepared) => prepared,
            Err(_) => return -4,
        };

    let payload_bytes = prepared.event.payload().to_vec();

    if event_exists_in_runtime(EventKind::InvitationRejected, &payload_bytes) {
        return 0;
    }

    let delivery_payload = payload_bytes.clone();
    let delivery_timestamp = prepared.event.timestamp().as_u64();
    let delivery_to = *peer_pubkey.as_bytes();

    match append_prepared_event(prepared) {
        Ok(_) => {
            // Local truth is ledger-first: once rejected is appended, UI projection
            // must not return invitation to actionable pending queues. Transport
            // delivery stays best-effort and must not roll back local reject.
            match load_invitation_delivery_context(&seed) {
                Ok((sender_secret, sender_pubkey)) => {
                    let message = Message {
                        from: sender_pubkey,
                        to: delivery_to,
                        kind: EventKind::InvitationRejected as u32,
                        payload: delivery_payload,
                        timestamp: delivery_timestamp,
                        invitation_id: Some(invitation_id),
                    };
                    if let Err(code) = with_cached_nostr_transport(
                        sender_secret,
                        TransportProfile::Default,
                        -5,
                        |transport| {
                            send_delivery_message(transport, message, -6, "InvitationRejected")
                        },
                    ) {
                        eprintln!(
                            "[Delivery/Nostr] InvitationRejected local append ok; delivery failed ({})",
                            code
                        );
                    }
                }
                Err(code) => {
                    eprintln!(
                        "[Delivery/Nostr] InvitationRejected local append ok; delivery context unavailable ({})",
                        code
                    );
                }
            }
            0
        }
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

    // Do not append a weaker terminal fact after the invitation is already
    // accepted, rejected, or expired in local runtime state.
    if invitation_is_resolved_in_runtime(&invitation_id) {
        return 0;
    }

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
