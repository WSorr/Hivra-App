use super::*;
use hivra_keystore::{
    open_inbound_quarantine_record, open_inbound_quarantine_snapshot,
    seal_inbound_quarantine_record, seal_inbound_quarantine_snapshot,
};
use hivra_transport::DomainEventProof;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

const SCHEMA_VERSION: u16 = 1;
const ADAPTER: &str = "nostr";
const SNAPSHOT_FILE: &str = "inbound_quarantine.v1.bin";
const SNAPSHOT_TEMP_FILE: &str = ".inbound_quarantine.v1.tmp";
const MAX_RECORDS: usize = 256;
const MAX_CIPHERTEXT_BYTES: usize = 32 * 1024 * 1024;
const MAX_RECORDS_PER_SENDER: usize = 32;
const MAX_OBSERVATIONS: usize = 16;
const PAYLOAD_RETENTION_SECS: u64 = 72 * 60 * 60;
const TOMBSTONE_RETENTION_SECS: u64 = 30 * 24 * 60 * 60;
const MAX_TOMBSTONES: usize = 1024;
const MAX_TOMBSTONE_BYTES: usize = 1024 * 1024;
const INITIAL_RETRY_DELAY_SECS: u64 = 15;
const MAX_RETRY_DELAY_SECS: u64 = 15 * 60;
const MAX_EVENT_ID_LEN: usize = 128;
const MAX_ENDPOINT_LEN: usize = 512;
const SENDER_POLICY_BURST: u8 = 8;
const SENDER_POLICY_REFILL_SECS: u64 = 15;
const MAX_POLICY_SENDERS: usize = 1024;
const CHARGE_EVIDENCE_RETENTION_SECS: u64 = 8 * 24 * 60 * 60;
const MAX_CHARGE_EVIDENCE: usize = 65_536;
const MAX_CHARGE_EVIDENCE_PER_SENDER: usize = 40_960;
const MAX_SENDER_POLICY_BYTES: usize = 8 * 1024 * 1024;

static APPLICATION_STORAGE_ROOT: Lazy<Mutex<Option<PathBuf>>> = Lazy::new(|| Mutex::new(None));
static REPOSITORY_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));
#[cfg(test)]
pub(crate) static TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

#[derive(Debug)]
pub(crate) enum QuarantineError {
    Uninitialized,
    InvalidScope,
    InvalidRecord,
    Capacity,
    TombstoneCapacity,
    Corrupt,
    Crypto,
    Io,
}

impl std::fmt::Display for QuarantineError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let value = match self {
            Self::Uninitialized => "storage root is not initialized",
            Self::InvalidScope => "invalid quarantine scope",
            Self::InvalidRecord => "invalid quarantine record",
            Self::Capacity => "quarantine capacity exhausted",
            Self::TombstoneCapacity => "quarantine tombstone capacity exhausted",
            Self::Corrupt => "quarantine snapshot is corrupt",
            Self::Crypto => "quarantine cryptographic operation failed",
            Self::Io => "quarantine persistence failed",
        };
        formatter.write_str(value)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct InboundQuarantineScopeV1 {
    pub(crate) capsule_id: String,
    pub(crate) network: u8,
    pub(crate) transport_endpoint: String,
}

