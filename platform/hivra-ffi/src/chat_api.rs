use super::*;
use hivra_keystore::{open_chat_handoff_snapshot, seal_chat_handoff_snapshot};
use serde::{Deserialize, Serialize};
use std::fmt::Write;
use std::fs::{self, File, OpenOptions};
use std::io::Write as IoWrite;
use std::path::PathBuf;

pub(crate) const CAPSULE_CHAT_KIND: u32 = 4097;
type ChatTransportKey = [u8; 32];
const CHAT_INBOX_CAPACITY: usize = 512;
const CHAT_HANDOFF_MAX_PLAINTEXT_BYTES: usize = 32 * 1024 * 1024;
const CHAT_TOMBSTONE_CAPACITY: usize = 65_536;
const CHAT_HANDOFF_SCHEMA_VERSION: u16 = 1;
const CHAT_HANDOFF_FILE: &str = "chat_handoff.v1.bin";
const CHAT_HANDOFF_TEMP_FILE: &str = ".chat_handoff.v1.tmp";
static CHAT_HANDOFF_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct QueuedChatMessage {
    event_id: String,
    from_hex: String,
    to_hex: String,
    payload_json: String,
    timestamp_ms: u64,
}

#[derive(Clone, Serialize, Deserialize)]
struct ChatHandoffSnapshotV1 {
    schema_version: u16,
    capsule_id: String,
    network: u8,
    transport_endpoint: String,
    records: Vec<QueuedChatMessage>,
    tombstones: Vec<String>,
}

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

