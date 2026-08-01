use crate::event_payloads::{
    EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload, InvitationRejectedPayload,
    InvitationSentPayload, RelationshipBrokenPayload, RelationshipEstablishedPayload,
    StarterBurnedPayload, StarterCreatedPayload,
};
use crate::{Event, EventKind, Ledger};
use alloc::vec;
use alloc::vec::Vec;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistorySubjectKindV1 {
    Invitation,
    Starter,
    Relationship,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistorySubjectV1 {
    pub kind: HistorySubjectKindV1,
    pub primary_id: [u8; 32],
    pub secondary_id: Option<[u8; 32]>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HistoryViewV1 {
    pub schema: &'static str,
    pub version: u16,
    pub ledger_version: usize,
    pub subject: HistorySubjectV1,
    pub entries: Vec<HistoryEntryV1>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HistoryEntryV1 {
    pub ledger_index: usize,
    pub event_kind: EventKind,
    pub timestamp: u64,
    pub summary_code: &'static str,
    pub summary_ids: Vec<[u8; 32]>,
    pub starter_kind: Option<u8>,
    pub reason: Option<u8>,
}

pub fn history_view_v1(ledger: &Ledger, subject: HistorySubjectV1) -> HistoryViewV1 {
    let entries = ledger
        .events()
        .iter()
        .enumerate()
        .filter_map(|(ledger_index, event)| {
            project_event(event, &subject).map(|summary| HistoryEntryV1 {
                ledger_index,
                event_kind: event.kind(),
                timestamp: event.timestamp().as_u64(),
                summary_code: summary.code,
                summary_ids: summary.ids,
                starter_kind: summary.starter_kind,
                reason: summary.reason,
            })
        })
        .collect();

    HistoryViewV1 {
        schema: "hivra.history_view",
        version: 1,
        ledger_version: ledger.events().len(),
        subject,
        entries,
    }
}

struct HistorySummary {
    code: &'static str,
    ids: Vec<[u8; 32]>,
    starter_kind: Option<u8>,
    reason: Option<u8>,
}

fn project_event(event: &Event, subject: &HistorySubjectV1) -> Option<HistorySummary> {
    match event.kind() {
        EventKind::InvitationSent | EventKind::InvitationReceived => {
            let payload = InvitationSentPayload::from_bytes(event.payload()).ok()?;
            let matches = match subject.kind {
                HistorySubjectKindV1::Invitation => payload.invitation_id == subject.primary_id,
                HistorySubjectKindV1::Starter => {
                    *payload.starter_id.as_bytes() == subject.primary_id
                }
                HistorySubjectKindV1::Relationship => {
                    subject.matches(payload.to_pubkey.as_bytes())
                        || payload
                            .sender_root_pubkey
                            .is_some_and(|root| subject.matches(root.as_bytes()))
                }
            };
            matches.then(|| HistorySummary {
                code: if event.kind() == EventKind::InvitationSent {
                    "invitation_sent"
                } else {
                    "invitation_received"
                },
                ids: vec![payload.invitation_id, *payload.starter_id.as_bytes()],
                starter_kind: None,
                reason: None,
            })
        }
        EventKind::InvitationAccepted => {
            let payload = InvitationAcceptedPayload::from_bytes(event.payload()).ok()?;
            let matches = match subject.kind {
                HistorySubjectKindV1::Invitation => payload.invitation_id == subject.primary_id,
                HistorySubjectKindV1::Starter => {
                    *payload.created_starter_id.as_bytes() == subject.primary_id
                }
                HistorySubjectKindV1::Relationship => {
                    subject.matches(payload.from_pubkey.as_bytes())
                        || payload
                            .accepter_root_pubkey
                            .is_some_and(|root| subject.matches(root.as_bytes()))
                }
            };
            matches.then(|| HistorySummary {
                code: "invitation_accepted",
                ids: vec![
                    payload.invitation_id,
                    *payload.created_starter_id.as_bytes(),
                ],
                starter_kind: None,
                reason: None,
            })
        }
        EventKind::InvitationRejected => {
            let payload = InvitationRejectedPayload::from_bytes(event.payload()).ok()?;
            (subject.kind == HistorySubjectKindV1::Invitation
                && payload.invitation_id == subject.primary_id)
                .then(|| HistorySummary {
                    code: "invitation_rejected",
                    ids: vec![payload.invitation_id],
                    starter_kind: None,
                    reason: Some(payload.reason as u8),
                })
        }
        EventKind::InvitationExpired => {
            let payload = InvitationExpiredPayload::from_bytes(event.payload()).ok()?;
            (subject.kind == HistorySubjectKindV1::Invitation
                && payload.invitation_id == subject.primary_id)
                .then(|| HistorySummary {
                    code: "invitation_expired",
                    ids: vec![payload.invitation_id],
                    starter_kind: None,
                    reason: None,
                })
        }
        EventKind::StarterCreated => {
            let payload = StarterCreatedPayload::from_bytes(event.payload()).ok()?;
            (subject.kind == HistorySubjectKindV1::Starter
                && *payload.starter_id.as_bytes() == subject.primary_id)
                .then(|| HistorySummary {
                    code: "starter_created",
                    ids: vec![*payload.starter_id.as_bytes()],
                    starter_kind: Some(payload.kind as u8),
                    reason: None,
                })
        }
        EventKind::StarterBurned => {
            let payload = StarterBurnedPayload::from_bytes(event.payload()).ok()?;
            (subject.kind == HistorySubjectKindV1::Starter
                && *payload.starter_id.as_bytes() == subject.primary_id)
                .then(|| HistorySummary {
                    code: "starter_burned",
                    ids: vec![*payload.starter_id.as_bytes()],
                    starter_kind: None,
                    reason: Some(payload.reason),
                })
        }
        EventKind::RelationshipEstablished => {
            let payload = RelationshipEstablishedPayload::from_bytes(event.payload()).ok()?;
            let matches = match subject.kind {
                HistorySubjectKindV1::Invitation => payload.invitation_id == subject.primary_id,
                HistorySubjectKindV1::Starter => {
                    subject.primary_id == *payload.own_starter_id.as_bytes()
                        || subject.primary_id == *payload.peer_starter_id.as_bytes()
                        || subject.primary_id == *payload.sender_starter_id.as_bytes()
                }
                HistorySubjectKindV1::Relationship => {
                    subject.matches(payload.peer_pubkey.as_bytes())
                        || subject.matches(payload.sender_pubkey.as_bytes())
                        || payload
                            .peer_root_pubkey
                            .is_some_and(|root| subject.matches(root.as_bytes()))
                        || payload
                            .sender_root_pubkey
                            .is_some_and(|root| subject.matches(root.as_bytes()))
                }
            };
            matches.then(|| HistorySummary {
                code: "relationship_established",
                ids: vec![*payload.peer_pubkey.as_bytes()],
                starter_kind: Some(payload.kind as u8),
                reason: None,
            })
        }
        EventKind::RelationshipBroken => {
            let payload = RelationshipBrokenPayload::from_bytes(event.payload()).ok()?;
            let matches = match subject.kind {
                HistorySubjectKindV1::Starter => {
                    subject.primary_id == *payload.own_starter_id.as_bytes()
                }
                HistorySubjectKindV1::Relationship => {
                    subject.matches(payload.peer_pubkey.as_bytes())
                        || payload
                            .peer_root_pubkey
                            .is_some_and(|root| subject.matches(root.as_bytes()))
                }
                HistorySubjectKindV1::Invitation => false,
            };
            matches.then(|| HistorySummary {
                code: "relationship_broken",
                ids: vec![*payload.peer_pubkey.as_bytes()],
                starter_kind: None,
                reason: None,
            })
        }
        EventKind::CapsuleCreated => None,
    }
}

impl HistorySubjectV1 {
    fn matches(&self, value: &[u8; 32]) -> bool {
        self.primary_id == *value || self.secondary_id.is_some_and(|id| id == *value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event_payloads::{RejectReason, RelationshipEstablishedPayload};
    use crate::{PubKey, Signature, StarterId, StarterKind, Timestamp};

    fn key(value: u8) -> PubKey {
        PubKey::from([value; 32])
    }

    fn starter(value: u8) -> StarterId {
        StarterId::from([value; 32])
    }

    fn event(kind: EventKind, payload: Vec<u8>, timestamp: u64) -> Event {
        Event::new(
            kind,
            payload,
            Timestamp::from(timestamp),
            Signature::from([0; 64]),
            key(250),
        )
    }

    fn ledger(events: Vec<Event>) -> Ledger {
        let mut ledger = Ledger::new(key(251));
        for event in events {
            ledger.append(event).unwrap();
        }
        ledger
    }

    #[test]
    fn invitation_history_contains_only_its_typed_lifecycle() {
        let invitation_id = [1; 32];
        let other_id = [2; 32];
        let starter_id = starter(3);
        let peer = key(4);
        let relationship = RelationshipEstablishedPayload {
            peer_pubkey: peer,
            own_starter_id: starter_id,
            peer_starter_id: starter(5),
            kind: StarterKind::Juice,
            invitation_id,
            sender_pubkey: peer,
            sender_starter_type: StarterKind::Juice,
            sender_starter_id: starter_id,
            peer_root_pubkey: None,
            sender_root_pubkey: None,
        };
        let ledger = ledger(vec![
            event(
                EventKind::InvitationSent,
                InvitationSentPayload {
                    invitation_id,
                    starter_id,
                    to_pubkey: peer,
                    sender_root_pubkey: None,
                }
                .to_bytes(),
                100,
            ),
            event(
                EventKind::InvitationRejected,
                InvitationRejectedPayload {
                    invitation_id: other_id,
                    reason: RejectReason::Other,
                }
                .to_bytes(),
                101,
            ),
            event(
                EventKind::InvitationReceived,
                InvitationSentPayload {
                    invitation_id,
                    starter_id,
                    to_pubkey: peer,
                    sender_root_pubkey: None,
                }
                .to_bytes(),
                102,
            ),
            event(
                EventKind::InvitationAccepted,
                InvitationAcceptedPayload {
                    invitation_id,
                    from_pubkey: peer,
                    created_starter_id: starter_id,
                    accepter_root_pubkey: None,
                }
                .to_bytes(),
                103,
            ),
            event(
                EventKind::InvitationRejected,
                InvitationRejectedPayload {
                    invitation_id,
                    reason: RejectReason::EmptySlot,
                }
                .to_bytes(),
                104,
            ),
            event(
                EventKind::InvitationExpired,
                InvitationExpiredPayload { invitation_id }.to_bytes(),
                105,
            ),
            event(
                EventKind::RelationshipEstablished,
                relationship.to_bytes(),
                106,
            ),
        ]);

        let view = history_view_v1(
            &ledger,
            HistorySubjectV1 {
                kind: HistorySubjectKindV1::Invitation,
                primary_id: invitation_id,
                secondary_id: None,
            },
        );

        assert_eq!(view.entries.len(), 6);
        assert_eq!(view.entries[0].ledger_index, 0);
        assert_eq!(view.entries[1].event_kind, EventKind::InvitationReceived);
        assert_eq!(view.entries[2].event_kind, EventKind::InvitationAccepted);
        assert_eq!(view.entries[3].reason, Some(RejectReason::EmptySlot as u8));
        assert_eq!(view.entries[4].event_kind, EventKind::InvitationExpired);
        assert_eq!(view.entries[5].summary_code, "relationship_established");
    }

    #[test]
    fn starter_history_follows_creation_invitation_relationship_and_burn() {
        let invitation_id = [11; 32];
        let starter_id = starter(12);
        let peer = key(13);
        let ledger = ledger(vec![
            event(
                EventKind::StarterCreated,
                StarterCreatedPayload {
                    starter_id,
                    nonce: [14; 32],
                    kind: StarterKind::Spark,
                    network: 1,
                }
                .to_bytes(),
                200,
            ),
            event(
                EventKind::InvitationSent,
                InvitationSentPayload {
                    invitation_id,
                    starter_id,
                    to_pubkey: peer,
                    sender_root_pubkey: None,
                }
                .to_bytes(),
                201,
            ),
            event(
                EventKind::RelationshipBroken,
                RelationshipBrokenPayload {
                    peer_pubkey: peer,
                    own_starter_id: starter_id,
                    peer_root_pubkey: None,
                }
                .to_bytes(),
                202,
            ),
            event(
                EventKind::StarterBurned,
                StarterBurnedPayload {
                    starter_id,
                    reason: 0,
                }
                .to_bytes(),
                203,
            ),
        ]);

        let view = history_view_v1(
            &ledger,
            HistorySubjectV1 {
                kind: HistorySubjectKindV1::Starter,
                primary_id: *starter_id.as_bytes(),
                secondary_id: None,
            },
        );

        assert_eq!(view.entries.len(), 4);
        assert_eq!(view.entries[0].starter_kind, Some(StarterKind::Spark as u8));
        assert_eq!(view.entries[3].reason, Some(0));
    }

    #[test]
    fn relationship_history_matches_transport_or_root_and_rejects_malformed_payloads() {
        let peer_transport = key(21);
        let peer_root = key(22);
        let starter_id = starter(23);
        let ledger = ledger(vec![
            event(EventKind::RelationshipBroken, vec![22; 63], 299),
            event(
                EventKind::RelationshipBroken,
                RelationshipBrokenPayload {
                    peer_pubkey: peer_transport,
                    own_starter_id: starter_id,
                    peer_root_pubkey: Some(peer_root),
                }
                .to_bytes(),
                300,
            ),
        ]);

        let view = history_view_v1(
            &ledger,
            HistorySubjectV1 {
                kind: HistorySubjectKindV1::Relationship,
                primary_id: *peer_transport.as_bytes(),
                secondary_id: Some(*peer_root.as_bytes()),
            },
        );

        assert_eq!(view.entries.len(), 1);
        assert_eq!(view.entries[0].ledger_index, 1);
        assert_eq!(view.entries[0].summary_code, "relationship_broken");
    }
}
