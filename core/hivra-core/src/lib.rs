#![no_std]

extern crate alloc;

// Make modules public so they can be used by other crates
pub mod capsule;
pub mod event;
pub mod event_payloads;
pub mod invitation;
pub mod ledger;
pub mod ledger_v5;
pub mod pair;
pub mod primitives;
pub mod relationship;
pub mod slot;
pub mod starter;

// Re-export commonly used types
pub use event::{Event, EventKind, CONTINUOUS_LEDGER_PROTOCOL_VERSION, PROTOCOL_VERSION};
pub use event_payloads::{
    CapsuleCreatedPayload, EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload,
    InvitationRejectedPayload, InvitationSentPayload, RejectReason, RelationshipBrokenPayload,
    RelationshipEstablishedPayload, StarterBurnedPayload, StarterCreatedPayload,
};
pub use invitation::{
    find_invitation, find_invitation_by_direction, invitation_current_view_v1, invitation_status,
    invitations_with_status, pending_invitation_count, pending_invitations, plan_accept_for_kind,
    AcceptPlan, InvitationCurrentItemV1, InvitationCurrentViewV1, InvitationDirection,
    InvitationRecord, InvitationStatus, PlannedStarterCreation,
};
pub use ledger::Ledger;
pub use ledger_v5::{
    Commitment, LedgerAnchorV5, LedgerEntryV5, LedgerV5Error, COMMITMENT_LENGTH,
    LEDGER_PROTOCOL_VERSION_V5, ZERO_COMMITMENT,
};
pub use pair::{pair_view_v1, PairBlockerV1, PairRelationshipV1, PairViewItemV1, PairViewV1};
pub use primitives::{Network, PubKey, Signature, StarterId, StarterKind, Timestamp};
pub use relationship::{
    relationship_current_view_v1, Relationship, RelationshipCurrentItemV1,
    RelationshipCurrentViewV1, Relationships,
};
pub use starter::Starter;
