use super::*;
use serde::Serialize;
use std::collections::HashMap;
use std::fmt::Write;

const PAIR_CONSENSUS_ATTESTATION_KIND: u32 = 4098;
const ATTESTATION_INBOX_CAPACITY: usize = 512;

#[derive(Clone, Serialize)]
pub(crate) struct QueuedConsensusAttestation {
    #[serde(skip_serializing)]
    event_id: String,
    from_hex: String,
    to_hex: String,
    payload_json: String,
    timestamp_ms: u64,
}

static CONSENSUS_ATTESTATION_INBOX: Lazy<
    Mutex<HashMap<[u8; 32], Vec<QueuedConsensusAttestation>>>,
> = Lazy::new(|| Mutex::new(HashMap::new()));

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

fn bytes_to_hex(bytes: &[u8; 32]) -> String {
    let mut out = String::with_capacity(64);
    for value in bytes {
        let _ = write!(&mut out, "{:02x}", value);
    }
    out
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

fn load_attestation_delivery_context(seed: &Seed) -> Result<([u8; 32], [u8; 32]), i32> {
    let sender_secret = match derive_nostr_keypair(seed) {
        Ok(key) => key,
        Err(_) => return Err(-3),
    };

    let sender_pubkey = match derive_nostr_public_key(seed) {
        Ok(key) => key,
        Err(_) => return Err(-3),
    };

    Ok((sender_secret, sender_pubkey))
}

pub(crate) fn queue_incoming_attestation_if_match(
    message: &DeliveryEnvelope,
    event_id: &str,
    local_pubkey: [u8; 32],
) -> InboundRouteResult {
    if message.kind != PAIR_CONSENSUS_ATTESTATION_KIND {
        return InboundRouteResult::NotMatched;
    }

    if message.to != local_pubkey || message.from == local_pubkey {
        return InboundRouteResult::Consumed;
    }

    let Ok(payload_json) = std::str::from_utf8(&message.payload) else {
        return InboundRouteResult::Consumed;
    };
    let payload_json = payload_json.trim();
    if payload_json.is_empty() {
        return InboundRouteResult::Consumed;
    }

    let from_hex = bytes_to_hex(&message.from);
    let to_hex = bytes_to_hex(&message.to);
    let mut inbox = CONSENSUS_ATTESTATION_INBOX.lock().unwrap();
    let messages = inbox.entry(local_pubkey).or_insert_with(Vec::new);

    let duplicate = messages.iter().any(|queued| queued.event_id == event_id);
    if duplicate {
        return InboundRouteResult::Consumed;
    }

    if messages.len() >= ATTESTATION_INBOX_CAPACITY {
        return InboundRouteResult::Retry;
    }

    messages.push(QueuedConsensusAttestation {
        event_id: event_id.to_string(),
        from_hex,
        to_hex,
        payload_json: payload_json.to_string(),
        timestamp_ms: message.timestamp,
    });

    InboundRouteResult::Consumed
}

fn drain_queued_attestations(local_pubkey: [u8; 32]) -> Vec<QueuedConsensusAttestation> {
    let mut inbox = CONSENSUS_ATTESTATION_INBOX.lock().unwrap();
    inbox.remove(&local_pubkey).unwrap_or_default()
}

#[cfg(test)]
mod ingress_tests {
    use super::*;

    #[test]
    fn full_attestation_inbox_returns_retry_without_evicting() {
        let local_pubkey = [203; 32];
        CONSENSUS_ATTESTATION_INBOX.lock().unwrap().insert(
            local_pubkey,
            (0..ATTESTATION_INBOX_CAPACITY)
                .map(|index| QueuedConsensusAttestation {
                    event_id: format!("event-{index}"),
                    from_hex: format!("sender-{index}"),
                    to_hex: "local".to_string(),
                    payload_json: "{}".to_string(),
                    timestamp_ms: index as u64,
                })
                .collect(),
        );
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: [204; 32],
            to: local_pubkey,
            kind: PAIR_CONSENSUS_ATTESTATION_KIND,
            payload: b"{\"proof\":\"retry\"}".to_vec(),
            timestamp: 999,
            correlation_id: None,
            domain_event: None,
        };

        assert_eq!(
            queue_incoming_attestation_if_match(&message, "event-retry", local_pubkey),
            InboundRouteResult::Retry
        );
        assert_eq!(
            CONSENSUS_ATTESTATION_INBOX
                .lock()
                .unwrap()
                .get(&local_pubkey)
                .unwrap()
                .len(),
            ATTESTATION_INBOX_CAPACITY
        );
        CONSENSUS_ATTESTATION_INBOX
            .lock()
            .unwrap()
            .remove(&local_pubkey);
    }
}

