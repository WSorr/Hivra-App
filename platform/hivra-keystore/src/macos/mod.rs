//! macOS Keychain implementation.

use crate::{Error, Result, Seed};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

const KEYCHAIN_SERVICE: &str = "com.hivra.keystore";
const LEGACY_KEYCHAIN_ACCOUNT: &str = "capsule_seed";
const ACTIVE_SEED_ACCOUNT: &str = "active_capsule_seed_account";

static ACTIVE_SEED_CACHE: OnceLock<Mutex<Option<Seed>>> = OnceLock::new();
static PERSISTED_SEED_ACCOUNT_CACHE: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

fn active_seed_cache() -> &'static Mutex<Option<Seed>> {
    ACTIVE_SEED_CACHE.get_or_init(|| Mutex::new(None))
}

fn persisted_seed_account_cache() -> &'static Mutex<HashSet<String>> {
    PERSISTED_SEED_ACCOUNT_CACHE.get_or_init(|| Mutex::new(HashSet::new()))
}

fn entry_for_account(account: &str) -> Result<keyring::Entry> {
    keyring::Entry::new(KEYCHAIN_SERVICE, account).map_err(|e| Error::PlatformError(e.to_string()))
}

/// Stores the capsule seed in the macOS Keychain.
pub fn store_seed(seed: &Seed) -> Result<()> {
    let encoded = encode_hex(seed.as_bytes());
    let seed_account = seed_account(seed);
    cache_active_seed(seed)?;

    if is_persisted_seed_account_cached(&seed_account)? {
        return Ok(());
    }

    match entry_for_account(&seed_account)?.get_password() {
        Ok(existing) if existing == encoded => {
            cache_persisted_seed_account(seed_account)?;
            Ok(())
        }
        Ok(_) | Err(keyring::Error::NoEntry) => {
            entry_for_account(&seed_account)?
                .set_password(&encoded)
                .map_err(|e| Error::PlatformError(e.to_string()))?;
            cache_persisted_seed_account(seed_account)
        }
        Err(err) => Err(Error::PlatformError(err.to_string())),
    }
}

/// Loads the capsule seed from the macOS Keychain.
pub fn load_seed() -> Result<Seed> {
    if let Some(seed) = active_seed_cache()
        .lock()
        .map_err(|_| Error::PlatformError("active seed cache poisoned".to_string()))?
        .clone()
    {
        return Ok(seed);
    }

    if let Ok(account) = active_seed_account() {
        match load_seed_from_account(&account) {
            Ok(seed) => {
                cache_active_seed(&seed)?;
                cache_persisted_seed_account(account)?;
                return Ok(seed);
            }
            Err(Error::KeyNotFound) => {}
            Err(other) => return Err(other),
        }
    }

    // Backward-compatibility for old single-account storage.
    let encoded = entry_for_account(LEGACY_KEYCHAIN_ACCOUNT)?
        .get_password()
        .map_err(map_get_error)?;
    let bytes = decode_hex_32(&encoded)?;
    let seed = Seed::new(bytes);
    cache_active_seed(&seed)?;
    // Best-effort migration to namespaced account model.
    let _ = store_seed(&seed);
    Ok(seed)
}

/// Deletes the capsule seed from the macOS Keychain.
pub fn delete_seed() -> Result<()> {
    if let Ok(mut cached) = active_seed_cache().lock() {
        *cached = None;
    }
    if let Ok(mut cached) = persisted_seed_account_cache().lock() {
        cached.clear();
    }
    if let Ok(account) = active_seed_account() {
        delete_account_credential(&account)?;
    }
    delete_account_credential(ACTIVE_SEED_ACCOUNT)?;
    delete_account_credential(LEGACY_KEYCHAIN_ACCOUNT)?;
    Ok(())
}

fn cache_active_seed(seed: &Seed) -> Result<()> {
    let mut cached = active_seed_cache()
        .lock()
        .map_err(|_| Error::PlatformError("active seed cache poisoned".to_string()))?;
    *cached = Some(seed.clone());
    Ok(())
}

fn is_persisted_seed_account_cached(account: &str) -> Result<bool> {
    let cached = persisted_seed_account_cache()
        .lock()
        .map_err(|_| Error::PlatformError("persisted seed account cache poisoned".to_string()))?;
    Ok(cached.contains(account))
}

fn cache_persisted_seed_account(account: String) -> Result<()> {
    let mut cached = persisted_seed_account_cache()
        .lock()
        .map_err(|_| Error::PlatformError("persisted seed account cache poisoned".to_string()))?;
    cached.insert(account);
    Ok(())
}

/// Returns `true` if a seed entry exists in the macOS Keychain.
pub fn seed_exists() -> bool {
    if active_seed_cache()
        .lock()
        .ok()
        .and_then(|cached| cached.clone())
        .is_some()
    {
        return true;
    }

    if let Ok(account) = active_seed_account() {
        if load_seed_from_account(&account).is_ok() {
            return true;
        }
    }
    entry_for_account(LEGACY_KEYCHAIN_ACCOUNT)
        .and_then(|e| e.get_password().map_err(map_get_error))
        .is_ok()
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
    match entry_for_account(account)?
        .delete_credential()
        .map_err(map_get_error)
    {
        Ok(()) | Err(Error::KeyNotFound) => Ok(()),
        Err(other) => Err(other),
    }
}

fn seed_account(seed: &Seed) -> String {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update(b"hivra_capsule_seed_account_v1");
    let hash = hasher.finalize();
    format!("capsule_seed:{}", encode_hex(hash.as_slice()))
}

fn map_get_error(err: keyring::Error) -> Error {
    match err {
        keyring::Error::NoEntry => Error::KeyNotFound,
        other => Error::PlatformError(other.to_string()),
    }
}

fn encode_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
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
