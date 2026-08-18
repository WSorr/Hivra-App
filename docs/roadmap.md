# Hivra Roadmap

This roadmap tracks the main engineering work needed to move Hivra from a working prototype to a disciplined, stable public product.

It is intentionally focused on architecture, determinism, release hygiene, and recovery safety rather than feature volume.

## Product Framing

Hivra is a local-first runtime for user-owned Capsules, not a social network or relationship product.

- A Capsule can work alone with its own ledger, recovery state, and WASM drones.
- Trusted links are optional Core Trust Layer facts created through real-world invitations.
- There is no global discovery, people search, public network map, or global relationship statistics.
- Drones are the primary extension model; chat, trading, staking, AI, and future tools must stay outside Core.
- Core remains minimal: Capsule, Ledger, Invitations, Trust Layer facts, Pair Consensus inputs, and deterministic transitions.

## Product Axis Gate

Every roadmap item is evaluated against `docs/product-axis.md` before work
starts and after it lands. It must name:

- the permanent invariant strengthened or risk removed;
- the sole capability owner;
- a `READY` pre-implementation capability-closure verdict and complete contract
  trace;
- its truth-lane and/or effect-lane mapping;
- its stable event or operation identity;
- the old path or ambiguity removed or sealed;
- replay, restart, concurrency, migration, and platform evidence as applicable.

Feature volume is not progress by itself. Work that adds paths, owners, or
dependencies without a measurable product-axis gain is not scheduled.
`NEEDS_CONTRACT` and `NEEDS_PROTOCOL` work first closes the missing architecture;
it does not enter production behind temporary DTOs or parallel facades.

## Parallel Version Tracks

The current one-page navigation board and session protocol live in
`docs/development-control.md`. This roadmap remains the detailed engineering
history and status authority for individual work items.

### Hivra 1.x: maintained product line

The current line remains the only production/release target. Work is limited to
security, correctness, deterministic recovery, platform parity, release
discipline, and refactors that demonstrably remove or seal an existing path.
The normative authority remains `docs/specification.md`.

### Hivra 2.0: architecture design line

Hivra 2.0 is designed in parallel without introducing a second production
runtime into 1.x. Its authority is the design-only
`docs/architecture-v2-blueprint.md` until an individual migration unit is
approved.

Current 2.0 program:

- `V2-0` baseline current capability owners, entrypoints, facts, projections,
  effects, dependency edges, and closure verdicts for the known architecture
  runway;
- `V2-1` define Core capability contracts and deterministic golden vectors;
- `V2-2` define effect ports and one durable lifecycle per effect;
- `V2-3` define the capability-scoped WASM host and projection-only app shell;
- `V2-4` migrate one capability at a time and delete each replaced 1.x path.

Capsule AI Runtime is a named cross-version architecture program governed by
`docs/architecture/capsule-ai-runtime.md`:

- 1.x incrementally consolidates existing Capsule Analyst, Developer Mode,
  history-advisor, and drone inference behind one process session owner and one
  provider-independent request port;
- each 1.x migration must delete or seal the replaced feature-local credential,
  provider-dispatch, disclosure, or scheduling path;
- 2.0 treats Capsule AI Runtime as a first-class host capability beside WASM
  Drone Runtime and the effect runtimes, never as part of Core;
- no new AI-enabled feature may add a direct Gemini/OpenAI/local-model path.

2.0 design constraints also include:

- separate Genesis/Proto birth mode from Leaf/Relay runtime role;
- keep 1.x on Neste;
- introduce Hood only as a fully isolated experimental network across ledger,
  slots, operational stores, drone state, delivery queues, and consensus
  evidence.

`V2-0` is complete as of 2026-08-04. Passes A-E produced one ownership-registry
schema, generated architecture evidence, owner discovery, service-locator
classification, explicit UI/Flutter-FFI mappings, bounded identity-family
decomposition, and a fail-closed exit matrix. `V2-1 / pass A` completed
`capsule_identity_birth_contract_v2`, including remediation of exact proof
binding, deterministic operation identity, replay semantics, root schema
validation, and blueprint ownership. `V2-1 / pass B` completed
`starter_inventory_contract_v2`. `V2-1 / pass C` completed the design-only
`capsule_continuity_export_contract_v2`. Post-Pass C consolidation selected
and `V2-1 / pass D` completed the design-only
`capsule_recovery_protocol_v2`. Post-Pass D consolidation selected
`V2-1 / pass E`, a design-only Capsule selection and prepared-activation
contract.
No 2.0 runtime implementation starts before the blueprint design exit criteria
are satisfied.

## 1.x / 2.0 Sequencing Contract

The two lines share one product axis but cannot share a second runtime path.
The ordering below is deliberate:

1. **1.x integrity before new lifecycle behavior.** Remediation passes
   `12.3 / pass 1-17` are complete. The post-pass audit selected only pass 18:
   bound pair-attestation automatic responses to one durable
   pair/snapshot/evidence checkpoint and remove blind re-announcement. It may
   not introduce another scheduler, outbox, transport route, or Core path.
   `5.1 Canonical Core Projection Convergence` remains a hard boundary: new
   invitation, relationship, consensus, or Capsule Map behavior must consume a
   canonical projection rather than add another Flutter event reducer.
2. **One operational lifecycle.** `12.3 / pass 4` replaced aggregate recovery
   markers for current facts with event-scoped delivery records carrying exact
   immutable correlation and normalized adapter publication evidence.
   Transport health, plugin transactions, and backup work remain behind that
   lifecycle rather than creating their own queues. Unreferenced legacy
   records remain quarantine debt and MUST NOT be replayed as a batch.
3. **2.0 proves the map before it migrates code.** `V2-0` may inventory owners,
   contracts, entrypoints, and dependency edges in parallel. It may not add a
   v2 event, DTO, storage format, facade, or executable runtime path to 1.x.
4. **Migration is capability-sized.** A V2 migration begins only with frozen
   1.x fixtures, a named public contract, an explicit removal target, and
   platform parity evidence. The replacement and deletion/sealing of the old
   path land in the same migration unit.

This contract prevents two common failures: delaying current integrity work in
the name of a redesign, and embedding speculative 2.0 structure into the
maintained 1.x runtime.

## Platform Toolchain Evolution

The Flutter/Dart, Rust, Android, and macOS build stack is a controlled
release-engineering axis, not an incidental local-machine detail and not a
bridge migration. Its current matrix, invariants, dedicated update units, and
required evidence are defined in `docs/platform-toolchain-evolution.md`.

Toolchain item `T0` completed on 2026-08-03 without changing any toolchain
version. The repository contains one non-secret compatibility manifest, an
exact Rust toolchain and target pin, and one fail-closed verifier with static,
full-local, and self-test modes. Release preflight and platform checklists
require the full verifier; CI verifies the repository-owned subset and
mismatch behavior.

Flutter-resolved JBR 21 is the canonical Android build JDK. A direct shell
Gradle invocation may inherit another host JDK, but that is diagnostic evidence
and not a second build authority. Local SDK paths remain untracked and are
resolved only by the full verifier. T0 does not activate T1 automatically:
newer Flutter/Dart, Rust, or Android versions remain candidates for separately
selected upgrade units with fresh macOS and Android artifact evidence. T0 exit
evidence is fresh build `100000327`: all automated gates passed, macOS packaged
`x86_64 + arm64`, Android packaged all three required ABIs, and both artifacts
cold-started without fatal evidence.

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
- Current progress:
  - `hivra-ffi` regression tests now cover replay-skip behavior after export/import for:
    - duplicated `InvitationAccepted` delivery (no duplicate relationship projection)
    - duplicated `InvitationRejected` delivery (no duplicate burn effects)
    - duplicated `RelationshipEstablished` delivery (no duplicate relationship facts)
    - duplicated `RelationshipBroken` delivery (no duplicate break facts)
    - replayed incoming offer for already resolved invitation (blocked)
  - Incoming delivery append now uses centralized replay guard policy (`should_skip_incoming_delivery_append`) in FFI receive path.
  - Replay policy blocks conflicting terminal invitation replays once invitation lineage is resolved, except a sender-signed `InvitationExpired` revoke for the exact incoming offer. That revoke may settle a recipient-local optimistic acceptance and releases its lineage-created starter from active projection.
  - Added regression coverage for:
    - conflicting terminal replay skipped for resolved invitation
    - first terminal event still accepted for unresolved invitation
    - `InvitationRejected` replay skipped when no matching outgoing offer exists
    - `InvitationRejected` replay skipped when invitation lineage is already terminal-accepted
    - `InvitationExpired` replay skipped when no matching outgoing offer exists
    - untrusted `InvitationExpired` replay skipped when invitation lineage is already terminal-accepted
    - out-of-order `InvitationAccepted` delivery (before local outgoing offer exists) is skipped and does not create relationship side effects
    - out-of-order `InvitationRejected` delivery (before local outgoing offer exists) is skipped and does not pre-burn local starter state
    - out-of-order `InvitationExpired` delivery (before local outgoing offer exists) is skipped and does not pre-resolve invitation lineage
    - conflicting `InvitationAccepted` replay skipped when invitation lineage is already terminal-expired
    - duplicated `InvitationExpired` delivery remains idempotent after export/import replay
  - Replay policy now also requires `InvitationExpired` delivery to resolve an existing outgoing offer, preventing orphan terminal append without local lineage anchor.
  - Replay policy now enforces relationship-delivery lineage anchors:
    - `RelationshipEstablished` delivery requires signer-to-peer binding plus an existing `InvitationAccepted` anchor and is skipped when that invitation lineage was already consumed.
    - `RelationshipBroken` delivery requires signer-to-peer binding plus an actively projected relationship key, blocking out-of-order/duplicate break replays from rewriting settled local state.
  - `RelationshipBroken` replay handling now distinguishes lifecycle episodes for the same relationship key:
    - duplicate break delivery is still skipped when the relationship key is not active,
    - break delivery is accepted after a re-establish cycle even when payload/signer bytes are identical to an older break event.
  - Added `hivra-ffi` replay-policy regression coverage for the two `RelationshipBroken` paths above, locking deterministic behavior across re-invite/re-break cycles.

Definition of done:
- Replayed transport events are either safely ignored or appended as genuinely new facts.
- Old resolved state cannot reappear as pending state after restart, restore, or device migration.
- Status: completed (2026-04-15).

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
- Current progress:
  - `hivra-ffi` regression tests now explicitly cover:
    - accepted relationship survives export/import
    - broken relationship survives export/import
    - re-invite with same starter type survives export/import
    - re-invite with different starter type survives export/import
    - reverse-direction pending invitation offers survive export/import
    - repeated import of the same exported ledger remains idempotent (no projection drift, no event duplication, same ledger JSON on re-export)
  - Runtime ledger import now rejects inconsistent histories before bootstrap restore:
    - invalid hash chain (`ledger.verify` failure)
    - missing or malformed capsule birth anchor (`CapsuleCreated` must exist for non-empty history, be first, owner-signed, and unique)

Definition of done:
- If an event is present in persisted ledger state, it survives restart and reconstructs the same projections.
- Status: completed (2026-04-15).

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
- Current progress:
  - Added `capsule_runtime_bootstrap_service_test.dart` coverage for bootstrap source selection:
    - prefers `ledger.json` when both ledger and backup are present
    - falls back to backup envelope when `ledger.json` is missing
    - returns no bootstrap when seed is unavailable
  - Runtime bootstrap now validates stored ledger compatibility before use:
    - `owner` must match the active capsule key
    - `events` must be a valid list
    - mismatched/corrupt `ledger.json` falls back to compatible backup ledger when available
    - refresh rejects incompatible stored history instead of importing ambiguous state
  - Backup ledger extraction now enforces baseline ledger shape before import:
    - valid 32-byte owner field (bytes/hex/base64)
    - `events` field must be a list
    - malformed envelopes/raw ledgers are rejected before persistence/index updates
  - Bootstrap source selection between `ledger.json` and backup is now deterministic by completeness:
    - when both sources are valid and owner-matching, the source with greater event count is selected
    - when event counts are equal, newer tail timestamp is preferred
    - if timestamp tie-break is unavailable/equal, `ledger.json` remains the stable fallback
  - Bootstrap/import path now carries ordered ledger candidates (`primary`, `fallback`) and attempts import sequentially, so a single stale/corrupt source does not abort restore when another valid source exists.
  - Capsule-delete artifact cleanup now removes legacy contact-card references by either hex (`rootHex`/`nostr hex`) or bech32 (`rootKey h1`/`nostr npub`) forms, reducing stale peer-card leftovers after restore/test cleanup cycles.
  - Added `invitation_projection_service_test.dart` coverage for restore fallback (`owner` from ledger when runtime owner is unavailable): replayed offer events after terminal `InvitationAccepted`/`InvitationRejected`/`InvitationExpired` remain terminal and do not return to pending projection.
  - Added `capsule_runtime_bootstrap_service_test.dart` restore-path fallback coverage:
    - `restoreRuntimeFromStorage` now has regression for sequential import fallback (primary candidate fails, secondary succeeds).
    - `restoreRuntimeFromStorage` now has regression that stored-history restore fails deterministically when no ledger candidate imports successfully.

Definition of done:
- A user can restore a capsule on a new machine without manual container surgery or hidden-path knowledge.
- Status: completed (2026-04-15).

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
- Stop showing starter identifiers in human-facing views as raw base64 with padding.
- Keep raw payload available behind an explicit disclosure.
- Add integrity hints for obviously inconsistent histories.

Current progress:
- Inspector event cards are decoded-first for all target kinds:
  - `InvitationSent`, `InvitationReceived`, `InvitationAccepted`
  - `StarterCreated`
  - `RelationshipEstablished`, `RelationshipBroken`
- Capsule/owner keys in inspector are shown in Hivra bech32 form.
- Raw event details are available on demand via per-event disclosure (`Raw event (on demand)`), with payload shown in base64 + hex and canonical event JSON.
- Integrity hints are surfaced for obvious inconsistencies (unknown event kinds, malformed payload lengths for known kinds, malformed signer field width).

Definition of done:
- The inspector is understandable without reading binary payloads.
- Raw event details remain available for debugging.
- Status: completed (2026-03-28).

### 5. Shared Projection Discipline

Goal:
- Prevent UI drift where different screens interpret the same ledger with different semantics.

Scope:
- Keep peer-level relationship grouping in one shared projection path.
- Continue removing duplicated projection logic from individual screens.
- Identify any remaining places where summary widgets and full screens compute different truths.
- Current progress:
  - Pairwise snapshot projection used by Ledger Inspector was moved from screen-local code into `PairwiseSnapshotService`, keeping projection logic in service layer rather than widget layer.
  - Event-kind label mapping for inspector/pairwise projections is now centralized in `LedgerViewSupport.kindLabel`, reducing duplicated event dictionaries in screen/service code.
  - Added `pairwise_snapshot_service_test.dart` regression coverage for numeric event-kind inputs, locking shared kind-label projection behavior across ledger readers.
  - Added `LedgerViewSupport` mapping invariant test coverage (`kindCode <-> kindLabel`) for canonical event kinds to prevent projection dictionary drift.
  - Added architecture contract review gate coverage to prevent reintroduction of local kind dictionaries in key projection readers.
  - `CapsuleLedgerSummaryParser` pending-invitation count now uses `InvitationProjectionService` terminal-precedence semantics (instead of `InvitationSent - resolved` arithmetic), aligning capsule selector counters with runtime invitation projections.
  - Invitations UI queue bucketing is now centralized via `bucketInvitationsForUi` (`incoming pending`, `outgoing pending`, `history`) with regression tests, so actionable queues cannot regress to showing terminal invitation states as pending work; locally resolved-id suppression now also has explicit coverage that terminal rows stay visible in history.
  - Added cross-service parity regression (`ledger_view_service_test.dart`) that the same ledger + local transport context yields identical `pendingInvitations` and `relationshipCount` in:
    - `LedgerViewService.loadCapsuleSnapshot`
    - `CapsuleLedgerSummaryParser.parse`
    This locks shared projection semantics between header snapshot counters and summary parsing.

Definition of done:
- Header counts, list screens, and detail views use the same underlying projection semantics.
- Status: completed (2026-04-15).

### 5.1 Canonical Core Projection Convergence

Goal:
- Replace shared-but-application-owned domain replay with one canonical Core
  projector and scoped `CurrentView`, `PairView`, and `HistoryView` contracts.

Current finding:
- Starter-slot, invitation, relationship, pair-consensus, and scoped history
  state now have one Core owner. Flutter consumers map versioned views and do
  not own lifecycle replay.

Current progress:
- Core now owns a direction-aware invitation lifecycle replay keyed by one
  globally unique `invitation_id`: the first offer owns the lifecycle, orphan
  terminals remain inapplicable, and the first valid terminal wins in ledger
  order.
- Sender revocation of an incoming offer is signer-bound and may supersede
  only recipient-local optimistic acceptance; an unrelated signer cannot
  expire that lifecycle.
- Engine invitation decisions now request an explicit incoming or outgoing
  projection instead of relying on an ambiguous direction fallback.
- Golden Core vectors cover terminal precedence, sender revocation, invalid
  revocation, orphan terminals, canonical peer direction, and duplicate IDs
  across directions.
- `InvitationCurrentViewV1` now carries the complete UI-facing invitation
  state through FFI. Flutter maps that versioned DTO without reading raw event
  kinds or payload offsets, and capsule-list pending counters consume the same
  view.
- The former Flutter invitation event walker and its duplicated lifecycle test
  matrix were removed; Core golden vectors now own those semantics. An
  architecture gate rejects reintroducing invitation replay into the adapter.
- `RelationshipCurrentViewV1` now owns relationship episode precedence,
  signer-bound break classification, root/transport identity grouping, and the
  active peer count in Core. FFI exports the versioned view; Flutter only maps
  its DTO and groups ready facts for presentation.
- The former Flutter relationship event walker and the naive competing Core
  relationship counter were removed. Core golden vectors cover remote-pending
  versus local-final breaks, foreign breaks, re-establishment, rejected
  invitation lineage, and multiple transports sharing one root. Architecture
  gates reject reintroducing raw relationship replay into Flutter.
- `PairViewV1` now composes the canonical invitation and relationship replay in
  Core into pair-scoped active relationships and blockers. The FFI exports the
  versioned view; Flutter only validates/maps it, creates snapshot-schema-v3
  canonical JSON, hashes it, and orchestrates signatures/attestations.
- The former Flutter pair lifecycle reducer and its duplicated event-offset
  matrix were removed. Core golden vectors now own mirrored orientation,
  third-capsule isolation, relationship deduplication, pending invitations,
  and remote-break blocking. The architecture gate rejects raw pair replay in
  Flutter.
- `HistoryViewV1` now validates typed payloads and projects the complete
  invitation, starter, or relationship chronology for one explicit subject.
  The FFI exposes the versioned view; Flutter owns only display labels,
  localized time/prose, and the advisory projection hash.
- The former Flutter history event walker and byte-offset matcher were removed.
  Core golden vectors own invitation provenance, starter lifecycle,
  root/transport relationship aliases, ledger ordering, and malformed-payload
  exclusion. The architecture gate rejects raw history replay in Flutter.

Required migration units:
1. Inventory every raw-ledger domain reader and classify it as current state,
   pair consensus, history/audit, or non-domain operational evidence.
2. Define versioned Core projection outputs and golden replay vectors for
   invitation terminal precedence, relationship episodes, starter lineage,
   pair scope, and history scope.
3. Move invitation and relationship lifecycle interpretation behind the Core
   projection boundary, then remove the replaced Flutter event walkers in the
   same migration units.
4. Make UI counters, screens, consensus, and drone guards consume only the
   appropriate canonical view.
5. Gate against new raw-event lifecycle interpretation outside Core and verify
   cache rejection on ledger/protocol version or hash mismatch.

Definition of done:
- One valid ledger and protocol version produce exactly one canonical domain
  state on macOS and Android.
- Current UI hides superseded history; explicit history remains complete;
  pair consensus contains only current pair-scoped truth and required lineage.
- No application or plugin module owns a second lifecycle reducer.
- Status: completed (2026-08-01).

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
- Current progress:
  - Added `tools/review/release_discipline_gate.sh` and wired it into `review_all.sh`.
  - Gate validates release-discipline sync between roadmap milestones, macOS release checklist, preflight steps, and review gate composition.
  - Gate also validates that preflight still includes and wires macOS bundle verification (`check_release_bundle`).
  - Gate validates presence and baseline scope of manual smoke checklist (invitation flow, relationship flow, ledger truth).
  - Gate validates that macOS release checklist includes explicit update-safety checks (truth preservation and no re-materialized resolved invites).
  - Added `docs/checklists/user-lifetime-safety-pack.md` and `tools/review/user_lifetime_safety_gate.sh`, wired into `review_all.sh` and `tools/release/preflight.sh`.
  - Release checklists now require explicit completion of User Lifetime Safety Pack scenarios on the release candidate build.

Definition of done:
- Every release candidate is validated through one clear preflight path before packaging and publishing.
- Status: completed (2026-03-29).

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
- Current progress:
  - Release-discipline gate now enforces checklist coverage for release-note signing/notarization disclosure and unsigned-build tester instructions.
  - Release-discipline gate now enforces publish checklist coverage for Git tag verification, release asset parity, and `Pre-release` flag validation.
  - Release-discipline gate now enforces packaging checklist coverage for asset naming, package rebuild, and checksum regeneration.
  - Added `tools/release/macos_release.sh` to standardize channel-aware packaging (`test` / `public`) with optional signing/notarization flow and reproducible `RELEASE-METADATA.txt` + `SHA256SUMS.txt` outputs.
  - `release_discipline_gate.sh` now enforces checklist coverage for scripted macOS release packaging, explicit channel selection, and pre-release flag mapping (`test` => pre-release, `public` => stable).
  - macOS packaging path now validates the packaged ZIP artifact itself (extract + verify `.app` bundle, universal `libhivra_ffi.dylib`, and signature checks), and preflight includes a dedicated packaged-artifact verification step.

Definition of done:
- Published macOS artifacts match the tested build and launch reliably on supported Macs.
- Status: completed (2026-04-19, v1 scope).

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
- Current progress:
  - Added `docs/checklists/release-android.md` for build/verification/diagnostics/publish discipline.
  - `release_discipline_gate.sh` now validates Android checklist presence and key coverage (send/accept smoke, transport diagnostics, keystore seed validation).
  - Android checklist and gate now require packaged-artifact install verification and APK checksum verification.
  - Android checklist and gate now require publish metadata coverage (asset naming and release-notes testing-scope/limitations disclosure).
  - Added `tools/release/android_release.sh` to standardize channel-aware Android packaging (`test` / `public`) with reproducible `RELEASE-METADATA.txt` + `SHA256SUMS.txt` outputs and ABI-level `libhivra_ffi.so` presence checks.
  - `release_discipline_gate.sh` now enforces Android scripted release packaging usage, explicit channel selection, release metadata traceability, and pre-release flag/channel mapping (`test` => pre-release, `public` => stable).
  - `tools/release/preflight.sh` now includes Android release bundle checks that validate `libhivra_ffi.so` presence for required ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`) in release APK artifacts when available.

Definition of done:
- Published Android APKs install cleanly, launch, and complete basic invitation flows on real devices.
- Android release verification is part of the normal release process rather than an ad hoc side task.
- Status: completed (2026-04-19, v1 scope).

### 7.1 Update Safety Blockers

Goal:
- Prevent app updates from silently changing capsule truth for existing users.

Current progress:
- Added persistence safety coverage for capsule index active-selection:
  - active capsule survives index write/read roundtrip
  - stale `active` pointers are sanitized when the referenced capsule entry is absent
- `loadRuntimeBootstrapForCurrent` now snapshots runtime owner key once per bootstrap read (stable owner identity for directory resolution + identity-mode classification), preventing owner-key drift during one bootstrap cycle.
- Added `capsule_runtime_bootstrap_service_test.dart` coverage that current-runtime bootstrap classifies identity mode deterministically:
  - `root_owner` when runtime owner matches root pubkey
  - `legacy_nostr_owner` when runtime owner differs from root pubkey
  - current-runtime bootstrap keeps a single owner snapshot even if runtime owner source mutates between potential reads (anti-drift regression lock).
- Added refresh-path regression coverage that `identityMode=legacy_nostr_owner` drives `legacyNostrOwnerMode` capsule creation during snapshot rebuild, locking owner-mode selection on upgrade/reload paths.
- Capsule selector now collapses duplicate visual aliases deterministically per `(network, display-key)`:
  - prefers seeded entries over unseeded aliases
  - prefers `root_owner` over `legacy_nostr_owner` when both map to the same display capsule identity
  - falls back to higher ledger version / newer activity for stable tie-breaks
- User-visible legacy documents migration is now one-shot in `UserVisibleDataDirectoryService` (migration marker file), so deleted canonical capsule data is not silently re-imported from old container paths on subsequent launches.
- Added `user_visible_data_directory_service_test.dart` regression coverage that one-shot migration does not rehydrate deleted canonical capsule files.
- Added update-safety projection fixture coverage for the same-ledger reconstruction path:
  - repeated parse of the same `ledger.json` keeps starter/relationship/pending counters stable
  - summary pending/relationship counters stay aligned with shared invitation/relationship projection services
  - replayed offer events after terminal accept/reject/expire remain non-pending (no pending resurrection)

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
- Status: completed (2026-04-15).

## Modularity and Architecture

### 8. Thin FFI Boundary

Goal:
- Keep FFI as a narrow bridge rather than a second policy layer.

Scope:
- Audit FFI entrypoints for hidden orchestration or domain leakage.
- Move business rules down into core/engine where they belong.
- Keep Flutter focused on presentation and screen-level orchestration.
- Current progress:
  - Legacy starter slot FFI getters (`hivra_starter_get_id/get_type/exists`) were aligned to ledger-derived slot projection (`SlotLayout::from_ledger`) instead of seed/slot-side derivation in the FFI layer.

Definition of done:
- FFI remains explicit, narrow, and predictable.
- Status: completed (2026-04-19, v1 scope).

### 8.1 Android Runtime Hardening

Goal:
- Reduce Android-specific fragility in capsule bootstrap, outbound transport, and seed storage.

Scope:
- Remove Android-only blind spots where transport failures collapse into generic UI errors.
- Keep runtime bootstrap behavior aligned with macOS so cross-platform truth stays comparable.
- Audit Android-specific storage and lifecycle assumptions for restart, reinstall, and upgrade behavior.
- Current progress:
  - Added `docs/checklists/android-runtime-hardening.md` to track bootstrap/storage/transport/parity runtime hardening checks.
  - `release_discipline_gate.sh` now validates Android runtime hardening checklist presence and key coverage.
  - Gate coverage now includes restart active-capsule stability, reinstall stale-seed guard, and receive-path diagnostic separation checks.
  - Gate coverage now includes restart seed-binding stability and backup-import truth parity checks.
  - Gate now enforces explicit parity checks for both invitation projections and relationship break/re-invite projections versus macOS.
  - Receive worker path now propagates FFI last-error details through `InvitationActionsService` into `InvitationIntentHandler` failure messages (full + quick fetch), so Android receive failures are diagnosable at UI layer without terminal-only inspection.
  - Added `invitation_intent_handler_test.dart` coverage for receive-failure diagnostics:
    - baseline receive failure now includes deterministic code suffix (`[code: ...]`)
    - FFI detail payload is surfaced when available (`[code: ...; ffi: ...]`)
  - Invitation worker ledger-apply path now restores the currently active runtime capsule when a worker completes for a stale capsule context (capsule switched mid-flight), preventing cross-capsule runtime drift during delayed send/fetch/accept/reject completions.
  - `MainScreen` quick-sync orchestration now drops stale delayed sync requests when their captured capsule is no longer active, reducing redundant transport/bootstrap churn after capsule switches.
  - `InvitationIntentHandler` local projection/expiry checks are now capsule-scoped (`capsuleHex`) instead of reading/mutating whichever runtime capsule happens to be active, reducing cross-capsule pending disappearance and stale-state leakage during rapid switches.
  - Invitations screen and header pending counter now request invitation projection with explicit `activeCapsuleHex`, preventing mixed “header from capsule A + invitation list from capsule B” rendering while runtime drift is being reconciled.
  - Pending-outgoing retry pump after transport-failed send now runs an extended backoff series (`2s/8s/20s/45s/90s/180s`) with explicit attempt/result diagnostics, so locally recorded invitations are retried longer under relay instability instead of stopping after two short attempts.
  - Starters send-success feedback now distinguishes transport-confirmed send from local-only recording (`local invitation is recorded`), avoiding misleading “Invitation sent” UX when relay delivery has not yet been accepted.

Definition of done:
- Android runtime failures are diagnosable.
- Android behavior matches the same ledger/truth rules expected on other platforms.
- Status: completed (2026-04-19, v1 scope).

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
- Current progress:
  - Recovery flow ledger decoding now reuses shared `LedgerViewSupport` (`kindCode` / `payloadBytes`) instead of maintaining a duplicate decoder path.
  - Recovery `isGenesis` fallback and starter-occupancy checks now reuse shared projection helpers (`LedgerViewSupport.inferGenesisFromLedgerRoot`, `CapsuleLedgerSummaryParser`) instead of local event-walk policy code.
  - Runtime bootstrap owner-field decoding now reuses shared `CapsuleLedgerSummaryParser.parseBytesField` instead of a duplicated bytes32 parser inside bootstrap service.
  - Runtime bootstrap now derives capsule `isGenesis` / `isNeste` from the preferred ledger candidate `CapsuleCreated` payload when history is present, keeping state-file flags only as fallback when ledger inference is unavailable.
  - Runtime bootstrap ledger candidate parsing now reuses shared `LedgerViewSupport` root/events helpers instead of local decode/event-list extraction logic.
  - Capsule persistence stale-check/owner extraction and legacy-ledger cleanup paths now reuse shared ledger-root helpers (`LedgerViewSupport.exportLedgerRoot` + common owner extraction) instead of repeated per-method decode logic.
  - Backup envelope ledger-shape validation now reuses shared byte decoding (`LedgerViewSupport.payloadBytes`) for owner parsing instead of maintaining another owner parser copy in `CapsuleBackupCodec`.
  - Backup envelope encoding now reuses shared ledger-root parsing (`LedgerViewSupport.exportLedgerRoot`) instead of local JSON-object branching.
  - Summary parser byte-field decoding now reuses shared `LedgerViewSupport.payloadBytes` semantics, with parser-level regression tests locking expected null/empty behaviors.
  - Summary parser root/events extraction now reuses shared `LedgerViewSupport.exportLedgerRoot/events` helpers instead of local JSON decode/list branches.
  - Recovery owner extraction now reuses shared ledger-root parsing (`LedgerViewSupport.exportLedgerRoot`) instead of local JSON decode branches.
  - Capsule persistence service now reuses a single JSON-map parse helper for index/seeds/contact-cards cleanup and backup-meta extraction instead of repeating per-call decode branches.
  - User-visible data migration path now reuses a shared JSON-map parser for legacy/canonical contact-card merge instead of duplicate decode branches.
  - Capsule seed fallback storage now reuses a shared JSON-map parser for read/write/delete paths instead of repeated decode branches.
  - Capsule index store now reuses shared JSON-map parse/coerce helpers for top-level and nested index entries instead of local decode branches.
  - Backup envelope extraction now reuses shared JSON-map decode/coerce helpers in `CapsuleBackupCodec.tryExtractLedgerJson` instead of per-branch map conversions.
  - Capsule file-store state loading now reuses a shared JSON-map parser in `CapsuleFileStore.readState`, with regression tests covering missing/valid/non-map state files.
  - Capsule address-card import/read/projection paths now reuse shared JSON-map parse/coerce helpers in `CapsuleAddressService`, with regression tests for card roundtrip and malformed contact-card file shape.
  - WASM plugin registry loading now reuses shared JSON list/map parse-coerce helpers in `WasmPluginRegistryService.loadPlugins`, with regression tests for malformed-entry filtering, sort order, and install/remove registry sync.
  - Shared projection counters (`pendingInvitations`, `relationshipCount`) are now centralized in `CapsuleLedgerSummaryParser.projectSharedCountersFromLedgerRoot(...)`; `LedgerViewService.loadCapsuleSnapshot` now reuses this parser boundary instead of maintaining a separate counter path.
  - Added parser/runtime regression coverage that malformed ledger owner + runtime owner context still yields deterministic pending classification (`capsule_ledger_summary_parser_test.dart`), aligning snapshot and summary projection semantics during degraded owner-field recovery windows.
  - Relationships screen refresh path now performs a quick transport sync before projection reload (via `MainScreen` sync hook), so incoming relationship-break facts are not hidden behind invitation-screen-only polling.
  - Manual relationship-screen refresh now bypasses quick-sync cooldown gating, ensuring explicit user refresh always triggers a transport receive cycle instead of being silently skipped by recent-sync throttling.
  - Invitations screen peer-identity root resolution now stays inside `RelationshipService` (cards + projected relationship roots) instead of reading ledger projections directly in screen code; added `relationship_service_test.dart` coverage for projected-root fallback from relationship groups.
  - `RelationshipService` root-resolution regression coverage now locks latest-relationship precedence when multiple projected peer roots exist for the same transport key (`establishedAt` tie-break toward newest), keeping peer identity display deterministic across re-invite history.
  - Relationships screen now delegates peer-root lookup orchestration to `RelationshipService` (`loadPeerRootKeysForGroups`, `resolvePeerRootDisplayKey`) instead of keeping group-scan and identity fallback policy in widget code; service-level regression tests cover non-representative transport-key lookup and fallback precedence.
  - Pending-remote-break notification projection in Relationships UI is now extracted into testable helper functions (`computeNewPendingRemoteBreakKeys`, `pruneNotifiedPendingRemoteBreakKeys`) with regression tests preventing duplicate snackbar alerts during repeated refresh/sync cycles.
  - Relationships pending-remote notifications now establish a first-load baseline before alerting; persisted pre-existing pending break rows are no longer surfaced as newly received break requests on initial screen open/switch.
  - Relationships screen bootstrap path now uses a single startup sync flow (`_syncTransportAndReload`) instead of parallel initial load + sync kickoff, reducing first-frame projection races and duplicate notification windows.
  - Relationship break delivery now has a ledger-derived retry path in FFI: unresolved locally signed `RelationshipBroken` events are re-sent before receive cycles until the remote peer's confirming break event or a later re-establish supersedes them.
  - Added a capsule-scoped durable delivery outbox (`delivery_outbox.json`) for transport retry intent. It tracks retry/backoff metadata only; ledger projection remains the single source of truth for invitations, relationships, consensus, and UI state.
  - Transport adapters now expose adapter-level `DeliveryReceipt` evidence (`transport`, accepted endpoint, envelope id, message kind, recipient). FFI publishes the latest receipts as diagnostics JSON so outbox handling can distinguish adapter acceptance from peer ledger confirmation.

Definition of done:
- Flutter consumes projections and initiates actions, but does not own domain truth.
- Status: completed (2026-04-19, v1 scope).

### 9.1 Identity Decoupling

Goal:
- Separate canonical capsule identity from transport-specific keys.

Scope:
- Make `ed25519` the canonical capsule root identity.
- Derive Nostr, Matrix, and future adapter keys from the same recovery seed using domain-separated derivation.
- Remove legacy behavior where a transport-specific public key is exposed as the capsule public key.
- Preserve seed compatibility, ledger ownership stability, and upgrade safety during migration.

Current progress:
- Runtime signing identity is root-backed by default:
  - `SeedBackedKeyStore::generate/public_key/sign` uses root derivation.
  - `build_engine` signer invariants are locked by regression coverage (`build_engine_uses_root_identity_for_signer`).
- FFI/public identity APIs are split explicitly by domain:
  - capsule/root identity: `hivra_capsule_root_public_key`, `hivra_seed_root_public_key`
  - transport identity: `hivra_capsule_nostr_public_key`, `hivra_seed_nostr_public_key`
  - runtime-owner identity: `hivra_capsule_runtime_owner_public_key`
- Added FFI regression coverage (`ffi_identity_boundary_keeps_root_and_transport_split`) that locks:
  - root and Nostr derivations are distinct for the same seed
  - runtime owner in `root` mode equals root derivation
- Flutter/runtime diagnostics and bootstrap paths now track identity mode explicitly (`root_owner` / `legacy_nostr_owner`) instead of assuming one transport key as canonical capsule identity.
- Protocol v4 rejects new `legacy_nostr_owner` runtime initialization:
  - Rust runtime creation fails closed for legacy owner mode.
  - Flutter refresh/worker bootstrap paths refuse legacy-owner runtime rebuilds.
  - `legacy_nostr_owner` remains a diagnostic label for old test artifacts, not
    an active runtime mode.

Definition of done:
- Capsule identity is transport-agnostic.
- Transport keys remain adapter-level concerns.
- Status: completed (2026-04-10, v1 scope).

### 9.2 Lineage-Derived Starter Identity

Goal:
- Move starter lifecycle from slot-only reactivation to linear lineage with immutable starter IDs.

Scope:
- Replace slot-stable reactivation (`active -> burned -> active` for the same ID) with per-slot linear generations.
- Adopt `starter_v2` lifecycle rules where:
  - every burned starter identity is terminal and never reused;
  - next activation in the same slot yields a new `starter_id` for the next generation;
  - lineage provenance is preserved in ledger events (`source_invitation_id`, `source_sender_root_pubkey`, `source_sender_starter_id`) instead of creating hash-level branching by transport era fields.
- Keep starter generations reconstructible from ledger truth only (no hidden runtime counters).
- Define migration so legacy slot-only starters remain readable and can continue in `starter_v2` as the next linear generation.

Current progress:
- FFI acceptance planning now derives acceptance-created starter identity/nonce from lineage inputs (`seed + slot + invitation_id + inviter anchor`) via dedicated `starter_v2_lineage` derivation helpers, instead of slot-only reactivation derivation.
- Inviter anchor selection now prefers sender root provenance from invitation lineage and falls back to sender transport key when root provenance is unavailable.
- Added regression coverage in `platform/hivra-ffi/src/tests.rs` for:
  - invitation-id-sensitive lineage derivation (same slot, different invitation IDs -> different starter IDs),
  - invitation-id-sensitive lineage nonce derivation (same slot, different invitation IDs -> different nonces),
  - fallback anchor behavior without sender root provenance,
  - root-anchor precedence over transport-key fallback.
- Added `UseExistingStarter` acceptance-plan coverage that when invited kind already exists, relationship binding reuses existing local starter while supplemental starter creation in the first empty slot still follows lineage derivation (`id + nonce`) with inviter-root anchor precedence.
- Added `UseExistingStarter` full-capacity coverage that when no slot is empty, acceptance plan stays deterministic with `created_starter=None` (no hidden lineage starter creation) while still reusing the existing local starter for relationship binding.
- Legacy reactivation expectations in FFI tests were replaced with linear-generation invariants (burned starter IDs are not reused, next cycle uses a distinct ID).
- Specification sync: `Starter Identity vs Provenance` and identifier rules now explicitly allow deterministic `starter_v2` lineage derivation from invitation provenance (`invitation_id + inviter anchor`) while forbidding peer-starter ID reuse.

Definition of done:
- Starter IDs are immutable per lifecycle episode and are not reanimated.
- Reconstructing from ledger preserves linear per-slot ancestry and inviter provenance without introducing branch explosions.
- Status: completed (2026-04-10, v1 scope).

### 9.3 Pairwise Consensus Snapshot v3

Goal:
- Define the smallest pairwise state snapshot that two capsules can independently derive, hash, and sign the same way.

Scope:
- Build the canonical pairwise snapshot from:
  - `schema_version`
  - `pair_roots_sorted`
  - `active_relationships`
- Use first-valid-terminal invitation semantics, with a sender-sovereignty revoke exception:
  - offer anchor must precede terminal state in local ledger order
  - first valid `accepted`, `rejected`, or `expired` wins permanently
  - later conflicting or duplicate terminal rows cannot change state/effects,
    except `expired` signed by the original incoming-offer sender
- Keep the snapshot symmetric:
  - no sender/receiver perspective bias
  - no transport delivery artifacts
  - no local-only counters or timestamps
- Terminal invitation history is diagnostic-only after it has established a
  relationship. It is not a signed snapshot input because one ledger can
  receive a relationship binding before its corresponding terminal invitation
  row. Pending invitations remain deterministic pair blockers.
- Explicitly exclude local starter-state facts such as:
  - `created_count`
  - `burned_count`
  - local `active/inactive`
  because those remain capsule-local rather than pairwise-consensus facts.
- Treat richer lineage or starter-state checks as future snapshot/schema revisions rather than overloading v1.
- Current progress:
  - Canonical consensus snapshot key naming now matches spec/roadmap contract (`pair_roots_sorted`), and legacy `pair_transport_keys_sorted` key emission was removed from `ConsensusProcessor`.
  - Added regression coverage in `consensus_processor_test.dart` to lock
    first-valid-terminal semantics in pair projection.
  - Added regression coverage that local starter-only events (`StarterCreated` / `StarterBurned`) do not affect pairwise snapshot canonical JSON/hash when pairwise facts are unchanged.
  - Added regression coverage that pairwise snapshot canonical JSON/hash remains
    stable under non-lifecycle sender-metadata noise when pairwise facts are
    equivalent. Lifecycle ordering itself is authoritative.
- Added regression coverage that symmetric A/B ledger perspectives derive the same pairwise snapshot canonical JSON/hash for equivalent pairwise facts.
- Snapshot v2 excluded terminal invitation history from the signed payload so
  that one-sided historical delivery and events involving third capsules cannot
  change an A<->B attestation. Existing v1 attestations naturally become
  inapplicable because the snapshot hash changes.
- Snapshot v3 also excludes `invitation_id` from each active relationship and
  collapses repeated establishment episodes by `relationship_kind` plus sorted
  `starter_pair`. Invitation lineage remains in the ledger, while consensus
  commits only the current live pair state.

Definition of done:
- A fresh pair of capsules can derive the same `pairwise consensus snapshot v3` hash from local ledger truth.
- The snapshot is small and stable enough to serve as a signed execution precondition for future smart-contract plugins.
- UI no longer presents a transport-derived key as the canonical capsule identity.
- Status: completed (2026-04-10, v1 scope).

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
- Current progress:
  - Added deterministic contract execution with manifest parsing and consensus-signable execution gate.
  - Added regression coverage for:
    - manifest validation
    - deterministic settlement hash
    - proposer/counterparty/draw outcomes
    - blocked execution when consensus is unresolved
  - Added external plugin package documentation and source-catalog installation flow.
  - Added manual runtime actions in the plugin surfaces so contract execution can be exercised through the consensus guard and semantic WASM ABI.
  - Added package-install preflight validation (`WasmPluginPackagePreflightService`) for `.wasm` magic/version and `.zip` manifest/module shape, wired into `WasmPluginRegistryService.installPluginFromFile` with regression coverage for malformed packages.
  - Zip preflight module discovery now considers only safe normalized `.wasm` paths (entries with parent-traversal segments are ignored), and install fails when no safe runtime module candidates remain.
  - External plugin source-catalog install path now verifies optional `sha256_hex` integrity before install (both remote download and local `file://` package flows); catalog entries with malformed `sha256_hex` shape are rejected, checksum mismatch blocks installation, and metadata mismatch (`plugin_id` / `package_kind` + `version` when available) triggers install rollback.
  - Remote plugin source catalogs now support Ed25519 signatures verified against host-pinned public keys, with host-pinned full-body SHA256 retained as a compatibility fallback for current unsigned catalogs. Package checksums are trusted only after the catalog itself passes an independent host trust root.
  - Source catalog parsing now drops entries with unsupported `download_url` schemes and deduplicates duplicate `entry.id` rows deterministically (first entry wins), reducing install-time ambiguity from malformed catalogs.
  - Source catalog parsing now also deduplicates duplicate package offers by `(plugin_id, version, package_kind)` (first entry wins), preventing one package release from appearing multiple times under different catalog entry IDs.
  - Source catalog parsing now filters malformed package identity metadata (`plugin_id`, `version`) before install flows, so only semantically valid plugin release entries reach source-install path.
  - Plugin install path carries manifest metadata (`pluginId`, `contractKind`, `capabilities`) into the local registry model so capability/contract inspection is available before runtime invocation.
  - Plugin registry loading now self-heals stale entries whose stored package files are missing, rewriting registry to only file-backed records so runtime binding resolution cannot stick on dead package pointers.
  - Added capability policy boundary (`WasmPluginCapabilityPolicyService`) and wired preflight to reject unknown manifest capabilities at install-time.
  - Added deterministic `PluginHostApiService` request/response boundary (`executed` / `blocked` / `rejected`) with response hashing and guard-gated semantic WASM execution as Host API v1.
  - Host API external-package boundary now validates `contractKind` against requested `plugin_id`; mismatched package metadata is rejected (`runtime_contract_kind_mismatch`) before contract execution.
  - Host API now validates external runtime binding shape (`package_id`, `package_kind`) before invoke and rejects malformed metadata as `runtime_binding_invalid`.
  - Host API external-package boundary now also validates declared runtime capabilities against required grants for requested `(plugin_id, method)` and rejects missing/unsupported capability sets (`runtime_capability_mismatch`) before contract execution.
  - Host response canonical boundary now includes normalized runtime capability metadata (`execution_capabilities`) for deterministic diagnostics and hash traceability.
  - Added host API v1 documentation (`docs/plugins/plugin_host_api_v1.md`) and regression coverage for deterministic hash, blocked guard path, unsupported plugin/method, and invalid-args rejection.
  - Host API runtime-binding path now supports `executeWithRuntimeHook(...)` with deterministic execution-source metadata (`host_fallback` vs `external_package` + package fields), including package-byte digest (`execution_package_digest_hex`) for resolved external packages; plugin screen panels/logs now surface source + digest hint for manual diagnostics.
  - Added deterministic plugin runtime path for external packages, later
    replaced by semantic ABI v2:
    - validates installed package bytes against binding digest (`execution_package_digest_hex`) before module extraction; digest mismatch is rejected as invalid runtime invoke
    - reads module bytes from resolved package (`.wasm` or first `.wasm` in `.zip`)
    - when zip manifest declares `runtime.module_path`, runtime stub resolves that exact module path and rejects missing targets
    - runtime module-path validation now rejects parent-traversal segments (`..`) while keeping deterministic support for normal dotted path segments
    - zip module auto-selection now ignores archive entries containing parent-traversal segments (`..`) so runtime evidence cannot bind to traversal-shaped module paths
    - runtime invoke now rejects zip packages where `.wasm` entries exist but all module paths are traversal-shaped (no safe runtime module candidates), producing explicit invalid-runtime diagnostics instead of ambiguous unavailable state
    - enforces strict ABI v2 manifest contract
      (`runtime.abi=hivra_host_abi_v2`,
      `runtime.entry_export=hivra_evaluate_v1`)
    - executes JSON-in/JSON-out semantics in the isolated Rust
      `hivra-wasm-runtime` adapter using import-free, fuel-bounded `wasmi`
    - validates alloc/evaluate/dealloc signatures, module/input/output limits,
      canonical output identity and SHA-256 integrity
    - emits `execution_runtime_mode`, `execution_runtime_module_digest_hex`, and `execution_runtime_invoke_digest_hex` in host response canonical boundary
    - keeps execution side-effect free and capability-neutral while wiring end-to-end runtime call path semantics
  - Host API/runtime diagnostics now also carry explicit runtime module path (`execution_runtime_module_path`), and plugin panels show that path alongside ABI/entry/invoke diagnostics for deterministic manual verification.
  - Host response now prioritizes runtime-selected module path (from invoke evidence) over manifest hint when they differ, with regression coverage to lock deterministic boundary output.
  - Runtime invoke evidence now carries explicit module-selection strategy (`manifest_module_path` / `lexical_first_wasm` / `package_wasm`), surfaced through host response for deterministic diagnostics.
  - Runtime invoke digest now binds module selection + module path in addition to module bytes, preventing same-byte different-path module selections from collapsing to identical invoke evidence.
  - WASM Plugins UI installed-package cards now show explicit runtime phase + ABI/entry diagnostics (`ABI ok/mismatch`, `Entry ok/mismatch`) so manual smoke testing does not require terminal log inspection.
  - BingX and Capsule Chat runtime panels now surface runtime invoke diagnostics from host responses (`runtime mode`, `ABI`, `entry export`, `invoke digest`) with explicit mismatch highlighting for ABI/entry.
  - BingX and Capsule Chat runtime panels now also show host-declared runtime capability diagnostics (`execution_capabilities`) with deterministic ordering and compact overflow hinting.
  - Runtime capability-chip display logic is now extracted into a shared utility (`summarizeRuntimeCapabilitiesForDisplay`) with dedicated unit tests, locking deterministic UI diagnostics shape for Host API capability responses.
  - WASM Plugins catalog/installed grids now use compact bounded layout (`maxColumns=3` with tighter aspect ratios), preventing oversized "skyscraper" plugin cards on wide desktop windows while keeping deterministic package diagnostics visible.

