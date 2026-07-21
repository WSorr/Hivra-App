//! Nostr transport adapter

use crate::{DeliveryReceipt, Message, Transport, TransportError};
use futures::stream::{FuturesUnordered, StreamExt};
use nostr_sdk::nips::nip04;
use nostr_sdk::prelude::*;
use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};
use tokio::runtime::{Builder, Runtime};
use tokio::time;

// Use standard DM kind for better relay compatibility.
const APP_EVENT_KIND: Kind = Kind::Custom(4);
const CONNECT_POLL_MS: u64 = 250;
const RECEIVE_LIMIT: usize = 2048;
const RECEIVE_LOOKBACK_SECS: u64 = 7 * 24 * 60 * 60;
const RECEIVE_FUTURE_SKEW_SECS: u64 = 5 * 60;
const RECEIVE_SEEN_CAPACITY: usize = 2048;
const MIN_RELAY_SEND_TIMEOUT_SECS: u64 = 6;
const SEND_CONNECT_TIMEOUT_SECS: u64 = 4;
const INIT_CONNECT_TIMEOUT_SECS: u64 = 4;

static SEEN_EVENT_IDS: OnceLock<Mutex<HashMap<[u8; 32], HashSet<String>>>> = OnceLock::new();

fn seen_event_ids() -> &'static Mutex<HashMap<[u8; 32], HashSet<String>>> {
    SEEN_EVENT_IDS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_receive_cursor(current: u64, query_now: u64, max_event_timestamp: u64) -> u64 {
    // Relay data is untrusted. A future-dated event must not move the cursor
    // beyond this query and hide later envelopes with valid timestamps.
    current.max(max_event_timestamp.min(query_now).saturating_sub(1))
}

fn looks_like_nip04_content(content: &str) -> bool {
    let mut parts = content.splitn(2, "?iv=");
    let cipher = parts.next().unwrap_or_default();
    let iv = parts.next().unwrap_or_default();

    // NIP-04 requires a 16-byte IV. In base64 that is typically 22-24 chars.
    !cipher.is_empty() && iv.len() >= 22
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
    pub timeout: u64,
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
        }
    }
}

pub struct NostrTransport {
    runtime: Runtime,
    client: Client,
    keys: Keys,
    public_key: PublicKey,
    timeout_secs: u64,
    receive_since: Mutex<u64>,
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
            timeout_secs: config.timeout,
            receive_since: Mutex::new(
                Timestamp::now()
                    .as_u64()
                    .saturating_sub(RECEIVE_LOOKBACK_SECS),
            ),
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

        if !Self::wait_for_connected_relays(
            runtime,
            &client,
            Duration::from_secs(config.timeout.min(INIT_CONNECT_TIMEOUT_SECS).max(2)),
        ) {
            eprintln!("[Nostr] Warning: no relay reached Connected state during init");
        }

