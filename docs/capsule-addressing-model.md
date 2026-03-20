# Capsule Addressing Model

This note defines the addressing model after root identity became the canonical capsule identity.

It explains:
- why `v1.0.0` invitation send felt simpler
- why `rootPubKey` alone is not enough for transport routing
- how public capsule cards, trusted peer records, and encrypted endpoint updates fit together

## 1. Background

In `v1.0.0`, the user-facing capsule key was effectively the Nostr transport key.

That meant:
- a user could paste one key into the invite flow
- the transport layer already knew how to route to it
- identity and routing were collapsed into the same value

After identity decoupling, this is no longer true:
- the capsule's canonical identity is the root `ed25519` key
- transport identities are service-specific derived keys
- routing information is no longer implied by the root key alone

This is the correct architecture, but it introduces a new requirement:
- capsule identity must be separate from capsule addressing

## 2. Core Principle

The user should live in one identity space:
- root capsule identity
- human-facing `h...` key

The user should not need to reason in:
- `npub`
- Matrix IDs
- future transport-specific public keys

Transport-specific endpoints remain system-level addressing details.

## 3. Root Identity Is Not Enough To Route

Given a remote capsule's `rootPubKey`, Hivra cannot deterministically derive:
- the remote Nostr public key
- the remote Matrix endpoint
- any other remote transport endpoint

Hivra can derive local transport keys from the local seed.

It cannot derive another capsule's transport endpoints from that capsule's public root key.

Therefore, a routing layer is required.

## 4. Three Layers

### 4.1 Public Capsule Card

This is the bootstrap addressing object a user can share.

It should contain:
- root identity
- public transport endpoints
- optional capabilities/version markers

For example:
- `rootKey`
- `transports.nostr.npub`
- later: other transport endpoints

This object may be shared as:
- QR code
- clipboard JSON
- file
- link

It is public metadata, not secret material.

### 4.2 Trusted Peer Record

Once a capsule card is received, the local capsule stores a trusted peer record.

This local record is the working routing cache for the peer.

It may contain:
- peer root identity
- known transport endpoints
- local trust/import timestamp
- optional labels or capabilities

This is local state, not a global naming system.

### 4.3 Encrypted Endpoint Update

After first contact exists, capsules may exchange richer endpoint metadata privately.

This can be encrypted to the peer's root public key and decrypted by the peer's capsule.

This enables:
- endpoint updates
- transport additions
- rotation announcements
- richer peer metadata

This does not replace the public capsule card.

It extends it after bootstrap trust/contact already exists.

## 5. Why Public Card Still Matters

An encrypted peer update requires a delivery path.

Before first contact, the sender still needs some bootstrap route:
- scan a QR
- import a shared card
- open a link
- fetch a published addressing record

So the public card remains necessary for first contact.

## 6. Secret Material Rules

Transport private keys should not be exported inside the capsule card.

Current rule:
- private transport keys are derived locally from seed when needed
- public transport endpoints may be shared

This preserves:
- deterministic recovery
- fewer persisted secrets
- clean separation between identity and routing

## 7. Product Mental Model

User mental model:
- "This is my capsule"
- "This is my capsule address card"

Not:
- "This is my Nostr key"
- "This is my Matrix key"
- "This transport needs a different identity"

Root identity stays primary.

Addressing becomes a shareable card or resolvable record.

## 8. Immediate Practical Direction

Near-term Hivra can use:
- root `h...` as the only user-facing capsule identifier
- a local trusted peer card store
- Nostr endpoint resolution from imported peer cards

This is a valid bootstrap bridge while broader addressing/discovery evolves.

## 9. Longer-Term Direction

Hivra should evolve toward a real capsule addressing layer that can support:
- public capsule cards
- local trusted peer records
- encrypted endpoint updates
- later published discovery records if needed

The important boundary is:
- identity is not transport
- transport is not user mental model
- capsule addressing is the bridge between them
