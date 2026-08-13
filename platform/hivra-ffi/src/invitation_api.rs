use super::*;
use crate::invitation_support::incoming_invitation_expired_matches_runtime;
use hivra_core::event_payloads::RelationshipBrokenPayload;

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

fn describe_transport_error(err: &TransportError) -> Option<String> {
    match err {
        TransportError::Other(reason) => {
            let trimmed = reason.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        TransportError::Timeout => Some("transport timeout".to_string()),
        TransportError::ConnectionFailed => Some("connection failed".to_string()),
        TransportError::SendFailed => Some("send failed".to_string()),
        TransportError::ReceiveFailed => Some("receive failed".to_string()),
        TransportError::InvalidMessage => Some("invalid message".to_string()),
        TransportError::EncodingFailed => Some("encoding failed".to_string()),
        TransportError::DecodingFailed => Some("decoding failed".to_string()),
        TransportError::InvalidKey => Some("invalid key".to_string()),
        TransportError::SenderMismatch => {
            Some("decrypted sender does not match signed transport event".to_string())
        }
        TransportError::NotImplemented => Some("transport not implemented".to_string()),
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
    message: &DeliveryEnvelope,
    publish_timeout_secs: u64,
    failure_code: i32,
    debug_label: &str,
) -> Result<DeliveryReceipt, (i32, Option<String>)> {
    let receipt =
        match transport.send_with_receipt_with_timeout(message.clone(), publish_timeout_secs) {
            Ok(receipt) => receipt,
            Err(err) => {
                let reason = describe_transport_error(&err);
                eprintln!(
                    "[Delivery/Nostr] {} failed: {:?}{}",
                    debug_label,
                    err,
                    reason
                        .as_deref()
                        .map(|value| format!(" | reason={value}"))
                        .unwrap_or_default()
                );
                return Err((map_delivery_error(err, failure_code), reason));
            }
        };

    eprintln!(
        "[Delivery/Nostr] {} accepted envelope={} by={}",
        debug_label, receipt.envelope_id, receipt.accepted_by
    );
    record_delivery_receipt_with_correlation(debug_label, receipt.clone(), message.correlation_id);
    Ok(receipt)
}

fn verified_event_from_message(
    message: &DeliveryEnvelope,
    expected_kind: EventKind,
) -> Result<Event, &'static str> {
    let proof = message
        .domain_event
        .as_ref()
        .ok_or("missing domain event proof")?;
    if proof.kind != expected_kind as u8 {
        return Err("domain event kind mismatch");
    }
    let signature_bytes: [u8; 64] = proof
        .signature
        .as_slice()
        .try_into()
        .map_err(|_| "invalid domain event signature length")?;

    let timestamp = Timestamp::from(message.timestamp);
    let signer = PubKey::from(proof.signer);
    match proof.version {
        hivra_core::PROTOCOL_VERSION => Ok(Event::new(
            expected_kind,
            message.payload.clone(),
            timestamp,
            Signature::from(signature_bytes),
            signer,
        )),
        hivra_core::CONTINUOUS_LEDGER_PROTOCOL_VERSION => Ok(Event::new_v5(
            expected_kind,
            message.payload.clone(),
            timestamp,
            Signature::from(signature_bytes),
            signer,
        )),
        _ => Err("unsupported domain event version"),
    }
}

fn proof_signer_matches_payload(kind: EventKind, payload: &[u8], signer: PubKey) -> bool {
    match kind {
        EventKind::InvitationReceived if payload.len() >= 128 => {
            payload[96..128] == signer.as_bytes()[..]
        }
        EventKind::InvitationAccepted if payload.len() == 128 => {
            payload[96..128] == signer.as_bytes()[..]
        }
        EventKind::RelationshipBroken if payload.len() == 96 => {
            payload[64..96] == signer.as_bytes()[..]
        }
        EventKind::InvitationRejected => true,
        EventKind::InvitationExpired => true,
        _ => false,
    }
}

fn project_invitation_accepted_delivery(
    seed: &Seed,
    message_from: [u8; 32],
    payload: &[u8],
) -> Result<(), &'static str> {
    let payload = InvitationAcceptedPayload::from_bytes(payload)
        .map_err(|_| "invalid InvitationAccepted payload")?;
    let engine = build_engine(seed);
    project_relationship_from_invitation_accepted(&engine, message_from, &payload)
}

