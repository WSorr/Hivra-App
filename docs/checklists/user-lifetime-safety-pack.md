# User Lifetime Safety Pack

Use this checklist to validate continuity of one or two Capsules across ordinary
use, interruption, update and recovery on the declared runtime matrix.

Run it on the release candidate build.

This is the sole end-to-end product-completion checklist. Platform packaging
details remain in the macOS and Android release checklists, and capability-
specific depth remains in their existing smoke checklists. Do not create a
second journey checklist.

Follow the required matrix in `docs/development-control.md`. Optional Intel and
separate macOS-profile evidence do not determine PASS/PENDING. Use bounded
restart/retry exercises and automated clock/event cases instead of calendar-ageing
waits.

## Scope

- [ ] Test includes one main capsule and one peer capsule (max two capsules in scope).
- [ ] Isolate test Capsule state; record reused package registries/credential
      stores without claiming an OS-clean account. Android uses the environment
      in `release-android.md`.
- [ ] The exact packaged macOS and Android artifacts, source commit, build tag,
      and clean-source metadata are recorded before the journey begins.

## Scenario 0: Packaged Install And Clean Launch

- [ ] Install the packaged release artifacts on the declared runtime matrix;
      do not substitute a debug or build-tree launch.
- [ ] On macOS, reach the selector and create/import only isolated test Capsules
      in the current account; existing working Capsules remain unchanged.
- [ ] On an empty Android Emulator runtime, first launch reaches an explicit
      create/recover choice without inherited Capsule, credential, plugin or
      OS-backup state. Relaunch before creation preserves that empty state and
      does not synthesize identity or history.

## Scenario 1: First Capsule Birth

- [ ] Create first capsule and verify app reaches normal starters/invitations/relationships screens.
- [ ] Close and relaunch app.
- [ ] Same capsule is selected and header counters remain stable.

## Scenario 2: First Relationship

- [ ] Create or recover second capsule.
- [ ] Exchange or import the exact trusted contact/address evidence used by the
      invitation path; no global discovery or root-key-as-transport fallback is
      accepted.
- [ ] Send invitation from capsule A to capsule B.
- [ ] Accept on capsule B and verify relationship appears on both capsules after receive/switch.
- [ ] No self-invite artifacts appear as pending on sender.

## Scenario 2A: Pair Consensus And Chat Continuity

- [ ] Verify the established pair becomes signable only for the exact two
      Capsule roots and matching attestation snapshot.
- [ ] Send one chat message in each direction and confirm sender, recipient,
      Capsule scope, and message identity remain bound after receive.
- [ ] Restart both runtimes, receive again, and confirm no duplicate message,
      cross-Capsule delivery, or stale pair-attestation acceptance appears.
- [ ] Break the relationship and verify pair-scoped consensus and new chat
      effects fail closed until a new valid relationship episode exists.

## Scenario 2B: Plugin Lifecycle And Isolation

- [ ] Install one reviewed plugin package through the canonical catalog/package
      path and execute one declared method through the WASM host.
- [ ] Restart the app and confirm the same active package/version and
      Capsule-scoped plugin state are projected without duplicate installation.
- [ ] Update or reinstall the same plugin id and confirm exactly one active
      package remains; failed update preserves the previous active package.
- [ ] Remove the plugin and confirm its package and Capsule-scoped secrets/state
      are removed through the canonical lifecycle.
- [ ] Complete the existing Moltbook smoke checklist separately when Moltbook is
      included in the named release candidate.

## Scenario 3: Recovery On New Device Path

- [ ] Export backup for capsule A.
- [ ] Confirm the exported full backup is authenticated envelope v3 and does not
      expose plaintext Ledger owner/events.
- [ ] Recover Capsule A using seed + backup into an empty Capsule destination.
      A new destination, or a test Capsule removed through the product after
      preserving backup/seed, suffices. Record reused platform state and preserve
      other Capsules. Android also exercises empty-runtime recovery under
      `release-android.md`.
- [ ] Confirm wrong-seed and tampered-backup recovery fail closed.
- [ ] Recovered capsule shows the same ledger truth (starters, relationships, pending counts) as before recovery.
- [ ] Android fresh install/profile receives no private Capsule state from OS
      Auto Backup or device transfer before explicit authenticated recovery.

## Scenario 4: Update Truth Preservation

- [ ] Keep capsule data from previous build.
- [ ] Launch new build on same data.
- [ ] Same ledger reconstructs the same visible truth.
- [ ] Previously resolved invitations do not reappear as pending.
- [ ] Deleting a capsule in canonical storage does not get silently undone by legacy-container migration on next launch.

