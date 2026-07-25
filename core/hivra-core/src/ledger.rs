//! Ledger — append-only journal of signed events.

use crate::{
    Commitment, Event, EventKind, LedgerAnchorV5, LedgerEntryV5, LedgerV5Error, PubKey, Signature,
    Timestamp, CONTINUOUS_LEDGER_PROTOCOL_VERSION, PROTOCOL_VERSION,
};
use alloc::vec::Vec;
use core::hash::{Hash, Hasher};
use serde::{Deserialize, Serialize};

/// Error type for ledger operations
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedgerError {
    InvalidOrder,
    WrongVersion,
    DuplicateEvent,
    Continuous(LedgerV5Error),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct LedgerV5Receipt {
    sequence: u64,
    previous_commitment: Commitment,
    signature: Signature,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct ContinuousLedgerV5 {
    anchor: LedgerAnchorV5,
    /// Number of immutable v4 events committed by a migration anchor. Fresh
    /// v5 ledgers have no legacy prefix.
    #[serde(default)]
    legacy_event_count: usize,
    receipts: Vec<LedgerV5Receipt>,
}

/// Simple hasher for no_std compatibility
#[derive(Default)]
struct SimpleHasher(u64);

impl SimpleHasher {
    fn new() -> Self {
        Self(0)
    }
    fn finish(&self) -> u64 {
        self.0
    }
}

impl Hasher for SimpleHasher {
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 = self.0.wrapping_mul(0x9e3779b97f4a7c15);
            self.0 ^= *b as u64;
        }
    }
    fn finish(&self) -> u64 {
        self.0
    }
}

/// Ledger — append-only journal of signed events
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ledger {
    events: Vec<Event>,
    owner: PubKey,
    last_hash: u64,
    /// Present only for v5. Events remain the one canonical domain-fact
    /// sequence; receipts attest to their local history acceptance.
    #[serde(default)]
    continuity_v5: Option<ContinuousLedgerV5>,
}

impl Ledger {
    pub fn new(owner: PubKey) -> Self {
        Self {
            events: Vec::new(),
            owner,
            last_hash: 0,
            continuity_v5: None,
        }
    }

    /// Creates a protocol-v5 ledger. It intentionally starts empty: a v4
    /// history must be migrated through a signed legacy anchor, never silently
    /// relabelled as continuous history.
    pub fn fresh_v5(owner: PubKey) -> Self {
        Self {
            events: Vec::new(),
            owner,
            last_hash: 0,
            continuity_v5: Some(ContinuousLedgerV5 {
                anchor: LedgerAnchorV5::fresh(owner),
                legacy_event_count: 0,
                receipts: Vec::new(),
            }),
        }
    }

    /// Converts one validated v4 ledger into a mixed-history v5 ledger. The
    /// original events stay in the only canonical event sequence; the signed
    /// anchor attests exactly that legacy prefix before any v5 mutation.
    pub fn migrate_v4(self, anchor: LedgerAnchorV5) -> Result<Self, LedgerV5Error> {
        if self.continuity_v5.is_some() {
            return Err(LedgerV5Error::NotContinuousLedger);
        }
        if anchor.owner() != &self.owner {
            return Err(LedgerV5Error::AnchorOwnerMismatch);
        }
        if !self.verify() {
            return Err(LedgerV5Error::InvalidPreviousCommitment);
        }
        Ok(Self {
            continuity_v5: Some(ContinuousLedgerV5 {
                anchor,
                legacy_event_count: self.events.len(),
                receipts: Vec::new(),
            }),
            ..self
        })
    }

    pub fn owner(&self) -> &PubKey {
        &self.owner
    }
    pub fn events(&self) -> &[Event] {
        &self.events
    }
    pub fn last_hash(&self) -> u64 {
        self.last_hash
    }

    pub fn is_continuous_v5(&self) -> bool {
        self.continuity_v5.is_some()
    }

    pub fn anchor_v5(&self) -> Option<&LedgerAnchorV5> {
        self.continuity_v5
            .as_ref()
            .map(|continuity| &continuity.anchor)
    }

    pub fn next_sequence_v5(&self) -> Result<u64, LedgerV5Error> {
        self.continuity_v5
            .as_ref()
            .map(|continuity| continuity.receipts.len() as u64)
            .ok_or(LedgerV5Error::NotContinuousLedger)
    }

