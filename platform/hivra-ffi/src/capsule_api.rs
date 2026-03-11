use super::*;

/// Create a new capsule from seed
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_create(
    seed_ptr: *const u8,
    _network: u8,
    _capsule_type: u8,
) -> i32 {
    if seed_ptr.is_null() {
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

    match store_seed(&seed) {
        Ok(_) => {
            if init_runtime_state(&seed, network, capsule_type).is_err() {
                return -2;
            }
            0
        }
        Err(_) => -1,
    }
}

/// Get capsule public key (derived from seed)
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_public_key(out_key: *mut u8) -> i32 {
    if out_key.is_null() {
        return -1;
    }

    match load_seed() {
        Ok(seed) => match derive_nostr_public_key(&seed) {
            Ok(pubkey) => {
                let pubkey_array: [u8; 32] = pubkey;
                std::ptr::copy_nonoverlapping(pubkey_array.as_ptr(), out_key, 32);
                0
            }
            Err(_) => -1,
        },
        Err(_) => -1,
    }
}

/// Reset capsule (delete seed and ledger)
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_reset() -> i32 {
    match delete_seed() {
        Ok(_) => {
            clear_runtime_state();
            0
        }
        Err(_) => -1,
    }
}

// ============ STARTER FUNCTIONS ============

/// Get starter ID for a slot (deterministic from seed)
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_id(slot: u8, out_id: *mut u8) -> i32 {
    if out_id.is_null() || slot >= 5 {
        return -1;
    }

    match load_seed() {
        Ok(seed) => {
            let seed_ref: &Seed = &seed;
            let mut hasher = Sha256::new();
            hasher.update(seed_ref.as_bytes());
            hasher.update(&[slot]);
            hasher.update(b"starter_v1");
            let result = hasher.finalize();

            std::ptr::copy_nonoverlapping(result.as_ptr(), out_id, 32);
            0
        }
        Err(_) => -1,
    }
}

/// Get starter type for a slot (Juice, Spark, Seed, Pulse, Kick)
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_type(slot: u8) -> i32 {
    if slot >= 5 {
        return -1;
    }
    slot as i32
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

    let mut by_kind: [Option<[u8; 32]>; 5] = [None, None, None, None, None];

    for event in capsule.ledger.events() {
        match event.kind() {
            EventKind::StarterCreated => {
                if let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) {
                    let kind_idx = payload.kind as usize;
                    if kind_idx < by_kind.len() {
                        by_kind[kind_idx] = Some(*payload.starter_id.as_bytes());
                    }
                }
            }
            EventKind::StarterBurned => {
                if let Ok(payload) = StarterBurnedPayload::from_bytes(event.payload()) {
                    let burned = *payload.starter_id.as_bytes();
                    for slot_ref in by_kind.iter_mut() {
                        if slot_ref.as_ref().is_some_and(|id| *id == burned) {
                            *slot_ref = None;
                        }
                    }
                }
            }
            _ => {}
        }
    }

    if by_kind[slot as usize].is_some() {
        1
    } else {
        0
    }
}
