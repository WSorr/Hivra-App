//! Nostr transport adapter

use crate::{
    DeliveryEnvelope, DeliveryReceipt, InboundDeliveryBatch, InboundDeliveryDisposition,
    InboundDeliveryItem, InboundDeliveryPayload, InboundDeliveryResolution, InboundEnvelopeGuard,
    Transport, TransportError, MAX_DELIVERY_ENVELOPE_PAYLOAD_BYTES,
};
use futures::future::join_all;
use futures::stream::{FuturesUnordered, StreamExt};
use nostr_sdk::nips::{nip04, nip44};
use nostr_sdk::prelude::*;
use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};
use tokio::runtime::{Builder, Runtime};
use tokio::time;

// Hivra uses one regular application event kind for authenticated NIP-44 v2
// delivery envelopes. Deprecated kind-4/NIP-04 events are receive-only
// compatibility input and are never emitted by this adapter.
const APP_EVENT_KIND: Kind = Kind::Custom(9444);
const LEGACY_NIP04_EVENT_KIND: Kind = Kind::Custom(4);
const CONNECT_POLL_MS: u64 = 250;
const RECEIVE_LIMIT: usize = 2048;
const RECEIVE_LOOKBACK_SECS: u64 = 7 * 24 * 60 * 60;
const RECEIVE_FUTURE_SKEW_SECS: u64 = 5 * 60;
const RECEIVE_SEEN_CAPACITY: usize = 2048;
// JSON byte arrays plus encrypted base64 framing are substantially larger than
// the opaque Hivra payload. Reject pathological wire content before decrypt.
const MAX_NOSTR_EVENT_CONTENT_BYTES: usize = MAX_DELIVERY_ENVELOPE_PAYLOAD_BYTES * 8;
const MIN_PUBLISH_TIMEOUT_SECS: u64 = 2;
const MIN_RECEIVE_CONNECTED_RELAYS: usize = 2;
const RECEIVE_RELAY_SETTLE_SECS: u64 = 2;
// These relays retain Hivra history reliably in the current public pool.
// Reads still fall back to every connected configured relay.
const PREFERRED_READ_RELAYS: [&str; 2] = ["wss://relay.damus.io", "wss://relay.primal.net"];

static SEEN_EVENT_IDS: OnceLock<Mutex<HashMap<[u8; 32], HashSet<String>>>> = OnceLock::new();

fn seen_event_ids() -> &'static Mutex<HashMap<[u8; 32], HashSet<String>>> {
    SEEN_EVENT_IDS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_receive_cursor(current: u64, query_now: u64, max_event_timestamp: u64) -> u64 {
    // Relay data is untrusted. A future-dated event must not move the cursor
    // beyond this query and hide later envelopes with valid timestamps.
    current.max(max_event_timestamp.min(query_now).saturating_sub(1))
}

fn prioritize_read_relay_urls(mut relay_urls: Vec<String>) -> Vec<String> {
    relay_urls.sort_by_key(|url| {
        PREFERRED_READ_RELAYS
            .iter()
            .position(|preferred| url == preferred)
            .unwrap_or(PREFERRED_READ_RELAYS.len())
    });
    relay_urls
}

fn looks_like_nip04_content(content: &str) -> bool {
    let mut parts = content.splitn(2, "?iv=");
    let cipher = parts.next().unwrap_or_default();
    let iv = parts.next().unwrap_or_default();

    // NIP-04 requires a 16-byte IV. In base64 that is typically 22-24 chars.
    !cipher.is_empty() && iv.len() >= 22
}

fn has_exact_recipient_tag(event: &Event, recipient: PublicKey) -> bool {
    let mut raw_recipient_tags = event.tags.filter(TagKind::p());
    if raw_recipient_tags.next().is_none() || raw_recipient_tags.next().is_some() {
        return false;
    }

    let mut recipients = event.tags.public_keys();
    recipients.next().copied() == Some(recipient) && recipients.next().is_none()
}

fn extract_auth_challenge(reason: &str) -> Option<String> {
    let needle = "auth-required:";
    let idx = reason.find(needle)?;
    let challenge = reason[idx + needle.len()..].trim();
    if challenge.is_empty() {
        None
    } else {
        Some(challenge.to_string())
    }
}

#[derive(Debug, Clone)]
pub struct NostrConfig {
    pub relays: Vec<String>,
    pub ephemeral: bool,
    /// Budget for fetching stored relay events.
    pub timeout: u64,
    /// Budget for an interactive publish to receive the first relay `OK`.
    pub publish_timeout: u64,
}

impl Default for NostrConfig {
    fn default() -> Self {
        Self {
            relays: vec![
                "wss://nos.lol".into(),
                "wss://relay.damus.io".into(),
                "wss://relay.primal.net".into(),
                "wss://relay.snort.social".into(),
                "wss://relay.nostr.band".into(),
                "wss://relay.current.fyi".into(),
            ],
            ephemeral: true,
            // Keep receive reliable across slower relay handshakes.
            timeout: 12,
            // Durable/default callers may wait longer for a relay receipt.
            publish_timeout: 6,
        }
    }
}

impl NostrConfig {
    pub fn quick_launch() -> Self {
        Self {
            relays: vec![
                "wss://nos.lol".into(),
                "wss://relay.damus.io".into(),
                "wss://relay.primal.net".into(),
                "wss://relay.snort.social".into(),
                "wss://relay.nostr.band".into(),
                "wss://relay.current.fyi".into(),
            ],
            ephemeral: true,
            // Quick profile is still user-facing fast path, but must be long
            // enough for real relay handshakes on mobile networks.
            timeout: 8,
            // A local ledger/outbox can recover Core effects after this
            // budget. Interactive UI must not wait behind a slow relay.
            publish_timeout: 3,
        }
    }
}

pub struct NostrTransport {
    runtime: Runtime,
    client: Client,
    keys: Keys,
    public_key: PublicKey,
    publish_timeout_secs: u64,
    // Relay histories replicate asynchronously. A cursor shared by every
    // relay can skip a valid event that arrives late on a second relay.
    receive_since_by_relay: Mutex<HashMap<String, u64>>,
    next_receive_batch_id: Mutex<u64>,
    pending_receive_batch: Mutex<Option<PendingReceiveBatch>>,
    last_receive_diagnostic: Mutex<String>,
}