    pub fn tail_commitment_v5(&self) -> Result<Commitment, LedgerV5Error> {
        let continuity = self
            .continuity_v5
            .as_ref()
            .ok_or(LedgerV5Error::NotContinuousLedger)?;
        Ok(match continuity.receipts.last().zip(self.events.last()) {
            Some((receipt, event)) => LedgerEntryV5::unsigned(
                self.owner,
                receipt.sequence,
                receipt.previous_commitment,
                event.clone(),
            )
            .with_signature(receipt.signature)
            .commitment(),
            None => continuity.anchor.commitment(),
        })
    }

    /// Returns the canonical v5 history head when this ledger uses continuous
    /// commitments. The legacy v4 checksum remains available through
    /// `last_hash()` solely to validate an anchored legacy prefix.
    pub fn head_commitment_v5(&self) -> Option<Commitment> {
        self.tail_commitment_v5().ok()
    }

    /// Reconstructs v5 entries from the canonical events and their local
    /// receipts. It never stores a second copy of a domain event.
    pub fn v5_entries(&self) -> Option<impl Iterator<Item = LedgerEntryV5> + '_> {
        self.continuity_v5.as_ref().map(|continuity| {
            continuity
                .receipts
                .iter()
                .zip(self.events[continuity.legacy_event_count..].iter())
                .map(move |(receipt, event)| {
                    LedgerEntryV5::unsigned(
                        self.owner,
                        receipt.sequence,
                        receipt.previous_commitment,
                        event.clone(),
                    )
                    .with_signature(receipt.signature)
                })
        })
    }

    pub fn append(&mut self, event: Event) -> Result<(), LedgerError> {
        if self.continuity_v5.is_some() {
            return Err(LedgerError::Continuous(LedgerV5Error::WrongEventVersion));
        }
        if event.version() != PROTOCOL_VERSION {
            return Err(LedgerError::WrongVersion);
        }

        if self.events.iter().any(|existing| existing == &event) {
            return Err(LedgerError::DuplicateEvent);
        }

        if let Some(last) = self.events.last() {
            if event.timestamp() < last.timestamp() {
                return Err(LedgerError::InvalidOrder);
            }
        }

        let mut hasher = SimpleHasher::new();
        self.last_hash.hash(&mut hasher);
        event.hash(&mut hasher);
        self.last_hash = hasher.finish();

        self.events.push(event);
        Ok(())
    }

    /// Appends one root-attested v5 history entry. The entry embeds a domain
    /// event only at the API boundary; `Ledger` stores that event once.
    pub fn append_v5(&mut self, entry: LedgerEntryV5) -> Result<(), LedgerError> {
        let Some(continuity) = self.continuity_v5.as_ref() else {
            return Err(LedgerError::Continuous(LedgerV5Error::NotContinuousLedger));
        };
        if continuity.anchor.owner() != &self.owner {
            return Err(LedgerError::Continuous(LedgerV5Error::AnchorOwnerMismatch));
        }
        if entry.owner() != &self.owner {
            return Err(LedgerError::Continuous(LedgerV5Error::EntryOwnerMismatch));
        }
        if entry.event().version() != CONTINUOUS_LEDGER_PROTOCOL_VERSION {
            return Err(LedgerError::Continuous(LedgerV5Error::WrongEventVersion));
        }
        if entry.sequence() != continuity.receipts.len() as u64 {
            return Err(LedgerError::Continuous(LedgerV5Error::InvalidSequence));
        }
        if entry.previous_commitment()
            != &self.tail_commitment_v5().map_err(LedgerError::Continuous)?
        {
            return Err(LedgerError::Continuous(
                LedgerV5Error::InvalidPreviousCommitment,
            ));
        }
        if self
            .events
            .iter()
            .any(|existing| existing.event_id() == entry.event().event_id())
        {
            return Err(LedgerError::DuplicateEvent);
        }

        self.events.push(entry.event().clone());
        self.continuity_v5
            .as_mut()
            .expect("continuity checked above")
            .receipts
            .push(LedgerV5Receipt {
                sequence: entry.sequence(),
                previous_commitment: *entry.previous_commitment(),
                signature: *entry.signature(),
            });
        Ok(())
    }

    pub fn events_in_range(&self, from: Timestamp, to: Timestamp) -> Vec<&Event> {
        self.events
            .iter()
            .filter(|e| e.timestamp() >= from && e.timestamp() <= to)
            .collect()
    }

    pub fn events_of_kind(&self, kind: EventKind) -> Vec<&Event> {
        self.events.iter().filter(|e| e.kind() == kind).collect()
    }

    pub fn verify(&self) -> bool {
        if self.continuity_v5.is_some() {
            return self.verify_v5_structure().is_ok();
        }
        let mut hash = 0u64;
        let mut last_ts = None;

        for (index, event) in self.events.iter().enumerate() {
            if event.version() != PROTOCOL_VERSION {
                return false;
            }

            if self.events[..index]
                .iter()
                .any(|existing| existing == event)
            {
                return false;
            }

            if let Some(ts) = last_ts {
                if event.timestamp() < ts {
                    return false;
                }
            }
            last_ts = Some(event.timestamp());

            let mut hasher = SimpleHasher::new();
            hash.hash(&mut hasher);
            event.hash(&mut hasher);
            hash = hasher.finish();
        }

        hash == self.last_hash
    }

    pub fn verify_v5_structure(&self) -> Result<(), LedgerV5Error> {
        let continuity = self
            .continuity_v5
            .as_ref()
            .ok_or(LedgerV5Error::NotContinuousLedger)?;
        if continuity.anchor.owner() != &self.owner {
            return Err(LedgerV5Error::AnchorOwnerMismatch);
        }
        if continuity.legacy_event_count > self.events.len()
            || continuity.receipts.len()
                != self
                    .events
                    .len()
                    .saturating_sub(continuity.legacy_event_count)
        {
            return Err(LedgerV5Error::InvalidSequence);
        }
        if continuity.legacy_event_count > 0
            && !verify_v4_events(
                &self.events[..continuity.legacy_event_count],
                self.last_hash,
            )
        {
            return Err(LedgerV5Error::InvalidPreviousCommitment);
        }
        let mut previous = continuity.anchor.commitment();
        for (index, (receipt, event)) in continuity
            .receipts
            .iter()
            .zip(self.events[continuity.legacy_event_count..].iter())
            .enumerate()
        {
            if event.version() != CONTINUOUS_LEDGER_PROTOCOL_VERSION {
                return Err(LedgerV5Error::WrongEventVersion);
            }
            if receipt.sequence != index as u64 {
                return Err(LedgerV5Error::InvalidSequence);
            }
            if receipt.previous_commitment != previous {
                return Err(LedgerV5Error::InvalidPreviousCommitment);
            }
            if self.events[..index]
                .iter()
                .any(|existing| existing.event_id() == event.event_id())
            {
                return Err(LedgerV5Error::DuplicateDomainEvent);
            }
            previous = LedgerEntryV5::unsigned(
                self.owner,
                receipt.sequence,
                receipt.previous_commitment,
                event.clone(),
            )
            .with_signature(receipt.signature)
            .commitment();
        }
        Ok(())
    }
}

