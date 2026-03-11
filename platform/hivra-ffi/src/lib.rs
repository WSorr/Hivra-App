use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::ptr;
use std::sync::Mutex;

use futures::executor::block_on;
use hivra_core::{
    capsule::{Capsule, CapsuleState, CapsuleType},
    event::{Event, EventKind},
    event_payloads::{
        CapsuleCreatedPayload, EventPayload, InvitationAcceptedPayload, InvitationRejectedPayload,
        InvitationSentPayload, RejectReason, StarterBurnedPayload, StarterCreatedPayload,
    },
    Ledger, Network, PubKey, Signature, StarterId, StarterKind, Timestamp,
};
use hivra_engine::{
    CryptoProvider, Engine, EngineConfig, IncomingEffect, PreparedEvent, RandomSource,
    SecureKeyStore, TimeSource,
};
use hivra_keystore::{
    delete_seed, derive_nostr_keypair, load_seed, mnemonic_to_seed, seed_exists, seed_to_mnemonic,
    store_seed, Seed,
};
use hivra_nostr_crypto::NostrCryptoProvider;
use hivra_transport::nostr::{NostrConfig, NostrTransport};
use hivra_transport::{Message, Transport, TransportError};
use nostr_sdk::prelude::{Keys, SecretKey};
use once_cell::sync::Lazy;
use rand::RngCore;
use serde_json;
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Default)]
struct RuntimeState {
    capsule: Option<Capsule>,
}

struct FfiTimeSource;

impl TimeSource for FfiTimeSource {
    fn now(&self) -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
    }
}

struct FfiRandomSource;

impl RandomSource for FfiRandomSource {
    fn fill_bytes(&self, buf: &mut [u8]) {
        rand::thread_rng().fill_bytes(buf);
    }
}

struct SeedBackedKeyStore {
    seed: Seed,
}

impl SecureKeyStore for SeedBackedKeyStore {
    type Error = ();

    fn generate(&self) -> Result<[u8; 32], Self::Error> {
        derive_nostr_public_key(&self.seed).map_err(|_| ())
    }

    fn public_key(&self) -> Result<[u8; 32], Self::Error> {
        derive_nostr_public_key(&self.seed).map_err(|_| ())
    }

    fn sign(&self, msg: &[u8]) -> Result<[u8; 64], Self::Error> {
        let privkey = derive_nostr_keypair(&self.seed).map_err(|_| ())?;
        let crypto = NostrCryptoProvider::new();
        crypto.sign(msg, &privkey).map_err(|_| ())
    }
}

static RUNTIME: Lazy<Mutex<RuntimeState>> = Lazy::new(|| Mutex::new(RuntimeState::default()));

type FfiEngine = Engine<FfiTimeSource, FfiRandomSource, NostrCryptoProvider, SeedBackedKeyStore>;

fn build_engine(seed: &Seed) -> FfiEngine {
    Engine::new(
        FfiTimeSource,
        FfiRandomSource,
        NostrCryptoProvider::new(),
        SeedBackedKeyStore { seed: seed.clone() },
        EngineConfig::default(),
    )
}

