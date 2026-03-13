use super::*;

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

    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -3,
    };
    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => PubKey::from(key),
        Err(_) => return -3,
    };

    let engine = build_engine(&seed);
    let local_prepared = match engine.prepare_relationship_broken(peer_pubkey, own_starter_id) {
        Ok(prepared) => prepared,
        Err(_) => return -4,
    };
    let remote_prepared = match engine.prepare_relationship_broken(sender_pubkey, peer_starter_id) {
        Ok(prepared) => prepared,
        Err(_) => return -4,
    };

    let transport = match NostrTransport::new(NostrConfig::default(), &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return -5,
    };

    let message = Message {
        from: *sender_pubkey.as_bytes(),
        to: *peer_pubkey.as_bytes(),
        kind: EventKind::RelationshipBroken as u32,
        payload: remote_prepared.event.payload().to_vec(),
        timestamp: remote_prepared.event.timestamp().as_u64(),
        invitation_id: None,
    };

    if transport.send(message).is_err() {
        return -6;
    }

    if append_prepared_event(local_prepared).is_err() {
        return -7;
    }

    0
}
