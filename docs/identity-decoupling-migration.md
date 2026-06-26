# Identity Decoupling Migration

This note records how Hivra moved from the legacy identity exposure path to the
target architecture where capsule identity is transport-agnostic.

Use this note before changing root identity derivation, capsule public key exposure, or transport key generation.

## Goal

Make the canonical capsule root identity independent from transport adapters.

Target derivation order:

1. recovery seed
2. canonical capsule root identity (`ed25519`)
3. transport-specific derived keys

This must preserve:

- seed compatibility
- deterministic reconstruction
- ledger ownership stability across upgrades
- downward-only dependency direction

## Current State

Root/transport identity split is implemented and live:

- runtime signing key path is root-backed (`SeedBackedKeyStore`)
- root and Nostr identities are exposed through explicit FFI APIs
- diagnostics/bootstrap track identity mode (`root_owner` / `legacy_nostr_owner`)
- protocol v4 runtime initialization rejects `legacy_nostr_owner`
- Flutter refresh/worker bootstrap paths fail closed for legacy-owner runtime rebuilds

Intentional compatibility surface:

- `legacy_nostr_owner` remains only a diagnostic label for old test artifacts
- invitation/relationship transport flows still derive Nostr keys locally (adapter boundary), which is expected
- old ledger/index artifacts can still carry legacy identity mode, but they are
  not an active v4 runtime mode

This is not an active v1 architecture debt: new capsules use `root_owner`.
Before stable public release, legacy test capsules should be recreated or their
trusted links re-established from the root phrase instead of silently rebuilding
runtime state with a transport owner.

## Required Invariants

The migration must keep these rules true:

1. Core remains curve-agnostic.
   - `PubKey` stays a raw 32-byte value.
   - Core does not learn what `ed25519` or `secp256k1` means.

2. Engine remains transport-agnostic.
   - Engine signs and exposes a root public key through its keystore interface.
   - Engine does not derive Nostr keys itself.

3. Transport identities stay below the runtime layer.
   - Nostr key derivation remains adapter/platform work.
   - UI does not treat a transport key as capsule identity.

4. Determinism is preserved.
   - the same seed must always produce the same root identity
   - the same seed must always produce the same transport key for the same derivation label

5. Existing root-owned ledgers remain valid during migration.
   - no history rewrite
   - no event re-signing
   - no starter ID recalculation from a peer identity
   - legacy-owner test ledgers fail closed under protocol v4

## Proposed Shape

### A. Introduce canonical root derivation in keystore/platform

Add a root identity derivation helper that is explicitly not adapter-specific:

- `derive_root_keypair(seed)` or equivalent
- `derive_root_public_key(seed)`

Use a separate HKDF label from Nostr:

- root identity label: `HIVRA_ROOT_IDENTITY_v1`
- Nostr label stays transport-specific

This keeps domain separation explicit and deterministic.

### B. Make the runtime owner use the root identity

The `SeedBackedKeyStore` used by the engine/runtime should expose:

- `generate()` -> root public key
- `public_key()` -> root public key
- `sign(msg)` -> root identity signature

`init_runtime_state(...)` should construct the capsule owner from the root public key, not from the Nostr public key.

This is the real decoupling step.

### C. Keep transport derivation below FFI adapter boundaries

When FFI needs Nostr transport behavior, it should derive:

- Nostr secret/public key from the same seed
- using the existing Nostr-specific derivation path

That work should stay local to:

- invitation send/accept
- self-check transport actions
- relationship transport actions

The runtime owner should not be reused as the transport identity.

### D. Split public API language

FFI/UI APIs must become explicit about which key is being requested:

- capsule root public key
- transport public key (Nostr, later Matrix, etc.)

Avoid one ambiguous `public key` concept in product-facing code.

## Phased Migration

### Phase 0: Preparation

Add root derivation helpers without changing behavior.

Definition of done:

- root derivation helper exists
- transport derivation helper remains unchanged
- tests prove deterministic derivation for both

### Phase 1: Explicit API split

Introduce separate APIs for:

- root capsule public key
- Nostr transport public key

Keep the existing legacy API temporarily, but clearly mark it as deprecated in code comments and bindings.

Definition of done:

- runtime code can ask for root identity explicitly
- transport code can ask for Nostr identity explicitly
- UI has a path to display the right concept later

### Phase 2: Runtime owner migration

Move runtime owner and capsule bootstrap to the root identity.

Definition of done:

- `Capsule.pubkey` represents the canonical root identity
- runtime initialization uses the root identity
- transport send paths still work via Nostr-derived keys

### Phase 3: UI and persistence cleanup

Remove remaining legacy assumptions that “capsule public key” means “Nostr key”.

Definition of done:

- diagnostics and UI labels refer to root identity unless transport is explicitly requested
- docs and comments stop treating Nostr identity as the capsule identity
- runtime and worker bootstrap paths no longer create legacy-owner capsules

## Upgrade Safety Notes

Protocol v4 chooses a clean root-owned runtime cutoff before stable public
release:

1. root-owned ledgers remain importable when signatures and hash chain verify
2. legacy-owner runtime rebuilds are rejected before FFI import/append
3. there is no silent history rewrite from transport owner to root owner
4. old test capsules can be recreated from phrase and trusted links
   re-established through normal invitations

## Current Decision

The root/transport split is complete for v1:

1. all newly created capsules use `root_owner`
2. `legacy_nostr_owner` is a diagnostic label only
3. runtime diagnostics continue to expose the detected identity mode
4. protocol v4 ledger import verifies hash chain plus Ed25519 event signatures
5. legacy-owner runtime initialization fails closed

## What Not To Do

- Do not teach Core about `ed25519` or `secp256k1`.
- Do not let Flutter decide which identity is canonical.
- Do not replace transport derivation by ad hoc UI logic.
- Do not rewrite historical events or starter IDs during migration.
- Do not silently rebuild a legacy-owner capsule as root-owned state in the same
  directory.
- Do not mix the identity refactor with unrelated Android transport or backup work.
