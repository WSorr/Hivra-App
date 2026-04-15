use super::*;
use hivra_core::event_payloads::{EventPayload, RelationshipEstablishedPayload};

fn load_relationship_delivery_context(seed: &Seed) -> Result<([u8; 32], PubKey), i32> {
    let sender_secret = match derive_nostr_keypair(seed) {
        Ok(key) => key,
        Err(_) => return Err(-3),
    };
    let sender_pubkey = match derive_nostr_public_key(seed) {
        Ok(key) => PubKey::from(key),
        Err(_) => return Err(-3),
    };

    Ok((sender_secret, sender_pubkey))
}

fn peer_root_for_relationship(
    peer_pubkey: PubKey,
    own_starter_id: StarterId,
    peer_starter_id: StarterId,
) -> Option<PubKey> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref()?;
    for event in capsule.ledger.events().iter().rev() {
        if event.kind() != EventKind::RelationshipEstablished {
            continue;
        }
        let Ok(payload) = RelationshipEstablishedPayload::from_bytes(event.payload()) else {
            continue;
        };
        if payload.peer_pubkey == peer_pubkey
            && payload.own_starter_id == own_starter_id
            && payload.peer_starter_id == peer_starter_id
        {
            return payload.peer_root_pubkey;
        }
    }
    None
}

#[no_mangle]
pub unsafe extern "C" fn hivra_break_relationship(
    peer_pubkey_ptr: *const u8,
    own_starter_id_ptr: *const u8,
    peer_starter_id_ptr: *const u8,
) -> i32 {
    if peer_pubkey_ptr.is_null() || own_starter_id_ptr.is_null() || peer_starter_id_ptr.is_null() {
        return -1;
    }

    let peer_pubkey = PubKey::from({
        let mut bytes = [0u8; 32];
        bytes.copy_from_slice(std::slice::from_raw_parts(peer_pubkey_ptr, 32));
        bytes
    });
    let own_starter_id = StarterId::from({
        let mut bytes = [0u8; 32];
        bytes.copy_from_slice(std::slice::from_raw_parts(own_starter_id_ptr, 32));
        bytes
    });
    let peer_starter_id = StarterId::from({
        let mut bytes = [0u8; 32];
        bytes.copy_from_slice(std::slice::from_raw_parts(peer_starter_id_ptr, 32));
        bytes
    });

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };

    let (sender_secret, sender_pubkey) = match load_relationship_delivery_context(&seed) {
        Ok(context) => context,
        Err(code) => return code,
    };

    let engine = build_engine(&seed);
    let local_root_pubkey = match engine.public_key() {
        Ok(pubkey) => pubkey,
        Err(_) => return -4,
    };
    let peer_root_pubkey = peer_root_for_relationship(peer_pubkey, own_starter_id, peer_starter_id);

    let local_prepared =
        match engine.prepare_relationship_broken(peer_pubkey, own_starter_id, peer_root_pubkey) {
            Ok(prepared) => prepared,
            Err(_) => return -4,
        };
    let remote_prepared = match engine.prepare_relationship_broken(
        sender_pubkey,
        peer_starter_id,
        Some(local_root_pubkey),
    ) {
        Ok(prepared) => prepared,
        Err(_) => return -4,
    };

    let message = Message {
        from: *sender_pubkey.as_bytes(),
        to: *peer_pubkey.as_bytes(),
        kind: EventKind::RelationshipBroken as u32,
        payload: remote_prepared.event.payload().to_vec(),
        timestamp: remote_prepared.event.timestamp().as_u64(),
        invitation_id: None,
    };

    if append_prepared_event(local_prepared).is_err() {
        return -7;
    }

    // Local sovereignty is ledger-first: once local break is appended, pairwise
    // local truth must not depend on remote transport availability. Delivery is
    // best-effort for peer convergence and must not block UI-facing FFI callers.
    let delivery_secret = sender_secret;
    let delivery_message = message.clone();
    std::thread::spawn(move || {
        if let Err(code) =
            with_cached_nostr_transport(delivery_secret, TransportProfile::Quick, -5, |transport| {
                transport.send(delivery_message.clone()).map_err(|err| {
                    eprintln!(
                        "[Delivery/Nostr] RelationshipBroken local append ok; delivery failed: {:?}",
                        err
                    );
                    -6
                })
            })
        {
            eprintln!(
                "[Delivery/Nostr] RelationshipBroken local append ok; delivery unavailable ({})",
                code
            );
        }
    });

    0
}