#[derive(Clone)]
struct PendingRelayCursor {
    candidate: u64,
    event_ids: HashSet<String>,
}

#[derive(Clone)]
struct PendingReceiveBatch {
    batch: InboundDeliveryBatch,
    relay_cursors: HashMap<String, PendingRelayCursor>,
}

struct RelayFetch {
    relay_url: String,
    events: Vec<Event>,
}

impl NostrTransport {
    pub fn new(config: NostrConfig, secret_key: &[u8; 32]) -> Result<Self, TransportError> {
        eprintln!("[Nostr] Creating transport with external secret key");

        let secret = SecretKey::from_slice(secret_key).map_err(|e| {
            eprintln!("[Nostr] Invalid secret key: {:?}", e);
            TransportError::InvalidKey
        })?;
        let keys = Keys::new(secret);
        let public_key = keys.public_key();

        eprintln!(
            "[Nostr] Public key: {}",
            public_key.to_bech32().unwrap_or("invalid".into())
        );

        let runtime = Self::build_runtime()?;
        let client = Self::build_client(&runtime, &config, &keys)?;

        eprintln!("[Nostr] Transport ready");

        Ok(Self {
            runtime,
            client,
            keys,
            public_key,
            publish_timeout_secs: config.publish_timeout,
            receive_since_by_relay: Mutex::new(HashMap::new()),
            next_receive_batch_id: Mutex::new(1),
            pending_receive_batch: Mutex::new(None),
            last_receive_diagnostic: Mutex::new(String::new()),
        })
    }

    pub fn new_with_keys(
        config: NostrConfig,
        secret_key: &[u8; 32],
    ) -> Result<Self, TransportError> {
        Self::new(config, secret_key)
    }

    fn build_runtime() -> Result<Runtime, TransportError> {
        Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .map_err(|_| TransportError::ConnectionFailed)
    }

    fn build_client(
        runtime: &Runtime,
        config: &NostrConfig,
        keys: &Keys,
    ) -> Result<Client, TransportError> {
        let client = Client::new(keys.clone());
        client.automatic_authentication(true);

        for relay_url in &config.relays {
            eprintln!("[Nostr] Adding relay: {}", relay_url);
            runtime.block_on(client.add_relay(relay_url)).map_err(|e| {
                eprintln!("[Nostr] Failed to add relay {}: {:?}", relay_url, e);
                TransportError::ConnectionFailed
            })?;
        }

        eprintln!("[Nostr] Connecting to relays...");
        runtime.block_on(client.connect());

        // Connection establishment continues in the client runtime. Send and
        // receive each apply their own operation budget, so merely creating a
        // cached transport never blocks a user action on a relay handshake.

        Ok(client)
    }

    fn wait_for_connected_relays_until(
        runtime: &Runtime,
        client: &Client,
        deadline: Instant,
    ) -> bool {
        loop {
            let relays = runtime.block_on(client.relays());
            let connected = relays
                .values()
                .any(|relay| matches!(relay.status(), RelayStatus::Connected));

            if connected {
                return true;
            }

            if Instant::now() >= deadline {
                return false;
            }

            runtime.block_on(client.connect());
            thread::sleep(Duration::from_millis(CONNECT_POLL_MS));
        }
    }

    fn connected_relay_count(runtime: &Runtime, client: &Client) -> usize {
        runtime
            .block_on(client.relays())
            .values()
            .filter(|relay| matches!(relay.status(), RelayStatus::Connected))
            .count()
    }

    fn configured_relay_urls(&self) -> Vec<String> {
        let relay_urls = self
            .runtime
            .block_on(self.client.relays())
            .into_values()
            .map(|relay| relay.url().to_string())
            .collect();
        prioritize_read_relay_urls(relay_urls)
    }

    fn ensure_connected_relays(&self, receive_timeout_secs: u64) -> bool {
        // A fetch launched as soon as the first relay connects can complete
        // against an empty relay before the relays that retained the event
        // finish their handshakes. Wait briefly for a second reader, but keep
        // degraded one-relay operation available after the settle window.
        let settle_secs = receive_timeout_secs.min(RECEIVE_RELAY_SETTLE_SECS).max(1);
        let deadline = Instant::now() + Duration::from_secs(settle_secs);
        loop {
            let connected = Self::connected_relay_count(&self.runtime, &self.client);
            if connected >= MIN_RECEIVE_CONNECTED_RELAYS {
                return true;
            }
            if Instant::now() >= deadline {
                return connected > 0;
            }
            self.runtime.block_on(self.client.connect());
            thread::sleep(Duration::from_millis(CONNECT_POLL_MS));
        }
    }

    pub fn public_key_bytes(&self) -> [u8; 32] {
        self.public_key.to_bytes()
    }

    pub fn last_receive_diagnostic(&self) -> String {
        self.last_receive_diagnostic
            .lock()
            .map(|value| value.clone())
            .unwrap_or_default()
    }

    /// Returns the Nostr event kind used by Hivra messages.
    pub fn event_kind() -> Kind {
        APP_EVENT_KIND
    }

    /// Serializes a transport message into Nostr event content.
    ///
    /// New outbound envelopes always use NIP-44 v2 authenticated encryption.
    pub fn serialize_message(&self, envelope: &DeliveryEnvelope) -> Result<String, TransportError> {
        let plaintext =
            serde_json::to_string(envelope).map_err(|_| TransportError::EncodingFailed)?;
        let recipient =
            PublicKey::from_slice(&envelope.to).map_err(|_| TransportError::InvalidKey)?;
        nip44::encrypt(
            self.keys.secret_key(),
            &recipient,
            plaintext.as_bytes(),
            nip44::Version::V2,
        )
        .map_err(|_| TransportError::EncodingFailed)
    }

    /// Builds Nostr tags for a transport message.
    pub fn message_tags(&self, envelope: &DeliveryEnvelope) -> Result<Vec<Tag>, TransportError> {
        let recipient_pubkey = PublicKey::from_slice(&envelope.to).map_err(|e| {
            eprintln!("[Nostr] Invalid recipient pubkey: {:?}", e);
            TransportError::InvalidKey
        })?;

        Ok(vec![Tag::public_key(recipient_pubkey)])
    }

