#![no_std]

extern crate alloc;

// Make modules public so they can be used by other crates
pub mod capsule;
pub mod event;
pub mod event_payloads;
pub mod invitation;
pub mod ledger;
pub mod primitives;
pub mod relationship;
pub mod slot;
pub mod starter;

// Re-export commonly used types
pub use event::{Event, EventKind, PROTOCOL_VERSION};
pub use event_payloads::{
    CapsuleCreatedPayload, EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload,
    InvitationRejectedPayload, InvitationSentPayload, RejectReason, RelationshipBrokenPayload,
    RelationshipEstablishedPayload, StarterBurnedPayload, StarterCreatedPayload,
};
pub use invitation::{
    find_invitation, invitation_status, invitations_with_status, pending_invitation_count,
    pending_invitations, plan_accept_for_kind, AcceptPlan, InvitationRecord, InvitationStatus,
    PlannedStarterCreation,
};
pub use ledger::Ledger;
pub use primitives::{Network, PubKey, Signature, StarterId, StarterKind, Timestamp};
pub use starter::Starter;
