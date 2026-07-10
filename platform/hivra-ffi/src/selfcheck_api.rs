use super::*;

fn sign_root_digest32(seed: &Seed, message: &[u8; 32]) -> Result<[u8; 64], &'static str> {
    let privkey = derive_root_keypair(seed).map_err(|_| "root key derivation failed")?;
    Ed25519CryptoProvider::new()
        .sign(message, &privkey)
        .map_err(|_| "root signing failed")
}

/// Root runtime signing self-check.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_crypto_self_check() -> i32 {
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -1,
    };

    let privkey = match derive_root_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };
    let pubkey = match derive_root_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -3,
    };

    let provider = Ed25519CryptoProvider::new();
    let msg = [0x42u8; 32];

    let sig = match provider.sign(&msg, &privkey) {
        Ok(sig) => sig,
        Err(_) => return -4,
    };

    match provider.verify(&msg, &pubkey, &sig) {
        Ok(_) => 0,
        Err(_) => -5,
    }
}

/// Verify detached ed25519 signature for a 32-byte message digest.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_verify_ed25519_signature32(
    message_ptr: *const u8,
    pubkey_ptr: *const u8,
    signature_ptr: *const u8,
) -> i32 {
    clear_last_error();
    if message_ptr.is_null() || pubkey_ptr.is_null() || signature_ptr.is_null() {
        set_last_error("Verify ed25519 failed: null pointer argument");
        return -1;
    }

    let mut message = [0u8; 32];
    message.copy_from_slice(std::slice::from_raw_parts(message_ptr, 32));
    let mut pubkey = [0u8; 32];
    pubkey.copy_from_slice(std::slice::from_raw_parts(pubkey_ptr, 32));
    let mut signature = [0u8; 64];
    signature.copy_from_slice(std::slice::from_raw_parts(signature_ptr, 64));

    let provider = Ed25519CryptoProvider::new();
    match provider.verify(&message, &pubkey, &signature) {
        Ok(_) => 0,
        Err(_) => {
            set_last_error("Verify ed25519 failed: signature mismatch");
            -2
        }
    }
}

/// Sign a 32-byte domain commitment with the active Capsule root identity.
#[no_mangle]
pub unsafe extern "C" fn hivra_sign_root_digest32(
    message_ptr: *const u8,
    signature_out: *mut u8,
) -> i32 {
    clear_last_error();
    if message_ptr.is_null() || signature_out.is_null() {
        set_last_error("Root signing failed: null pointer argument");
        return -1;
    }
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => {
            set_last_error("Root signing failed: seed unavailable");
            return -2;
        }
    };
    let mut message = [0u8; 32];
    message.copy_from_slice(std::slice::from_raw_parts(message_ptr, 32));
    match sign_root_digest32(&seed, &message) {
        Ok(signature) => {
            std::ptr::copy_nonoverlapping(signature.as_ptr(), signature_out, 64);
            0
        }
        Err(error) => {
            set_last_error(error);
            -3
        }
    }
}

#[cfg(test)]
mod root_signing_tests {
    use super::*;

    #[test]
    fn root_digest_signature_verifies_against_derived_root() {
        let seed = Seed([37u8; 32]);
        let message = [91u8; 32];
        let signature = sign_root_digest32(&seed, &message).expect("signature");
        let pubkey = derive_root_public_key(&seed).expect("root pubkey");
        Ed25519CryptoProvider::new()
            .verify(&message, &pubkey, &signature)
            .expect("valid root signature");
    }
}

/// End-to-end self-check for the current delivery prepared-send path.
///
/// The current implementation still exercises the Nostr adapter, but the
/// purpose of this check is delivery-path validation rather than transport
/// naming exposure in higher layers.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_nostr_send_prepared_self_check() -> i32 {
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -1,
    };

    let privkey = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };

    let transport = match NostrTransport::new(NostrConfig::default(), &privkey) {
        Ok(transport) => transport,
        Err(_) => return -3,
    };

    let signing_secret = match SecretKey::from_slice(&privkey) {
        Ok(secret) => secret,
        Err(_) => return -4,
    };
    let keys = Keys::new(signing_secret);

    let message = Message {
        from: transport.public_key_bytes(),
        to: transport.public_key_bytes(),
        kind: 1,
        payload: vec![1, 2, 3],
        timestamp: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0),
        invitation_id: None,
        domain_event: None,
    };

    match transport.prepare_event(&message, |builder| {
        block_on(builder.sign(&keys)).map_err(|_| TransportError::EncodingFailed)
    }) {
        Ok(_) => 0,
        Err(_) => -5,
    }
}
