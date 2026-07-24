//! Event types for Hivra Core

use crate::{PubKey, Signature, Timestamp};
use alloc::vec::Vec;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Protocol version
pub const PROTOCOL_VERSION: u8 = 4;
pub const CONTINUOUS_LEDGER_PROTOCOL_VERSION: u8 = 5;

const V5_DOMAIN_EVENT_TAG: &[u8] = b"hivra/domain-event/v5";

/// Kind of event
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum EventKind {
    CapsuleCreated = 0,
    InvitationSent = 1,
    InvitationAccepted = 2,
    InvitationRejected = 3,
    InvitationExpired = 4,
    StarterCreated = 5,
    StarterBurned = 6,
    RelationshipEstablished = 7,
    RelationshipBroken = 8,
    InvitationReceived = 9,
}

/// A signed event
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Event {
    version: u8,
    kind: EventKind,
    payload: Vec<u8>,
    timestamp: Timestamp,
    signature: Signature,
    signer: PubKey,
}

impl Event {
    pub fn new(
        kind: EventKind,
        payload: Vec<u8>,
        timestamp: Timestamp,
        signature: Signature,
        signer: PubKey,
    ) -> Self {
        Self {
            version: PROTOCOL_VERSION,
            kind,
            payload,
            timestamp,
            signature,
            signer,
        }
    }

    /// Constructs a protocol-v5 event. The existing `Event` remains the sole
    /// domain-event representation across the v4/v5 migration boundary.
    pub fn new_v5(
        kind: EventKind,
        payload: Vec<u8>,
        timestamp: Timestamp,
        signature: Signature,
        signer: PubKey,
    ) -> Self {
        Self {
            version: CONTINUOUS_LEDGER_PROTOCOL_VERSION,
            kind,
            payload,
            timestamp,
            signature,
            signer,
        }
    }

    pub fn version(&self) -> u8 {
        self.version
    }
    pub fn kind(&self) -> EventKind {
        self.kind
    }
    pub fn payload(&self) -> &[u8] {
        &self.payload
    }
    pub fn timestamp(&self) -> Timestamp {
        self.timestamp
    }
    pub fn signature(&self) -> &Signature {
        &self.signature
    }
    pub fn signer(&self) -> &PubKey {
        &self.signer
    }

    /// Deterministic event ID from protocol fields.
    ///
    /// Protocol-v4 formula:
    /// SHA256(version || kind || payload_bytes)
    ///
    /// Protocol-v5 formula binds timestamp and signer as immutable signed
    /// provenance fields. Ledger-entry sequence is committed separately.
    pub fn event_id(&self) -> [u8; 32] {
        let mut hasher = Sha256::new();
        match self.version {
            PROTOCOL_VERSION => {
                hasher.update([self.version]);
                hasher.update([self.kind as u8]);
                hasher.update(&self.payload);
            }
            CONTINUOUS_LEDGER_PROTOCOL_VERSION => {
                hasher.update(V5_DOMAIN_EVENT_TAG);
                hasher.update([self.version]);
                hasher.update([self.kind as u8]);
                hasher.update((self.payload.len() as u64).to_be_bytes());
                hasher.update(&self.payload);
                hasher.update(self.timestamp.as_u64().to_be_bytes());
                hasher.update(self.signer.as_bytes());
            }
            _ => {
                hasher.update([self.version]);
                hasher.update([self.kind as u8]);
                hasher.update(&self.payload);
                hasher.update(self.timestamp.as_u64().to_be_bytes());
                hasher.update(self.signer.as_bytes());
            }
        }
        let digest = hasher.finalize();

        let mut out = [0u8; 32];
        out.copy_from_slice(&digest);
        out
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    #[test]
    fn test_event_id_deterministic() {
        let event = Event::new(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(123),
            Signature::from([9u8; 64]),
            PubKey::from([7u8; 32]),
        );

        let id1 = event.event_id();
        let id2 = event.event_id();
        assert_eq!(id1, id2);
    }

    #[test]
    fn test_event_id_ignores_timestamp_signature_and_signer() {
        let event_a = Event::new(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(100),
            Signature::from([1u8; 64]),
            PubKey::from([2u8; 32]),
        );
        let event_b = Event::new(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(200),
            Signature::from([3u8; 64]),
            PubKey::from([4u8; 32]),
        );

        assert_eq!(event_a.event_id(), event_b.event_id());
    }

    #[test]
    fn v5_event_id_binds_timestamp_and_signer() {
        let event_a = Event::new_v5(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(100),
            Signature::from([1u8; 64]),
            PubKey::from([2u8; 32]),
        );
        let event_b = Event::new_v5(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(101),
            Signature::from([1u8; 64]),
            PubKey::from([2u8; 32]),
        );
        let event_c = Event::new_v5(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(100),
            Signature::from([1u8; 64]),
            PubKey::from([3u8; 32]),
        );

        assert_ne!(event_a.event_id(), event_b.event_id());
        assert_ne!(event_a.event_id(), event_c.event_id());
    }
}
