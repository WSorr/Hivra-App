//! Cryptographically continuous ledger primitives for protocol v5.
//!
//! These types are intentionally isolated from the protocol-v4 runtime until
//! Engine/FFI can switch append, import, and persistence as one migration.

use crate::{EventKind, PubKey, Signature, Timestamp};
use alloc::vec::Vec;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const LEDGER_PROTOCOL_VERSION_V5: u8 = 5;
pub const COMMITMENT_LENGTH: usize = 32;
pub const ZERO_COMMITMENT: [u8; COMMITMENT_LENGTH] = [0; COMMITMENT_LENGTH];

const DOMAIN_EVENT_TAG: &[u8] = b"hivra/domain-event/v5";
const FRESH_ANCHOR_TAG: &[u8] = b"hivra/ledger-anchor/v5";
const LEGACY_ANCHOR_TAG: &[u8] = b"hivra/legacy-v4-anchor/v5";
const LEGACY_SNAPSHOT_TAG: &[u8] = b"hivra/legacy-v4-snapshot/v1";
const LEDGER_ENTRY_TAG: &[u8] = b"hivra/ledger-entry/v5";

pub type Commitment = [u8; COMMITMENT_LENGTH];

/// A signed, immutable domain statement. Its timestamp and signer are part of
/// the v5 signature message and must never be changed by a recipient.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DomainEventV5 {
    version: u8,
    kind: EventKind,
    payload: Vec<u8>,
    issued_at: Timestamp,
    signer: PubKey,
    signature: Signature,
}

impl DomainEventV5 {
    pub fn unsigned(
        kind: EventKind,
        payload: Vec<u8>,
        issued_at: Timestamp,
        signer: PubKey,
    ) -> Self {
        Self {
            version: LEDGER_PROTOCOL_VERSION_V5,
            kind,
            payload,
            issued_at,
            signer,
            signature: Signature::from([0; 64]),
        }
    }

    pub fn with_signature(mut self, signature: Signature) -> Self {
        self.signature = signature;
        self
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

    pub fn issued_at(&self) -> Timestamp {
        self.issued_at
    }

    pub fn signer(&self) -> &PubKey {
        &self.signer
    }

    pub fn signature(&self) -> &Signature {
        &self.signature
    }

    pub fn commitment(&self) -> Commitment {
        let mut hasher = Sha256::new();
        hasher.update(DOMAIN_EVENT_TAG);
        hasher.update([self.version]);
        hasher.update([self.kind as u8]);
        hasher.update((self.payload.len() as u64).to_be_bytes());
        hasher.update(&self.payload);
        hasher.update(self.issued_at.as_u64().to_be_bytes());
        hasher.update(self.signer.as_bytes());
        digest_into_array(hasher)
    }
}

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
    event: DomainEventV5,
    signature: Signature,
}

