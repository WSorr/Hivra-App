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
- Current progress:
  - `hivra-ffi` regression tests now cover replay-skip behavior after export/import for:
    - duplicated `InvitationAccepted` delivery (no duplicate relationship projection)
    - duplicated `InvitationRejected` delivery (no duplicate burn effects)
    - duplicated `RelationshipEstablished` delivery (no duplicate relationship facts)
    - duplicated `RelationshipBroken` delivery (no duplicate break facts)
    - replayed incoming offer for already resolved invitation (blocked)
  - Incoming delivery append now uses centralized replay guard policy (`should_skip_incoming_delivery_append`) in FFI receive path.
  - Replay policy now explicitly blocks conflicting terminal invitation replays (`Accepted/Rejected/Expired`) once invitation lineage is already resolved.
  - Added regression coverage for:
    - conflicting terminal replay skipped for resolved invitation
    - first terminal event still accepted for unresolved invitation

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
- Current progress:
  - `hivra-ffi` regression tests now explicitly cover:
    - accepted relationship survives export/import
    - broken relationship survives export/import
    - re-invite with same starter type survives export/import
    - re-invite with different starter type survives export/import
    - reverse-direction pending invitation offers survive export/import
  - Runtime ledger import now rejects inconsistent histories before bootstrap restore:
    - invalid hash chain (`ledger.verify` failure)
    - missing or malformed capsule birth anchor (`CapsuleCreated` must exist for non-empty history, be first, owner-signed, and unique)

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
- Current progress:
  - Added `docs/checklists/release-android.md` for build/verification/diagnostics/publish discipline.
  - `release_discipline_gate.sh` now validates Android checklist presence and key coverage (send/accept smoke, transport diagnostics, keystore seed validation).
  - Android checklist and gate now require packaged-artifact install verification and APK checksum verification.
  - Android checklist and gate now require publish metadata coverage (asset naming and release-notes testing-scope/limitations disclosure).

Definition of done:
- Published Android APKs install cleanly, launch, and complete basic invitation flows on real devices.
- Android release verification is part of the normal release process rather than an ad hoc side task.

### 7.1 Update Safety Blockers

Goal:
- Prevent app updates from silently changing capsule truth for existing users.

Current progress:
- Added persistence safety coverage for capsule index active-selection:
  - active capsule survives index write/read roundtrip
  - stale `active` pointers are sanitized when the referenced capsule entry is absent
- Added update-safety projection fixture coverage for the same-ledger reconstruction path:
  - repeated parse of the same `ledger.json` keeps starter/relationship/pending counters stable
  - summary pending/relationship counters stay aligned with shared invitation/relationship projection services
  - replayed offer events after terminal accept/reject remain non-pending (no pending resurrection)

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
- Current progress:
  - Legacy starter slot FFI getters (`hivra_starter_get_id/get_type/exists`) were aligned to ledger-derived slot projection (`SlotLayout::from_ledger`) instead of seed/slot-side derivation in the FFI layer.

Definition of done:
- FFI remains explicit, narrow, and predictable.

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
- Current progress:
  - Recovery flow ledger decoding now reuses shared `LedgerViewSupport` (`kindCode` / `payloadBytes`) instead of maintaining a duplicate decoder path.
  - Recovery `isGenesis` fallback and starter-occupancy checks now reuse shared projection helpers (`LedgerViewSupport.inferGenesisFromLedgerRoot`, `CapsuleLedgerSummaryParser`) instead of local event-walk policy code.
  - Runtime bootstrap owner-field decoding now reuses shared `CapsuleLedgerSummaryParser.parseBytesField` instead of a duplicated bytes32 parser inside bootstrap service.
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

### 9.2 Lineage-Derived Starter Identity

Goal:
- Move starter identity from slot-only derivation to lineage-derived derivation.

Scope:
- Replace `starter_id = H(seed || slot)` as the long-term model.
- Design and adopt a `starter_v2` derivation anchored in:
  - local seed
  - slot
  - `invitation_id`
  - `sender_pubkey`