fn derive_starter_id(seed: &Seed, slot: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update([slot]);
    hasher.update(b"starter_v1");
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

fn derive_starter_nonce(seed: &Seed, slot: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update([slot]);
    hasher.update(b"starter_nonce_v1");
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

fn derive_nostr_public_key(seed: &Seed) -> Result<[u8; 32], ()> {
    let secret_bytes = derive_nostr_keypair(seed).map_err(|_| ())?;
    let secret = SecretKey::from_slice(&secret_bytes).map_err(|_| ())?;
    let keys = Keys::new(secret);
    Ok(keys.public_key().to_bytes())
}

fn init_runtime_state(
    seed: &Seed,
    network: Network,
    capsule_type: CapsuleType,
) -> Result<(), &'static str> {
    let owner_bytes = derive_nostr_public_key(seed).map_err(|_| "failed to derive pubkey")?;
    let owner = PubKey::from(owner_bytes);
    let mut ledger = Ledger::new(owner);

    let payload = CapsuleCreatedPayload::new(network.to_byte(), capsule_type as u8, [0u8; 32]);
    let event = Event::new(
        EventKind::CapsuleCreated,
        payload.to_bytes(),
        Timestamp::from(0),
        Signature::from([0u8; 64]),
        owner,
    );
    let _ = ledger.append(event);

    // In current Flutter flow, Relay maps to Genesis and Leaf maps to Proto.
    if capsule_type == CapsuleType::Relay {
        let starter_kinds = [
            StarterKind::Juice,
            StarterKind::Spark,
            StarterKind::Seed,
            StarterKind::Pulse,
            StarterKind::Kick,
        ];

        for (slot, kind) in starter_kinds.iter().enumerate() {
            let slot_u8 = slot as u8;
            let starter_id = StarterId::from(derive_starter_id(seed, slot_u8));
            let nonce = derive_starter_nonce(seed, slot_u8);
            let payload = StarterCreatedPayload {
                starter_id,
                nonce,
                kind: *kind,
                network: network.to_byte(),
            };
            let starter_event = Event::new(
                EventKind::StarterCreated,
                payload.to_bytes(),
                Timestamp::from(slot as u64 + 1),
                Signature::from([0u8; 64]),
                owner,
            );
            let _ = ledger.append(starter_event);
        }
    }

    let capsule = Capsule {
        pubkey: owner,
        capsule_type,
        network,
        ledger,
    };

    let mut runtime = RUNTIME.lock().unwrap();
    runtime.capsule = Some(capsule);
    Ok(())
}

fn clear_runtime_state() {
    let mut runtime = RUNTIME.lock().unwrap();
    runtime.capsule = None;
}

fn current_capsule_state() -> Option<CapsuleState> {
    let runtime = RUNTIME.lock().unwrap();
    runtime
        .capsule
        .as_ref()
        .map(|capsule| CapsuleState::from_capsule(capsule))
}

fn export_runtime_ledger() -> Result<String, &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref().ok_or("no capsule")?;
    let mut value = serde_json::to_value(&capsule.ledger).map_err(|_| "serialization failed")?;
    if let serde_json::Value::Object(map) = &mut value {
        map.insert(
            "last_hash".to_string(),
            serde_json::Value::String(capsule.ledger.last_hash().to_string()),
        );
    }
    serde_json::to_string(&value).map_err(|_| "serialization failed")
}

fn normalize_ledger_last_hash(value: &mut serde_json::Value) {
    if let serde_json::Value::Object(map) = value {
        if let Some(raw) = map.get("last_hash") {
            let parsed = match raw {
                serde_json::Value::String(text) => {
                    let trimmed = text.trim();
                    if trimmed.starts_with("0x") || trimmed.starts_with("0X") {
                        u64::from_str_radix(&trimmed[2..], 16).ok()
                    } else {
                        trimmed.parse::<u64>().ok()
                    }
                }
                serde_json::Value::Number(num) => {
                    if let Some(v) = num.as_u64() {
                        Some(v)
                    } else {
                        num.as_f64().and_then(|v| {
                            if v.is_finite() && v >= 0.0 && v <= u64::MAX as f64 {
                                Some(v as u64)
                            } else {
                                None
                            }
                        })
                    }
                }
                _ => None,
            };

            if let Some(num) = parsed {
                map.insert(
                    "last_hash".to_string(),
                    serde_json::Value::Number(num.into()),
                );
            }
        }
    }
}

fn import_runtime_ledger(json: &str) -> Result<(), &'static str> {
    let mut runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_mut().ok_or("no capsule")?;

    let parsed: Ledger = match serde_json::from_str::<Ledger>(json) {
        Ok(ledger) => ledger,
        Err(_) => {
            let mut value: serde_json::Value =
                serde_json::from_str(json).map_err(|_| "parse failed")?;
            if let serde_json::Value::Object(obj) = &mut value {
                let schema = obj.get("schema").and_then(|v| v.as_str());
                let version = obj.get("version").and_then(|v| v.as_u64());
                if schema == Some("hivra.capsule_backup") && version == Some(1) {
                    if let Some(ledger_value) = obj.get_mut("ledger") {
                        normalize_ledger_last_hash(ledger_value);
                        let ledger: Ledger = serde_json::from_value(std::mem::take(ledger_value))
                            .map_err(|_| "parse failed")?;
                        ledger
                    } else {
                        return Err("parse failed");
                    }
                } else {
                    normalize_ledger_last_hash(&mut value);
                    serde_json::from_value(value).map_err(|_| "parse failed")?
                }
            } else {
                return Err("parse failed");
            }
        }
    };

    if parsed.owner() != &capsule.pubkey {
        return Err("owner mismatch");
    }
    capsule.ledger = parsed;
    Ok(())
}