    /// Creates an unsigned `EventBuilder` from a transport message.
    ///
    /// This method exists so upper layers can sign outside of transport,
    /// then submit the fully signed event via `send_event`.
    pub fn event_builder_for_message(
        &self,
        envelope: &DeliveryEnvelope,
    ) -> Result<EventBuilder, TransportError> {
        let content = self.serialize_message(envelope)?;
        let tags = self.message_tags(envelope)?;
        Ok(EventBuilder::new(APP_EVENT_KIND, content, tags))
    }

    fn build_signed_event(&self, content: String, tags: Vec<Tag>) -> Result<Event, TransportError> {
        eprintln!(
            "[Nostr] Creating event with kind: {}",
            APP_EVENT_KIND.as_u16()
        );

        self.runtime
            .block_on(EventBuilder::new(APP_EVENT_KIND, content, tags).sign(&self.keys))
            .map_err(|e| {
                eprintln!("[Nostr] Signing failed: {:?}", e);
                TransportError::EncodingFailed
            })
    }

    fn encode_message(&self, envelope: DeliveryEnvelope) -> Result<Event, TransportError> {
        eprintln!("[Nostr] Encoding envelope to: {:?}", &envelope.to[..4]);

        let content = self.serialize_message(&envelope)?;
        eprintln!("[Nostr] Message content: {}", content);

        let tags = self.message_tags(&envelope)?;
        let event = self.build_signed_event(content, tags)?;

        eprintln!("[Nostr] Event ID: {}", event.id.to_hex());
        Ok(event)
    }

    /// Prepares a signed Nostr event using an external signer.
    ///
    /// This is the migration path toward keeping signing in upper layers.
    pub fn prepare_event<S>(
        &self,
        envelope: &DeliveryEnvelope,
        signer: S,
    ) -> Result<Event, TransportError>
    where
        S: FnOnce(EventBuilder) -> Result<Event, TransportError>,
    {
        let builder = self.event_builder_for_message(envelope)?;
        signer(builder)
    }

    /// Sends a message using an externally signed Nostr event.
    pub fn send_prepared<S>(
        &self,
        envelope: &DeliveryEnvelope,
        signer: S,
    ) -> Result<(), TransportError>
    where
        S: FnOnce(EventBuilder) -> Result<Event, TransportError>,
    {
        let event = self.prepare_event(envelope, signer)?;
        self.send_event(event)
    }

    pub fn send_event(&self, event: Event) -> Result<(), TransportError> {
        self.publish_event_with_timeout(event, self.publish_timeout_secs)
            .map(|_| ())
    }

    fn publish_event_with_timeout(
        &self,
        event: Event,
        publish_timeout_secs: u64,
    ) -> Result<(String, String, u32), TransportError> {
        let publish_timeout_secs = publish_timeout_secs.max(MIN_PUBLISH_TIMEOUT_SECS);
        // Connection and relay acknowledgement share one interactive budget.
        // Giving each phase the full duration made a nominal 3s publish wait
        // for up to 6s before its caller could hand durable work to the outbox.
        let publish_deadline = Instant::now() + Duration::from_secs(publish_timeout_secs);
        if !Self::wait_for_connected_relays_until(&self.runtime, &self.client, publish_deadline) {
            eprintln!(
                "[Nostr] No connected relays available within publish budget {}s",
                publish_timeout_secs
            );
            return Err(TransportError::ConnectionFailed);
        }
        let relays = self.runtime.block_on(self.client.relays());
        let connected_relays: Vec<_> = relays
            .into_values()
            .filter(|relay| matches!(relay.status(), RelayStatus::Connected))
            .collect();

        if connected_relays.is_empty() {
            let reason = "no connected relays available for publish".to_string();
            eprintln!("[Nostr] {}", reason);
            return Err(TransportError::Other(reason));
        }

        let per_relay_timeout = publish_deadline.saturating_duration_since(Instant::now());
        if per_relay_timeout.is_zero() {
            return Err(TransportError::Timeout);
        }
        let publish_result = self.runtime.block_on(async {
            let mut pending = FuturesUnordered::new();
            for relay in connected_relays {
                let relay_url = relay.url().to_string();
                let event = event.clone();
                pending.push(async move {
                    let result = time::timeout(per_relay_timeout, relay.send_event(event)).await;
                    (relay_url, result)
                });
            }

            let mut first_accept: Option<(String, String)> = None;
            let mut accepted_relays = 0u32;
            let mut failure_details: Vec<String> = Vec::new();
            while let Some((relay_url, result)) = pending.next().await {
                match result {
                    Ok(Ok(event_id)) => {
                        accepted_relays += 1;
                        if first_accept.is_none() {
                            first_accept = Some((relay_url, event_id.to_hex()));
                        }
                    }
                    Err(_) => {
                        failure_details.push(format!(
                            "{}: timeout after {}s",
                            relay_url,
                            per_relay_timeout.as_secs()
                        ));
                    }
                    Ok(Err(err)) => {
                        let reason = err.to_string();
                        if let Some(challenge) = extract_auth_challenge(&reason) {
                            eprintln!(
                                "[Nostr] Relay {} returned auth challenge marker: {}",
                                relay_url, challenge
                            );
                        }
                        failure_details.push(format!("{}: {}", relay_url, reason));
                    }
                }
            }

            match first_accept {
                Some((relay_url, event_id)) => {
                    Ok((relay_url, event_id, accepted_relays, failure_details))
                }
                None => Err(failure_details),
            }
        });

        if let Ok((relay_url, event_id, accepted_relays, failure_details)) = publish_result {
            eprintln!(
                "[Nostr] Published event {} to {}/{} connected relay(s); first acceptance: {}",
                event_id,
                accepted_relays,
                accepted_relays + failure_details.len() as u32,
                relay_url,
            );
            let failed_before_accept = failure_details.len() as u32;
            if !failure_details.is_empty() {
                eprintln!(
                    "[Nostr] Message published with {} relay(s) failing during fan-out",
                    failure_details.len()
                );
            }
            return Ok((relay_url, event_id, failed_before_accept));
        }

        let failure_details = publish_result.err().unwrap_or_default();
        let reason = format!("no relay accepted event; {}", failure_details.join(" | "));
        eprintln!("[Nostr] Send failed: {}", reason);
        Err(TransportError::Other(reason))
    }

