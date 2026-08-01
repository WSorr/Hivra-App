//! Relationship entity.
//!
//! A Relationship is a fact of mutual recognition between two Capsules.
//! One starter can participate in multiple relationships.

use crate::event::EventKind;
use crate::event_payloads::{
    EventPayload, RelationshipBrokenPayload, RelationshipEstablishedPayload,
};
use crate::invitation::{invitations_with_status, InvitationDirection, InvitationStatus};
use crate::ledger::Ledger;
use crate::{PubKey, StarterId, StarterKind, Timestamp};
use alloc::vec::Vec;
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RelationshipCurrentViewV1 {
    pub schema: &'static str,
    pub version: u16,
    pub ledger_version: usize,
    pub active_peer_count: usize,
    pub relationships: Vec<RelationshipCurrentItemV1>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RelationshipCurrentItemV1 {
    pub peer_pubkey: [u8; 32],
    pub peer_root_pubkey: Option<[u8; 32]>,
    pub peer_identity: [u8; 32],
    pub own_starter_id: [u8; 32],
    pub peer_starter_id: [u8; 32],
    pub starter_kind: u8,
    pub established_at: u64,
    pub status: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ProjectedRelationship {
    peer_pubkey: PubKey,
    peer_root_pubkey: Option<PubKey>,
    own_starter_id: StarterId,
    peer_starter_id: StarterId,
    kind: StarterKind,
    established_at: Timestamp,
    is_active: bool,
    has_pending_remote_break: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct EstablishedFact {
    peer_pubkey: PubKey,
    sender_pubkey: Option<PubKey>,
    invitation_id: Option<[u8; 32]>,
    peer_root_pubkey: Option<PubKey>,
    sender_root_pubkey: Option<PubKey>,
    own_starter_id: StarterId,
    peer_starter_id: StarterId,
    kind: StarterKind,
}

pub fn relationship_current_view_v1(
    ledger: &Ledger,
    local_transport: Option<PubKey>,
) -> RelationshipCurrentViewV1 {
    let owner = *ledger.owner();
    let invitation_records = invitations_with_status(ledger);
    let mut projected: Vec<ProjectedRelationship> = Vec::new();

    for event in ledger.events() {
        match event.kind() {
            EventKind::RelationshipEstablished => {
                let Some(established) = parse_established_fact(event.payload()) else {
                    continue;
                };
                let invitation = established.invitation_id.and_then(|invitation_id| {
                    invitation_records
                        .iter()
                        .find(|record| record.invitation_id == invitation_id)
                });
                if invitation.is_some_and(|record| {
                    matches!(
                        record.status,
                        InvitationStatus::Rejected { .. } | InvitationStatus::Expired
                    )
                }) {
                    continue;
                }

                let mut relationship = orient_established(established, owner, event.timestamp());
                if relationship.peer_root_pubkey.is_none() {
                    relationship.peer_root_pubkey =
                        invitation.and_then(|record| match record.direction {
                            InvitationDirection::Incoming => record.sender_root_pubkey,
                            InvitationDirection::Outgoing => match record.status {
                                InvitationStatus::Accepted {
                                    from_pubkey,
                                    accepter_root_pubkey,
                                    ..
                                } if local_transport == Some(from_pubkey)
                                    && record.responded_signer != Some(owner) =>
                                {
                                    accepter_root_pubkey
                                }
                                _ => None,
                            },
                        });
                }
                if relationship.peer_root_pubkey == Some(owner)
                    || local_transport == Some(relationship.peer_pubkey)
                {
                    continue;
                }

                if let Some(current) = projected.iter_mut().find(|current| {
                    current.peer_pubkey == relationship.peer_pubkey
                        && current.own_starter_id == relationship.own_starter_id
                }) {
                    *current = relationship;
                } else {
                    projected.push(relationship);
                }
            }
            EventKind::RelationshipBroken => {
                let Ok(broken) = RelationshipBrokenPayload::from_bytes(event.payload()) else {
                    continue;
                };
                let Some(current) = projected.iter_mut().find(|current| {
                    current.peer_pubkey == broken.peer_pubkey
                        && current.own_starter_id == broken.own_starter_id
                }) else {
                    continue;
                };
                if event.timestamp() < current.established_at {
                    continue;
                }

                let signer = *event.signer();
                let signer_matches_local = signer == owner || local_transport == Some(signer);
                let signer_matches_peer = signer == current.peer_pubkey;
                if !signer_matches_local && !signer_matches_peer {
                    continue;
                }
                let pending_remote = !signer_matches_local && signer_matches_peer;
                if pending_remote && !current.is_active && !current.has_pending_remote_break {
                    continue;
                }
                current.is_active = pending_remote;
                current.has_pending_remote_break = pending_remote;
            }
            _ => {}
        }
    }

    projected.sort_by(|left, right| right.established_at.cmp(&left.established_at));
    let transport_roots: Vec<(PubKey, PubKey)> = projected
        .iter()
        .filter_map(|relationship| {
            relationship
                .peer_root_pubkey
                .map(|root| (relationship.peer_pubkey, root))
        })
        .collect();
    let mut active_peers: Vec<PubKey> = Vec::new();
    let relationships = projected
        .into_iter()
        .map(|relationship| {
            let peer_identity = relationship
                .peer_root_pubkey
                .or_else(|| {
                    transport_roots.iter().find_map(|(transport, root)| {
                        (*transport == relationship.peer_pubkey).then_some(*root)
                    })
                })
                .unwrap_or(relationship.peer_pubkey);
            if relationship.is_active && !active_peers.contains(&peer_identity) {
                active_peers.push(peer_identity);
            }
            RelationshipCurrentItemV1 {
                peer_pubkey: *relationship.peer_pubkey.as_bytes(),
                peer_root_pubkey: relationship.peer_root_pubkey.map(|key| *key.as_bytes()),
                peer_identity: *peer_identity.as_bytes(),
                own_starter_id: *relationship.own_starter_id.as_bytes(),
                peer_starter_id: *relationship.peer_starter_id.as_bytes(),
                starter_kind: relationship.kind.to_byte(),
                established_at: relationship.established_at.as_u64(),
                status: if relationship.has_pending_remote_break {
                    "pending_remote_break"
                } else if relationship.is_active {
                    "active"
                } else {
                    "broken"
                },
            }
        })
        .collect();

    RelationshipCurrentViewV1 {
        schema: "hivra.relationship_current_view",
        version: 1,
        ledger_version: ledger.events().len(),
        active_peer_count: active_peers.len(),
        relationships,
    }
}

fn parse_established_fact(bytes: &[u8]) -> Option<EstablishedFact> {
    if bytes.len() == 97 {
        return Some(EstablishedFact {
            peer_pubkey: PubKey::from(bytes[0..32].try_into().ok()?),
            sender_pubkey: None,
            invitation_id: None,
            peer_root_pubkey: None,
            sender_root_pubkey: None,
            own_starter_id: StarterId::from(bytes[32..64].try_into().ok()?),
            peer_starter_id: StarterId::from(bytes[64..96].try_into().ok()?),
            kind: StarterKind::from_u8(bytes[96])?,
        });
    }
    let payload = RelationshipEstablishedPayload::from_bytes(bytes).ok()?;
    Some(EstablishedFact {
        peer_pubkey: payload.peer_pubkey,
        sender_pubkey: Some(payload.sender_pubkey),
        invitation_id: Some(payload.invitation_id),
        peer_root_pubkey: payload.peer_root_pubkey,
        sender_root_pubkey: payload.sender_root_pubkey,
        own_starter_id: payload.own_starter_id,
        peer_starter_id: payload.peer_starter_id,
        kind: payload.kind,
    })
}

fn orient_established(
    fact: EstablishedFact,
    owner: PubKey,
    established_at: Timestamp,
) -> ProjectedRelationship {
    let peer_root = resolve_peer_root(fact.peer_root_pubkey, fact.sender_root_pubkey, owner);
    let swap_to_sender = fact.peer_root_pubkey == Some(owner)
        && fact.sender_root_pubkey.is_some_and(|root| root != owner)
        && fact.sender_pubkey.is_some();

    if swap_to_sender {
        ProjectedRelationship {
            peer_pubkey: fact.sender_pubkey.expect("checked sender"),
            peer_root_pubkey: peer_root,
            own_starter_id: fact.peer_starter_id,
            peer_starter_id: fact.own_starter_id,
            kind: fact.kind,
            established_at,
            is_active: true,
            has_pending_remote_break: false,
        }
    } else {
        ProjectedRelationship {
            peer_pubkey: fact.peer_pubkey,
            peer_root_pubkey: peer_root,
            own_starter_id: fact.own_starter_id,
            peer_starter_id: fact.peer_starter_id,
            kind: fact.kind,
            established_at,
            is_active: true,
            has_pending_remote_break: false,
        }
    }
}

fn resolve_peer_root(
    peer_root: Option<PubKey>,
    sender_root: Option<PubKey>,
    owner: PubKey,
) -> Option<PubKey> {
    match (peer_root, sender_root) {
        (None, sender) => sender,
        (Some(peer), Some(sender)) if peer == owner && sender != owner => Some(sender),
        (Some(peer), Some(sender)) if sender == owner && peer != owner => Some(peer),
        (peer, _) => peer,
    }
}

/// A relationship between two capsules.
///
/// Each relationship is based on a specific starter kind.
/// One starter can have multiple relationships with different peers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Relationship {
    /// Peer's public key
    peer: PubKey,

    /// Own starter ID used in this relationship
    own_starter_id: StarterId,

    /// Peer's starter ID (if known)
    peer_starter_id: StarterId,

    /// Kind of starter (Juice, Spark, Seed, Pulse, Kick)
    kind: StarterKind,

    /// When the relationship was established
    established_at: Timestamp,
}

impl Relationship {
    /// Creates a new relationship.
    pub fn new(
        peer: PubKey,
        own_starter_id: StarterId,
        peer_starter_id: StarterId,
        kind: StarterKind,
        established_at: Timestamp,
    ) -> Self {
        Self {
            peer,
            own_starter_id,
            peer_starter_id,
            kind,
            established_at,
        }
    }

    /// Returns the peer's public key.
    pub const fn peer(&self) -> &PubKey {
        &self.peer
    }

    /// Returns the own starter ID used in this relationship.
    pub const fn own_starter_id(&self) -> &StarterId {
        &self.own_starter_id
    }

    /// Returns the peer's starter ID.
    pub const fn peer_starter_id(&self) -> &StarterId {
        &self.peer_starter_id
    }

    /// Returns the kind of starter this relationship is based on.
    pub const fn kind(&self) -> StarterKind {
        self.kind
    }

    /// Returns when the relationship was established.
    pub const fn established_at(&self) -> Timestamp {
        self.established_at
    }

    /// Checks if this relationship involves a specific starter.
    pub fn involves_starter(&self, starter_id: &StarterId) -> bool {
        &self.own_starter_id == starter_id || &self.peer_starter_id == starter_id
    }

    /// Checks if this relationship is with a specific peer.
    pub fn is_with_peer(&self, peer: &PubKey) -> bool {
        &self.peer == peer
    }
}

/// Collection of relationships.
///
/// Provides methods to query and manage relationships.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Relationships {
    /// List of active relationships
    active: Vec<Relationship>,
}

impl Relationships {
    /// Creates a new empty relationships collection.
    pub fn new() -> Self {
        Self { active: Vec::new() }
    }

    /// Returns all active relationships.
    pub fn all(&self) -> &[Relationship] {
        &self.active
    }

    /// Returns relationships with a specific peer.
    pub fn with_peer(&self, peer: &PubKey) -> Vec<&Relationship> {
        self.active
            .iter()
            .filter(|r: &&Relationship| r.is_with_peer(peer))
            .collect()
    }

    /// Returns relationships where the given starter is the local (own) starter.
    pub fn for_starter(&self, starter_id: &StarterId) -> Vec<&Relationship> {
        self.active
            .iter()
            .filter(|r: &&Relationship| r.own_starter_id() == starter_id)
            .collect()
    }

    /// Returns relationships of a specific kind.
    pub fn of_kind(&self, kind: StarterKind) -> Vec<&Relationship> {
        self.active
            .iter()
            .filter(|r: &&Relationship| r.kind() == kind)
            .collect()
    }

    /// Adds a new relationship.
    ///
    /// Returns `false` if relationship already exists.
    pub fn add(&mut self, relationship: Relationship) -> bool {
        // Check for duplicate (same peer and same own starter)
        let exists = self.active.iter().any(|r: &Relationship| {
            r.peer() == relationship.peer() && r.own_starter_id() == relationship.own_starter_id()
        });

        if exists {
            false
        } else {
            self.active.push(relationship);
            true
        }
    }

    /// Removes a relationship with a specific peer and starter.
    ///
    /// Returns the removed relationship if found.
    pub fn remove(&mut self, peer: &PubKey, own_starter_id: &StarterId) -> Option<Relationship> {
        let pos = self.active.iter().position(|r: &Relationship| {
            r.is_with_peer(peer) && r.own_starter_id() == own_starter_id
        });

        pos.map(|idx| self.active.remove(idx))
    }

    /// Removes all relationships for a specific starter (when starter is burned).
    pub fn remove_all_for_starter(&mut self, starter_id: &StarterId) -> Vec<Relationship> {
        let mut removed = Vec::new();
        self.active.retain(|r: &Relationship| {
            if r.involves_starter(starter_id) {
                removed.push(r.clone());
                false
            } else {
                true
            }
        });
        removed
    }

    /// Removes all relationships with a specific peer.
    pub fn remove_all_with_peer(&mut self, peer: &PubKey) -> Vec<Relationship> {
        let mut removed = Vec::new();
        self.active.retain(|r: &Relationship| {
            if r.is_with_peer(peer) {
                removed.push(r.clone());
                false
            } else {
                true
            }
        });
        removed
    }

    /// Checks if a relationship exists with a specific peer and starter.
    pub fn exists(&self, peer: &PubKey, own_starter_id: &StarterId) -> bool {
        self.active
            .iter()
            .any(|r: &Relationship| r.is_with_peer(peer) && r.own_starter_id() == own_starter_id)
    }

    /// Returns the number of active relationships.
    pub fn len(&self) -> usize {
        self.active.len()
    }

    /// Returns true if there are no relationships.
    pub fn is_empty(&self) -> bool {
        self.active.is_empty()
    }
}

impl Default for Relationships {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::Event;
    use crate::event_payloads::{InvitationRejectedPayload, RejectReason};
    use crate::Signature;

    fn test_pubkey(id: u8) -> PubKey {
        PubKey::from([id; 32])
    }

    fn test_starter_id(id: u8) -> StarterId {
        StarterId::new([id; 32])
    }

    fn create_test_relationship(
        peer_id: u8,
        own_id: u8,
        peer_starter_id: u8,
        kind: StarterKind,
        time: u64,
    ) -> Relationship {
        Relationship::new(
            test_pubkey(peer_id),
            test_starter_id(own_id),
            test_starter_id(peer_starter_id),
            kind,
            Timestamp::from(time),
        )
    }

    fn append_event(
        ledger: &mut Ledger,
        kind: EventKind,
        payload: Vec<u8>,
        timestamp: u64,
        signer: PubKey,
    ) {
        ledger
            .append(Event::new(
                kind,
                payload,
                Timestamp::from(timestamp),
                Signature::from([0u8; 64]),
                signer,
            ))
            .expect("append relationship vector");
    }

    fn established_payload(
        peer: PubKey,
        own_starter: StarterId,
        peer_starter: StarterId,
        kind: StarterKind,
        invitation_id: [u8; 32],
        sender: PubKey,
        peer_root: Option<PubKey>,
        sender_root: Option<PubKey>,
    ) -> Vec<u8> {
        RelationshipEstablishedPayload {
            peer_pubkey: peer,
            own_starter_id: own_starter,
            peer_starter_id: peer_starter,
            kind,
            invitation_id,
            sender_pubkey: sender,
            sender_starter_type: kind,
            sender_starter_id: own_starter,
            peer_root_pubkey: peer_root,
            sender_root_pubkey: sender_root,
        }
        .to_bytes()
    }

    #[test]
    fn current_view_marks_remote_break_pending() {
        let owner = test_pubkey(1);
        let local_transport = test_pubkey(2);
        let peer = test_pubkey(3);
        let mut ledger = Ledger::new(owner);
        append_event(
            &mut ledger,
            EventKind::RelationshipEstablished,
            established_payload(
                peer,
                test_starter_id(4),
                test_starter_id(5),
                StarterKind::Spark,
                [6u8; 32],
                owner,
                Some(test_pubkey(7)),
                Some(owner),
            ),
            10,
            owner,
        );
        append_event(
            &mut ledger,
            EventKind::RelationshipBroken,
            RelationshipBrokenPayload {
                peer_pubkey: peer,
                own_starter_id: test_starter_id(4),
                peer_root_pubkey: Some(test_pubkey(7)),
            }
            .to_bytes(),
            11,
            peer,
        );

        let view = relationship_current_view_v1(&ledger, Some(local_transport));
        assert_eq!(view.active_peer_count, 1);
        assert_eq!(view.relationships.len(), 1);
        assert_eq!(view.relationships[0].status, "pending_remote_break");
    }

    #[test]
    fn current_view_keeps_local_break_final() {
        let owner = test_pubkey(11);
        let peer = test_pubkey(12);
        let own_starter = test_starter_id(13);
        let mut ledger = Ledger::new(owner);
        append_event(
            &mut ledger,
            EventKind::RelationshipEstablished,
            established_payload(
                peer,
                own_starter,
                test_starter_id(14),
                StarterKind::Seed,
                [15u8; 32],
                owner,
                Some(test_pubkey(16)),
                Some(owner),
            ),
            20,
            owner,
        );
        for (timestamp, signer) in [(21, owner), (22, peer)] {
            append_event(
                &mut ledger,
                EventKind::RelationshipBroken,
                RelationshipBrokenPayload {
                    peer_pubkey: peer,
                    own_starter_id: own_starter,
                    peer_root_pubkey: Some(test_pubkey(16)),
                }
                .to_bytes(),
                timestamp,
                signer,
            );
        }

        let view = relationship_current_view_v1(&ledger, None);
        assert_eq!(view.active_peer_count, 0);
        assert_eq!(view.relationships[0].status, "broken");
    }

    #[test]
    fn current_view_ignores_foreign_breaks() {
        let owner = test_pubkey(21);
        let peer = test_pubkey(22);
        let own_starter = test_starter_id(23);
        let mut ledger = Ledger::new(owner);
        append_event(
            &mut ledger,
            EventKind::RelationshipEstablished,
            established_payload(
                peer,
                own_starter,
                test_starter_id(24),
                StarterKind::Pulse,
                [25u8; 32],
                owner,
                None,
                None,
            ),
            100,
            owner,
        );
        append_event(
            &mut ledger,
            EventKind::RelationshipBroken,
            RelationshipBrokenPayload {
                peer_pubkey: peer,
                own_starter_id: own_starter,
                peer_root_pubkey: None,
            }
            .to_bytes(),
            101,
            test_pubkey(26),
        );

        let view = relationship_current_view_v1(&ledger, None);
        assert_eq!(view.relationships[0].status, "active");
    }

    #[test]
    fn current_view_counts_one_root_across_multiple_transport_links() {
        let owner = test_pubkey(27);
        let peer_root = test_pubkey(28);
        let mut ledger = Ledger::new(owner);
        for (offset, peer) in [test_pubkey(29), test_pubkey(30)].into_iter().enumerate() {
            append_event(
                &mut ledger,
                EventKind::RelationshipEstablished,
                established_payload(
                    peer,
                    test_starter_id(40 + offset as u8),
                    test_starter_id(50 + offset as u8),
                    StarterKind::Spark,
                    [60 + offset as u8; 32],
                    owner,
                    Some(peer_root),
                    Some(owner),
                ),
                110 + offset as u64,
                owner,
            );
        }

        let view = relationship_current_view_v1(&ledger, None);
        assert_eq!(view.relationships.len(), 2);
        assert_eq!(view.active_peer_count, 1);
        assert!(view
            .relationships
            .iter()
            .all(|item| item.peer_identity == *peer_root.as_bytes()));
    }

    #[test]
    fn current_view_new_establishment_supersedes_old_break_episode() {
        let owner = test_pubkey(31);
        let peer = test_pubkey(32);
        let own_starter = test_starter_id(33);
        let mut ledger = Ledger::new(owner);
        let first = established_payload(
            peer,
            own_starter,
            test_starter_id(34),
            StarterKind::Kick,
            [35u8; 32],
            owner,
            None,
            None,
        );
        append_event(
            &mut ledger,
            EventKind::RelationshipEstablished,
            first.clone(),
            10,
            owner,
        );
        append_event(
            &mut ledger,
            EventKind::RelationshipBroken,
            RelationshipBrokenPayload {
                peer_pubkey: peer,
                own_starter_id: own_starter,
                peer_root_pubkey: None,
            }
            .to_bytes(),
            11,
            owner,
        );
        append_event(
            &mut ledger,
            EventKind::RelationshipEstablished,
            first,
            20,
            owner,
        );

        let view = relationship_current_view_v1(&ledger, None);
        assert_eq!(view.active_peer_count, 1);
        assert_eq!(view.relationships[0].status, "active");
        assert_eq!(view.relationships[0].established_at, 20);
    }

    #[test]
    fn current_view_rejects_relationship_lineage_after_invitation_reject() {
        let owner = test_pubkey(41);
        let peer = test_pubkey(42);
        let invitation_id = [43u8; 32];
        let mut ledger = Ledger::new(owner);
        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            crate::InvitationSentPayload {
                invitation_id,
                starter_id: test_starter_id(44),
                to_pubkey: peer,
                sender_root_pubkey: Some(owner),
            }
            .to_bytes(),
            1,
            owner,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            InvitationRejectedPayload {
                invitation_id,
                reason: RejectReason::Other,
            }
            .to_bytes(),
            2,
            peer,
        );
        append_event(
            &mut ledger,
            EventKind::RelationshipEstablished,
            established_payload(
                peer,
                test_starter_id(44),
                test_starter_id(45),
                StarterKind::Juice,
                invitation_id,
                owner,
                None,
                None,
            ),
            3,
            owner,
        );

        let view = relationship_current_view_v1(&ledger, None);
        assert!(view.relationships.is_empty());
        assert_eq!(view.active_peer_count, 0);
    }

    #[test]
    fn test_relationship_creation() {
        let rel = create_test_relationship(1, 2, 3, StarterKind::Juice, 1234567890);

        assert_eq!(rel.peer(), &test_pubkey(1));
        assert_eq!(rel.own_starter_id(), &test_starter_id(2));
        assert_eq!(rel.peer_starter_id(), &test_starter_id(3));
        assert_eq!(rel.kind(), StarterKind::Juice);
        assert_eq!(rel.established_at(), Timestamp::from(1234567890));
    }

    #[test]
    fn test_relationships_collection() {
        let mut rels = Relationships::new();
        assert!(rels.is_empty());

        let rel1 = create_test_relationship(1, 1, 1, StarterKind::Juice, 1000);
        let rel2 = create_test_relationship(2, 1, 2, StarterKind::Juice, 1001);
        let rel3 = create_test_relationship(3, 2, 3, StarterKind::Spark, 1002);

        // Add relationships
        assert!(rels.add(rel1));
        assert!(rels.add(rel2));
        assert!(rels.add(rel3));

        assert_eq!(rels.len(), 3);
        assert!(!rels.is_empty());

        // Check duplicates
        let duplicate = create_test_relationship(1, 1, 4, StarterKind::Juice, 1003);
        assert!(!rels.add(duplicate)); // Should fail

        // Query by peer
        let with_peer1 = rels.with_peer(&test_pubkey(1));
        assert_eq!(with_peer1.len(), 1);
        assert_eq!(with_peer1[0].peer(), &test_pubkey(1));

        // Query by starter
        let for_starter1 = rels.for_starter(&test_starter_id(1));
        assert_eq!(for_starter1.len(), 2); // rel1 and rel2

        let for_starter2 = rels.for_starter(&test_starter_id(2));
        assert_eq!(for_starter2.len(), 1); // rel3

        // Query by kind
        let juice_rels = rels.of_kind(StarterKind::Juice);
        assert_eq!(juice_rels.len(), 2);
        let spark_rels = rels.of_kind(StarterKind::Spark);
        assert_eq!(spark_rels.len(), 1);
    }

    #[test]
    fn test_remove_relationship() {
        let mut rels = Relationships::new();

        let rel1 = create_test_relationship(1, 1, 1, StarterKind::Juice, 1000);
        let rel2 = create_test_relationship(2, 1, 2, StarterKind::Juice, 1001);

        rels.add(rel1);
        rels.add(rel2);
        assert_eq!(rels.len(), 2);

        // Remove specific relationship
        let removed = rels.remove(&test_pubkey(1), &test_starter_id(1));
        assert!(removed.is_some());
        assert_eq!(rels.len(), 1);
        assert!(!rels.exists(&test_pubkey(1), &test_starter_id(1)));
        assert!(rels.exists(&test_pubkey(2), &test_starter_id(1)));

        // Remove non-existent
        let removed = rels.remove(&test_pubkey(3), &test_starter_id(3));
        assert!(removed.is_none());
    }

    #[test]
    fn test_remove_all_for_starter() {
        let mut rels = Relationships::new();

        // Starter 1 has relationships with peers 1 and 2
        rels.add(create_test_relationship(1, 1, 1, StarterKind::Juice, 1000));
        rels.add(create_test_relationship(2, 1, 2, StarterKind::Juice, 1001));
        // Starter 2 has relationship with peer 3
        rels.add(create_test_relationship(3, 2, 3, StarterKind::Spark, 1002));

        assert_eq!(rels.len(), 3);

        // Remove all for starter 1
        let removed = rels.remove_all_for_starter(&test_starter_id(1));
        assert_eq!(removed.len(), 2);
        assert_eq!(rels.len(), 1);

        // Only starter 2's relationship remains
        let remaining = rels.all();
        assert_eq!(remaining[0].own_starter_id(), &test_starter_id(2));
    }

    #[test]
    fn test_remove_all_with_peer() {
        let mut rels = Relationships::new();

        // Peer 1 has relationships with starter 1 and starter 2
        rels.add(create_test_relationship(1, 1, 1, StarterKind::Juice, 1000));
        rels.add(create_test_relationship(1, 2, 2, StarterKind::Spark, 1001));
        // Peer 2 has relationship with starter 1
        rels.add(create_test_relationship(2, 1, 3, StarterKind::Juice, 1002));

        assert_eq!(rels.len(), 3);

        // Remove all with peer 1
        let removed = rels.remove_all_with_peer(&test_pubkey(1));
        assert_eq!(removed.len(), 2);
        assert_eq!(rels.len(), 1);

        // Only peer 2's relationship remains
        let remaining = rels.all();
        assert_eq!(remaining[0].peer(), &test_pubkey(2));
    }

    #[test]
    fn test_relationship_invariants() {
        let rel = create_test_relationship(1, 1, 1, StarterKind::Juice, 1000);

        // Test involves_starter
        assert!(rel.involves_starter(&test_starter_id(1)));
        assert!(!rel.involves_starter(&test_starter_id(2)));

        // Test is_with_peer
        assert!(rel.is_with_peer(&test_pubkey(1)));
        assert!(!rel.is_with_peer(&test_pubkey(2)));
    }
}