#[no_mangle]
pub unsafe extern "C" fn hivra_send_pair_consensus_attestation(
    to_pubkey_ptr: *const u8,
    payload_json_ptr: *const c_char,
) -> i32 {
    clear_last_error();
    clear_delivery_receipts();
    if to_pubkey_ptr.is_null() || payload_json_ptr.is_null() {
        set_last_error("Pair consensus attestation send failed: invalid arguments");
        return -1;
    }

    let payload_json = match CStr::from_ptr(payload_json_ptr).to_str() {
        Ok(value) => value.trim(),
        Err(_) => {
            set_last_error("Pair consensus attestation send failed: payload is not valid UTF-8");
            return -1;
        }
    };
    if payload_json.is_empty() {
        set_last_error("Pair consensus attestation send failed: payload is empty");
        return -1;
    }

    let to_slice = std::slice::from_raw_parts(to_pubkey_ptr, 32);
    let mut to_pubkey = [0u8; 32];
    to_pubkey.copy_from_slice(to_slice);

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Pair consensus attestation send failed: seed not found");
            return -2;
        }
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            set_last_error(
                "Pair consensus attestation send failed: capsule runtime is not initialized",
            );
            return -4;
        }
    }

    let (sender_secret, sender_pubkey) = match load_attestation_delivery_context(&seed) {
        Ok(context) => context,
        Err(code) => {
            set_last_error(format!(
                "Pair consensus attestation send failed: delivery context init failed (code {code})"
            ));
            return code;
        }
    };

    let message = DeliveryEnvelope {
        schema_version: 1,
        from: sender_pubkey,
        to: to_pubkey,
        kind: PAIR_CONSENSUS_ATTESTATION_KIND,
        payload: payload_json.as_bytes().to_vec(),
        timestamp: now_ms(),
        correlation_id: None,
        domain_event: None,
    };

    let delivery_reason = Mutex::new(None::<String>);
    let profile = TransportProfile::Quick;
    if let Err(code) = with_cached_nostr_transport(sender_secret, profile, -5, |transport| {
        transport
            .send_with_receipt_with_timeout(message.clone(), profile.publish_timeout_secs())
            .map(|receipt| {
                eprintln!(
                    "[ConsensusAttestation/Nostr] accepted envelope={} by={}",
                    receipt.envelope_id, receipt.accepted_by
                );
                record_delivery_receipt("PairConsensusAttestation", receipt);
            })
            .map_err(|err| {
                let reason = describe_transport_error(&err);
                eprintln!(
                    "[ConsensusAttestation/Nostr] send failed: {:?}{}",
                    err,
                    reason
                        .as_deref()
                        .map(|value| format!(" | reason={value}"))
                        .unwrap_or_default()
                );
                if let Ok(mut guard) = delivery_reason.lock() {
                    *guard = reason;
                }
                map_delivery_error(err, -6)
            })
    }) {
        let reason_suffix = delivery_reason
            .lock()
            .ok()
            .and_then(|guard| guard.as_deref().map(|value| format!(": {value}")))
            .unwrap_or_default();
        set_last_error(format!(
            "Pair consensus attestation send failed: transport rejected message (code {code}{reason_suffix})"
        ));
        return code;
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_receive_pair_consensus_attestations_json(
    out_json: *mut *mut c_char,
) -> i32 {
    clear_last_error();
    if out_json.is_null() {
        set_last_error("Pair consensus attestation receive failed: output pointer is null");
        return -1;
    }

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Pair consensus attestation receive failed: seed not found");
            return -2;
        }
    };

    let local_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => {
            set_last_error(format!(
                "Pair consensus attestation receive failed: delivery context initialization failed"
            ));
            return -3;
        }
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            set_last_error(
                "Pair consensus attestation receive failed: capsule runtime is not initialized",
            );
            return -4;
        }
    }

    // The application-level passive receive coordinator polls the canonical
    // transport ingress exactly once before capability queues are drained.
    let queued = drain_queued_attestations(local_pubkey);
    let json = match serde_json::to_string(&queued) {
        Ok(value) => value,
        Err(_) => {
            set_last_error("Pair consensus attestation receive failed: serialization error");
            return -7;
        }
    };
    match CString::new(json) {
        Ok(cstr) => {
            *out_json = cstr.into_raw();
            queued.len() as i32
        }
        Err(_) => {
            set_last_error("Pair consensus attestation receive failed: output contains NUL");
            -8
        }
    }
}