        Ok(client)
    }

    fn wait_for_connected_relays(runtime: &Runtime, client: &Client, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;

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

    fn ensure_connected_relays(&self) -> bool {
        self.ensure_connected_relays_with_timeout(self.timeout_secs.max(2))
    }

    fn ensure_connected_relays_with_timeout(&self, timeout_secs: u64) -> bool {
        Self::wait_for_connected_relays(
            &self.runtime,
            &self.client,
            Duration::from_secs(timeout_secs.max(2)),
        )
    }

    pub fn public_key_bytes(&self) -> [u8; 32] {
        self.public_key.to_bytes()
    }

    /// Returns the Nostr event kind used by Hivra messages.
    pub fn event_kind() -> Kind {
        APP_EVENT_KIND
    }

    /// Serializes a transport message into Nostr event content.
    ///
    /// For kind=4 we publish a NIP-04 encrypted DM content.
    pub fn serialize_message(&self, message: &Message) -> Result<String, TransportError> {
        let plaintext =
            serde_json::to_string(message).map_err(|_| TransportError::EncodingFailed)?;

        if APP_EVENT_KIND == Kind::Custom(4) {
            let recipient =
                PublicKey::from_slice(&message.to).map_err(|_| TransportError::InvalidKey)?;
            let secret = self.keys.secret_key();
            nip04::encrypt(secret, &recipient, plaintext.as_str())
                .map_err(|_| TransportError::EncodingFailed)
        } else {
            Ok(plaintext)
        }
    }

    /// Builds Nostr tags for a transport message.
    pub fn message_tags(&self, message: &Message) -> Result<Vec<Tag>, TransportError> {
        let recipient_pubkey = PublicKey::from_slice(&message.to).map_err(|e| {
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
        message: &Message,
    ) -> Result<EventBuilder, TransportError> {
        let content = self.serialize_message(message)?;
        let tags = self.message_tags(message)?;
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

    fn encode_message(&self, message: Message) -> Result<Event, TransportError> {
        eprintln!("[Nostr] Encoding message to: {:?}", &message.to[..4]);

        let content = self.serialize_message(&message)?;
        eprintln!("[Nostr] Message content: {}", content);

        let tags = self.message_tags(&message)?;
        let event = self.build_signed_event(content, tags)?;

        eprintln!("[Nostr] Event ID: {}", event.id.to_hex());
        Ok(event)
    }

    /// Prepares a signed Nostr event using an external signer.
    ///
    /// This is the migration path toward keeping signing in upper layers.
    pub fn prepare_event<S>(&self, message: &Message, signer: S) -> Result<Event, TransportError>
    where
        S: FnOnce(EventBuilder) -> Result<Event, TransportError>,
    {
        let builder = self.event_builder_for_message(message)?;
        signer(builder)
    }

    /// Sends a message using an externally signed Nostr event.
    pub fn send_prepared<S>(&self, message: &Message, signer: S) -> Result<(), TransportError>
    where
        S: FnOnce(EventBuilder) -> Result<Event, TransportError>,
    {
        let event = self.prepare_event(message, signer)?;
        self.send_event(event)
    }

    pub fn send_event(&self, event: Event) -> Result<(), TransportError> {
        self.publish_event(event).map(|_| ())
    }

    fn publish_event(&self, event: Event) -> Result<(String, String, u32), TransportError> {
        let connect_timeout_secs = self.timeout_secs.min(SEND_CONNECT_TIMEOUT_SECS).max(2);
        if !self.ensure_connected_relays_with_timeout(connect_timeout_secs) {
            // Mobile networks may need longer TLS/relay handshake than the fast
            // send path budget. Keep quick attempt first, then allow one
            // extended fallback before declaring transport unavailable.
            let fallback_timeout_secs = self.timeout_secs.max(connect_timeout_secs);
            if fallback_timeout_secs > connect_timeout_secs {
                eprintln!(
                    "[Nostr] No connected relays in fast window ({}s), retrying connect with fallback budget {}s",
                    connect_timeout_secs, fallback_timeout_secs
                );
            }
            if fallback_timeout_secs <= connect_timeout_secs
                || !self.ensure_connected_relays_with_timeout(fallback_timeout_secs)
            {
                eprintln!("[Nostr] No connected relays available before publish");
                return Err(TransportError::ConnectionFailed);
            }
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

        let per_relay_timeout =
            Duration::from_secs(self.timeout_secs.max(MIN_RELAY_SEND_TIMEOUT_SECS));
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

            let mut failure_details: Vec<String> = Vec::new();
            while let Some((relay_url, result)) = pending.next().await {
                match result {
                    Ok(Ok(event_id)) => {
                        return Ok((relay_url, event_id.to_hex(), failure_details));
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

            Err(failure_details)
        });

        if let Ok((relay_url, event_id, failure_details)) = publish_result {
            eprintln!("[Nostr] Relay {} accepted event: {}", relay_url, event_id);
            let failed_before_accept = failure_details.len() as u32;
            if !failure_details.is_empty() {
                eprintln!(
                    "[Nostr] Message published with {} relay(s) failing before first success",
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

    fn decode_event(&self, event: Event) -> Result<Message, TransportError> {
        if event.kind != APP_EVENT_KIND {
            return Err(TransportError::InvalidMessage);
        }

        let content = if APP_EVENT_KIND == Kind::Custom(4) {
            // Only attempt DM decryption for events addressed to our pubkey.
            let addressed_to_me = event.tags.public_keys().any(|pk| *pk == self.public_key);
            if !addressed_to_me {
                return Err(TransportError::InvalidMessage);
            }

            if !looks_like_nip04_content(&event.content) {
                return Err(TransportError::DecodingFailed);
            }

            let secret = self.keys.secret_key();
            // kind=4 content is NIP-04 ciphertext encrypted by the sender for our pubkey.
            nip04::decrypt(secret, &event.pubkey, &event.content)
                .map_err(|_| TransportError::DecodingFailed)?
        } else {
            event.content
        };

        let message: Message =
            serde_json::from_str(&content).map_err(|_| TransportError::InvalidMessage)?;
        if message.from != event.pubkey.to_bytes() {
            return Err(TransportError::SenderMismatch);
        }
        Ok(message)
    }
}

impl Transport for NostrTransport {
    fn send(&self, message: Message) -> Result<(), TransportError> {
        self.send_with_receipt(message).map(|_| ())
    }

    fn send_with_receipt(&self, message: Message) -> Result<DeliveryReceipt, TransportError> {
        eprintln!("[Nostr] Sending message...");
        let message_kind = message.kind;
        let recipient = message.to.to_vec();
        let event = self.encode_message(message)?;
        let (accepted_by, envelope_id, failed_before_accept) = self.publish_event(event)?;
        Ok(DeliveryReceipt {
            transport: self.name().to_string(),
            accepted_by,
            envelope_id,
            message_kind,
            recipient,
            failed_before_accept,
        })
    }

    fn receive(&self) -> Result<Vec<Message>, TransportError> {
        eprintln!("[Nostr] Receiving messages...");

        if !self.ensure_connected_relays() {
            eprintln!("[Nostr] No connected relays available for receive");
            return Ok(Vec::new());
        }

        // Start from a bounded recovery window, then advance a per-transport
        // cursor. Without `since`, a noisy inbox can fill the relay limit with
        // old events and permanently hide the newest delivery.
        let receive_since = self
            .receive_since
            .lock()
            .map(|cursor| *cursor)
            .unwrap_or_else(|_| {
                Timestamp::now()
                    .as_u64()
                    .saturating_sub(RECEIVE_LOOKBACK_SECS)
            });
        let query_now = Timestamp::now().as_u64();
        let filter = Filter::new()
            .kind(APP_EVENT_KIND)
            .pubkey(self.public_key)
            .since(Timestamp::from(receive_since))
            .until(Timestamp::from(
                query_now.saturating_add(RECEIVE_FUTURE_SKEW_SECS),
            ))
            .limit(RECEIVE_LIMIT);

        let events = self
            .runtime
            .block_on(
                self.client
                    .fetch_events(vec![filter], Some(Duration::from_secs(self.timeout_secs))),
            )
            .map_err(|e| {
                eprintln!("[Nostr] Receive failed: {:?}", e);
                TransportError::ReceiveFailed
            })?;

        eprintln!("[Nostr] Received {} events", events.len());

        if let Some(max_timestamp) = events.iter().map(|event| event.created_at.as_u64()).max() {
            if let Ok(mut cursor) = self.receive_since.lock() {
                // Keep one second of overlap because multiple envelopes may
                // share a relay timestamp; event-id dedupe handles the replay.
                *cursor = next_receive_cursor(*cursor, query_now, max_timestamp);
            }
        }

        let mut seen_guard = seen_event_ids().lock().expect("seen ids mutex poisoned");
        let seen_for_pubkey = seen_guard
            .entry(self.public_key_bytes())
            .or_insert_with(HashSet::new);

        let mut messages = Vec::new();
        for event in events {
            let event_id = event.id.to_hex();
            if seen_for_pubkey.contains(&event_id) {
                continue;
            }

            if let Ok(msg) = self.decode_event(event) {
                if seen_for_pubkey.len() >= RECEIVE_SEEN_CAPACITY {
                    seen_for_pubkey.clear();
                }
                seen_for_pubkey.insert(event_id);
                messages.push(msg);
            }
        }
        Ok(messages)
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

    #[test]
    fn receive_cursor_does_not_follow_future_dated_event() {
        assert_eq!(next_receive_cursor(100, 200, 10_000), 199);
        assert_eq!(next_receive_cursor(250, 200, 10_000), 250);
        assert_eq!(next_receive_cursor(100, 200, 150), 149);
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
            },
            &receiver_secret,
        )
        .expect("receiver transport");
        let attacker_keys =
            Keys::new(SecretKey::from_slice(&attacker_secret).expect("attacker key"));
        let message = Message {
            from: claimed_sender,
            to: receiver.public_key_bytes(),
            kind: 1,
            payload: vec![1, 2, 3],
            timestamp: 1,
            invitation_id: None,
            domain_event: None,
        };
        let plaintext = serde_json::to_string(&message).expect("message json");
        let content = nip04::encrypt(attacker_keys.secret_key(), &receiver.public_key, plaintext)
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
}