- Keep starter birth reconstructible from ledger truth rather than hidden runtime state.
- Ensure repeated use of the same slot after burn can produce a genuinely new lineage-born starter identity.
- Define how legacy slot-only starters remain readable during migration.

Definition of done:
- New starter identity reflects both local capsule structure and invitation lineage.
- Reconstructing a capsule from ledger preserves starter ancestry without relying on transport-era shortcuts.

### 9.3 Pairwise Consensus Snapshot v1

Goal:
- Define the smallest pairwise state snapshot that two capsules can independently derive, hash, and sign the same way.

Scope:
- Build the first canonical pairwise snapshot from:
  - `schema_version`
  - `pair_roots_sorted`
  - `finalized_invitations`
  - `active_relationships`
- Use terminal invitation precedence:
  - `accepted > rejected > expired > pending`
- Keep the snapshot symmetric:
  - no sender/receiver perspective bias
  - no transport delivery artifacts
  - no local-only counters or timestamps
- Explicitly exclude local starter-state facts such as:
  - `created_count`
  - `burned_count`
  - local `active/inactive`
  because those remain capsule-local rather than pairwise-consensus facts.
- Treat richer lineage or starter-state checks as future snapshot/schema revisions rather than overloading v1.
- Current progress:
  - Added regression coverage in `consensus_processor_test.dart` to lock terminal invitation precedence in snapshot projection (`accepted > rejected > expired`).
  - Added regression coverage that local starter-only events (`StarterCreated` / `StarterBurned`) do not affect pairwise snapshot canonical JSON/hash when pairwise facts are unchanged.

Definition of done:
- A fresh pair of capsules can derive the same `pairwise consensus snapshot v1` hash from local ledger truth.
- The snapshot is small and stable enough to serve as a signed execution precondition for future smart-contract plugins.
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
- Current progress:
  - Added deterministic pre-host test-contract service for `temperature_tomorrow_liechtenstein` with manifest parsing and consensus-signable execution gate (`TemperatureTomorrowContractService`).
  - Added regression coverage for:
    - manifest validation
    - deterministic settlement hash
    - proposer/counterparty/draw outcomes
    - blocked execution when consensus is unresolved
  - Added plugin draft documentation for the first test smart-contract package (`docs/plugins/temperature_tomorrow_liechtenstein_test_plugin.md`).
  - Added `PluginDemoContractRunnerService` + WASM Plugins screen `Run Demo Settlement` dry-run action so test-contract execution can be manually exercised via consensus guard without introducing wasm runtime execution yet.
  - Added package-install preflight validation (`WasmPluginPackagePreflightService`) for `.wasm` magic/version and `.zip` manifest/module shape, wired into `WasmPluginRegistryService.installPluginFromFile` with regression coverage for malformed packages.
  - Plugin install path now carries manifest metadata (`pluginId`, `contractKind`, `capabilities`) into the local registry model so capability/contract inspection is available before wasm runtime execution exists.
  - Added capability policy boundary (`WasmPluginCapabilityPolicyService`) and wired preflight to reject unknown manifest capabilities at install-time.
  - Added deterministic `PluginHostApiService` request/response boundary (`executed` / `blocked` / `rejected`) with response hashing and guard-gated temperature contract execution as Host API v1 (no wasm runtime execution yet).
  - Added host API v1 documentation (`docs/plugins/plugin_host_api_v1.md`) and regression coverage for deterministic hash, blocked guard path, unsupported plugin/method, and invalid-args rejection.

Definition of done:
- Plugins extend transport capabilities without bypassing core rules or rewriting local truth.

## Working Rule

When tradeoffs are unclear, prefer:
1. one source of truth
2. deterministic reconstruction
3. explicit boundaries
4. fewer hidden side effects
5. release discipline over speed theater

- `9.4 Root-Scoped Pairwise Consensus Truth`
  - Current shared truth still anchors peers on transport identity, not peer root identity.
  - True root-scoped `pairwise consensus snapshot v1` cannot be derived from ledger alone until peer root identity is carried through invitation lineage and then anchored in relationship events.
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