## Scenario 4A: macOS Runtime Storage Migration

Run affected cases for migration/index/legacy-path changes; keep automated
fixtures for unchanged code. A separate OS account is optional. Never inject
faults into working Capsule storage.

- [ ] Start with a previous-build capsule under `~/Documents/Hivra/capsules`.
- [ ] Launch the update and verify capsule runtime is copied to `~/Library/Application Support/Hivra` with matching files and ledger truth.
- [ ] Verify `Backups` and `Ledger Exports` remain user-visible under `~/Documents/Hivra`.
- [ ] Relaunch after deleting or changing the old runtime copy and verify it is not imported again.
- [ ] Simulate an unavailable/offloaded old source and verify the app fails closed with recovery actions instead of opening first launch.
- [ ] Corrupt `capsules_index.json` while keeping valid capsule directories and verify the index is repaired from those directories.
- [ ] Corrupt the index with no recoverable capsule directories and verify the corrupt index is preserved and an explicit error is shown.

## Scenario 5: Long-Pending Invitation Stability

- [ ] Create one pending invitation and leave it unresolved.
- [ ] After restart/switch, invitation state is still coherent (no duplicate lineage or phantom pending rows).
- [ ] Timeout/burn behavior follows specification once terminal event is appended;
      verify time-dependent semantics with automated controlled-time/event cases,
      without a calendar-ageing wait for each release candidate.

## Scenario 5A: Cross-Platform Restart And Capsule Isolation

- [ ] On both macOS and Android, switch A -> B -> A and verify Ledger,
      relationships, chat, plugin state, credentials, and diagnostics remain
      scoped to the selected Capsule.
- [ ] Pause/close during receive or another in-flight operation, relaunch, and
      verify stale completion cannot overwrite the newly selected Capsule.
- [ ] Android restart keeps seed material in the active profile's app-private
      keystore path; macOS switching produces no Keychain prompt storm.
- [ ] Transport degradation remains visible in diagnostics and manual retry
      re-enters the canonical receive/delivery lifecycle without a second loop.

## Automated Readiness Evidence

This table maps the journey to existing owners and regression evidence. It does
not replace packaged-artifact execution.

| Journey segment | Existing owner | Automated evidence |
| --- | --- | --- |
| Birth and bootstrap | `FirstLaunchService`, `CapsuleRuntimeBootstrapService` | `flutter/test/first_launch_service_test.dart`, `flutter/test/capsule_runtime_bootstrap_service_test.dart` |
| Selection and isolation | `CapsuleSelectorService`, `CapsuleStateManager` | `flutter/test/capsule_selector_service_test.dart`, `flutter/test/capsule_state_manager_test.dart`, `flutter/test/capsule_index_store_test.dart` |
| Contacts and relationships | `CapsuleAddressService`, Core relationship projection | `flutter/test/capsule_address_service_test.dart`, `flutter/test/relationship_service_test.dart`, `core/hivra-core/src/relationship.rs` |
| Invitations and delivery | `InvitationIntentHandler`, `InvitationActionsService`, delivery lifecycle | `flutter/test/invitation_intent_handler_test.dart`, `flutter/test/invitation_actions_service_test.dart`, `flutter/test/invitation_delivery_service_test.dart` |
| Pair consensus | Core `PairView`, `ConsensusRuntimeService`, attestation exchange | `flutter/test/consensus_runtime_service_test.dart`, `flutter/test/consensus_attestation_exchange_service_test.dart`, `core/hivra-core/src/pair.rs` |
| Chat | `CapsuleChatDeliveryService`, canonical ingress | `flutter/test/capsule_chat_delivery_service_test.dart`, `platform/hivra-ffi/src/chat_api.rs` |
| Plugin lifecycle | `WasmPluginRegistryService`, execution guard, WASM host | `flutter/test/wasm_plugin_registry_service_test.dart`, `flutter/test/plugin_execution_guard_service_test.dart`, `flutter/test/wasm_plugin_runtime_service_test.dart` |
| Recovery and update | `RecoveryService`, backup codec, bootstrap/persistence | `flutter/test/recovery_service_test.dart`, `flutter/test/capsule_backup_codec_test.dart`, `flutter/test/capsule_file_store_test.dart` |
| Restart and transport diagnostics | passive receive coordinator, transport health policy | `flutter/test/capsule_passive_receive_coordinator_test.dart`, `flutter/test/transport_health_policy_service_test.dart`, `flutter/test/capsule_diagnostics_service_test.dart` |
