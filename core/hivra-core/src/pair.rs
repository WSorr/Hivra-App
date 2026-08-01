use crate::invitation::{invitations_with_status, InvitationDirection, InvitationStatus};
use crate::relationship::relationship_current_view_v1;
use crate::{Ledger, PubKey};
use alloc::vec::Vec;
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PairViewV1 {
    pub schema: &'static str,
    pub version: u16,
    pub ledger_version: usize,
    pub pairs: Vec<PairViewItemV1>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PairViewItemV1 {
    pub local_identity: [u8; 32],
    pub peer_identity: [u8; 32],
    pub finalized_invitation_count: usize,
    pub active_relationships: Vec<PairRelationshipV1>,
    pub blockers: Vec<PairBlockerV1>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PairRelationshipV1 {
    pub relationship_kind: u8,
    pub starter_pair: [[u8; 32]; 2],
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PairBlockerV1 {
    pub code: &'static str,
    pub subject_id: [u8; 32],
}

#[derive(Default)]
struct PairAccumulator {
    rooted: bool,
    finalized_invitation_count: usize,
    active_relationships: Vec<PairRelationshipV1>,
    pending_invitations: Vec<[u8; 32]>,
    pending_remote_breaks: Vec<[u8; 32]>,
    broken_relationships: Vec<[u8; 32]>,
}

pub fn pair_view_v1(ledger: &Ledger, local_transport: Option<PubKey>) -> PairViewV1 {
    let owner = *ledger.owner();
    let relationships = relationship_current_view_v1(ledger, local_transport);
    let mut transport_to_identity: Vec<([u8; 32], [u8; 32])> = Vec::new();
    let mut pairs: Vec<([u8; 32], PairAccumulator)> = Vec::new();

    for relationship in relationships.relationships {
        transport_to_identity.push((relationship.peer_pubkey, relationship.peer_identity));
        let pair = accumulator_for(&mut pairs, relationship.peer_identity);
        pair.rooted |= relationship.peer_root_pubkey.is_some();
        match relationship.status {
            "active" | "pending_remote_break" => {
                let mut starter_pair = [relationship.own_starter_id, relationship.peer_starter_id];
                starter_pair.sort();
                let fact = PairRelationshipV1 {
                    relationship_kind: relationship.starter_kind,
                    starter_pair,
                };
                if !pair.active_relationships.contains(&fact) {
                    pair.active_relationships.push(fact);
                }
                if relationship.status == "pending_remote_break" {
                    push_unique(&mut pair.pending_remote_breaks, relationship.own_starter_id);
                }
            }
            "broken" => push_unique(&mut pair.broken_relationships, relationship.own_starter_id),
            _ => {}
        }
    }

    for invitation in invitations_with_status(ledger) {
        let (peer_transport, peer_root) = match invitation.direction {
            InvitationDirection::Incoming => (
                invitation.sender_transport_pubkey,
                invitation.sender_root_pubkey,
            ),
            InvitationDirection::Outgoing => {
                let accepted_root = match invitation.status {
                    InvitationStatus::Accepted {
                        accepter_root_pubkey,
                        ..
                    } => accepter_root_pubkey,
                    _ => None,
                };
                (invitation.recipient_pubkey, accepted_root)
            }
        };
        let peer_identity = peer_root
            .map(|key| *key.as_bytes())
            .or_else(|| {
                transport_to_identity
                    .iter()
                    .find_map(|(transport, identity)| {
                        (*transport == *peer_transport.as_bytes()).then_some(*identity)
                    })
            })
            .unwrap_or(*peer_transport.as_bytes());
        if peer_identity == *owner.as_bytes()
            || local_transport.is_some_and(|key| peer_identity == *key.as_bytes())
        {
            continue;
        }
        let pair = accumulator_for(&mut pairs, peer_identity);
        pair.rooted |= peer_root.is_some()
            || transport_to_identity.iter().any(|(transport, identity)| {
                *transport == *peer_transport.as_bytes() && *identity != *peer_transport.as_bytes()
            });
        match invitation.status {
            InvitationStatus::Pending => {
                push_unique(&mut pair.pending_invitations, invitation.invitation_id)
            }
            _ => pair.finalized_invitation_count += 1,
        }
    }

    pairs.sort_by_key(|(peer, _)| *peer);
    let mut items = Vec::with_capacity(pairs.len());
    for (peer_identity, mut pair) in pairs {
        pair.active_relationships.sort_by(|left, right| {
            left.relationship_kind
                .cmp(&right.relationship_kind)
                .then_with(|| left.starter_pair.cmp(&right.starter_pair))
        });
        pair.pending_invitations.sort();
        pair.pending_remote_breaks.sort();
        pair.broken_relationships.sort();

        let local_identity = if pair.rooted {
            *owner.as_bytes()
        } else {
            *local_transport.unwrap_or(owner).as_bytes()
        };
        let mut blockers = Vec::new();
        blockers.extend(
            pair.pending_invitations
                .into_iter()
                .map(|subject_id| PairBlockerV1 {
                    code: "pending_invitation",
                    subject_id,
                }),
        );
        blockers.extend(
            pair.pending_remote_breaks
                .into_iter()
                .map(|subject_id| PairBlockerV1 {
                    code: "pending_remote_break",
                    subject_id,
                }),
        );
        if pair.active_relationships.is_empty() {
            blockers.extend(pair.broken_relationships.into_iter().map(|subject_id| {
                PairBlockerV1 {
                    code: "relationship_broken",
                    subject_id,
                }
            }));
            blockers.push(PairBlockerV1 {
                code: "no_active_relationship",
                subject_id: peer_identity,
            });
        }

        items.push(PairViewItemV1 {
            local_identity,
            peer_identity,
            finalized_invitation_count: pair.finalized_invitation_count,
            active_relationships: pair.active_relationships,
            blockers,
        });
    }

    PairViewV1 {
        schema: "hivra.pair_view",
        version: 1,
        ledger_version: ledger.events().len(),
        pairs: items,
    }
}

fn accumulator_for(
    pairs: &mut Vec<([u8; 32], PairAccumulator)>,
    peer: [u8; 32],
) -> &mut PairAccumulator {
    if let Some(index) = pairs.iter().position(|(identity, _)| *identity == peer) {
        return &mut pairs[index].1;
    }
    pairs.push((peer, PairAccumulator::default()));
    &mut pairs.last_mut().expect("inserted pair").1
}

fn push_unique(values: &mut Vec<[u8; 32]>, value: [u8; 32]) {
    if !values.contains(&value) {
        values.push(value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, EventKind};
    use crate::event_payloads::{
        EventPayload, InvitationSentPayload, RelationshipBrokenPayload,
        RelationshipEstablishedPayload,
    };
    use crate::{Signature, StarterId, StarterKind, Timestamp};
    use alloc::vec;

    fn key(value: u8) -> PubKey {
        PubKey::from([value; 32])
    }

    fn starter(value: u8) -> StarterId {
        StarterId::from([value; 32])
    }

    fn event(kind: EventKind, payload: Vec<u8>, signer: PubKey, timestamp: u64) -> Event {
        Event::new(
            kind,
            payload,
            Timestamp::from(timestamp),
            Signature::from([0; 64]),
            signer,
        )
    }

    fn ledger(owner: PubKey, events: Vec<Event>) -> Ledger {
        let mut ledger = Ledger::new(owner);
        for event in events {
            ledger.append(event).unwrap();
        }
        ledger
    }

    fn established(
        peer_transport: PubKey,
        local_transport: PubKey,
        peer_root: PubKey,
        local_root: PubKey,
        own_starter: StarterId,
        peer_starter: StarterId,
        invitation_id: [u8; 32],
        timestamp: u64,
    ) -> Event {
        event(
            EventKind::RelationshipEstablished,
            RelationshipEstablishedPayload {
                peer_pubkey: peer_transport,
                own_starter_id: own_starter,
                peer_starter_id: peer_starter,
                kind: StarterKind::Spark,
                invitation_id,
                sender_pubkey: local_transport,
                sender_starter_type: StarterKind::Spark,
                sender_starter_id: own_starter,
                peer_root_pubkey: Some(peer_root),
                sender_root_pubkey: Some(local_root),
            }
            .to_bytes(),
            local_root,
            timestamp,
        )
    }

    #[test]
    fn mirrored_ledgers_produce_the_same_pair_snapshot_facts() {
        let root_a = key(1);
        let root_b = key(2);
        let transport_a = key(3);
        let transport_b = key(4);
        let starter_a = starter(5);
        let starter_b = starter(6);
        let invitation_id = [7; 32];
        let ledger_a = ledger(
            root_a,
            vec![established(
                transport_b,
                transport_a,
                root_b,
                root_a,
                starter_a,
                starter_b,
                invitation_id,
                1,
            )],
        );
        let ledger_b = ledger(
            root_b,
            vec![established(
                transport_a,
                transport_b,
                root_a,
                root_b,
                starter_b,
                starter_a,
                invitation_id,
                1,
            )],
        );

        let a = pair_view_v1(&ledger_a, Some(transport_a));
        let b = pair_view_v1(&ledger_b, Some(transport_b));

        assert_eq!(a.pairs.len(), 1);
        assert_eq!(b.pairs.len(), 1);
        assert_eq!(a.pairs[0].local_identity, *root_a.as_bytes());
        assert_eq!(a.pairs[0].peer_identity, *root_b.as_bytes());
        assert_eq!(b.pairs[0].local_identity, *root_b.as_bytes());
        assert_eq!(b.pairs[0].peer_identity, *root_a.as_bytes());
        assert_eq!(
            a.pairs[0].active_relationships,
            b.pairs[0].active_relationships
        );
        assert!(a.pairs[0].blockers.is_empty());
        assert!(b.pairs[0].blockers.is_empty());
    }

    #[test]
    fn pair_scope_ignores_third_capsule_and_deduplicates_relationships() {
        let root_a = key(11);
        let transport_a = key(12);
        let root_b = key(13);
        let transport_b = key(14);
        let root_c = key(15);
        let transport_c = key(16);
        let starter_a = starter(17);
        let starter_b = starter(18);
        let starter_c = starter(19);
        let ab = established(
            transport_b,
            transport_a,
            root_b,
            root_a,
            starter_a,
            starter_b,
            [20; 32],
            1,
        );
        let ledger = ledger(
            root_a,
            vec![
                ab,
                established(
                    transport_b,
                    transport_a,
                    root_b,
                    root_a,
                    starter_a,
                    starter_b,
                    [20; 32],
                    2,
                ),
                established(
                    transport_c,
                    transport_a,
                    root_c,
                    root_a,
                    starter_a,
                    starter_c,
                    [21; 32],
                    3,
                ),
            ],
        );

        let view = pair_view_v1(&ledger, Some(transport_a));
        let pair_b = view
            .pairs
            .iter()
            .find(|pair| pair.peer_identity == *root_b.as_bytes())
            .unwrap();

        assert_eq!(view.pairs.len(), 2);
        assert_eq!(pair_b.active_relationships.len(), 1);
    }

    #[test]
    fn pending_invitation_and_remote_break_block_the_selected_pair() {
        let root_a = key(31);
        let transport_a = key(32);
        let root_b = key(33);
        let transport_b = key(34);
        let own_starter = starter(35);
        let peer_starter = starter(36);
        let invitation_id = [37; 32];
        let pending_id = [38; 32];
        let mut events = vec![established(
            transport_b,
            transport_a,
            root_b,
            root_a,
            own_starter,
            peer_starter,
            invitation_id,
            1,
        )];
        events.push(event(
            EventKind::InvitationSent,
            InvitationSentPayload {
                invitation_id: pending_id,
                starter_id: starter(39),
                to_pubkey: transport_b,
                sender_root_pubkey: Some(root_a),
            }
            .to_bytes(),
            root_a,
            2,
        ));
        events.push(event(
            EventKind::RelationshipBroken,
            RelationshipBrokenPayload {
                peer_pubkey: transport_b,
                own_starter_id: own_starter,
                peer_root_pubkey: Some(root_b),
            }
            .to_bytes(),
            transport_b,
            3,
        ));
        let ledger = ledger(root_a, events);

        let pair = &pair_view_v1(&ledger, Some(transport_a)).pairs[0];
        let codes: Vec<_> = pair.blockers.iter().map(|blocker| blocker.code).collect();

        assert_eq!(pair.active_relationships.len(), 1);
        assert!(codes.contains(&"pending_invitation"));
        assert!(codes.contains(&"pending_remote_break"));
        assert!(!codes.contains(&"no_active_relationship"));
    }
}
