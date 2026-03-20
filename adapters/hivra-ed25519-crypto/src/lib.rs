//! ed25519 implementation of Hivra Engine `CryptoProvider`.

use ed25519_dalek::{Signature as Ed25519Signature, Signer, SigningKey, Verifier, VerifyingKey};
use hivra_engine::CryptoProvider;

/// Errors returned by `Ed25519CryptoProvider`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Ed25519CryptoError {
    InvalidPublicKey,
    InvalidSignature,
    InvalidSecretKey,
    VerifyFailed,
    EcdhUnsupported,
}

/// Crypto provider for canonical root signing over ed25519.
pub struct Ed25519CryptoProvider;

impl Ed25519CryptoProvider {
    /// Creates a new provider instance.
    pub fn new() -> Self {
        Self
    }
}

impl Default for Ed25519CryptoProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl CryptoProvider for Ed25519CryptoProvider {
    type Error = Ed25519CryptoError;

    fn verify(&self, msg: &[u8], pubkey: &[u8; 32], sig: &[u8; 64]) -> Result<(), Self::Error> {
        let verifying_key =
            VerifyingKey::from_bytes(pubkey).map_err(|_| Ed25519CryptoError::InvalidPublicKey)?;
        let signature = Ed25519Signature::from_bytes(sig);
        verifying_key
            .verify(msg, &signature)
            .map_err(|_| Ed25519CryptoError::VerifyFailed)
    }

    fn sign(&self, msg: &[u8], privkey: &[u8; 32]) -> Result<[u8; 64], Self::Error> {
        let signing_key = SigningKey::from_bytes(privkey);
        let signature = signing_key.sign(msg);
        Ok(signature.to_bytes())
    }

    fn ecdh(&self, _privkey: &[u8; 32], _pubkey: &[u8; 32]) -> Result<[u8; 32], Self::Error> {
        Err(Ed25519CryptoError::EcdhUnsupported)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_and_verify_roundtrip() {
        let provider = Ed25519CryptoProvider::new();
        let privkey = [7u8; 32];
        let signing_key = SigningKey::from_bytes(&privkey);
        let pubkey = signing_key.verifying_key().to_bytes();
        let message = [9u8; 32];

        let signature = provider.sign(&message, &privkey).expect("signature");
        provider
            .verify(&message, &pubkey, &signature)
            .expect("verification succeeds");
    }

    #[test]
    fn ecdh_is_not_supported() {
        let provider = Ed25519CryptoProvider::new();
        let err = provider
            .ecdh(&[1u8; 32], &[2u8; 32])
            .expect_err("must be unsupported");
        assert_eq!(err, Ed25519CryptoError::EcdhUnsupported);
    }
}