Definition of done:
- WASM drones extend user-facing behavior without bypassing core rules or rewriting local truth.
- Transport capabilities extend through host transport adapters, not through ordinary WASM drone packages.
- Status: completed (2026-04-19, v1 scope pre-runtime-execution).

## Working Rule

When tradeoffs are unclear, prefer:
1. one source of truth
2. deterministic reconstruction
3. explicit boundaries
4. fewer hidden side effects
5. release discipline over speed theater

- `9.4 Root-Scoped Pairwise Consensus Truth`
  - Current shared truth still anchors peers on transport identity, not peer root identity.
  - True root-scoped `pairwise consensus snapshot v2` cannot be derived from ledger alone until peer root identity is carried through invitation lineage and then anchored in relationship events.
  - Invitation lineage must first carry peer root truth so both sides can derive the same pair identity during accept/projection.
  - Relationship events then become the root-aware pair anchor:
    - extend `RelationshipEstablished` with `peer_root_pubkey` and `sender_root_pubkey`
    - extend `RelationshipBroken` with `peer_root_pubkey` so break operates on the same root-scoped pair truth
- Keep invitation transport payloads delivery-oriented where possible, but stop losing root provenance in the shared lineage.
- Keep current inspector snapshot explicitly transport-scoped until ledger truth is expanded.
- Current progress:
  - Flutter relationship projection decoders now accept root-augmented relationship payloads (`RelationshipEstablished` payloads longer than 194 bytes and `RelationshipBroken` payloads longer than 64 bytes) while keeping backward compatibility with existing payload layout.
  - Consensus processor now prefers `peer_root_pubkey` from root-augmented `RelationshipEstablished`/`RelationshipBroken` payloads when present, and falls back to legacy transport-key mapping otherwise.
  - Added regression coverage for root-augmented relationship payload handling in `ledger_view_support_test.dart`, `relationship_projection_service_test.dart`, `capsule_ledger_summary_parser_test.dart`, and `consensus_processor_test.dart`.
  - Core payload codecs now support root-augmented lineage/event shapes with backward-compatible parsing:
    - `InvitationAccepted`: `96` (legacy) or `128` bytes (`accepter_root_pubkey`)
    - `RelationshipEstablished`: `194` (legacy), `226` (`peer_root_pubkey`), or `258` bytes (`peer_root_pubkey + sender_root_pubkey`)
    - `RelationshipBroken`: `64` (legacy) or `96` bytes (`peer_root_pubkey`)
  - FFI invitation send path now appends sender root provenance into offer payload (`InvitationSent` extended variants `128/129`), while keeping legacy `96/97` offer parsing support in runtime lookup/projection paths.
  - `InvitationSentPayload` core codec now carries optional `sender_root_pubkey` (`96/97` legacy, `128/129` root-augmented), and engine `prepare_invitation_sent` now emits sender-root lineage by default; FFI send path keeps compatibility without double-appending root bytes.
  - Sender-side relationship projection from incoming `InvitationAccepted` now anchors peer root from `accepter_root_pubkey`, and local acceptance projection now anchors sender root when incoming offer carries sender-root provenance.
  - Break-relationship delivery now carries optional `peer_root_pubkey` in `RelationshipBroken` payloads when root anchor is known from established lineage.
  - Relationship peer grouping now collapses mixed transport links under the same root anchor (when root provenance exists), reducing transport-key fragmentation in relationship counters and peer cards while preserving per-link transport payloads for operations.
  - Relationship projection now infers peer root for legacy `RelationshipEstablished` payloads from root-augmented invitation lineage (`InvitationReceived`/`InvitationAccepted`) by `invitation_id`, reducing legacy transport-only peer identity drift in mixed ledgers.
  - Relationship projection now enforces local-addressed + remote-signed checks for `InvitationReceived` lineage fallback (`to_pubkey == local transport`, signer != local), preventing foreign or mirrored incoming records from polluting peer-root inference.
  - Invitation-lineage root inference now requires explicit local identity addressing even when runtime transport key is unavailable (owner-only fallback path), so foreign `InvitationReceived` rows cannot inject peer-root anchors during startup/switch windows.
  - `InvitationAccepted` lineage root fallback now requires known local transport anchor (`from_pubkey == local transport`), preventing ambiguous accepted rows from mutating peer-root mapping when transport identity is unavailable.
  - Relationship projection invitation-lineage fallback is now direction-aware: local `InvitationSent` and local-signed `InvitationAccepted` root fields are excluded from peer-root inference, preventing local-root leakage into peer identity (`npub/self-root` drift) for legacy relationship payloads.
  - Relationship projection now also filters transport-self peers (when runtime transport key is available), so mixed root/transport ledgers cannot project local `npub` self-links as active remote relationships.
  - Added `consensus_processor_test.dart` regression coverage that local invitation-lineage root fields (`InvitationSent.sender_root_pubkey`, local-signed `InvitationAccepted.accepter_root_pubkey`) are not treated as peer-root anchors during consensus peer mapping.
  - Consensus peer-root inference from `InvitationAccepted.accepter_root_pubkey` now requires a valid remote signer; unsigned/imported accepted rows no longer rewrite peer-root mapping in preview/signable paths.
  - Relationship projection now requires a valid remote signer for `InvitationAccepted` lineage fallback; unsigned/imported accepted rows no longer infer peer root, preventing signer-less drift between Relationships and Consensus views.
  - Signed `InvitationAccepted` lineage fallback remains invitation-anchored: peer root is inferred only when the same `invitation_id` is first seen in local offer lineage (`InvitationSent` / local-addressed `InvitationReceived`), preventing orphan accepted rows from creating phantom peer-root links.
  - Added projection/consensus regression coverage that remote-signed `InvitationAccepted` still anchors peer-root inference, preventing over-hardening regressions after removing unsigned/imported fallback paths.
    - Consensus invitation ingestion now mirrors local-address/signature projection rules:
      - `InvitationReceived` is accepted only when remote-signed and addressed to local identity;
      - foreign `InvitationSent` rows are ignored unless they are local-signed or explicitly addressed to local identity;
      - peer-signed `InvitationSent` addressed to local identity is treated as incoming pending lineage for consensus blocking.
    - Consensus ingestion now drops `InvitationReceived` facts not addressed to the active local transport key, preventing foreign/merged incoming records from creating phantom pending pairwise blockers during preview/signable checks.
    - Consensus preview now drops local-transport peer rows (in addition to local-root rows), preventing transport-self relationship artifacts from appearing as separate consensus peers in mixed/legacy payload histories.
  - Added runtime regression coverage (`consensus_runtime_service_test.dart`) that mirrored A/B root-anchored ledgers derive identical pairwise consensus hash, locking symmetric cross-capsule snapshot behavior.
  - Invitations and Relationships screens now share root-first identity formatting (`root as primary, transport as hint`) with fallback to transport label when root anchor is unknown.
  - Relationships screen root fallback now resolves imported contact-card root identity across all transport keys inside a peer group (not only the representative transport key), reducing false `npub` fallback in mixed-link groups.
  - Status: completed (2026-04-10, v1 scope).

- `9.5 Ledger-Gated Capsule UI`
  - Capsule UI should treat the local ledger as the primary source of domain truth once any ledger history exists.
  - If the ledger is empty, enter an explicit awaiting-history state instead of projecting starters, invitations, and relationships from runtime slot probes.
  - Rebuild UI state immediately after any ledger mutation source: local create/init, JSON import, backup restore, or transport-delivered events.
  - Keep invitation UI simple: block only clearly invalid cases such as self-invite, and avoid embedding pairwise-consensus policy directly into send forms.
  - Keep bootstrap/runtime fallback only for truly empty-ledger birth state, not as the normal steady-state source of capsule truth.
  - Current progress:
    - `LedgerViewService.loadCapsuleSnapshot` now keeps `hasLedgerHistory=false` when ledger exists but has zero events, preventing slot/state projection from bypassing the explicit awaiting-history UI state.
    - Added `ledger_view_service_test.dart` coverage for both branches:
      - empty-ledger snapshot stays awaiting-history and ignores capsule-state slot occupancy
      - non-empty ledger enables normal history-backed snapshot projection
    - Launch/resume invitation receive path now keeps ledger-first UX by running lightweight quick receive after first frame, with bounded quick timeout and dedupe guards:
      - quick receive timeout reduced to 8s (`InvitationActionsService`) to avoid long startup stalls under relay-connect degradation
    - quick receive dedupe is capsule-scoped in `InvitationIntentHandler` (in-flight coalescing + cooldown), so repeated screen/runtime reopen cycles do not trigger redundant receive workers for the same active capsule
      - added `invitation_intent_handler_test.dart` coverage for concurrent coalescing, cooldown skip, and per-capsule cooldown isolation
      - unknown capsule identity (`unknown`/empty) now bypasses quick-fetch dedupe/cooldown so startup capsule-switch windows cannot suppress receive checks by aliasing different capsules under one placeholder key
      - quick-fetch cooldown now applies only after successful fetch results (`code >= 0`), so transient receive failures do not suppress immediate retry on the same capsule
    - FFI now reuses per-capsule Nostr transport sessions (default + quick profiles) across send/receive/accept/reject/break paths instead of recreating transport on each action, reducing relay re-handshake churn during capsule switches and periodic refreshes
    - `hivra_reject_invitation` is now ledger-first: local `InvitationRejected` append occurs before/beside transport delivery so UI projections do not re-surface the same invitation as actionable pending during relay timeout/degradation windows; outbound reject delivery remains best-effort.
    - Superseded: outgoing invitations no longer auto-expire after 24h. Network silence is not a pairwise terminal fact; starters remain locked until accept/reject arrives or the user explicitly cancels.
    - Added `invitation_intent_handler_test.dart` coverage that fetch/quick-fetch paths do not synthesize `InvitationExpired` from overdue local timeouts.
    - Invitation projection now falls back to ledger `owner` when runtime owner key is temporarily unavailable, preserving incoming/outgoing classification from ledger truth instead of dropping invitation rows to empty.
    - Invitation projection incoming/outgoing classification is now local-identity aware (`owner + runtime transport`): offers addressed to local transport key are treated as incoming even when owner/root differs, reducing mixed root/transport pending misclassification.
    - Capsule selector summary parsing now feeds invitation/relationship projections with derived local transport identity when available (legacy owner key or root-seed nostr derivation), keeping header pending/relationship counters aligned with runtime screens in mixed root/transport histories.
    - Invitations screen now retains local incoming-resolution suppression after successful `accept/reject` until ledger projection reports terminal status, avoiding transient reappearance of the same pending row during post-action receive/update windows.
    - Local incoming-resolution suppression pruning is now absence-tolerant: suppression is cleared only when an invitation id is explicitly projected as non-pending/non-incoming, not when it is temporarily missing during refresh windows, reducing pending-row resurrection flicker across capsule switches.
    - Invitations screen fetch flow now queues refresh requests that arrive while an action/fetch is in-flight and drains them immediately after unlock, preventing dropped refresh intents during rapid accept/reject/switch interaction bursts.
    - Invitations screen lifecycle is now capsule-stable across ledger mutations (screen key no longer rotates on `ledgerVersion`), with explicit `didUpdateWidget` refresh on `ledgerVersion` and transient-state reset on active-capsule switch; this removes action-state loss/flicker caused by per-mutation widget re-creation.
    - Invitations async actions/fetch now drop stale completions when active capsule changes mid-flight, preventing old-capsule delivery/result messages from mutating the currently selected capsule view after switch.
    - `InvitationActionsService.rejectInvitation` timeout path now mirrors send/accept behavior by scheduling late worker-ledger apply, so timed-out reject workers can still reconcile local ledger truth when completion arrives after UI timeout.
    - `InvitationIntentHandler.rejectInvitation` now treats transport-failure codes with recorded local ledger state as success (`Local rejection is recorded`) and also trusts terminal local projection fallback, reducing duplicate-reject loops when network delivery degrades after local reject append.
    - Invitation projection now matches FFI ingress with first-valid-terminal
      semantics: an offer must already exist, the first terminal row wins, and
      later duplicate/conflicting terminal rows cannot replace it.
    - Added `invitation_projection_service_test.dart` regression coverage for
      accepted/rejected/expired first-terminal cases and terminal-before-offer
      rejection.
    - Consensus and relationship projections now suppress
      `RelationshipEstablished` rows whose invitation lineage was first
      finalized as rejected or expired; a late accepted row cannot restore the
      relationship or rewrite peer-root inference.
    - `InvitationIntentHandler` now short-circuits repeated terminal `accept/reject` attempts using current local projection state, so stale UI rows cannot re-trigger duplicate terminal actions against already resolved invitation lineage.
    - `respondedAt` comes from the first valid terminal ledger row; later rows
      cannot replace it using a smaller timestamp.
    - Invitation terminal projection (`Accepted/Rejected/Expired`) now requires valid signer width (32-byte signer), so malformed/imported unsigned terminal rows cannot mutate pending/terminal state.
    - Invitation projection now filters foreign invitation rows by local addressing rules: `InvitationReceived` must target local identity and be remote-signed, while foreign `InvitationSent` rows that are neither local-signed nor local-addressed are ignored, reducing phantom pending queues in merged/imported ledgers.
  - Status: completed (2026-04-10, v1 scope).

- `9.6 Ledger-Derived Slot Projection In Flutter`
  - Core already provides deterministic slot projection via `SlotLayout::from_ledger` and `CapsuleState::from_capsule`.
  - Legacy per-slot Flutter FFI probes (`starterExists/getStarterId/getStarterType`) have been removed from the active read-path and bindings surface.
  - Keep slot projection sourced from the same ledger-derived capsule state path used by core.
  - Current progress:
    - Architecture contract gate now enforces absence of legacy per-slot starter probes in Flutter bindings (`starterExists/getStarterId/getStarterType` and `hivra_starter_get_*` symbols), preventing accidental rollback to slot-side FFI reads.
  - Status: completed (2026-04-10).

- `9.7 Local Relationship Sovereignty And Pairwise Consensus`
  - Each capsule remains sovereign over its own relationship truth: one side may append `RelationshipBroken` locally without waiting for remote approval.
  - A break should still emit a remote notification so the peer can accept the break and converge onto the same pairwise state.
  - The remote side should not get a reject path for break-notifications; this is closer to accepting a delivered fact than negotiating a new invite.
  - Repeated starter sends toward an already-connected peer should not be silently repurposed into break semantics or other hidden ledger mutations.
  - Relationship mutation remains explicit, but invitation UI should stay lightweight and avoid taking on full pairwise-consensus policy.
  - Resulting model:
    - local break is immediately valid for the initiator
    - remote break notification remains in ledger and continues to project as pending until accepted
    - pairwise consensus exists only after the peer also accepts the break notification
    - if consensus is absent, pair-scoped smart contracts must not execute
    - any future pair-scoped contract with that capsule remains blocked until the old pending break is resolved
    - disagreement about one peer must not affect relationships or contracts with other capsules
  - UI implication: break-notification should be presented as a pending state transition to accept, not as a bidirectional accept/reject negotiation.
  - Runtime preserves a remote-signed break as `pending_remote_break` until explicit local acceptance; only the initiating capsule finalizes its local break immediately.
  - Pairwise event reading should remain layered:
    - invitation events record transit/history and terminal responses
    - starter events record local anatomy only
    - relationship events remain the pairwise truth anchors used for explicit relationship mutation and future smart-contract gating
  - Current progress:
    - Added `consensus_processor_test.dart` coverage that `RelationshipBroken` blocks only the affected pairwise path (`relationship_broken` fact) while other peer paths remain signable.
    - Relationship projection now treats remote-signed `RelationshipBroken` as a pending remote-break signal (keeps link active until local confirmation), while local-signed break events still finalize break immediately.
    - Relationship projection now falls back to ledger `owner` when runtime owner key is temporarily unavailable, preventing remote break notifications from being auto-projected as finalized local breaks.
    - Projection now preserves `local break > remote pending` precedence, so late/replayed remote break notifications cannot re-open a pending state after a local break was already finalized.
    - Added `relationship_projection_service_test.dart` coverage that this `local break > remote pending` precedence also holds when local owner is resolved via ledger fallback (restore/runtime-owner-unavailable path).
    - Relationship projection now requires a valid 32-byte `signer` on `RelationshipBroken` before classifying local-finalized vs remote-pending when local owner is known; malformed/missing signer break events are ignored instead of mutating state.
    - Relationship projection break classification now uses both local owner and local transport identity as deterministic signer anchors; when local identity is known, foreign-signed break events are ignored, and remote-signed breaks remain pending (never auto-finalized by missing owner context).
    - Ledger-owner fallback in relationship projection now treats owner as present only when raw owner bytes are actually available (32 bytes), preventing zero-filled owner fallbacks from misclassifying unsigned break events as deterministic local truth.
    - FFI `hivra_break_relationship` now applies local break ledger append before transport delivery and keeps remote notification best-effort (`TransportProfile::Quick`), so local relationship sovereignty is preserved during relay degradation windows.
    - `RelationshipService` peer root resolution now normalizes contact-card hex fields (case/separator tolerant), so relationship identity hints continue resolving `transport -> root` for cards created/imported under older formatting variants.
    - Added `RelationshipService.confirmRemoteBreak` edge-case coverage: invalid relationship ids and breaker refusal both return deterministic failure without persisting ledger snapshot.
    - Capsule summary relationship counts now reuse `RelationshipProjectionService` so header/list counters stay aligned with pending remote-break semantics instead of diverging on direct payload walks.
    - Relationships screen now exposes explicit pending-break confirmation action (single or chooser flow) so peer break notifications are finalized by deliberate user action instead of passive badge-only state.
    - `ConsensusProcessor` now keeps remote-signed break facts as explicit `pending_remote_break` blockers (when local root identity is available), instead of auto-demoting the pair to finalized `relationship_broken`; this aligns signability gating with pending-break UI semantics.
    - Added `hivra-ffi` regression coverage that a repeated `InvitationSent` toward an already active peer appends only invitation lineage (no implicit `RelationshipBroken` or hidden relationship-state mutation).
  - Status: completed (2026-04-10, v1 scope).

- `9.8 Consensus Processor Module`
  - Keep consensus logic out of screen flows and invitation form orchestration.
  - Build a dedicated processor module that:
    - consumes ledger projections
    - computes canonical pairwise snapshots
    - reports consensus state (`match`/`mismatch`) and blocking facts
  - Current progress:
    - Added `flutter/lib/services/consensus_processor.dart` with on-demand `preview`, `signable`, and `verify` APIs over ledger-derived pairwise projections.
    - Added `flutter/lib/services/consensus_runtime_service.dart` as a read-only runtime facade that feeds the processor from exported ledger truth plus local transport identity.
    - `ConsensusRuntimeService.checks()` now derives readiness from a single runtime-input + preview pass (instead of per-peer `signable` re-entry), keeping manual checks on-demand and avoiding repeated ledger/key reads inside one check cycle.
    - `ConsensusProcessor` now adds an explicit `no_active_relationship` blocking fact for peer paths with zero active relationship anchors, so pair-scoped contract execution stays blocked even when invitation history exists without a live link.
    - Runtime consensus identity now prefers local root key when a peer path is root-anchored (root-augmented `RelationshipEstablished` payload) and falls back to local transport key for legacy non-root paths, avoiding transport-coupling for modern paths while preserving legacy determinism.
    - Added `flutter/lib/services/plugin_execution_guard_service.dart` so the future plugin host can read pairwise signability as a guard input without taking on execution or screen-owned consensus logic.
    - Added `flutter/lib/services/manual_consensus_check_service.dart` so Ledger Inspector can consume a read-only manual consensus-check use case instead of building pairwise preview state directly.
    - Ledger Inspector screen no longer imports `consensus_runtime_service.dart` directly; consensus rows are typed/read through `ManualConsensusCheckService` boundary.
    - Ledger Inspector consensus checks are now explicit on-demand (`Run consensus checks`) and no longer auto-run during generic ledger refresh/reload, keeping consensus recomputation tied to deliberate user action.
    - Removed the legacy `PairwiseSnapshotService` wrapper after moving inspector/guard readers onto shared consensus boundaries.
    - Added processor regression coverage for canonical hash derivation, pending-invitation blocking facts, and verification mismatch reporting.
    - `ConsensusProcessor.verify()` now treats duplicate participant IDs in a signature set as an explicit blocking fact (`duplicate_participant`), with regression coverage to prevent ambiguous/replayed signature bundles from being treated as valid match input.
    - Duplicate-participant detection in `ConsensusProcessor.verify()` is now case-insensitive for hex participant IDs, so mixed upper/lowercase variants of the same capsule key cannot bypass duplicate-signature guards.
    - Consensus preview now ignores self-addressed outgoing invitations and self-signed incoming invitations, preventing self-loop delivery artifacts from appearing as pairwise peers or pending blockers in manual/plugin guard checks.
    - `ConsensusProcessor.signable()` now validates/normalizes `peerHex` input (case-insensitive hex), returning `invalid_peer_id` for malformed values, with regression coverage for uppercase and invalid peer-id paths.
    - Added runtime/guard regression coverage that remote-signed `RelationshipBroken` is propagated as `pending_remote_break` (with local root identity), so host execution guard blocks contracts without collapsing pair state into finalized `relationship_broken`.
    - `ConsensusProcessor` now ignores unsigned/malformed `RelationshipBroken` events when local root identity is available, aligning break classification with relationship projection semantics (deterministic local-finalized vs remote-pending split requires valid signer) and preventing unsigned break artifacts from mutating consensus state.
    - Added host API regression coverage that `pending_remote_break` survives plugin blocked-response canonicalization/hash path, ensuring plugin runtime consumers receive the same pairwise blocker semantics as guard/runtime services.
    - Added plugin demo runner regression coverage that execution-level `pending_remote_break` facts take precedence over stale check-level blockers, so partial-run summaries and blocked pair rows expose consistent remote-break gating semantics.
    - Added contract-level regression coverage for chat/trading plugin services that `pending_remote_break` blocks deterministic execution paths exactly as other consensus blockers, preventing contract-specific drift in guard semantics.
    - Added deterministic digest boundary for plugin execution diagnostics with explicit `guard_digest` (consensus-only) and `run_digest` (execution-inclusive), plus regression coverage for digest stability and ordering invariance.
  - Consensus must be computed on demand, not continuously in UI/runtime background.
  - Recalculation triggers are explicit:
    - smart-contract precondition check
    - user-requested manual consensus check
  - Processor API should support:
    - `preview` (derive and display snapshot/hash)
    - `signable` (derive hash to be signed)
    - `verify` (validate signatures and hash equality)
  - Expose processor output as read-only inputs to UI and plugin execution guards.
  - Do not mix processor rollout with transport send/receive UX changes.
  - Status: completed (2026-04-10, v1 scope).

- `9.9 UI-FFI Boundary Reduction`
  - Reduce direct `HivraBindings` imports in UI screens by moving operational calls into service/facade boundaries.
  - Baseline at start:
    - `12` screens import `HivraBindings` directly
    - `7` services import `HivraBindings` directly
  - Current snapshot:
    - `0` screens import `HivraBindings` directly
    - `0` services import `HivraBindings` directly (explicit allowlist in review gate)
    - `FirstLaunchService` no longer imports `HivraBindings`; it now consumes `CapsuleDraftRuntime` boundary with `HivraCapsuleDraftRuntime` adapter at FFI layer
    - `BackupService` no longer imports `HivraBindings`; it now consumes `BackupRuntime` boundary with `HivraBackupRuntime` adapter at FFI layer
    - `CapsuleAddressService` no longer imports `HivraBindings`; it now consumes `CapsuleAddressRuntime` boundary with `HivraCapsuleAddressRuntime` adapter at FFI layer
    - `CapsuleSelectorService` no longer imports `HivraBindings`; it now consumes `CapsuleSelectorRuntime` boundary with `HivraCapsuleSelectorRuntime` adapter at FFI layer
    - `RecoveryService` no longer imports `HivraBindings`; it now consumes `RecoveryRuntime` boundary with `HivraRecoveryRuntime` adapter at FFI layer
    - `SettingsService` no longer imports `HivraBindings`; it now consumes read-only runtime boundaries injected from `AppRuntimeService`
    - `InvitationProjectionService` no longer imports `HivraBindings`; runtime owner key is now injected via provider boundary from `LedgerViewService`
    - `RelationshipService` no longer imports `HivraBindings`; it now consumes injected callbacks for `load groups`, `break relationship`, and `persist snapshot`
    - `CapsuleStateManager` no longer imports `HivraBindings`; it now consumes ledger snapshot projection through `LedgerViewService` boundary
    - `CapsuleFileStore` no longer imports `HivraBindings`; runtime capsule directory resolution now consumes runtime-owner callback boundary
    - `LedgerViewService` no longer imports `HivraBindings`; it now consumes `LedgerViewRuntime` boundary with `HivraLedgerViewRuntime` adapter at FFI layer
    - `CapsuleRuntimeBootstrapService` no longer imports `HivraBindings`; it now consumes `CapsuleRuntimeBootstrapRuntime` boundary with `HivraCapsuleRuntimeBootstrapRuntime` adapter at FFI layer
    - `InvitationActionsService` no longer imports `HivraBindings`; worker entrypoints and persistence/FFI operations now flow through `InvitationActionsRuntime` boundary with `HivraInvitationActionsRuntime` adapter at FFI layer
    - `AppRuntimeService` no longer imports `HivraBindings`; it now consumes `AppRuntimeRuntime` boundary with `HivraAppRuntimeRuntime` adapter at FFI layer
    - `CapsulePersistenceService` no longer imports `HivraBindings` directly; it now consumes `CapsulePersistenceBindings` boundary from FFI layer
    - UI entrypoint `main.dart` no longer imports `HivraBindings` directly
    - review gate also protects `widgets/` and `utils/` from direct `HivraBindings` imports
    - `tools/review/ui_ffi_boundary_gate.sh` now enforces a service-level import budget and fails if new service files add direct `HivraBindings` ownership outside the allowlist
  - Prioritize extracting read-only screens and backup/recovery orchestration first.
- Definition of done for this slice:
  - screens depend on application services/facades, not raw FFI bindings
  - FFI access is concentrated in a smaller boundary layer with explicit ownership
