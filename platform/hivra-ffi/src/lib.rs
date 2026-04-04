use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::ptr;
use std::sync::Mutex;

use futures::executor::block_on;
#[cfg(test)]
use hivra_core::event_payloads::StarterBurnedPayload;
use hivra_core::{
    capsule::{Capsule, CapsuleState, CapsuleType},
    event::{Event, EventKind},
    event_payloads::{
        CapsuleCreatedPayload, EventPayload, InvitationAcceptedPayload, InvitationRejectedPayload,
        InvitationSentPayload, RejectReason, StarterCreatedPayload,
    },
    Ledger, Network, PubKey, Signature, StarterId, StarterKind, Timestamp,
};
use hivra_ed25519_crypto::Ed25519CryptoProvider;
use hivra_engine::{
    CryptoProvider, Engine, EngineConfig, PreparedEvent, RandomSource, SecureKeyStore, TimeSource,
};
use hivra_keystore::{
    delete_seed, derive_nostr_keypair, derive_root_keypair, derive_root_public_key, load_seed,
    mnemonic_to_seed, seed_exists, seed_to_mnemonic, store_seed, Seed,
};
use hivra_transport::nostr::{NostrConfig, NostrTransport};
use hivra_transport::{Message, Transport, TransportError};
use nostr_sdk::prelude::{Keys, SecretKey};
use once_cell::sync::Lazy;
use rand::RngCore;
use serde_json;
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) static LAST_ERROR: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

pub(crate) fn set_last_error(message: impl Into<String>) {
    *LAST_ERROR.lock().unwrap() = Some(message.into());
}

pub(crate) fn clear_last_error() {
    *LAST_ERROR.lock().unwrap() = None;
}

mod capsule_api;
mod chat_api;
mod ffi_support;
mod invitation_api;
mod invitation_support;
mod ledger_api;
mod relationship_api;
mod runtime_support;
mod seed_api;
mod selfcheck_api;
mod transport_cache;

pub use ffi_support::FfiBytes;
#[cfg(test)]
pub(crate) use invitation_support::invitation_offer_exists_in_runtime;
pub(crate) use invitation_support::{
    finalize_local_acceptance, find_invitation_sent_in_runtime, invitation_is_resolved_in_runtime,
    project_effects_from_invitation_rejected, project_relationship_from_invitation_accepted,
    resolve_local_acceptance_plan, should_skip_incoming_delivery_append,
};
pub(crate) use runtime_support::{
    active_starter_id_for_slot, append_prepared_event, append_runtime_event,
    append_runtime_event_with_signer, build_engine, capsule_network, clear_runtime_state,
    current_capsule_state, derive_nostr_public_key, event_exists_in_runtime,
    event_exists_in_runtime_with_signer, event_kind_from_u8, export_runtime_ledger,
    find_starter_kind_by_id_in_runtime, import_runtime_ledger, init_runtime_state,
    starter_kind_from_slot, CapsuleOwnerMode, FfiEngine, RUNTIME,
};
#[cfg(test)]
pub(crate) use runtime_support::{derive_starter_id, derive_starter_nonce};
pub(crate) use transport_cache::{
    clear_cached_nostr_transports, with_cached_nostr_transport, TransportProfile,
};

#[cfg(test)]
mod tests;