fn event_kind_from_u8(kind: u8) -> Option<EventKind> {
    match kind {
        0 => Some(EventKind::CapsuleCreated),
        1 => Some(EventKind::InvitationSent),
        2 => Some(EventKind::InvitationAccepted),
        3 => Some(EventKind::InvitationRejected),
        4 => Some(EventKind::InvitationExpired),
        5 => Some(EventKind::StarterCreated),
        6 => Some(EventKind::StarterBurned),
        7 => Some(EventKind::RelationshipEstablished),
        8 => Some(EventKind::RelationshipBroken),
        _ => None,
    }
}

fn append_runtime_event_with_signer(
    kind: EventKind,
    payload: &[u8],
    signer: PubKey,
) -> Result<(), &'static str> {
    let mut runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_mut().ok_or("no capsule")?;

    let last_plus_one = capsule
        .ledger
        .events()
        .last()
        .map(|event| event.timestamp().as_u64().saturating_add(1))
        .unwrap_or(0);

    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(last_plus_one);

    // Keep monotonic ordering while moving to unix_ms UTC timestamps.
    let next_ts = core::cmp::max(now_ms, last_plus_one);

    let event = Event::new(
        kind,
        payload.to_vec(),
        Timestamp::from(next_ts),
        Signature::from([0u8; 64]),
        signer,
    );

    capsule.ledger.append(event).map_err(|_| "append failed")
}

fn append_runtime_event(kind: EventKind, payload: &[u8]) -> Result<(), &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    let signer = runtime.capsule.as_ref().ok_or("no capsule")?.pubkey;
    drop(runtime);
    append_runtime_event_with_signer(kind, payload, signer)
}

fn append_prepared_event(prepared: PreparedEvent) -> Result<(), &'static str> {
    let mut runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_mut().ok_or("no capsule")?;
    capsule
        .ledger
        .append(prepared.event)
        .map_err(|_| "append failed")
}

fn event_exists_in_runtime(kind: EventKind, payload: &[u8]) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule
        .ledger
        .events()
        .iter()
        .any(|event| event.kind() == kind && event.payload() == payload)
}

fn event_exists_in_runtime_with_signer(kind: EventKind, payload: &[u8], signer: PubKey) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule.ledger.events().iter().any(|event| {
        event.kind() == kind && event.payload() == payload && event.signer() == &signer
    })
}

fn starter_kind_from_slot(slot: u8) -> Option<StarterKind> {
    match slot {
        0 => Some(StarterKind::Juice),
        1 => Some(StarterKind::Spark),
        2 => Some(StarterKind::Seed),
        3 => Some(StarterKind::Pulse),
        4 => Some(StarterKind::Kick),
        _ => None,
    }
}

fn capsule_network() -> Result<Network, &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    Ok(runtime.capsule.as_ref().ok_or("no capsule")?.network)
}

fn find_starter_kind_by_id_in_runtime(starter_id: &[u8; 32]) -> Option<StarterKind> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref()?;

    for event in capsule.ledger.events() {
        if event.kind() != EventKind::StarterCreated {
            continue;
        }

        let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) else {
            continue;
        };

        if payload.starter_id.as_bytes() == starter_id {
            return Some(payload.kind);
        }
    }

    None
}

fn find_invitation_sent_in_runtime(
    invitation_id: &[u8; 32],
) -> Option<(StarterId, StarterKind, PubKey, bool)> {
    find_invitation_sent_in_runtime_with_direction(invitation_id, None)
}