    pub fn send_with_receipt_with_timeout(
        &self,
        envelope: DeliveryEnvelope,
        publish_timeout_secs: u64,
    ) -> Result<DeliveryReceipt, TransportError> {
        eprintln!("[Nostr] Sending message...");
        let message_kind = envelope.kind;
        let recipient = envelope.to.to_vec();
        let event = self.encode_message(envelope)?;
        let (accepted_by, envelope_id, failed_before_accept) =
            self.publish_event_with_timeout(event, publish_timeout_secs)?;
        Ok(DeliveryReceipt {
            transport: self.name().to_string(),
            accepted_by,
            envelope_id,
            message_kind,
            recipient,
            failed_before_accept,
        })
    }

    pub fn receive_batch_with_timeout(
        &self,
        receive_timeout_secs: u64,
    ) -> Result<InboundDeliveryBatch, TransportError> {
        eprintln!("[Nostr] Receiving messages...");

        if let Ok(pending) = self.pending_receive_batch.lock() {
            if let Some(pending) = pending.as_ref() {
                if let Ok(mut current) = self.last_receive_diagnostic.lock() {
                    *current = format!(
                        "pending_batch={}; unresolved={}",
                        pending.batch.batch_id,
                        pending.batch.items.len()
                    );
                }
                return Ok(pending.batch.clone());
            }
        }

        if !self.ensure_connected_relays(receive_timeout_secs) {
            eprintln!("[Nostr] No connected relays available for receive");
            let batch = InboundDeliveryBatch {
                batch_id: self.take_next_receive_batch_id(),
                items: Vec::new(),
            };
            *self
                .pending_receive_batch
                .lock()
                .expect("pending receive batch mutex poisoned") = Some(PendingReceiveBatch {
                batch: batch.clone(),
                relay_cursors: HashMap::new(),
            });
            return Ok(batch);
        }

        let query_now = Timestamp::now().as_u64();
        let relay_urls = self.configured_relay_urls();
        if relay_urls.is_empty() {
            return Err(TransportError::ReceiveFailed);
        }
        let fetch_timeout = Duration::from_secs(receive_timeout_secs);
        let (relay_fetches, successful_reads, relay_diagnostics) =
            self.fetch_events_from_relays(relay_urls, query_now, fetch_timeout);

        if successful_reads == 0 {
            return Err(TransportError::ReceiveFailed);
        }

        let fetched_count = relay_fetches
            .iter()
            .map(|fetch| fetch.events.len())
            .sum::<usize>();
        eprintln!("[Nostr] Received {} events", fetched_count);

        let mut seen_guard = seen_event_ids().lock().expect("seen ids mutex poisoned");
        let seen_for_pubkey = seen_guard
            .entry(self.public_key_bytes())
            .or_insert_with(HashSet::new);
        let mut events_by_id: HashMap<String, (Event, HashSet<String>)> = HashMap::new();
        let mut relay_cursors = HashMap::new();
        let mut replayed = 0usize;
        for fetch in relay_fetches {
            let candidate = fetch
                .events
                .iter()
                .map(|event| event.created_at.as_u64())
                .max()
                .map(|max_timestamp| {
                    next_receive_cursor(
                        self.receive_since_for_relay(&fetch.relay_url),
                        query_now,
                        max_timestamp,
                    )
                });
            let mut unresolved_event_ids = HashSet::new();
            for event in fetch.events {
                let event_id = event.id.to_hex();
                if seen_for_pubkey.contains(&event_id) {
                    replayed += 1;
                    continue;
                }
                unresolved_event_ids.insert(event_id.clone());
                events_by_id
                    .entry(event_id)
                    .and_modify(|(_, relays)| {
                        relays.insert(fetch.relay_url.clone());
                    })
                    .or_insert_with(|| {
                        let mut relays = HashSet::new();
                        relays.insert(fetch.relay_url.clone());
                        (event, relays)
                    });
            }
            if let Some(candidate) = candidate {
                relay_cursors.insert(
                    fetch.relay_url,
                    PendingRelayCursor {
                        candidate,
                        event_ids: unresolved_event_ids,
                    },
                );
            }
        }
        drop(seen_guard);

        let mut event_ids = events_by_id.keys().cloned().collect::<Vec<_>>();
        event_ids.sort();
        let mut items = Vec::with_capacity(event_ids.len());
        let mut dropped: HashMap<String, usize> = HashMap::new();
        for event_id in event_ids {
            let (event, observed_by) = events_by_id
                .remove(&event_id)
                .expect("event id collected from the same map");
            let decoded = self.decode_event(event);
            let payload = match decoded {
                Ok(message) => InboundDeliveryPayload::Envelope(message),
                Err(err) => {
                    *dropped.entry(format!("{err:?}")).or_insert(0) += 1;
                    eprintln!("[Nostr] Dropped invalid inbound event: {err:?}");
                    InboundDeliveryPayload::AdapterRejected {
                        reason: format!("{err:?}"),
                    }
                }
            };
            let mut observed_by = observed_by.into_iter().collect::<Vec<_>>();
            observed_by.sort();
            items.push(InboundDeliveryItem {
                event_id,
                observed_by,
                payload,
            });
        }
        let decoded_count = items
            .iter()
            .filter(|item| matches!(item.payload, InboundDeliveryPayload::Envelope(_)))
            .count();
        let dropped_summary = if dropped.is_empty() {
            "none".to_string()
        } else {
            let mut entries = dropped
                .into_iter()
                .map(|(reason, count)| format!("{reason}:{count}"))
                .collect::<Vec<_>>();
            entries.sort();
            entries.join(",")
        };
        let diagnostic = format!(
            "reads={successful_reads}; relays=[{}]; fetched={fetched_count}; decoded={decoded_count}; replayed={replayed}; dropped=[{dropped_summary}]",
            relay_diagnostics.join(", ")
        );
        if let Ok(mut current) = self.last_receive_diagnostic.lock() {
            *current = diagnostic;
        }
        let batch = InboundDeliveryBatch {
            batch_id: self.take_next_receive_batch_id(),
            items,
        };
        *self
            .pending_receive_batch
            .lock()
            .expect("pending receive batch mutex poisoned") = Some(PendingReceiveBatch {
            batch: batch.clone(),
            relay_cursors,
        });
        Ok(batch)
    }