- Status: completed (2026-04-10).

- `9.10 Execution Discipline Standard`
  - Codify one internal execution discipline for new modules and refactors.
  - Scope:
    - explicit action path (`intent -> effect -> ledger -> projection`)
    - isolated effect boundaries for network/filesystem/keys/time
    - async resolve-once discipline with stale-completion drop
    - shared projection ownership (no screen-local reinterpretation)
  - Current progress:
    - Added `docs/architecture-execution-discipline.md` as internal architecture standard.
    - Added module-creation and refactor acceptance checklists aligned to:
      - modular ownership
      - deterministic replay/projection behavior
      - strict downward dependencies
    - `UiEventLogService` now serializes concurrent log writes and sanitizes legacy torn log lines on first write, so operational diagnostics stay deterministic and parseable under concurrent UI actions.
    - Starters send-success flow now finalizes through screen-level lifecycle (not modal lifecycle), preventing stale modal unmount from dropping ledger-refresh/message side effects after successful invitation send.
    - Removed duplicate UI-level send timeout in Starters flow; invitation send now relies on single worker timeout boundary from `InvitationActionsService`, avoiding competing timeout branches for one intent.
    - Interactive outbound delivery paths (`InvitationSent` / `InvitationAccepted` / `InvitationRejected` / `RelationshipBroken` notification / capsule chat send) now use cached `TransportProfile::Quick`, reducing latency while keeping ledger-first local truth discipline.
    - Invitations send path now emits explicit `invitations.send.finally` timing diagnostics (`elapsedMs`, `resultCode`, widget mount state) so both send entry points share the same resolve-once observability.
    - `tools/review/architecture_contract_gate.sh` now enforces baseline execution-discipline sync across:
      - `docs/architecture-execution-discipline.md`
      - `docs/README.md` index reference
      - roadmap tracking (`9.10`)
      - architecture checklist section and canonical action-path review item
  - Definition of done:
    - New architectural work uses one documented execution discipline.
    - Review and implementation discussions reference internal Hivra rules instead of ad hoc patterns.
  - Status: completed (2026-04-10).

## Active Debt Kill List

No active `9.x` architecture debt remains in v1 scope before trading-agent build.
No active `10.x` plugin-host debt remains in v1 scope before trading-agent build.
No active `11.x` trading-drone / AI-engineer module-boundary debt remains in v1 scope before release smoke.

- `12.1 Trading Drone UI Type Boundary Audit`
  - Goal:
    - reduce UI coupling to concrete trading/plugin service implementation files
      without changing runtime behavior or weakening the module boundaries.
  - Current problem:
    - `TradingDroneScreen` and `WasmPluginsScreen` now use module services for
      service-graph construction, but still import many concrete service files
      because UI-facing DTO/result types live beside service implementations.
    - this is not a current runtime bug, but it keeps the screens wider than a
      clean projection/action surface and makes future service refactors riskier.
  - Scope:
    - audit imports used only for DTO/result/projection types.
    - move stable UI-facing types into neutral model/projection files where it
      reduces coupling without creating microfile sprawl.
    - keep service construction behind `TradingDroneModuleService` and
      `PluginRuntimeModuleService`.
    - extend architecture gates only after the model boundary is real enough to
      enforce without false positives.
  - Constraints:
    - no trading decision logic moves into widgets or screens.
    - no plugin-source code moves into Hivra-App.
    - no Core/engine/platform dependency changes.
  - Current progress:
    - `TradingDroneScreen` now keeps one `TradingDroneModule` reference instead
      of separate fields for every trading/plugin/chat/log service, reducing
      screen-owned service surface while preserving runtime behavior.
    - `WasmPluginsScreen` now keeps one `PluginRuntimeModule` reference instead
      of separate registry/source-catalog/host/chat/log service fields.
    - WASM plugin registry/source-catalog DTOs now live in
      `models/wasm_plugin_models.dart`, so `WasmPluginsScreen` no longer imports
      registry/source-catalog service implementations just to render plugin
      projections.
    - BingX futures order-tracking DTOs now live in
      `models/bingx_futures_order_tracking_models.dart`; `TradingDroneScreen`
      uses the module-owned order tracking store instead of keeping its own
      concrete store field.
    - Capsule chat/trade-signal inbox DTOs now live in
      `models/capsule_chat_models.dart`, so trading/plugin screens no longer
      import `CapsuleChatDeliveryService` just to render received messages.
    - Plugin contract IDs/method names now live in `models/plugin_contract_ids.dart`,
      so screens do not import plugin contract handler implementations just to
      address plugin host requests.
    - `InvitationsScreen` now keeps one `InvitationModule` reference for
      invitation intents, relationship projection helpers, contact-card writes,
      delivery formatting, and UI diagnostics instead of assembling those
      service dependencies directly in the screen.
    - `LedgerInspectorScreen` now keeps one `LedgerInspectorModule` reference
      for state refresh, ledger export, root-key lookup, and manual consensus
      checks instead of constructing service dependencies directly in the
      inspector UI.
    - `MainScreen` now keeps one `MainScreenModule` reference for child screen
      service factories, so the navigation shell no longer assembles
      relationship/settings service dependencies directly.
    - BingX futures risk DTOs now live in
      `models/bingx_futures_risk_models.dart`; `TradingDroneScreen` imports
      risk policy/decision types from the model boundary while
      `BingxFuturesRiskGovernorService` remains behavior-only.
    - BingX futures live-decision DTOs now live in
      `models/bingx_futures_live_decision_models.dart`; `TradingDroneScreen`
      imports decision input/result types from the model boundary while
      `BingxFuturesLiveDecisionService` remains behavior-only.
    - BingX futures exchange DTOs now live in
      `models/bingx_futures_exchange_models.dart`; `TradingDroneScreen`
      imports credentials, intent payload, open-order, execution, and public
      market result types from the model boundary while
      `BingxFuturesExchangeService` remains behavior-only.
    - BingX futures order-sizing DTOs now live in
      `models/bingx_futures_order_sizing_models.dart`; `TradingDroneScreen`
      imports sizing status/result types from the model boundary while
      `BingxFuturesOrderSizingService` remains behavior-only.
    - BingX futures signal-rank DTOs now live in
      `models/bingx_futures_signal_rank_models.dart`; `TradingDroneScreen`
      imports scan candidate/result/entry types from the model boundary while
      `BingxFuturesSignalRankUseCaseService` remains behavior-only.
    - BingX futures live-strategy DTOs now live in
      `models/bingx_futures_live_strategy_models.dart`; `TradingDroneScreen`
      imports strategy command/result types from the model boundary while
      `BingxFuturesLiveStrategyUseCaseService` remains behavior-only.
    - BingX futures intent DTOs now live in
      `models/bingx_futures_intent_models.dart`; `TradingDroneScreen` imports
      intent command/result types from the model boundary while
      `BingxFuturesIntentUseCaseService` remains behavior-only.
    - BingX futures execution DTOs now live in
      `models/bingx_futures_exchange_execution_models.dart` and execution queue
      DTOs now live in `models/bingx_futures_execution_queue_models.dart`;
      `TradingDroneScreen` imports execution status/result types from the model
      boundary while execution services remain behavior-only.
    - BingX futures replacement DTOs now live in
      `models/bingx_futures_order_replacement_models.dart`;
      `TradingDroneScreen` imports replacement plan/runtime result types from
      the model boundary while `BingxFuturesOrderReplacementService` remains
      behavior-only.
  - Remaining follow-up:
    - No active trading-domain DTO/result import remains in
      `TradingDroneScreen`; continue to enforce new model boundaries through
      architecture gates before adding future trading UI surfaces.
    - Plugin-host and consensus DTO extraction is complete in `12.2`; keep
      future cleanup focused on trading-domain DTO/result boundaries only.
  - Status: completed for screen-owned service-field cleanup and low-risk DTO
    boundary extraction (2026-07-07).

- `12.2 Consensus and Plugin Host Model Boundary`
  - Goal:
    - separate stable consensus/plugin-host DTOs from their service
      implementations without weakening pair-scoped consensus or semantic WASM
      execution rules.
  - Original problem:
    - `PluginHostApiRequest`, `PluginHostApiResponse`,
      `PluginRuntimeBinding`, and `PluginRuntimeInvokeEvidence` live beside
      `PluginHostApiService`, so UI and service clients import the concrete host
      service file for API envelopes.
    - these plugin-host DTOs depend on `ConsensusBlockingFact`, which currently
      lives beside `ConsensusProcessor`; moving plugin-host DTOs first would
      create a model -> service dependency and violate downward discipline.
  - Scope:
    - first move stable consensus DTOs (`ConsensusBlockingFact`,
      `ConsensusPreview`, `ConsensusSignableResult`, verify result/participant
      types) into one neutral consensus model boundary.
    - then move plugin-host API/runtime envelope DTOs into one neutral plugin
      host model boundary.
    - keep `ConsensusProcessor`, `ConsensusRuntimeService`,
      `PluginHostApiService`, and plugin contract handlers as behavior/services.
    - add architecture gates only after the model boundary is real and does not
      false-positive on service implementations.
  - Constraints:
    - no consensus semantics change.
    - no plugin execution semantics change.
    - no screen-local consensus or plugin-host logic.
    - no god model: split only into consensus models and plugin-host models.
  - Progress:
    - Stable consensus DTOs now live in
      `flutter/lib/models/consensus_models.dart`; `ConsensusProcessor` remains
      behavior only.
    - Stable plugin-host API/runtime DTOs now live in
      `flutter/lib/models/plugin_host_api_models.dart`; `PluginHostApiService`
      remains behavior only.
    - Architecture gates now prevent screens, contract handlers, and WASM
      runtime service from importing plugin-host DTOs through the concrete host
      service.
  - Status: completed (2026-07-07).

- `11.30 Explainable Capsule History`
  - Goal:
    - provide one ledger-backed history surface for relationships,
      invitations, and starters without provider dependencies in cards.
  - Contract:
    - typed entity subjects select only relevant confirmed ledger events;
    - projection order and hash are deterministic under replay;
    - App Shell owns navigation and AI module assembly;
    - optional AI explanation receives only explicit redacted evidence and has
      no mutation, consensus, or authorization authority.
  - Verification:
    - projection scope and replay-hash tests;
    - AI payload redaction/provider-boundary tests;
    - relationship, invitation, and occupied-starter card navigation smoke;
    - `tools/review/review_all.sh`, `flutter analyze`, and `flutter test`.
  - Status: completed (2026-08-01). Core owns the canonical history view;
    Flutter projects the typed subject and optional redacted AI explanation.

- `12.3 Integrity and Reliability Remediation`
  - Goal:
    - close the July 2026 review findings in risk order without weakening the
      three Hivra laws: modularity, determinism, and downward-only dependencies.
  - Execution order:
    1. Serialize all ledger-mutating transport workers per capsule across UI
       timeouts, background retries, screen instances, and capsule switches.
       A late worker may finish and persist its own capsule, but a second worker
       MUST NOT start from the same ledger revision and create a competing tail.
    2. Upgrade Pair Consensus from local signability to an explicit two-party
       signed snapshot protocol. Pair-scoped drone effects MUST fail closed
       until both root identities sign the same canonical pair hash.
    3. Define and implement a cryptographically continuous ledger protocol in
       which signed event identity commits to ordering-critical fields and the
       previous signed history commitment. Migration compatibility MUST be
       designed before changing the protocol version.
    4. Replace aggregate delivery retry markers with event-scoped durable
       delivery records bound to domain event/invitation id, recipient,
       transport, and adapter receipt. One successful envelope MUST NOT resolve
       unrelated pending deliveries.
    5. Connect Trading Drone risk policy to persisted realized-loss history so
       loss-streak cooldown and last-loss time are real production inputs, not
       constant placeholders.
       - Complete for the maintained 1.x runtime: the host reads BingX
         `REALIZED_PNL` income records over the supported 90-day window,
         normalizes and deduplicates them by stable exchange transaction/trade
         identity, and atomically persists a Capsule-scoped risk projection.
       - The risk governor receives the current UTC-day account-wide realized
         PnL, consecutive non-zero loss count, and actual last-loss time.
         Account-wide scope is intentional: manual losses also reduce the
         capital available to an autonomous drone.
       - This projection is plugin/external-effect state. It is not written to
         the Capsule Core ledger and is not a second order journal.
       - Live execution fails closed when exchange history is unavailable,
         malformed, non-USDT, conflicting, cannot be persisted, or reaches the
         unpageable 1000-record response limit.
    6. Migrate confidential transport payloads away from deprecated NIP-04 to
       an authenticated current envelope while preserving the transport adapter
       boundary and replay/idempotence rules.
    7. Make plugin install/update/remove transactional and serialized; registry
       state and package files MUST survive interruption without dead pointers
       or lost concurrent updates.
    8. Add encrypted backup envelopes and temporary-export cleanup, repair
       stale protocol/WASM documentation, and continue splitting oversized UI
       surfaces only at existing module boundaries.
    9. Add a shared Transport Health Policy v1 above host transport adapters.
       It MUST provide capsule-scoped cooldown/backoff, network-degraded
       diagnostics, manual retry semantics, and one policy surface reused by
       invitations, chat, pair attestations, relationship notifications, and
       trading signals. Ledger projection and pair consensus MUST remain
       independent from transport health state.
  - Verification contract:
    - each pass adds a regression test that fails on the reviewed weakness.
    - `tools/review/review_all.sh`, `cargo test --workspace`, `flutter analyze`,
      and `flutter test` remain green after every pass.
    - security- or protocol-changing passes require focused manual smoke before
      release evidence can be recorded.
    - important passes are committed separately; publication still follows the
      guarded release workflow.
  - Current progress:
    - audit findings recorded and ordered on 2026-07-10.
    - pass 1 completed on 2026-07-10:
      - every invitation transport worker now enters one shared
        capsule-scoped queue, including background retries and workers that
        outlive a UI timeout.
      - bootstrap is refreshed inside the queue and the resulting ledger is
        applied or persisted before the next worker for that capsule starts.
      - workers for different capsules remain independent.
      - queue ordering, cross-capsule independence, and recovery after worker
        failure have focused regression coverage; the architecture gate
        prevents reintroducing the late-worker bypass.
    - pass 2 (two-party signed Pair Consensus) completed on 2026-07-10:
      - 2a: signature-set verification now fails
        closed without a cryptographic verifier, and production runtime wires
        the existing root Ed25519 verification adapter.
      - 2b: canonical domain-separated pair
        attestation commitments are symmetric and validated, and the FFI
        exposes fixed-size root signing without exposing seed/private key
        material to Flutter.
      - 2c: pair attestations now have a dedicated
        host transport kind, Flutter worker bindings, a capsule-scoped
        `pair_consensus_attestations.json` store, and receive orchestration
        that recomputes commitments and verifies root signatures before merge.
      - 2d: pair-scoped plugin host runtime-hook
        preflight now uses exact two-root verified attestation evidence instead
        of local signability alone; solo futures and signal-ranking paths remain
        consensus-free by design.
    - Transport Health Policy v1 debt recorded on 2026-07-11:
      - existing `hivra-transport` remains a separate adapter module, but retry,
        cooldown, preflight, and receive orchestration are currently split
        across FFI and Flutter service paths.
      - degraded-network behavior can make multiple subsystems repeatedly hit
        the same failing transport (`-1003` fetch/receive timeouts) without one
        shared cooldown state.
      - implementation MUST follow `docs/checklists/transport-health-policy.md`
        before release.
      - first implementation slice completed on 2026-07-11:
        - added a shared Flutter application-level
          `TransportHealthPolicyService` with capsule-scoped timeout backoff.
        - invitation receive, pair-attestation receive, chat receive, and
          trading-signal receive paths now share one cooldown decision surface.
        - manual send paths still record timeout/success results but are not
          silently blocked by passive receive cooldown.
        - focused regression coverage proves timeout -> cooldown -> success
          recovery and cross-capsule independence for invitations, pair
          attestations, and chat/trading-signal receive.
      - remaining follow-up:
        - completed in pass 9 on 2026-08-03: relationship notification refresh
          reuses the canonical invitation/domain receive worker with explicit
          one-attempt manual retry; no relationship-specific route was added.
        - completed in pass 9 on 2026-08-03: the shared policy exposes a
          capsule-scoped degraded snapshot and the main UI renders actionable
          cooldown diagnostics.
        - explicit invitation, relationship, chat, and trading-signal refresh
          can bypass one passive cooldown for one operation; lifecycle and
          background receive remain gated, and success clears degradation.
    - Transport Delivery Lifecycle v1 consolidation slice completed on
      2026-07-11:
      - extracted retry timing, receipt reconciliation, and capsule-scoped
        background-pump lifetime from `InvitationActionsService` into one
        `CapsuleDeliveryLifecycleService`.
      - invitation send/accept/reject recovery and locally initiated
        relationship breaks now enqueue the same lifecycle; a relationship
        break no longer waits for an unrelated invitation refresh to start
        recovery.
      - documented the hard boundary between Ledger truth, the recovery index,
        lifecycle scheduling, transport adapters, and UI projection in
        `docs/architecture/transport-delivery-lifecycle.md`.
      - this initial extraction did not close execution-order item 4; the later
        pass now binds current invitation and relationship-break obligations to
        immutable event references and persists matching adapter publication
        evidence in the same outbox record. Legacy unreferenced records were
        classified as quarantine debt rather than a second retry path; pass 10
        later enforced that state in the persisted recovery index.
    - Capsule Selection Ownership remediation completed on 2026-07-14:
      - explicit create/recover/select flows remain the only writers allowed to
        change `capsules_index.active`;
      - ledger persistence and worker completion update capsule metadata without
        changing the selected capsule;
      - index read-modify-write operations are serialized so a background
        metadata upsert cannot restore a stale active pointer;
      - MainScreen pins one capsule selection for its lifetime and ignores a
        transient foreign runtime projection while a worker restores the
        selected runtime.
    - Current unreleaseable integration work (2026-07-24) uses one generic
      `DeliveryEnvelope v1`/`DeliveryReceipt` boundary for transport routing,
      preserves domain semantics at the receiving capability, and keeps local
      user-assigned peer names as per-capsule operational metadata rather than
      ledger facts or contact-card mutations. It does not close pass 3 or pass
      4 and must pass fresh platform smoke before becoming a release candidate.
    - Transport ingress hardening slice completed on 2026-07-25:
      - one transport-neutral guard now rejects unsupported envelope schemas,
        wrong transport recipients, and opaque payloads above 256 KiB before
        invitation, chat, attestation, or drone-signal routing;
      - the Nostr adapter authenticates the outer signer first and records
        deterministically rejected event ids in its overlap dedup set, so one
        malformed retained event cannot be reprocessed on every fetch;
      - at this audit point sender-class rate limiting remained
        `NEEDS_CONTRACT`; passes 12-16 later closed the acknowledged handoff,
        bounded encrypted quarantine, and persisted sender policy without
        silently dropping valid envelopes after relay cursor advancement.
    - pass 3 protocol contract completed on 2026-07-24:
      - `docs/architecture/continuous-ledger-protocol-v5.md` defines distinct
        signed domain provenance and locally signed sequential ledger-entry
        acceptance;
      - v4 import remains explicit legacy compatibility and cannot be claimed
        as cryptographically continuous history;
      - implementation now proceeds only through P3-A Core vectors, P3-B
        Engine/FFI append-import, and P3-C persistence/release evidence.
    - P3-A completed on 2026-07-24:
      - Core keeps one canonical `Ledger` event sequence; v5 receipts attest
        to those facts without a parallel event container;
      - the signed v4 migration anchor keeps legacy history auditable before
        subsequent v5 entries.
    - P3-B Engine signing boundary completed on 2026-07-24:
      - Engine is the only new path that prepares and verifies signed v5 domain
        provenance, local ledger entries, and legacy migration anchors;
      - fresh FFI runtime creation and append now select v5; a valid v4 import
        is anchored before new mutation, and a transport proof carries the
        exact signed event version;
      - P3-C now writes a ledger generation through the single authoritative
        order `ledger -> backup -> derived Core projection`; each file uses
        temp/flush/rename and never deletes an existing target after a failed
        replacement. v5 exports carry `head_commitment_v5` separately from
        the retained v4 `last_hash` checksum, so UI and backup selection use
        the real continuous-history head;
      - focused restart/restore and cross-platform recovery evidence remains
        the release blocker.
      - P3-C automated recovery evidence now proves that backup wrapping
        preserves the complete v5 continuity object and that partial backup or
        derived-projection write failures retain the authoritative ledger
        generation without inventing a second truth. Packaged macOS/Android
        restart and restore smoke remains required before pass 3 closes.
      - local Android continuity smoke completed on 2026-08-01 at `39ba870`
        (`versionCode=100000317`): an explicit seed plus backup restore after
        uninstall reconstructed the same owner and ledger `v74` projection,
        and a cold restart preserved it. This narrows the remaining blocker but
        does not replace packaged macOS/Android evidence for the next release
        candidate.
      - current-line Android update/restart smoke completed on 2026-08-01 from
        source `9df510c` using a development `versionCode=100000318` installed
        over `100000317`: both cold starts selected the same Capsule
        `5996bcbe...0d6e` and projected the same ledger `v74`; bootstrap and
        Keystore access completed without errors. This is build-tree continuity
        evidence only. It does not satisfy clean packaged restore or release
        signoff for `v1.0.3-test15`.
      - current-source Android clean restore smoke completed on 2026-08-01 at
        `1d12554`: after uninstall and clean install, standalone backup import
        required the matching recovery phrase before activation, restored
        owner `5996bcbe...0d6e` with ledger `v74`, persisted the seed in Android
        Keystore, and cold-started again without another phrase prompt while
        preserving the same owner and ledger. This validates the repaired
        backup-to-seed binding path but remains development evidence until the
        guarded packaged candidate is built and signed off.
      - accepted-terminal projection reconciliation completed on 2026-08-01
        at `c91cd81`:
        - relay diagnostics proved that Android fetched and authenticated the
          retained `InvitationAccepted` envelopes while the signed terminal
          facts already existed in the local ledger;
        - replay now idempotently reconciles a missing
          `RelationshipEstablished` derivation instead of treating the
          terminal fact as an exhausted no-op;
        - the repair appends only missing signed derived facts and never
          rewrites prior ledger history;
        - focused regression coverage preserves one `InvitationAccepted` and
          one derived relationship under repair;
        - manual Android evidence restored `Kick`, `Spark`, `Juice`, and
          `Seed` parity with peer `h1jd57...49q2vl`, advanced the ledger from
          `v74` to `v79`, and retained `v79` across a cold restart.
      - local macOS cold-restart smoke completed on 2026-08-01 from the same
        runtime checkpoint: the selector reconstructed three existing capsules
        at ledger versions `94`, `49`, and `111`; all three canonical
        `ledger.json` SHA-256 values were byte-identical before and after the
        restart. This is continuity evidence only, not packaged restore signoff.
      - selector and peer-identity cleanup completed at `e1c0c0a` and
        `074b586`: selector rows read public summaries without activating a
        Capsule or unlocking its seed, while local peer labels retain a
        separate shortened root Capsule ID in operational UI.
    - pass 4 event-scoped delivery records completed at `7297948`:
      - current invitation and relationship-break obligations are bound to one
        immutable domain reference and one exact retry endpoint;
      - normalized adapter publication evidence updates only the matching
        outbox item through its correlation id;
      - ambiguous legacy aggregate records were excluded from the new exact
        retry contract and registered for explicit quarantine instead of batch
        replay; pass 10 later made that quarantine executable and durable.
    - pass 5 persisted Trading Drone risk history completed at `bdabae8`:
      - exchange-derived `REALIZED_PNL` history now supplies UTC daily loss,
        consecutive loss count, and last-loss time through one Capsule-scoped
        risk projection;
      - unavailable, conflicting, malformed, or unpageable history fails
        closed and never becomes Core ledger truth.
    - pass 6 authenticated confidential transport envelope completed on
      2026-08-02:
      - the canonical Nostr write path now emits signed regular kind `9444`
        events containing NIP-44 v2 authenticated `DeliveryEnvelope v1`
        ciphertext;
      - receive verifies the outer NIP-01 id/signature before decryption,
        requires exactly one local recipient tag, binds the decoded sender to
        the event signer, and preserves the existing common envelope guard;
      - kind `9444` never falls back to NIP-04 after an authentication or
        version failure, preventing wire-format downgrade;
      - deprecated kind `4`/NIP-04 remains only as an isolated read-only
        rolling-compatibility decoder and cannot send, translate, retry, or
        create another transport lifecycle;
      - focused regression coverage proves NIP-44 round-trip, MAC rejection,
        sender spoof rejection, exact recipient binding, schema rejection, and
        strict downgrade isolation while preserving correlation metadata.
    - pass 7 transactional and serialized plugin package lifecycle completed
      on 2026-08-02:
      - `WasmPluginRegistryService` serializes load/install/update/remove across
        service instances and remains the only registry/package owner;
      - install and update stage and validate the candidate before an atomic
        registry commit, while source-catalog metadata rejection preserves the
        previously active version;
      - remove commits deregistration before deleting package bytes, so an
        interruption can leave only a recoverable orphan and never a new dead
        registry pointer;
      - serialized load removes orphan packages and atomic temporary files,
        while mutations fail closed on malformed registry state;
      - concurrency, failed update/remove commit, interruption recovery, and
        catalog-mismatch regression tests cover the reviewed weakness;
      - the normative lifecycle is recorded in
        `docs/architecture/plugin-package-lifecycle.md`.
    - pass 8 encrypted backup/export and boundary repair implementation
      completed on 2026-08-03:
      - new user-visible exports use authenticated `hivra.capsule_backup` v2
        envelopes with HKDF-SHA256 seed derivation, fresh salt/nonce, and
        AES-256-GCM; Ledger and metadata remain encrypted;
      - recognized v2 input rejects wrong seed, tampering, malformed fields,
        and unsupported suites without plaintext downgrade;
      - plaintext v1/raw Ledger remains read-only compatibility input and the
        local v1 snapshot remains internal recovery state, not a new export;
      - one temporary-share lifecycle deletes its directory in `finally` and
        both backup screens delegate export/share orchestration to services;
      - recovery decrypts only after mnemonic validation, and selector import
        binds the decrypted owner to the supplied seed before persistence;
      - Android disables OS Auto Backup and excludes every private storage
        domain from both legacy backup and Android 12+ cloud/device-transfer
        extraction, so the authenticated v2 envelope remains the sole
        cross-install recovery route;
      - the normative specification, architecture gate, and plugin host API
        now distinguish plugin contract v1 from semantic WASM ABI v2 and lock
        the current import-free bounded runtime contract.
    - Fresh macOS manual smoke on 2026-08-03 proved a v2 export with no visible
      Ledger fields, recursive temporary-share cleanup, byte-identical
      105-event recovery, and zero imported Capsules for wrong-seed and
      modified-ciphertext attempts.
    - Android export/cancel smoke on 2026-08-03 kept the release process alive
      and returned from the system chooser without crash or ANR. An attempted
      ephemeral-user recovery exposed that the previous manifest default
      allowed OS restoration of private Capsule state; the test was stopped,
      user `0` returned intact at owner `5996bcbe...0d6e` and Ledger `v82`, and
      the implicit OS recovery route is now sealed by manifest and extraction
      rules.
    - The next fresh-profile attempt exposed a hardcoded owner-user keystore
      path. The existing JNI initialization boundary now supplies the active
      process `Context.filesDir`; a host regression test covers secondary-user
      path derivation and the architecture gate forbids `/data/user/0` and
      `/data/data` hardcodes. This keeps one secure-store adapter route and
      adds no Core recovery path.
    - Fresh Android release artifact `versionCode=100000319`, SHA-256
      `d7268dbd2d26fa79c22175b78fdda353f7d0d7c20ab626a61ca904ab4fe52b46`,
      completed pass 8 smoke on 2026-08-03. A clean secondary profile started
      without restored Capsule state, explicitly recovered the six-event test
      Ledger through the v2 envelope, and retained Ledger `v6` after a cold
      restart, proving seed persistence through that profile's app-private
      path. Wrong-seed and modified-ciphertext attempts each failed
      authentication and left zero local Capsules. The temporary profile was
      removed, and owner user `0` remained intact on Ledger `v82` after the
      package update. No crash, ANR, or old app-private-path error was present.
    - Pass 9 completed on 2026-08-03:
      - all required automated gates pass: `git diff --check`, `flutter analyze`,
        full `flutter test` (713 tests), `cargo test --workspace`, and
        `tools/review/review_all.sh`.
      - fresh macOS release smoke activated Capsule Ledger `v105`, completed
        canonical transport receive and pair-attestation receive, and showed no
        process crash, fault, or hidden receive loop.
      - fresh Android release APK `versionCode=100000319`, SHA-256
        `8d2ccfd07b337a01b21c20de46aab203f91298e2e3dda03fc1dbb90dcedce6f0`,
        updated in place while preserving the original install/data boundary,
        activated Capsule Ledger `v82`, completed canonical receive and
        attestation, and showed no crash or retry storm.
      - Android network-loss smoke restored airplane/Wi-Fi/mobile state;
        transport send failures remained adapter-level (`-11`) and did not
        alter Ledger truth or create a second retry route. Timeout/cooldown,
        explicit one-attempt retry, success recovery, and cross-Capsule
        isolation remain deterministically covered by focused regressions.
    - Pass 10 legacy aggregate delivery quarantine completed on 2026-08-03:
      - `delivery_outbox.json` schema v5 maps every unreferenced pending or
        legacy retry-exhausted obligation to explicit durable `quarantined`
        state and rewrites the migrated classification on first successful
        store load;
      - quarantined records are excluded from due-item selection and cannot
        bind adapter receipts, so malformed aggregate debt cannot sustain a
        hidden recovery wake loop;
      - referenced legacy records remain recoverable through the same exact
        retry lifecycle; no ledger scan, second transport route, Core change,
        or speculative domain reconstruction is introduced;
      - all required automated gates pass: `git diff --check`,
        `flutter analyze`, full `flutter test` (718 tests),
        `cargo test --workspace`, and `tools/review/review_all.sh`;
      - fresh macOS release launch reconstructed Capsule ledgers `105`, `62`,
        and `119` without process fault or retry loop;
      - fresh Android release APK `versionCode=100000320`, SHA-256
        `d6e09d1b07121211730aa54f0e15ef4576de1bc1b4b5c90f94785d0805de576d`,
        updated in place while preserving install/data scope and Capsule
        Ledger `v82`, completed canonical receive and `98/98` pair-attestation
        receive, and showed no crash, ANR, or retry storm.
    - At pass 10, durable sender-rate quarantine remained separately tracked
      `NEEDS_CONTRACT` debt; passes 12-16 subsequently closed that debt.
    - Pass 11 single transport session ownership completed on 2026-08-03:
      - the sender-quarantine audit found that default and quick Nostr caches
        owned independent relay cursor maps while sharing one process seen set;
      - one transport-key-owned cache now owns the relay pool, seen set, and
        per-relay cursors for both operation profiles;
      - default `12s/6s` and quick `8s/3s` receive/publish budgets remain
        explicit operation policy and no longer select session identity;
      - wire format, Core, domain routing, outbox, and transport health paths
        are unchanged;
      - `git diff --check`, `flutter analyze`, full `flutter test`,
        `cargo test --workspace`, and `tools/review/review_all.sh` passed;
      - fresh macOS release launch reconstructed Capsule ledgers `105`, `62`,
        and `119` without process fault;
      - fresh Android release APK `versionCode=100000321`, SHA-256
        `1e7a02994f93a11a2a43473ad37be73dc66525c926ddef70d78a55874884773a`,
        updated in place while preserving the original install/data boundary,
        activated Capsule Ledger `v82`, completed canonical receive and
        `98/98` pair-attestation receive, sent three successful attestation
        answers, and showed no crash, ANR, or retry storm.
    - The same audit proved that durable sender quarantine additionally needs
      an acknowledged ingress handoff. The current adapter marks events seen
      and advances relay cursors before FFI routing, so limiter implementation
      remains unauthorized until consume-or-durable-quarantine acknowledgement,
      bounded capacity backpressure, retention, expiry, and replay ownership
      are complete.
    - Pass 12 acknowledged ingress contract completed on 2026-08-03 without
      runtime changes:
      - adapter batches retain stable event identity, relay provenance, signed
        timestamp, and per-relay cursor candidates until disposition;
      - the existing application-runtime FFI ingress router owns one
        resolve-once `consumed`, `quarantined`, or `retry` disposition;
      - an adapter may commit seen identity or relay cursor prefix only after
        canonical consumption, durable quarantine, or deterministic
        adapter-invalid rejection;
      - retryable routing, timeout, panic, capacity, and persistence failures
        preserve the affected cursor prefix and expose backpressure;
      - quarantine replay must use the original event identity and the same FFI
        router, never a capability-direct or Core path;
      - expiry requires bounded terminal evidence and cannot silently evict an
        unconsumed authenticated envelope;
      - architecture gates pin the ownership, cursor, rejection, and
        single-route constraints;
      - `git diff --check`, `flutter analyze`, full `flutter test`,
        `cargo test --workspace`, and `tools/review/review_all.sh` passed.
    - Pass 13 may implement only this acknowledged handoff and its regressions.
      Sender limiting and quarantine storage remain unauthorized until the
      handoff is proven and their separate retention/capacity contract closes.
    - Pass 13 acknowledged ingress implementation completed on 2026-08-03:
      - transport-neutral batch/item/disposition contracts carry stable event
        identity while the Nostr adapter retains merged relay provenance and
        per-relay cursor candidates in one pending batch;
      - relay fetch no longer mutates cursor or seen state; exact batch/item
        resolution is required before terminal ids and complete relay prefixes
        commit;
      - retry dispositions remain pending under a new batch id, stale-session
        rebuild is forbidden during resolution, and the legacy aggregate Nostr
        receive method is sealed;
      - the existing FFI ingress router remains the sole capability/Core route;
        append/projection and full chat/attestation inbox failures return retry
        while deterministic policy rejects are terminal;
      - capability inboxes use adapter event identity and no longer evict old
        unconsumed items when full;
      - focused regressions cover exact batch identity, retry seen/cursor
        backpressure, per-relay terminal prefixes, stable capability identity,
        and full-inbox behavior;
      - `git diff --check`, `flutter analyze`, full `flutter test`,
        `cargo test --workspace`, and `tools/review/review_all.sh` passed;
      - fresh macOS release launch reconstructed Capsule ledgers `105`, `62`,
        and `119` without process fault;
      - fresh Android APK `versionCode=100000322`, SHA-256
        `c6d5028e76b3f4d1299fe7c247f9ebaf31705bc2a8c659736be6e4929bcaf9bb`,
        updated in place while preserving the original install/data boundary,
        activated Capsule Ledger `v82`, resolved canonical ingress `batch=1`
        with `retry=0`, received `98/98` attestations, and sent three answers;
      - a second cold start preserved Ledger `v82`, replayed the same canonical
        path with `retry=0`, received `97/97` attestations, and showed no crash,
        ANR, or retry storm.
    - Pass 14 quarantine repository and sender-policy contract completed on
      2026-08-03 without runtime changes:
      - one future `CapsuleInboundQuarantineRepository` owns encrypted records,
        sender buckets, expiry, and tombstones under Capsule/network/transport
        endpoint scope; Core, outbox, inboxes, and adapters cannot own copies;
      - schema v1 is keyed by adapter event id and fixes record, byte,
        per-sender, relay-provenance, payload-retention, and tombstone bounds;
      - capacity and persistence failure return cursor-safe `retry`; admitting a
        newer envelope cannot evict another retained payload;
      - `SenderIngressPolicyV1` uses authenticated sender only after neutral
        guards, charges each event id once, fixes burst/refill bounds, and has
        no trust, domain, relay, UI, IP, or plugin bypass;
      - recovery re-enters the same FFI router with the original event id,
        cannot charge replay again, and creates no parallel scheduler or Core
        path;
      - expiry, tombstone, storage-key separation, corruption, atomic write,
        restart, Capsule switch, temporary cleanup, and deletion behavior are
        explicit architecture gates;
      - `git diff --check`, `flutter analyze`, full `flutter test`,
        `cargo test --workspace`, and `tools/review/review_all.sh` passed.
    - Pass 15 may implement only repository persistence, expiry/tombstones,
      deletion, and same-router recovery. Sender-policy activation remains a
      later isolated pass after cross-platform repository evidence.
    - Pass 15 repository implementation completed on 2026-08-03:
      - `platform/hivra-ffi` owns one encrypted snapshot repository scoped by
        Capsule, network, and local transport endpoint; neither Core nor the
        Nostr adapter gained storage or routing authority;
      - records and metadata enforce the pass-14 record, byte, per-sender,
        provenance, retention, and tombstone bounds without eviction;
      - platform crypto derives distinct authenticated record and snapshot
        storage roles; plaintext envelopes do not enter the persisted file;
      - retryable input is acknowledged as `quarantined` only after atomic
        persistence; full, corrupt, undecryptable, or unavailable storage
        returns visible retry/fail-closed behavior;
      - one eligible record re-enters the existing FFI ingress router with its
        original event id before a new fetch; consumed and expired payloads
        become bounded metadata-only tombstones;
      - Flutter supplies the canonical application root and the existing
        Capsule deletion lifecycle removes only that Capsule's quarantine
        subtree;
      - focused regressions cover encryption-role separation, restart,
        corruption, duplicate provenance, sender capacity, expiry,
        consumption, deletion isolation, and same-router chat recovery;
      - `git diff --check`, Rust formatting, `flutter analyze`, all `718`
        Flutter tests, `cargo test --workspace`, and
        `tools/review/review_all.sh` passed;
      - the universal macOS release bundle exposed both new FFI symbols and
        launched with Capsule Ledger versions `105`, `62`, and `119` without
        process, storage-root, or quarantine failure;
      - Android APK `versionCode=100000323`, SHA-256
        `6c4d21afe514589dc2519e0bd24623cde945d6a6cc9fc8a10041ce4862a7b03e`,
        contained all three required ABIs and both new FFI symbols, updated in
        place while preserving Ledger `v82`, and completed two cold starts;
      - both Android starts resolved canonical ingress with `fetched=123`,
        `decoded=115`, `retry=0`, no quarantine/storage failure, and received
        `96/96` attestations;
      - `SenderIngressPolicyV1` remains absent from runtime code.
    - Pass 16 may activate only `SenderIngressPolicyV1` behind this repository
      and handoff. Stable event charging, persisted bucket bounds, restart
      resistance, same-router replay exemption, and capacity backpressure are
      mandatory; Core and scheduler changes remain unauthorized.
    - Pass 16 sender-policy activation completed on 2026-08-03:
      - sender buckets, refill checkpoints, and bounded exact charge evidence
        persist in the same encrypted repository snapshot;
      - v1 permits burst `8`, refills one permit every `15 seconds`, and bounds
        state to `1024` senders, `65536` recent event ids, `8 MiB` per scope,
        and `40960` ids per sender;
      - stable event replay returns already-charged without another permit;
        quarantine recovery bypasses policy charging and reuses the same FFI
        router;
      - throttled input is acknowledged only after atomic quarantine;
        repository, sender-state, and evidence capacity preserve cursor-safe
        `retry` without eviction or bypass;
      - pass-15 snapshots migrate to empty policy state without rewriting
        retained records or tombstones;
      - focused regressions cover burst/refill, restart, double-charge,
        message-kind and sender isolation, active-state capacity, pass-15
        migration, and same-router recovery;
      - `git diff --check`, Rust formatting, `flutter analyze`, all `718`
        Flutter tests, `cargo test --workspace`, and
        `tools/review/review_all.sh` passed;
      - universal macOS launch preserved Ledger versions `105`, `62`, and
        `119` without process or storage failure;
      - Android APK `versionCode=100000324`, SHA-256
        `c21541e3009bf681a6762a727c3e6ee6f5eebf0b42058839d7656b14d00b3225`,
        updated in place and preserved Ledger `v82`;
      - three Android cold starts showed bounded migration backpressure rather
        than loss: initial history produced `55` durable quarantines and `37`
        retries, then restart recovery and persisted charge evidence reduced
        retry monotonically `37→32→25` while attestations continued to
        converge and no crash, policy bypass, or storage failure appeared.
    - Passive receive ownership audit completed on 2026-08-03:
      - the audit found one native FFI router, one cached Nostr session/cursor
        owner, one process-global FFI worker queue, and one shared transport
        health policy;
      - redundant work is created above those boundaries: launch/resume/network
        follow-ups, the invitations-screen 15-second timer, and chat/trading
        plus pair-attestation refresh chains can serialize multiple full relay
        polls for one trigger wave;
      - `CapsulePassiveReceiveCoordinator` is the sole selected application
        owner for trigger lifetime and coalescing. It owns neither transport
        state nor domain/capability interpretation;
      - the exact removal set is screen-owned passive timers/follow-ups and
        in-flight flags, direct passive receive orchestration in invitations,
        trading, and plugin-chat screens, and nested relay polling from chat
        and pair-attestation drain FFI functions;
      - restart, Capsule-switch, manual-retry, foreground, and cross-Capsule
        serialization semantics are fixed in the transport lifecycle contract.
    - Pass 17 passive receive convergence completed on 2026-08-03:
      - add one process-scoped application coordinator that coalesces automatic
        triggers per Capsule and permits at most one bounded forced manual
        follow-up;
      - preserve one existing default/quick FFI ingress poll and the existing
        canonical router, cached session/cursors, health policy, shared worker
        queue, Ledger/Core projection, and capability inbox owners;
      - separate chat and pair-attestation drain from relay polling, then
        project/drain all current capabilities after the one canonical poll;
      - move the existing foreground periodic cadence and lifecycle/network
        trigger lifetime out of screens without increasing polling frequency;
      - delete or seal every audited redundant caller in the same pass and add
        launch/resume/network/periodic/manual, Capsule-switch, timeout, and
        cross-capability coalescing regressions;
      - do not add Core facts, a second transport route, a second scheduler,
        durable scheduler state, a new adapter session, or a parallel DTO
        family.
      - implementation preserved the existing ingress router, cached Nostr
        session/cursors, shared FFI worker queue, Core/Ledger projection, and
        capability inbox owners while deleting the audited redundant callers;
      - focused and full automated regression suites cover trigger joining,
        bounded manual follow-up, lifecycle/Capsule invalidation,
        poll-before-drain ordering, drain-failure isolation, and
        capsule-scoped connectivity cooldown.
      - `git diff --check`, Rust formatting, `flutter analyze`, all `726`
        Flutter tests, `cargo test --workspace`, and
        `tools/review/review_all.sh` passed;
      - universal macOS release smoke preserved Ledger versions `105`, `62`,
        and `119` across launch/resume/follow-up/periodic receive with no
        process error or fault;
      - Android smoke build `versionCode=100000325`, SHA-256
        `ac0dd45dbd195f7094c83b151e68af2cffccded3c6faf8e1b07813b78661de3d`,
        updated in place, preserved Ledger `v82`, and passed launch, periodic,
        explicit manual retry, attestation drain, and cold restart.
    - Post-pass audit completed on 2026-08-03:
      - pass-17 macOS and Android evidence exposed a stable-snapshot
        pair-attestation ping-pong under foreground periodic receive;
      - duplicate verified evidence is currently counted as newly stored and
        `answerStoredEvidence` responds without a durable response identity;
      - `ensureForPeer` also performs blind ready-state fire-and-forget
        re-announcement;
      - no second native relay poll, screen-owned passive timer, channel-owned
        receive route, or environment-baseline change was found;
      - T0 remains the next platform unit, but it cannot preempt this active
        network/crypto loop.
    - Pass 18 may implement only bounded pair-attestation response convergence:
      - `ConsensusAttestationExchangeService` owns response policy and
        `ConsensusAttestationStore` owns schema-v2 checkpoint persistence in
        the existing Capsule-scoped file;
      - response identity binds exact pair, snapshot, peer evidence, and local
        evidence; adapter success is terminal and failure retries no sooner
        than the persisted 15-minute boundary;
      - v1 evidence migrates without changing evidence records and with empty
        checkpoints;
        corruption or the 4096-checkpoint bound suppresses automatic send;
      - delete blind ready-state re-announcement and prevent duplicate receives
        from being reported as newly stored;
      - do not add Core facts, a receiver-ack protocol, another outbox,
        scheduler, timer, transport route, or DTO family.
  - Status: passes 1-18 complete (2026-08-03). Pass 18 passed its focused
    `31`-test matrix, all repository gates, and fresh build `100000326`
    macOS/Android smoke. Stable snapshots produced no newly stored attestation
    on repeated receive or cold restart; macOS Ledger files remained
    byte-identical and Android preserved Ledger `v82`.

