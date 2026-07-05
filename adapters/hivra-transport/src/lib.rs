//! Hivra Transport Layer
//!
//! Abstract transport interface for sending and receiving messages.
//! Supports multiple transport implementations (Nostr, Matrix, BLE, etc.)

#![cfg_attr(not(any(test, feature = "std")), no_std)]

extern crate alloc;

use alloc::string::String;
use alloc::vec::Vec;
use serde::{Deserialize, Serialize};

pub mod nostr;

/// Transport errors
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportError {
    NotImplemented,
    ConnectionFailed,
    SendFailed,
    ReceiveFailed,
    InvalidMessage,
    EncodingFailed,
    DecodingFailed,
    InvalidKey,
    SenderMismatch,
    Timeout,
    Other(String),
}

/// Message format for transport layer
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Message {
    /// Sender public key
    pub from: [u8; 32],

    /// Recipient public key
    pub to: [u8; 32],

    /// Message kind (event type)
    pub kind: u32,

    /// Message payload (serialized event)
    pub payload: Vec<u8>,

    /// Timestamp
    pub timestamp: u64,

    /// Optional invitation ID
    pub invitation_id: Option<[u8; 32]>,

    /// Signed Core event carried by this transport message.
    ///
    /// Non-Core channels such as chat leave this empty.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub domain_event: Option<DomainEventProof>,
}

/// Transport-level delivery receipt.
///
/// This confirms only that a host transport adapter accepted/published the
/// envelope. It does not mean the peer capsule received, validated, or appended
/// the domain event to its ledger.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeliveryReceipt {
    /// Adapter that accepted the envelope (`nostr`, later `matrix`, `ble`, ...).
    pub transport: String,

    /// Adapter-specific endpoint that accepted the envelope.
    pub accepted_by: String,

    /// Adapter-specific envelope/event id.
    pub envelope_id: String,

    /// Hivra message kind carried by this envelope.
    pub message_kind: u32,

    /// Transport recipient endpoint.
    pub recipient: Vec<u8>,

    /// Number of adapter endpoints that failed before the first acceptance.
    pub failed_before_accept: u32,
}

/// Cryptographic proof for a Core event transported between capsules.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DomainEventProof {
    /// Core EventKind encoded as u8.
    pub kind: u8,

    /// Root key that signed the Core event.
    pub signer: [u8; 32],

    /// Ed25519 signature over the canonical Core event ID.
    pub signature: Vec<u8>,
}

/// Transport trait - all transport implementations must implement this
pub trait Transport: Send + Sync {
    /// Send a message
    fn send(&self, message: Message) -> Result<(), TransportError>;

    /// Send a message and return adapter-level delivery evidence.
    fn send_with_receipt(&self, message: Message) -> Result<DeliveryReceipt, TransportError> {
        let receipt = DeliveryReceipt {
            transport: self.name().to_string(),
            accepted_by: self.name().to_string(),
            envelope_id: String::new(),
            message_kind: message.kind,
            recipient: message.to.to_vec(),
            failed_before_accept: 0,
        };
        self.send(message)?;
        Ok(receipt)
    }

    /// Receive messages
    fn receive(&self) -> Result<Vec<Message>, TransportError>;

    /// Check if transport is connected
    fn is_connected(&self) -> bool;

    /// Get transport name
    fn name(&self) -> &'static str;
}

/// Transport manager that can use multiple transports
pub struct TransportManager {
    transports: Vec<Box<dyn Transport>>,
}

impl TransportManager {
    /// Create new transport manager
    pub fn new() -> Self {
        Self {
            transports: Vec::new(),
        }
    }

    /// Add a transport
    pub fn add_transport(&mut self, transport: Box<dyn Transport>) {
        self.transports.push(transport);
    }

    /// Send message via all transports
    pub fn send(&self, message: Message) -> Result<(), TransportError> {
        self.send_with_receipt(message).map(|_| ())
    }

    /// Send message via all transports and return the adapter receipt.
    pub fn send_with_receipt(&self, message: Message) -> Result<DeliveryReceipt, TransportError> {
        let mut last_error = None;

        for transport in &self.transports {
            match transport.send_with_receipt(message.clone()) {
                Ok(receipt) => return Ok(receipt),
                Err(e) => last_error = Some(e),
            }
        }

        Err(last_error.unwrap_or(TransportError::SendFailed))
    }

    /// Receive messages from all transports
    pub fn receive(&self) -> Result<Vec<Message>, TransportError> {
        let mut all_messages = Vec::new();

        for transport in &self.transports {
            if let Ok(messages) = transport.receive() {
                all_messages.extend(messages);
            }
        }

        Ok(all_messages)
    }

    /// Get list of connected transports
    pub fn connected_transports(&self) -> Vec<&'static str> {
        self.transports
            .iter()
            .filter(|t| t.is_connected())
            .map(|t| t.name())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct MockTransport {
        name: &'static str,
        connected: bool,
    }

    impl Transport for MockTransport {
        fn send(&self, _message: Message) -> Result<(), TransportError> {
            Ok(())
        }

        fn receive(&self) -> Result<Vec<Message>, TransportError> {
            Ok(Vec::new())
        }

        fn is_connected(&self) -> bool {
            self.connected
        }

        fn name(&self) -> &'static str {
            self.name
        }
    }

    #[test]
    fn test_transport_manager() {
        let mut manager = TransportManager::new();

        let transport = Box::new(MockTransport {
            name: "mock",
            connected: true,
        });

        manager.add_transport(transport);
        assert_eq!(manager.connected_transports(), vec!["mock"]);

        let receipt = manager
            .send_with_receipt(Message {
                from: [1u8; 32],
                to: [2u8; 32],
                kind: 42,
                payload: Vec::new(),
                timestamp: 7,
                invitation_id: None,
                domain_event: None,
            })
            .expect("transport receipt");
        assert_eq!(receipt.transport, "mock");
        assert_eq!(receipt.message_kind, 42);
        assert_eq!(receipt.recipient, vec![2u8; 32]);
    }
}
