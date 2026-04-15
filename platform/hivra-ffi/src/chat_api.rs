use super::*;
use serde::Serialize;
use std::collections::HashMap;
use std::fmt::Write;

const CAPSULE_CHAT_KIND: u32 = 4097;
const CHAT_INBOX_CAPACITY: usize = 512;

#[derive(Clone, Serialize)]
pub(crate) struct QueuedChatMessage {
    from_hex: String,
    to_hex: String,
    payload_json: String,
    timestamp_ms: u64,
}

static CHAT_INBOX: Lazy<Mutex<HashMap<[u8; 32], Vec<QueuedChatMessage>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

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

fn load_chat_delivery_context(seed: &Seed) -> Result<([u8; 32], [u8; 32]), i32> {
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

pub(crate) fn queue_incoming_chat_if_match(message: &Message, local_pubkey: [u8; 32]) -> bool {
    if message.kind != CAPSULE_CHAT_KIND {
        return false;
    }

    if message.to != local_pubkey || message.from == local_pubkey {
        return true;
    }

    let Ok(payload_json) = std::str::from_utf8(&message.payload) else {
        return true;
    };
    let payload_json = payload_json.trim();
    if payload_json.is_empty() {
        return true;
    }

    let from_hex = bytes_to_hex(&message.from);
    let to_hex = bytes_to_hex(&message.to);
    let mut inbox = CHAT_INBOX.lock().unwrap();
    let messages = inbox.entry(local_pubkey).or_insert_with(Vec::new);

    let duplicate = messages.iter().any(|queued| {
        queued.timestamp_ms == message.timestamp
            && queued.from_hex == from_hex
            && queued.payload_json == payload_json
    });
    if duplicate {
        return true;
    }

    if messages.len() >= CHAT_INBOX_CAPACITY {
        let overflow = messages.len() + 1 - CHAT_INBOX_CAPACITY;
        messages.drain(0..overflow);
    }

    messages.push(QueuedChatMessage {
        from_hex,
        to_hex,
        payload_json: payload_json.to_string(),
        timestamp_ms: message.timestamp,
    });

    true
}

fn drain_queued_chat(local_pubkey: [u8; 32]) -> Vec<QueuedChatMessage> {
    let mut inbox = CHAT_INBOX.lock().unwrap();
    inbox.remove(&local_pubkey).unwrap_or_default()
}

#[no_mangle]
pub unsafe extern "C" fn hivra_send_capsule_chat(
    to_pubkey_ptr: *const u8,
    payload_json_ptr: *const c_char,
) -> i32 {
    clear_last_error();
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

    let message = Message {
        from: sender_pubkey,
        to: to_pubkey,
        kind: CAPSULE_CHAT_KIND,
        payload: payload_json.as_bytes().to_vec(),
        timestamp: now_ms(),
        invitation_id: None,
    };

    if let Err(code) =
        with_cached_nostr_transport(sender_secret, TransportProfile::Quick, -5, |transport| {
            transport
                .send(message.clone())
                .map_err(|err| map_delivery_error(err, -6))
        })
    {
        set_last_error(format!(
            "Capsule chat send failed: transport rejected message (code {code})"
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

    let (sender_secret, local_pubkey) = match load_chat_delivery_context(&seed) {
        Ok(context) => context,
        Err(code) => {
            set_last_error(format!(
                "Capsule chat receive failed: delivery context init failed (code {code})"
            ));
            return code;
        }
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            set_last_error("Capsule chat receive failed: capsule runtime is not initialized");
            return -4;
        }
    }

    let fetched =
        with_cached_nostr_transport(sender_secret, TransportProfile::Quick, -5, |transport| {
            transport
                .receive()
                .map_err(|err| map_delivery_error(err, -6))
        });
    if let Ok(messages) = fetched {
        for message in messages {
            let _ = queue_incoming_chat_if_match(&message, local_pubkey);
        }
    } else if let Err(code) = fetched {
        set_last_error(format!(
            "Capsule chat receive failed: transport receive error (code {code})"
        ));
        return code;
    }

    let queued = drain_queued_chat(local_pubkey);
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