fn bytes_to_hex(bytes: &ChatTransportKey) -> String {
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

fn load_chat_delivery_context(seed: &Seed) -> Result<(ChatTransportKey, ChatTransportKey), i32> {
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

pub(crate) fn queue_incoming_chat_if_match(
    message: &DeliveryEnvelope,
    event_id: &str,
    local_pubkey: ChatTransportKey,
    capsule_state: &CapsuleState,
    seed: &Seed,
) -> InboundRouteResult {
    if message.kind != CAPSULE_CHAT_KIND {
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

    let record = QueuedChatMessage {
        event_id: event_id.to_string(),
        from_hex: bytes_to_hex(&message.from),
        to_hex: bytes_to_hex(&message.to),
        payload_json: payload_json.to_string(),
        timestamp_ms: message.timestamp,
    };
    match persist_chat_handoff(capsule_state, local_pubkey, seed, record) {
        Ok(()) => InboundRouteResult::Consumed,
        Err(error) => {
            eprintln!("[Delivery/Chat] Durable handoff failed: {error}");
            InboundRouteResult::Retry
        }
    }
}

fn chat_handoff_aad(capsule_id: &str, network: u8, endpoint: &str) -> String {
    format!("hivra.chat_handoff.v1|{capsule_id}|{network}|{endpoint}")
}

pub(crate) fn chat_handoff_path(capsule_id: &str) -> Result<PathBuf, String> {
    Ok(crate::inbound_quarantine::application_storage_root()
        .map_err(|error| error.to_string())?
        .join("capsules")
        .join(capsule_id)
        .join("capability_state")
        .join("chat")
        .join(CHAT_HANDOFF_FILE))
}

fn load_chat_handoff(
    capsule_state: &CapsuleState,
    local_pubkey: ChatTransportKey,
    seed: &Seed,
) -> Result<ChatHandoffSnapshotV1, String> {
    let capsule_id = bytes_to_hex(&capsule_state.public_key);
    let endpoint = bytes_to_hex(&local_pubkey);
    let path = chat_handoff_path(&capsule_id)?;
    if !path.exists() {
        return Ok(ChatHandoffSnapshotV1 {
            schema_version: CHAT_HANDOFF_SCHEMA_VERSION,
            capsule_id,
            network: capsule_state.network,
            transport_endpoint: endpoint,
            records: Vec::new(),
            tombstones: Vec::new(),
        });
    }
    let sealed = fs::read(&path).map_err(|_| "read failed".to_string())?;
    let aad = chat_handoff_aad(&capsule_id, capsule_state.network, &endpoint);
    let plaintext = open_chat_handoff_snapshot(seed, aad.as_bytes(), &sealed)
        .map_err(|_| "authentication failed".to_string())?;
    let snapshot: ChatHandoffSnapshotV1 =
        bincode::deserialize(&plaintext).map_err(|_| "snapshot corrupt".to_string())?;
    if snapshot.schema_version != CHAT_HANDOFF_SCHEMA_VERSION
        || snapshot.capsule_id != capsule_id
        || snapshot.network != capsule_state.network
        || snapshot.transport_endpoint != endpoint
        || snapshot.records.len() > CHAT_INBOX_CAPACITY
        || snapshot.tombstones.len() > CHAT_TOMBSTONE_CAPACITY
    {
        return Err("scope or bounds mismatch".to_string());
    }
    Ok(snapshot)
}

fn write_chat_handoff(snapshot: &ChatHandoffSnapshotV1, seed: &Seed) -> Result<(), String> {
    let path = chat_handoff_path(&snapshot.capsule_id)?;
    let parent = path.parent().ok_or_else(|| "invalid path".to_string())?;
    fs::create_dir_all(parent).map_err(|_| "directory create failed".to_string())?;
    let plaintext = bincode::serialize(snapshot).map_err(|_| "serialize failed".to_string())?;
    if plaintext.len() > CHAT_HANDOFF_MAX_PLAINTEXT_BYTES {
        return Err("snapshot capacity exhausted".to_string());
    }
    let aad = chat_handoff_aad(
        &snapshot.capsule_id,
        snapshot.network,
        &snapshot.transport_endpoint,
    );
    let sealed = seal_chat_handoff_snapshot(seed, aad.as_bytes(), &plaintext)
        .map_err(|_| "encryption failed".to_string())?;
    let temp = parent.join(CHAT_HANDOFF_TEMP_FILE);
    if temp.exists() {
        fs::remove_file(&temp).map_err(|_| "temp cleanup failed".to_string())?;
    }
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&temp)
        .map_err(|_| "temp open failed".to_string())?;
    file.write_all(&sealed)
        .map_err(|_| "write failed".to_string())?;
    file.sync_all().map_err(|_| "sync failed".to_string())?;
    fs::rename(&temp, &path).map_err(|_| "rename failed".to_string())?;
    if let Ok(directory) = File::open(parent) {
        let _ = directory.sync_all();
    }
    Ok(())
}

fn persist_chat_handoff(
    capsule_state: &CapsuleState,
    local_pubkey: ChatTransportKey,
    seed: &Seed,
    record: QueuedChatMessage,
) -> Result<(), String> {
    let _guard = CHAT_HANDOFF_LOCK
        .lock()
        .map_err(|_| "lock failed".to_string())?;
    let mut snapshot = load_chat_handoff(capsule_state, local_pubkey, seed)?;
    if snapshot.tombstones.iter().any(|id| id == &record.event_id)
        || snapshot
            .records
            .iter()
            .any(|item| item.event_id == record.event_id)
    {
        return Ok(());
    }
    snapshot.records.push(record);
    snapshot.records.sort_by(|left, right| {
        left.timestamp_ms
            .cmp(&right.timestamp_ms)
            .then_with(|| left.event_id.cmp(&right.event_id))
    });
    while snapshot.records.len() > CHAT_INBOX_CAPACITY {
        let evicted = snapshot.records.remove(0);
        snapshot.tombstones.push(evicted.event_id);
    }
    while bincode::serialized_size(&snapshot).unwrap_or(u64::MAX)
        > CHAT_HANDOFF_MAX_PLAINTEXT_BYTES as u64
    {
        if snapshot.records.len() <= 1 {
            return Err("record exceeds snapshot capacity".to_string());
        }
        let evicted = snapshot.records.remove(0);
        snapshot.tombstones.push(evicted.event_id);
    }
    snapshot.tombstones.sort();
    snapshot.tombstones.dedup();
    if snapshot.tombstones.len() > CHAT_TOMBSTONE_CAPACITY {
        return Err("tombstone capacity exhausted".to_string());
    }
    write_chat_handoff(&snapshot, seed)
}

pub(crate) fn list_chat_handoff(
    capsule_state: &CapsuleState,
    local_pubkey: ChatTransportKey,
    seed: &Seed,
) -> Result<Vec<QueuedChatMessage>, String> {
    let _guard = CHAT_HANDOFF_LOCK
        .lock()
        .map_err(|_| "lock failed".to_string())?;
    Ok(load_chat_handoff(capsule_state, local_pubkey, seed)?.records)
}

fn acknowledge_chat_handoff(
    capsule_state: &CapsuleState,
    local_pubkey: ChatTransportKey,
    seed: &Seed,
    event_ids: &[String],
) -> Result<(), String> {
    let _guard = CHAT_HANDOFF_LOCK
        .lock()
        .map_err(|_| "lock failed".to_string())?;
    let mut snapshot = load_chat_handoff(capsule_state, local_pubkey, seed)?;
    let ids = event_ids
        .iter()
        .map(String::as_str)
        .collect::<std::collections::BTreeSet<_>>();
    if ids.is_empty() {
        return Ok(());
    }
    let mut acknowledged = Vec::new();
    snapshot.records.retain(|record| {
        if ids.contains(record.event_id.as_str()) {
            acknowledged.push(record.event_id.clone());
            false
        } else {
            true
        }
    });
    snapshot.tombstones.extend(acknowledged);
    snapshot.tombstones.sort();
    snapshot.tombstones.dedup();
    if snapshot.tombstones.len() > CHAT_TOMBSTONE_CAPACITY {
        return Err("tombstone capacity exhausted".to_string());
    }
    write_chat_handoff(&snapshot, seed)
}

#[cfg(test)]
mod ingress_tests {
    use super::*;
    use tempfile::tempdir;

    fn state(capsule: u8, network: u8) -> CapsuleState {
        CapsuleState {
            public_key: [capsule; 32],
            capsule_type: 0,
            network,
            slots: [None; 5],
            ledger_hash: 0,
            ledger_head_commitment: None,
            relationships_count: 0,
            version: 0,
        }
    }

    #[test]
    fn durable_chat_handoff_survives_reopen_and_evicts_with_tombstone() {
        let _guard = crate::inbound_quarantine::TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        crate::inbound_quarantine::set_application_storage_root(root.path()).unwrap();
        let local_pubkey = [201; 32];
        let capsule = state(200, 1);
        let seed = Seed::new([199; 32]);
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: [202; 32],
            to: local_pubkey,
            kind: CAPSULE_CHAT_KIND,
            payload: b"{\"text\":\"retry\"}".to_vec(),
            timestamp: 999,
            correlation_id: None,
            domain_event: None,
        };

        assert_eq!(
            queue_incoming_chat_if_match(&message, "event-restart", local_pubkey, &capsule, &seed),
            InboundRouteResult::Consumed
        );
        let reopened = list_chat_handoff(&capsule, local_pubkey, &seed).unwrap();
        assert_eq!(reopened.len(), 1);
        assert_eq!(reopened[0].event_id, "event-restart");
        assert_eq!(
            list_chat_handoff(&capsule, local_pubkey, &seed)
                .unwrap()
                .len(),
            1
        );
        let path = chat_handoff_path(&bytes_to_hex(&capsule.public_key)).unwrap();
        let sealed = fs::read(path).unwrap();
        assert!(!sealed
            .windows(b"{\"text\":\"retry\"}".len())
            .any(|window| window == b"{\"text\":\"retry\"}"));
    }

    #[test]
    fn chat_inbox_deduplicates_by_adapter_event_identity() {
        let _guard = crate::inbound_quarantine::TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        crate::inbound_quarantine::set_application_storage_root(root.path()).unwrap();
        let local_pubkey = [205; 32];
        let capsule = state(204, 1);
        let seed = Seed::new([203; 32]);
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: [206; 32],
            to: local_pubkey,
            kind: CAPSULE_CHAT_KIND,
            payload: b"{\"text\":\"same\"}".to_vec(),
            timestamp: 999,
            correlation_id: None,
            domain_event: None,
        };

        assert_eq!(
            queue_incoming_chat_if_match(&message, "event-one", local_pubkey, &capsule, &seed),
            InboundRouteResult::Consumed
        );
        assert_eq!(
            queue_incoming_chat_if_match(&message, "event-one", local_pubkey, &capsule, &seed),
            InboundRouteResult::Consumed
        );
        assert_eq!(
            queue_incoming_chat_if_match(&message, "event-two", local_pubkey, &capsule, &seed),
            InboundRouteResult::Consumed
        );
        assert_eq!(
            list_chat_handoff(&capsule, local_pubkey, &seed)
                .unwrap()
                .len(),
            2
        );
    }

    #[test]
    fn acknowledgement_is_atomic_and_replay_stays_consumed() {
        let _guard = crate::inbound_quarantine::TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        crate::inbound_quarantine::set_application_storage_root(root.path()).unwrap();
        let local_pubkey = [211; 32];
        let capsule = state(210, 1);
        let seed = Seed::new([209; 32]);
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: [212; 32],
            to: local_pubkey,
            kind: CAPSULE_CHAT_KIND,
            payload: b"{\"command\":\"once\"}".to_vec(),
            timestamp: 1000,
            correlation_id: None,
            domain_event: None,
        };
        assert_eq!(
            queue_incoming_chat_if_match(&message, "event-once", local_pubkey, &capsule, &seed),
            InboundRouteResult::Consumed
        );
        acknowledge_chat_handoff(&capsule, local_pubkey, &seed, &["event-once".to_string()])
            .unwrap();
        assert!(list_chat_handoff(&capsule, local_pubkey, &seed)
            .unwrap()
            .is_empty());
        assert_eq!(
            queue_incoming_chat_if_match(&message, "event-once", local_pubkey, &capsule, &seed),
            InboundRouteResult::Consumed
        );
        assert!(list_chat_handoff(&capsule, local_pubkey, &seed)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn corruption_wrong_key_and_wrong_scope_fail_closed() {
        let _guard = crate::inbound_quarantine::TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        crate::inbound_quarantine::set_application_storage_root(root.path()).unwrap();
        let local_pubkey = [221; 32];
        let capsule = state(220, 1);
        let seed = Seed::new([219; 32]);
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: [222; 32],
            to: local_pubkey,
            kind: CAPSULE_CHAT_KIND,
            payload: b"{\"text\":\"secret\"}".to_vec(),
            timestamp: 1001,
            correlation_id: None,
            domain_event: None,
        };
        assert_eq!(
            queue_incoming_chat_if_match(&message, "event-secret", local_pubkey, &capsule, &seed),
            InboundRouteResult::Consumed
        );
        assert!(list_chat_handoff(&capsule, local_pubkey, &Seed::new([218; 32])).is_err());

        let wrong_scope = state(223, 1);
        let source = chat_handoff_path(&bytes_to_hex(&capsule.public_key)).unwrap();
        let target = chat_handoff_path(&bytes_to_hex(&wrong_scope.public_key)).unwrap();
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        fs::copy(&source, &target).unwrap();
        assert!(list_chat_handoff(&wrong_scope, local_pubkey, &seed).is_err());

        fs::write(&source, b"corrupt").unwrap();
        assert!(list_chat_handoff(&capsule, local_pubkey, &seed).is_err());
    }

    #[test]
    fn record_capacity_evicts_oldest_into_replay_tombstone() {
        let _guard = crate::inbound_quarantine::TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        crate::inbound_quarantine::set_application_storage_root(root.path()).unwrap();
        let local_pubkey = [231; 32];
        let capsule = state(230, 1);
        let seed = Seed::new([229; 32]);
        let mut snapshot = load_chat_handoff(&capsule, local_pubkey, &seed).unwrap();
        snapshot.records = (0..CHAT_INBOX_CAPACITY)
            .map(|index| QueuedChatMessage {
                event_id: format!("event-{index:04}"),
                from_hex: bytes_to_hex(&[232; 32]),
                to_hex: bytes_to_hex(&local_pubkey),
                payload_json: "{}".to_string(),
                timestamp_ms: index as u64,
            })
            .collect();
        write_chat_handoff(&snapshot, &seed).unwrap();
        persist_chat_handoff(
            &capsule,
            local_pubkey,
            &seed,
            QueuedChatMessage {
                event_id: "event-new".to_string(),
                from_hex: bytes_to_hex(&[233; 32]),
                to_hex: bytes_to_hex(&local_pubkey),
                payload_json: "{}".to_string(),
                timestamp_ms: 9999,
            },
        )
        .unwrap();
        let reopened = load_chat_handoff(&capsule, local_pubkey, &seed).unwrap();
        assert_eq!(reopened.records.len(), CHAT_INBOX_CAPACITY);
        assert!(!reopened
            .records
            .iter()
            .any(|item| item.event_id == "event-0000"));
        assert!(reopened.tombstones.contains(&"event-0000".to_string()));
    }
}

