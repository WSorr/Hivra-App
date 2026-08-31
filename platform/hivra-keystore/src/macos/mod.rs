//! macOS Keychain implementation.

use crate::{Error, Result, Seed};
use sha2::{Digest, Sha256};
use std::sync::{Mutex, OnceLock};

const KEYCHAIN_SERVICE: &str = "com.hivra.keystore";
const LEGACY_KEYCHAIN_ACCOUNT: &str = "capsule_seed";
const ACTIVE_SEED_ACCOUNT: &str = "active_capsule_seed_account";

static ACTIVE_SEED_CACHE: OnceLock<Mutex<Option<Seed>>> = OnceLock::new();

fn active_seed_cache() -> &'static Mutex<Option<Seed>> {
    ACTIVE_SEED_CACHE.get_or_init(|| Mutex::new(None))
}

fn entry_for_account(account: &str) -> Result<keyring::Entry> {
    keyring::Entry::new(KEYCHAIN_SERVICE, account).map_err(|e| Error::PlatformError(e.to_string()))
}

/// Activates the capsule seed in process-local memory.
///
/// Per-capsule persistence is owned by Flutter secure storage. Keeping a
/// second writable copy here would create two authorities for the same secret
/// and make every ad-hoc development build negotiate a separate Keychain ACL.
pub fn store_seed(seed: &Seed) -> Result<()> {
    cache_active_seed(seed)
}

/// Loads the active seed from memory or from the legacy native Keychain layout.
pub fn load_seed() -> Result<Seed> {
    if let Some(seed) = active_seed_cache()
        .lock()
        .map_err(|_| Error::PlatformError("active seed cache poisoned".to_string()))?
        .clone()
    {
        return Ok(seed);
    }

    match active_seed_account() {
        Ok(account) => {
            if !is_seed_account(&account) {
                return Err(Error::PlatformError(
                    "macOS Keychain active seed account is malformed".to_string(),
                ));
            }
            match load_seed_from_account(&account) {
                Ok(seed) => {
                    cache_active_seed(&seed)?;
                    return Ok(seed);
                }
                Err(Error::KeyNotFound) => {}
                Err(other) => return Err(other),
            }
        }
        Err(Error::KeyNotFound) => {}
        Err(other) => return Err(other),
    }

    // Backward-compatibility for old single-account storage.
    let encoded = entry_for_account(LEGACY_KEYCHAIN_ACCOUNT)?
        .get_password()
        .map_err(map_get_error)?;
    let bytes = decode_hex_32(&encoded)?;
    let seed = Seed::new(bytes);
    cache_active_seed(&seed)?;
    Ok(seed)
}

/// Deletes the capsule seed from the macOS Keychain.
pub fn delete_seed() -> Result<()> {
    match active_seed_account() {
        Ok(account) => {
            if !is_seed_account(&account) {
                return Err(Error::PlatformError(
                    "macOS Keychain active seed account is malformed".to_string(),
                ));
            }
            delete_account_credential(&account)?;
        }
        Err(Error::KeyNotFound) => {}
        Err(other) => return Err(other),
    }
    delete_account_credential(ACTIVE_SEED_ACCOUNT)?;
    delete_account_credential(LEGACY_KEYCHAIN_ACCOUNT)?;
    let mut cached = active_seed_cache()
        .lock()
        .map_err(|_| Error::PlatformError("active seed cache poisoned".to_string()))?;
    *cached = None;
    Ok(())
}

/// Deletes the legacy namespaced Keychain credential for one exact seed.
pub fn delete_seed_for(seed: &Seed) -> Result<()> {
    delete_account_credential(&seed_account(seed))
}

fn cache_active_seed(seed: &Seed) -> Result<()> {
    let mut cached = active_seed_cache()
        .lock()
        .map_err(|_| Error::PlatformError("active seed cache poisoned".to_string()))?;
    *cached = Some(seed.clone());
    Ok(())
}

/// Returns `true` if a runtime seed is active or a legacy seed can be loaded.
/// A successful legacy read populates the runtime cache, so a following load
/// does not request Keychain access for the same records again.
pub fn seed_exists() -> bool {
    load_seed().is_ok()
}

fn active_seed_account() -> Result<String> {
    entry_for_account(ACTIVE_SEED_ACCOUNT)?
        .get_password()
        .map_err(map_get_error)
}

fn load_seed_from_account(account: &str) -> Result<Seed> {
    let encoded = entry_for_account(account)?
        .get_password()
        .map_err(map_get_error)?;
    let bytes = decode_hex_32(&encoded)?;
    Ok(Seed::new(bytes))
}

fn delete_account_credential(account: &str) -> Result<()> {
    let entry = entry_for_account(account)?;
    match entry.delete_credential().map_err(map_get_error) {
        Ok(()) | Err(Error::KeyNotFound) => {}
        Err(other) => return Err(other),
    }
    match entry.get_password().map_err(map_get_error) {
        Err(Error::KeyNotFound) => Ok(()),
        Ok(_) => Err(Error::PlatformError(
            "macOS Keychain credential still exists after deletion".to_string(),
        )),
        Err(other) => Err(other),
    }
}

fn is_seed_account(account: &str) -> bool {
    let Some(digest) = account.strip_prefix("capsule_seed:") else {
        return false;
    };
    digest.len() == 64 && digest.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn seed_account(seed: &Seed) -> String {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update(b"hivra_capsule_seed_account_v1");
    let hash = hasher.finalize();
    format!("capsule_seed:{}", encode_hex(hash.as_slice()))
}

fn encode_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn map_get_error(err: keyring::Error) -> Error {
    match err {
        keyring::Error::NoEntry => Error::KeyNotFound,
        other => Error::PlatformError(other.to_string()),
    }
}

fn decode_hex_32(input: &str) -> Result<[u8; 32]> {
    if input.len() != 64 {
        return Err(Error::InvalidSeedLength(input.len() / 2));
    }

    let mut out = [0u8; 32];
    let bytes = input.as_bytes();
    for i in 0..32 {
        let hi = from_hex_nibble(bytes[i * 2])
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in keychain".to_string()))?;
        let lo = from_hex_nibble(bytes[i * 2 + 1])
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in keychain".to_string()))?;
        out[i] = (hi << 4) | lo;
    }
    Ok(out)
}

fn from_hex_nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn store_seed_activates_without_keychain_round_trip() {
        let seed = Seed::new([0x5a; 32]);
        store_seed(&seed).unwrap();
        assert_eq!(load_seed().unwrap().as_bytes(), seed.as_bytes());
        assert!(seed_exists());
    }

    #[test]
    fn legacy_seed_account_binding_rejects_malformed_values() {
        assert!(is_seed_account(&format!("capsule_seed:{}", "a".repeat(64))));
        assert!(!is_seed_account("capsule_seed"));
        assert!(!is_seed_account(
            "capsule_seed:../active_capsule_seed_account"
        ));
        assert!(!is_seed_account(&format!(
            "capsule_seed:{}",
            "g".repeat(64)
        )));
    }

    #[test]
    fn legacy_seed_account_is_deterministic_and_seed_bound() {
        let first = Seed::new([0x11; 32]);
        let second = Seed::new([0x12; 32]);
        assert_eq!(seed_account(&first), seed_account(&first));
        assert_ne!(seed_account(&first), seed_account(&second));
        assert!(is_seed_account(&seed_account(&first)));
    }
}
