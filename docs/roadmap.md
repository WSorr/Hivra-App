# Hivra Roadmap

This roadmap tracks the main engineering work needed to move Hivra from a working prototype to a disciplined, stable public product.

It is intentionally focused on architecture, determinism, release hygiene, and recovery safety rather than feature volume.

## Current Priorities

### 1. Replay Safety

Goal:
- Ensure transport replay can never rewrite resolved local truth.

Scope:
- Formalize replay rules for:
  - `InvitationAccepted`
  - `RelationshipEstablished`
  - `RelationshipBroken`
- Extend the current invitation replay guards into a general replay policy.
- Add regression coverage for replay on long-lived capsules.

Definition of done:
- Replayed transport events are either safely ignored or appended as genuinely new facts.
- Old resolved state cannot reappear as pending state after restart, restore, or device migration.

### 2. Persist / Import Idempotence

Goal:
- Guarantee that a persisted ledger reconstructs the same capsule truth after bootstrap.

Scope:
- Audit the full path:
  - `append -> export -> persist -> bootstrap -> import`
- Add regression tests for:
  - send -> accept
  - break
  - re-invite with same starter type
  - re-invite with different starter type
  - reverse-direction invitation flows
- Detect incomplete or inconsistent capsule histories during bootstrap.

Definition of done:
- If an event is present in persisted ledger state, it survives restart and reconstructs the same projections.

### 3. Device Migration Safety

Goal:
- Make recovery on a new machine predictable and safe.

Scope:
- Validate recovery flows for:
  - seed phrase only
  - seed phrase + backup
  - backup import after clean install
- Confirm transport receive after restore does not resurrect closed invitation history.
- Ensure user-facing recovery artifacts remain understandable and easy to locate.

Definition of done:
- A user can restore a capsule on a new machine without manual container surgery or hidden-path knowledge.

### 4. Ledger Inspector v2

Goal:
- Make the inspector useful for humans without weakening the underlying ledger model.

Principle:
- Decoded first, raw on demand.

Scope:
- Decode and display human-readable fields for:
  - `InvitationSent`
  - `InvitationReceived`
  - `InvitationAccepted`
  - `StarterCreated`
  - `RelationshipEstablished`
  - `RelationshipBroken`
- Show keys in Hivra bech32 form.
- Keep raw payload available behind an explicit disclosure.
- Add integrity hints for obviously inconsistent histories.

Definition of done:
- The inspector is understandable without reading binary payloads.
- Raw event details remain available for debugging.

### 5. Shared Projection Discipline

Goal:
- Prevent UI drift where different screens interpret the same ledger with different semantics.

Scope:
- Keep peer-level relationship grouping in one shared projection path.
- Continue removing duplicated projection logic from individual screens.
- Identify any remaining places where summary widgets and full screens compute different truths.

Definition of done:
- Header counts, list screens, and detail views use the same underlying projection semantics.

## Release Discipline

### 6. Release Preflight as a Gate

Goal:
- Make release validation a repeatable process rather than memory.

Scope:
- Maintain:
  - `tools/release/preflight.sh`
  - `tools/review/review_all.sh`
  - macOS release checklist
- Expand preflight coverage where useful, without turning it into fragile theater.

Definition of done:
- Every release candidate is validated through one clear preflight path before packaging and publishing.

### 7. Public macOS Release Quality

Goal:
- Move from test distribution to clean public distribution.

Scope:
- Keep universal macOS FFI packaging in place.
- Move toward:
  - proper signing
  - notarization
  - clean tester/public release separation
- Verify release artifacts from the packaged archive, not only from the build tree.

Definition of done:
- Published macOS artifacts match the tested build and launch reliably on supported Macs.

### 7.2 Android Release Quality

Goal:
- Move Android from bring-up success to a disciplined release channel.

Scope:
- Keep Rust FFI packaging explicit and reproducible in Android builds.
- Replace temporary app-private seed storage with a proper Android keystore-backed implementation.
- Add Android-specific smoke coverage for:
  - app launch
  - capsule create/recover
  - invitation send
  - invitation accept
  - backup/recovery entry paths