impl LedgerEntryV5 {
    pub fn unsigned(
        owner: PubKey,
        sequence: u64,
        previous_commitment: Commitment,
        event: DomainEventV5,
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

    pub fn event(&self) -> &DomainEventV5 {
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
        hasher.update(self.event.commitment());
        digest_into_array(hasher)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedgerV5Error {
    AnchorOwnerMismatch,
    EntryOwnerMismatch,
    InvalidSequence,
    InvalidPreviousCommitment,
    DuplicateDomainEvent,
    WrongEventVersion,
}

/// Structural ledger model. Cryptographic verification remains an Engine/FFI
/// operation because Core deliberately has no crypto dependency.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LedgerV5 {
    owner: PubKey,
    anchor: LedgerAnchorV5,
    entries: Vec<LedgerEntryV5>,
}

impl LedgerV5 {
    pub fn fresh(owner: PubKey) -> Self {
        Self {
            owner,
            anchor: LedgerAnchorV5::fresh(owner),
            entries: Vec::new(),
        }
    }

    pub fn from_anchor(owner: PubKey, anchor: LedgerAnchorV5) -> Result<Self, LedgerV5Error> {
        if anchor.owner() != &owner {
            return Err(LedgerV5Error::AnchorOwnerMismatch);
        }
        Ok(Self {
            owner,
            anchor,
            entries: Vec::new(),
        })
    }

    pub fn owner(&self) -> &PubKey {
        &self.owner
    }

    pub fn anchor(&self) -> &LedgerAnchorV5 {
        &self.anchor
    }

    pub fn entries(&self) -> &[LedgerEntryV5] {
        &self.entries
    }

    pub fn next_sequence(&self) -> u64 {
        self.entries.len() as u64
    }

    pub fn tail_commitment(&self) -> Commitment {
        self.entries
            .last()
            .map(LedgerEntryV5::commitment)
            .unwrap_or_else(|| self.anchor.commitment())
    }

    pub fn append(&mut self, entry: LedgerEntryV5) -> Result<(), LedgerV5Error> {
        if entry.owner() != &self.owner {
            return Err(LedgerV5Error::EntryOwnerMismatch);
        }
        if entry.event().version() != LEDGER_PROTOCOL_VERSION_V5 {
            return Err(LedgerV5Error::WrongEventVersion);
        }
        if entry.sequence() != self.next_sequence() {
            return Err(LedgerV5Error::InvalidSequence);
        }
        if entry.previous_commitment() != &self.tail_commitment() {
            return Err(LedgerV5Error::InvalidPreviousCommitment);
        }
        if self
            .entries
            .iter()
            .any(|existing| existing.event().commitment() == entry.event().commitment())
        {
            return Err(LedgerV5Error::DuplicateDomainEvent);
        }
        self.entries.push(entry);
        Ok(())
    }

    pub fn verify_structure(&self) -> Result<(), LedgerV5Error> {
        if self.anchor.owner() != &self.owner {
            return Err(LedgerV5Error::AnchorOwnerMismatch);
        }
        let mut previous = self.anchor.commitment();
        for (index, entry) in self.entries.iter().enumerate() {
            if entry.owner() != &self.owner {
                return Err(LedgerV5Error::EntryOwnerMismatch);
            }
            if entry.event().version() != LEDGER_PROTOCOL_VERSION_V5 {
                return Err(LedgerV5Error::WrongEventVersion);
            }
            if entry.sequence() != index as u64 {
                return Err(LedgerV5Error::InvalidSequence);
            }
            if entry.previous_commitment() != &previous {
                return Err(LedgerV5Error::InvalidPreviousCommitment);
            }
            if self.entries[..index]
                .iter()
                .any(|existing| existing.event().commitment() == entry.event().commitment())
            {
                return Err(LedgerV5Error::DuplicateDomainEvent);
            }
            previous = entry.commitment();
        }
        Ok(())
    }
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
    use alloc::vec;

    fn owner() -> PubKey {
        PubKey::from([7; 32])
    }

    fn event(payload: Vec<u8>) -> DomainEventV5 {
        DomainEventV5::unsigned(
            EventKind::InvitationSent,
            payload,
            Timestamp::from(123),
            PubKey::from([9; 32]),
        )
    }

    #[test]
    fn domain_event_commitment_binds_all_order_critical_fields() {
        let base = event(vec![1, 2, 3]);
        let different_time = DomainEventV5::unsigned(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(124),
            PubKey::from([9; 32]),
        );
        let different_signer = DomainEventV5::unsigned(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(123),
            PubKey::from([10; 32]),
        );

        assert_ne!(base.commitment(), different_time.commitment());
        assert_ne!(base.commitment(), different_signer.commitment());
    }

    #[test]
    fn v5_entry_chain_rejects_reorder_and_previous_link_substitution() {
        let mut ledger = LedgerV5::fresh(owner());
        let first = LedgerEntryV5::unsigned(owner(), 0, ledger.tail_commitment(), event(vec![1]));
        ledger.append(first.clone()).expect("first entry");

        let second = LedgerEntryV5::unsigned(owner(), 1, ledger.tail_commitment(), event(vec![2]));
        ledger.append(second).expect("second entry");

        let reordered =
            LedgerEntryV5::unsigned(owner(), 0, ledger.anchor().commitment(), event(vec![2]));
        assert_eq!(
            ledger.append(reordered),
            Err(LedgerV5Error::InvalidSequence)
        );

        let wrong_previous = LedgerEntryV5::unsigned(owner(), 2, ZERO_COMMITMENT, event(vec![3]));
        assert_eq!(
            ledger.append(wrong_previous),
            Err(LedgerV5Error::InvalidPreviousCommitment)
        );
        assert!(ledger.verify_structure().is_ok());

        // Removing an interior entry makes the remaining sequence/link invalid.
        ledger.entries.remove(0);
        assert_eq!(
            ledger.verify_structure(),
            Err(LedgerV5Error::InvalidSequence)
        );
    }

    #[test]
    fn v5_legacy_anchor_binds_exact_v4_snapshot() {
        let first = LedgerAnchorV5::legacy_snapshot_commitment(b"legacy-v4-a");
        let second = LedgerAnchorV5::legacy_snapshot_commitment(b"legacy-v4-b");
        assert_ne!(first, second);

        let anchor = LedgerAnchorV5::legacy(owner(), first, Signature::from([3; 64]));
        let ledger = LedgerV5::from_anchor(owner(), anchor).expect("matching owner");
        assert_eq!(ledger.tail_commitment(), ledger.anchor().commitment());
    }

    #[test]
    fn v5_golden_commitment_vectors_are_stable() {
        let domain = event(vec![1, 2, 3]);
        let anchor = LedgerAnchorV5::fresh(owner());
        let entry = LedgerEntryV5::unsigned(owner(), 0, anchor.commitment(), domain.clone());

        assert_eq!(
            hex::encode(domain.commitment()),
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