- `12.4 Cryptographic Agility Compatibility Debt`
  - Permanent invariant:
    - domain identity, authority, and Capsule continuity do not depend on one
      cryptographic algorithm, public-key size, or signature size;
    - algorithms stay in crypto/platform adapters, while protocol proofs are
      versioned, suite-tagged, key-id-bound, and length-delimited.
  - Maintained 1.x boundary:
    - Ed25519 root signing, secp256k1 Nostr transport signing, NIP-44 transport
      encryption, and current fixed-size key/signature contracts remain the
      compatibility baseline;
    - `[u8; 32]`, `[u8; 64]`, `pubkey32`, and `signature64` usages that encode
      keys or signatures across Core/Engine/FFI/Flutter are registered debt,
      not the target 2.0 contract;
    - an architecture gate prevents those shapes from spreading into new
      production files and keeps the compatibility-match count
      non-increasing;
    - no post-quantum runtime, hybrid proof acceptance, or release claim is
      authorized in 1.x by this documentation pass.
  - 2.0 contract work before implementation:
    1. Define stable `CapsuleId` separately from every public key.
    2. Define suite registry, `KeyDescriptor`, `SignatureProof`, role binding,
       variable-length encoding, canonical errors, and golden vectors.
    3. Define an append-only migration checkpoint mutually bound by the active
       classical root and new post-quantum key and anchored to the exact prior
       Ledger head.
    4. Prove that historical events remain byte-identical and are neither
       rewritten nor re-signed; subsequent hybrid verification uses the same
       Core history and result path.
    5. Define version-gated hybrid genesis for new Capsules, including recovery
       and downgrade behavior.
    6. Migrate root signing, transport signing, and transport encryption as
       independent roles; Nostr remains a replaceable adapter and its
       secp256k1 identity never becomes `CapsuleId`.
    7. Define a hybrid KEM delivery envelope that binds classical and
       post-quantum encapsulations to one ciphertext to reduce
       harvest-now/decrypt-later exposure.
    8. Define independently verifiable suite-tagged Capsule Effect Proof over
       the canonical effect commitment and lifecycle identity.
  - Sequencing rule:
    - this debt does not preempt the active ordered `12.3` remediation passes;
    - crypto runtime implementation remains `NEEDS_PROTOCOL` until every
      descriptor, checkpoint, downgrade, recovery, fixture, and removal target
      is reviewed;
    - migration is controlled and hybrid, never a rapid full Ed25519 swap,
      second Core path, dual Ledger, or history rewrite.
  - Status: architecture canon and executable debt gate only; runtime not
    started.

- `12.5 Capsule AI Runtime Convergence`
  - Owner: host Capsule AI Runtime outside Core and effect owners.
  - Permanent invariant:
    - every inference request uses one provider-independent runtime port;
    - features own disclosure selection and proposal meaning, but never
      credentials, provider dispatch, or an AI scheduler;
    - inference remains untrusted and cannot mutate truth or execute effects.
  - AI-0 completed on 2026-08-03:
    - froze `CapsuleInferenceRequestV1` and `CapsuleInferenceResultV1` semantic
      contracts, canonicalization, typed failure, budget, Capsule binding, and
      stale-completion rules;
    - inventoried four callable legacy dispatch paths: Capsule Analyst,
      Developer Engineer, history advisor, and Moltbook;
    - added `tools/review/capsule_ai_runtime_gate.sh` so direct credential and
      adapter ownership can only decrease and cannot spread into screens,
      widgets, Core, Engine, adapters, or platform crates;
    - `flutter analyze`, all `737` Flutter tests, `cargo test --workspace`, and
      `tools/review/review_all.sh` passed;
    - no runtime behavior, provider request, credential storage, Core path, or
      effect path changed.
  - AI-1 completed on 2026-08-03:
    - implemented the host-owned `CapsuleAiRuntimeService` without adding a
      Core, FFI, truth, or effect path;
    - migrated only `CapsuleHistoryAiAdvisorService` and deleted its direct
      credential-store and provider-adapter ownership;
    - enforced canonical disclosure/request hashing, explicit session unlock,
      one process-wide scheduler, same-scope supersession, byte/time budgets,
      provider evidence, Capsule binding, and stale-completion rejection;
    - reduced callable legacy dispatch and credential-reader paths from four
      to three, and hardened the gate against restoring the history path;
    - added focused provider substitution, locked-session, wrong-Capsule,
      stale-completion, supersession, budget, timeout, serialization, evidence,
      key-confusion, and redaction regressions;
    - focused runtime/history tests pass `12/12`; `flutter analyze`, all `748`
      Flutter tests, `cargo test --workspace`, and
      `tools/review/review_all.sh` pass;
    - build `100000328` produces a universal macOS bundle and Android APK with
      `arm64-v8a`, `armeabi-v7a`, and `x86_64`; both fresh artifacts cold-start
      without fatal terminal evidence. Live provider use remains an explicit
      credentialed user action rather than an automated gate.
  - AI-2 completed on 2026-08-03:
    - migrated only `AiDeveloperEngineerService` through the existing runtime
      and deleted its direct credential, provider DTO, adapter, and dispatch
      ownership;
    - preserved selected-context disclosure, denylisted paths, payload preview,
      provider/model controls, and advisory-only semantics;
    - bound explicit provider and model policy into canonical request identity,
      rejected mismatched response evidence, and separated temporary provider
      unlock from persistent preferred-provider state;
    - reduced callable legacy dispatch and credential-reader paths from three
      to two and hardened the executable gate against restoring Developer
      Engineer's old path;
    - focused runtime/history/developer/credential tests pass `30/30`;
      `flutter analyze`, all `751` Flutter tests, `cargo test --workspace`, and
      `tools/review/review_all.sh` pass;
    - build `100000329` produces a universal macOS bundle and Android APK with
      `arm64-v8a`, `armeabi-v7a`, and `x86_64`; both fresh artifacts cold-start
      without fatal terminal evidence. Live inference remains an explicit
      credentialed user action rather than an automated gate.
  - AI-3 completed on 2026-08-03:
    - migrated only `AiDoctorChatService` through the existing runtime and
      deleted its direct credential, provider DTO, adapter, and dispatch
      ownership;
    - preserved selected-section disclosure, redaction, outbound preview,
      payload limits, provider/model controls, and advisory-only semantics;
    - moved provider preference, key/base-URL configuration, explicit session
      unlock, canonical request identity, and provider/model evidence binding
      behind the runtime without creating a second credential owner;
    - reduced callable legacy dispatch and credential-reader paths from two to
      one and hardened the executable gate against restoring Capsule Analyst's
      old path;
    - focused runtime/history/developer/Analyst/credential tests pass `38/38`;
      `flutter analyze`, all `757` Flutter tests, and
      `cargo test --workspace` pass;
    - build `100000330` produces a universal macOS bundle and Android APK with
      `arm64-v8a`, `armeabi-v7a`, and `x86_64`; both fresh artifacts cold-start
      without fatal terminal evidence. Live inference remains an explicit
      credentialed user action rather than an automated gate.
  - AI-4 completed on 2026-08-04:
    - migrated only `MoltbookPublicBulletinAiService` through the existing
      runtime and deleted the final feature-owned credential, provider DTO,
      adapter, and dispatch path;
    - preserved bounded public-note and untrusted-conversation disclosure,
      strict bulletin/reply schemas, prompt-injection controls, provider
      session UI, and advisory-only proposal validation;
    - preserved the automatic cycle, durable feed checkpoint, WASM draft,
      approval policy, and canonical external-effect lifecycle; AI failure or
      Capsule change still defers checkpoint advancement and creates no effect;
    - reduced callable legacy provider dispatch and credential-reader paths
      from one to zero and fixed both executable gate inventories at zero;
    - focused AI/Moltbook/cycle tests pass `53/53`; `flutter analyze`, all
      `760` Flutter tests, `cargo test --workspace`, and
      `tools/review/review_all.sh` pass;
    - build `100000331` produces a universal macOS bundle and Android APK with
      `arm64-v8a`, `armeabi-v7a`, and `x86_64`; both fresh artifacts cold-start
      without fatal terminal evidence. Live inference remains an explicit
      credentialed user action rather than an automated gate.
  - Post-AI-4 documentation, debt, and environment audit is completed in
    `12.6`; it selected design-only `V2-0 / pass A` and did not infer AI-5 or a
    release candidate.
  - Status: AI-4 convergence complete; no legacy feature-owned provider
    dispatch or credential-read path remains.

- `12.6 Post-AI-4 Debt and Environment Checkpoint`
  - Scope:
    - reconcile current documentation, executable debt gates, and pinned local
      toolchain evidence after Capsule AI Runtime convergence;
    - distinguish active 1.x findings from guarded compatibility, design-only,
      release-only, and parked work;
    - select exactly one next bounded unit without inferring a release or
      runtime migration.
  - Evidence (2026-08-04):
    - `main` was clean at `b86cb7a`; AI provider dispatch and feature-owned
      credential-read gates remain fixed at `0/0`;
    - `tools/toolchain/verify_environment.sh` matched Flutter `3.41.2`, Dart
      `3.11.0`, Rust/Cargo `1.93.0`, Android SDK/build tools `36.1.0`, NDK
      `28.2.13676358`, AGP `8.13.2`, Gradle `8.13`, Kotlin `2.2.20`, JDK `21`,
      Xcode `26.6`, macOS SDK `26.5`, and CocoaPods `1.16.2` to the T0 manifest;
    - direct Gradle JDK and simulator-runtime discovery remain documented
      noncanonical/out-of-scope warnings, not release-authority drift for the
      maintained macOS and Android line;
    - no active 1.x correctness, security, replay, transport, projection,
      effect-lifecycle, AI-runtime, or platform-parity finding was identified;
      T1 and product tracks remain parked, and release work still requires a
      named candidate.
  - Next selected unit:
    - `V2-1 / pass B`, Starter inventory and atomic Genesis seed-plan design;
    - design/tooling only, with no 1.x runtime behavior, 2.0 production code,
      new DTO family, storage format, facade, or parallel execution path.
  - Status: completed (2026-08-04).

- `V2-0 / pass A — Ownership Registry Baseline`
  - Scope:
    - freeze one repository registry for current packages, known capability
      owners, contracts, facts, projections, effects, entrypoints, composition
      bindings, and forbidden Rust edges;
    - generate deterministic evidence and closure verdicts from the registry
      plus current code metadata;
    - add fail-closed consistency and negative self-tests without changing
      runtime code.
  - Evidence under remediation (2026-08-04):
    - `architecture/ownership-registry.v1.json` records nine packages and twelve
      known capability families;
    - `docs/generated/architecture-ownership-baseline.md` records current Rust
      and Flutter layer edges, composition bindings, closure verdicts, and owner
      surface entropy;
    - the gate rejects package drift, missing symbols, duplicate owners, Rust
      cycles, forbidden edges, non-composition bindings, invalid closure claims,
      entrypoint bypass, and stale generated evidence;
    - `trading_drone` and `person_runtime_shell` remain `NEEDS_CONTRACT`; no
      speculative 2.0 contract, facade, event, storage, or runtime path was
      introduced.
  - Next selected unit:
    - `V2-0 / pass B`, owner-candidate discovery and service-locator
      classification only.
  - Status: completed (2026-08-04).

- `V2-0 / pass B — Owner Discovery and Composition Surfaces`
  - Scope:
    - derive owner-like Flutter declarations and service/module builders from
      production code;
    - classify every candidate through the canonical registry and fail closed
      on unclassified owners, hidden composition builders, or generic service
      locator escape;
    - report oversized candidate surfaces without moving or splitting them.
  - Evidence (2026-08-04):
    - the generated baseline records 158 owner candidates across capability,
      evidence, entrypoint, composition, supporting, and compatibility-debt
      classifications;
    - 33 service/module builders are restricted to eight registered composition
      roots, while generic service-locator pattern evidence remains zero;
    - fifteen candidate files meet the 800-line entropy threshold, making the
      current Trading, Moltbook, plugin, exchange, persistence, chat, and
      invitation concentration visible without inferring a runtime refactor;
    - negative self-tests reject an unclassified owner, a builder outside
      composition, and an unapproved locator pattern.
  - Next selected unit:
    - `V2-0 / pass C`, explicit UI entrypoint and Flutter/FFI compatibility
      mapping only.
  - Status: completed (2026-08-04).

- `V2-0 / pass C — Explicit UI and Flutter/FFI Boundary Map`
  - Scope:
    - replace broad screen and Flutter/FFI compatibility rules with explicit
      per-declaration mappings;
    - bind canonical UI surfaces to exact registered capability commands and
      give every remaining 1.x surface a named capability-qualified debt target;
    - reject mapping drift without changing runtime code.
  - Evidence (2026-08-04):
    - all 17 screen surfaces and 18 Flutter/FFI runtime declarations are mapped;
    - seven UI entrypoints are `CANONICAL`; 28 UI/FFI surfaces remain explicit
      `COMPATIBILITY_DEBT` with rationale;
    - broad screen and FFI fallback rules are removed;
    - negative tests reject missing/duplicate mappings, unknown capabilities,
      canonical target drift, and canonical-entrypoint downgrade;
    - the map exposes sixteen assignments to `capsule_identity`, proving that
      birth, selection, addressing, backup, recovery, and settings need bounded
      ownership evidence before any future contract is frozen.
  - Next selected unit:
    - `V2-0 / pass D`, identity/continuity/addressing/Starter capability
      decomposition using current code evidence only.
  - Status: completed (2026-08-04).

- `V2-0 / pass D — Bounded Identity and Continuity Families`
  - Scope:
    - replace the overloaded `capsule_identity` surface bucket with bounded
      birth, selection, continuity, recovery, addressing, and Starter inventory
      capability evidence;
    - preserve base identity as a Core-owned domain capability rather than a UI,
      FFI, backup, settings, or recovery facade;
    - fail closed if the broad identity catch-all returns.
  - Evidence (2026-08-04):
    - the registry grows from twelve to eighteen known capability families using
      existing code owners only;
    - seventeen UI/FFI surfaces move to six required bounded families, while
      `capsule_identity` retains zero UI/FFI mappings;
    - birth, selection, continuity, and Starter inventory are explicitly
      `NEEDS_CONTRACT`; recovery and addressing are `NEEDS_PROTOCOL`;
    - policy and negative self-tests reject a missing bounded family or any
      return to the identity catch-all;
    - no runtime code, Core contract, DTO, event, facade, storage, or executable
      path is introduced.
  - Next selected unit:
    - `V2-0 / pass E`, final exit audit and ordering only.
  - Status: completed (2026-08-04).

- `V2-0 / pass E — Exit Audit`
  - Scope:
    - verify every V2-0 work-package requirement against generated evidence and
      fail-closed gates;
    - order all non-ready capability families without implementing contracts;
    - select at most one first V2-1 design contract while keeping runtime
      implementation unauthorized.
  - Evidence (2026-08-04):
    - the generated exit matrix records all seven requirements `COMPLETE`;
    - the baseline contains 18 capabilities, 161 owner candidates, 33
      composition builders, 35 UI/FFI surface mappings, dependency/concrete
      binding evidence, crypto-debt checks, and entropy surfaces;
    - closure totals are ten `READY`, six `NEEDS_CONTRACT`, and two
      `NEEDS_PROTOCOL`; all eight non-ready families are explicitly ordered;
    - registry policy and negative tests require
      `runtime_implementation_authorized: false`;
    - `capsule_identity_birth_contract_v2` is selected first because stable
      CapsuleId and birth mode unblock continuity, recovery, addressing,
      selection, and later crypto-agility proofs.
  - Next selected unit:
    - `V2-1 / pass A`, Capsule identity and birth contract/schema/fixture design
      only; no production implementation.
  - Status: completed (2026-08-04).

- `V2-1 / pass A — Capsule Identity and Birth Contract`
  - Scope:
    - define opaque algorithm-independent CapsuleId and immutable Genesis/Proto
      birth mode;
    - separate proof verification from the verified Core birth command;
    - define fact/result/error semantics, 1.x migration, and sealing targets;
    - produce semantic design vectors without choosing a production wire format
      or implementing runtime code.
  - Evidence (2026-08-04):
    - the blueprint is normative; the checked-in JSON Schema and fixtures are
      machine-readable review evidence rather than a second architecture source;
    - vectors bind authorization to exact birth semantics, derive operation id,
      distinguish exact replay from duplicate Capsule birth, and reject changed
      request fields after proof creation;
    - the validator uses draft-2020-12 validation and rejects weakened root,
      proof-binding, fixture coverage, and semantic-result mutations;
    - 1.x `capsule_type` remains read-only compatibility input with mapping
      `1 -> GENESIS`, `0 -> PROTO`; history is never rewritten or re-signed;
    - no production Rust, Flutter, FFI, storage, event, adapter, or UI path is
      introduced.
  - Next selected unit:
    - `V2-1 / pass B`, Starter inventory/current-view and atomic Genesis
      seed-plan contract design only.
  - Status: completed (2026-08-04); remediation and consolidation review closed
    with no remaining finding.

- `V2-1 / pass B — Starter Inventory and Genesis Seed Contract`
  - Scope:
    - assign Starter lifecycle facts, slot occupancy, and current view to one
      Core owner;
    - derive the five Genesis Starters from the verified Pass A birth command;
    - require one all-or-none birth transaction and define no second seed or
      repair operation;
    - preserve 1.x history as read compatibility without runtime changes.
  - Evidence (2026-08-04):
    - one normative blueprint section, one schema, one semantic vector set, and
      one validator integrated into the existing architecture gate;
    - standard schema validation and negative mutations reject root weakening,
      duplicated CapsuleId semantics, generic Genesis ids, `LOCKED` ownership,
      missing evidence, semantic drift, missing canon, and runtime authorization;
    - vectors prove exact Genesis/Proto plans, atomic append, exact replay,
      terminal burn, closed burn reasons, scope isolation, and deterministic
      current view;
    - no Rust, Flutter, FFI, storage, adapter, production event, or UI path
      changed.
  - Architecture-economy review:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | Existing blueprint section plus one schema, fixture set, validator, and existing-gate hook | Second seed command, post-birth repair route, invitation-owned `LOCKED` state, and Genesis-scheme reuse are forbidden | Starter ownership, Genesis derivation, atomic birth, replay, burn, and projection scope | One design owner; zero runtime owners or paths | 1.x FFI Genesis loop, derivation policy, fixed StarterId, slot probes, and Dart replay remain explicit migration targets | Consolidate and select at most one later contract only from a named ambiguity |

  - Next selected unit: none; Pass C and runtime implementation remain
    unauthorized pending a separate consolidation decision.
  - Status: completed (2026-08-04); consolidation found no duplicated normative
    owner and no new finding.

- `V2-1 / post-Pass B consolidation and Pass C selection`
  - Findings (2026-08-04):
    - the ownership baseline remains a current-runtime snapshot; reviewed
      design-only contracts do not make their 1.x production paths `READY`;
    - birth and Starter registry debt now names production binding and sealing
      work instead of incorrectly claiming that no reviewed design exists;
    - continuity is the next ordered capability whose ambiguity is independently
      closable: export intent and snapshot evidence currently span
      `BackupService`, FFI, codec, persistence, and recovery-facing surfaces;
    - recovery migration, owner verification, history anchoring, and a new
      backup wire format are separate responsibilities and are excluded.
  - Architecture-economy review:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | No document, schema, registry, or gate; existing registry/report/status text only | False equivalence between design completion and production closure | Pass A/B design evidence versus unresolved 1.x runtime binding | Zero owners; zero runtime paths | Birth/Starter runtime binding remains; continuity, recovery, addressing, selection, shell, and trading remain non-ready | One bounded continuity export contract can now be reviewed without absorbing recovery or storage |

  - Next selected unit:
    - `V2-1 / pass C`, Capsule continuity export contract, design/schema/vectors/
      validator only;
    - one application owner, one immutable snapshot commitment, one export
      operation/result path; no recovery protocol, second backup format, Core
      fact, FFI/storage/UI binding, or runtime implementation.
  - Status: completed (2026-08-04).

- `V2-1 / pass C — Capsule Continuity Export Contract`
  - Scope:
    - assign export intent, exact immutable snapshot binding, local authority,
      operation replay, and prepared artifact evidence to one application-level
      design owner;
    - retain the existing authenticated `hivra.capsule_backup.v2` codec profile
      and keep filesystem, sharing, durability receipts, and recovery outside
      the contract;
    - add no Core fact, production DTO, FFI, storage, Flutter, UI, or runtime
      path.
  - Evidence (2026-08-04):
    - one normative blueprint section, one draft-2020-12 schema, one compact
      semantic vector set, and one validator integrated into the existing
      architecture gate;
    - vectors bind Capsule/network/Ledger snapshot, exact authorization scope,
      operation replay, encrypted artifact profile, digest, and byte length;
    - negative mutations reject malformed Core snapshots, replay evidence
      substitution, plaintext profiles, raw seeds, destination paths, schema
      weakening, missing canon, semantic drift, and runtime authorization;
    - exact replay returns the prior exact evidence, while operation-id reuse
      with changed semantics fails closed and appends no Core fact.
  - Architecture-economy review:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | Existing blueprint section plus one schema, compact fixture set, validator, and existing-gate hook | Second export route, raw seed/path capability intent, recovery/storage/share ownership leakage, and replay evidence substitution | Exact snapshot, authority, operation, profile, and artifact-evidence ownership | One design owner; zero runtime paths | 1.x `BackupService`/`BackupRuntime`/persistence/screen composition and future V2-2 effect receipts remain explicit | Consolidation can decide whether another bounded contract is justified without reopening continuity semantics |

  - Next selected unit: none; runtime implementation and later V2-1 contracts
    remain unauthorized pending a separate consolidation decision.
  - Status: completed (2026-08-04); local design and repository gates pass.

- `V2-1 / post-Pass C consolidation and Pass D selection`
  - Findings (2026-08-07):
    - the blueprint remains the sole normative continuity owner; schema and
      fixtures are machine evidence, roadmap is history, and the generated
      ownership baseline remains a current 1.x runtime snapshot;
    - no duplicated continuity DTO family, registry, gate, document, Core path,
      or runtime route was added by Pass C;
    - current recovery meaning is split between `RecoveryService.recover` and
      selector-driven `importCapsuleFromBackupJson`, with different ordering of
      artifact decoding, seed/owner verification, Ledger import, Capsule
      creation, persistence, and activation;
    - this is one independently closable protocol ambiguity: which exact
      Capsule, network, authority evidence, artifact commitment, accepted
      history head, and operation identity authorize one recovery result;
    - codec/KDF details, mnemonic handling, filesystem writes, secure storage,
      UI/FFI composition, a new backup format, and runtime migration remain
      downstream or compatibility responsibilities.
  - Architecture-economy review:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | Existing status and roadmap text only | Automatic progression after Pass C and any claim that export completion already defines recovery | Continuity evidence ownership versus recovery authorization/history acceptance | Zero owners; zero runtime paths | Two 1.x recovery routes, seed-derived identity alias, direct Ledger import, persistence/activation ordering, and runtime binding remain explicit | One bounded recovery protocol can be reviewed without absorbing codec, storage, selection, or UI |

  - Next selected unit:
    - `V2-1 / pass D`, Capsule recovery authorization and history-anchoring
      protocol, design/schema/vectors/validator only;
    - one protocol owner and one accepted/rejected/replayed result path over the
      reviewed CapsuleId, authenticated continuity artifact evidence, exact
      Ledger history commitment, and verified local authority;
    - no production Rust, Flutter, FFI, storage, event, adapter, UI, recovery
      execution, new backup wire format, release, or manual smoke.
  - Status: completed (2026-08-07); Pass D selected, runtime unauthorized.

- `V2-1 / pass D — Capsule Recovery Authorization and History Anchoring`
  - Scope:
    - assign artifact authentication, exact root-authority authorization,
      deterministic operation identity, local-base comparison, Ledger history
      acceptance, replay, and prepared activation to one application protocol;
    - reuse Pass A Capsule identity/authority proof and Pass C continuity
      snapshot/artifact evidence rather than introducing a second DTO family;
    - add no production Core fact, backup format, Rust, Flutter, FFI, storage,
      adapter, UI, recovery execution, release, or manual smoke.
  - Evidence (2026-08-08):
    - one normative blueprint section, one draft-2020-12 schema, one compact
      semantic vector set, and one validator integrated into the existing
      architecture gate;
    - 20 vectors prove empty-base, exact, and descendant acceptance; exact
      replay; operation conflict and invalid identity; wrong Capsule/network;
      artifact, authority, authorization, and history-evidence binding;
      rollback, fork, stale-base, seed-only, raw-seed, and destination-path
      rejection;
    - negative self-tests reject schema-root weakening, copied upstream types,
      optional artifacts, activation claims, raw secret command fields, missing
      vectors, semantic drift, proof rebinding, replay-plan substitution,
      missing canon, and runtime authorization;
    - accepted results are only `PREPARED` or `REPLAYED`, append no Core fact,
      and claim neither durability nor activation.
  - Architecture-economy review:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | Existing blueprint section plus one schema, compact fixture set, validator, and existing-gate hook | Seed-only native V2 recovery success, selector-owned parallel import, direct persist/activate before decision, create-import-recreate inference, rollback/fork, and replay-plan substitution are forbidden | Exact artifact, authority, operation, local-base, history-relation, replay, and prepared-result ownership | One design owner; zero runtime paths | Two 1.x recovery routes, seed-derived identity alias, codec/persistence/activation composition, fixed crypto compatibility, runtime binding, and future V2-2 effect receipts remain explicit | Consolidation can decide whether another bounded contract is justified without reopening recovery semantics |

  - Next selected unit: none; runtime implementation and later V2-1 contracts
    remain unauthorized pending a separate consolidation decision.
  - Status: completed (2026-08-08); local design and repository gates pass.

- `V2-1 / post-Pass D consolidation and Pass E selection`
  - Findings (2026-08-08):
    - Pass C and D retain one normative owner each; schemas and fixtures remain
      machine evidence, roadmap remains history, and the ownership registry
      remains the current 1.x closure source;
    - the registry previously described Continuity and Recovery as still
      missing their design contract/protocol; their actual remaining debt is
      production binding to the reviewed contract plus sealing old 1.x routes;
    - the generated ownership baseline is regenerated from that corrected
      registry, while both closure verdicts remain non-ready and runtime
      implementation remains unauthorized;
    - Capsule Selection is the next independently closable ambiguity: one
      `activateCapsule` seam currently maps missing authority to a boolean,
      delegates directly to persistence, and is surrounded by unrelated
      import/export/delete/mnemonic operations in the same compatibility port;
    - Selection directly consumes the prepared recovery boundary and requires
      one exact expected-active/target decision. Addressing remains later
      because card schema, crypto-agile proof, endpoint rotation, resolution,
      and storage form a wider independent protocol.
  - Architecture-economy review:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | Existing registry, generated baseline, two existing validator linkages, status, and roadmap only | Stale claims that Continuity/Recovery design is missing and stale ordering of Selection behind the wider Addressing protocol | Reviewed design completion versus unresolved production binding; next bounded dependency after recovery | Zero owners; zero runtime paths | Birth/Starter/Continuity/Recovery production binding, 28 compatibility surfaces, fixed crypto shapes, Selection, Addressing, shell, and trading contracts remain explicit | One serialized Capsule selection/prepared-activation contract can now be reviewed without absorbing recovery, persistence, addressing, or UI |

  - Next selected unit:
    - `V2-1 / pass E`, Capsule selection and prepared-activation contract,
      design/schema/vectors/validator only;
    - one application owner, deterministic operation identity, exact expected
      active Capsule, exact target Capsule, authority-availability evidence,
      serialized replay/conflict handling, and a prepared result awaiting a
      future V2-2 activation receipt;
    - no production Rust, Flutter, FFI, storage, adapter, UI, import/export,
      delete, mnemonic/seed recovery, address protocol, release, or manual
      smoke.
  - Status: completed (2026-08-08); Pass E selected, runtime unauthorized.

- `V2-1 / Pass E Capsule Selection and Prepared Activation Contract`
  - Completed design (2026-08-08):
    - one application-level Capsule Selection owner accepts one exact request
      over the verified local inventory revision/commitment, expected-active
      state, target `CapsuleId`, and target root authority;
    - the domain-separated semantic commitment covers every selection field,
      the deterministic operation id derives from it, and the suite-tagged
      proof binds both values without carrying proof bytes into the verified
      command;
    - exact replay returns the prior exact plan, conflicting reuse closes with
      `OPERATION_ID_CONFLICT`, and stale inventory or active state, wrong scope,
      authority confusion, proof substitution, and replay-plan substitution
      fail closed;
    - `NO_CHANGE` creates no activation obligation; `ACTIVATE_TARGET` remains a
      prepared plan until a future V2-2 effect owner atomically re-checks the
      preconditions and returns a plan-bound receipt;
    - the contract appends no Core fact, claims no persistence or activation,
      and authorizes no recovery, storage, UI/FFI, addressing, seed,
      import/export/delete, or runtime implementation;
    - standard draft-2020-12 schema validation, 20 semantic vectors, validator
      mutation self-tests, ownership evidence, architecture gate, repository
      gates, Rust workspace, Flutter analyze, and Flutter `760/760` pass.
  - Architecture-economy result:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | One existing blueprint section, one schema, one compact fixture set, one validator, and one existing-gate hook | Boolean recovery-as-selection outcome, recursive UI restore/select, direct persistence activation, broad selector port, and navigation-as-success are forbidden V2 routes | Exact inventory, active-state, target, authority, operation, replay, no-op, and prepared-result semantics | One existing application owner; zero runtime paths | Production binding, one V2-2 activation effect/receipt, and sealing the named 1.x compatibility routes | A bounded consolidation can measure duplication before any next contract is selected |

  - Next selected unit: none. Pass F, runtime implementation, release work, and
    manual smoke remain unauthorized pending a separate consolidation decision.
  - Status: completed (2026-08-08); local design, regression, and repository
    gates pass; protected PR and post-merge CI remain required.

