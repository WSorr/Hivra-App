//! Hivra Keystore
//! Platform-specific secure storage for cryptographic keys.

#![warn(missing_docs)]

use std::fmt;
use std::path::{Path, PathBuf};
use zeroize::Zeroize;

const QUARANTINE_RECORD_KEY_LABEL: &[u8] = b"HIVRA_INBOUND_QUARANTINE_RECORD_KEY_v1";
const QUARANTINE_SNAPSHOT_KEY_LABEL: &[u8] = b"HIVRA_INBOUND_QUARANTINE_SNAPSHOT_KEY_v1";
const SEALED_PAYLOAD_VERSION: u8 = 1;
const AES_GCM_NONCE_LEN: usize = 12;

/// Errors that can occur in keystore operations
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Platform-specific keychain error
    #[error("Platform keystore error: {0}")]
    PlatformError(String),
    /// Key not found in keystore
    #[error("Key not found")]
    KeyNotFound,
    /// Invalid seed length
    #[error("Invalid seed length: {0}, expected 32")]
    InvalidSeedLength(usize),
    /// BIP39 mnemonic error
    #[error("BIP39 error: {0}")]
    Bip39Error(String),
    /// Signature error
    #[error("Signature error: {0}")]
    SignatureError(String),
    /// I/O error
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
}

/// Result type for keystore operations
pub type Result<T> = std::result::Result<T, Error>;

/// A 32-byte seed for deterministic key generation
#[derive(Clone, Zeroize)]
#[zeroize(drop)]
pub struct Seed(pub [u8; 32]);

impl Seed {
    /// Create a new seed from bytes
    pub fn new(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }
    /// Get seed as bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for Seed {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Seed")
            .field("bytes", &"[redacted]")
            .finish()
    }
}

/// Convert seed to BIP39 mnemonic phrase
pub fn seed_to_mnemonic(seed: &Seed, word_count: usize) -> Result<String> {
    use bip39::{Language, Mnemonic};
    let entropy = match word_count {
        12 => &seed.0[..16],
        24 => &seed.0[..32],
        _ => return Err(Error::Bip39Error("Word count must be 12 or 24".to_string())),
    };
    let mnemonic = Mnemonic::from_entropy_in(Language::English, entropy)
        .map_err(|e| Error::Bip39Error(e.to_string()))?;
    Ok(mnemonic.to_string())
}

/// Convert BIP39 mnemonic phrase to seed
pub fn mnemonic_to_seed(phrase: &str) -> Result<Seed> {
    use bip39::{Language, Mnemonic};
    let mnemonic = Mnemonic::parse_in(Language::English, phrase)
        .map_err(|e| Error::Bip39Error(e.to_string()))?;
    let entropy = mnemonic.to_entropy();
    let mut seed_bytes = [0u8; 32];
    let len = entropy.len().min(32);
    seed_bytes[..len].copy_from_slice(&entropy);
    Ok(Seed(seed_bytes))
}

/// Derive Nostr keypair from seed using HKDF
pub fn derive_nostr_keypair(seed: &Seed) -> Result<[u8; 32]> {
    derive_key_with_label(seed, b"HIVRA_NOSTR_KEY_v1")
}

/// Derive canonical root signing key from seed using HKDF.
pub fn derive_root_keypair(seed: &Seed) -> Result<[u8; 32]> {
    derive_key_with_label(seed, b"HIVRA_ROOT_IDENTITY_v1")
}

/// Derive canonical root public key from seed.
pub fn derive_root_public_key(seed: &Seed) -> Result<[u8; 32]> {
    let signing_bytes = derive_root_keypair(seed)?;
    let signing_key = ed25519_dalek::SigningKey::from_bytes(&signing_bytes);
    Ok(signing_key.verifying_key().to_bytes())
}