fn find_invitation_sent_in_runtime_with_direction(
    invitation_id: &[u8; 32],
    expect_incoming: Option<bool>,
) -> Option<(StarterId, StarterKind, PubKey, bool)> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref()?;
    let local_pubkey = capsule.pubkey;
    let mut fallback: Option<(StarterId, StarterKind, PubKey, bool)> = None;

    for event in capsule.ledger.events() {
        if event.kind() != EventKind::InvitationSent {
            continue;
        }

        let payload = event.payload();
        if payload.len() != 96 && payload.len() != 97 {
            continue;
        }

        let mut current_invitation_id = [0u8; 32];
        current_invitation_id.copy_from_slice(&payload[..32]);
        if current_invitation_id != *invitation_id {
            continue;
        }

        let mut starter_id = [0u8; 32];
        starter_id.copy_from_slice(&payload[32..64]);

        let mut addressed_to = [0u8; 32];
        addressed_to.copy_from_slice(&payload[64..96]);
        let signer = *event.signer().as_bytes();

        let is_incoming_by_signer_and_address = addressed_to == local_pubkey.as_bytes().to_owned()
            && signer != local_pubkey.as_bytes().to_owned();
        let is_incoming = is_incoming_by_signer_and_address;

        let mut peer_pubkey = [0u8; 32];
        if is_incoming {
            peer_pubkey.copy_from_slice(&signer);
        } else {
            peer_pubkey.copy_from_slice(&addressed_to);
        }

        let kind = if payload.len() == 97 {
            starter_kind_from_slot(payload[96]).unwrap_or(StarterKind::Juice)
        } else {
            find_starter_kind_by_id_in_runtime(&starter_id).unwrap_or(StarterKind::Juice)
        };

        let candidate = (
            StarterId::from(starter_id),
            kind,
            PubKey::from(peer_pubkey),
            is_incoming,
        );
        match expect_incoming {
            Some(expected) if expected == is_incoming => return Some(candidate),
            Some(_) => {
                if fallback.is_none() {
                    fallback = Some(candidate);
                }
            }
            None => return Some(candidate),
        }
    }

    fallback
}

fn debug_log_invitation_sent_candidates(label: &str, target_invitation_id: &[u8; 32]) {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        eprintln!("[InviteLookup] {} no capsule", label);
        return;
    };
    let local_pubkey = capsule.pubkey;

    eprintln!(
        "[InviteLookup] {} target={:02x?} local={:02x?}",
        label,
        &target_invitation_id[..4],
        &local_pubkey.as_bytes()[..4]
    );

    for event in capsule.ledger.events() {
        if event.kind() != EventKind::InvitationSent {
            continue;
        }

        let payload = event.payload();
        if payload.len() != 96 && payload.len() != 97 {
            continue;
        }

        let mut current_invitation_id = [0u8; 32];
        current_invitation_id.copy_from_slice(&payload[..32]);

        let mut addressed_to = [0u8; 32];
        addressed_to.copy_from_slice(&payload[64..96]);
        let signer = *event.signer().as_bytes();
        let is_incoming = addressed_to == local_pubkey.as_bytes().to_owned()
            && signer != local_pubkey.as_bytes().to_owned();

        eprintln!(
            "[InviteLookup] candidate id={:02x?} signer={:02x?} to={:02x?} incoming={} len={}",
            &current_invitation_id[..4],
            &signer[..4],
            &addressed_to[..4],
            is_incoming,
            payload.len()
        );
    }
}

fn append_starter_created_if_missing(
    engine: &FfiEngine,
    starter_id: StarterId,
    kind: StarterKind,
    network: Network,
    nonce: [u8; 32],
) -> Result<(), &'static str> {
    let prepared = engine
        .prepare_starter_created(starter_id, nonce, kind, network)
        .map_err(|_| "prepare failed")?;
    let payload_bytes = prepared.event.payload().to_vec();

    if event_exists_in_runtime(EventKind::StarterCreated, &payload_bytes) {
        return Ok(());
    }

    append_prepared_event(prepared)
}