- `Post-V2-1/E consolidation and 1.x Product Completion selection`
  - Findings (2026-08-08):
    - Passes A-E each retain one normative section in
      `architecture-v2-blueprint.md`; their schemas, vectors, and validators
      remain subordinate machine evidence rather than parallel specifications;
    - `development-control.md` remains the only current-status board,
      `roadmap.md` remains history, and the ownership registry plus generated
      baseline remain the only current production-binding debt inventory;
    - no contradictory Pass A-E semantics, duplicate contract owner, stale
      generated evidence, or automatically implied Pass F was found;
    - the next higher-value uncertainty is product evidence, not another 2.0
      contract: current release checklists cover platform packaging and the User
      Lifetime Safety Pack covers core lifetime risks, but no single reviewed
      journey currently proves installation, birth/recovery, contacts,
      invitations, consensus, chat, plugins, restart/switch, and both platforms
      as one coherent product-completion readiness map;
    - that gap fits the existing User Lifetime Safety Pack and release
      checklists. A new document, schema, registry, gate, DTO, service, or state
      owner would add duplication rather than reduce ambiguity.
  - Architecture-economy result:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | Short status/history update only | Automatic Pass F, automatic V2 runtime work, and a second product-completion checklist are sealed | 2.0 design completion versus real 1.x product readiness; current status versus historical evidence | Zero owners; zero runtime paths | Existing registry production-binding debt, Trust Layer issue #7, dependency updates, and unreproduced user-journey gaps remain explicit | One bounded 1.x readiness audit can determine whether a named test release candidate is justified |

  - Next selected unit:
    - `1.x Product Completion / pass A`, end-to-end user-journey readiness;
    - inspect existing runtime paths, tests, diagnostics, and checklist coverage
      for installation, Capsule birth/recovery, contacts, invitations,
      consensus, chat, plugins, restart/switch, and macOS/Android parity;
    - extend only `docs/checklists/user-lifetime-safety-pack.md` where a real
      coverage gap exists; do not create another checklist or runtime path;
    - runtime edits require a reproduced finding; packaging and manual smoke
      require a separately named release candidate.
  - Status: completed (2026-08-08); 2.0 paused, pass A selected, no release
    candidate or runtime implementation authorized.

- `1.x Product Completion / pass A — end-to-end journey readiness`
  - Findings (2026-08-08):
    - existing Core, FFI, Flutter application, transport, consensus, chat,
      plugin, recovery, restart, and diagnostics suites provide automated
      evidence for every requested journey segment;
    - no failing regression, contradictory owner, second runtime route, or
      reproducible 1.x defect was found during the readiness audit;
    - the actual gap was coordination evidence: the User Lifetime Safety Pack
      covered birth, relationship, recovery, update, and pending invitations,
      but did not require packaged clean install, pair consensus/chat,
      plugin lifecycle, or cross-platform restart/Capsule isolation as one
      coherent release-candidate journey;
    - the existing pack now owns those scenarios and maps each segment to its
      existing owner and regression files. Capability-specific and platform
      details remain linked rather than copied;
    - the existing lifetime gate now protects the expanded journey and includes
      a negative mutation that removes consensus/chat coverage and must fail.
  - Product-completion result:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | Four bounded scenarios, one evidence map in the existing lifetime pack, and a mutation self-test in its existing gate | A second end-to-end checklist, debug-build substitution, anecdotal UI-only signoff, and automatic release selection are forbidden | Which single artifact owns the full person journey and which existing tests support each segment | Zero state owners; zero runtime paths; zero new documents/gates | Manual packaged execution on both platforms, external tester evidence, Trust Layer issue #7, dependency updates, and registry production-binding debt remain explicit | A separate release decision can name the next test candidate without reopening architecture or inventing runtime work |

  - Next selected unit: none. Packaging, manual smoke, tags, and publication
    require a separately named test release candidate.
  - Status: completed (2026-08-08); no runtime finding reproduced.

- `1.x release candidate selection — v1.0.3-test16`
  - Decision (2026-08-08):
    - the repository release guard identifies `v1.0.3-test16` as the only valid
      next test version after published `v1.0.3-test15`;
    - the completed product-readiness map justifies one packaged macOS/Android
      system run from one clean post-merge `main` SHA;
    - strict preflight, platform packaging checks, User Lifetime Safety Pack,
      Trading Drone evidence, Moltbook smoke, applicable AI smoke, hashes,
      diagnostics, and manual signoff are required before any tag or release;
    - only reproduced candidate defects may open runtime remediation. The
      candidate does not authorize speculative cleanup, dependency upgrades,
      2.0 implementation, stable `1.0`, tagging, or publication.
  - Status: selected; artifacts and manual evidence pending.

- `v1.0.3-test16 preflight remediation — canonical Trading Drone evidence`
  - Strict preflight exposed that the evidence checker accepted arbitrary
    well-formed hashes and had no production-backed generator or golden vector.
  - The existing release owner now binds candidate rows to one canonical
    fixture, production envelope tests prove its hashes, and negative mutations
    reject changed hashes, risk paths, duplicate rows, and missing coverage.
  - Runtime behavior and release authority are unchanged. Packaging remains
    blocked until this remediation is merged with green repository gates and
    exact candidate rows are recorded separately.
  - Status: completed (2026-08-08); candidate packaging starts only from the
    green post-merge `main` SHA.

- `v1.0.3-test16 packaging remediation — monotonic build identity`
  - Packaged smoke reproduced that the old build-number formula mapped test16
    to `100000316`, below the last verified internal build `100000331`, and
    also mapped stable `1.0.3` below its own prereleases.
  - The existing version-derivation owner now reserves a stable slot inside
    each patch and proves test-to-stable and patch-to-patch monotonicity plus
    Android's upper bound with negative boundary tests.
  - The first test16 artifacts are rejected. Both platforms must be rebuilt
    from the green post-merge remediation SHA before smoke resumes.
  - Status: completed (2026-08-08); replacement artifacts pending.

- `v1.0.3-test16 smoke remediation — masked Trading credentials`
  - Packaged Android smoke reproduced that the stored BingX API key was
    rendered as plaintext while the secret field alone was masked.
  - The existing `TradingDroneScreen` UI owner now keeps both populated
    credential fields masked by default. Each value can be revealed only by
    its own explicit visibility control; suggestions and autocorrection remain
    disabled for both fields.
  - A widget regression proves default masking with populated values and
    independently mutates each reveal control. No credential store, execution
    service, Core path, DTO family, or effect route was added.
  - The prior test16 artifacts are rejected. Replacement macOS and Android
    artifacts require green PR and post-merge gates before packaged smoke can
    resume.
  - Status: completed and merged (2026-08-08); Android packaged smoke confirms
    both values are masked by default. Final candidate signoff remains pending.

- `v1.0.3-test16 smoke remediation — preserve passive chat inbox`
  - Replacement Android smoke reproduced a destructive projection gap:
    transport diagnostics reported `chat=3/3` during launch receive, but the
    later Chat workspace displayed `Inbox: 0` because the accepted in-memory
    FFI inbox had already been drained.
  - The existing `CapsuleDeliveryInboxStore` owner retains accepted chat
    messages by Capsule and stable message id, alongside its existing
    trade-signal cache. The Chat workspace projects that cache before and after
    canonical passive receive, so a timeout or other transport error changes
    only the visible transport notice and cannot hide accepted messages.
  - The regression proves a message accepted by an earlier passive drain
    remains available to a later workspace service instance even when its next
    refresh returns a timeout. Retention is capped at eight Capsule scopes and
    256 chat messages plus 256 trade signals per Capsule; the existing Capsule
    deletion use case clears the deleted scope from the process cache. Core,
    FFI, transport encryption, Ledger truth, and outbound delivery are
    unchanged.
  - Every prior test16 artifact is rejected. Both platforms must be rebuilt
    from one green post-merge remediation SHA and repeat complete manual signoff.
  - Status: completed (2026-08-09); rebuild and manual signoff pending, no tag
    or publication.

- `v1.0.3-test16 smoke remediation — visible AI Engineer selection`
  - Packaged macOS hands smoke reproduced that quick-add changed a selected-file
    field hidden below long repository listings, so the operator could not
    verify the exact advisory context. Changing that field also left an older
    built context eligible for Ask.
  - The existing `_DeveloperWorkspaceCard` owner now places the exact selection
    beside quick-add, reports additive/deduplicated changes, and invalidates the
    built preview and answer whenever selection changes. No AI provider,
    credential, runtime dispatch, DTO, file-write path, or second context owner
    is added.
  - Every prior test16 artifact is rejected. Both platforms require one rebuild
    from the green post-merge SHA and complete manual signoff.
  - Status: completed and merged (2026-08-09); packaged hands smoke confirms
    the exact selection is visible and stale context is invalidated.

- `v1.0.3-test16 smoke remediation — bounded AI Engineer quick-add`
  - Replacement macOS hands smoke reproduced that quick-add could extend the
    selected context to `9/8`; the canonical context builder then rejected the
    request only after the invalid selection was already visible.
  - The existing `_DeveloperWorkspaceCard` owner now fills only the remaining
    slots up to `AiDeveloperWorkspaceService.maxSelectedFiles` and reports
    suggestions skipped at the limit. The existing builder continues to reject
    manually entered over-limit selections fail-closed.
  - A focused regression mutates available capacity and proves quick-add cannot
    exceed it. No provider, credential, runtime dispatch, DTO, file-write path,
    validator owner, or second selected-context path is added.
  - Every test16 artifact through `f5632b9` is rejected. Both platforms require
    one rebuild from the green post-merge SHA and complete manual signoff.
  - Status: completed and merged (2026-08-09); packaged macOS hands smoke
    confirms the selection remains at `8/8` and context build succeeds.

- `v1.0.3-test16 smoke remediation — reconcile stale managed-order tracking`
  - Packaged macOS hands smoke restored one persisted managed-order lineage and
    started symbol polling, while the successful live open-order projection
    reported `Drone: 0`; the closed managed ID had no tracked-order pointer and
    therefore escaped the existing single-pointer cleanup path.
  - The existing `BingxFuturesOrderTrackingState` now reconciles every managed
    ID, symbol, and provenance record against each successful open-order read.
    A surviving managed order becomes the tracked pointer; when none survive,
    polling stops and only the existing risk settings remain persisted.
  - Regression vectors cover the reproduced restart state and the positive
    multi-order case. No exchange effect, order cancellation, Core/FFI path,
    DTO family, tracking owner, or persistence route is added.
  - Every test16 artifact through `332083d` is rejected. Replacement artifacts
    built from clean source commit `30e0800` passed packaged macOS and Android
    hands smoke, including restart reconciliation without a stale drone-owned
    order or unintended exchange effect.
  - Status: completed (2026-08-09); exact replacement artifacts passed manual
    signoff and were published through the guarded test-release path.

- `v1.0.3-test16 release publication`
  - Evidence-only commit `2a23411` differs from artifact source commit `30e0800`
    only by `docs/checklists/release-manual-signoff-log.md`.
  - The guarded publisher repeated automated preflight and manual signoff, then
    created annotated tag `v1.0.3-test16` at `2a23411` and published a GitHub
    prerelease using the exact previously verified macOS and Android artifacts.
  - Remote asset digests match the signoff record: macOS
    `a4775a3b6321cebd25c2e7b327257f7060df04baf3596f01c84d1c3fe8dfd6da`
    and Android
    `1472c4731590d824d1d3473923da04f17d81f299d5b67350649d57cbeeaa2727`.
  - Release notes explicitly identify the macOS artifact as unsigned and not
    notarized. No stable `1.0` claim or next release candidate is implied.
  - Status: published (2026-08-09); no next 1.x or 2.0 runtime pass selected.

- `1.x Moltbook Reference-Grade Pass A — session resume ownership`
  - Audit found one trigger-owner contradiction: `Stop` correctly invalidated
    in-flight work, but the process-scoped `session` latch remained closed, so
    an explicit local Enable could leave the Ambassador visibly stopped.
  - The existing `MoltbookCycleTriggerService` now clears its session latch at
    the same stop generation boundary. A resumed scope starts exactly one new
    session cycle; duplicate starts still collapse to that one cycle.
  - Regression tests cover the trigger owner directly and the canonical
    `PluginRuntimeModule` path. No DTO, service, effect owner, provider request,
    Core/FFI path, persistence route, or automatic publication authority was
    added.
  - Status: completed (2026-08-09); no next 1.x pass, release candidate, or 2.0
    runtime unit selected automatically.

- `1.x Moltbook Reference-Grade Pass B — Assisted publication continuity`
  - The existing Capsule-scoped external-effect lifecycle now prioritizes and
    reconciles recoverable Moltbook operations, including provider responses
    that reject verification after the exact post or reply is already visible.
    Exact post identity closes duplicate local drafts; successful verification
    archives its source draft; rejected reply proposals can be discarded
    through the existing cancellation path without publication.
  - The canonical AI product anchor keeps confirmed domain truth in Ledger and
    places publication attempts, deduplication, challenges, and receipts in the
    Capsule-scoped external-effect journal. No Core fact, DTO family, transport,
    service owner, or automatic publication authority was added.
  - Android Assisted evidence covered persisted Moltbook and Gemini credentials,
    process-scoped AI unlock, exact AI/WASM post and reply review, explicit
    approval, provider challenge, exact reconciliation receipt, cold restart,
    and no duplicate publication. Final restart state was `3 published · 0
    drafts · 0 blocked`; Gemini returned configured-but-locked and the Moltbook
    account refreshed without credential re-entry.
  - Automated evidence: `flutter analyze`, Flutter `779/779`, Rust workspace,
    `tools/review/review_all.sh`, and `git diff --check` pass.
  - Status: completed (2026-08-09); no Pass C, release candidate, or 2.0 runtime
    unit is selected automatically.

- `1.x Moltbook Reference-Grade Pass C — foreground bounded nested replies`
  - Explicit schema-v3 configuration may select Bounded replies; schema-v1/v2
    migration preserves Assisted authority and cannot enable Bounded implicitly.
  - One selected foreign comment binds one AI proposal, deterministic WASM
    draft, WASM delegation authorization, durable host budget, and the existing
    External Effects operation. No DTO, service, Core/FFI path, provider route,
    background runner, or second inbox/effect owner is added.
  - Daily and interval limits derive from the Capsule-scoped durable effect
    journal. Capsule switch and Stop are rechecked after authorization and
    before effect progression; provider challenges remain human-only.
  - Focused regressions cover configuration migration, exact delegated flow,
    durable daily/interval denial across module recreation, Capsule switch,
    Stop, challenge non-resolution, and canonical effect processing.
  - Android Hands smoke found a closed-target selection gap: after WASM chose a
    comment already represented in the effect journal, the cycle stopped
    instead of considering another eligible comment. The existing publication
    owner now filters journal-owned targets before WASM planning; regressions
    cover next-target selection and automatic non-reopening after cancellation.
  - Follow-up Android smoke on `4f8b269` confirmed exact target filtering
    (`5` observed, `3` excluded, `2` available) and no duplicate effect, then
    exposed a second starvation gap: `no_action` on the first heartbeat post
    ended the cycle despite later candidates. The canonical cycle now evaluates
    candidates in order until one actionable target is selected or the bounded
    set is exhausted, while still advancing at most one action.
  - Cross-Capsule review found one final duplicate surface: two local Capsules
    could bind the same external Moltbook account while only one journal knew
    about an existing reply. The cycle now treats a provider-visible direct
    reply by the bound account as closed evidence and never targets comments
    authored by that account. The existing cycle owner performs this filtering;
    no global journal, DTO, service, or second effect path was added.
  - Final packaged Hands evidence used source `4899b2d` and build
    `1.0.3+100030020` on both platforms. macOS began with an empty local
    publication journal for the bound account, excluded four provider-visible
    closed targets, prepared exactly one new reply, preserved one operation
    through explicit approval and anti-spam verification, and received a
    successful provider receipt. The public API exposed exactly one verified
    direct reply for target `470c6969-3ce4-4ba0-947f-41392f9790fb`. After cold
    restart the same conversation reported `available=0`, `excluded=6`; all
    five heartbeat candidates completed without inference or a new effect.
    Android independently reported the same `available=0`, `excluded=6`
    closure and exhausted all five candidates without inference or publication.
  - Artifact SHA-256: macOS
    `136cc59a1cce04075e71c1b61300dfe8830e5848c05d0d4d49c64e841536207d`;
    Android
    `76b95b5d9c84c63b0c2798fe57f0763d46632602a4c7dfe3767fcc3f6c73911e`.
  - Status: completed (2026-08-10). Artifacts from `88a0f3e`, `4f8b269`, and
    `313d55b` are invalid. No next product pass, release candidate, background
    authority, or 2.0 runtime unit is selected automatically.

- `1.x Trading protective-order ownership classification`
  - The test16 finding was audited against the official BingX placement,
    current-open-orders, all-orders, and order-details contracts. Placement
    returns only the submitted parent order; current open orders document no
    parent-to-generated-protection identifier. Read APIs expose
    `triggerOrderId`, but their description and examples do not prove a stable
    directional parent binding suitable for ownership authority.
  - The existing `BingxFuturesOrderTrackingState` remains the sole owner.
    Reconciliation retains only exact order IDs already persisted for the
    active Capsule. Symbol, side, price, trigger price, quantity, and timing
    never authorize adoption; another Capsule's tracking file cannot confer
    ownership.
  - Negative regressions cover exchange-generated STOP/TAKE_PROFIT IDs that
    resemble a managed parent but lack exact ID evidence, and cross-Capsule
    non-inheritance. Such orders remain `Exchange only` and cannot enter cancel,
    replacement, or managed-order revalidation paths.
  - No DTO, service, registry, exchange request, Core/FFI path, persistence
    route, or runtime behavior was added. A future change requires new exact
    provider evidence and a separately selected remediation; it may extend the
    existing owner only.
  - Status: classified fail-closed (2026-08-11); GitHub issue `#26` may close
    after PR and post-merge gates pass. No manual smoke or release candidate is
    implied because production behavior is unchanged.

- `1.x Capsule AI Runtime restart acceptance`
  - Lane: maintained 1.x product evidence; no production runtime change.
  - Invariant: saved provider configuration survives application restart, the
    process-memory AI lease does not, explicit unlock restores the saved
    provider without API-key re-entry, and inference remains bound to the
    active Capsule before dispatch and after provider completion.
  - Sole owners remain `AiDoctorCredentialStore` for provider configuration
    and process lease, and `CapsuleAiRuntimeService` for request execution and
    Capsule binding. No AI-5, DTO, provider adapter, credential reader,
    scheduler, Core path, or second acceptance document is added.
  - Automated evidence adds a fresh-store restart regression and reuses the
    existing locked-session, wrong-Capsule, and stale-completion runtime tests.
    The existing AI Engineer release smoke checklist now owns packaged
    configured-but-locked, explicit-unlock, no-key-reentry, and Capsule-switch
    acceptance.
  - Exit evidence: focused tests, full repository gates, green PR and
    post-merge checks passed. The published macOS `test16` artifact with SHA-256
    `a4775a3b6321cebd25c2e7b327257f7060df04baf3596f01c84d1c3fe8dfd6da`
    was used without rebuild; the three AI owner files have no diff from its
    source commit `30e0800`.
  - Packaged evidence: cold start restored Gemini and `gemini-2.5-flash` while
    leaving the API-key field empty; outbound preview bound snapshot
    `8a190e23127fa67c91117f3a0264a99612a59233787a17efefb44bc6399d5735`,
    `4003` bytes, and `Secrets redacted: true`. Explicit Ask reached Gemini with
    the saved key, surfaced temporary provider backpressure, and one bounded
    retry returned an advisory result. No state mutation or fatal runtime
    evidence was observed. Wrong-Capsule and stale-completion rejection remain
    proven by the focused runtime regressions.
  - Status: completed (2026-08-11); reference-grade 1.x baseline accepted. No
    AI-5, release candidate, or following product pass is selected
    automatically.

- `1.x Trading Remote Runner Pass A — public-data shadow contract`
  - Selected lane: product design only. The existing Trading Drone goal
    contract is the sole normative owner; no new document, schema, DTO, gate,
    service, repository, deployment, or runtime path is introduced.
  - The pass separates reproducible unattended compute from authority. A
    future runner may consume public BingX market data and produce signed,
    hash-linked shadow decisions; it cannot receive Capsule material, local
    trading credentials, account state, approval, consensus, or exchange-effect
    capability.
  - The contract binds package/policy/snapshot/decision identity, ordered
    evidence, bounded freshness, runner-key binding, replay/fork rejection,
    revocation, parity evidence, and zero authenticated remote calls. It seals
    Capsule-on-VPS, trading-key-on-VPS, and second-execution-route shortcuts.
  - Official provider evidence confirms that public market data is accessible
    without authentication and that read-only or IP-bound API keys are distinct
    provider controls. Pass A deliberately uses neither key type; any account
    read or trade authority requires a separate later decision.
  - Architecture-economy result:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | One section in the existing Trading goal contract | Capsule-on-VPS, local trading-key-on-VPS, remote effects, and a second execution route are forbidden | Unattended shadow compute is separated from account access and trading authority | Zero runtime owners; zero runtime/effect paths | No runner lease/evidence implementation, remote storage, deployment, or live parity proof exists | Consolidation may decide whether a fixture-only shadow harness is the smallest justified Pass B |

  - Status: completed (2026-08-11). PR and post-merge gates passed; zero runtime
    paths were added. Implementation, deployment, Pass B, release work, and
    24/7 trading claims remain unauthorized.

- `1.x Trading Remote Runner Pass B — fixture-only shadow evidence`
  - Selected lane: bounded 1.x validation harness. The existing
    `BingxFuturesDeterministicReplayHarnessService` remains the sole owner; one
    colocated evidence value represents the Pass A wire commitment without a
    new service, repository, transport, screen, or effect route.
  - The harness binds a domain-separated canonical commitment to runner key,
    suite, build/ABI, plugin/version/package, policy,
    snapshot/features/decision, validity, sequence, and previous evidence hash.
    Signature verification precedes both acceptance and exact-replay
    classification.
  - Golden and negative fixture vectors close downgrade, spoofing, invalid
    signature, stale evidence, changed-content replay, fork, build,
    plugin/package, policy, and local parity ambiguity. Remote evidence remains
    diagnostics only and cannot become a Trading intent or exchange effect.
  - Architecture-economy result:

    | Added | Removed or sealed | Ambiguity eliminated | New owner/path count | Remaining compatibility debt | Next decision unlocked |
    | --- | --- | --- | --- | --- | --- |
    | One evidence value and fixture mutations in the existing replay owner | Unauthenticated exact replay, changed-content sequence reuse, chain fork, downgrade, and package/policy substitution fail closed | The exact authenticated shadow commitment and local parity order are executable | Zero new owners; zero network/effect paths | No live observations, acceptance persistence, runner lease, deployment, account reads, or remote execution | A later review may decide whether live public-observation parity is justified |

  - Status: completed (2026-08-11) through PR `#39`; required PR and exact
    post-merge repository gates passed. No manual smoke was required because no
    app route, network, storage, credential, UI, FFI, Core, or exchange behavior
    changed. No following pass, deployment, release work, or 24/7 claim is
    selected automatically.

- `1.x Trading Remote Runner Pass B remediation — public shadow and wire`
  - Finding: the first Pass B harness fed Capsule-local consensus inputs into
    the shadow rule evaluation and verified a typed value without an
    untrusted-byte parser, so neither remote authority separation nor a real
    cross-language wire contract was proven.
  - Remediation owner remains
    `BingxFuturesDeterministicReplayHarnessService`. Public shadow computation
    now excludes consensus, blocking facts, account risk, execution, and effect
    state. Local gates remain downstream and may block any matching shadow
    signal.
  - One compact ordered JSON wire is parsed from strict UTF-8 and accepted only
    after byte-for-byte canonical re-encoding. The existing Trading parity gate
    runs an independent Python reconstruction of the Dart golden fixture and
    negative whitespace/order/unknown/duplicate/local-field mutations.
  - Status: completed through PR `#41` and exact post-merge run `31486417119`
    (2026-08-11). Runtime consumers, network, persistence, credentials, UI, VPS,
    effects, release work, and Pass C remain unchanged and unauthorized.

- `1.x Trading market/local-guard consolidation`
  - Scope: remove the remaining structural smell after Pass B without selecting
    Pass C. The existing `BingxFuturesTvhRuleEngineService` remains the sole
    decision owner.
  - `evaluateMarket()` owns market-only TVH evaluation and accepts no consensus
    or blocking arguments. Existing `evaluate()` owns the local consensus guard
    and delegates to the same market evaluator after that guard passes. The
    public replay harness no longer supplies a synthetic consensus value.
  - Exit evidence: existing market decision hashes remain stable, local blocked
    behavior remains stable, and focused tests prove the public method cannot
    receive local guard inputs.
  - Status: complete through full local and clean-checkout gates, protected PR
    `#43`, and exact post-merge run `31487730478` (2026-08-11). No runtime
    consumer, network, persistence, credential, UI, VPS, effect, release, or
    Pass C was added; no next pass is selected.

- `1.x Trading Liquidity Lifecycle hardening`
  - Selected lane: bounded 1.x product hardening in the existing market and
    zone owners. This is not Remote Runner Pass C and adds no server, network,
    credential, persistence, plugin ABI, or exchange-effect path.
  - Provider klines are classified against one injected UTC observation clock.
    Forming candles are excluded from the canonical snapshot digest, derived
    liquidity, feature extraction, and zone evaluation.
  - The existing `BingxFuturesZoneDecisionService` reconstructs one pure
    closed-candle sweep event. Reclaim requires a directional body of at least
    `0.5 * ATR14`, expires after 8 bars, rejects more than 2 failed close-back
    attempts, and remains anchored to the exact sweep extreme.
  - Fixed percentage reverse parameters that had no runtime consumer were
    removed. No external indicator code, UI drawing state, alert state, or
    mutable market-state owner was introduced.
  - Exit gate: focused and full repository checks, then one bounded manual
    zone-calculation smoke with no live order. Release, remote runner, and
    following product work require separate selection.
  - Status: complete locally (2026-08-11). Full gates passed. Automatic macOS
    smoke scanned the six-symbol Core Watchlist, selected SOL-USDT as READY,
    calculated a fresh executable sellside zone, and prepared the decision
    envelope without invoking an exchange order effect. Android was not
    required because this pass changed the shared deterministic market/zone
    pipeline rather than a platform adapter. No following pass is selected.

- `1.x Trading Intent Freshness and One-Event/One-Effect`
  - Selected lane: bounded local 1.x trading lifecycle hardening. Remote
    Runner/VPS, background execution, credentials, plugin ABI, release work,
    and a second exchange-effect route remain outside scope.
  - Invariant: one stable liquidity event can authorize at most one test/live
    exchange effect, and only while the exact prepared closed-bar decision is
    still current.
  - Sole owners: `BingxFuturesZoneDecisionService` derives event identity,
    `BingxFuturesExchangeExecutionUseCaseService` owns freshness and exchange
    submission, and the existing Capsule-scoped order tracking store owns the
    durable effect claim.
  - Sealed paths: timestamp-only client IDs, queue-only process idempotency,
    post-effect-only ownership recording, and replacement's direct queue call.
  - Exit evidence: stale-bar/event negative vectors, concurrent duplicate and
    restart recovery, Capsule isolation, bounded fail-closed claim retention,
    one queue caller, full local/clean-checkout gates, protected PR, and green
    post-merge repository gates.
  - Status: complete (2026-08-11) at `255a356`; protected PR `#46`, clean
    checkout, and post-merge repository gates `31531348050` passed. No
    following product pass is selected.

- `1.x Trading Restart Recovery and Reconciliation`
  - Lane: maintained 1.x runtime; Remote Runner/VPS, background execution,
    plugin ABI, Core/Ledger changes, and new effect paths remain blocked.
  - Owner: the existing exchange execution use case classifies lifecycle,
    `BingxFuturesOrderTrackingStore` persists Capsule-scoped evidence, and the
    existing BingX adapter performs exact read-only order queries.
  - Sealed path: absence from the provider open-orders collection no longer
    deletes ownership/provenance or guesses a terminal outcome.
  - Evidence: exact active and terminal statuses, timeout, provider not-found,
    account mismatch, provider acceptance before order-id capture, late
    Capsule switch, manual-order non-adoption, and durable event claims.
  - Status: complete (2026-08-13) at `399b949`; protected PR `#48`, clean
    checkout, and post-merge repository gates `31644669310` passed. No
    following pass is selected.

- `1.x Trading Productization and 24/7 Readiness`
  - Product objective: make Trading Drone a reference-grade capability that
    can observe, decide, execute, recover, and reconcile continuously without
    turning AI into authority or moving the Capsule onto a server.
  - Proven baseline: freshness, one liquidity event to at most one effect,
    managed-order ownership, restart recovery, reconciliation, deterministic
    risk gating, and public shadow evidence already have canonical owners.
  - Product sequence is ordered and fail-closed:
    1. build a truthful public-market liquidity confluence map;
    2. prove one local strategy lifecycle with replay and adverse vectors;
    3. bind unattended actions to a Capsule-owned bounded trading mandate;
    4. run the same decision and effect contracts in a headless host;
    5. authorize scoped remote execution only with lease, kill switch, account
       binding, risk ceilings, exact receipts, and restart reconciliation.
  - Completed rung: `Liquidity Confluence Observation`. The existing
    live snapshot builder owns public observations and the existing zone
    decision service owns entry-zone semantics. Replace the single-largest
    bid/ask proxy with bounded deterministic clusters combining depth, closed
    structure, open-interest change, funding, and aggressive flow. Market-wide
    liquidation positions are not exposed by the current BingX public API, so
    inferred clusters remain `liquidation_proxy`; they may rank context,
    targets, and activation areas but cannot independently authorize an order.
  - Threat model: spoofed walls, rapidly withdrawn depth, stale snapshots,
    crossed or malformed books, duplicated levels, outlier notionals, changed
    funding/OI windows, proxy/confirmed-data confusion, and a cluster becoming
    an accidental second entry owner must fail closed or remain diagnostic.
  - Exit evidence: deterministic clustering and ordering, bounded inputs and
    outputs, permutation stability after canonicalization, stale/malformed/
    spoof-prone negative vectors, explicit proxy provenance, unchanged effect
    count for proxy-only evidence, full local and clean-checkout gates,
    protected PR/post-merge CI, and packaged Trading diagnostics smoke.
  - Removed or sealed: the current single-largest-level representation is
    removed; proxy-as-confirmed-liquidation and proxy-only order authorization
    remain sealed. No new DTO family, market-state owner, exchange adapter,
    execution route, Capsule/Core/Ledger path, VPS deployment, tag, or Release
    is authorized by this pass.
  - Status: implementation merged (2026-08-15) at `d2797bf`; protected PR
    `#79` and post-merge repository gates `31891306724` passed. Packaged smoke
    found that the live BingX depth wire uses uppercase `T`, while the existing
    adapter accepted only legacy timestamp aliases. The same adapter owner was
    remediated at `79e0af4`; regression coverage, protected PR `#80`, and
    post-merge repository gates `31892115092` passed. A fresh macOS Release
    smoke artifact from `79e0af4`, build `1.0.3+100030037`, has SHA-256
    `f1e5383752c04a85d6c90a2a5deb2b68c63b6f45e017968ba3dd05ca3203d7dd`.
    A live production-adapter probe parsed the timestamped 20x20 public book,
    and the existing snapshot builder produced non-empty bounded buy-side and
    sell-side `liquidation_proxy` clusters without creating an exchange effect.
    Packaged macOS Hands diagnostics subsequently crossed the Keychain boundary
    through explicit user authorization, loaded the Capsule-scoped credentials,
    restored zero managed orders, and ran only the canonical `Run Intent` path.
    The decision projected `sellside:63095.00068126` and
    `buyside:63086.7100533`, returned `noSignal` because the deterministic trade
    and session-delta gates failed, and created no exchange effect. Status:
    complete. No next pass is selected pending a short consolidation review.

- `1.x Trading Local Strategy Lifecycle Evidence`
  - Lane: maintained 1.x product completion; this is evidence and bounded
    remediation of the existing local path, not a new strategy or runtime.
  - Invariant: one prepared strategy intent traverses the existing decision,
    host, risk, queue, exchange, receipt, tracking, and reconciliation owners;
    replay or restart cannot create a second semantic effect.
  - Sole effect owner: `BingxFuturesExchangeExecutionUseCaseService`; the screen
    remains an action/projection surface and cannot own an alternate effect.
  - Threat model: changed decision/bar/event, stale zone, risk rejection,
    transient ambiguity, duplicate action, restart, missing receipt, unrelated
    manual order, and Capsule switch must fail closed or remain unresolved.
  - Exit evidence: the existing adverse suites pass as one focused matrix;
    packaged macOS diagnostics capture decision and execution hashes for a
    test-order receipt; restart/reconciliation preserves the same ownership and
    effect count; Android parity is assessed before closure.
  - Removed or sealed: stale checklist ambiguity is removed. Live orders,
    background execution, Remote Runner/VPS, mandate design, new DTO/service,
    second exchange route, Core/Ledger writes, plugin ABI changes, tags, and
    Releases remain sealed.
  - Status: complete (2026-08-15) on `main` at `e25b1e0`. Protected PR `#86`
    and post-merge repository gates passed. Packaged macOS Release build
    `1.0.3+100030040` produced one successful `/order/test` receipt after exact
    semantic freshness and risk checks, persisted the operation provenance,
    restored the unresolved ownership evidence after a cold restart, and did
    not repeat the provider effect. The matching Android package loaded the
    Trading Drone, fetched 1,039 perpetual markets, rejected `Run Intent` as
    `blocked:drone_paused` without an exchange call, and reopened after a cold
    restart without adopting unrelated orders. No following product pass is
    selected automatically.

- `1.x Trading Durable Emergency Pause`
  - Lane: maintained 1.x trading productization; bounded remediation before any
    mandate or remote-host design.
  - Invariant: a Capsule that is paused cannot create an exchange effect after
    restart, Capsule switch, missing/corrupt state, or a pause written while
    risk inputs are refreshing.
  - Owners: the existing `BingxFuturesOrderTrackingStore` owns the
    Capsule-scoped control bit; `BingxFuturesExchangeExecutionUseCaseService`
    remains the sole exchange-effect owner and verifies durable control before
    risk work and immediately before claim/queue.
  - Evidence: state schema v5 preserves explicit enabled and paused values,
    legacy or malformed values resolve fail-closed, Capsule scopes remain
    isolated, and focused tests prove restart plus mid-flight pause rejection
    without provider access.
  - Removed or sealed: process-local default enablement is removed. No new
    service, mandate DTO, effect path, Core/Ledger fact, plugin ABI, live order,
    background execution, Remote Runner/VPS, tag, or Release is authorized.
  - Status: complete on `main` at `4d2f09f` (2026-08-15). Protected PR `#88`,
    required branch gates, and post-merge run `31904504430` passed. Same-source
    smoke-only Release build `1.0.3+100030041` proved Android enable and pause
    persistence across separate cold restarts and left the Capsule paused;
    macOS restored the paused state after a cold process restart and explicit
    Keychain authorization. Source was `4d2f09f`; macOS executable SHA-256 was
    `6a8e82254649fb3f532b1d7190309e287d9c2dd1fb2b56b4e056402d07de1e90`
    and Android APK SHA-256 was
    `01303b706745ce4d9ef7e2df4a3e696872f8194c4f169047116b618ecf121027`.
    No provider effect, tag, or Release was created. No following product pass
    is selected automatically.

- `1.x Trading Capsule-Owned Bounded Mandate`
  - Lane: maintained 1.x Trading productization; local authority proof before
    any headless-host work.
  - Invariant: every new exchange order effect is bound to one active
    Capsule-owned mandate covering the exact account, symbol, test/live mode,
    validity window, max notional, deterministic risk policy, and effect
    budget.
  - Sole owners: the existing order-tracking store owns mandate state and the
    existing exchange-execution use case owns enforcement and provider effect.
  - Removed or sealed: process-local/static UI policy cannot independently
    authorize an effect; legacy enablement, mutation-in-place, implicit renewal,
    cross-Capsule/account reuse, budget overrun, Remote Runner/VPS, background
    execution, second effect route, Core/Ledger fact, and plugin ABI remain
    sealed.
  - Exit evidence: semantic commitment mutations, expiry/revocation, restart,
    Capsule/account/symbol/mode mismatch, policy escalation, notional ceiling,
    atomic effect-budget exhaustion, full local and clean-checkout gates,
    protected PR/post-merge CI, and same-source packaged control smoke without
    a live provider effect.
  - Status: complete on `main` at `61f8f1d` (2026-08-16). Protected PR `#91`,
    required branch gates `31915301503`, and post-merge repository gates
    `31915346326` passed. Same-source automatic packaged control smoke created
    one test-mode mandate on macOS, preserved its exact id across cold restart,
    revoked it through Emergency Pause, and preserved the revoked state across
    another cold restart. The pre-existing effect-claim count remained one and
    no new provider effect was requested. The Android upgrade preserved its
    Capsules and opened the shared Trading UI paused; `Run Intent` was not
    invoked. Source was `61f8f1d`; macOS Release build `1.0.3+100030017` ZIP
    SHA-256 was
    `3bec7a6ce665de33345eee5cd1a079d29efacfe5d0b2f1bb2886915279e19b9a`, and
    Android Release build `1.0.3+100030042` APK SHA-256 was
    `9c68811a0aae3f08d61f22d9668166cff29d62b9bc1786f5c68d7239be20a755`.
    No live order, background execution, Remote Runner/VPS, tag, or Release was
    created. No following product pass is selected automatically.