    pub fn resolve_receive_batch(
        &self,
        batch_id: u64,
        resolutions: Vec<InboundDeliveryResolution>,
    ) -> Result<(), TransportError> {
        let mut pending_guard = self
            .pending_receive_batch
            .lock()
            .map_err(|_| TransportError::ReceiveFailed)?;
        let Some(pending) = pending_guard.as_ref() else {
            return Err(TransportError::InvalidMessage);
        };
        if pending.batch.batch_id != batch_id {
            return Err(TransportError::InvalidMessage);
        }

        let mut dispositions = HashMap::new();
        for resolution in resolutions {
            if dispositions
                .insert(resolution.event_id, resolution.disposition)
                .is_some()
            {
                return Err(TransportError::InvalidMessage);
            }
        }
        if dispositions.len() != pending.batch.items.len()
            || pending
                .batch
                .items
                .iter()
                .any(|item| !dispositions.contains_key(&item.event_id))
        {
            return Err(TransportError::InvalidMessage);
        }
        for item in &pending.batch.items {
            let disposition = dispositions[&item.event_id];
            match (&item.payload, disposition) {
                (
                    InboundDeliveryPayload::AdapterRejected { .. },
                    InboundDeliveryDisposition::AdapterRejected,
                ) => {}
                (
                    InboundDeliveryPayload::Envelope(_),
                    InboundDeliveryDisposition::AdapterRejected,
                )
                | (
                    InboundDeliveryPayload::AdapterRejected { .. },
                    InboundDeliveryDisposition::Consumed | InboundDeliveryDisposition::Quarantined,
                ) => return Err(TransportError::InvalidMessage),
                _ => {}
            }
        }

        let terminal_ids = dispositions
            .iter()
            .filter_map(|(event_id, disposition)| {
                disposition.is_terminal().then(|| event_id.clone())
            })
            .collect::<HashSet<_>>();
        {
            let mut seen_guard = seen_event_ids().lock().expect("seen ids mutex poisoned");
            let seen_for_pubkey = seen_guard
                .entry(self.public_key_bytes())
                .or_insert_with(HashSet::new);
            for event_id in &terminal_ids {
                if seen_for_pubkey.len() >= RECEIVE_SEEN_CAPACITY {
                    seen_for_pubkey.clear();
                }
                seen_for_pubkey.insert(event_id.clone());
            }
        }

        let retry_ids = dispositions
            .iter()
            .filter_map(|(event_id, disposition)| {
                (*disposition == InboundDeliveryDisposition::Retry).then(|| event_id.clone())
            })
            .collect::<HashSet<_>>();
        let mut remaining_relay_cursors = HashMap::new();
        for (relay_url, relay_cursor) in &pending.relay_cursors {
            if relay_cursor
                .event_ids
                .iter()
                .all(|event_id| terminal_ids.contains(event_id))
            {
                self.commit_receive_cursor_for_relay(relay_url, relay_cursor.candidate);
            } else {
                let event_ids = relay_cursor
                    .event_ids
                    .intersection(&retry_ids)
                    .cloned()
                    .collect::<HashSet<_>>();
                remaining_relay_cursors.insert(
                    relay_url.clone(),
                    PendingRelayCursor {
                        candidate: relay_cursor.candidate,
                        event_ids,
                    },
                );
            }
        }

        if retry_ids.is_empty() {
            *pending_guard = None;
        } else {
            let items = pending
                .batch
                .items
                .iter()
                .filter(|item| retry_ids.contains(&item.event_id))
                .cloned()
                .collect();
            *pending_guard = Some(PendingReceiveBatch {
                batch: InboundDeliveryBatch {
                    batch_id: self.take_next_receive_batch_id(),
                    items,
                },
                relay_cursors: remaining_relay_cursors,
            });
        }
        Ok(())
    }

    fn take_next_receive_batch_id(&self) -> u64 {
        let mut next = self
            .next_receive_batch_id
            .lock()
            .expect("receive batch id mutex poisoned");
        let current = *next;
        *next = next.saturating_add(1);
        current
    }

    fn decode_event(&self, event: Event) -> Result<DeliveryEnvelope, TransportError> {
        if event.kind != APP_EVENT_KIND && event.kind != LEGACY_NIP04_EVENT_KIND {
            return Err(TransportError::InvalidMessage);
        }
        if event.content.len() > MAX_NOSTR_EVENT_CONTENT_BYTES {
            return Err(TransportError::InvalidMessage);
        }
        event.verify().map_err(|_| TransportError::InvalidMessage)?;

        if !has_exact_recipient_tag(&event, self.public_key) {
            return Err(TransportError::InvalidMessage);
        }

        let content = if event.kind == APP_EVENT_KIND {
            nip44::decrypt(
                self.keys.secret_key(),
                &event.pubkey,
                event.content.as_bytes(),
            )
            .map_err(|_| TransportError::DecodingFailed)?
        } else {
            if !looks_like_nip04_content(&event.content) {
                return Err(TransportError::DecodingFailed);
            }
            nip04::decrypt(self.keys.secret_key(), &event.pubkey, &event.content)
                .map_err(|_| TransportError::DecodingFailed)?
        };

        let envelope: DeliveryEnvelope =
            serde_json::from_str(&content).map_err(|_| TransportError::InvalidMessage)?;
        if envelope.from != event.pubkey.to_bytes() {
            return Err(TransportError::SenderMismatch);
        }
        InboundEnvelopeGuard::for_recipient(self.public_key_bytes())
            .validate(&envelope)
            .map_err(|reason| {
                eprintln!(
                    "[Nostr] Inbound envelope rejected by neutral guard: {}",
                    reason.as_str()
                );
                TransportError::InvalidMessage
            })?;
        Ok(envelope)
    }