- Improve outbound transport diagnostics so relay write failures are visible and actionable.
- Verify release APKs from the packaged artifact, not only from a local build tree install.

Definition of done:
- Published Android APKs install cleanly, launch, and complete basic invitation flows on real devices.
- Android release verification is part of the normal release process rather than an ad hoc side task.

### 7.1 Update Safety Blockers

Goal:
- Prevent app updates from silently changing capsule truth for existing users.

Required conditions before treating updates as safe:
- The same persisted `ledger.json` reconstructs the same:
  - starters
  - relationships
  - pending invitations
  - capsule header counters
- Bootstrap remains ledger-first.
- Transport replay cannot override already reconstructed local truth.
- Resolved invitation history cannot reappear as pending state.
- A single invitation lineage cannot be realized twice after an update.
- Public release builds must not share a mutable test/dev container story.
- Capsule identity, seed binding, and active capsule selection must survive upgrade.

Minimum required upgrade tests:
- same container, same ledger, new build -> same UI truth
- accepted relationship survives update
- broken relationship survives update
- re-invite history does not duplicate after update
- old resolved invites do not resurrect after update
- restore on a clean machine still reconstructs the same capsule truth

Definition of done:
- Updating the app preserves the same capsule truth instead of reconstructing a partial or duplicated history.

## Modularity and Architecture

### 8. Thin FFI Boundary

Goal:
- Keep FFI as a narrow bridge rather than a second policy layer.

Scope:
- Audit FFI entrypoints for hidden orchestration or domain leakage.
- Move business rules down into core/engine where they belong.
- Keep Flutter focused on presentation and screen-level orchestration.

Definition of done:
- FFI remains explicit, narrow, and predictable.

### 8.1 Android Runtime Hardening

Goal:
- Reduce Android-specific fragility in capsule bootstrap, outbound transport, and seed storage.

Scope:
- Remove Android-only blind spots where transport failures collapse into generic UI errors.
- Keep runtime bootstrap behavior aligned with macOS so cross-platform truth stays comparable.
- Audit Android-specific storage and lifecycle assumptions for restart, reinstall, and upgrade behavior.

Definition of done:
- Android runtime failures are diagnosable.
- Android behavior matches the same ledger/truth rules expected on other platforms.

### 9. Flutter Policy Reduction

Goal:
- Reduce business-policy drift in Flutter-side services.

Scope:
- Review:
  - capsule persistence
  - projections
  - recovery flows
  - transport-triggered UI behavior
- Remove any remaining logic that creates a second truth beside the ledger.

Definition of done:
- Flutter consumes projections and initiates actions, but does not own domain truth.

### 9.1 Identity Decoupling

Goal:
- Separate canonical capsule identity from transport-specific keys.

Scope:
- Make `ed25519` the canonical capsule root identity.
- Derive Nostr, Matrix, and future adapter keys from the same recovery seed using domain-separated derivation.
- Remove legacy behavior where a transport-specific public key is exposed as the capsule public key.
- Preserve seed compatibility, ledger ownership stability, and upgrade safety during migration.

Definition of done:
- Capsule identity is transport-agnostic.
- Transport keys remain adapter-level concerns.
- UI no longer presents a transport-derived key as the canonical capsule identity.

## Longer-Term Work

### 10. WASM Plugin Host

Goal:
- Introduce a plugin system without violating modularity, determinism, or dependency direction.

Scope:
- Keep plugin storage and registry sandboxed.
- Define:
  - manifest format
  - capability model
  - host API
  - execution boundaries
- Only introduce execution after the shell and safety model are explicit.

Definition of done:
- Plugins extend transport capabilities without bypassing core rules or rewriting local truth.

## Working Rule

When tradeoffs are unclear, prefer:
1. one source of truth
2. deterministic reconstruction
3. explicit boundaries
4. fewer hidden side effects
5. release discipline over speed theater
