use super::*;
use hivra_core::primitives::SlotIndex;

/// Create a new capsule from seed
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_create(
    seed_ptr: *const u8,
    _network: u8,
    _capsule_type: u8,
    _owner_mode: u8,
) -> i32 {
    clear_last_error();
    if seed_ptr.is_null() {
        set_last_error("Capsule create failed: seed pointer was null");
        return -1;
    }

    let seed_bytes = std::slice::from_raw_parts(seed_ptr, 32);
    let mut seed_array = [0u8; 32];
    seed_array.copy_from_slice(seed_bytes);
    let seed = Seed(seed_array);

    let network = if _network == 0 {
        Network::Hood
    } else {
        Network::Neste
    };
    let capsule_type = if _capsule_type == 1 {
        CapsuleType::Relay
    } else {
        CapsuleType::Leaf
    };
    let owner_mode = CapsuleOwnerMode::from_u8(_owner_mode);

    match store_seed(&seed) {
        Ok(_) => {
            if let Err(err) = init_runtime_state(&seed, network, capsule_type, owner_mode) {
                set_last_error(format!("Capsule create failed during runtime init: {err}"));
                return -2;
            }
            0
        }
        Err(err) => {
            set_last_error(format!("Capsule create failed while storing seed: {err}"));
            -1
        }
    }
}

/// Get the current runtime owner public key from the active capsule.
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_runtime_owner_public_key(out_key: *mut u8) -> i32 {
    clear_last_error();
    if out_key.is_null() {
        set_last_error("Capsule runtime owner public key failed: output pointer was null");
        return -1;
    }

    let runtime = RUNTIME.lock().unwrap();
    let capsule = match runtime.capsule.as_ref() {
        Some(capsule) => capsule,
        None => {
            set_last_error("Capsule runtime owner public key failed: no active capsule");
            return -1;
        }
    };

    std::ptr::copy_nonoverlapping(capsule.pubkey.as_bytes().as_ptr(), out_key, 32);
    0
}

/// Get canonical root capsule public key from the stored seed.
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_root_public_key(out_key: *mut u8) -> i32 {
    clear_last_error();
    if out_key.is_null() {
        set_last_error("Capsule root public key failed: output pointer was null");
        return -1;
    }

    match load_seed() {
        Ok(seed) => match derive_root_public_key(&seed) {
            Ok(pubkey) => {
                std::ptr::copy_nonoverlapping(pubkey.as_ptr(), out_key, 32);
                0
            }
            Err(_) => {
                set_last_error("Capsule root public key derivation failed");
                -1
            }
        },
        Err(err) => {
            set_last_error(format!(
                "Capsule root public key failed while loading seed: {err}"
            ));
            -1
        }
    }
}

/// Get Nostr transport public key from the stored seed.
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_nostr_public_key(out_key: *mut u8) -> i32 {
    clear_last_error();
    if out_key.is_null() {
        set_last_error("Capsule Nostr public key failed: output pointer was null");
        return -1;
    }

    match load_seed() {
        Ok(seed) => match derive_nostr_public_key(&seed) {
            Ok(pubkey) => {
                let pubkey_array: [u8; 32] = pubkey;
                std::ptr::copy_nonoverlapping(pubkey_array.as_ptr(), out_key, 32);
                0
            }
            Err(_) => {
                set_last_error("Capsule Nostr public key derivation failed");
                -1
            }
        },
        Err(err) => {
            set_last_error(format!(
                "Capsule Nostr public key failed while loading seed: {err}"
            ));
            -1
        }
    }
}

/// Reset capsule (delete seed and ledger)
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_reset() -> i32 {
    clear_last_error();
    match delete_seed() {
        Ok(_) => {
            clear_runtime_state();
            0
        }
        Err(err) => {
            set_last_error(format!("Capsule reset failed: {err}"));
            -1
        }
    }
}

// ============ STARTER FUNCTIONS ============

/// Get starter ID for a slot (deterministic from seed)
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_id(slot: u8, out_id: *mut u8) -> i32 {
    if out_id.is_null() || slot >= 5 {
        return -1;
    }

    let runtime = RUNTIME.lock().unwrap();
    let capsule = match runtime.capsule.as_ref() {
        Some(capsule) => capsule,
        None => return -1,
    };

    let index = match SlotIndex::new(slot) {
        Some(index) => index,
        None => return -1,
    };
    let layout = hivra_core::slot::SlotLayout::from_ledger(&capsule.ledger);
    let starter_id = match layout.starter_id_at(index) {
        Some(id) => id,
        None => return -1,
    };

    std::ptr::copy_nonoverlapping(starter_id.as_bytes().as_ptr(), out_id, 32);
    0
}

/// Get starter type for a slot (Juice, Spark, Seed, Pulse, Kick)
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_type(slot: u8) -> i32 {
    if slot >= 5 {
        return -1;
    }

    let runtime = RUNTIME.lock().unwrap();
    let capsule = match runtime.capsule.as_ref() {
        Some(capsule) => capsule,
        None => return -1,
    };

    let index = match SlotIndex::new(slot) {
        Some(index) => index,
        None => return -1,
    };
    let layout = hivra_core::slot::SlotLayout::from_ledger(&capsule.ledger);
    let entries = layout.entries_with_kinds(&capsule.ledger);
    let entry = entries[index.as_u8() as usize];

    entry.starter_kind.map(|kind| kind as i32).unwrap_or(-1)
}

/// Check if starter exists in slot
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_exists(slot: u8) -> i8 {
    if slot >= 5 {
        return 0;
    }

    let runtime = RUNTIME.lock().unwrap();
    let capsule = match runtime.capsule.as_ref() {
        Some(capsule) => capsule,
        None => return 0,
    };

    let index = match SlotIndex::new(slot) {
        Some(index) => index,
        None => return 0,
    };
    let layout = hivra_core::slot::SlotLayout::from_ledger(&capsule.ledger);
    if layout.starter_id_at(index).is_some() {
        1
    } else {
        0
    }
}
