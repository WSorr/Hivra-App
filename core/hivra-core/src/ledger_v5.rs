//! Cryptographically continuous ledger primitives for protocol v5.
//!
//! `Event` remains the single domain-fact representation. These types contain
//! only the v5 local-history commitments that attest to those events.

use crate::{Event, PubKey, Signature};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const LEDGER_PROTOCOL_VERSION_V5: u8 = 5;
pub const COMMITMENT_LENGTH: usize = 32;
pub const ZERO_COMMITMENT: [u8; COMMITMENT_LENGTH] = [0; COMMITMENT_LENGTH];

const FRESH_ANCHOR_TAG: &[u8] = b"hivra/ledger-anchor/v5";
const LEGACY_ANCHOR_TAG: &[u8] = b"hivra/legacy-v4-anchor/v5";
const LEGACY_SNAPSHOT_TAG: &[u8] = b"hivra/legacy-v4-snapshot/v1";
const LEDGER_ENTRY_TAG: &[u8] = b"hivra/ledger-entry/v5";

pub type Commitment = [u8; COMMITMENT_LENGTH];

/// The commitment before the first v5 entry. A legacy anchor binds future v5
/// history to one exact v4 snapshot without pretending that v4 was continuous.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum LedgerAnchorV5 {
    Fresh {
        owner: PubKey,
    },
    LegacyV4 {
        owner: PubKey,
        snapshot: Commitment,
        signature: Signature,
    },
}

impl LedgerAnchorV5 {
    pub fn fresh(owner: PubKey) -> Self {
        Self::Fresh { owner }
    }

    pub fn legacy_snapshot_commitment(canonical_v4_ledger_bytes: &[u8]) -> Commitment {
        let mut hasher = Sha256::new();
        hasher.update(LEGACY_SNAPSHOT_TAG);
        hasher.update((canonical_v4_ledger_bytes.len() as u64).to_be_bytes());
        hasher.update(canonical_v4_ledger_bytes);
        digest_into_array(hasher)
    }

    pub fn legacy(owner: PubKey, snapshot: Commitment, signature: Signature) -> Self {
        Self::LegacyV4 {
            owner,
            snapshot,
            signature,
        }
    }

    pub fn owner(&self) -> &PubKey {
        match self {
            Self::Fresh { owner } | Self::LegacyV4 { owner, .. } => owner,
        }
    }

    pub fn signature(&self) -> Option<&Signature> {
        match self {
            Self::Fresh { .. } => None,
            Self::LegacyV4 { signature, .. } => Some(signature),
        }
    }

    pub fn commitment(&self) -> Commitment {
        let mut hasher = Sha256::new();
        match self {
            Self::Fresh { owner } => {
                hasher.update(FRESH_ANCHOR_TAG);
                hasher.update(owner.as_bytes());
            }
            Self::LegacyV4 {
                owner, snapshot, ..
            } => {
                hasher.update(LEGACY_ANCHOR_TAG);
                hasher.update(owner.as_bytes());
                hasher.update(snapshot);
            }
        }
        digest_into_array(hasher)
    }
}

/// A root-signed local acceptance of one immutable domain event at one exact
/// position in the owner's history.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LedgerEntryV5 {
    owner: PubKey,
    sequence: u64,
    previous_commitment: Commitment,
    event: Event,
    signature: Signature,
}

impl LedgerEntryV5 {
    pub fn unsigned(
        owner: PubKey,
        sequence: u64,
        previous_commitment: Commitment,
        event: Event,
    ) -> Self {
        Self {
            owner,
            sequence,
            previous_commitment,
            event,
            signature: Signature::from([0; 64]),
        }
    }

    pub fn with_signature(mut self, signature: Signature) -> Self {
        self.signature = signature;
        self
    }

    pub fn owner(&self) -> &PubKey {
        &self.owner
    }

    pub fn sequence(&self) -> u64 {
        self.sequence
    }

    pub fn previous_commitment(&self) -> &Commitment {
        &self.previous_commitment
    }

    pub fn event(&self) -> &Event {
        &self.event
    }

    pub fn signature(&self) -> &Signature {
        &self.signature
    }

    pub fn commitment(&self) -> Commitment {
        let mut hasher = Sha256::new();
        hasher.update(LEDGER_ENTRY_TAG);
        hasher.update(self.owner.as_bytes());
        hasher.update(self.sequence.to_be_bytes());
        hasher.update(self.previous_commitment);
        hasher.update(self.event.event_id());
        digest_into_array(hasher)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedgerV5Error {
    NotContinuousLedger,
    AnchorOwnerMismatch,
    EntryOwnerMismatch,
    InvalidSequence,
    InvalidPreviousCommitment,
    DuplicateDomainEvent,
    WrongEventVersion,
}

fn digest_into_array(hasher: Sha256) -> Commitment {
    let digest = hasher.finalize();
    let mut result = [0; COMMITMENT_LENGTH];
    result.copy_from_slice(&digest);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{EventKind, Timestamp};
    use alloc::{vec, vec::Vec};

    fn owner() -> PubKey {
        PubKey::from([7; 32])
    }

    fn event(payload: Vec<u8>) -> Event {
        Event::new_v5(
            EventKind::InvitationSent,
            payload,
            Timestamp::from(123),
            Signature::from([9; 64]),
            PubKey::from([9; 32]),
        )
    }

    #[test]
    fn domain_event_commitment_binds_all_order_critical_fields() {
        let base = event(vec![1, 2, 3]);
        let different_time = Event::new_v5(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(124),
            Signature::from([9; 64]),
            PubKey::from([9; 32]),
        );
        let different_signer = Event::new_v5(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(123),
            Signature::from([9; 64]),
            PubKey::from([10; 32]),
        );

        assert_ne!(base.event_id(), different_time.event_id());
        assert_ne!(base.event_id(), different_signer.event_id());
    }

    #[test]
    fn v5_legacy_anchor_binds_exact_v4_snapshot() {
        let first = LedgerAnchorV5::legacy_snapshot_commitment(b"legacy-v4-a");
        let second = LedgerAnchorV5::legacy_snapshot_commitment(b"legacy-v4-b");
        assert_ne!(first, second);

        let anchor = LedgerAnchorV5::legacy(owner(), first, Signature::from([3; 64]));
        assert_eq!(anchor.owner(), &owner());
    }

    #[test]
    fn v5_golden_commitment_vectors_are_stable() {
        let domain = event(vec![1, 2, 3]);
        let anchor = LedgerAnchorV5::fresh(owner());
        let entry = LedgerEntryV5::unsigned(owner(), 0, anchor.commitment(), domain.clone());

        assert_eq!(
            hex::encode(domain.event_id()),
            "bf20db840e7c899af034f53fca87e9a322250f1dacdbfdb899842faa42c33bb7"
        );
        assert_eq!(
            hex::encode(anchor.commitment()),
            "3cea9e3bc40327ddea2cbc3870c6a0ea8fa823399eb17065877700524715894d"
        );
        assert_eq!(
            hex::encode(entry.commitment()),
            "a2bda1a0df0d45d97b82558827b8d450d2508c7be455ebcd66b1e77e2d243d72"
        );
    }
}
