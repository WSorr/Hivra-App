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

2.0 design constraints also include:

- separate Genesis/Proto birth mode from Leaf/Relay runtime role;
- keep 1.x on Neste;
- introduce Hood only as a fully isolated experimental network across ledger,
  slots, operational stores, drone state, delivery queues, and consensus
  evidence.

The first active item is `V2-0`. No 2.0 runtime implementation starts before
the blueprint design exit criteria are satisfied.

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

### 9.3 Pairwise Consensus Snapshot v2

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
- Snapshot v2 excludes terminal invitation history from the signed payload so
  that one-sided historical delivery and events involving third capsules cannot
  change an A<->B attestation. Existing v1 attestations naturally become
  inapplicable because the snapshot hash changes.

Definition of done:
- A fresh pair of capsules can derive the same `pairwise consensus snapshot v2` hash from local ledger truth.
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
    - pass 2 (two-party signed Pair Consensus) is next.
      - 2a completed on 2026-07-10: signature-set verification now fails
        closed without a cryptographic verifier, and production runtime wires
        the existing root Ed25519 verification adapter.
      - 2b completed on 2026-07-10: canonical domain-separated pair
        attestation commitments are symmetric and validated, and the FFI
        exposes fixed-size root signing without exposing seed/private key
        material to Flutter.
      - 2c completed on 2026-07-10: pair attestations now have a dedicated
        host transport kind, Flutter worker bindings, a capsule-scoped
        `pair_consensus_attestations.json` store, and receive orchestration
        that recomputes commitments and verifies root signatures before merge.
      - 2d completed on 2026-07-10: pair-scoped plugin host runtime-hook
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
        - route relationship-notification receive through the same policy.
        - expose degraded-transport status in UI instead of only returning
          service-level cooldown errors.
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
      - this intentionally does not close execution-order item 4: the current
        outbox is still an aggregate recovery index and must gain event-scoped
        identifiers and matching receipts before it can be a reliable queue.
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
  - Status: active.

## Planned Product Tracks

- `13.1 AI-Assisted Trading Analysis`
  - Goal:
    - connect the existing Capsule Analyst/Hivra Engineer AI tooling to the
      Trading Drone as an advisory analysis layer.
  - Boundary:
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