fn append_relationship_established_if_missing(
    engine: &FfiEngine,
    peer_pubkey: PubKey,
    own_starter_id: StarterId,
    peer_starter_id: StarterId,
    kind: StarterKind,
) -> Result<(), &'static str> {
    let prepared = engine
        .prepare_relationship_established(peer_pubkey, own_starter_id, peer_starter_id, kind)
        .map_err(|_| "prepare failed")?;
    let payload_bytes = prepared.event.payload().to_vec();

    if event_exists_in_runtime(EventKind::RelationshipEstablished, &payload_bytes) {
        return Ok(());
    }

    append_prepared_event(prepared)
}

fn project_relationship_from_invitation_accepted(
    engine: &FfiEngine,
    message_from: [u8; 32],
    payload: &InvitationAcceptedPayload,
) -> Result<(), &'static str> {
    debug_log_invitation_sent_candidates("incoming_accept", &payload.invitation_id);
    let Some((own_starter_id, kind, _, false)) =
        find_invitation_sent_in_runtime_with_direction(&payload.invitation_id, Some(false))
    else {
        return Err("matching outgoing invitation not found");
    };

    let relationship = engine
        .prepare_relationship_established(
            PubKey::from(message_from),
            own_starter_id,
            payload.created_starter_id,
            kind,
        )
        .map_err(|_| "prepare failed")?;

    let effect = IncomingEffect::Append(relationship.event);
    let IncomingEffect::Append(event) = effect;
    append_prepared_event(PreparedEvent {
        event,
        recipient: None,
    })
}

fn project_effects_from_invitation_rejected(
    engine: &FfiEngine,
    payload: &InvitationRejectedPayload,
) -> Result<(), &'static str> {
    let Some((starter_id, _, _, false)) =
        find_invitation_sent_in_runtime_with_direction(&payload.invitation_id, Some(false))
    else {
        return Err("matching outgoing invitation not found");
    };

    match payload.reason {
        RejectReason::EmptySlot => {
            let prepared = engine
                .prepare_starter_burned(starter_id, payload.reason as u8)
                .map_err(|_| "prepare failed")?;

            if event_exists_in_runtime(EventKind::StarterBurned, prepared.event.payload()) {
                return Ok(());
            }

            append_prepared_event(prepared)
        }
        RejectReason::Other => Ok(()),
    }
}

struct LocalAcceptancePlan {
    relationship_starter_id: StarterId,
    relationship_kind: StarterKind,
    peer_starter_id: StarterId,
    created_starter: Option<(StarterId, StarterKind, [u8; 32])>,
}

fn resolve_local_acceptance_plan(
    seed: &Seed,
    invitation_id: [u8; 32],
) -> Result<LocalAcceptancePlan, &'static str> {
    let Some((peer_starter_id, invited_kind, _, true)) =
        find_invitation_sent_in_runtime_with_direction(&invitation_id, Some(true))
    else {
        eprintln!(
            "[Accept] resolve plan failed: invitation {:02x?} not found as incoming",
            &invitation_id[..4]
        );
        return Err("matching incoming invitation not found");
    };

    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref().ok_or("no capsule")?;
    let slots = hivra_core::slot::SlotLayout::from_ledger(&capsule.ledger);
    let plan = hivra_core::plan_accept_for_kind(&capsule.ledger, &slots, invited_kind);
    eprintln!(
        "[Accept] planning invitation={:02x?} invited_kind={:?} peer_starter={:02x?} slots={:?} plan={:?}",
        &invitation_id[..4],
        invited_kind,
        &peer_starter_id.as_bytes()[..4],
        slots.states(),
        plan
    );
    drop(runtime);

    match plan {
        hivra_core::AcceptPlan::UseExistingStarter {
            relationship_starter_id,
            created_starter,
        } => {
            let created_starter = created_starter.map(|planned| {
                let slot = planned.slot.as_u8();
                (
                    StarterId::from(derive_starter_id(seed, slot)),
                    planned.kind,
                    derive_starter_nonce(seed, slot),
                )
            });

            Ok(LocalAcceptancePlan {
                relationship_starter_id,
                relationship_kind: invited_kind,
                peer_starter_id,
                created_starter,
            })
        }
        hivra_core::AcceptPlan::CreateStarterInEmptySlot { slot, kind } => {
            Ok(LocalAcceptancePlan {
                relationship_starter_id: StarterId::from(derive_starter_id(seed, slot.as_u8())),
                relationship_kind: invited_kind,
                peer_starter_id,
                created_starter: Some((
                    StarterId::from(derive_starter_id(seed, slot.as_u8())),
                    kind,
                    derive_starter_nonce(seed, slot.as_u8()),
                )),
            })
        }
        hivra_core::AcceptPlan::NoCapacity => Err("no capacity to accept invitation"),
    }
}