- `1.x Trading Headless Cycle Port`
  - Lane: bounded 1.x Trading productization between the proven local mandate
    and any separately authorized host/deployment work.
  - Invariant: foreground solo limit preparation and a future headless host use
    one capability-owned cycle command/result path. Decision, sizing, WASM
    intent, mandate/risk/freshness enforcement, event claim, provider effect,
    receipt, and reconciliation retain their existing owners.
  - Sole application owner: `TradingDroneModuleService` composes
    `BingxFuturesTradingCycleUseCaseService`; the latter replaces the
    screen-owned solo limit orchestration and delegates an optional effect only
    to `BingxFuturesExchangeExecutionUseCaseService`.
  - Threat model and negative vectors: invalid symbol/side/budget, missing or
    changed event evidence, blocked sizing, rejected WASM intent, missing
    credential, stale refresh, revoked/expired mandate, duplicate event, and
    provider ambiguity must stop before or remain inside their canonical owner.
  - Removed or sealed: the solo limit UI no longer owns a parallel market ->
    sizing -> intent composition. Scheduler, daemon, SSH/VPS deployment,
    credential transfer, lease activation, live order, background execution,
    second provider/effect route, Core/Ledger fact, plugin ABI, tag, and Release
    remain sealed.
  - Exit evidence: focused cycle and existing execution suites, full local and
    clean-checkout gates, protected PR/post-merge CI, then same-source packaged
    preparation smoke with zero provider effect.
  - Status: complete on `main` at `b00ba99` (2026-08-17). Protected PR `#93`,
    required branch gates `31920130783`, and post-merge repository gates
    `31920174774` passed. Same-source Hands smoke used Release build
    `1.0.3+100030043`: macOS prepared ETH-USDT with a decision envelope and
    `effect=false`; Android prepared BTC-USDT with a decision envelope and
    `effect=false`. No `bingx.exchange.execute` event, provider effect, tag, or
    Release was created. macOS ZIP SHA-256 was
    `7f351669d99905205c4c0ce16c939380890cc559c5b7b996c704501e09cfa160`;
    Android APK SHA-256 was
    `f9f7bf91c4f8ff414a8d29d0a8f79ee85ec451938701242eefc8991c1cfaa173`.
    Smoke found a separate presentation P2: the UI shows an unswept HTF
    pending-liquidity anchor as `READY` and labels its bounds only as `Zone
    Low/High`, without source time, age, distance, or clarification that the
    bounds are not current market prices. The BTC evidence was recomputed on
    `Run Intent` from a `4h_fresh_high`; independent reconstruction placed the
    selected unswept pivot at 2026-07-27T04:00:00Z, 124 closed 4h bars before
    the observed snapshot. This does not contradict the canonical `fresh =
    unswept` lifecycle or prove stale-cache reuse, but the UI ambiguity must be
    remediated through the existing decision/projection path before Remote
    Runner/VPS work. No algorithmic age policy is changed by this checkpoint.
    The bounded presentation remediation is complete on `main` at `6c6c7aa`
    (2026-08-17). Protected PR `#95`, required branch gates `31979736936`, and
    post-merge repository gates `31979798382` passed. One pure formatter and an
    optional existing-result projection field expose source, formation time,
    age, signed distance, and `Run Intent` revalidation without changing the
    decision hash, strategy policy, owner, DTO family, or effect path. Hands
    smoke used same-source macOS and Android Release build
    `1.0.3+100030044`. Both platforms displayed the pending-zone evidence,
    cleared it on symbol change, and recomputed it through `Run Intent` with
    `effect=false`; no `bingx.exchange.execute` event occurred. The smoke-only
    macOS ZIP SHA-256 was
    `8d9f8e4db34753ecbde10d89baeaffed50a79547c6e6f421d45c2a8cf9efb050`;
    Android APK SHA-256 was
    `30bd88aed3bd48d15c5641851e7e973e59928c6bdaabb2d30ef8c5e1225857e6`.
    No next pass, tag, Release, scheduler, or Remote Runner/VPS deployment is
    selected by this evidence checkpoint.

- `1.x Trading Remote Runner Pass C — Live Public Shadow Probe`
  - Lane: bounded 1.x Trading productization; no release or deployment work.
  - Invariant: a headless process can reproduce one live public market decision
    and emit the existing authenticated shadow wire without receiving Capsule,
    account, credential, mandate, order, consensus, or effect authority.
  - Sole owner: `BingxFuturesDeterministicReplayHarnessService` retains shadow
    evidence semantics. `BingxFuturesPublicMarketDataPort` is only the narrowed
    provider contract; the CLI is a replaceable one-shot composition boundary.
  - Removed or sealed: credentials are removed from live snapshot and strategy
    commands, the public pipeline no longer depends on the concrete
    effect-capable exchange adapter, and direct reuse of the app-wide Trading
    module as a remote host is forbidden.
  - Exit evidence: canonical metadata and validity rejection, public-input
    failure, signature verification, no-overwrite output, authority-boundary
    mutation tests, full Flutter/Rust/repository gates, one live BingX public
    observation, protected PR gates, and green post-merge CI.
  - Remaining boundary: retained sequence state, restart continuity, daemon,
    scheduler, VPS deployment, lease activation, account reads, remote effects,
    tag, and Release remain unauthorized and unimplemented.
  - Status: complete on `main` at `a7158d1` (2026-08-17). Protected PR `#97`,
    required run `31993523725`, and post-merge run `31993593095` passed. A live
    public observation produced decision `long` and evidence hash
    `c116410ff689cec4833f332e64c6dce9601e2d218f68da409955c20813f4c311`;
    OpenSSL independently verified its Ed25519 signature. No following pass is
    selected automatically.

- `1.x Trading Remote Runner Pass D — Durable Shadow Stream and Restart Continuity`
  - Lane: bounded 1.x Trading productization; no release or deployment work.
  - Invariant: one runner key resumes one authenticated immutable evidence
    chain after process restart; no observation failure, retry, or concurrent
    process may reuse a sequence or fork the predecessor hash.
  - Sole owner: `BingxFuturesShadowStreamStore` owns runner-only durable
    retention; the existing replay harness retains evidence semantics,
    authentication, public decision, and canonical wire ownership.
  - Removed or sealed: the probe can no longer restart at sequence `1` when a
    stream exists; retained evidence cannot be overwritten, evicted, repaired,
    or silently reset by the store. Capsule/order/effect journals remain sealed
    out of the remote shadow path.
  - Exit evidence: authenticated restart continuation, same-process and real
    cross-process serialization, exhausted lock budget, failed-observation
    no-write, corruption, signature mutation, wrong key, sequence/predecessor conflict,
    unknown-entry, bounded-capacity, structural mutation, full local and clean
    checkout gates, protected PR, and green post-merge CI.
  - Remaining boundary: stream rotation, rollback-resistant external anchors,
    scheduler/daemon, transport/receiver, VPS deployment, lease activation,
    account reads, local acceptance state, remote effects, tag, and Release are
    unauthorized.
  - Status: complete on `main` at `014180c` (2026-08-17). Protected PR `#99`,
    required run `32001611779`, and post-merge run `32001689942` passed.
    Flutter `906/906`, analyze, Rust workspace, full review gates, clean
    checkout, and `25/25` focused restart/adverse tests passed. No following
    pass is selected automatically.

- `1.x Trading Remote Runner Pass D Remediation — Crash-Atomic Shadow Append`
  - Lane: bounded remediation of the existing runner-only durable stream; no
    release, deployment, scheduler, receiver, account, or effect work.
  - Finding: the final committed file was created before its canonical bytes
    were flushed, so process termination could leave a visible empty or
    truncated committed entry and permanently block restart.
  - Invariant: one exclusive pending write is flushed before atomic rename;
    rename is the sole commit point. Restart may remove only one regular file
    with the exact canonical pending name. Committed evidence is never deleted,
    replaced, rewritten, or repaired.
  - Sole owner: the existing `BingxFuturesShadowStreamStore`; the replay
    harness retains evidence semantics and authentication ownership.
  - Removed or sealed: the partial-committed-file crash window and any cleanup
    interpretation that could delete committed evidence. Unknown, linked, or
    multiple pending state fails closed.
  - Exit evidence: interrupted pending recovery, unknown pending rejection,
    committed target conflict, retained corruption rejection, structural
    negative mutation, full local and clean-checkout gates, protected PR, and
    green post-merge CI.
  - Remaining boundary: rollback-resistant anchors, rotation, daemon,
    scheduler, transport/receiver, VPS deployment, leases, account reads,
    local acceptance state, remote effects, tag, and Release remain
    unauthorized.
  - Status: complete on `main` at `ede2eb3` (2026-08-17). Protected PR `#101`,
    required run `32021137109`, and post-merge run `32021215679` passed.
    Flutter `910/910`, analyze, Rust workspace, full review gates, clean
    checkout, and `15/15` focused crash-atomic adverse tests passed. No
    following pass is selected automatically.

- `1.x Trading Remote Runner Pass E — Authenticated Bounded Stream Compaction`
  - Lane: bounded 1.x Trading productization before any scheduler or VPS work.
  - Invariant: one full authenticated tail is replaced only by its exact final
    signed checkpoint committed before cleanup; global sequence and predecessor
    continuity never reset across compaction or restart.
  - Sole owner: the existing `BingxFuturesShadowStreamStore`; the canonical
    shadow evidence remains the checkpoint wire and authentication contract.
  - Removed or sealed: the 256-entry terminal capacity dead end is removed.
    Unauthenticated deletion, conflicting overlap, key confusion, partial
    checkpoint success, a second journal, daemon, deployment, lease, account
    access, Capsule state, and remote effects remain sealed.
  - Exit evidence: full-tail continuation, restart, committed-before-cleanup
    recovery, conflicting checkpoint no-delete, non-file and interrupted state,
    concurrency, structural mutation, full local and clean-checkout gates,
    protected PR, and green post-merge CI.
  - Status: complete on `main` at `8c5c644` (2026-08-17) through protected PR
    `#113`; required run `32042296142` and post-merge run `32042345162` passed.
    Focused store `27/27`, combined shadow/replay `39/39`, Flutter `927/927`,
    analyze, Rust workspace, full review gates, clean detached-checkout, and the
    checkpoint-before-cleanup negative mutation passed. No new owner or path
    was added. This local checkpoint does not provide rollback resistance;
    external anchoring remains a separate prerequisite before any remotely
    authorized effect. No following pass is selected automatically.

- `1.x Trading Remote Runner Pass F — Public-Only Bounded Scheduler`
  - Lane: bounded 1.x Trading productization before deployment or authority.
  - Invariant: one existing probe process runs at most 288 public observations
    strictly serially, with an explicit 60–3600 second delay after each
    successful append; the first failure stops without retry or inferred
    success.
  - Sole owner: the existing `trading_remote_shadow_probe.dart` composition
    root schedules the existing harness and stream store. No scheduler service,
    journal, receiver, supervisor, or deployment owner is added.
  - Removed or sealed: repeated manual one-shot invocation is replaced by one
    bounded command. Overlap, endless loops, catch-up, hidden retry, scheduler
    state, VPS configuration, credentials, account reads, Capsule state,
    leases, remote effects, tags, and Releases remain sealed.
  - Exit evidence: serial cadence, stop-on-first-failure, invalid bounds,
    scheduler and authority mutation tests, full local and clean-checkout
    gates, protected PR, and green post-merge CI.
  - Status: complete on `main` at `712177f` (2026-08-17) through protected PR
    `#115`; required run `32043346812` and post-merge run `32043400512` passed.
    Scheduler `4/4`, combined scheduler/shadow/replay `45/45`, Flutter
    `931/931`, analyze, Rust workspace, full review gates, clean detached-
    checkout, and scheduler/authority negative mutations passed. No new owner
    or path was added. This pass does not claim unattended VPS or 24/7 trading
    readiness. No following pass is selected automatically.

- `1.x Trading Remote Runner Pass G — Verifiable Standalone Host Artifact`
  - Lane: bounded 1.x Trading packaging before any host transfer or deployment.
  - Invariant: one completely clean source commit and pinned Dart SDK produce
    one host-native public-only binary whose exact bytes, source, platform,
    entrypoint, and authority profile are bound by one strict manifest.
  - Sole owner: `public_shadow_runner_artifact.sh` owns only package creation
    and verification around the existing probe; it owns no runtime state,
    scheduling, deployment, credential, account, or effect lifecycle.
  - Removed or sealed: a target host no longer needs the Flutter source tree or
    SDK to execute the probe. Dirty-source packaging, overwrite, malformed
    manifests, byte substitution, and authenticated authority markers fail
    closed. Transfer, Linux evidence, VPS installation, supervisor, site or
    Amnezia changes, credentials, account reads, external anchoring, and remote
    effects remain sealed.
  - Exit evidence: verifier hash/shape/authority negative tests, dirty-tree
    rejection, one clean host-native package, full local and clean-checkout
    gates, protected PR, and green post-merge CI.
  - Status: complete on `main` at `3fbe8f2` (2026-08-17) through protected PR
    `#117`; required run `32044373306` and post-merge run `32044425543` passed.
    The post-merge Darwin arm64 artifact is 6,917,488 bytes with SHA-256
    `4782f3f119f1975dc4ed7005f94ad96526ae6f9753377483102e0c1adf498282`.
    Verifier negative tests, dirty-tree rejection, Flutter `931/931`, analyze,
    Rust workspace, full review gates, and clean detached-checkout packaging
    passed. Dart AOT is explicitly not claimed byte-reproducible. No new owner
    or path was added, and no following pass is selected automatically.

- `1.x Trading Remote Runner Pass H — Pinned Linux x64 Artifact Evidence`
  - Lane: bounded 1.x Trading Linux packaging evidence before any host action.
  - Invariant: one pinned pure-Dart lock and one clean source commit produce an
    explicit `linux/x64` binary; the manifest binds the lock SHA and verifier
    requires matching ELF x86-64 bytes.
  - Sole owner: the existing artifact script owns dependency resolution,
    cross-target compilation, and verification. The existing probe remains the
    sole entrypoint; no runtime or deployment owner is added.
  - Removed or sealed: Linux evidence no longer requires the full Flutter Linux
    archive or a duplicate runner. Unlocked resolution, package drift, generic
    target expansion, and target/binary confusion fail closed. Execution,
    transfer, installation, supervisor, VPS networking/resources, site or
    Amnezia changes, credentials, account reads, external anchoring, and remote
    effects remain sealed.
  - Exit evidence: pinned lock validation, target/binary and authority negative
    tests, one clean Linux x64 artifact, full local and clean-checkout gates,
    protected PR, and green post-merge CI.
  - Status: complete on `main` at `ea36a8b` (2026-08-17) through protected PR
    `#119`; required run `32054282257` and post-merge run `32054365614` passed.
    The post-merge ELF x86-64 artifact is 7,807,720 bytes with SHA-256
    `8c31e006535227088ea4b9ff63f162d06760f37c28bd18072a6f18fcee1f34b6`;
    dependency-lock SHA-256 is
    `f5443e020cbafc892fb75080be84899d3d7f6196be1dc0f7525d73f1eac789ac`.
    Flutter `931/931`, analyze, Rust workspace, full review gates, clean
    detached-checkout packaging, and negative mutations passed. No runtime
    owner or path was added. Linux runtime compatibility and deployment are not
    claimed, and no following pass is selected automatically.

- `1.x Trading Remote Runner Pass I — Linux Runtime Startup Evidence`
  - Lane: bounded 1.x Trading packaging/CI; no host deployment or release work.
  - Invariant: the exact manifest-verified Linux x64 ELF starts on a matching
    Linux host and reaches the canonical probe's fail-closed missing-authority
    boundary with the runner seed removed from its environment.
  - Sole owner: the existing artifact script owns packaging and runtime-startup
    evidence; the existing probe remains the sole entrypoint. No service,
    receiver, supervisor, deployment, credential, account, or effect owner is
    added.
  - Removed or sealed: Linux runtime compatibility can no longer be inferred
    from ELF shape alone. Loader failure, target mismatch, inherited authority,
    unexpected output, and false success fail closed. The ephemeral artifact is
    not uploaded. Public provider execution, transfer, VPS/SSH, installation,
    site or Amnezia changes, credentials, account reads, external anchoring,
    leases, and effects remain sealed.
  - Exit evidence: focused artifact/parity gates, negative authority mutation,
    full local and clean-checkout gates, protected PR `review-gates`, and green
    post-merge CI.
  - Status: complete on `main` at `1770ded` (2026-08-17) through protected PR
    `#121`; required run `32057547066` and post-merge run `32057670511` passed.
    The required Ubuntu job built and verified one ephemeral Linux x64 artifact,
    executed it without runner authority, reached the exact canonical
    missing-authority rejection, preserved a clean post-review checkout, and
    uploaded nothing. No owner, runtime/effect path, VPS change, credential,
    account read, tag, or Release was added. No following pass is selected
    automatically.

- `1.x Trading Remote Runner Pass J — Ephemeral VPS Public Observation Evidence`
  - Lane: bounded 1.x Trading host-compatibility evidence; no installation,
    supervisor, credential, account, effect, or release work.
  - Invariant: one exact public-only artifact runs one low-priority observation
    from a unique temporary host directory, while the website and existing VPN
    containers remain healthy; every transferred and generated smoke artifact
    is removed afterward.
  - Sole owner: the existing probe owns the cycle and the existing shadow store
    owns its temporary stream. The host adds no service, container, receiver,
    listener, journal, account, or effect owner.
  - Removed or sealed: target-host public provider and resource compatibility
    are no longer inferred from CI startup alone. Binary mismatch, timeout,
    runner failure, service regression, and residual process/path state fail
    closed. Durable identity, installation, supervisor, credentials, account
    reads, external anchoring, leases, and effects remain sealed.
  - Evidence: clean source `12c8f30`; Linux artifact SHA-256
    `8c31e006535227088ea4b9ff63f162d06760f37c28bd18072a6f18fcee1f34b6`;
    one 3.213-second public observation; peak RSS 24,072 KiB; sequence `1`;
    evidence hash
    `5c8f75b6b7fb32b9f09e4c2b1a33ceec16d18068a0144eb0ca7d06f21986013b`;
    no stderr; website and VPN continuity; zero residual process/path state.
    Status: complete (2026-08-17). No following pass is selected automatically.

- `1.x Trading Remote Runner Pass K — Ephemeral VPS Resource Soak Evidence`
  - Lane: bounded 1.x Trading host-resource evidence; no installation,
    supervisor, credential, account, effect, or release work.
  - Invariant: one exact public-only artifact completes 60 strictly serial
    observations inside one finite transient cgroup while website and VPN
    continuity remain unchanged; all process and path state is removed.
  - Sole owner: the existing probe scheduler owns cadence and the existing
    shadow store owns evidence retention. The transient cgroup constrains the
    process but owns no runtime state, retry, journal, authority, or effect.
  - Removed or sealed: one-cycle RSS is no longer extrapolated into an
    unattended-host budget. A `MemoryHigh=48 MiB` preflight caused sustained
    reclaim pressure and cadence degradation, and the measured natural peak
    leaves insufficient production margin under 64 MiB. Persistent units,
    users, paths, credentials, account reads, external anchors, leases, remote
    effects, tags, and Releases remain sealed.
  - Evidence: clean source `f98ce25`; Linux artifact SHA-256
    `8c31e006535227088ea4b9ff63f162d06760f37c28bd18072a6f18fcee1f34b6`;
    60 observations in 3,740 seconds under `MemoryMax=128 MiB`, no swap, and
    `TasksMax=16`; peak 66,367,488 bytes (63.29 MiB); post-collection current
    range 47,095,808–52,887,552 bytes and median 50,786,304 bytes; sequence
    `60`; final evidence hash
    `68915ba57a35e92d50003492030e48ef5c27394d2842b0442b0a783725547945`;
    no stderr; website and VPN continuity; zero residual unit/process/path
    state.
  - Next decision unlocked: a separate resource-bounded supervisor contract
    may start with a fail-closed 128 MiB ceiling. Tightening that ceiling,
    including to 96 MiB, requires longer-duration evidence. Status: complete
    (2026-08-18). No following pass is selected automatically.

- `1.x Trading Remote Runner Pass L — Fail-Closed Public-Shadow Supervisor Contract`
  - Lane: bounded 1.x Trading host lifecycle contract; no installation,
    enablement, credential creation, account access, effect, or release work.
  - Invariant: one successful bounded 288-cycle public-only batch may restart;
    any provider, validation, append, cadence, timeout, signal, or OOM failure
    remains stopped. The runner seed enters from exactly one strict encrypted
    credential file rather than unit environment or CLI text; ordinary private
    files and exact protected systemd `0440` delivery remain distinct.
  - Sole owner: systemd owns only process lifecycle and resource containment;
    the existing probe owns composition/cadence and the existing shadow store
    owns evidence continuity. One justified unit contract is added, with zero
    new domain, credential, journal, decision, or effect owner.
  - Removed or sealed: `Restart=always`/`on-failure`, environment secrets,
    linked/permissive seed files, 64 MiB limits, swap, unconstrained tasks,
    listener binding, mutable argument environments, and endless runtime are
    rejected. Bundle creation, installation, enablement, durable credential,
    exact-unit runtime smoke, external anchoring, leases, account reads, remote
    effects, tags, and Releases remain sealed.
  - Exit evidence: focused seed-file/scheduler tests, semantic unit parsing,
    restart/memory/credential/listener negative mutations, systemd 257 syntax
    verification, offline hardening analysis, full local and clean-checkout
    gates, protected PR, and green post-merge CI.
  - Evidence: implementation merged on `main` at `dc6ce3a` through protected
    PR `#125`; required run `32075468982` and post-merge run `32076142166`
    passed. Full Flutter `934/934`, Flutter analyze, Rust workspace, repository
    gates, focused `7/7`, and clean detached-checkout review passed. A clean
    Linux x64 artifact from `775378d` (tree-identical to the merged commit) had
    SHA-256
    `64264ae0bca4b0b90d768c4ce254f3ae7d488d16eb1c8b93ace8a9e5d8f08868`
    and size 7,810,680 bytes. An isolated transient VPS smoke appended one
    public evidence record with hash
    `e33532cf2e19cd86480ed95998217b0cbf9ccc5999b850a791b7e71a9ca6413e`.
    The malformed-credential case remained failed with exit status `1` and
    zero restarts after the 60-second restart window. The exact 128 MiB,
    no-swap, 16-task, protected-credential, and no-listener boundaries were
    observed; the website remained HTTP `200`, Amnezia containers retained
    zero restarts, listeners were unchanged, and all smoke state was removed.
  - Next decision unlocked: one verifiable artifact/unit bundle and atomic
    ephemeral install smoke may be evaluated separately before any persistent
    enablement. Status: complete (2026-08-18). No following pass is selected
    automatically.

- `1.x Trading Remote Runner Pass M — Verifiable Bundle and Ephemeral Exact-Unit Install`
  - Lane: bounded 1.x Trading packaging and host-installation evidence; no
    persistent deployment, account access, effect, or release work.
  - Invariant: one verified binary/unit/manifest bundle enters its canonical
    `/opt` destination through one rename. The exact unit may be linked and
    started without enablement only when every canonical target is absent; one
    authenticated public evidence append must be observed before success, and
    exact cleanup must leave no unit, credential, bundle, state, or enablement
    path.
  - Sole owner: the existing `public_shadow_runner_artifact.sh` owns bundle
    construction, verification, and the bounded ephemeral smoke. Systemd
    retains process lifecycle/resource ownership, the existing probe retains
    composition/cadence, and the existing shadow store retains evidence. No
    installer service, DTO, journal, credential owner, or effect path is added.
  - Removed or sealed: mixed binary/unit bundles, alternate destinations,
    symlink or pre-existing-state adoption, concurrent install races,
    plaintext seed files/environment, `systemctl enable`, false success before
    evidence, and incomplete cleanup fail closed. Persistent installation,
    boot enablement, durable runner identity, external anchoring, account
    reads, leases, remote effects, tags, and Releases remain sealed.
  - Exit evidence: bundle and parity self-tests with independent unit/path/
    collision/enablement/cleanup mutations; clean Linux x64 bundle build and
    verification; exact-unit ephemeral VPS smoke; website, listener, and
    Amnezia continuity; full local and clean-checkout gates; protected PR and
    green post-merge CI.
  - Evidence: implementation merged on `main` at `0ba5bcc` through protected
    PR `#127`; required run `32077843922` and post-merge run `32078130235`
    passed. Full Flutter `934/934`, Flutter analyze, Rust workspace, repository
    gates, and clean detached-checkout review passed. The clean Linux x64
    bundle from `b80dc8d` (tree-identical to the merge) contained a 7,810,680-
    byte binary with SHA-256
    `5c662b67da2fabfe0201d8126f4fa18950fa4731294662572f07eb7ca8aad393`
    and the canonical unit with SHA-256
    `61d582064ee8be1f1ef53b19f6b4fc28f2cf415d24173b69d53fb6a129fa8583`.
    The exact unit appended evidence hash
    `86e375726c05b2230c298b5b73e7b4e4c3d4c5577a3de8428f72f93040af4807`
    at cycle `1/288`, had zero restarts, and exposed the exact 128 MiB,
    no-swap, 16-task, DynamicUser, address-family, and listener-denial
    properties. Final cleanup left no bundle, unit, credential, state, lock,
    source, or enablement path. Website HTTP status, Amnezia container
    identities/start times, restart counts, and listeners remained unchanged.
    Two earlier attempts failed closed and drove removal of the implicit
    `file` package dependency plus correction of EXIT-trap rollback scope.
    Status: complete (2026-08-18). No following pass is selected automatically.

- `1.x Documentation Control Consolidation`
  - Lane: process/documentation only; no runtime, deployment, release, or
    product authority change.
  - Invariant: current selection has one concise owner in
    `development-control.md`; detailed pass evidence and debt remain here.
  - Sole owner: the existing development board owns current navigation and this
    roadmap owns chronological evidence. No document, registry, schema, DTO,
    service, or gate is added.
  - Removed or sealed: the stale Pass E selection, the duplicate chronological
    pass narrative, and repeated Pass M SHA/smoke/CI evidence are removed from
    the current-status board. Historical entries cannot select future work.
  - Exit evidence: a smaller documentation diff, documentation integrity and
    repository review gates, clean detached-checkout validation, protected PR,
    and green post-merge CI. No following product pass is selected
    automatically.
  - Status: complete on `main` at `79bab2e` (2026-08-18) through protected PR
    `#129`; required run `32083764573` and post-merge run `32083870579` passed.
    The current-status document fell from 597 to 146 lines with 38 additions
    against 473 removals across the pass. No owner, gate, runtime path, VPS
    state, tag, or Release was added. No following pass is selected.

- `1.x Trading Remote Runner Pass N — Encrypted Identity Restart Continuity`
  - Lane: bounded 1.x host-lifecycle evidence; no persistent deployment,
    account access, effect, release, or 2.0 work.
  - Invariant: the exact unit appends sequence `1`, crosses one explicit
    stop/start boundary with the same encrypted runner-only credential and
    retained state, then appends sequence `2` without an implicit restart.
  - Sole owner: the existing shadow store owns identity and evidence; the
    existing artifact script only orchestrates the exact-unit smoke. No owner,
    service, DTO, credential store, journal, or effect path is added.
  - Removed or sealed: host restart continuity can no longer be inferred from
    local store tests or one process start. Sequence reset, missing identity,
    repeated evidence, implicit restart, and cleanup residue fail closed.
    Rotation/replacement, persistent installation, boot enablement, external
    anchoring, account reads, leases, effects, tags, and Releases remain sealed.
  - Exit evidence: focused probe/store tests, artifact and parity negative
    mutations, full local and clean-checkout gates, one exact-bundle VPS
    stop/start smoke with website and Amnezia continuity, protected PR, and
    green post-merge CI.
  - Status: complete on `main` at `96f2628` (2026-08-18) through protected PR
    `#131`; required run `32085039781` and post-merge run `32085133479` passed.
    The exact post-merge Linux x64 bundle used binary SHA-256
    `bbe5bfd53d69eaab8886d6e8b7869fd1ea3fb92404caa92a9219e191fd5bb2d3`
    and canonical unit SHA-256
    `61d582064ee8be1f1ef53b19f6b4fc28f2cf415d24173b69d53fb6a129fa8583`.
    On the audited VPS, one encrypted runner-only credential produced sequence
    `1` with evidence hash
    `2f7db45e1baf233aee9236b233fa45a45a63c68e381060e2caa431632c140c0b`,
    survived an explicit stop/start with retained identity state, and produced
    sequence `2` with evidence hash
    `1af1f27ea9fc0a7bf5de262f2de4eeee7a8d0c8c52898bfb22532b1a64344bea`.
    `NRestarts` remained zero and the exact 128 MiB/no-swap/16-task boundaries
    remained active. Cleanup removed every bundle, unit, credential, state,
    lock, and enablement path; website HTTP status, Amnezia container identity,
    start time/restart count, and listeners were unchanged. Full Flutter
    `934/934`, analyze, Rust workspace, review gates, clean checkout, and focused
    `34/34` passed. No following pass is selected.

- `1.x Trading Remote Runner Pass O — Observable Runner Identity Binding`
  - Lane: bounded 1.x public-shadow observability; no persistence, account,
    effect, release, or 2.0 work.
  - Invariant: every successful append exposes the exact non-secret 64-hex
    `runner_key_id` already signed into canonical evidence, and the exact-unit
    stop/start smoke accepts only the same fingerprint from both processes.
  - Sole owner: canonical shadow evidence owns the key id; the existing probe
    projects it and the existing artifact smoke verifies continuity. No DTO,
    service, registry, credential owner, journal, or effect path is added.
  - Removed or sealed: operators no longer infer identity from an opaque
    evidence hash. Missing or changed fingerprint fails closed. The fingerprint
    cannot authorize persistence, rotation, anchoring, account access, leases,
    or effects.
  - Exit evidence: focused probe/store tests, independent probe-output and
    smoke-comparison mutations, full local and clean-checkout gates, exact
    merge-SHA VPS continuity with infrastructure comparison, protected PR, and
    green post-merge CI.
  - Status: complete at merge commit `337a109` through PR `#133`. Required PR
    run `32089923541` passed; post-merge run `32090004740` passed after one
    infrastructure-only rerun when its first GitHub runner stalled installing
    shell dependencies.
  - Exact merge-SHA VPS evidence: sequence `1` and `2` exposed the same
    `runner_key_id`
    `3baa5401aa7dfcfdbe1d61aa3bc55e1331cfbbc7ca729bfeb99f1cb89d405255`;
    evidence hashes were
    `bcf576c1249b3ef987aedc4dddda42778e9ad7247647f76f5f8b27be4c79f630`
    and
    `8f1f5fa3409296c201d899c119c765b3a05127e11bf36f204a7c337dcf118470`.
    The binary SHA-256 was
    `d9c969355bc6b2131e3177f07e16eb93d2500f2b3576e8b2a8aef731abeacda5`;
    the unit SHA-256 remained
    `61d582064ee8be1f1ef53b19f6b4fc28f2cf415d24173b69d53fb6a129fa8583`.
    The exact unit retained `NRestarts=0`, `MemoryMax=128 MiB`, no swap, and
    `TasksMax=16`; cleanup removed every canonical runner path without
    enablement. The site remained HTTP `200`, all four Amnezia containers
    remained active, and the listener-set hash stayed unchanged at
    `d962a1ffaa457f23708c3ec345a4479063e8de4a3a8e2bd000103adf287dae0e`.
    Full Flutter `934/934`, analyze, Rust workspace, review gates, clean
    checkout, and focused `34/34` passed. No following pass is selected.

- `1.x Trading Remote Runner Pass P — Persistent Disabled Install and Exact Uninstall`
  - Lane: bounded 1.x host lifecycle; no boot enablement, account, effect,
    release, or 2.0 work.
  - Invariant: the existing artifact owner atomically installs one exact
    public-shadow bundle and encrypted runner identity, leaves it disabled and
    inactive, and removes only exact owned paths with the bundle removed last
    so interrupted cleanup remains retryable.
  - Sole owner: `public_shadow_runner_artifact.sh` remains the only package,
    install, smoke, and uninstall owner. No installer, service, DTO, registry,
    credential owner, journal, listener, or effect route is added.
  - Removed or sealed: persistent host state no longer requires copying the
    ephemeral smoke by hand. Collision, symlink substitution, drift, foreign
    state, accidental enablement, concurrent lifecycle work, and partial
    uninstall fail closed. Rotation/replacement, boot enablement, external
    anchoring, account reads, leases, and effects remain sealed.
  - Exit evidence: artifact self-tests and independent install/uninstall
    mutations, full local and clean-checkout gates, exact merge-SHA VPS
    install/start/stop/uninstall with stable `runner_key_id` and unchanged
    website/Amnezia/listeners, protected PR, and green post-merge CI.
  - Status: complete on `main` at `7d93eb6` (2026-08-18) through protected PR
    `#135`; required run `32106482943` and post-merge run `32106609859`
    passed.
  - Exact merge-SHA VPS evidence: installation ended disabled and inactive;
    explicit processes appended sequences `1` and `2` with stable
    `runner_key_id`
    `769281de3913cb91cad60d76b30f0e2a32e85d2b39a1cdd8bf14f80b9e6ca0ce`
    and evidence hashes
    `b1c0a0397d297e3a5336b10fb91fd59356d9c7824fabcafc358e8b47cfc0b90e`
    and
    `e6811c223495ed4655de255425c824056f761087486da2c5419f923830808c9b`.
    The binary SHA-256 was
    `d9c969355bc6b2131e3177f07e16eb93d2500f2b3576e8b2a8aef731abeacda5`;
    the unit SHA-256 was
    `61d582064ee8be1f1ef53b19f6b4fc28f2cf415d24173b69d53fb6a129fa8583`.
    Exact uninstall removed every runner bundle, link, credential, and state
    path. The site remained HTTP `200`, all four Amnezia containers remained
    active, and the listener-set hash stayed unchanged at
    `d962a1ffaa457f23708c3ec345a4479063e8de4a3a8e2bd000103adf287dae0e`.
    Full Flutter `934/934`, analyze, Rust workspace, review gates, clean
    checkout, artifact self-tests, and independent lifecycle mutations passed.
    No following pass is selected.

- `1.x Trading Remote Runner Pass Q — Explicit Identity-Bound Activation`
  - Lane: maintained 1.x host lifecycle; public-market shadow observation only.
  - Invariant:
    - an installed runner may become boot-enabled only after its committed
      `runner_key_id` matches both the operator's expected fingerprint and new
      authenticated evidence from the exact disabled unit.
  - Sole owner:
    - `tools/trading/public_shadow_runner_artifact.sh` remains the only install,
      initialization, activation, deactivation, and uninstall owner.
  - Threat model:
    - blind first-boot identity creation, wrong-key activation, bundle or unit
      drift, foreign path adoption, pre-existing enablement, concurrent host
      operations, stale journal evidence, failed-start enablement residue, and
      deactivation of an ambiguous runner must fail closed.
    - remediation after implementation review forbids `systemctl disable`
      because it may remove the canonical `systemctl link`; rollback and
      deactivation remove only the already verified exact boot-target link.
  - Exit evidence:
    - mutation/self-tests and the trading parity gate;
    - full repository gates and clean detached-checkout verification;
    - required PR and post-merge GitHub Actions;
    - exact merge-SHA VPS install, disabled identity initialization, wrong-key
      rejection, matching-key activation, authenticated evidence, exact
      deactivation, uninstall, and unchanged site/Amnezia evidence without a
      host reboot.
  - Removed or sealed:
    - boot enablement before identity proof and silent adoption of a different
      runner identity are unreachable through the canonical host lifecycle.
  - Still blocked:
    - external anchoring, credential rotation/replacement, Capsule or exchange
      credentials, account reads, leases, mandates, trading effects,
      reconciliation, listeners, tags, Releases, and 2.0 implementation.
  - Status: implementation candidate; merge-SHA host evidence pending.

- `1.x Moltbook Capsule Public Change Feed`
  - Scope: let one Capsule retain a bounded queue of explicitly confirmed
    public development facts and feed the oldest pending item into the existing
    Gemini bulletin proposal and ambassador WASM draft path.
  - Invariants: versioned semantic commitment, exact replay idempotency,
    conflicting source-id rejection, Capsule isolation, bounded retention,
    oldest-first selection, and drafted state only after durable canonical WASM
    draft evidence.
  - Sealed paths: Gemini cannot read Ledger, repository, Capsule history, or
    credentials; the feed cannot publish; approval, provider effects,
    challenges, receipts, and reconciliation retain their existing owners.
  - Not included: Git/CI producer, background host, automatic publication,
    provider authority expansion, plugin ABI changes, or release work.
  - Status: complete on `main` at `caed6d4` (2026-08-13); protected PR `#50`
    and post-merge repository gates `31654314173` passed. No following pass is
    selected.

- `1.x Moltbook Bundled Public Change Ingestion`
  - Scope: import one bounded, reviewed build-time product-change manifest into
    the existing Capsule-scoped public change feed when the Moltbook workspace
    opens, so ordinary builds can present confirmed development facts without
    manual re-entry.
  - Invariants: strict version and producer binding, bounded raw input and
    entry count, atomic validation before persistence, exact replay and restart
    idempotency, source-id conflict rejection, Capsule-switch protection, and
    existing allowed-topic enforcement.
  - Sealed paths: no Git, Ledger, Core, Analyst, credential, or private Capsule
    access; no second feed, draft, effect, or publication path; no automatic
    approval or publication.
  - Exit evidence: actual packaged asset vector, malformed/oversized/unknown/
    duplicate/conflicting negative vectors, Capsule isolation and restart
    replay tests, full local and clean-checkout gates, protected PR/post-merge
    CI, and packaged Hands smoke through proposal and WASM draft without an
    external effect.
  - Status: complete (2026-08-15). Protected PR `#71` merged ingestion at
    `4699624`; packaged smoke exposed a stale manual bulletin id. Protected PR
    `#72` merged the bounded binding remediation at `c3949bf`, and post-merge
    repository run `31875750814` passed. Fresh packaged macOS Hands smoke from
    `c3949bf`, build `1.0.3+100030033`, artifact SHA-256
    `2653520a8618b0474aa71f01398563639f577c7c0cc7407c12c65ee0bf628cee`,
    proved the exact queued source/category reached the installed WASM package
    and persisted draft hash
    `608238ba90b6b7e191163d79c2180f46dbd66730d2f3f861ea1fa92d86989c2f`.
    No publication or external effect occurred. No owner, DTO, credential,
    plugin ABI, publication, or effect path was added. Destination routing is a
    separate later product decision; Remote Runner/VPS and v2 remain frozen,
    and no next pass is selected automatically.