/// Authenticated-encrypts one inbound quarantine envelope with a key role
/// distinct from root signing, transport signing, and transport encryption.
pub fn seal_inbound_quarantine_record(
    seed: &Seed,
    associated_data: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>> {
    seal_with_label(
        seed,
        QUARANTINE_RECORD_KEY_LABEL,
        associated_data,
        plaintext,
    )
}

/// Authenticated-decrypts one inbound quarantine envelope.
pub fn open_inbound_quarantine_record(
    seed: &Seed,
    associated_data: &[u8],
    sealed: &[u8],
) -> Result<Vec<u8>> {
    open_with_label(seed, QUARANTINE_RECORD_KEY_LABEL, associated_data, sealed)
}

/// Authenticated-encrypts the complete quarantine snapshot and index.
pub fn seal_inbound_quarantine_snapshot(
    seed: &Seed,
    associated_data: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>> {
    seal_with_label(
        seed,
        QUARANTINE_SNAPSHOT_KEY_LABEL,
        associated_data,
        plaintext,
    )
}

/// Authenticated-decrypts the complete quarantine snapshot and index.
pub fn open_inbound_quarantine_snapshot(
    seed: &Seed,
    associated_data: &[u8],
    sealed: &[u8],
) -> Result<Vec<u8>> {
    open_with_label(seed, QUARANTINE_SNAPSHOT_KEY_LABEL, associated_data, sealed)
}

fn seal_with_label(
    seed: &Seed,
    label: &[u8],
    associated_data: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>> {
    use aes_gcm::aead::{Aead, Payload};
    use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
    use rand::RngCore;

    let mut key = derive_key_with_label(seed, label)?;
    let cipher = Aes256Gcm::new_from_slice(&key)
        .map_err(|_| Error::PlatformError("Invalid quarantine storage key".to_string()))?;
    let mut nonce_bytes = [0u8; AES_GCM_NONCE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce_bytes),
            Payload {
                msg: plaintext,
                aad: associated_data,
            },
        )
        .map_err(|_| Error::PlatformError("Quarantine encryption failed".to_string()))?;
    key.zeroize();

    let mut sealed = Vec::with_capacity(1 + nonce_bytes.len() + ciphertext.len());
    sealed.push(SEALED_PAYLOAD_VERSION);
    sealed.extend_from_slice(&nonce_bytes);
    sealed.extend_from_slice(&ciphertext);
    Ok(sealed)
}

fn open_with_label(
    seed: &Seed,
    label: &[u8],
    associated_data: &[u8],
    sealed: &[u8],
) -> Result<Vec<u8>> {
    use aes_gcm::aead::{Aead, Payload};
    use aes_gcm::{Aes256Gcm, KeyInit, Nonce};

    if sealed.len() <= 1 + AES_GCM_NONCE_LEN || sealed[0] != SEALED_PAYLOAD_VERSION {
        return Err(Error::PlatformError(
            "Unsupported quarantine ciphertext framing".to_string(),
        ));
    }
    let mut key = derive_key_with_label(seed, label)?;
    let cipher = Aes256Gcm::new_from_slice(&key)
        .map_err(|_| Error::PlatformError("Invalid quarantine storage key".to_string()))?;
    let nonce = Nonce::from_slice(&sealed[1..1 + AES_GCM_NONCE_LEN]);
    let result = cipher
        .decrypt(
            nonce,
            Payload {
                msg: &sealed[1 + AES_GCM_NONCE_LEN..],
                aad: associated_data,
            },
        )
        .map_err(|_| Error::PlatformError("Quarantine authentication failed".to_string()));
    key.zeroize();
    result
}

fn derive_key_with_label(seed: &Seed, info: &[u8]) -> Result<[u8; 32]> {
    use hkdf::Hkdf;
    use sha2::Sha256;
    let hk = Hkdf::<Sha256>::new(None, seed.as_bytes());
    let mut okm = [0u8; 32];
    hk.expand(info, &mut okm)
        .map_err(|_| Error::Bip39Error("HKDF expansion failed".to_string()))?;
    Ok(okm)
}

fn android_keystore_dir(files_dir: &Path) -> Result<PathBuf> {
    if !files_dir.is_absolute() {
        return Err(Error::PlatformError(
            "Android app-private files directory must be absolute".to_string(),
        ));
    }
    Ok(files_dir.join("hivra-keystore"))
}

#[cfg(target_os = "macos")]
pub mod macos;

// Re-export platform functions at the crate root for convenience
#[cfg(target_os = "macos")]
pub use macos::{delete_seed, load_seed, seed_exists, store_seed};

#[cfg(target_os = "android")]
pub mod android;

#[cfg(target_os = "android")]
pub use android::{delete_seed, load_seed, seed_exists, store_seed};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_identity_derivation_is_deterministic() {
        let seed = Seed([7u8; 32]);
        assert_eq!(
            derive_root_keypair(&seed).unwrap(),
            derive_root_keypair(&seed).unwrap()
        );
        assert_eq!(
            derive_root_public_key(&seed).unwrap(),
            derive_root_public_key(&seed).unwrap()
        );
    }

    #[test]
    fn root_and_nostr_derivation_are_domain_separated() {
        let seed = Seed([9u8; 32]);
        assert_ne!(
            derive_root_keypair(&seed).unwrap(),
            derive_nostr_keypair(&seed).unwrap()
        );
        assert_ne!(
            derive_root_public_key(&seed).unwrap(),
            derive_nostr_keypair(&seed).unwrap()
        );
    }

    #[test]
    fn quarantine_storage_roles_are_authenticated_and_domain_separated() {
        let seed = Seed([0x42; 32]);
        let aad = b"capsule:neste:nostr";
        let plaintext = b"authenticated envelope";
        let record = seal_inbound_quarantine_record(&seed, aad, plaintext).unwrap();
        let snapshot = seal_inbound_quarantine_snapshot(&seed, aad, plaintext).unwrap();

        assert_ne!(record, snapshot);
        assert_eq!(
            open_inbound_quarantine_record(&seed, aad, &record).unwrap(),
            plaintext
        );
        assert!(open_inbound_quarantine_record(&seed, b"wrong", &record).is_err());
        assert!(open_inbound_quarantine_snapshot(&seed, aad, &record).is_err());
    }

    #[test]
    fn android_keystore_directory_follows_the_runtime_user_files_directory() {
        assert_eq!(
            android_keystore_dir(Path::new("/data/user/11/com.hivra.hivra_app/files",)).unwrap(),
            PathBuf::from("/data/user/11/com.hivra.hivra_app/files/hivra-keystore"),
        );
        assert!(android_keystore_dir(Path::new("relative/files")).is_err());
    }
}