fn retry_outgoing_relationship_break_by_event_id_over_transport(
    transport: &NostrTransport,
    engine: &FfiEngine,
    sender_pubkey: [u8; 32],
    event_id: [u8; 32],
    publish_timeout_secs: u64,
) -> Result<i32, i32> {
    let Some(pending_delivery) =
        crate::invitation_support::pending_outgoing_relationship_break_deliveries_in_runtime(
            PubKey::from(sender_pubkey),
        )
        .into_iter()
        .find(|delivery| delivery.event_id == event_id)
    else {
        // The exact ledger fact was superseded or already acknowledged. This
        // is a successful no-op, not a reason to scan and publish other facts.
        return Ok(0);
    };

    let payload = RelationshipBrokenPayload {
        peer_pubkey: PubKey::from(sender_pubkey),
        own_starter_id: pending_delivery.peer_starter_id,
        peer_root_pubkey: Some(pending_delivery.local_root_pubkey),
    }
    .to_bytes();
    let remote_prepared = engine
        .prepare_domain_event(
            EventKind::RelationshipBroken,
            payload.clone(),
            Some(PubKey::from(pending_delivery.to_pubkey)),
        )
        .map_err(|_| -7)?;
    let message = DeliveryEnvelope {
        schema_version: 1,
        from: sender_pubkey,
        to: pending_delivery.to_pubkey,
        kind: EventKind::RelationshipBroken as u32,
        payload,
        timestamp: remote_prepared.event.timestamp().as_u64(),
        correlation_id: Some(event_id),
        domain_event: Some(domain_event_proof(&remote_prepared.event)),
    };
    send_delivery_message(
        transport,
        &message,
        publish_timeout_secs,
        -7,
        "RelationshipBrokenRetry",
    )
    .map_err(|(code, _reason)| code)?;
    Ok(1)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum InvitationDeliveryMode {
    Offer,
    Terminal,
}

fn retry_pending_outgoing_invitations_over_transport(
    transport: &NostrTransport,
    engine: &FfiEngine,
    sender_pubkey: [u8; 32],
    only_invitation_id: Option<[u8; 32]>,
    mode: InvitationDeliveryMode,
    publish_timeout_secs: u64,
) -> Result<i32, i32> {
    let pending = if mode == InvitationDeliveryMode::Terminal {
        Vec::new()
    } else {
        crate::invitation_support::pending_outgoing_invitation_deliveries_in_runtime()
            .into_iter()
            .filter(|delivery| {
                only_invitation_id
                    .map(|id| delivery.invitation_id == id)
                    .unwrap_or(true)
            })
            .collect::<Vec<_>>()
    };
    let pending_terminals = if mode == InvitationDeliveryMode::Offer {
        Vec::new()
    } else {
        crate::invitation_support::pending_outgoing_invitation_terminal_deliveries_in_runtime()
            .into_iter()
            .filter(|delivery| {
                only_invitation_id
                    .map(|id| delivery.invitation_id == id)
                    .unwrap_or(true)
            })
            .collect::<Vec<_>>()
    };
    if pending.is_empty() && pending_terminals.is_empty() {
        return Ok(0);
    }

    let mut delivered_count: i32 = 0;
    let mut first_delivery_error: Option<(i32, Option<String>)> = None;
    for pending_delivery in pending {
        let remote_prepared = match engine.prepare_domain_event(
            EventKind::InvitationReceived,
            pending_delivery.payload.clone(),
            Some(PubKey::from(pending_delivery.to_pubkey)),
        ) {
            Ok(prepared) => prepared,
            Err(_) => {
                first_delivery_error.get_or_insert((-7, Some("event signing failed".to_string())));
                continue;
            }
        };
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: sender_pubkey,
            to: pending_delivery.to_pubkey,
            kind: EventKind::InvitationSent as u32,
            payload: pending_delivery.payload,
            timestamp: remote_prepared.event.timestamp().as_u64(),
            correlation_id: Some(pending_delivery.invitation_id),
            domain_event: Some(domain_event_proof(&remote_prepared.event)),
        };

        match send_delivery_message(
            transport,
            &message,
            publish_timeout_secs,
            -7,
            "InvitationSentRetry",
        ) {
            Ok(_) => {
                delivered_count += 1;
            }
            Err(delivery_error) => {
                if first_delivery_error.is_none() {
                    first_delivery_error = Some(delivery_error);
                }
            }
        }
    }
    for pending_delivery in pending_terminals {
        let remote_prepared = match engine.prepare_domain_event(
            pending_delivery.kind,
            pending_delivery.payload.clone(),
            Some(PubKey::from(pending_delivery.to_pubkey)),
        ) {
            Ok(prepared) => prepared,
            Err(_) => {
                first_delivery_error.get_or_insert((-7, Some("event signing failed".to_string())));
                continue;
            }
        };
        let retry_label = match pending_delivery.kind {
            EventKind::InvitationAccepted => "InvitationAcceptedRetry",
            EventKind::InvitationRejected => "InvitationRejectedRetry",
            EventKind::InvitationExpired => "InvitationExpiredRetry",
            _ => "InvitationTerminalRetry",
        };
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: sender_pubkey,
            to: pending_delivery.to_pubkey,
            kind: pending_delivery.kind as u32,
            payload: pending_delivery.payload,
            timestamp: remote_prepared.event.timestamp().as_u64(),
            correlation_id: Some(pending_delivery.invitation_id),
            domain_event: Some(domain_event_proof(&remote_prepared.event)),
        };

        match send_delivery_message(transport, &message, publish_timeout_secs, -7, retry_label) {
            Ok(_) => {
                delivered_count += 1;
            }
            Err(delivery_error) => {
                if first_delivery_error.is_none() {
                    first_delivery_error = Some(delivery_error);
                }
            }
        }
    }

    if delivered_count > 0 {
        eprintln!(
            "[Delivery/Nostr] InvitationRetry delivered count={}",
            delivered_count
        );
        return Ok(delivered_count);
    }

    if let Some((code, _reason)) = first_delivery_error {
        return Err(code);
    }

    Ok(0)
}