fn verify_v4_events(events: &[Event], expected_hash: u64) -> bool {
    let mut hash = 0u64;
    let mut last_ts = None;

    for (index, event) in events.iter().enumerate() {
        if event.version() != PROTOCOL_VERSION {
            return false;
        }
        if events[..index].iter().any(|existing| existing == event) {
            return false;
        }
        if let Some(ts) = last_ts {
            if event.timestamp() < ts {
                return false;
            }
        }
        last_ts = Some(event.timestamp());

        let mut hasher = SimpleHasher::new();
        hash.hash(&mut hasher);
        event.hash(&mut hasher);
        hash = hasher.finish();
    }
    hash == expected_hash
}

impl Hash for Event {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.kind().hash(state);
        self.payload().hash(state);
        self.timestamp().hash(state);
        self.signature().as_bytes().hash(state);
        self.signer().as_bytes().hash(state);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{EventKind, Signature, Timestamp};
    use alloc::vec;

    #[test]
    fn test_ledger_append() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        let event = Event::new(
            EventKind::CapsuleCreated,
            vec![0, 1],
            Timestamp::from(1000),
            Signature::from([0u8; 64]),
            owner,
        );

        assert!(ledger.append(event).is_ok());
        assert_eq!(ledger.events().len(), 1);
    }

    #[test]
    fn test_ledger_rejects_duplicate_event() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        let event = Event::new(
            EventKind::CapsuleCreated,
            vec![0, 1],
            Timestamp::from(1000),
            Signature::from([0u8; 64]),
            owner,
        );

        assert!(ledger.append(event.clone()).is_ok());
        assert_eq!(ledger.append(event), Err(LedgerError::DuplicateEvent));
    }

    #[test]
    fn test_ledger_verify_after_append() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        let event = Event::new(
            EventKind::CapsuleCreated,
            vec![0, 1],
            Timestamp::from(1000),
            Signature::from([0u8; 64]),
            owner,
        );

        ledger.append(event).expect("append succeeds");
        assert!(ledger.verify());
    }

    #[test]
    fn test_ledger_accepts_foreign_signed_event() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        let foreign_signer = PubKey::from([2u8; 32]);
        let event = Event::new(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(1000),
            Signature::from([9u8; 64]),
            foreign_signer,
        );

        assert!(ledger.append(event).is_ok());
        assert!(ledger.verify());
    }

    #[test]
    fn v5_ledger_keeps_events_as_the_only_domain_fact_source() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::fresh_v5(owner);
        let event = Event::new_v5(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(1000),
            Signature::from([3u8; 64]),
            PubKey::from([4u8; 32]),
        );
        let entry = LedgerEntryV5::unsigned(owner, 0, ledger.tail_commitment_v5().unwrap(), event)
            .with_signature(Signature::from([5u8; 64]));

        ledger.append_v5(entry).expect("v5 append");
        assert_eq!(ledger.events().len(), 1);
        assert_eq!(ledger.v5_entries().unwrap().count(), 1);
        assert!(ledger.verify_v5_structure().is_ok());
    }

    #[test]
    fn v5_ledger_rejects_reordered_or_missing_receipts() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::fresh_v5(owner);
        let first = Event::new_v5(
            EventKind::InvitationSent,
            vec![1],
            Timestamp::from(1000),
            Signature::from([3u8; 64]),
            PubKey::from([4u8; 32]),
        );
        let first_entry =
            LedgerEntryV5::unsigned(owner, 0, ledger.tail_commitment_v5().unwrap(), first)
                .with_signature(Signature::from([5u8; 64]));
        ledger.append_v5(first_entry).unwrap();

        let bad = LedgerEntryV5::unsigned(
            owner,
            0,
            ledger.tail_commitment_v5().unwrap(),
            Event::new_v5(
                EventKind::InvitationAccepted,
                vec![2],
                Timestamp::from(1001),
                Signature::from([3u8; 64]),
                PubKey::from([4u8; 32]),
            ),
        );
        assert_eq!(
            ledger.append_v5(bad),
            Err(LedgerError::Continuous(LedgerV5Error::InvalidSequence))
        );
    }

    #[test]
    fn v4_migration_keeps_one_event_history_and_starts_v5_after_anchor() {
        let owner = PubKey::from([7u8; 32]);
        let mut legacy = Ledger::new(owner);
        legacy
            .append(Event::new(
                EventKind::CapsuleCreated,
                vec![1],
                Timestamp::from(1000),
                Signature::from([3u8; 64]),
                owner,
            ))
            .unwrap();
        let anchor = LedgerAnchorV5::legacy(
            owner,
            LedgerAnchorV5::legacy_snapshot_commitment(b"canonical legacy snapshot"),
            Signature::from([5u8; 64]),
        );
        let mut ledger = legacy.migrate_v4(anchor).expect("valid migration");
        assert_eq!(ledger.events().len(), 1);
        assert_eq!(ledger.v5_entries().unwrap().count(), 0);

        let event = Event::new_v5(
            EventKind::InvitationSent,
            vec![2],
            Timestamp::from(1),
            Signature::from([6u8; 64]),
            PubKey::from([8u8; 32]),
        );
        let entry = LedgerEntryV5::unsigned(owner, 0, ledger.tail_commitment_v5().unwrap(), event)
            .with_signature(Signature::from([9u8; 64]));
        ledger.append_v5(entry).unwrap();

        assert_eq!(ledger.events().len(), 2);
        assert_eq!(ledger.v5_entries().unwrap().count(), 1);
        assert!(ledger.verify_v5_structure().is_ok());
    }
}