fn finalize_local_acceptance(
    engine: &FfiEngine,
    plan: &LocalAcceptancePlan,
    from_pubkey: [u8; 32],
) -> Result<(), &'static str> {
    let network = capsule_network()?;
    eprintln!(
        "[Accept] finalize from={:02x?} relationship_starter={:02x?} peer_starter={:02x?} kind={:?} created={}",
        &from_pubkey[..4],
        &plan.relationship_starter_id.as_bytes()[..4],
        &plan.peer_starter_id.as_bytes()[..4],
        plan.relationship_kind,
        plan.created_starter.is_some()
    );

    if let Some((created_starter_id, created_kind, created_nonce)) = plan.created_starter {
        eprintln!(
            "[Accept] append StarterCreated starter={:02x?} kind={:?}",
            &created_starter_id.as_bytes()[..4],
            created_kind
        );
        append_starter_created_if_missing(
            engine,
            created_starter_id,
            created_kind,
            network,
            created_nonce,
        )?;
        eprintln!("[Accept] StarterCreated append ok");
    }

    eprintln!("[Accept] append RelationshipEstablished");
    append_relationship_established_if_missing(
        engine,
        PubKey::from(from_pubkey),
        plan.relationship_starter_id,
        plan.peer_starter_id,
        plan.relationship_kind,
    )?;
    eprintln!("[Accept] RelationshipEstablished append ok");
    Ok(())
}

/// Structure for returning serialized bytes
#[repr(C)]
pub struct FfiBytes {
    data: *mut u8,
    len: usize,
}

mod capsule_api;
mod invitation_api;
mod ledger_api;
mod seed_api;
mod selfcheck_api;

#[cfg(test)]
mod tests {
    use super::*;
    use hivra_core::event_payloads::RelationshipEstablishedPayload;
    use std::sync::Mutex;

    static TEST_GUARD: Mutex<()> = Mutex::new(());

    fn test_seed(byte: u8) -> Seed {
        Seed([byte; 32])
    }

    fn derived_pubkey(seed: &Seed) -> PubKey {
        PubKey::from(derive_nostr_public_key(seed).unwrap())
    }

    fn set_runtime_capsule(owner: PubKey, network: Network) {
        let capsule = Capsule {
            pubkey: owner,
            capsule_type: CapsuleType::Leaf,
            network,
            ledger: Ledger::new(owner),
        };

        let mut runtime = RUNTIME.lock().unwrap();
        runtime.capsule = Some(capsule);
    }

    fn runtime_events() -> Vec<Event> {
        let runtime = RUNTIME.lock().unwrap();
        runtime.capsule.as_ref().unwrap().ledger.events().to_vec()
    }

    fn append_invitation_sent_for_test(
        invitation_id: [u8; 32],
        starter_id: [u8; 32],
        to_pubkey: [u8; 32],
        starter_slot: Option<u8>,
        from_pubkey: Option<[u8; 32]>,
    ) {
        let payload = InvitationSentPayload {
            invitation_id,
            starter_id: StarterId::from(starter_id),
            to_pubkey: PubKey::from(to_pubkey),
        };

        let mut bytes = payload.to_bytes();
        if let Some(slot) = starter_slot {
            bytes.push(slot);
        }
        if let Some(from) = from_pubkey {
            append_runtime_event_with_signer(EventKind::InvitationSent, &bytes, PubKey::from(from))
                .unwrap();
        } else {
            append_runtime_event(EventKind::InvitationSent, &bytes).unwrap();
        }
    }