    fn receive_since_for_relay(&self, relay_url: &str) -> u64 {
        let initial = Timestamp::now()
            .as_u64()
            .saturating_sub(RECEIVE_LOOKBACK_SECS);
        self.receive_since_by_relay
            .lock()
            .map(|mut cursors| *cursors.entry(relay_url.to_string()).or_insert(initial))
            .unwrap_or(initial)
    }

    fn commit_receive_cursor_for_relay(&self, relay_url: &str, candidate: u64) {
        if let Ok(mut cursors) = self.receive_since_by_relay.lock() {
            let current = cursors.get(relay_url).copied().unwrap_or_else(|| {
                Timestamp::now()
                    .as_u64()
                    .saturating_sub(RECEIVE_LOOKBACK_SECS)
            });
            cursors.insert(relay_url.to_string(), current.max(candidate));
        }
    }

    fn fetch_events_from_relays(
        &self,
        relay_urls: Vec<String>,
        query_now: u64,
        timeout: Duration,
    ) -> (Vec<RelayFetch>, usize, Vec<String>) {
        let requests: Vec<_> = relay_urls
            .into_iter()
            .map(|relay_url| {
                let receive_since = self.receive_since_for_relay(&relay_url);
                let filter = Filter::new()
                    .kinds([APP_EVENT_KIND, LEGACY_NIP04_EVENT_KIND])
                    .pubkey(self.public_key)
                    .since(Timestamp::from(receive_since))
                    .until(Timestamp::from(
                        query_now.saturating_add(RECEIVE_FUTURE_SKEW_SECS),
                    ))
                    .limit(RECEIVE_LIMIT);
                (relay_url, filter)
            })
            .collect();

        // `fetch_events_from` stops at the first EOSE within its relay set.
        // Run one request per replica concurrently so a busy relay cannot hide
        // an invitation retained by another relay, without multiplying the UI
        // wait budget by the number of relays.
        let client = self.client.clone();
        let results = self.runtime.block_on(async move {
            join_all(requests.into_iter().map(|(relay_url, filter)| {
                let client = client.clone();
                async move {
                    let result = client
                        .fetch_events_from(vec![relay_url.clone()], vec![filter], Some(timeout))
                        .await;
                    (relay_url, result)
                }
            }))
            .await
        });

        let mut relay_fetches = Vec::new();
        let mut successful_reads = 0usize;
        let mut relay_diagnostics = Vec::new();
        for (relay_url, result) in results {
            match result {
                Ok(relay_events) => {
                    let relay_events = relay_events.to_vec();
                    relay_diagnostics.push(format!("{relay_url}={}", relay_events.len()));
                    successful_reads += 1;
                    relay_fetches.push(RelayFetch {
                        relay_url,
                        events: relay_events,
                    });
                }
                Err(err) => {
                    relay_diagnostics.push(format!("{relay_url}=error:{err:?}"));
                    eprintln!("[Nostr] Receive failed for {relay_url}: {err:?}");
                }
            }
        }
        (relay_fetches, successful_reads, relay_diagnostics)
    }
}

impl Transport for NostrTransport {
    fn send(&self, envelope: DeliveryEnvelope) -> Result<(), TransportError> {
        self.send_with_receipt(envelope).map(|_| ())
    }

    fn send_with_receipt(
        &self,
        envelope: DeliveryEnvelope,
    ) -> Result<DeliveryReceipt, TransportError> {
        self.send_with_receipt_with_timeout(envelope, self.publish_timeout_secs)
    }

    fn receive(&self) -> Result<Vec<DeliveryEnvelope>, TransportError> {
        Err(TransportError::NotImplemented)
    }

    fn is_connected(&self) -> bool {
        !self.runtime.block_on(self.client.relays()).is_empty()
    }