#[no_mangle]
pub unsafe extern "C" fn hivra_send_capsule_chat(
    to_pubkey_ptr: *const u8,
    payload_json_ptr: *const c_char,
) -> i32 {
    clear_last_error();
    clear_delivery_receipts();
    if to_pubkey_ptr.is_null() || payload_json_ptr.is_null() {
        set_last_error("Capsule chat send failed: invalid arguments");
        return -1;
    }

    let payload_json = match CStr::from_ptr(payload_json_ptr).to_str() {
        Ok(value) => value.trim(),
        Err(_) => {
            set_last_error("Capsule chat send failed: payload is not valid UTF-8");
            return -1;
        }
    };
    if payload_json.is_empty() {
        set_last_error("Capsule chat send failed: payload is empty");
        return -1;
    }

    let to_slice = std::slice::from_raw_parts(to_pubkey_ptr, 32);
    let mut to_pubkey = [0u8; 32];
    to_pubkey.copy_from_slice(to_slice);

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Capsule chat send failed: seed not found");
            return -2;
        }
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            set_last_error("Capsule chat send failed: capsule runtime is not initialized");
            return -4;
        }
    }

    let (sender_secret, sender_pubkey) = match load_chat_delivery_context(&seed) {
        Ok(context) => context,
        Err(code) => {
            set_last_error(format!(
                "Capsule chat send failed: delivery context init failed (code {code})"
            ));
            return code;
        }
    };

    let message = DeliveryEnvelope {
        schema_version: 1,
        from: sender_pubkey,
        to: to_pubkey,
        kind: CAPSULE_CHAT_KIND,
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
                    "[Chat/Nostr] accepted envelope={} by={}",
                    receipt.envelope_id, receipt.accepted_by
                );
                record_delivery_receipt("CapsuleChat", receipt);
            })
            .map_err(|err| {
                let reason = describe_transport_error(&err);
                eprintln!(
                    "[Chat/Nostr] send failed: {:?}{}",
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
            "Capsule chat send failed: transport rejected message (code {code}{reason_suffix})"
        ));
        return code;
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_receive_capsule_chat_json(out_json: *mut *mut c_char) -> i32 {
    clear_last_error();
    if out_json.is_null() {
        set_last_error("Capsule chat receive failed: output pointer is null");
        return -1;
    }

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Capsule chat receive failed: seed not found");
            return -2;
        }
    };

    let local_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => {
            set_last_error(format!(
                "Capsule chat receive failed: delivery context initialization failed"
            ));
            return -3;
        }
    };

    let capsule_state = match current_capsule_state() {
        Some(state) => state,
        None => {
            set_last_error("Capsule chat receive failed: capsule runtime is not initialized");
            return -4;
        }
    };

    // The application-level passive receive coordinator polls the canonical
    // transport ingress exactly once before the durable capability projection
    // is read. Reading is non-destructive so restart cannot lose accepted
    // transport evidence before Flutter projects it.
    let queued = match list_chat_handoff(&capsule_state, local_pubkey, &seed) {
        Ok(records) => records,
        Err(error) => {
            set_last_error(format!(
                "Capsule chat receive failed: durable handoff unavailable ({error})"
            ));
            return -9;
        }
    };
    let json = match serde_json::to_string(&queued) {
        Ok(value) => value,
        Err(_) => {
            set_last_error("Capsule chat receive failed: serialization error");
            return -7;
        }
    };
    match CString::new(json) {
        Ok(cstr) => {
            *out_json = cstr.into_raw();
            queued.len() as i32
        }
        Err(_) => {
            set_last_error("Capsule chat receive failed: output contains NUL");
            -8
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn hivra_ack_capsule_chat_events_json(
    event_ids_json_ptr: *const c_char,
) -> i32 {
    clear_last_error();
    if event_ids_json_ptr.is_null() {
        set_last_error("Capsule chat acknowledgement failed: null event list");
        return -1;
    }
    let raw = match CStr::from_ptr(event_ids_json_ptr).to_str() {
        Ok(value) => value,
        Err(_) => {
            set_last_error("Capsule chat acknowledgement failed: invalid UTF-8");
            return -1;
        }
    };
    let event_ids: Vec<String> = match serde_json::from_str(raw) {
        Ok(value) => value,
        Err(_) => {
            set_last_error("Capsule chat acknowledgement failed: invalid JSON");
            return -1;
        }
    };
    if event_ids.len() > CHAT_INBOX_CAPACITY
        || event_ids.iter().any(|id| id.is_empty() || id.len() > 128)
    {
        set_last_error("Capsule chat acknowledgement failed: invalid event identity");
        return -1;
    }
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };
    let local_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -3,
    };
    let capsule_state = match current_capsule_state() {
        Some(state) => state,
        None => return -4,
    };
    match acknowledge_chat_handoff(&capsule_state, local_pubkey, &seed, &event_ids) {
        Ok(()) => 0,
        Err(error) => {
            set_last_error(format!("Capsule chat acknowledgement failed: {error}"));
            -9
        }
    }
}