- `1.x Moltbook Person-First Runtime Community Bootstrap`
  - Lane: bounded 1.x Moltbook product completion. One fixed permanent
    `m/person-first-runtime` community effect uses the existing publication
    service, external-effect journal, and provider adapter.
  - Invariant: the active Capsule and exact Moltbook account authorize one
    immutable name/display-name/description commitment. Replay, double click,
    restart, timeout, and delayed provider visibility cannot create a second
    semantic effect or permit blind recreation.
  - Failure boundary: wrong creator account id or changed descriptor is a
    terminal conflict; temporary absence is unresolved observation evidence,
    not proof that a prior POST failed.
  - Sealed paths: no generic community manager, AI-selected destination,
    automatic creation/publication, post migration, new DTO/service/state
    owner, second effect route, plugin ABI, Remote Runner/VPS, or v2 work.
  - Exit evidence: exact payload and receipt binding, wrong-owner/descriptor
    negative vectors, Capsule isolation, replay/restart and timeout recovery
    without duplicate POST, full local and clean-checkout gates, protected PR
    and post-merge CI, then packaged macOS Hands creation with public ownership
    observation and no automatic post.
  - Packaged-smoke remediation: the first Hands attempt from `acc141e`, build
    `1.0.3+100030034`, reached exact approval but received a confirmed Moltbook
    authorization rejection. No receipt or community was observed. A bounded
    reauthorization may requeue only the same immutable operation after
    `credential_rejected` or `permission_rejected`; changed approval evidence,
    ambiguous outcomes, missing receipts, not-found observation, and conflicts
    remain sealed. HTTP `401` and `403` retain distinct diagnostics.
  - Status: complete on `main` at `dc15de9` (2026-08-15). Protected PR `#75`
    and post-merge repository-gates run `31881796780` passed. Packaged macOS
    Hands smoke used Release build `1.0.3+100030035`; artifact SHA-256 is
    `d5236f5c5f893b724882efabe9f4b87385f1d668587c5f83886f92e8c1d670fb`.
    The original operation `moltbook-submolt-91957960...4cb9d` resumed after a
    fresh exact acknowledgement and succeeded on attempt two with receipt
    `7f40d1ea-e89c-4b5a-a81d-0fa0608da56f`. Independent public observation
    matched the exact descriptor and creator `hivra_ambassador`. Cold restart
    restored one succeeded community operation, left post/comment operation
    counts unchanged at `5/5`, showed verified ownership, and projected
    `m/person-first-runtime` as the local-draft destination. No automatic post,
    duplicate community, second effect route, tag, or Release was created.
    Test filesystem isolation issue `#76` remains a separate P2; no following
    product pass is selected automatically.

- `1.x Capsule AI single-prompt unlock remediation`
  - Finding: packaged macOS Release smoke from `0440e92` proved the complete
    Capsule Change Feed -> Gemini proposal -> WASM draft path without an
    external effect, but one explicit AI unlock produced two password prompts.
  - Root cause: `AiDoctorCredentialStore` read a non-secret preferred-provider
    id and the selected credential from separate Keychain records.
  - Boundary: retain the same credential and runtime owners; store the
    provider id as bounded local configuration, keep keys and protected local
    endpoints in Secure Storage, and migrate only the exact legacy provider
    record without enumerating unrelated Keychain entries. No provider, DTO,
    Core, effect, or publication path is added.
  - Exit evidence: bounded legacy migration, one protected read for every
    post-migration cold unlock, malformed preference failure, full gates,
    protected CI, and a fresh packaged macOS restart smoke showing one password
    prompt and successful inference.
  - Status: complete on `main` at `b6c2e01` (2026-08-13); protected PR `#52`
    and post-merge repository gates `31659447915` passed. Packaged macOS
    Release SHA-256 `24cfabd4f81cb2d4c40e835d5a4b500eeb24a691ccc7c174466ca3992bda4ad7`
    migrated the legacy preference; a cold restart then unlocked Gemini with
    zero password prompts and changed `Unlock AI` to `Lock AI`. No following
    pass is selected.

- `1.x Android Invitations explicit-refresh projection remediation`
  - Finding: on Android, pull-to-refresh updated the Invitations list while the
    top-bar refresh could receive the same deliveries without repainting the
    retained screen when the Ledger version did not change.
  - Root cause: the top bar invoked the canonical passive-receive coordinator
    and refreshed the shell projection, but `InvitationsScreen` only reloaded
    for Capsule or Ledger-version changes.
  - Boundary: keep the existing receive and Capsule-scoped invitation owners;
    issue a bounded projection revision after the existing manual receive,
    including its error result, so locally accepted evidence remains visible.
    No transport, inbox, DTO, Core, Ledger, or second projection path is added.
  - Exit evidence: focused positive and no-op regression vectors, full local
    gates, protected PR and post-merge gates, then fresh Android packaged smoke
    proving the top-bar button updates the same list as pull-to-refresh.
  - Packaged Hands finding: source `1ee7ef4` completed the canonical manual
    receive and refreshed the projection, but only error results produced a
    top-bar notice. Pull-to-refresh showed every non-empty result. Follow-up
    remediation must reuse the existing invitation feedback helper for both
    controls and add a positive success-notice regression.
  - Follow-up result: both controls now use the existing invitation feedback
    helper, and widget evidence covers the positive success notice. Protected
    PRs `#54` and `#56` merged at `1ee7ef4` and `96433fa`; PR and post-merge
    repository gates passed, including final run `31664542748`.
  - Packaged Hands evidence: fresh Android Release source `96433fa`, local
    build `1.0.3+100030023`, SHA-256
    `0886443a6eee643025395f8b0310c8e0a2f1df3ae06a1c5fcc657e413483c151`,
    produced canonical `reason=manual` receive and the user-visible
    `No new invitation deliveries` result from one top-bar tap without a
    swipe.
  - Status: complete (2026-08-13). No following pass, tag, or Release is
    selected.

## Planned Product Tracks

- `1.x Chat Durable Receive Handoff`
  - Finding: authenticated chat ingress returned `consumed` after writing only
    to a process-memory native queue, then the FFI receive call destructively
    removed that queue before Flutter consensus filtering and projection.
    Restart or a crash in either window could permanently hide an acknowledged
    message. The stable adapter event id was also omitted from the FFI payload.
  - Invariant: one authenticated event is either atomically retained by the
    existing encrypted Capsule-scoped Chat owner or returns `retry`; restart,
    repeated receive, consensus defer, and projection failure cannot create a
    loss, duplicate, cross-Capsule record, or alternate receive route.
  - Boundary: replace the volatile handoff inside the existing native Chat
    owner, retain exact event identity through the existing deferred store, and
    keep Flutter as a projection consumer. Core, Ledger, transport wire format,
    attachments, notifications, unread UI, and a second inbox owner remain
    sealed.
  - Exit evidence: encrypted-at-rest restart/reopen, replay dedupe, corruption
    fail-closed, quarantine recovery through the canonical router, bounded
    retention/tombstones, exact deferred event identity, Capsule isolation and
    deletion, full automated gates, protected PR, and packaged platform smoke.
  - Status: complete on `main` at `c9caa7e` (2026-08-13). PR `#58`, its
    required check, and post-merge run `31667408208` passed. Smoke-only Release
    artifacts from the same source used build `100030024`; macOS SHA-256 was
    `0e29224a7c0c78948c1bb588e1ff74497d39571dd7e014da1e6b24a37abdd295`
    and Android SHA-256 was
    `f48f438721ed909597a8b6ffc7f038fc0b512456c10079232756a9ce3969a72b`.
    Android accepted `M2A-DURABLE-C9CAA7E-02`, restored it after process
    `20784 -> 23041`, and displayed it once. macOS restored the Android `sync`
    message after process `70422 -> 71616` and displayed it once. An initially
    incomplete Android-side pair attestation was repaired through the existing
    canonical Chat attestation exchange; no alternate route or code change was
    required. No tag or Release was created.

- `1.x Chat Durable Handoff Capacity Remediation`
  - Finding: ordinary Chat messages committed to the existing durable Flutter
    timeline without adding their adapter event id to the later handoff ACK;
    replay therefore retained the same native record indefinitely. Separately,
    acknowledged and evicted ids accumulated until tombstone capacity stopped
    the handoff permanently.
  - Invariant: one ordinary message ACK occurs only after successful durable
    timeline merge. Handoff records and replay tombstones are bounded FIFO
    windows; new state replaces the oldest retained state without a second
    inbox or unbounded growth. Timeline persistence failure never ACKs.
  - Sole owners: the existing native Chat handoff owns pre-projection records
    and bounded replay tombstones; `CapsuleDeliveryInboxStore` owns the durable
    Capsule-scoped timeline.
  - Removed or sealed: missing normal-message ACK and terminal tombstone
    exhaustion. Transport, Core, Ledger, FFI shape, DTO, inbox, notification,
    and Chat effect routes remain unchanged.
  - Exit evidence: normal-message durable ACK, persistence-failure no-ACK,
    replay dedupe, record FIFO eviction, tombstone FIFO overwrite, corruption
    fail-closed, full Flutter/Rust/repository gates, clean checkout, protected
    PR, and green post-merge CI.
  - Status: complete on `main` at `340c8a6` (2026-08-17). Protected PR `#103`,
    required run `32024383365`, and post-merge run `32024462405` passed.
    Flutter `911/911`, analyze, Rust workspace, full review gates, clean
    checkout, Rust Chat `6/6`, and Flutter Chat `32/32` passed. Trading outcome
    truth and shadow identity initialization remain separate findings; no
    release or following product pass is selected automatically.

- `1.x Trading Execution Outcome Truth Remediation`
  - Finding: the canonical execution owner returned `executed` even when the
    nested BingX provider result reported failure, and the trading cycle trusted
    that wrapper status without independently requiring provider success.
  - Invariant: `executed` requires explicit provider success. Rejection,
    exhausted retry, timeout, missing success evidence, and contradictory
    wrapper state remain non-success and cannot confirm or recreate an effect.
  - Sole owners: `BingxFuturesExchangeExecutionUseCaseService` owns provider
    outcome truth; `BingxFuturesTradingCycleUseCaseService` consumes it for the
    one canonical cycle result.
  - Removed or sealed: false executed projection after provider rejection and
    success inference from enum state alone. No DTO, provider, queue, effect
    route, scheduler, Remote Runner/VPS, Core, Ledger, tag, or Release is added.
  - Exit evidence: rejected provider and contradictory-wrapper regressions,
    executable mutation-gate, full Flutter/Rust/repository gates, clean
    checkout, protected PR, and green post-merge CI.
  - Status: complete on `main` at `505c4ca` (2026-08-17). Protected PR `#105`,
    required run `32025516002`, and post-merge run `32025615776` passed.
    Flutter `913/913`, analyze, Rust workspace, full review gates, clean
    checkout, and `32/32` focused tests passed. Crash-atomic shadow identity
    initialization remains a separate finding; no following pass, tag, or
    Release is selected automatically.

- `1.x Trading Shadow Identity Atomic Commit Remediation`
  - Finding: first-run stream identity created the committed file before
    writing and flushing its bytes, so termination could leave empty or partial
    committed JSON and permanently block the runner-only shadow stream.
  - Invariant: one fixed pending identity is flushed before atomic rename, and
    no evidence is produced before identity commit. Recovery can complete exact
    same-runner pending state or replace malformed uncommitted bytes only while
    the stream is empty.
  - Sole owner: `BingxFuturesShadowStreamStore` retains runner identity and
    shadow evidence; the replay harness continues to own evidence semantics.
  - Removed or sealed: create-final-then-write initialization, rebinding over
    retained state, foreign-key adoption, committed corruption repair, and
    ambiguous identity cleanup. No new DTO, owner, service, authority, effect,
    scheduler, deployment, tag, or Release is added.
  - Exit evidence: valid and malformed pending recovery, foreign-key pending,
    committed corruption, committed-plus-pending ambiguity, unbound-state
    rejection, mutation-gate, full Flutter/Rust/repository gates, clean
    checkout, protected PR, and green post-merge CI.
  - Status: complete on `main` at `2af3de5` (2026-08-17). Protected PR `#107`,
    required run `32027671293`, and post-merge run `32027767936` passed.
    Flutter `919/919`, analyze, Rust workspace, full review gates, clean
    checkout, and `21/21` focused tests passed. No following pass, deployment,
    tag, or Release is selected automatically.

- `1.x Chat Execution Control Durable Lifecycle Remediation`
  - Finding: authenticated execution commands and receipts were acknowledged
    out of the native Chat handoff after process-memory projection only. The
    command replay store was process-local, and a failed receipt send lost the
    exact deterministic receipt across restart.
  - Invariant: command decisions and incoming receipts commit durably before
    handoff acknowledgement. Failed receipt delivery retains and retries the
    exact canonical bytes without policy re-evaluation. Receipt sender, target,
    local peer, command identity, canonical hash, and Capsule scope remain
    bound and fail closed.
  - Sole owners: the native Chat handoff remains the transport ingress owner;
    the existing `CapsuleDeliveryInboxStore` remains the sole bounded 1.x
    delivery-capability retention owner. The exchange-effect owner, Core,
    Ledger, plugin ABI, and V2 topology remain unchanged.
  - Required evidence: persistence-failure no-ACK, command decision restart,
    exact receipt retry after restart, incoming receipt restart, replay dedupe,
    conflicting stable-id sealing, binding/hash mutation rejection, bounded
    retention, legacy Chat timeline compatibility, full automated gates, clean
    checkout, protected PR, and green post-merge CI.
  - Status: complete on `main` at `bb4b52a` (2026-08-17). Protected PR `#109`,
    required run `32032243278`, and post-merge run `32032343388` passed.
    Flutter `920/920`, analyze, Rust workspace, full review gates, clean
    detached-checkout gates, and focused Chat delivery `33/33` passed. No
    deployment, tag, Release, or following product pass is selected.

- `1.x Flutter Test Runtime Isolation Remediation`
  - Finding: Flutter tests constructing production-default filesystem owners
    could resolve the real user home and write fixture Capsule state or logs
    into an active packaged Hivra runtime.
  - Invariant: every Flutter test suite uses one retained temporary home before
    any default filesystem owner resolves a path. Explicit per-test overrides
    remain authoritative, while the real runtime and user-visible roots remain
    untouched.
  - Sole owner: `UserVisibleDataDirectoryService` continues to resolve runtime
    and user-visible roots. The suite bootstrap supplies test context without
    creating a production storage path or second owner.
  - Removed or sealed: default test access to real Capsule files, logs,
    migration inputs, and cleanup targets. Production path resolution and all
    runtime DTO, service, Core, Ledger, plugin, and effect routes are unchanged.
  - Exit evidence: default `CapsuleFileStore` and `UiEventLogService` writes
    remain beneath the suite sandbox, a unique real Capsule path remains
    absent, bootstrap/owner/lifetime/probe mutations fail the architecture
    gate, and full Flutter/Rust/repository and clean-checkout gates pass.
  - Status: complete on `main` at `24eb042` (2026-08-17). Protected PR `#111`,
    required run `32036080325`, and post-merge run `32036163520` passed.
    Flutter `921/921`, analyze, Rust workspace, full review gates, and clean
    detached-checkout validation passed. Issue `#76` is closed. No following
    product pass, V2 pass, deployment, tag, or Release is selected
    automatically.

- `1.x Capsule-scoped Chat Unread Indicator`
  - Goal: surface accepted unread Chat messages on the cross-screen shell while
    preserving the existing durable native handoff and Flutter Chat projection
    as the only inbox path.
  - Audit boundary: identify the sole read-state owner, define a stable
    Capsule-scoped read cursor over existing message identity, and prove unread
    count behavior across passive receive, Chat open, refresh, restart, Capsule
    switch, retention eviction, and deletion.
  - Sealed paths: no second inbox or message DTO family, no Core/Ledger unread
    fact, no transport change, no OS push/background service, no attachment
    lifecycle, and no badge derived from network success alone.
  - Required negative vectors: replay cannot increment twice; opening another
    Capsule cannot clear or expose the active Capsule count; refresh failure
    cannot hide retained unread state; eviction/deletion cannot resurrect a
    count; a message becomes read only through the canonical Chat workspace.
  - Implementation: the existing `CapsuleDeliveryInboxStore` owns a bounded
    persisted set of read message ids under the Capsule directory. Unread is
    derived only from retained projected ids minus that read set; transport
    result counts never increment it. The existing Plugins navigation icon
    projects the active Capsule count, and only the canonical Chat workspace
    marks messages it actually displayed as read, including when the following
    network refresh fails.
  - Entropy reduction: one read owner and one projection path replace the
    ambiguity between replayed retained history and newly unread messages;
    added owner count is zero and added execution-path count is zero.
  - Verification: Flutter `833/833`, Rust workspace, analyze, repository-wide
    review, detached clean-checkout, protected PR `#60`, and post-merge run
    `31673505950` passed. Fresh smoke-only Release artifacts from source
    `d50e70f`, build `1.0.3+100030025`, had macOS SHA-256
    `fdc1d51632ccb7ef18b46ab80969ad542bc8dad2fd23876e387fc21585df71cb`
    and Android SHA-256
    `bcbcc2f3897092e8986b877b3015931c2177da5cd0ac486161711facf4e4164a`.
    macOS projected badge `3` and Android badge `2`; each cleared only after
    the canonical Chat workspace displayed the retained messages, stayed clear
    through periodic replay, and stayed clear after a cold process restart.
  - Status: complete (2026-08-13). No following pass, tag, or Release is
    selected.

- `1.x Capsule Chat Conversation Timeline`
  - Finding: the canonical Chat workspace projected only a bounded incoming
    process-memory inbox. Successful outgoing envelopes were not projected,
    and acknowledged incoming content had no durable conversation view after
    restart.
  - Invariant: one canonical envelope hash maps to at most one bounded
    Capsule/peer-scoped timeline record. Incoming content is persisted before
    handoff acknowledgement. Outgoing content is persisted before the effect
    and records `pending`, `transportAccepted`, `ambiguous`, or `failed`
    without treating adapter acceptance as peer delivery proof.
  - Owner and boundary: the existing `CapsuleDeliveryInboxStore` remains the
    sole Chat projection owner and is physically separated from the transport
    service file without changing ownership. Timeline content is suite-tagged,
    Capsule-bound, and encrypted at rest from the existing Capsule seed owner.
    Core, Ledger, transport wire, FFI, WASM ABI, attachments, background
    delivery, and a second inbox/history service remain sealed.
  - Negative evidence: replay dedupe, peer and Capsule isolation, bounded
    retention, wrong key, wrong scope, malformed storage, unavailable key,
    timeout ambiguity, unread exclusion for outgoing records, and persistence
    failure before acknowledgement.
  - Status: implementation merged at `ae1af30` through protected PR `#62`; the
    post-merge repository gate `31706040424` passed. Fresh artifacts from
    post-remediation source `89c3b36` proved bidirectional macOS/Android
    delivery, one transport-accepted envelope per send, passive macOS receive,
    unread projection, and persistence of the `A27` conversation after a real
    macOS process restart. Android cold-restart persistence remains the only
    unclosed packaged evidence item. No tag or Release is selected.

- `1.x Chat Conversation Workspace UX`
  - Finding: the sole Chat workspace still exposed plugin-host, transport,
    runtime ABI, and pair-consensus controls as the primary user experience,
    despite the underlying delivery and timeline lifecycle already being
    canonical and cross-platform proven.
  - Invariant and owner: `WasmPluginsScreen` remains the existing workspace
    orchestrator, while `CapsuleDeliveryInboxStore` and the existing Chat
    delivery/attestation services remain the sole state and lifecycle owners.
    Presentation may rename and arrange their states but cannot reinterpret
    transport acceptance as peer delivery.
  - Entropy reduction: replace one 600-line technical panel with one
    independently testable presentation widget; remove the visible manual
    inbox action and ordinary consensus/runtime jargon; keep a receive retry
    only when the existing receive path reports failure. Added state-owner and
    execution-path counts remain zero.
  - Sealed paths: no second inbox, DTO, service, transport route, Core/Ledger
    fact, FFI/WASM contract, attachment lifecycle, OS notification service, or
    background delivery path.
  - Required evidence: ordinary UI terminology, trusted-contact selection,
    chronological incoming/outgoing bubbles, `Accepted by transport` rather
    than delivered, draft preservation during conversation securing, retained
    cached messages during receive failure, collapsed technical details, full
    automated gates, protected PR/post-merge CI, and packaged Hands smoke.
  - Packaged-smoke finding: source `451648f` accepted and durably retained the
    `CUX28 mac to android` message through the canonical passive receive owner,
    but an already-open Android workspace kept its pre-receive timeline. The
    separate dialog route rebuilt only after its own actions, so parent-shell
    unread projection did not refresh the visible conversation.
  - Remediation boundary: the open conversation may periodically reproject the
    existing Capsule-scoped durable inbox. This is presentation-only and must
    not trigger transport, add a receive listener, or create another inbox,
    DTO, service, notification, or background-delivery path. A negative test
    must prove cache projection updates the open workspace without invoking the
    receive retry.
  - Replacement-smoke finding: source `c9f8900` and build `100030029` proved
    one `CUX29` send, one passive Android acceptance, and durable timeline
    growth from 14 to 15 while the dialog remained open. The cache projection
    worked, but the non-reversed list retained its old viewport and left the
    newest bubble below the visible edge.
  - Viewport remediation: use the existing chronological message list through
    a reversed visual list so the normal Chat position shows the newest item.
    Overflow vectors must prove a newly projected message is visible without a
    manual receive or animation-owned state path.
  - Separate finding: Android contact selection applied only on the second
    attempt during the same smoke. It remains a later focused UX remediation;
    no contact-selection behavior is changed by the viewport fix.
  - Closure evidence: protected PR `#67`, merge source `aafbf52`, green
    post-merge gates, and same-source packaged macOS/Android build
    `1.0.3+100030030`. One `CUX31 open live` send was accepted once, entered the
    already-open Android workspace through periodic passive receive, increased
    the retained timeline from 16 to 17, and remained visible at the normal
    Chat edge without refresh, scrolling, reopen, or restart. macOS artifact
    SHA-256 is
    `712cb1f5a55802f197a74010a06520cbcef5c976dd7d28589c09cad4d0d52fc5`;
    Android artifact SHA-256 is
    `90a8bf06510f93d22f6b6c47e093d4cd4908c5e7dbb09211a00df930a755e013`.
  - Status: complete (2026-08-14). No tag or Release is selected.

- `1.x Chat Contact Selection Projection remediation`
  - Finding: packaged Android Hands smoke from build `1.0.3+100030030`
    reproduced a trusted-contact choice that appeared only after a later tap
    rebuilt the open workspace.
  - Owner and invariant: the existing Chat peer `TextEditingController` remains
    the sole selected-peer owner. One valid controller update must immediately
    project exactly one selected conversation.
  - Remediation boundary: the workspace may listen to its existing controller.
    No second selected-peer state, picker, DTO, service, transport, inbox, Core,
    Ledger, or Chat effect path is authorized.
  - Required evidence: a negative-before/positive-after widget vector for one
    controller update, full automated gates, protected PR/post-merge CI, and
    replacement packaged Android Hands smoke proving one-tap selection.
  - Closure evidence: source `c56213f`, protected PR `#69`, green post-merge
    gates, `849/849` Flutter tests, and packaged Android Hands smoke from build
    `1.0.3+100030031`. One tap selected `h1un5...`, immediately replaced the
    empty state with the conversation header, and enabled the composer. The
    artifact SHA-256 is
    `1990e92157cc623d0efb582533ee2acbf2f29a25a0eeae71c8dd5642f8dfa544`.
  - Status: complete (2026-08-14). No tag or Release is selected.

- `1.x Relationship Root-Signed Break Projection remediation`
  - Finding: a real remote Seed break was accepted by canonical ingress and
    appended to the active Capsule Ledger, but the current-view projection
    compared the signer only with the established peer transport key. The
    root-signed fact therefore remained invisible after manual refresh.
  - Invariant: a remote break may become `pending_remote_break` only when its
    signer matches the exact established peer transport key or the exact
    established peer root key. An unrelated root cannot break or suspend the
    relationship. Local confirmation remains the only path to final removal.
  - Owner and sealed paths: the existing Core relationship current view remains
    the sole projection owner, and the existing Relationships full refresh
    remains the sole visible refresh on that tab. No event, DTO, transport,
    Ledger owner, confirmation use case, or parallel refresh path is added.
  - Evidence: Core positive root-binding and negative unbound-root vectors,
    ingress-to-exported-Ledger-to-FFI projection regression, one visible
    Relationships refresh action, protected PR `#63`, post-merge run
    `31710031485`, and fresh packaged macOS/Android artifacts from `89c3b36`.
    Real macOS Hands smoke projected the remote break as pending, preserved the
    local-confirmation boundary, and then projected the confirmed break without
    adding a second relationship or refresh path.
  - Status: complete (2026-08-13). The related Chat Android cold-restart
    evidence remains separate and pending. No tag or Release is selected.

- `13.1 AI-Assisted Trading Analysis`
  - Goal:
    - connect the existing Capsule Analyst/Hivra Engineer AI tooling to the
      Trading Drone as an advisory analysis layer.
  - Boundary:
    - all inference follows
      `docs/architecture/ai-proposal-boundary.md`; AI output remains an
      untrusted proposal/explanation with no trading capability.
    - AI reads trading-drone snapshots, decision envelopes, risk envelopes,
      order-tracking state, and reason codes.
    - AI explains signals, missing inputs, risk blocks, trend conflicts, and
      weak TVH criteria.
    - AI MUST NOT place orders, change risk policy, mutate trading intents, or
      become an input to deterministic decision hashes.
    - exchange API keys, recovery seed, private keys, and raw sensitive capsule
      data MUST NOT be included in AI context.
  - Hivra laws:
    - Modularity: AI remains an advisory drone/tooling layer; Trading Drone
      owns deterministic trade decisions and exchange execution.
    - Determinism: Trading Drone decisions remain reproducible without AI
      output.
    - Downward dependencies: AI consumes exported application-level snapshots;
      Core/Engine/Transport do not depend on AI or trading policy.
  - First deliverable:
    - `TradingDroneSnapshot` context for Capsule Analyst with redacted,
      hash-linked decision/risk/order evidence.
  - Status: planned.

- `13.2 Distributed Capsule Backup Drone`
  - Goal:
    - allow a capsule to distribute encrypted backup shards across trusted peer
      capsules.
  - Boundary:
    - This is a Backup Drone / application-layer protocol, not a Core ledger
      feature.
    - Core remains limited to Capsule, Ledger, Invitations, Trust Layer facts,
      Pair Consensus inputs, and deterministic domain transitions.
    - Trust Layer may provide peer eligibility, for example full trust links
      across all five starter kinds.
    - Transport delivers encrypted backup-shard envelopes; it does not inspect
      backup payloads.
  - Required safety model:
    - backup is encrypted locally before sharding.
    - use threshold recovery (`K-of-N`, for example 3-of-5) so any single peer
      shard is useless.
    - seed phrase, private keys, exchange API keys, and unencrypted ledger data
      MUST NOT be stored on peer capsules.
    - restore requires local user confirmation and enough valid shards.
    - shard rotation/revocation must be specified before release.
  - Hivra laws:
    - Modularity: backup protocol is a drone with its own state and manifests.
    - Determinism: shard manifests, shard ids, and restore verification are
      canonical and hashable.
    - Downward dependencies: Backup Drone consumes Trust Layer and Transport
      APIs; Core does not depend on backup logic.
  - First deliverable:
    - `Distributed Backup Drone v1` specification and threat model for
      encrypted ledger/history backup only, excluding seeds and API keys.
  - Status: planned.

- `13.3 AI-Operated Staking Drone`
  - Goal:
    - provide a staking drone that monitors all user-staked crypto assets and
      helps the user understand yield, risk, lockups, rewards, validator health,
      and required maintenance actions.
  - Boundary:
    - all inference follows
      `docs/architecture/ai-proposal-boundary.md`; executable staking authority
      cannot be inferred from model output.
    - This is a Staking Drone / financial-operations plugin, not Core.
    - AI acts as an operator assistant: it explains portfolio state, detects
      anomalies, ranks maintenance actions, and prepares user-readable plans.
    - AI MUST NOT sign transactions, move funds, unstake, restake, compound, or
      change validator/delegation choices without an explicit deterministic
      action policy and user confirmation.
    - wallet private keys, seed phrases, exchange API secrets, and raw signing
      material MUST NOT be included in AI context.
  - Required product model:
    - inventory of staked assets across supported chains/exchanges.
    - normalized staking position snapshots with chain, asset, amount,
      validator/provider, lockup/unbonding state, reward state, and health
      signals.
    - deterministic alert rules for missed rewards, slashing risk, validator
      degradation, unlock windows, excessive concentration, and stale data.
    - optional AI explanations generated from redacted staking snapshots and
      deterministic rule outputs.
  - Hivra laws:
    - Modularity: staking logic is owned by the Staking Drone; Core only
      provides capsule runtime, Trust Layer, and plugin execution boundaries.
    - Determinism: alerts and executable staking actions are derived from
      canonical snapshots and deterministic policies, not AI prose.
    - Downward dependencies: Staking Drone consumes wallet/exchange/chain
      adapters through plugin host APIs; Core/Engine/Transport do not depend on
      staking policy or AI.
  - First deliverable:
    - `Staking Drone v1` specification with read-only monitoring, redacted AI
      operator context, supported-source inventory, and a no-autosign safety
      contract.
  - Status: planned.

- `13.4 Moltbook Agent Drone`
  - Goal:
    - allow one user-owned Capsule to maintain an optional agent presence on
      Moltbook while keeping Capsule identity, private state, and Core truth
      local and independent.
  - Boundary:
    - Moltbook behavior belongs to an external WASM drone.
    - WASM receives no direct network, credential, ledger-write, repository,
      or unrestricted storage access.
    - Moltbook HTTPS effects use one provider adapter behind a capability-
      scoped host port and durable external-effect lifecycle.
    - public Moltbook state remains Moltbook-owned remote truth; private policy,
      drafts, cursors, and audit history remain isolated plugin state.
    - solo account operation does not require Relationships or Pair Consensus.
  - Required safety model:
    - all inference follows
      `docs/architecture/ai-proposal-boundary.md`; model output has no
      capability and cannot select or execute provider effects.
    - credentials are scoped by Capsule, plugin, provider, and external account
      in platform secure storage.
    - agent name, description, persona, topic allowlist, approval mode, and
      enabled state live in one host-owned plugin-state configuration; they do
      not become manifest fields, ledger events, or Capsule identity.
    - remote content and AI output are untrusted inputs and cannot invoke tools
      or grant capabilities.
    - the first releasable mode is Assisted: every post/reply requires exact
      outbound preview and user approval.
    - retries are idempotent and reconcile provider receipts before declaring
      success.
  - Architecture closure:
    - the installed `hivra.contract.moltbook-ambassador.v1` WASM package owns
      deterministic Public Bulletin draft construction without network access;
      the host-owned Assisted path separately reviews, approves, delivers, and
      verifies each explicit remote publication.
    - completed host baseline: the provider-neutral external-effect lifecycle:
      `prepare -> approve -> enqueue -> deliver -> reconcile -> terminal
      receipt`.
    - the normative lifecycle owner and review gate are documented in
      `docs/architecture/external-effect-lifecycle.md`.
    - the normative inference/authority boundary is documented in
      `docs/architecture/ai-proposal-boundary.md`.
    - the normative target identity, single-engagement lifecycle,
      wake-run-sleep cycle, and trigger-mode contract is documented in
      `docs/plugins/moltbook_engagement_lifecycle_v1.md`.
    - completed read-only adapter baseline: pinned official HTTPS origin,
      bounded account/home projections, redirect rejection, timeout/size
      limits, rate-budget parsing, and fail-closed provider error mapping.
    - completed bounded conversation review: one exact post and at most 20
      newest comments are normalized as untrusted in-memory observations;
      provider DTOs and remote text are not persisted.
    - completed deterministic engagement proposal: WASM may propose review of
      a reply, comment, or vote candidate, but generates no reply text and has
      no network-effect capability.
    - completed Assisted Reply pipeline: one bounded public conversation and
      deterministic engagement plan may be explicitly disclosed to the
      configured inference provider as untrusted context; advisory prose
      remains editable and in memory until WASM binds the exact reviewed text
      to its post/comment target and plan hash.
    - completed durable comment effect: root comments and nested replies use
      the same approval, queue, delivery, reconciliation, verification, and
      receipt lifecycle as posts. Exact target, author, and content matching
      prevents blind retry after an ambiguous provider outcome.
    - completed macOS Release smoke on 2026-07-29: repeated review produced one
      stable comment operation, provider verification remained unresolved
      until explicit challenge resolution, and success bound exact comment
      receipt `b3c2d72c-c0ed-48b4-9aef-b5a8bbb05fd3`.
    - completed optional Public Bulletin communication proposal: the selected
      inference provider receives only explicitly confirmed public source
      notes, public topic, and persona; a strict bounded title, natural body,
      and supporting facts remain in memory for manual edit before the
      independent WASM draft and publication approval gates.
    - require the installed ambassador WASM to preserve the exact reviewed
      title/body and reject the former mechanical newline fact dump before a
      draft can enter publication approval.
    - completed generic secure plugin-credential vault: one versioned Secure
      Storage item, serialized updates, fail-closed parsing, and cleanup by
      both Capsule deletion and plugin removal.
    - completed Moltbook account binding: verify-before-save, transactional
      account replacement, explicit refresh/disconnect, and non-secret
      Capsule-scoped binding metadata. Ordinary workspace loading does not
      read Secure Storage.
    - no second provider-specific credential store or Keychain orphan is
      accepted.
    - completed first write milestone: Assisted publication with exact preview,
      one explicit approval per effect, durable provider challenge, explicit
      verification response, and matching visible-post evidence before success.
    - completed canonical engagement convergence: Assisted and Bounded writes
      share one `engagement_id`, target projection, and orchestration port;
      duplicate active/succeeded targets cannot enter a parallel effect route.
    - completed trigger-policy host: `on_demand`, once-per-process `session`,
      and sequential `continuous_while_running` invoke the same
      Capsule/plugin/account-scoped cycle engine. Existing profiles migrate to
      `on_demand`, stop prevents future wake-ups, and no trigger policy changes
      decision or effect semantics.
    - completed canonical workspace UI projection: one computed next action
      prioritizes active effect recovery, write and trigger policies remain
      visibly separate, Stop is available on the primary surface, cycle/effect
      counts are projected without granting authority, and raw provider/cycle
      diagnostics are secondary. The ordinary release UI exposes no Bounded
      publication button before release evidence passes.
    - completed generation-bound Stop behavior: an in-flight provider read may
      finish, but its late result cannot start WASM planning, commit a
      checkpoint, overwrite the stopped projection, or race a replacement
      cycle.
    - remaining blocker before Bounded/automatic release: complete release
      evidence for hostile input, duplicate target, restart, timeout,
      challenge, Capsule switch, rate limit, stop, macOS, and Android.
    - completed macOS Release evidence on 2026-07-27: Moltbook post
      `32a3006b-94e3-4087-82f6-58e3666cef4e` remained unresolved while hidden
      and became succeeded only after explicit challenge resolution and a
      matching public `verified` post observation.
    - the dedicated Ambassador workspace owns Connection, Profile, Drafts,
      Approval Queue, Activity, and Stop surfaces; the generic Plugins screen
      remains installation/health UI.
    - Discover publication is blocked until macOS and Android effect/restart/
      retry smoke passes against a disposable Moltbook agent.
    - design authority:
      `docs/plugins/moltbook_agent_drone_design_v1.md`.
  - First deliverable:
    - completed: approve the ownership boundary and define the draft-only
      Public Bulletin contract without changing the 1.x Core protocol.
  - Status: Phase 0 draft prototype, Phase 1 host lifecycle, Phase 2
    account/home/feed/conversation Observe with secure binding, Phase 3
    deterministic WASM Draft, Engagement, and Reply Preview, and the Phase 4
    Assisted post/reply publication host paths are implemented. Automated
    adapter and contract tests and macOS Release smoke pass; Android manual
    smoke for the new reply path remains required before catalog publication.