/// Retry one immutable relationship-break fact. The caller must supply the
/// signed local ledger event ID returned when the break was appended.
#[no_mangle]
pub unsafe extern "C" fn hivra_retry_outgoing_relationship_break_by_event_id(
    event_id_ptr: *const u8,
) -> i32 {
    clear_last_error();
    clear_delivery_receipts();
    if event_id_ptr.is_null() {
        return -1;
    }
    let mut event_id = [0u8; 32];
    event_id.copy_from_slice(std::slice::from_raw_parts(event_id_ptr, 32));
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };
    let (sender_secret, sender_pubkey) = match load_invitation_delivery_context(&seed) {
        Ok(context) => context,
        Err(code) => return code,
    };
    let engine = build_engine(&seed);
    let profile = TransportProfile::Quick;
    match with_cached_nostr_transport(sender_secret, profile, -5, |transport| {
        retry_outgoing_relationship_break_by_event_id_over_transport(
            transport,
            &engine,
            sender_pubkey,
            event_id,
            profile.publish_timeout_secs(),
        )
    }) {
        Ok(delivered) => delivered,
        Err(code) => {
            set_last_error(format!("Retry relationship break failed (code {code})"));
            code
        }
    }
}

/// Retry one exact invitation effect. The host outbox owns scheduling; this
/// function only derives and publishes the referenced domain effect.
unsafe fn retry_outgoing_invitation_by_id(
    invitation_id_ptr: *const u8,
    mode: InvitationDeliveryMode,
) -> i32 {
    clear_last_error();
    clear_delivery_receipts();
    if invitation_id_ptr.is_null() {
        return -1;
    }
    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Retry invitation failed: seed not found");
            return -2;
        }
    };
    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            set_last_error("Retry invitation failed: capsule runtime is not initialized");
            return -4;
        }
    }
    let (sender_secret, sender_pubkey) = match load_invitation_delivery_context(&seed) {
        Ok(context) => context,
        Err(code) => return code,
    };
    let engine = build_engine(&seed);
    let profile = TransportProfile::Quick;
    match with_cached_nostr_transport(sender_secret, profile, -5, |transport| {
        retry_pending_outgoing_invitations_over_transport(
            transport,
            &engine,
            sender_pubkey,
            Some(invitation_id),
            mode,
            profile.publish_timeout_secs(),
        )
    }) {
        Ok(delivered) => delivered,
        Err(code) => {
            set_last_error(format!(
                "Retry invitation failed: delivery transport rejected message (code {code})"
            ));
            code
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn hivra_retry_outgoing_invitation_offer_by_id(
    invitation_id_ptr: *const u8,
) -> i32 {
    retry_outgoing_invitation_by_id(invitation_id_ptr, InvitationDeliveryMode::Offer)
}

#[no_mangle]
pub unsafe extern "C" fn hivra_retry_outgoing_invitation_terminal_by_id(
    invitation_id_ptr: *const u8,
) -> i32 {
    retry_outgoing_invitation_by_id(invitation_id_ptr, InvitationDeliveryMode::Terminal)
}

/// Deliver an invitation and append `InvitationSent` to the local ledger.
///
/// Exported symbol remains stable for existing bindings.
#[no_mangle]
pub unsafe extern "C" fn hivra_send_invitation(to_pubkey_ptr: *const u8, starter_slot: u8) -> i32 {
    send_invitation_with_card_signature(to_pubkey_ptr, starter_slot, None)
}

/// Deliver an invitation with the sender's signed public contact-card proof.
/// The proof contains no private material and lets the receiver reconstruct
/// and validate the canonical v2 card after acceptance.
#[no_mangle]
pub unsafe extern "C" fn hivra_send_invitation_with_card(
    to_pubkey_ptr: *const u8,
    starter_slot: u8,
    card_signature_ptr: *const u8,
) -> i32 {
    if card_signature_ptr.is_null() {
        return send_invitation_with_card_signature(to_pubkey_ptr, starter_slot, None);
    }
    let mut signature = [0u8; 64];
    signature.copy_from_slice(std::slice::from_raw_parts(card_signature_ptr, 64));
    send_invitation_with_card_signature(to_pubkey_ptr, starter_slot, Some(signature))
}

unsafe fn send_invitation_with_card_signature(
    to_pubkey_ptr: *const u8,
    starter_slot: u8,
    card_signature: Option<[u8; 64]>,
) -> i32 {
    clear_last_error();
    clear_delivery_receipts();
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

    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => {
            set_last_error("Send invitation failed: transport key derivation failed");
            return -3;
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
    let invitation = match engine.prepare_invitation_sent(starter_id, PubKey::from(to_pubkey)) {
        Ok(prepared) => prepared,
        Err(_) => {
            set_last_error("Send invitation failed: prepare_invitation_sent failed");
            return -6;
        }
    };
    let mut payload_bytes = invitation.event.payload().to_vec();
    if payload_bytes.len() == 96 {
        if let Ok(sender_root_pubkey) = derive_root_public_key(&seed) {
            payload_bytes.extend_from_slice(&sender_root_pubkey);
        }
    }
    // Include starter kind byte so receiver can render correct kind for incoming invitation.
    payload_bytes.push(starter_kind.to_byte());
    // Core signer is the root key; retain Nostr routing identity explicitly.
    payload_bytes.extend_from_slice(&sender_pubkey);
    if let Some(signature) = card_signature {
        payload_bytes.extend_from_slice(&signature);
    }

    let local_prepared = match engine.prepare_domain_event(
        EventKind::InvitationSent,
        payload_bytes.clone(),
        Some(PubKey::from(to_pubkey)),
    ) {
        Ok(prepared) => prepared,
        Err(_) => {
            set_last_error("Send invitation failed: final local event signing failed");
            return -6;
        }
    };
    match append_prepared_event(local_prepared) {
        Ok(_) => {}
        Err(_) => {
            set_last_error("Send invitation failed: append InvitationSent to local ledger failed");
            return -6;
        }
    };

    // The ledger fact is now durable. Delivery is performed only by the
    // capsule-scoped outbox using this invitation_id, never by this use-case.
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

#[derive(Default)]
struct IngressCounters {
    appended: i32,
    loopback: usize,
    routed_non_core: usize,
    unsupported: usize,
    not_addressed: usize,
    proof_invalid: usize,
    signer_mismatch: usize,
    replayed: usize,
    append_failed: usize,
    capacity_backpressure: usize,
    quarantined: usize,
    quarantine_recovered: usize,
    quarantine_expired: usize,
    quarantine_failed: usize,
    quarantine_terminal_replay: usize,
    sender_policy_permitted: usize,
    sender_policy_replayed: usize,
    sender_policy_throttled: usize,
    sender_policy_failed: usize,
    adapter_rejected: usize,
    accepted_seen: usize,
    accepted_replayed: usize,
    accepted_appended: usize,
    accepted_projection_reconciled: usize,
}

fn recover_one_quarantined_envelope(
    repository: &mut crate::inbound_quarantine::CapsuleInboundQuarantineRepository<'_>,
    local_pubkey: PubKey,
    seed: &Seed,
    counters: &mut IngressCounters,
    now: u64,
) -> Result<(), crate::inbound_quarantine::QuarantineError> {
    counters.quarantine_expired += repository.expire_due(now)?;
    let Some(recovered) = repository.next_eligible(now)? else {
        return Ok(());
    };
    let disposition = route_inbound_envelope(
        &recovered.adapter_event_id,
        recovered.envelope,
        local_pubkey,
        seed,
        counters,
    );
    match disposition {
        InboundDeliveryDisposition::Consumed => {
            repository.mark_consumed(&recovered.adapter_event_id, now)?;
            counters.quarantine_recovered += 1;
        }
        InboundDeliveryDisposition::Retry => {
            repository.mark_retry(&recovered.adapter_event_id, now)?;
        }
        InboundDeliveryDisposition::Quarantined | InboundDeliveryDisposition::AdapterRejected => {
            return Err(crate::inbound_quarantine::QuarantineError::InvalidRecord);
        }
    }
    Ok(())
}

fn route_inbound_envelope(
    event_id: &str,
    message: DeliveryEnvelope,
    local_pubkey: PubKey,
    seed: &Seed,
    counters: &mut IngressCounters,
) -> InboundDeliveryDisposition {
    let local_endpoint = *local_pubkey.as_bytes();
    eprintln!(
        "[Delivery/Nostr] Received message kind={} payload_len={} to_prefix={:02x?}",
        message.kind,
        message.payload.len(),
        &message.to[..4]
    );

    if message.from == local_endpoint {
        counters.loopback += 1;
        eprintln!(
            "[Delivery/Nostr] Skip loopback message kind={} from local pubkey",
            message.kind
        );
        return InboundDeliveryDisposition::Consumed;
    }

    let capsule_state = match current_capsule_state() {
        Some(state) => state,
        None => return InboundDeliveryDisposition::Retry,
    };
    match crate::chat_api::queue_incoming_chat_if_match(
        &message,
        event_id,
        local_endpoint,
        &capsule_state,
        seed,
    ) {
        InboundRouteResult::Consumed => {
            counters.routed_non_core += 1;
            return InboundDeliveryDisposition::Consumed;
        }
        InboundRouteResult::Retry => {
            counters.capacity_backpressure += 1;
            return InboundDeliveryDisposition::Retry;
        }
        InboundRouteResult::NotMatched => {}
    }
    match crate::consensus_attestation_api::queue_incoming_attestation_if_match(
        &message,
        event_id,
        local_endpoint,
    ) {
        InboundRouteResult::Consumed => {
            counters.routed_non_core += 1;
            return InboundDeliveryDisposition::Consumed;
        }
        InboundRouteResult::Retry => {
            counters.capacity_backpressure += 1;
            return InboundDeliveryDisposition::Retry;
        }
        InboundRouteResult::NotMatched => {}
    }

    let kind_u8 = match u8::try_from(message.kind) {
        Ok(value) => value,
        Err(_) => {
            counters.unsupported += 1;
            eprintln!(
                "[Delivery/Nostr] Skip message: unsupported kind value {}",
                message.kind
            );
            return InboundDeliveryDisposition::Consumed;
        }
    };
    let kind = match event_kind_from_u8(kind_u8) {
        Some(value) => value,
        None => {
            counters.unsupported += 1;
            eprintln!("[Delivery/Nostr] Skip message: unmapped kind {}", kind_u8);
            return InboundDeliveryDisposition::Consumed;
        }
    };

    let payload_targets_local = if kind == EventKind::InvitationSent && message.payload.len() >= 96
    {
        let mut to_from_payload = [0u8; 32];
        to_from_payload.copy_from_slice(&message.payload[64..96]);
        to_from_payload == local_endpoint
    } else {
        false
    };
    let expired_targets_local =
        if kind == EventKind::InvitationExpired && message.payload.len() == 32 {
            let mut invitation_id = [0u8; 32];
            invitation_id.copy_from_slice(&message.payload);
            incoming_invitation_expired_matches_runtime(&invitation_id, PubKey::from(message.from))
        } else {
            false
        };
    if message.to != local_endpoint && !payload_targets_local && !expired_targets_local {
        counters.not_addressed += 1;
        eprintln!("[Delivery/Nostr] Skip message: not addressed to local capsule");
        return InboundDeliveryDisposition::Consumed;
    }

    let local_payload = message.payload.clone();
    let local_kind = if kind == EventKind::InvitationSent {
        EventKind::InvitationReceived
    } else {
        kind
    };
    let is_accepted = local_kind == EventKind::InvitationAccepted;
    if is_accepted {
        counters.accepted_seen += 1;
    }

    let verified_event = match verified_event_from_message(&message, local_kind) {
        Ok(event) => event,
        Err(err) => {
            counters.proof_invalid += 1;
            eprintln!("[Delivery/Nostr] Skip message: {}", err);
            return InboundDeliveryDisposition::Consumed;
        }
    };
    let message_signer = *verified_event.signer();
    if !proof_signer_matches_payload(local_kind, &local_payload, message_signer) {
        counters.signer_mismatch += 1;
        eprintln!("[Delivery/Nostr] Skip message: proof signer does not match payload root");
        return InboundDeliveryDisposition::Consumed;
    }
    if should_skip_incoming_delivery_append_with_timestamp(
        local_kind,
        &local_payload,
        message_signer,
        Some(message.timestamp),
    ) {
        counters.replayed += 1;
        if is_accepted {
            counters.accepted_replayed += 1;
            match project_invitation_accepted_delivery(seed, message.from, &local_payload) {
                Ok(()) => counters.accepted_projection_reconciled += 1,
                Err(err) => {
                    eprintln!(
                        "[Delivery/Nostr] Failed to reconcile RelationshipEstablished from replayed InvitationAccepted ({})",
                        err
                    );
                    return InboundDeliveryDisposition::Retry;
                }
            }
        } else if local_kind == EventKind::InvitationRejected && local_payload.len() == 33 {
            if let Ok(payload) = InvitationRejectedPayload::from_bytes(&local_payload) {
                let engine = build_engine(seed);
                if let Err(err) = project_effects_from_invitation_rejected(&engine, &payload) {
                    eprintln!(
                        "[Delivery/Nostr] Failed to reconcile local effects from replayed InvitationRejected ({})",
                        err
                    );
                    return InboundDeliveryDisposition::Retry;
                }
            }
        }
        eprintln!("[Delivery/Nostr] Skip message: event already exists");
        return InboundDeliveryDisposition::Consumed;
    }

    if let Err(err) = append_verified_runtime_event(verified_event) {
        counters.append_failed += 1;
        eprintln!("[Delivery/Nostr] Skip message: append failed ({})", err);
        return InboundDeliveryDisposition::Retry;
    }
    counters.appended += 1;
    if is_accepted {
        counters.accepted_appended += 1;
    }

    if kind == EventKind::InvitationAccepted {
        if let Err(err) = project_invitation_accepted_delivery(seed, message.from, &message.payload)
        {
            eprintln!(
                "[Delivery/Nostr] Failed to project RelationshipEstablished from InvitationAccepted ({})",
                err
            );
            return InboundDeliveryDisposition::Retry;
        }
    } else if kind == EventKind::InvitationRejected && message.payload.len() == 33 {
        if let Ok(payload) = InvitationRejectedPayload::from_bytes(&message.payload) {
            let engine = build_engine(seed);
            if let Err(err) = project_effects_from_invitation_rejected(&engine, &payload) {
                eprintln!(
                    "[Delivery/Nostr] Failed to project local effects from InvitationRejected ({})",
                    err
                );
                return InboundDeliveryDisposition::Retry;
            }
        }
    }

    InboundDeliveryDisposition::Consumed
}

fn hivra_transport_receive_with_profile(profile: TransportProfile) -> i32 {
    clear_last_error();
    clear_delivery_receipts();
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
    let capsule_state = match current_capsule_state() {
        Some(state) => state,
        None => return -3,
    };
    let scope = crate::inbound_quarantine::InboundQuarantineScopeV1::for_runtime(
        &capsule_state.public_key,
        capsule_state.network,
        &local_pubkey,
    );
    let mut quarantine =
        match crate::inbound_quarantine::CapsuleInboundQuarantineRepository::open(scope, &seed) {
            Ok(repository) => repository,
            Err(error) => {
                set_last_error(format!(
                    "Transport receive blocked: inbound quarantine unavailable ({error})"
                ));
                return -7;
            }
        };
    let mut counters = IngressCounters::default();
    let receive_now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0);
    if let Err(error) = recover_one_quarantined_envelope(
        &mut quarantine,
        PubKey::from(local_pubkey),
        &seed,
        &mut counters,
        receive_now,
    ) {
        set_last_error(format!(
            "Transport receive blocked: inbound quarantine recovery failed ({error})"
        ));
        return -7;
    }

    let (batch, receive_diagnostic) =
        match with_cached_nostr_transport(sender_secret, profile, -4, |transport| {
            let batch = transport
                .receive_batch_with_timeout(profile.receive_timeout_secs())
                .map_err(|_| -5)?;
            Ok((batch, transport.last_receive_diagnostic()))
        }) {
            Ok(result) => result,
            Err(code) => return code,
        };
    let batch_id = batch.batch_id;
    let mut resolutions = Vec::with_capacity(batch.items.len());
    for item in batch.items {
        let event_id = item.event_id;
        let observed_by = item.observed_by;
        let disposition = match item.payload {
            InboundDeliveryPayload::AdapterRejected { reason } => {
                counters.adapter_rejected += 1;
                eprintln!(
                    "[Delivery/Nostr] Adapter rejected event={} reason={}",
                    event_id, reason
                );
                InboundDeliveryDisposition::AdapterRejected
            }
            InboundDeliveryPayload::Envelope(message) => {
                if quarantine.has_terminal_evidence(&event_id) {
                    counters.quarantine_terminal_replay += 1;
                    InboundDeliveryDisposition::Consumed
                } else {
                    match quarantine.apply_sender_policy(
                        &event_id,
                        &observed_by,
                        &message,
                        receive_now,
                    ) {
                        Ok(crate::inbound_quarantine::SenderIngressDecision::Quarantined) => {
                            counters.quarantined += 1;
                            counters.sender_policy_throttled += 1;
                            InboundDeliveryDisposition::Quarantined
                        }
                        Ok(policy_decision) => {
                            match policy_decision {
                                crate::inbound_quarantine::SenderIngressDecision::Permit => {
                                    counters.sender_policy_permitted += 1;
                                }
                                crate::inbound_quarantine::SenderIngressDecision::AlreadyCharged => {
                                    counters.sender_policy_replayed += 1;
                                }
                                crate::inbound_quarantine::SenderIngressDecision::Quarantined => {
                                    unreachable!()
                                }
                            }
                            let route_disposition = route_inbound_envelope(
                                &event_id,
                                message.clone(),
                                PubKey::from(local_pubkey),
                                &seed,
                                &mut counters,
                            );
                            if route_disposition == InboundDeliveryDisposition::Retry {
                                match quarantine.quarantine(
                                    &event_id,
                                    &observed_by,
                                    &message,
                                    "canonical_route_retry",
                                    receive_now,
                                ) {
                                    Ok(()) => {
                                        counters.quarantined += 1;
                                        InboundDeliveryDisposition::Quarantined
                                    }
                                    Err(error) => {
                                        counters.quarantine_failed += 1;
                                        eprintln!(
                                            "[Delivery/Nostr] Quarantine backpressure event={} reason={}",
                                            event_id, error
                                        );
                                        InboundDeliveryDisposition::Retry
                                    }
                                }
                            } else {
                                route_disposition
                            }
                        }
                        Err(error) => {
                            counters.sender_policy_failed += 1;
                            eprintln!(
                                "[Delivery/Nostr] Sender policy backpressure event={} reason={}",
                                event_id, error
                            );
                            InboundDeliveryDisposition::Retry
                        }
                    }
                }
            }
        };
        resolutions.push(InboundDeliveryResolution {
            event_id,
            disposition,
        });
    }

    if with_current_nostr_transport(sender_secret, -6, |transport| {
        transport
            .resolve_receive_batch(batch_id, resolutions.clone())
            .map_err(|_| -6)
    })
    .is_err()
    {
        set_last_error(format!(
            "Transport receive diagnostic: {receive_diagnostic}; ingress resolution failed for batch={batch_id}"
        ));
        return -6;
    }

    let retry = resolutions
        .iter()
        .filter(|resolution| resolution.disposition == InboundDeliveryDisposition::Retry)
        .count();
    set_last_error(format!(
        "Transport receive diagnostic: {receive_diagnostic}; ingress=[batch={batch_id}, appended={}, loopback={}, non_core={}, unsupported={}, not_addressed={}, proof_invalid={}, signer_mismatch={}, replayed={}, append_failed={}, capacity_backpressure={}, quarantined={}, quarantine_recovered={}, quarantine_expired={}, quarantine_failed={}, quarantine_terminal_replay={}, sender_policy_permitted={}, sender_policy_replayed={}, sender_policy_throttled={}, sender_policy_failed={}, adapter_rejected={}, retry={retry}, accepted_seen={}, accepted_replayed={}, accepted_appended={}, accepted_projection_reconciled={}]",
        counters.appended,
        counters.loopback,
        counters.routed_non_core,
        counters.unsupported,
        counters.not_addressed,
        counters.proof_invalid,
        counters.signer_mismatch,
        counters.replayed,
        counters.append_failed,
        counters.capacity_backpressure,
        counters.quarantined,
        counters.quarantine_recovered,
        counters.quarantine_expired,
        counters.quarantine_failed,
        counters.quarantine_terminal_replay,
        counters.sender_policy_permitted,
        counters.sender_policy_replayed,
        counters.sender_policy_throttled,
        counters.sender_policy_failed,
        counters.adapter_rejected,
        counters.accepted_seen,
        counters.accepted_replayed,
        counters.accepted_appended,
        counters.accepted_projection_reconciled,
    ));

    counters.appended
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
        set_last_error("Accept invitation failed: invitation is no longer pending");
        return -15;
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

    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => {
            set_last_error("Accept invitation failed: sender key derivation failed");
            return -4;
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

    if let Err(err) = finalize_local_acceptance(&engine, &acceptance_plan, from_pubkey) {
        eprintln!(
            "[Accept] finalize failed invitation={:02x?}: {}",
            &invitation_id[..4],
            err
        );
        set_last_error(format!(
            "Accept invitation failed: finalize local acceptance failed ({err})"
        ));
        return -10;
    }

    eprintln!(
        "[Accept] finalize ok invitation={:02x?}",
        &invitation_id[..4]
    );

    // Outbound acceptance is a separate, exact terminal-delivery item.
    0
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

    match append_prepared_event(prepared) {
        Ok(_) => {
            // The terminal fact is durable; its exact transport effect is
            // queued by the host lifecycle after this call returns.
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

    if !matches!(find_invitation_sent_in_runtime(&invitation_id), Some(record) if !record.is_incoming)
    {
        return -4;
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

#[cfg(test)]
mod quarantine_recovery_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn quarantined_chat_recovers_through_the_canonical_router() {
        let _guard = crate::inbound_quarantine::TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        crate::inbound_quarantine::set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([41; 32]);
        let local_pubkey = [42; 32];
        let owner = PubKey::from([43; 32]);
        RUNTIME.lock().unwrap().capsule = Some(Capsule {
            pubkey: owner,
            capsule_type: CapsuleType::Leaf,
            network: Network::Neste,
            ledger: Ledger::new(owner),
        });
        let scope = crate::inbound_quarantine::InboundQuarantineScopeV1::for_runtime(
            &[43; 32],
            1,
            &local_pubkey,
        );
        let mut repository =
            crate::inbound_quarantine::CapsuleInboundQuarantineRepository::open(scope, &seed)
                .unwrap();
        let envelope = DeliveryEnvelope {
            schema_version: 1,
            from: [44; 32],
            to: local_pubkey,
            kind: crate::chat_api::CAPSULE_CHAT_KIND,
            payload: b"{\"text\":\"recover\"}".to_vec(),
            timestamp: 100,
            correlation_id: None,
            domain_event: None,
        };
        let capsule_hex = [43u8; 32]
            .iter()
            .map(|value| format!("{value:02x}"))
            .collect::<String>();
        let chat_path = crate::chat_api::chat_handoff_path(&capsule_hex).unwrap();
        std::fs::create_dir_all(chat_path.parent().unwrap()).unwrap();
        std::fs::write(&chat_path, b"corrupt").unwrap();
        let mut counters = IngressCounters::default();
        assert_eq!(
            route_inbound_envelope(
                "recover-event",
                envelope.clone(),
                PubKey::from(local_pubkey),
                &seed,
                &mut counters,
            ),
            InboundDeliveryDisposition::Retry
        );
        repository
            .quarantine(
                "recover-event",
                &[],
                &envelope,
                "canonical_route_retry",
                100,
            )
            .unwrap();

        std::fs::remove_file(&chat_path).unwrap();
        recover_one_quarantined_envelope(
            &mut repository,
            PubKey::from(local_pubkey),
            &seed,
            &mut counters,
            115,
        )
        .unwrap();

        assert_eq!(
            crate::chat_api::list_chat_handoff(
                &current_capsule_state().unwrap(),
                local_pubkey,
                &seed,
            )
            .unwrap()
            .len(),
            1
        );
        assert_eq!(repository.record_count(), 0);
        assert_eq!(repository.tombstone_count(), 1);
        assert_eq!(counters.quarantine_recovered, 1);
        std::fs::remove_file(chat_path).unwrap();
        RUNTIME.lock().unwrap().capsule = None;
    }
}
