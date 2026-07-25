use super::*;
use hivra_core::event_payloads::{EventPayload, RelationshipEstablishedPayload};

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
    break_relationship_with_delivery_reference(
        peer_pubkey_ptr,
        own_starter_id_ptr,
        peer_starter_id_ptr,
        None,
    )
}

/// Append the local break fact and return its immutable signed event ID.
/// The host outbox owns publication; this function deliberately performs no
/// transport I/O so a local state transition cannot trigger hidden retries.
#[no_mangle]
pub unsafe extern "C" fn hivra_break_relationship_with_delivery_reference(
    peer_pubkey_ptr: *const u8,
    own_starter_id_ptr: *const u8,
    peer_starter_id_ptr: *const u8,
    delivery_reference_out: *mut u8,
) -> i32 {
    if delivery_reference_out.is_null() {
        return -1;
    }
    break_relationship_with_delivery_reference(
        peer_pubkey_ptr,
        own_starter_id_ptr,
        peer_starter_id_ptr,
        Some(delivery_reference_out),
    )
}

unsafe fn break_relationship_with_delivery_reference(
    peer_pubkey_ptr: *const u8,
    own_starter_id_ptr: *const u8,
    peer_starter_id_ptr: *const u8,
    delivery_reference_out: Option<*mut u8>,
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

    let engine = build_engine(&seed);
    let peer_root_pubkey = peer_root_for_relationship(peer_pubkey, own_starter_id, peer_starter_id);

    let local_prepared =
        match engine.prepare_relationship_broken(peer_pubkey, own_starter_id, peer_root_pubkey) {
            Ok(prepared) => prepared,
            Err(_) => return -4,
        };
    // The locally appended event is the outbox reference. The remote envelope
    // is reconstructed only when that exact reference is pumped.
    let delivery_reference = local_prepared.event.event_id();

    if append_prepared_event(local_prepared).is_err() {
        return -7;
    }

    if let Some(out) = delivery_reference_out {
        std::ptr::copy_nonoverlapping(delivery_reference.as_ptr(), out, 32);
    }

    0
}