- `11.8 Trading Drone Live Criteria Parity (spec factors must drive live entry)`
  - Goal:
    - eliminate the remaining gap between documented TVH criteria and live entry behavior in execution surfaces.
  - Original problem:
    - deterministic TVH pipeline exists (`snapshot -> feature -> rule -> replay`) but live entry in `TradingDroneScreen` still uses zone-heuristic decision path and does not consume full TVH feature/rule outcome for signal gating.
    - risk input still relies on local proxy values for equity/pnl/positions in UI path instead of exchange-backed runtime state.
  - Scope:
    - introduce one service-level live decision contract that is consumed by:
      - `TradingDroneScreen`
      - `WasmPluginsScreen`
    - enforce that live entry eligibility is derived from TVH rule-engine decision (`LONG|SHORT|NO_SIGNAL|BLOCKED`) plus consensus/risk/runtime gates.
    - map TVH decision outputs into side/zone/entry-mode payload fields with stable reason codes and deterministic decision hash provenance.
    - replace UI risk proxy fields with exchange-backed risk inputs where available (equity, daily pnl, open positions), while preserving deterministic fallback path.
    - extend regression coverage for:
      - parity between replay decision and live decision contract for identical normalized input
      - reject-path determinism (`NO_SIGNAL`, `BLOCKED`, risk blocks)
      - decision envelope linkage (`feature_hash -> decision_hash -> execution envelope`)
  - Current progress:
    - Extended `BingxFuturesExchangeService` public market-data surface for live TVH snapshot inputs:
      - `getPublicDepth` (`/openApi/swap/v2/quote/depth`)
      - `getPublicTrades` (`/openApi/swap/v2/quote/trades`)
      - `getPublicPremiumIndex` (`/openApi/swap/v2/quote/premiumIndex`)
      - `getPublicOpenInterest` (`/openApi/swap/v2/quote/openInterest`)
    - Added regression coverage in `flutter/test/bingx_futures_exchange_service_test.dart` for all new public adapters.
    - Added `BingxFuturesLiveDecisionService` as the first shared live decision contract:
      - builds canonical snapshot
      - extracts features
      - evaluates TVH rule-engine gate
      - maps passing `LONG|SHORT` decisions to side/zone intent fields
      - links `market_snapshot_hash -> feature_hash -> tvh_decision_hash -> live_decision_hash`
    - Added regression coverage in `flutter/test/bingx_futures_live_decision_service_test.dart` for:
      - deterministic live `LONG` eligibility
      - deterministic live `SHORT` eligibility
      - deterministic `NO_SIGNAL` (funding-guard) branch
      - input ordering stability
      - consensus-guard blocked path.
    - Both execution surfaces now consume the same live decision contract before intent prepare:
      - `TradingDroneScreen._runIntent`
      - `WasmPluginsScreen._runBingxIntent`
      removing screen-local side/zone branching from live signal gating.
    - Live execution risk inputs now use exchange-backed runtime values via `BingxFuturesExchangeRiskInputService` (`equity`, `daily pnl`, `concurrent positions`) and both execution surfaces run the same risk-governor boundary before exchange submit.
    - Live exchange execution now fails closed when balance, pnl, or position
      inputs use fallback values; fallback risk inputs remain diagnostic/test
      only.
  - Definition of done:
    - no execution surface can place intent from a decision path outside the shared TVH contract.
    - identical normalized input produces identical decision payload/hash in replay and live path.
    - checklist `docs/checklists/trading-drone-spec-runtime-parity.md` status matrix is fully green.
  - Status: completed (2026-06-01).

- `11.7 Trading Drone Decision Pipeline Unification (remove screen-local heuristic split)`
  - Goal:
    - remove decision split-brain between screen-local heuristic zone logic and service-level deterministic TVH pipeline.
  - Original problem:
    - futures decision services exist (`snapshot -> feature -> rule -> replay`) but `TradingDroneScreen` still owns side/zone computation heuristics directly.
    - this creates spec/runtime ambiguity and weakens deterministic auditability of decision provenance.
  - Scope:
    - expose one service-level decision contract for:
      - selected side (`buy|sell`)
      - zone bounds (`zone_low`, `zone_high`)
      - reason codes and matched criteria summary
      - deterministic decision hash linkage
    - consume this contract from:
      - `TradingDroneScreen`
      - `WasmPluginsScreen`
    - keep UI projection-only (no duplicated decision branch logic in screens).
    - extend replay fixtures/tests to include side/zone outputs and reason-code stability.
  - Definition of done:
    - screen-local heuristic decision branches are removed or reduced to view-only formatting.
    - both execution surfaces use the same deterministic decision contract for identical inputs.
    - replay tests detect any side/zone/reason drift.
  - Current progress:
    - Added `BingxFuturesZoneDecisionService` as service-level deterministic zone/side decision boundary.
    - Moved side/zone heuristic decision logic out of `TradingDroneScreen` and into the service contract.
    - `TradingDroneScreen` now consumes one decision result payload (side/zone/reason/diagnostic context) and remains orchestration/projection-only for this path.
    - Added regression coverage in `flutter/test/bingx_futures_zone_decision_service_test.dart` for:
      - deterministic fallback behavior
      - sweep-reversal side selection
      - repeatability for identical inputs.
  - Status: completed (2026-05-18).

- `11.1 Trading Drone Runtime Execution (remove host_fallback for execution path)`
  - Goal:
    - execute trading-drone contract path through mounted plugin runtime boundary (not host fallback) while preserving modularity, determinism, and downward dependencies.
  - Current progress:
    - `PluginHostApiService` now enforces runtime-only execution for `place_bingx_futures_order_intent`:
      - host-fallback path is rejected with deterministic `runtime_invoke_unavailable`
      - runtime package + invoke evidence are required for futures intent execution
    - Added/updated regression coverage in `flutter/test/plugin_host_api_service_test.dart`:
      - executed futures path via `executeWithRuntimeHook(...)` + external runtime evidence
      - explicit fallback-disabled reject path via `execute(...)`
  - Scope:
    - route `place_bingx_futures_order_intent` execution through runtime invoke path whenever runtime contract is valid (`abi/entry/capabilities` pass).
    - keep deterministic reject paths (`runtime_binding_invalid`, `runtime_contract_kind_mismatch`, capability mismatch) unchanged and hash-stable.
    - add regression coverage that response/source metadata stays deterministic across:
      - runtime executed path
      - runtime rejected path
      - explicit fallback-disabled path
    - add manual smoke checklist entries for Trading Drone screen:
      - `intent -> execute -> queue/retry/idempotency -> signal broadcast/inbox`.
  - Definition of done:
    - trading-drone execution no longer reports `execution_source=host_fallback` in normal valid-runtime path.
    - plugin runtime and fallback error branches are deterministic and test-covered.
    - release smoke can verify runtime execution end-to-end on macOS and Android.
  - Status: completed (2026-05-14).

- `11.2 Trading Drone Mode Orchestrator (situational + interactive parity)`
  - Goal:
    - introduce explicit dual-mode lifecycle (`situational` and `interactive`) without forking decision logic.
  - Current progress:
    - Added `BingxFuturesModeOrchestratorService` as dedicated mode lifecycle boundary (`situational` / `interactive`) using one shared deterministic pipeline callback.
    - Added regression coverage in `flutter/test/bingx_futures_mode_orchestrator_service_test.dart` for:
      - situational execution path
      - interactive sequential cycle path
      - mode parity for identical cycle input.
  - Scope:
    - add a dedicated orchestrator service that schedules evaluation cycles for `interactive` mode and single-run execution for `situational`.
    - enforce one shared deterministic pipeline for both modes:
      - `snapshot_normalize -> feature_extract -> rule_engine -> intent_builder`.
    - prevent UI from owning any mode-specific decision logic (UI is projection-only).
  - Definition of done:
    - both modes produce identical decision payload/hash for identical snapshot+policy input.
    - mode-specific behavior differs only in orchestration/timing.
    - mode parity is covered by deterministic regression tests.
  - Status: completed (2026-05-14).

- `11.3 Deterministic Replay Harness for Drone Decisions`
  - Goal:
    - guarantee reproducible decisions and hashes across replays and platforms.
  - Current progress:
    - Added `BingxFuturesTvhRuleEngineService` with deterministic `LONG|SHORT|NO_SIGNAL|BLOCKED` evaluation and hashable canonical decision envelope.
    - Added `BingxFuturesDeterministicReplayHarnessService` to execute:
      - `snapshot_normalize -> feature_extract -> rule_engine`
      - fixture-by-fixture deterministic replay assertions.
    - Added regression suites:
      - `flutter/test/bingx_futures_tvh_rule_engine_service_test.dart`
      - `flutter/test/bingx_futures_deterministic_replay_harness_service_test.dart`
      covering `long`, `short`, `no_signal`, `blocked` branches plus repeat/permutation hash stability checks.
  - Scope:
    - add canonical fixture pack (`snapshot fixtures + expected decision + expected hash`).
    - add replay runner tests to execute the same fixtures multiple times and across ordering permutations.
    - fail build on any non-deterministic drift (`decision drift`, `hash drift`, unstable rounding).
  - Definition of done:
    - repeated replay of identical fixtures is bit-stable for decision payload and hash.
    - CI contains deterministic replay suite for all primary branches (`long`, `short`, `no_signal`, blocked paths).
  - Status: completed (2026-05-14).

- `11.4 Futures Risk Governor v1 (pre-execution hard gates)`
  - Goal:
    - ensure no order can bypass deterministic risk limits before exchange execution.
  - Current progress:
    - Added dedicated `BingxFuturesRiskGovernorService` boundary with deterministic pre-execution hard gates:
      - symbol allow/deny,
      - max concurrent positions,
      - loss-streak cooldown,
      - daily loss limit,
      - per-trade risk budget via `risk% + stop-loss distance`.
    - Wired risk gate into both futures execution UI entrypoints before exchange submit:
      - `TradingDroneScreen._executeLastIntent()`
      - `WasmPluginsScreen._executeLastBingxIntentOnExchange()`
      with explicit `risk_allowed` / `risk_blocked` log events and user-visible reject feedback.
    - Decision output now includes canonical envelope + stable hash for audit and replay checks.
    - Added regression coverage in `flutter/test/bingx_futures_risk_governor_service_test.dart` for allow path and each block branch plus hash determinism.
    - Replaced the balance-summary/constant-placeholder risk inputs with a
      Capsule-scoped atomic projection of authenticated BingX `REALIZED_PNL`
      income records. The governor now receives real UTC-day PnL, loss streak,
      and last-loss time; incomplete history fails closed for live orders.
  - Scope:
    - implement hard gates:
      - `max_risk_per_trade`,
      - `max_daily_loss`,
      - `max_concurrent_positions`,
      - cooldown after loss-streak,
      - symbol allowlist/denylist.
    - compute position size strictly from risk model (`risk% + SL distance`), not from ad-hoc UI quantity.
    - emit deterministic reject codes/reasons for each blocked gate.
  - Definition of done:
    - every execution attempt passes through risk governor with deterministic output.
    - blocked decisions are explainable and test-covered with stable reason codes.
  - Status: completed (2026-05-14).

- `11.5 Futures Execution Reliability (idempotency + TTL + retry discipline)`
  - Goal:
    - eliminate duplicate/missing execution effects under network jitter and relay/exchange instability.
  - Current progress:
    - Extended `BingxFuturesExecutionQueueService` with deterministic pending-order lifecycle:
      - successful limit/zone-pending orders are tracked as pending with bounded TTL,
      - expired pending records emit deterministic `cancelReplace` actions (`pending_order_ttl_expired`),
      - TTL sweep releases idempotency cache for the same key so replace flow is unblocked.
    - Added retry-class matrix helper (`bingxExchangeExecutionRetryClass`) with explicit clock-skew branch (`-1021` / timestamp / recvWindow) while preserving deterministic fail-fast for non-retryable rejects.
    - Added regression coverage in `flutter/test/bingx_futures_execution_queue_service_test.dart` for:
      - pending TTL expiry -> cancel/replace action + cache release,
      - timestamp-drift retry classification.
  - Scope:
    - enforce idempotency keys across command send and exchange execution.
    - add pending-order TTL lifecycle (`place -> monitor -> cancel/replace`).
    - define bounded retry matrix for transient failures (network timeout, timestamp drift), while keeping deterministic fail-fast on non-retryable exchange rejects.
    - keep anti-replay state in plugin journal boundary (no core-ledger mutation bypass).
  - Definition of done:
    - no duplicate order placement for same command idempotency key.
    - stale pending orders are deterministically canceled by TTL policy.
    - retry behavior is deterministic and covered by tests.
  - Status: completed (2026-05-14).

- `11.6 Drone Observability + Release Smoke Gate`
  - Goal:
    - make every drone decision/execution auditable and release-verifiable on macOS + Android.
  - Current progress:
    - Added deterministic observability envelope boundary:
      - `BingxFuturesObservabilityEnvelopeService`
      - canonical `decision` / `execution` envelopes with stable hash.
    - Wired envelope logging into both futures execution surfaces:
      - `TradingDroneScreen` (`drone.decision.envelope`, `drone.execution.envelope`)
      - `WasmPluginsScreen` (`drone.decision.envelope`, `drone.execution.envelope`)
    - Added regression coverage:
      - `flutter/test/bingx_futures_observability_envelope_service_test.dart`
    - Extended release smoke checklists to require Trading Drone gate on both platforms.
  - Scope:
    - standardize `decision log` and `execution log` envelopes with stable fields/hashes.
    - add release smoke checklist:
      - `situational run`,
      - `interactive cycle`,
      - risk-block path,
      - retry path,
      - receipt path.
    - add cross-platform acceptance thresholds (no critical execution errors, deterministic hash parity on fixture run).
  - Definition of done:
    - release preflight includes drone smoke checks for both platforms.
    - operators can trace any order to its deterministic decision record.
  - Status: completed (2026-05-14).

- `11.7 Managed Order Provenance Journal`
  - Goal:
    - preserve enough capsule-scoped lineage to revalidate and eventually replace a managed exchange order without guessing from mutable UI state.
  - Current progress:
    - tracking state schema v2 persists canonical intent JSON plus intent/snapshot/feature/TVH/live decision hashes per managed order.
    - successful exchange receipts register provenance; cancel/close paths remove it with the managed order id.
    - v1 tracking files remain readable and produce empty provenance rather than fabricated lineage.
  - Definition of done:
    - app restart retains deterministic origin for every newly placed managed order.
    - API credentials and exchange secrets are never written to the provenance journal.
    - future replacement may only proceed from valid provenance through fresh decision, risk, idempotency, and execution gates.
  - Status: completed (2026-06-12).

- `11.10 Side-Locked Structural Order Revalidation`
  - Goal:
    - prevent stale managed orders from surviving only because transient flow
      inputs produce `NO_SIGNAL`, without canceling valid structural orders on
      every temporary signal loss.
  - Current progress:
    - live decision accepts an explicit existing-order side for structural
      zone evaluation while preserving `side=null` and
      `can_prepare_intent=false` for `NO_SIGNAL`.
    - managed order revalidation compares the existing trigger price with that
      side-locked executable zone.
    - missing anchors and zone mismatch cancel; an in-zone structural order is
      kept.
    - structural-only cancellation is cancel-only and cannot place a
      replacement order.
  - Definition of done:
    - transient trade-delta `NO_SIGNAL` does not churn a structurally valid
      order.
    - an order on a consumed or obsolete level cannot survive behind
      `live_decision_not_actionable`.
  - Status: completed (2026-06-12).

- `11.8 Deterministic Managed Order Replacement`
  - Goal:
    - replace a stale-zone managed order without copying mutable UI state or bypassing normal execution safety.
  - Current progress:
    - added pure `BingxFuturesOrderReplacementService` planner.
    - only `live_zone_mismatch` can auto-replace; side flips and market-dead gates remain cancel-only.
    - replacement keeps original quantity and projects original stop-distance percentage + risk/reward ratio onto the fresh TVH zone.
    - runtime replacement path repeats plugin host/consensus preparation, risk governor, idempotent execution queue, exchange receipt, and provenance registration.
    - one replacement per `(peer, symbol, side)` is allowed in a revalidation cycle.
    - open-order polling uses a lifecycle revision guard so a pre-cancel exchange snapshot cannot delete the newly registered replacement receipt.
  - Definition of done:
    - identical provenance + live decision + cycle timestamp yields identical replacement args/client id.
    - no unprovenanced, side-flipped, or market-dead order is automatically replaced.
    - successful replacement produces a new managed receipt and capsule-scoped provenance.
  - Status: completed (2026-06-12).

- `11.9 HTF Liquidity Lifecycle Gate`
  - Goal:
    - prevent already swept or later consumed higher-timeframe levels from
      being reused as fresh pending-entry anchors.
  - Current progress:
    - replaced raw `4h/1d/1w` high/low candidates with confirmed swing pivots.
    - added deterministic `fresh`, `sweep_origin`, `post_sweep_reaction`, and
      `consumed` lifecycle classification from ordered closed candles.
    - only untouched `fresh` pivots reach external retest selection.
    - post-sweep entries remain on the separate current
      `sweep -> reclaim -> displacement` path.
    - local older/recent high/low fallback remains available for diagnostics,
      but cannot authorize an executable pending-entry intent.
    - liquidation, force-order, and orderbook proxy levels remain contextual
      evidence only and cannot become executable entry anchors.
    - expanded `4h` lifecycle input from 120 to 500 closed candles (about
      83 days) so older sweeps cannot disappear outside a 20-day lookback.
    - the first same-side pivot after a sweep-origin remains part of the
      reaction leg and cannot be promoted to fresh external liquidity.
    - no fresh HTF or confirmed current micro anchor emits
      `liquidity_anchor_unavailable`; managed-order revalidation treats it as
      cancel-only and does not fabricate a replacement.
    - added regression coverage for untouched, sweep-origin, and later-breached
      pivots plus non-executable internal fallback.
  - Definition of done:
    - a sweep-origin or consumed level cannot produce an external pending-entry
      zone from the same normalized snapshot.
    - identical ordered candle inputs produce identical candidate selection.
  - Status: completed (2026-06-12).

- `11.11 Plugin-Owned Semantic WASM ABI`
  - Goal:
    - make the installed `hivra-plugins` package the authoritative evaluator
      of its deterministic contract instead of using WASM only as an entry
      probe before host-side evaluation.
  - Implemented:
    - bounded deterministic JSON-in/JSON-out ABI v2 with explicit
      alloc/evaluate/dealloc memory ownership and result/error envelope.
    - import-free, fuel-bounded and size-bounded `wasmi` runtime in the lower
      platform layer, exposed through FFI for macOS and Android builds.
    - canonical output schema/identity/hash validation in the host.
    - BingX and Capsule Chat semantic evaluators live in `hivra-plugins`;
      mirrored Flutter evaluators were removed.
  - Definition of done:
    - changing plugin evaluator code changes runtime result without rebuilding
      Hivra-App.
    - identical package digest + canonical input yields identical output hash.
    - host owns only validation, capabilities, consensus, risk and exchange
      adapters; plugin owns contract semantics.
    - `trading_drone_parity_gate.sh` is green and release evidence is recorded.
  - Status: completed (2026-06-14).

- `11.12 Pair-Scoped Trading Consensus Guard`
  - Goal:
    - keep Trading Drone peer execution diagnostics pair-scoped instead of
      treating any signable peer as permission for an unspecified peer.
  - Implemented:
    - Pair-scoped Trading Drone paths report `consensus_peer_not_selected` when
      no explicit peer is selected, and `consensus_peer_not_found` when the
      selected peer is absent from the current consensus projection.
    - Solo futures intent execution is not pair-scoped and must not require
      consensus; the consensus guard remains mandatory for peer/broadcast/copy
      execution.
    - market scan and managed-order structural revalidation keep their explicit
      diagnostic bypass path (`forceConsensusSignable`) because they do not
      mutate a pair-scoped contract by themselves.
    - `ConsensusProcessor` regression coverage now locks the ledger truth that
      an active relationship with one peer does not make a pending invitation
      from another peer signable.
  - Status: completed (2026-06-28).

- `11.13 Local Backup Follows Ledger`
  - Goal:
    - prevent local capsule backups from becoming a stale second truth after
      normal ledger mutations.
  - Implemented:
    - every persisted runtime ledger snapshot now refreshes the local
      `capsule-backup.v1.json` envelope from the same ledger and capsule state.
    - worker-provided capsule ledger snapshots follow the same rule.
  - Status: completed (2026-06-29).

- `11.14 Capsule Analyst and macOS Runtime Seed Boundary`
  - Goal:
    - replace scattered bootstrap/trace diagnostics with one deterministic
      local diagnostic surface.
    - prevent macOS capsule switching from rewriting Keychain active-seed
      state and repeatedly prompting for passwords.
  - Implemented:
    - added Capsule Analyst as the local user-facing diagnostic screen for
      bootstrap summary, filesystem trace, ledger projection, invitations,
      relationships, outbox, consensus, and plugin state.
    - removed separate Settings entries for bootstrap diagnostics and local
      capsule trace; those summaries now live under Capsule Analyst.
    - capsule recovery seed fallback migration now deduplicates secure-storage
      reads/writes in-process and remains fail-closed for plaintext fallback.
    - macOS keystore now keeps the active runtime seed in process-local memory
      and caches already verified per-seed Keychain accounts, so switching
      capsules does not rewrite a global active-seed pointer.
  - Verification:
    - `cargo test -p hivra-keystore`
    - `flutter test test/ai_capsule_inspection_service_test.dart test/capsule_seed_store_test.dart`
    - `flutter analyze`
    - `tools/review/review_all.sh`
    - `flutter build macos --release`
    - manual release run showed capsule bootstrap around `23 ms` and no
      repeated `SecKeychainItemModifyAttributesAndData` during capsule switches.
  - Status: completed (2026-07-05).

- `11.14.1 macOS Keychain Prompt Consolidation`
  - Goal:
    - remove repeated Keychain authorization loops during capsule activation.
    - preserve one secure per-capsule seed authority and a process-local Rust
      runtime seed without weakening secret storage.
  - Implemented:
    - macOS Rust seed activation no longer reads or writes a duplicate native
      Keychain record during normal capsule selection and runtime bootstrap.
    - legacy native Keychain records remain readable only for recovery, and a
      successful existence check populates the runtime cache for the following
      load.
    - Release builds disable injected base entitlements so `get-task-allow`
      cannot leak into the application signature through Xcode defaults.
  - Distribution constraint:
    - ad-hoc builds still have an unstable code-signing identity; persistent
      Keychain trust across rebuilt binaries requires a stable signed release.
  - Status: completed (2026-07-21).

- `11.15 Unified Capsule Analyst Module`
  - Goal:
    - keep Capsule Analyst as the single user-facing diagnostic surface while
      also consolidating bootstrap and filesystem trace diagnostics behind one
      internal diagnostic module.
    - prevent diagnostics from spreading back into Settings, UI screens, or
      persistence orchestration.
  - Scope:
    - moved `diagnoseBootstrapReport` and `diagnoseCapsuleTraces` behind one
      cohesive `CapsuleDiagnosticsService` boundary.
    - kept lower-level bootstrap and persistence code as data providers only.
    - kept the diagnostic snapshot deterministic and local-only.
    - removed diagnostics from `SettingsService`; Settings no longer acts as a
      diagnostics transport surface.
  - Constraints:
    - no new upward dependencies from core/engine/platform into Flutter UI.
    - no provider/AI upload path for seed, ledger, transport secrets, or
      credentials.
    - Capsule Analyst remains projection-only and does not mutate capsule state.
  - Verification:
    - `flutter test test/ai_capsule_inspection_service_test.dart test/capsule_diagnostics_service_test.dart test/settings_service_test.dart`
    - `flutter analyze`
    - `tools/review/review_all.sh`
  - Status: completed (2026-07-05).

- `11.16 Scoped AI Capsule Analyst`
  - Goal:
    - add an optional AI-provider advisory path to Capsule Analyst without
      turning any external model into ledger truth or a runtime actor.
    - keep the first AI integration scoped to redacted, user-selected
      diagnostic summaries instead of repository access or raw capsule data.
  - Scope:
    - added secure-storage-only provider credential storage.
    - added deterministic outbound prompt/preview construction with bounded
      payload size and explicit selected sections.
    - added an `InferenceProvider` boundary with provider-isolated keys,
      OpenAI Responses API support, Gemini GenerateContent support, and strict
      empty/malformed response rejection.
    - added Capsule Analyst UI controls for provider key save/clear, model,
      question, selected context sections, outbound preview, and advisory
      response rendering.
  - Constraints:
    - no plaintext provider-key fallback.
    - provider adapters receive only already-redacted prompt payloads.
    - no ledger/runtime/plugin/contact/outbox mutation from provider response.
    - no repository access in this phase.
    - no dependencies from core/engine/platform back into Flutter provider
      code.
  - Verification:
    - `flutter test test/ai_doctor_credential_store_test.dart test/ai_doctor_prompt_service_test.dart test/ai_doctor_provider_adapter_test.dart`
    - `flutter test`
    - `flutter analyze`
    - `tools/review/review_all.sh`
    - `flutter build macos --release`
  - Status: completed (2026-07-05).

- `11.17 Plugin Auditor Diagnostics`
  - Goal:
    - add a read-only plugin audit mode before developer repository access.
    - make installed plugin package trust evidence visible from Capsule Analyst
      without granting new capabilities or mutating plugin state.
  - Scope:
    - added deterministic `AiPluginAuditService` over installed plugin registry
      records and stored package bytes.
    - audit report includes package digest, package kind, size, declared
      capabilities, plugin id/version, ABI/entry compatibility, and findings.
    - Capsule Analyst now surfaces Plugin Auditor as a separate read-only card.
  - Constraints:
    - no plugin registry/catalog/package mutation.
    - no capability escalation; unsupported capabilities are findings only.
    - no source-code or repository access in this phase.
    - no dependencies from core/engine/platform into plugin audit UI code.
  - Verification:
    - `flutter test test/ai_plugin_audit_service_test.dart`
    - `flutter analyze`
    - `tools/review/review_all.sh`
    - `flutter build macos --release`
  - Status: completed (2026-07-05).

- `11.18 Developer Workspace Preview`
  - Goal:
    - start Developer Mode without giving any AI/provider broad repository
      access.
    - provide a deterministic local allowlist scan that can later feed explicit
      developer snippets.
  - Scope:
    - added `AiDeveloperWorkspaceService` for read-only local repository
      previews.
    - scan output includes allowed file paths, sizes, SHA-256 hashes, skip
      counts, denylist findings, and a deterministic report hash.
    - Capsule Analyst now includes a manual Developer Workspace Preview card for
      explicit local paths.
  - Constraints:
    - no source contents are uploaded or sent to AI.
    - no remote clone/cache yet.
    - no script/hook execution.
    - denylisted secrets, build/cache directories, symlinks, binaries,
      oversized files, and unknown top-level paths are skipped.
  - Verification:
    - `flutter test test/ai_developer_workspace_service_test.dart`
    - `flutter analyze`
    - `tools/review/review_all.sh`
    - `flutter build macos --release`
  - Status: completed (2026-07-05).

- `11.19 Developer Selected Context Preview`
  - Goal:
    - allow developer-mode context to advance from repository map to explicit
      selected snippets without broad repository upload.
  - Scope:
    - added selected-file context builder on top of workspace preview.
    - selected files are read only when they were present in the preview and
      their SHA-256 still matches.
    - selected context includes snippet text, file hashes, findings, payload
      size, and deterministic context hash.
    - Capsule Analyst shows a local selected-context JSON preview.
  - Constraints:
    - no provider submission in this step.
    - no automatic patching, committing, pushing, cloning, or script execution.
    - selected source/log/manifest content is explicitly marked as untrusted
      prompt input.
  - Verification:
    - `flutter test test/ai_developer_workspace_service_test.dart`
    - `flutter analyze`
    - `tools/review/review_all.sh`
    - `flutter build macos --release`
  - Status: completed (2026-07-05).

- `11.20 Explicit Developer Mode Boundary`
  - Goal:
    - prevent developer repository tooling from appearing as ordinary
      user-facing Capsule Analyst.
  - Scope:
    - added a Developer Mode card that is disabled by default.
    - workspace scan/selected-context tools are rendered only after explicit
      per-screen enablement.
    - enabled state is visually distinct and repeats the no-mutation rule.
  - Constraints:
    - no new repository read capability was added in this step.
    - no provider upload, patching, committing, pushing, releasing, ledger
      mutation, or plugin registry mutation.
  - Verification:
    - `flutter analyze`
    - `tools/review/review_all.sh`
    - `flutter build macos --release`
  - Status: completed (2026-07-06).

- `11.21 Hivra Engineer Advisory Ask`
  - Goal:
    - allow Developer Mode to ask an AI engineer about explicit selected
      evidence without granting repository write access.
  - Scope:
    - combine local Capsule Analyst snapshot, selected developer context, and a
      user question into one outbound preview.
    - provider response is advisory only: likely files, hypotheses, suggested
      tests, and patch plan.
    - no file writes, no patch application, no git operations, no release
      operations.
    - Capsule Analyst Developer Mode now exposes Preview/Ask Hivra Engineer
      controls after selected context is built.
  - Acceptance:
    - empty selected context is rejected.
    - changed selected files are rejected before provider submission.
    - provider failures leave capsule state and repository state unchanged.
  - Verification:
    - `flutter test test/ai_developer_engineer_service_test.dart`
    - `flutter analyze`
    - `tools/review/review_all.sh`
    - `flutter build macos --release`
  - Status: completed (2026-07-06).

- `11.22 Developer Provider Boundary Tests`
  - Goal:
    - make the Hivra Engineer provider path fail closed before adding more
      repository capabilities.
  - Scope:
    - tests for invalid/empty provider key, timeout/rate limit, malformed
      response, oversized context, prompt-injection warning presence, and
      no-mutation guarantees.
    - explicit fixtures proving denylisted paths are never included in
      provider payloads.
    - Hivra Engineer now revalidates selected snippet paths before provider
      submission instead of trusting only the workspace preview layer.
  - Verification:
    - `flutter test test/ai_developer_engineer_service_test.dart test/ai_developer_workspace_service_test.dart test/ai_doctor_provider_adapter_test.dart`
    - `flutter analyze`
    - `tools/review/review_all.sh`
  - Status: completed (2026-07-06).

- `11.23 Remote Repository Allowlist Cache`
  - Goal:
    - support developer-provided public repository links without giving AI or
      plugins uncontrolled network/repository access.
  - Scope:
    - read-only clone/cache under Hivra-controlled developer cache.
    - pin commit/tag where possible; mutable/unpinned context is marked
      dangerous.
    - no hooks, no scripts, no submodules unless explicitly allowlisted.
    - cache clear action.
    - added `AiDeveloperRemoteRepositoryCacheService` with GitHub HTTPS URL
      allowlist, controlled cache path, prompt-free git calls, hook disabling,
      submodule recursion disabling, resolved commit reporting, and cache clear.
  - Verification:
    - `flutter test test/ai_developer_remote_repository_cache_service_test.dart`
  - Status: completed (2026-07-06).

- `11.24 Plugin Auditor v2`
  - Goal:
    - extend plugin audit from installed package metadata to selected plugin
      source evidence in Developer Mode.
  - Scope:
    - audit installed package, catalog signature/digest evidence, manifest,
      capabilities, runtime invocation evidence, and selected source snippets.
    - auditor remains read-only and cannot grant capabilities.
    - added selected-source audit for plugin manifest, catalog digest/signature
      evidence, runtime entry evidence, expected plugin id drift, ABI drift, and
      unsupported capabilities.
  - Verification:
    - `flutter test test/ai_plugin_audit_service_test.dart`
  - Status: completed (2026-07-06).

- `11.25 Plugin Scaffolder Draft Mode`
  - Goal:
    - create draft-only WASM plugin skeletons without crossing the app/plugin
      repository boundary.
  - Scope:
    - developer supplies plugin id, purpose, capabilities, and host API
      version.
    - generated draft includes manifest, source skeleton, tests, README, and at
      least one golden vector.
    - no build, install, catalog update, signing, commit, push, tag, or release
      is automatic.
    - added `AiPluginScaffoldDraftService`, guarded by explicit hivra-plugins
      repository markers, writing only under `plugins/drafts/<slug>/`.
  - Verification:
    - `flutter test test/ai_plugin_scaffold_draft_service_test.dart`
  - Status: completed (2026-07-06).

- `11.26 Patch Proposal Mode`
  - Goal:
    - let AI propose patches without applying them.
  - Scope:
    - AI returns patch text/diff preview only.
    - user reviews; applying remains a separate human-confirmed action.
    - no commits, pushes, tags, or releases from AI output.
    - added `AiPatchProposalService` to parse unified diff proposals into a
      deterministic preview report with no apply/git/release side effects.
  - Verification:
    - `flutter test test/ai_patch_proposal_service_test.dart`
  - Status: completed (2026-07-06).

- `11.27 Review Gate Integration`
  - Goal:
    - ensure AI suggestions stay subordinate to Hivra gates.
  - Scope:
    - advisory reports list required tests/gates.
    - UI marks output as unverified until user runs checks.
    - AI output never overrides review gates, release gates, or manual smoke.
    - added `AiReviewGateIntegrationService` for deterministic unverified
      reports across developer advisory, patch proposal, plugin source audit,
      and release-readiness scopes.
  - Verification:
    - `flutter test test/ai_review_gate_integration_service_test.dart`
  - Status: completed (2026-07-06).

- `11.28 AI Engineer Release Readiness`
  - Goal:
    - prepare the AI Capsule Engineer feature set for a release-quality manual
      smoke pass.
  - Scope:
    - manual macOS release smoke for Capsule Analyst, scoped AI analysis, Plugin
      Auditor, Developer Mode boundary, Workspace Preview, Selected Context,
      and Hivra Engineer Advisory Ask.
    - Android smoke remains a separate release pass after macOS is stable.
    - added `docs/checklists/ai-engineer-release-smoke.md`.
    - macOS release checklist now requires AI Engineer smoke completion.
    - release discipline gate now enforces the AI Engineer smoke checklist
      exists and covers the required surfaces.
  - Verification:
    - `tools/review/release_discipline_gate.sh`
    - `tools/review/review_all.sh`
  - Status: completed (2026-07-06).

- `11.29 Application Module Boundary Cleanup`
  - Goal:
    - keep AI tooling, plugin runtime, and trading-drone orchestration modular
      without widening `AppRuntimeService` or screen-level service graphs.
  - Scope:
    - introduce a `TradingDroneModuleService` or controller boundary so
      `TradingDroneScreen` does not assemble BingX, order tracking, signal,
      credential, and plugin-host services directly.
    - introduce a `PluginRuntimeModuleService` boundary for plugin host,
      installed-plugin projection, chat/manual-consensus support, and runtime
      invocation helpers.
    - keep AI Capsule Analyst/Hivra Engineer construction behind
      `AiToolingModuleService`; `AppRuntimeService` must expose only neutral
      capsule/runtime primitives.
    - split the Capsule Analyst screen (legacy internal class:
      `CapsuleDoctorScreen`) into presentation cards/widgets after
      service boundaries stabilize; widgets must not construct feature service
      graphs.
    - add a `localOpenAiCompatible` inference provider option with explicit
      `baseUrl`, model, timeout, and no secrets in logs.
    - defer physical `flutter/lib/services` directory moves until module
      facades are stable, to avoid churn without stronger boundaries.
  - Constraints:
    - no dependency from core/engine/platform back into Flutter feature modules.
    - no AI/provider/trading/plugin-specific policy inside Core.
    - screens remain UI projection/action surfaces, not orchestration owners.
    - ledger remains the source of truth for confirmed capsule state.
  - Current progress:
    - Added `TradingDroneModuleService` so `TradingDroneScreen` no longer
      assembles BingX exchange, order tracking, signal, credential,
      execution, chat, and plugin-host service graphs directly.
    - Added `PluginRuntimeModuleService` so `WasmPluginsScreen` no longer
      assembles plugin registry/catalog, plugin host, manual-consensus, chat,
      and UI-log dependencies directly.
    - `AiToolingModuleService` remains the AI Capsule Analyst/Hivra Engineer
      construction boundary; no AI/provider/trading policy was moved into
      Core.
    - Added `localOpenAiCompatible` inference provider support:
      - local provider uses explicit secure-stored `baseUrl`,
      - API key is optional for local runtimes,
      - provider calls target OpenAI-compatible `/v1/chat/completions`,
      - UI/log output records provider id/model only, not endpoint secrets or
        key material.
    - Started the Capsule Analyst presentation split by moving reusable AI
      outbound preview and status-message panels into
      `widgets/ai_diagnostics/provider_widgets.dart`; no service wiring or runtime
      behavior moved into widgets.
    - Continued the screen split by moving Developer Workspace presentation
      widgets (engineer preview, selected context, repo tile, quick-add panel)
      into `widgets/ai_diagnostics/developer_workspace_widgets.dart`; widgets remain
      projection-only and accept data/callbacks only.
    - Moved Plugin Auditor presentation helpers (status color and audit entry
      tile) into `widgets/ai_diagnostics/plugin_audit_widgets.dart`; audit
      service ownership stays in the screen/card state and widgets remain read-only.
    - Moved shared diagnostics report presentation (header, findings, key/value
      sections, retry error state) into `widgets/ai_diagnostics/report_widgets.dart`;
      deterministic key sorting stays in the presentation boundary.
    - Added an `AiToolingModule` aggregate so the Capsule Analyst screen keeps one
      AI tooling boundary instead of individual service fields for inspection,
      chat, plugin audit, developer workspace, and engineer advisory paths.
    - Extended architecture contract gate so Capsule Analyst must keep using
      `AiToolingModuleService`, while `widgets/` cannot construct runtime/module
      service graphs.
  - Verification:
    - `tools/review/review_all.sh`
    - `flutter analyze`
    - `flutter test`
    - `cargo test --workspace`
    - macOS release smoke for Capsule Analyst, plugins, chat, and trading drone.
  - Status: completed (2026-07-07).