    #[test]
    fn finalize_local_acceptance_creates_starter_and_relationship() {
        let _guard = TEST_GUARD.lock().unwrap();
        clear_runtime_state();

        let seed = test_seed(7);
        let local_pubkey = derived_pubkey(&seed);
        let inviter_pubkey = [3u8; 32];
        let invitation_id = [5u8; 32];
        let inviter_slot = 1u8;
        let peer_starter_id = derive_starter_id(&test_seed(11), inviter_slot);

        set_runtime_capsule(local_pubkey, Network::Neste);

        append_invitation_sent_for_test(
            invitation_id,
            peer_starter_id,
            local_pubkey.as_bytes().to_owned(),
            Some(inviter_slot),
            Some(inviter_pubkey),
        );

        let engine = build_engine(&seed);
        let acceptance_plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
        let created_starter_id = *acceptance_plan.relationship_starter_id.as_bytes();
        finalize_local_acceptance(&engine, &acceptance_plan, inviter_pubkey).unwrap();

        let events = runtime_events();
        assert!(events.iter().any(|event| {
            event.kind() == EventKind::StarterCreated
                && StarterCreatedPayload::from_bytes(event.payload())
                    .is_ok_and(|payload| payload.starter_id.as_bytes() == &created_starter_id)
        }));
        assert!(events.iter().any(|event| {
            event.kind() == EventKind::RelationshipEstablished
                && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(
                    |payload| {
                        payload.peer_pubkey == PubKey::from(inviter_pubkey)
                            && payload.own_starter_id.as_bytes() == &created_starter_id
                            && payload.peer_starter_id.as_bytes() == &peer_starter_id
                            && payload.kind == StarterKind::Spark
                    },
                )
        }));
    }

    #[test]
    fn incoming_invitation_accepted_projects_outgoing_relationship() {
        let _guard = TEST_GUARD.lock().unwrap();
        clear_runtime_state();

        let local_seed = test_seed(12);
        let local_pubkey = derived_pubkey(&local_seed);
        let peer_pubkey = [8u8; 32];
        let invitation_id = [4u8; 32];
        let own_starter_id = derive_starter_id(&test_seed(12), 0);
        let peer_starter_id = derive_starter_id(&test_seed(13), 0);

        set_runtime_capsule(local_pubkey, Network::Neste);
        append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

        let payload = InvitationAcceptedPayload {
            invitation_id,
            from_pubkey: local_pubkey,
            created_starter_id: StarterId::from(peer_starter_id),
        };

        let engine = build_engine(&local_seed);
        project_relationship_from_invitation_accepted(&engine, peer_pubkey, &payload).unwrap();

        let events = runtime_events();
        assert!(events.iter().any(|event| {
            event.kind() == EventKind::RelationshipEstablished
                && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(
                    |projected| {
                        projected.peer_pubkey == PubKey::from(peer_pubkey)
                            && projected.own_starter_id.as_bytes() == &own_starter_id
                            && projected.peer_starter_id.as_bytes() == &peer_starter_id
                            && projected.kind == StarterKind::Juice
                    },
                )
        }));
    }

    #[test]
    fn incoming_empty_slot_reject_burns_sender_starter() {
        let _guard = TEST_GUARD.lock().unwrap();
        clear_runtime_state();

        let local_seed = test_seed(21);
        let local_pubkey = derived_pubkey(&local_seed);
        let peer_pubkey = [8u8; 32];
        let invitation_id = [4u8; 32];
        let own_starter_id = derive_starter_id(&local_seed, 0);

        set_runtime_capsule(local_pubkey, Network::Neste);
        append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

        let engine = build_engine(&local_seed);
        project_effects_from_invitation_rejected(
            &engine,
            &InvitationRejectedPayload {
                invitation_id,
                reason: RejectReason::EmptySlot,
            },
        )
        .unwrap();

        let events = runtime_events();
        assert!(events.iter().any(|event| {
            event.kind() == EventKind::StarterBurned
                && StarterBurnedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                    payload.starter_id.as_bytes() == &own_starter_id
                        && payload.reason == RejectReason::EmptySlot as u8
                })
        }));
    }
}