impl InboundQuarantineScopeV1 {
    pub(crate) fn for_runtime(capsule_id: &[u8], network: u8, transport_endpoint: &[u8]) -> Self {
        Self {
            capsule_id: encode_hex(capsule_id),
            network,
            transport_endpoint: encode_hex(transport_endpoint),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InboundQuarantineRecordV1 {
    schema_version: u16,
    scope: InboundQuarantineScopeV1,
    adapter: String,
    adapter_event_id: String,
    authenticated_sender: String,
    observed_by: Vec<String>,
    message_kind: u32,
    reason: String,
    first_observed_at: u64,
    quarantined_at: u64,
    eligible_after: u64,
    expires_at: u64,
    attempt_count: u16,
    last_attempt_at: Option<u64>,
    envelope_ciphertext: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InboundQuarantineTombstoneV1 {
    schema_version: u16,
    scope: InboundQuarantineScopeV1,
    adapter: String,
    adapter_event_id: String,
    authenticated_sender: String,
    message_kind: u32,
    terminal_reason: String,
    first_observed_at: u64,
    terminal_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InboundQuarantineSnapshotV1 {
    schema_version: u16,
    scope: InboundQuarantineScopeV1,
    records: Vec<InboundQuarantineRecordV1>,
    tombstones: Vec<InboundQuarantineTombstoneV1>,
    sender_policies: Vec<SenderIngressPolicyV1>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InboundQuarantineSnapshotPass15V1 {
    schema_version: u16,
    scope: InboundQuarantineScopeV1,
    records: Vec<InboundQuarantineRecordV1>,
    tombstones: Vec<InboundQuarantineTombstoneV1>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SenderIngressPolicyV1 {
    schema_version: u16,
    scope: InboundQuarantineScopeV1,
    authenticated_sender: String,
    available_permits: u8,
    last_refill_at: u64,
    last_activity_at: u64,
    charged_events: Vec<SenderChargeEvidenceV1>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SenderChargeEvidenceV1 {
    adapter_event_id: String,
    charged_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredInboundEnvelopeV1 {
    schema_version: u16,
    from: Vec<u8>,
    to: Vec<u8>,
    kind: u32,
    payload: Vec<u8>,
    timestamp: u64,
    correlation_id: Option<Vec<u8>>,
    domain_event: Option<DomainEventProof>,
}

impl From<&DeliveryEnvelope> for StoredInboundEnvelopeV1 {
    fn from(envelope: &DeliveryEnvelope) -> Self {
        Self {
            schema_version: envelope.schema_version,
            from: envelope.from.to_vec(),
            to: envelope.to.to_vec(),
            kind: envelope.kind,
            payload: envelope.payload.clone(),
            timestamp: envelope.timestamp,
            correlation_id: envelope.correlation_id.map(|value| value.to_vec()),
            domain_event: envelope.domain_event.clone(),
        }
    }
}

impl StoredInboundEnvelopeV1 {
    fn into_delivery_envelope(self) -> Result<DeliveryEnvelope, QuarantineError> {
        Ok(DeliveryEnvelope {
            schema_version: self.schema_version,
            from: self.from.try_into().map_err(|_| QuarantineError::Corrupt)?,
            to: self.to.try_into().map_err(|_| QuarantineError::Corrupt)?,
            kind: self.kind,
            payload: self.payload,
            timestamp: self.timestamp,
            correlation_id: self
                .correlation_id
                .map(|value| value.try_into().map_err(|_| QuarantineError::Corrupt))
                .transpose()?,
            domain_event: self.domain_event,
        })
    }
}

#[derive(Debug, Clone)]
pub(crate) struct RecoveredInboundEnvelope {
    pub(crate) adapter_event_id: String,
    pub(crate) envelope: DeliveryEnvelope,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SenderIngressDecision {
    Permit,
    AlreadyCharged,
    Quarantined,
}

pub(crate) struct CapsuleInboundQuarantineRepository<'a> {
    seed: &'a Seed,
    scope: InboundQuarantineScopeV1,
    snapshot_path: PathBuf,
    snapshot: InboundQuarantineSnapshotV1,
}

pub(crate) fn set_application_storage_root(path: &Path) -> Result<(), QuarantineError> {
    if !path.is_absolute() {
        return Err(QuarantineError::InvalidScope);
    }
    *APPLICATION_STORAGE_ROOT
        .lock()
        .map_err(|_| QuarantineError::Io)? = Some(path.to_path_buf());
    Ok(())
}

pub(crate) fn delete_capsule_quarantine(capsule_id: &str) -> Result<(), QuarantineError> {
    validate_hex32(capsule_id)?;
    let _guard = REPOSITORY_LOCK.lock().map_err(|_| QuarantineError::Io)?;
    let root = application_storage_root()?;
    let path = root
        .join("capsules")
        .join(capsule_id)
        .join("transport_quarantine");
    if path.exists() {
        fs::remove_dir_all(path).map_err(|_| QuarantineError::Io)?;
    }
    Ok(())
}

impl<'a> CapsuleInboundQuarantineRepository<'a> {
    pub(crate) fn open(
        scope: InboundQuarantineScopeV1,
        seed: &'a Seed,
    ) -> Result<Self, QuarantineError> {
        validate_scope(&scope)?;
        let _guard = REPOSITORY_LOCK.lock().map_err(|_| QuarantineError::Io)?;
        let snapshot_path = snapshot_path(&scope)?;
        cleanup_temp_file(&snapshot_path)?;
        let snapshot = if snapshot_path.exists() {
            load_snapshot(&snapshot_path, &scope, seed)?
        } else {
            InboundQuarantineSnapshotV1 {
                schema_version: SCHEMA_VERSION,
                scope: scope.clone(),
                records: Vec::new(),
                tombstones: Vec::new(),
                sender_policies: Vec::new(),
            }
        };
        validate_snapshot(&snapshot, &scope)?;
        Ok(Self {
            seed,
            scope,
            snapshot_path,
            snapshot,
        })
    }

    pub(crate) fn quarantine(
        &mut self,
        adapter_event_id: &str,
        observed_by: &[String],
        envelope: &DeliveryEnvelope,
        reason: &str,
        now: u64,
    ) -> Result<(), QuarantineError> {
        let mut next = self.snapshot.clone();
        append_quarantine_record(
            &mut next,
            &self.scope,
            self.seed,
            adapter_event_id,
            observed_by,
            envelope,
            reason,
            now,
        )?;
        self.snapshot = next;
        self.persist()
    }

    pub(crate) fn apply_sender_policy(
        &mut self,
        adapter_event_id: &str,
        observed_by: &[String],
        envelope: &DeliveryEnvelope,
        now: u64,
    ) -> Result<SenderIngressDecision, QuarantineError> {
        validate_event_id(adapter_event_id)?;
        let authenticated_sender = encode_hex(&envelope.from);
        let mut next = self.snapshot.clone();
        maintain_sender_policy_state(&mut next, now);

        if next
            .records
            .iter()
            .any(|record| record.adapter_event_id == adapter_event_id)
        {
            append_quarantine_record(
                &mut next,
                &self.scope,
                self.seed,
                adapter_event_id,
                observed_by,
                envelope,
                "sender_rate_limited",
                now,
            )?;
            self.snapshot = next;
            self.persist()?;
            return Ok(SenderIngressDecision::Quarantined);
        }

        let policy_index = match next
            .sender_policies
            .iter()
            .position(|policy| policy.authenticated_sender == authenticated_sender)
        {
            Some(index) => index,
            None => {
                make_sender_policy_capacity(&mut next)?;
                next.sender_policies.push(SenderIngressPolicyV1 {
                    schema_version: SCHEMA_VERSION,
                    scope: self.scope.clone(),
                    authenticated_sender: authenticated_sender.clone(),
                    available_permits: SENDER_POLICY_BURST,
                    last_refill_at: now,
                    last_activity_at: now,
                    charged_events: Vec::new(),
                });
                next.sender_policies.len() - 1
            }
        };

        if next.sender_policies[policy_index]
            .charged_events
            .iter()
            .any(|evidence| evidence.adapter_event_id == adapter_event_id)
        {
            next.sender_policies[policy_index].last_activity_at = now;
            self.snapshot = next;
            self.persist()?;
            return Ok(SenderIngressDecision::AlreadyCharged);
        }

        if next.sender_policies[policy_index].available_permits == 0 {
            append_quarantine_record(
                &mut next,
                &self.scope,
                self.seed,
                adapter_event_id,
                observed_by,
                envelope,
                "sender_rate_limited",
                now,
            )?;
            next.sender_policies[policy_index].last_activity_at = now;
            self.snapshot = next;
            self.persist()?;
            return Ok(SenderIngressDecision::Quarantined);
        }

        ensure_charge_evidence_capacity(&next, policy_index)?;
        let policy = &mut next.sender_policies[policy_index];
        policy.available_permits -= 1;
        policy.last_activity_at = now;
        policy.charged_events.push(SenderChargeEvidenceV1 {
            adapter_event_id: adapter_event_id.to_string(),
            charged_at: now,
        });
        policy
            .charged_events
            .sort_by(|left, right| left.adapter_event_id.cmp(&right.adapter_event_id));
        self.snapshot = next;
        self.persist()?;
        Ok(SenderIngressDecision::Permit)
    }

    pub(crate) fn has_terminal_evidence(&self, adapter_event_id: &str) -> bool {
        self.snapshot
            .tombstones
            .iter()
            .any(|item| item.adapter_event_id == adapter_event_id)
    }

    pub(crate) fn expire_due(&mut self, now: u64) -> Result<usize, QuarantineError> {
        let tombstones_before = self.snapshot.tombstones.len();
        self.snapshot.tombstones.retain(|tombstone| {
            now.saturating_sub(tombstone.terminal_at) <= TOMBSTONE_RETENTION_SECS
        });
        let expired_ids = self
            .snapshot
            .records
            .iter()
            .filter(|record| record.expires_at <= now)
            .map(|record| record.adapter_event_id.clone())
            .collect::<Vec<_>>();
        if expired_ids.is_empty() && tombstones_before == self.snapshot.tombstones.len() {
            return Ok(0);
        }

        let mut next = self.snapshot.clone();
        for event_id in &expired_ids {
            let record = next
                .records
                .iter()
                .find(|record| &record.adapter_event_id == event_id)
                .cloned()
                .ok_or(QuarantineError::Corrupt)?;
            append_tombstone(&mut next, &record, "expired", now)?;
            next.records
                .retain(|candidate| candidate.adapter_event_id != *event_id);
        }
        self.snapshot = next;
        self.persist()?;
        Ok(expired_ids.len())
    }

    pub(crate) fn next_eligible(
        &self,
        now: u64,
    ) -> Result<Option<RecoveredInboundEnvelope>, QuarantineError> {
        let Some(record) = self
            .snapshot
            .records
            .iter()
            .filter(|record| record.eligible_after <= now && record.expires_at > now)
            .min_by(|left, right| {
                (
                    left.eligible_after,
                    left.quarantined_at,
                    &left.adapter_event_id,
                )
                    .cmp(&(
                        right.eligible_after,
                        right.quarantined_at,
                        &right.adapter_event_id,
                    ))
            })
        else {
            return Ok(None);
        };
        let aad = record_associated_data(&self.scope, &record.adapter_event_id);
        let plaintext =
            open_inbound_quarantine_record(self.seed, aad.as_bytes(), &record.envelope_ciphertext)
                .map_err(|_| QuarantineError::Crypto)?;
        let stored_envelope: StoredInboundEnvelopeV1 =
            bincode::deserialize(&plaintext).map_err(|_| QuarantineError::Corrupt)?;
        let envelope = stored_envelope.into_delivery_envelope()?;
        if encode_hex(&envelope.from) != record.authenticated_sender
            || envelope.to.as_slice() != decode_hex32(&self.scope.transport_endpoint)?.as_slice()
            || envelope.kind != record.message_kind
        {
            return Err(QuarantineError::Corrupt);
        }
        Ok(Some(RecoveredInboundEnvelope {
            adapter_event_id: record.adapter_event_id.clone(),
            envelope,
        }))
    }

    pub(crate) fn mark_consumed(
        &mut self,
        adapter_event_id: &str,
        now: u64,
    ) -> Result<(), QuarantineError> {
        let record = self
            .snapshot
            .records
            .iter()
            .find(|record| record.adapter_event_id == adapter_event_id)
            .cloned()
            .ok_or(QuarantineError::InvalidRecord)?;
        let mut next = self.snapshot.clone();
        append_tombstone(&mut next, &record, "consumed", now)?;
        next.records
            .retain(|candidate| candidate.adapter_event_id != adapter_event_id);
        self.snapshot = next;
        self.persist()
    }

    pub(crate) fn mark_retry(
        &mut self,
        adapter_event_id: &str,
        now: u64,
    ) -> Result<(), QuarantineError> {
        let record = self
            .snapshot
            .records
            .iter_mut()
            .find(|record| record.adapter_event_id == adapter_event_id)
            .ok_or(QuarantineError::InvalidRecord)?;
        record.attempt_count = record.attempt_count.saturating_add(1);
        record.last_attempt_at = Some(now);
        let exponent = u32::from(record.attempt_count.min(6));
        let delay = INITIAL_RETRY_DELAY_SECS
            .saturating_mul(2u64.saturating_pow(exponent))
            .min(MAX_RETRY_DELAY_SECS);
        record.eligible_after = now.saturating_add(delay).min(record.expires_at);
        self.persist()
    }

    #[cfg(test)]
    pub(crate) fn record_count(&self) -> usize {
        self.snapshot.records.len()
    }

    #[cfg(test)]
    pub(crate) fn tombstone_count(&self) -> usize {
        self.snapshot.tombstones.len()
    }

    #[cfg(test)]
    fn sender_policy(&self, sender: &[u8]) -> Option<&SenderIngressPolicyV1> {
        let sender = encode_hex(sender);
        self.snapshot
            .sender_policies
            .iter()
            .find(|policy| policy.authenticated_sender == sender)
    }

    fn persist(&self) -> Result<(), QuarantineError> {
        validate_snapshot(&self.snapshot, &self.scope)?;
        let _guard = REPOSITORY_LOCK.lock().map_err(|_| QuarantineError::Io)?;
        let parent = self
            .snapshot_path
            .parent()
            .ok_or(QuarantineError::InvalidScope)?;
        fs::create_dir_all(parent).map_err(|_| QuarantineError::Io)?;
        let plaintext = bincode::serialize(&self.snapshot).map_err(|_| QuarantineError::Corrupt)?;
        let aad = snapshot_associated_data(&self.scope);
        let sealed = seal_inbound_quarantine_snapshot(self.seed, aad.as_bytes(), &plaintext)
            .map_err(|_| QuarantineError::Crypto)?;
        atomic_write(&self.snapshot_path, &sealed)
    }
}

fn append_quarantine_record(
    snapshot: &mut InboundQuarantineSnapshotV1,
    scope: &InboundQuarantineScopeV1,
    seed: &Seed,
    adapter_event_id: &str,
    observed_by: &[String],
    envelope: &DeliveryEnvelope,
    reason: &str,
    now: u64,
) -> Result<(), QuarantineError> {
    validate_event_id(adapter_event_id)?;
    let authenticated_sender = encode_hex(&envelope.from);
    if let Some(existing) = snapshot
        .records
        .iter_mut()
        .find(|record| record.adapter_event_id == adapter_event_id)
    {
        if existing.authenticated_sender != authenticated_sender
            || existing.message_kind != envelope.kind
        {
            return Err(QuarantineError::InvalidRecord);
        }
        existing.observed_by = merge_observations(&existing.observed_by, observed_by);
        return Ok(());
    }

    if snapshot.records.len() >= MAX_RECORDS
        || snapshot
            .records
            .iter()
            .filter(|record| record.authenticated_sender == authenticated_sender)
            .count()
            >= MAX_RECORDS_PER_SENDER
    {
        return Err(QuarantineError::Capacity);
    }

    let stored_envelope = StoredInboundEnvelopeV1::from(envelope);
    let envelope_bytes =
        bincode::serialize(&stored_envelope).map_err(|_| QuarantineError::Corrupt)?;
    let record_aad = record_associated_data(scope, adapter_event_id);
    let envelope_ciphertext =
        seal_inbound_quarantine_record(seed, record_aad.as_bytes(), &envelope_bytes)
            .map_err(|_| QuarantineError::Crypto)?;
    let current_bytes = snapshot
        .records
        .iter()
        .map(|record| record.envelope_ciphertext.len())
        .sum::<usize>();
    if current_bytes.saturating_add(envelope_ciphertext.len()) > MAX_CIPHERTEXT_BYTES {
        return Err(QuarantineError::Capacity);
    }

    snapshot.records.push(InboundQuarantineRecordV1 {
        schema_version: SCHEMA_VERSION,
        scope: scope.clone(),
        adapter: ADAPTER.to_string(),
        adapter_event_id: adapter_event_id.to_string(),
        authenticated_sender,
        observed_by: merge_observations(&[], observed_by),
        message_kind: envelope.kind,
        reason: bounded_reason(reason),
        first_observed_at: now,
        quarantined_at: now,
        eligible_after: now.saturating_add(INITIAL_RETRY_DELAY_SECS),
        expires_at: now.saturating_add(PAYLOAD_RETENTION_SECS),
        attempt_count: 0,
        last_attempt_at: None,
        envelope_ciphertext,
    });
    snapshot
        .records
        .sort_by(|left, right| left.adapter_event_id.cmp(&right.adapter_event_id));
    Ok(())
}

fn maintain_sender_policy_state(snapshot: &mut InboundQuarantineSnapshotV1, now: u64) {
    for policy in &mut snapshot.sender_policies {
        policy.charged_events.retain(|evidence| {
            now.saturating_sub(evidence.charged_at) <= CHARGE_EVIDENCE_RETENTION_SECS
        });
        let elapsed = now.saturating_sub(policy.last_refill_at);
        let refill = elapsed / SENDER_POLICY_REFILL_SECS;
        if refill > 0 {
            policy.available_permits = policy
                .available_permits
                .saturating_add(refill.min(u64::from(u8::MAX)) as u8)
                .min(SENDER_POLICY_BURST);
            policy.last_refill_at = policy
                .last_refill_at
                .saturating_add(refill.saturating_mul(SENDER_POLICY_REFILL_SECS));
        }
    }
}

fn make_sender_policy_capacity(
    snapshot: &mut InboundQuarantineSnapshotV1,
) -> Result<(), QuarantineError> {
    if snapshot.sender_policies.len() < MAX_POLICY_SENDERS {
        return Ok(());
    }
    let removable = snapshot
        .sender_policies
        .iter()
        .enumerate()
        .filter(|(_, policy)| {
            policy.available_permits == SENDER_POLICY_BURST
                && policy.charged_events.is_empty()
                && !snapshot
                    .records
                    .iter()
                    .any(|record| record.authenticated_sender == policy.authenticated_sender)
        })
        .min_by_key(|(_, policy)| policy.last_activity_at)
        .map(|(index, _)| index);
    if let Some(index) = removable {
        snapshot.sender_policies.remove(index);
        Ok(())
    } else {
        Err(QuarantineError::Capacity)
    }
}

fn ensure_charge_evidence_capacity(
    snapshot: &InboundQuarantineSnapshotV1,
    policy_index: usize,
) -> Result<(), QuarantineError> {
    let policy = &snapshot.sender_policies[policy_index];
    let total = snapshot
        .sender_policies
        .iter()
        .map(|item| item.charged_events.len())
        .sum::<usize>();
    if total >= MAX_CHARGE_EVIDENCE || policy.charged_events.len() >= MAX_CHARGE_EVIDENCE_PER_SENDER
    {
        return Err(QuarantineError::Capacity);
    }
    let mut candidate = snapshot.sender_policies.clone();
    candidate[policy_index]
        .charged_events
        .push(SenderChargeEvidenceV1 {
            adapter_event_id: "capacity-probe".to_string(),
            charged_at: 0,
        });
    if bincode::serialize(&candidate)
        .map_err(|_| QuarantineError::Corrupt)?
        .len()
        > MAX_SENDER_POLICY_BYTES
    {
        return Err(QuarantineError::Capacity);
    }
    Ok(())
}

fn append_tombstone(
    snapshot: &mut InboundQuarantineSnapshotV1,
    record: &InboundQuarantineRecordV1,
    terminal_reason: &str,
    now: u64,
) -> Result<(), QuarantineError> {
    if snapshot
        .tombstones
        .iter()
        .any(|item| item.adapter_event_id == record.adapter_event_id)
    {
        return Ok(());
    }
    let tombstone = InboundQuarantineTombstoneV1 {
        schema_version: SCHEMA_VERSION,
        scope: record.scope.clone(),
        adapter: record.adapter.clone(),
        adapter_event_id: record.adapter_event_id.clone(),
        authenticated_sender: record.authenticated_sender.clone(),
        message_kind: record.message_kind,
        terminal_reason: terminal_reason.to_string(),
        first_observed_at: record.first_observed_at,
        terminal_at: now,
    };
    if snapshot.tombstones.len() >= MAX_TOMBSTONES {
        return Err(QuarantineError::TombstoneCapacity);
    }
    let current_bytes = bincode::serialize(&snapshot.tombstones)
        .map_err(|_| QuarantineError::Corrupt)?
        .len();
    let new_bytes = bincode::serialize(&tombstone)
        .map_err(|_| QuarantineError::Corrupt)?
        .len();
    if current_bytes.saturating_add(new_bytes) > MAX_TOMBSTONE_BYTES {
        return Err(QuarantineError::TombstoneCapacity);
    }
    snapshot.tombstones.push(tombstone);
    snapshot
        .tombstones
        .sort_by(|left, right| left.adapter_event_id.cmp(&right.adapter_event_id));
    Ok(())
}

fn application_storage_root() -> Result<PathBuf, QuarantineError> {
    APPLICATION_STORAGE_ROOT
        .lock()
        .map_err(|_| QuarantineError::Io)?
        .clone()
        .ok_or(QuarantineError::Uninitialized)
}

fn snapshot_path(scope: &InboundQuarantineScopeV1) -> Result<PathBuf, QuarantineError> {
    let root = application_storage_root()?;
    Ok(root
        .join("capsules")
        .join(&scope.capsule_id)
        .join("transport_quarantine")
        .join(scope.network.to_string())
        .join(&scope.transport_endpoint)
        .join(ADAPTER)
        .join(SNAPSHOT_FILE))
}

fn cleanup_temp_file(snapshot_path: &Path) -> Result<(), QuarantineError> {
    let parent = snapshot_path
        .parent()
        .ok_or(QuarantineError::InvalidScope)?;
    let temp = parent.join(SNAPSHOT_TEMP_FILE);
    if temp.exists() {
        fs::remove_file(temp).map_err(|_| QuarantineError::Io)?;
    }
    Ok(())
}

fn load_snapshot(
    path: &Path,
    scope: &InboundQuarantineScopeV1,
    seed: &Seed,
) -> Result<InboundQuarantineSnapshotV1, QuarantineError> {
    let sealed = fs::read(path).map_err(|_| QuarantineError::Io)?;
    let aad = snapshot_associated_data(scope);
    let plaintext = open_inbound_quarantine_snapshot(seed, aad.as_bytes(), &sealed)
        .map_err(|_| QuarantineError::Crypto)?;
    if let Ok(snapshot) = bincode::deserialize::<InboundQuarantineSnapshotV1>(&plaintext) {
        return Ok(snapshot);
    }
    let legacy: InboundQuarantineSnapshotPass15V1 =
        bincode::deserialize(&plaintext).map_err(|_| QuarantineError::Corrupt)?;
    Ok(InboundQuarantineSnapshotV1 {
        schema_version: legacy.schema_version,
        scope: legacy.scope,
        records: legacy.records,
        tombstones: legacy.tombstones,
        sender_policies: Vec::new(),
    })
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), QuarantineError> {
    let parent = path.parent().ok_or(QuarantineError::InvalidScope)?;
    let temp = parent.join(SNAPSHOT_TEMP_FILE);
    if temp.exists() {
        fs::remove_file(&temp).map_err(|_| QuarantineError::Io)?;
    }
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&temp)
        .map_err(|_| QuarantineError::Io)?;
    file.write_all(bytes).map_err(|_| QuarantineError::Io)?;
    file.sync_all().map_err(|_| QuarantineError::Io)?;
    fs::rename(&temp, path).map_err(|_| QuarantineError::Io)?;
    if let Ok(directory) = File::open(parent) {
        let _ = directory.sync_all();
    }
    Ok(())
}

fn validate_snapshot(
    snapshot: &InboundQuarantineSnapshotV1,
    scope: &InboundQuarantineScopeV1,
) -> Result<(), QuarantineError> {
    if snapshot.schema_version != SCHEMA_VERSION || &snapshot.scope != scope {
        return Err(QuarantineError::Corrupt);
    }
    if snapshot.records.len() > MAX_RECORDS
        || snapshot.tombstones.len() > MAX_TOMBSTONES
        || snapshot.sender_policies.len() > MAX_POLICY_SENDERS
    {
        return Err(QuarantineError::Corrupt);
    }
    let mut ids = BTreeSet::new();
    let mut sender_counts = BTreeMap::<&str, usize>::new();
    let mut ciphertext_bytes = 0usize;
    for record in &snapshot.records {
        if record.schema_version != SCHEMA_VERSION
            || record.scope != *scope
            || record.adapter != ADAPTER
            || !ids.insert(record.adapter_event_id.as_str())
            || record.observed_by.len() > MAX_OBSERVATIONS
            || record.expires_at
                != record
                    .first_observed_at
                    .saturating_add(PAYLOAD_RETENTION_SECS)
        {
            return Err(QuarantineError::Corrupt);
        }
        validate_event_id(&record.adapter_event_id)?;
        validate_hex32(&record.authenticated_sender)?;
        let sender_count = sender_counts
            .entry(record.authenticated_sender.as_str())
            .or_default();
        *sender_count += 1;
        if *sender_count > MAX_RECORDS_PER_SENDER {
            return Err(QuarantineError::Corrupt);
        }
        ciphertext_bytes = ciphertext_bytes.saturating_add(record.envelope_ciphertext.len());
    }
    if ciphertext_bytes > MAX_CIPHERTEXT_BYTES {
        return Err(QuarantineError::Corrupt);
    }
    for tombstone in &snapshot.tombstones {
        if tombstone.schema_version != SCHEMA_VERSION
            || tombstone.scope != *scope
            || tombstone.adapter != ADAPTER
            || !ids.insert(tombstone.adapter_event_id.as_str())
        {
            return Err(QuarantineError::Corrupt);
        }
        validate_event_id(&tombstone.adapter_event_id)?;
        validate_hex32(&tombstone.authenticated_sender)?;
    }
    if bincode::serialize(&snapshot.tombstones)
        .map_err(|_| QuarantineError::Corrupt)?
        .len()
        > MAX_TOMBSTONE_BYTES
    {
        return Err(QuarantineError::Corrupt);
    }
    let mut policy_senders = BTreeSet::new();
    let mut charged_ids = BTreeSet::new();
    let mut charged_count = 0usize;
    for policy in &snapshot.sender_policies {
        if policy.schema_version != SCHEMA_VERSION
            || policy.scope != *scope
            || policy.available_permits > SENDER_POLICY_BURST
            || !policy_senders.insert(policy.authenticated_sender.as_str())
            || policy.charged_events.len() > MAX_CHARGE_EVIDENCE_PER_SENDER
        {
            return Err(QuarantineError::Corrupt);
        }
        validate_hex32(&policy.authenticated_sender)?;
        for evidence in &policy.charged_events {
            validate_event_id(&evidence.adapter_event_id)?;
            if !charged_ids.insert(evidence.adapter_event_id.as_str()) {
                return Err(QuarantineError::Corrupt);
            }
        }
        charged_count = charged_count.saturating_add(policy.charged_events.len());
    }
    if charged_count > MAX_CHARGE_EVIDENCE
        || bincode::serialize(&snapshot.sender_policies)
            .map_err(|_| QuarantineError::Corrupt)?
            .len()
            > MAX_SENDER_POLICY_BYTES
    {
        return Err(QuarantineError::Corrupt);
    }
    Ok(())
}

fn validate_scope(scope: &InboundQuarantineScopeV1) -> Result<(), QuarantineError> {
    validate_hex32(&scope.capsule_id)?;
    validate_hex32(&scope.transport_endpoint)?;
    if scope.network > 1 {
        return Err(QuarantineError::InvalidScope);
    }
    Ok(())
}

fn validate_hex32(value: &str) -> Result<(), QuarantineError> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(QuarantineError::InvalidScope);
    }
    Ok(())
}

fn decode_hex32(value: &str) -> Result<Vec<u8>, QuarantineError> {
    validate_hex32(value)?;
    let mut decoded = Vec::with_capacity(32);
    for chunk in value.as_bytes().chunks_exact(2) {
        let pair = std::str::from_utf8(chunk).map_err(|_| QuarantineError::InvalidScope)?;
        decoded.push(u8::from_str_radix(pair, 16).map_err(|_| QuarantineError::InvalidScope)?);
    }
    Ok(decoded)
}

fn validate_event_id(value: &str) -> Result<(), QuarantineError> {
    if value.is_empty()
        || value.len() > MAX_EVENT_ID_LEN
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b':'))
    {
        return Err(QuarantineError::InvalidRecord);
    }
    Ok(())
}

fn merge_observations(existing: &[String], incoming: &[String]) -> Vec<String> {
    existing
        .iter()
        .chain(incoming.iter())
        .filter(|value| !value.is_empty() && value.len() <= MAX_ENDPOINT_LEN)
        .cloned()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .take(MAX_OBSERVATIONS)
        .collect()
}

fn bounded_reason(value: &str) -> String {
    value.chars().take(96).collect()
}

fn snapshot_associated_data(scope: &InboundQuarantineScopeV1) -> String {
    format!(
        "hivra:inbound-quarantine:snapshot:v1:{}:{}:{}:{}",
        scope.capsule_id, scope.network, scope.transport_endpoint, ADAPTER
    )
}

fn record_associated_data(scope: &InboundQuarantineScopeV1, event_id: &str) -> String {
    format!(
        "hivra:inbound-quarantine:record:v1:{}:{}:{}:{}:{}",
        scope.capsule_id, scope.network, scope.transport_endpoint, ADAPTER, event_id
    )
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[no_mangle]
pub unsafe extern "C" fn hivra_set_application_storage_root(path: *const c_char) -> i32 {
    clear_last_error();
    if path.is_null() {
        set_last_error("Application storage root initialization failed: null path");
        return -1;
    }
    let raw = match CStr::from_ptr(path).to_str() {
        Ok(value) => value,
        Err(_) => {
            set_last_error("Application storage root initialization failed: invalid UTF-8");
            return -2;
        }
    };
    match set_application_storage_root(Path::new(raw)) {
        Ok(()) => 0,
        Err(error) => {
            set_last_error(format!(
                "Application storage root initialization failed: {error}"
            ));
            -3
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn hivra_delete_inbound_quarantine(capsule_id_ptr: *const u8) -> i32 {
    clear_last_error();
    if capsule_id_ptr.is_null() {
        set_last_error("Inbound quarantine deletion failed: null Capsule id");
        return -1;
    }
    let capsule_id = encode_hex(std::slice::from_raw_parts(capsule_id_ptr, 32));
    match delete_capsule_quarantine(&capsule_id) {
        Ok(()) => 0,
        Err(error) => {
            set_last_error(format!("Inbound quarantine deletion failed: {error}"));
            -2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn scope(capsule: u8, endpoint: u8) -> InboundQuarantineScopeV1 {
        InboundQuarantineScopeV1 {
            capsule_id: encode_hex(&[capsule; 32]),
            network: 1,
            transport_endpoint: encode_hex(&[endpoint; 32]),
        }
    }

    fn envelope(sender: u8, recipient: u8, kind: u32) -> DeliveryEnvelope {
        DeliveryEnvelope {
            schema_version: 1,
            from: [sender; 32],
            to: [recipient; 32],
            kind,
            payload: b"secret-payload-marker".to_vec(),
            timestamp: 100,
            correlation_id: None,
            domain_event: None,
        }
    }

    #[test]
    fn encrypted_snapshot_round_trips_without_plaintext_residue() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([3; 32]);
        let scope = scope(1, 2);
        let mut repository =
            CapsuleInboundQuarantineRepository::open(scope.clone(), &seed).unwrap();
        repository
            .quarantine(
                "event-1",
                &["wss://relay.example".to_string()],
                &envelope(4, 2, 7),
                "canonical_route_retry",
                1_000,
            )
            .unwrap();
        let raw = fs::read(&repository.snapshot_path).unwrap();
        assert!(!raw
            .windows(21)
            .any(|window| window == b"secret-payload-marker"));

        let reopened = CapsuleInboundQuarantineRepository::open(scope, &seed).unwrap();
        assert_eq!(reopened.record_count(), 1);
        assert!(reopened.next_eligible(1_014).unwrap().is_none());
        let recovered = reopened.next_eligible(1_015).unwrap().unwrap();
        assert_eq!(recovered.adapter_event_id, "event-1");
        assert_eq!(recovered.envelope.payload, b"secret-payload-marker");
    }

    #[test]
    fn duplicate_event_merges_bounded_provenance_without_resetting_expiry() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([4; 32]);
        let scope = scope(2, 3);
        let mut repository = CapsuleInboundQuarantineRepository::open(scope, &seed).unwrap();
        repository
            .quarantine(
                "same-event",
                &["relay-a".to_string()],
                &envelope(5, 3, 8),
                "retry",
                10,
            )
            .unwrap();
        let original_expiry = repository.snapshot.records[0].expires_at;
        let observations = (0..32)
            .map(|index| format!("relay-{index}"))
            .collect::<Vec<_>>();
        repository
            .quarantine("same-event", &observations, &envelope(5, 3, 8), "retry", 20)
            .unwrap();
        assert_eq!(repository.record_count(), 1);
        assert_eq!(repository.snapshot.records[0].expires_at, original_expiry);
        assert_eq!(
            repository.snapshot.records[0].observed_by.len(),
            MAX_OBSERVATIONS
        );
    }

    #[test]
    fn sender_capacity_returns_backpressure_without_eviction() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([5; 32]);
        let mut repository = CapsuleInboundQuarantineRepository::open(scope(3, 4), &seed).unwrap();
        for index in 0..MAX_RECORDS_PER_SENDER {
            repository
                .quarantine(
                    &format!("event-{index}"),
                    &[],
                    &envelope(6, 4, 9),
                    "retry",
                    100,
                )
                .unwrap();
        }
        assert!(matches!(
            repository.quarantine("overflow", &[], &envelope(6, 4, 9), "retry", 100),
            Err(QuarantineError::Capacity)
        ));
        assert_eq!(repository.record_count(), MAX_RECORDS_PER_SENDER);
    }

    #[test]
    fn expiry_and_consumption_replace_ciphertext_with_tombstones() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([6; 32]);
        let scope = scope(4, 5);
        let mut repository =
            CapsuleInboundQuarantineRepository::open(scope.clone(), &seed).unwrap();
        repository
            .quarantine("expired", &[], &envelope(7, 5, 10), "retry", 1)
            .unwrap();
        assert_eq!(
            repository.expire_due(1 + PAYLOAD_RETENTION_SECS).unwrap(),
            1
        );
        assert_eq!(repository.record_count(), 0);
        assert_eq!(repository.tombstone_count(), 1);

        repository
            .quarantine("consumed", &[], &envelope(8, 5, 10), "retry", 10)
            .unwrap();
        repository.mark_consumed("consumed", 30).unwrap();
        assert_eq!(repository.record_count(), 0);
        assert_eq!(repository.tombstone_count(), 2);
        let reopened = CapsuleInboundQuarantineRepository::open(scope, &seed).unwrap();
        assert_eq!(reopened.tombstone_count(), 2);
    }

    #[test]
    fn corruption_and_wrong_scope_fail_closed() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([7; 32]);
        let scope = scope(5, 6);
        let mut repository =
            CapsuleInboundQuarantineRepository::open(scope.clone(), &seed).unwrap();
        repository
            .quarantine("event", &[], &envelope(9, 6, 11), "retry", 10)
            .unwrap();
        fs::write(&repository.snapshot_path, b"corrupt").unwrap();
        assert!(CapsuleInboundQuarantineRepository::open(scope, &seed).is_err());
    }

    #[test]
    fn capsule_deletion_removes_only_its_quarantine_tree() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([8; 32]);
        let first = scope(6, 7);
        let second = scope(8, 9);
        let mut first_repository =
            CapsuleInboundQuarantineRepository::open(first.clone(), &seed).unwrap();
        first_repository
            .quarantine("first", &[], &envelope(10, 7, 12), "retry", 10)
            .unwrap();
        let mut second_repository =
            CapsuleInboundQuarantineRepository::open(second.clone(), &seed).unwrap();
        second_repository
            .quarantine("second", &[], &envelope(11, 9, 12), "retry", 10)
            .unwrap();

        delete_capsule_quarantine(&first.capsule_id).unwrap();
        assert!(!first_repository.snapshot_path.exists());
        assert!(second_repository.snapshot_path.exists());
    }

    #[test]
    fn sender_policy_persists_burst_refill_and_exact_event_charging() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([12; 32]);
        let scope = scope(12, 13);
        let mut repository =
            CapsuleInboundQuarantineRepository::open(scope.clone(), &seed).unwrap();

        for index in 0..SENDER_POLICY_BURST {
            assert_eq!(
                repository
                    .apply_sender_policy(
                        &format!("policy-{index}"),
                        &[],
                        &envelope(14, 13, u32::from(index)),
                        100,
                    )
                    .unwrap(),
                SenderIngressDecision::Permit
            );
        }
        assert_eq!(
            repository
                .apply_sender_policy("policy-throttled", &[], &envelope(14, 13, 9), 100)
                .unwrap(),
            SenderIngressDecision::Quarantined
        );
        assert_eq!(repository.record_count(), 1);
        assert_eq!(
            repository
                .sender_policy(&[14; 32])
                .unwrap()
                .available_permits,
            0
        );

        let mut reopened = CapsuleInboundQuarantineRepository::open(scope, &seed).unwrap();
        assert_eq!(
            reopened
                .apply_sender_policy("policy-0", &[], &envelope(14, 13, 99), 100)
                .unwrap(),
            SenderIngressDecision::AlreadyCharged
        );
        assert_eq!(
            reopened.sender_policy(&[14; 32]).unwrap().available_permits,
            0
        );
        assert_eq!(
            reopened
                .apply_sender_policy("policy-after-refill", &[], &envelope(14, 13, 99), 115)
                .unwrap(),
            SenderIngressDecision::Permit
        );
        assert_eq!(
            reopened.sender_policy(&[14; 32]).unwrap().available_permits,
            0
        );
    }

    #[test]
    fn sender_policy_has_no_message_kind_or_sender_bypass() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([15; 32]);
        let mut repository =
            CapsuleInboundQuarantineRepository::open(scope(15, 16), &seed).unwrap();

        for index in 0..SENDER_POLICY_BURST {
            assert_eq!(
                repository
                    .apply_sender_policy(
                        &format!("mixed-{index}"),
                        &[],
                        &envelope(17, 16, 4_096 + u32::from(index)),
                        200,
                    )
                    .unwrap(),
                SenderIngressDecision::Permit
            );
        }
        assert_eq!(
            repository
                .apply_sender_policy("mixed-overflow", &[], &envelope(17, 16, 1), 200)
                .unwrap(),
            SenderIngressDecision::Quarantined
        );
        assert_eq!(
            repository
                .apply_sender_policy("other-sender", &[], &envelope(18, 16, 1), 200)
                .unwrap(),
            SenderIngressDecision::Permit
        );
    }

    #[test]
    fn pass15_snapshot_migrates_without_rewriting_quarantine_evidence() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([19; 32]);
        let scope = scope(19, 20);
        let mut repository =
            CapsuleInboundQuarantineRepository::open(scope.clone(), &seed).unwrap();
        repository
            .quarantine("legacy-record", &[], &envelope(21, 20, 7), "retry", 10)
            .unwrap();
        let legacy = InboundQuarantineSnapshotPass15V1 {
            schema_version: repository.snapshot.schema_version,
            scope: repository.snapshot.scope.clone(),
            records: repository.snapshot.records.clone(),
            tombstones: repository.snapshot.tombstones.clone(),
        };
        let plaintext = bincode::serialize(&legacy).unwrap();
        let aad = snapshot_associated_data(&scope);
        let sealed = seal_inbound_quarantine_snapshot(&seed, aad.as_bytes(), &plaintext).unwrap();
        atomic_write(&repository.snapshot_path, &sealed).unwrap();

        let migrated = CapsuleInboundQuarantineRepository::open(scope, &seed).unwrap();
        assert_eq!(migrated.record_count(), 1);
        assert!(migrated.snapshot.sender_policies.is_empty());
    }

    #[test]
    fn sender_policy_capacity_fails_closed_without_evicting_active_state() {
        let _guard = TEST_LOCK.lock().unwrap();
        let root = tempdir().unwrap();
        set_application_storage_root(root.path()).unwrap();
        let seed = Seed::new([22; 32]);
        let scope = scope(22, 23);
        let mut repository =
            CapsuleInboundQuarantineRepository::open(scope.clone(), &seed).unwrap();
        repository.snapshot.sender_policies = (0..MAX_POLICY_SENDERS)
            .map(|index| SenderIngressPolicyV1 {
                schema_version: SCHEMA_VERSION,
                scope: scope.clone(),
                authenticated_sender: format!("{index:064x}"),
                available_permits: SENDER_POLICY_BURST - 1,
                last_refill_at: 500,
                last_activity_at: 500,
                charged_events: vec![SenderChargeEvidenceV1 {
                    adapter_event_id: format!("active-{index}"),
                    charged_at: 500,
                }],
            })
            .collect();

        assert!(matches!(
            repository.apply_sender_policy("new-sender", &[], &envelope(24, 23, 1), 500),
            Err(QuarantineError::Capacity)
        ));
        assert_eq!(
            repository.snapshot.sender_policies.len(),
            MAX_POLICY_SENDERS
        );
    }
}
