//! Android app-private seed storage.
//!
//! This is a temporary Android bring-up implementation that mirrors the
//! current keystore API using app-private files. It keeps the active seed in
//! the app sandbox so the Rust FFI can boot correctly on Android.

use crate::{Error, Result, Seed};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

const PACKAGE_NAME: &str = "com.hivra.hivra_app";
const ACTIVE_SEED_ACCOUNT: &str = "active_capsule_seed_account";
const LEGACY_SEED_FILE: &str = "capsule_seed";

/// Stores the capsule seed in Android app-private storage.
pub fn store_seed(seed: &Seed) -> Result<()> {
    let dir = keystore_dir()?;
    fs::create_dir_all(&dir)?;

    let account = seed_account(seed);
    let encoded = encode_hex(seed.as_bytes());
    fs::write(dir.join(&account), encoded)?;
    fs::write(dir.join(ACTIVE_SEED_ACCOUNT), account)?;
    Ok(())
}

/// Loads the capsule seed from Android app-private storage.
pub fn load_seed() -> Result<Seed> {
    let dir = keystore_dir()?;

    if let Ok(account) = fs::read_to_string(dir.join(ACTIVE_SEED_ACCOUNT)) {
        let account = account.trim();
        match load_seed_from_account(account) {
            Ok(seed) => return Ok(seed),
            Err(Error::KeyNotFound) => {}
            Err(other) => return Err(other),
        }
    }

    let legacy_path = dir.join(LEGACY_SEED_FILE);
    let encoded = fs::read_to_string(&legacy_path).map_err(map_io_error)?;
    let seed = Seed::new(decode_hex_32(encoded.trim())?);
    let _ = store_seed(&seed);
    Ok(seed)
}

/// Deletes the capsule seed from Android app-private storage.
pub fn delete_seed() -> Result<()> {
    let dir = keystore_dir()?;

    if let Ok(account) = fs::read_to_string(dir.join(ACTIVE_SEED_ACCOUNT)) {
        let _ = fs::remove_file(dir.join(account.trim()));
    }
    let _ = fs::remove_file(dir.join(ACTIVE_SEED_ACCOUNT));
    let _ = fs::remove_file(dir.join(LEGACY_SEED_FILE));
    Ok(())
}

/// Returns `true` if a seed entry exists in Android app-private storage.
pub fn seed_exists() -> bool {
    load_seed().is_ok()
}

fn load_seed_from_account(account: &str) -> Result<Seed> {
    let encoded = fs::read_to_string(keystore_dir()?.join(account)).map_err(map_io_error)?;
    Ok(Seed::new(decode_hex_32(encoded.trim())?))
}

fn keystore_dir() -> Result<PathBuf> {
    let candidates = [
        format!("/data/user/0/{PACKAGE_NAME}/files/hivra-keystore"),
        format!("/data/data/{PACKAGE_NAME}/files/hivra-keystore"),
    ];

    for candidate in candidates {
        let path = PathBuf::from(candidate);
        if path.exists() || parent_exists(&path) {
            return Ok(path);
        }
    }

    Err(Error::PlatformError(
        "Android app-private files directory not available".to_string(),
    ))
}

fn parent_exists(path: &Path) -> bool {
    path.parent().is_some_and(Path::exists)
}

fn seed_account(seed: &Seed) -> String {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update(b"hivra_capsule_seed_account_v1");
    let hash = hasher.finalize();
    format!("capsule_seed:{}", encode_hex(hash.as_slice()))
}

fn map_io_error(err: std::io::Error) -> Error {
    match err.kind() {
        std::io::ErrorKind::NotFound => Error::KeyNotFound,
        _ => Error::IoError(err),
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
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in storage".to_string()))?;
        let lo = from_hex_nibble(bytes[i * 2 + 1])
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in storage".to_string()))?;
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