    fn name(&self) -> &'static str {
        "nostr"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ingress_test_transport(secret: u8) -> NostrTransport {
        NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &[secret; 32],
        )
        .expect("test transport")
    }

    fn ingress_test_item(event_id: &str, recipient: [u8; 32]) -> InboundDeliveryItem {
        InboundDeliveryItem {
            event_id: event_id.to_string(),
            observed_by: vec!["wss://relay.test".to_string()],
            payload: InboundDeliveryPayload::Envelope(DeliveryEnvelope {
                schema_version: 1,
                from: [99; 32],
                to: recipient,
                kind: 4097,
                payload: b"{}".to_vec(),
                timestamp: 1,
                correlation_id: None,
                domain_event: None,
            }),
        }
    }

    #[test]
    fn receive_cursor_does_not_follow_future_dated_event() {
        assert_eq!(next_receive_cursor(100, 200, 10_000), 199);
        assert_eq!(next_receive_cursor(250, 200, 10_000), 250);
        assert_eq!(next_receive_cursor(100, 200, 150), 149);
    }

    #[test]
    fn retry_resolution_keeps_cursor_and_seen_uncommitted() {
        let transport = ingress_test_transport(79);
        let event_id = "event-retry".to_string();
        transport
            .receive_since_by_relay
            .lock()
            .unwrap()
            .insert("wss://relay.test".to_string(), 100);
        *transport.pending_receive_batch.lock().unwrap() = Some(PendingReceiveBatch {
            batch: InboundDeliveryBatch {
                batch_id: 7,
                items: vec![ingress_test_item(&event_id, transport.public_key_bytes())],
            },
            relay_cursors: HashMap::from([(
                "wss://relay.test".to_string(),
                PendingRelayCursor {
                    candidate: 200,
                    event_ids: HashSet::from([event_id.clone()]),
                },
            )]),
        });

        transport
            .resolve_receive_batch(
                7,
                vec![InboundDeliveryResolution {
                    event_id: event_id.clone(),
                    disposition: InboundDeliveryDisposition::Retry,
                }],
            )
            .expect("retry resolution");

        assert_eq!(transport.receive_since_for_relay("wss://relay.test"), 100);
        assert!(!seen_event_ids()
            .lock()
            .unwrap()
            .get(&transport.public_key_bytes())
            .is_some_and(|seen| seen.contains(&event_id)));
        let pending = transport.pending_receive_batch.lock().unwrap();
        assert_eq!(pending.as_ref().unwrap().batch.items.len(), 1);
        assert_ne!(pending.as_ref().unwrap().batch.batch_id, 7);
    }

    #[test]
    fn terminal_resolution_commits_seen_and_only_complete_relay_prefixes() {
        let transport = ingress_test_transport(80);
        let first = "event-first".to_string();
        let second = "event-second".to_string();
        {
            let mut cursors = transport.receive_since_by_relay.lock().unwrap();
            cursors.insert("wss://relay.mixed".to_string(), 100);
            cursors.insert("wss://relay.complete".to_string(), 100);
        }
        *transport.pending_receive_batch.lock().unwrap() = Some(PendingReceiveBatch {
            batch: InboundDeliveryBatch {
                batch_id: 9,
                items: vec![
                    ingress_test_item(&first, transport.public_key_bytes()),
                    ingress_test_item(&second, transport.public_key_bytes()),
                ],
            },
            relay_cursors: HashMap::from([
                (
                    "wss://relay.mixed".to_string(),
                    PendingRelayCursor {
                        candidate: 300,
                        event_ids: HashSet::from([first.clone(), second.clone()]),
                    },
                ),
                (
                    "wss://relay.complete".to_string(),
                    PendingRelayCursor {
                        candidate: 250,
                        event_ids: HashSet::from([first.clone()]),
                    },
                ),
            ]),
        });

        transport
            .resolve_receive_batch(
                9,
                vec![
                    InboundDeliveryResolution {
                        event_id: first.clone(),
                        disposition: InboundDeliveryDisposition::Consumed,
                    },
                    InboundDeliveryResolution {
                        event_id: second.clone(),
                        disposition: InboundDeliveryDisposition::Retry,
                    },
                ],
            )
            .expect("partial resolution");

        assert_eq!(transport.receive_since_for_relay("wss://relay.mixed"), 100);
        assert_eq!(
            transport.receive_since_for_relay("wss://relay.complete"),
            250
        );
        assert!(seen_event_ids()
            .lock()
            .unwrap()
            .get(&transport.public_key_bytes())
            .is_some_and(|seen| seen.contains(&first) && !seen.contains(&second)));

        let retry_batch_id = transport
            .pending_receive_batch
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .batch
            .batch_id;
        transport
            .resolve_receive_batch(
                retry_batch_id,
                vec![InboundDeliveryResolution {
                    event_id: second.clone(),
                    disposition: InboundDeliveryDisposition::Consumed,
                }],
            )
            .expect("terminal retry resolution");
        assert_eq!(transport.receive_since_for_relay("wss://relay.mixed"), 300);
        assert!(transport.pending_receive_batch.lock().unwrap().is_none());
    }

    #[test]
    fn resolution_requires_exact_batch_identity_and_item_set() {
        let transport = ingress_test_transport(81);
        let event_id = "event-exact".to_string();
        *transport.pending_receive_batch.lock().unwrap() = Some(PendingReceiveBatch {
            batch: InboundDeliveryBatch {
                batch_id: 11,
                items: vec![ingress_test_item(&event_id, transport.public_key_bytes())],
            },
            relay_cursors: HashMap::new(),
        });

        assert_eq!(
            transport.resolve_receive_batch(12, Vec::new()),
            Err(TransportError::InvalidMessage)
        );
        assert_eq!(
            transport.resolve_receive_batch(11, Vec::new()),
            Err(TransportError::InvalidMessage)
        );
        assert!(transport.pending_receive_batch.lock().unwrap().is_some());
    }

    #[test]
    fn read_relays_are_prioritized_before_empty_pool_members() {
        let relays = prioritize_read_relay_urls(vec![
            "wss://nos.lol".to_string(),
            "wss://relay.primal.net".to_string(),
            "wss://relay.damus.io".to_string(),
        ]);
        assert_eq!(relays[0], "wss://relay.damus.io");
        assert_eq!(relays[1], "wss://relay.primal.net");
    }

    #[test]
    fn rejects_decrypted_message_with_spoofed_sender() {
        let receiver_secret = [7u8; 32];
        let attacker_secret = [8u8; 32];
        let claimed_sender = [9u8; 32];
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let attacker_keys =
            Keys::new(SecretKey::from_slice(&attacker_secret).expect("attacker key"));
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: claimed_sender,
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&message).expect("message json");
        let content = nip44::encrypt(
            attacker_keys.secret_key(),
            &receiver.public_key,
            plaintext.as_bytes(),
            nip44::Version::V2,
        )
        .expect("encrypt");
        let event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    APP_EVENT_KIND,
                    content,
                    [Tag::public_key(receiver.public_key)],
                )
                .sign(&attacker_keys),
            )
            .expect("signed event");

        assert_eq!(
            receiver.decode_event(event),
            Err(TransportError::SenderMismatch),
        );
    }

    #[test]
    fn rejects_authenticated_envelope_for_another_recipient() {
        let receiver_secret = [17u8; 32];
        let sender_secret = [18u8; 32];
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let sender_keys = Keys::new(SecretKey::from_slice(&sender_secret).expect("sender key"));
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: sender_keys.public_key().to_bytes(),
            to: [19u8; 32],
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&message).expect("message json");
        let content = nip44::encrypt(
            sender_keys.secret_key(),
            &receiver.public_key,
            plaintext.as_bytes(),
            nip44::Version::V2,
        )
        .expect("encrypt");
        let event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    APP_EVENT_KIND,
                    content,
                    [Tag::public_key(receiver.public_key)],
                )
                .sign(&sender_keys),
            )
            .expect("signed event");

        assert_eq!(
            receiver.decode_event(event),
            Err(TransportError::InvalidMessage),
        );
    }

    #[test]
    fn rejects_authenticated_envelope_with_unsupported_schema() {
        let receiver_secret = [27u8; 32];
        let sender_secret = [28u8; 32];
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let sender_keys = Keys::new(SecretKey::from_slice(&sender_secret).expect("sender key"));
        let message = DeliveryEnvelope {
            schema_version: 2,
            from: sender_keys.public_key().to_bytes(),
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&message).expect("message json");
        let content = nip44::encrypt(
            sender_keys.secret_key(),
            &receiver.public_key,
            plaintext.as_bytes(),
            nip44::Version::V2,
        )
        .expect("encrypt");
        let event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    APP_EVENT_KIND,
                    content,
                    [Tag::public_key(receiver.public_key)],
                )
                .sign(&sender_keys),
            )
            .expect("signed event");

        assert_eq!(
            receiver.decode_event(event),
            Err(TransportError::InvalidMessage),
        );
    }

    #[test]
    fn authenticated_nip44_envelope_round_trips() {
        let sender_secret = [37u8; 32];
        let receiver_secret = [38u8; 32];
        let sender = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &sender_secret,
        )
        .expect("sender transport");
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let envelope = DeliveryEnvelope {
            schema_version: 1,
            from: sender.public_key_bytes(),
            to: receiver.public_key_bytes(),
            kind: 4097,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: Some([39u8; 32]),
            domain_event: None,
        };

        let event = sender
            .encode_message(envelope.clone())
            .expect("encoded event");

        assert_eq!(event.kind, APP_EVENT_KIND);
        assert_eq!(receiver.decode_event(event), Ok(envelope));
    }

    #[test]
    fn rejects_nip44_ciphertext_with_invalid_mac() {
        let receiver_secret = [47u8; 32];
        let sender_secret = [48u8; 32];
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let sender_keys = Keys::new(SecretKey::from_slice(&sender_secret).expect("sender key"));
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: sender_keys.public_key().to_bytes(),
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&message).expect("message json");
        let mut content = nip44::encrypt(
            sender_keys.secret_key(),
            &receiver.public_key,
            plaintext.as_bytes(),
            nip44::Version::V2,
        )
        .expect("encrypt")
        .into_bytes();
        let last = content.len() - 1;
        content[last] = if content[last] == b'A' { b'B' } else { b'A' };
        let tampered_content = String::from_utf8(content).expect("base64 text");
        let event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    APP_EVENT_KIND,
                    tampered_content,
                    [Tag::public_key(receiver.public_key)],
                )
                .sign(&sender_keys),
            )
            .expect("signed tampered event");

        assert_eq!(
            receiver.decode_event(event),
            Err(TransportError::DecodingFailed),
        );
    }

    #[test]
    fn rejects_invalid_outer_signature_before_nip44_decrypt() {
        let sender_secret = [49u8; 32];
        let receiver_secret = [50u8; 32];
        let sender = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &sender_secret,
        )
        .expect("sender transport");
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let envelope = DeliveryEnvelope {
            schema_version: 1,
            from: sender.public_key_bytes(),
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let mut event = sender.encode_message(envelope).expect("encoded event");
        event.content.push('A');

        assert_eq!(
            receiver.decode_event(event),
            Err(TransportError::InvalidMessage),
        );
    }

    #[test]
    fn rejects_authenticated_envelope_with_multiple_recipient_tags() {
        let receiver_secret = [57u8; 32];
        let sender_secret = [58u8; 32];
        let other_secret = [59u8; 32];
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let sender_keys = Keys::new(SecretKey::from_slice(&sender_secret).expect("sender key"));
        let other_keys = Keys::new(SecretKey::from_slice(&other_secret).expect("other key"));
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: sender_keys.public_key().to_bytes(),
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&message).expect("message json");
        let content = nip44::encrypt(
            sender_keys.secret_key(),
            &receiver.public_key,
            plaintext.as_bytes(),
            nip44::Version::V2,
        )
        .expect("encrypt");
        let event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    APP_EVENT_KIND,
                    content,
                    [
                        Tag::public_key(receiver.public_key),
                        Tag::public_key(other_keys.public_key()),
                    ],
                )
                .sign(&sender_keys),
            )
            .expect("signed event");

        assert_eq!(
            receiver.decode_event(event),
            Err(TransportError::InvalidMessage),
        );
    }

    #[test]
    fn rejects_authenticated_envelope_with_malformed_additional_recipient_tag() {
        let receiver_secret = [60u8; 32];
        let sender_secret = [61u8; 32];
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let sender_keys = Keys::new(SecretKey::from_slice(&sender_secret).expect("sender key"));
        let message = DeliveryEnvelope {
            schema_version: 1,
            from: sender_keys.public_key().to_bytes(),
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&message).expect("message json");
        let content = nip44::encrypt(
            sender_keys.secret_key(),
            &receiver.public_key,
            plaintext.as_bytes(),
            nip44::Version::V2,
        )
        .expect("encrypt");
        let malformed_recipient =
            Tag::parse(&["p", "not-a-public-key"]).expect("raw malformed recipient tag");
        let event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    APP_EVENT_KIND,
                    content,
                    [Tag::public_key(receiver.public_key), malformed_recipient],
                )
                .sign(&sender_keys),
            )
            .expect("signed event");

        assert_eq!(
            receiver.decode_event(event),
            Err(TransportError::InvalidMessage),
        );
    }

    #[test]
    fn legacy_nip04_is_receive_only_and_cannot_downgrade_new_kind() {
        let receiver_secret = [67u8; 32];
        let sender_secret = [68u8; 32];
        let receiver = NostrTransport::new(
            NostrConfig {
                relays: Vec::new(),
                ephemeral: true,
                timeout: 2,
                publish_timeout: 2,
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let sender_keys = Keys::new(SecretKey::from_slice(&sender_secret).expect("sender key"));
        let envelope = DeliveryEnvelope {
            schema_version: 1,
            from: sender_keys.public_key().to_bytes(),
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            correlation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&envelope).expect("message json");
        let legacy_content = nip04::encrypt(
            sender_keys.secret_key(),
            &receiver.public_key,
            plaintext.as_str(),
        )
        .expect("legacy encrypt");
        let legacy_event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    LEGACY_NIP04_EVENT_KIND,
                    legacy_content.clone(),
                    [Tag::public_key(receiver.public_key)],
                )
                .sign(&sender_keys),
            )
            .expect("signed legacy event");
        let downgrade_event = receiver
            .runtime
            .block_on(
                EventBuilder::new(
                    APP_EVENT_KIND,
                    legacy_content,
                    [Tag::public_key(receiver.public_key)],
                )
                .sign(&sender_keys),
            )
            .expect("signed downgrade event");

        assert_eq!(receiver.decode_event(legacy_event), Ok(envelope));
        assert_eq!(
            receiver.decode_event(downgrade_event),
            Err(TransportError::DecodingFailed),
        );
    }
}