- `9.6 Ledger-Derived Slot Projection In Flutter`
  - Core already provides deterministic slot projection via `SlotLayout::from_ledger` and `CapsuleState::from_capsule`.
  - Legacy per-slot Flutter FFI probes (`starterExists/getStarterId/getStarterType`) have been removed from the active read-path and bindings surface.
  - Keep slot projection sourced from the same ledger-derived capsule state path used by core.
  - Current progress:
    - Architecture contract gate now enforces absence of legacy per-slot starter probes in Flutter bindings (`starterExists/getStarterId/getStarterType` and `hivra_starter_get_*` symbols), preventing accidental rollback to slot-side FFI reads.

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
  - Current local/runtime behavior may auto-apply remote break immediately, especially in single-app local testing; target behavior should preserve a pending remote break until explicit acceptance.
  - Pairwise event reading should remain layered:
    - invitation events record transit/history and terminal responses
    - starter events record local anatomy only
    - relationship events remain the pairwise truth anchors used for explicit relationship mutation and future smart-contract gating
  - Current progress:
    - Added `consensus_processor_test.dart` coverage that `RelationshipBroken` blocks only the affected pairwise path (`relationship_broken` fact) while other peer paths remain signable.

- `9.8 Consensus Processor Module`
  - Keep consensus logic out of screen flows and invitation form orchestration.
  - Build a dedicated processor module that:
    - consumes ledger projections
    - computes canonical pairwise snapshots
    - reports consensus state (`match`/`mismatch`) and blocking facts
  - Current progress:
    - Added `flutter/lib/services/consensus_processor.dart` with on-demand `preview`, `signable`, and `verify` APIs over ledger-derived pairwise projections.
    - Added `flutter/lib/services/consensus_runtime_service.dart` as a read-only runtime facade that feeds the processor from exported ledger truth plus local transport identity.
    - Added `flutter/lib/services/plugin_execution_guard_service.dart` so the future plugin host can read pairwise signability as a guard input without taking on execution or screen-owned consensus logic.
    - Added `flutter/lib/services/manual_consensus_check_service.dart` so Ledger Inspector can consume a read-only manual consensus-check use case instead of building pairwise preview state directly.
    - Ledger Inspector screen no longer imports `consensus_runtime_service.dart` directly; consensus rows are typed/read through `ManualConsensusCheckService` boundary.
    - Removed the legacy `PairwiseSnapshotService` wrapper after moving inspector/guard readers onto shared consensus boundaries.
    - Added processor regression coverage for canonical hash derivation, pending-invitation blocking facts, and verification mismatch reporting.
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

- `9.9 UI-FFI Boundary Reduction`
  - Reduce direct `HivraBindings` imports in UI screens by moving operational calls into service/facade boundaries.
  - Baseline at start:
    - `12` screens import `HivraBindings` directly
    - `7` services import `HivraBindings` directly
  - Current snapshot:
    - `0` screens import `HivraBindings` directly
    - `13` services import `HivraBindings` directly (explicit allowlist in review gate)
    - `FirstLaunchService` no longer imports `HivraBindings`; it now consumes `CapsuleDraftRuntime` boundary with `HivraCapsuleDraftRuntime` adapter at FFI layer
    - `SettingsService` no longer imports `HivraBindings`; it now consumes read-only runtime boundaries injected from `AppRuntimeService`
    - UI entrypoint `main.dart` no longer imports `HivraBindings` directly
    - review gate also protects `widgets/` and `utils/` from direct `HivraBindings` imports
    - `tools/review/ui_ffi_boundary_gate.sh` now enforces a service-level import budget and fails if new service files add direct `HivraBindings` ownership outside the allowlist
  - Prioritize extracting read-only screens and backup/recovery orchestration first.
  - Definition of done for this slice:
    - screens depend on application services/facades, not raw FFI bindings
    - FFI access is concentrated in a smaller boundary layer with explicit ownership
