import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../ffi/app_runtime_runtime.dart';
import '../models/capsule_chat_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_address_service.dart';
import 'capsule_contact_label_store.dart';
import 'capsule_diagnostics_service.dart';
import 'capsule_delivery_lifecycle_service.dart';
import 'capsule_state_manager.dart';
import 'capsule_chat_delivery_service.dart';
import 'capsule_passive_receive_coordinator.dart';
import 'consensus_attested_guard_service.dart';
import 'consensus_attestation_exchange_service.dart';
import 'consensus_attestation_sync_service.dart';
import 'consensus_runtime_service.dart';
import 'invitation_actions_service.dart';
import 'invitation_delivery_service.dart';
import 'invitation_intent_handler.dart';
import 'ledger_view_service.dart';
import 'manual_consensus_check_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';
import 'plugin_host_api_service.dart';
import 'wasm_plugin_registry_service.dart';
import 'wasm_plugin_runtime_service.dart';

class AppRuntimeService {
  final AppRuntimeRuntime _runtime;
  late final CapsuleStateManager _stateManager;
  late final CapsuleDeliveryLifecycleService _deliveryLifecycle;
  late final InvitationActionsService _invitationActions;
  late final InvitationIntentHandler _invitationIntents;
  late final LedgerViewService _ledgerView;
  late final ConsensusAttestationSyncService _consensusAttestations;
  late final ConsensusAttestationExchangeService _attestationExchange;
  late final CapsuleChatDeliveryService _chatDelivery;
  int _lastChatMessageMicros = 0;
  late final CapsulePassiveReceiveCoordinator _passiveReceive;

  AppRuntimeService({AppRuntimeRuntime? runtime})
    : _runtime = runtime ?? HivraAppRuntimeRuntime() {
    _ledgerView = LedgerViewService(runtime: _runtime.ledgerViewRuntime);
    _stateManager = CapsuleStateManager(_ledgerView);
    final addressBook = CapsuleAddressService(
      runtime: _runtime.capsuleAddressRuntime,
    );
    _deliveryLifecycle = CapsuleDeliveryLifecycleService(
      retryRunner:
          (capsuleHex, item) => _invitationActions.retryPendingDelivery(
            capsuleHex: capsuleHex,
            item: item,
          ),
    );
    _invitationActions = InvitationActionsService(
      runtime: _runtime.invitationActionsRuntime,
      deliveryLifecycle: _deliveryLifecycle,
      readOwnCardSignature: () async {
        final card = await addressBook.buildOwnCard();
        final signatureHex = card?.signatureHex;
        if (signatureHex == null || signatureHex.length != 128) return null;
        try {
          final bytes = <int>[];
          for (var i = 0; i < signatureHex.length; i += 2) {
            bytes.add(int.parse(signatureHex.substring(i, i + 2), radix: 16));
          }
          return Uint8List.fromList(bytes);
        } catch (_) {
          return null;
        }
      },
    );
    _invitationIntents = InvitationIntentHandler(
      actions: _invitationActions,
      delivery: const InvitationDeliveryService(),
      stateManager: _stateManager,
      ledgerView: _ledgerView,
    );
    _consensusAttestations = ConsensusAttestationSyncService(
      runtime: _runtime,
      consensus: buildConsensusRuntimeService(),
    );
    _attestationExchange = ConsensusAttestationExchangeService(
      sync: _consensusAttestations,
      loadRelationships: _ledgerView.loadRelationships,
      loadInvitations: _ledgerView.loadInvitations,
      listTrustedCards: addressBook.listTrustedCards,
    );
    _chatDelivery = CapsuleChatDeliveryService(
      runtime: _runtime,
      manualChecks: buildManualConsensusCheckService(),
      readAttestedSignable: buildConsensusAttestedGuardService().signable,
      loadRelationships: _ledgerView.loadRelationships,
      loadInvitations: _ledgerView.loadInvitations,
      listTrustedCards: addressBook.listTrustedCards,
    );
    _passiveReceive = CapsulePassiveReceiveCoordinator(
      invitations: _invitationIntents,
      attestations: _consensusAttestations,
      chat: _chatDelivery,
      postProjection:
          (result) => _attestationExchange.answerAcceptedEvidence(
            result.attestations.acceptedEvidence,
          ),
    );
  }

  CapsuleStateManager get stateManager => _stateManager;
  InvitationIntentHandler get invitationIntents => _invitationIntents;
  LedgerViewService get ledgerView => _ledgerView;
  CapsuleDeliveryLifecycleService get deliveryLifecycle => _deliveryLifecycle;
  CapsulePassiveReceiveCoordinator get passiveReceive => _passiveReceive;

  Future<bool> bootstrapActiveCapsuleRuntime() {
    return _runtime.bootstrapActiveCapsuleRuntime();
  }

  Future<void> persistLedgerSnapshot() {
    return _runtime.persistLedgerSnapshot();
  }

  Uint8List? capsuleRootPublicKey() => _runtime.capsuleRootPublicKey();
  Uint8List? capsuleNostrPublicKey() => _runtime.capsuleNostrPublicKey();
  String? exportLedger() => _runtime.exportLedger();

  String? projectHistoryViewV1(String ledgerJson, String requestJson) =>
      _runtime.ledgerViewRuntime.projectHistoryViewV1(ledgerJson, requestJson);

  String? activeCapsuleRootHex() {
    final stateKey = _stateManager.state.publicKey;
    if (stateKey.length == 32) {
      return _hex(stateKey);
    }
    final root = _runtime.capsuleRootPublicKey();
    if (root == null || root.length != 32) return null;
    return _hex(root);
  }

  ConsensusRuntimeService buildConsensusRuntimeService() {
    return ConsensusRuntimeService(
      exportLedger: _runtime.exportLedger,
      readLocalTransportKey: _runtime.capsuleNostrPublicKey,
      readLocalRootKey: _runtime.capsuleRootPublicKey,
      projectPairView:
          (ledgerJson, localTransportKey) =>
              _runtime.ledgerViewRuntime.projectPairViewV1(
                ledgerJson,
                localTransportPublicKey: localTransportKey,
              ),
      verifySignature: _runtime.verifyConsensusSignature,
    );
  }

  ManualConsensusCheckService buildManualConsensusCheckService() {
    final consensus = buildConsensusRuntimeService();
    return ManualConsensusCheckService(
      consensus: consensus,
      attestedGuard: ConsensusAttestedGuardService(
        consensus: consensus,
        attestations: _consensusAttestations,
      ),
    );
  }

  ConsensusAttestedGuardService buildConsensusAttestedGuardService() {
    final consensus = buildConsensusRuntimeService();
    return ConsensusAttestedGuardService(
      consensus: consensus,
      attestations: _consensusAttestations,
    );
  }

  ConsensusAttestationExchangeService
  buildConsensusAttestationExchangeService() {
    return _attestationExchange;
  }

  CapsuleDiagnosticsService buildCapsuleDiagnosticsService() {
    return CapsuleDiagnosticsService(
      diagnoseBootstrap: _runtime.diagnoseBootstrapReport,
      diagnoseTrace: _runtime.diagnoseCapsuleTraces,
    );
  }

  CapsuleChatDeliveryService buildCapsuleChatDeliveryService() {
    return _chatDelivery;
  }

  Future<CapsuleChatSendResult> sendChatMessage({
    required String peerHex,
    required String messageText,
  }) async {
    final owner = activeCapsuleRootHex();
    final peer = peerHex.trim().toLowerCase();
    final message = messageText.trim();
    if (owner == null ||
        peer == owner ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(peer)) {
      return const CapsuleChatSendResult(
        status: CapsuleChatSendStatus.rejected,
        message: 'Choose a trusted Capsule before sending.',
      );
    }
    final messageBytes = utf8.encode(message).length;
    if (messageBytes == 0 || messageBytes > 1024) {
      return const CapsuleChatSendResult(
        status: CapsuleChatSendStatus.rejected,
        message: 'Enter a message of 1 to 1024 UTF-8 bytes.',
      );
    }

    const changed = CapsuleChatSendResult(
      status: CapsuleChatSendStatus.capsuleChanged,
      message: 'The active Capsule changed.',
    );
    try {
      final attestation = await buildConsensusAttestationExchangeService()
          .ensureForPeer(peer);
      if (activeCapsuleRootHex() != owner) return changed;
      if (!attestation.isReady) {
        return CapsuleChatSendResult(
          status:
              attestation.status == ConsensusAttestationExchangeStatus.syncing
                  ? CapsuleChatSendStatus.syncing
                  : CapsuleChatSendStatus.blocked,
          message: attestation.message ?? 'Verify this relationship to send.',
        );
      }

      final now = DateTime.now().toUtc();
      final micros = now.microsecondsSinceEpoch;
      _lastChatMessageMicros =
          micros > _lastChatMessageMicros ? micros : _lastChatMessageMicros + 1;
      final createdAt = now.toIso8601String();
      // Retain the v1 wire fields and ordering for peers on earlier builds.
      final envelope = jsonEncode({
        'schema_version': 1,
        'plugin_id': capsuleChatPluginId,
        'contract_kind': 'capsule_chat_direct',
        'peer_hex': peer,
        'client_message_id': 'ui-$_lastChatMessageMicros',
        'message_text': message,
        'created_at_utc': createdAt,
      });
      final guard = buildConsensusAttestedGuardService();
      final delivery = await buildCapsuleChatDeliveryService()
          .sendCanonicalEnvelopeWithTimeline(
            capsuleRootHex: owner,
            peerHex: peer,
            canonicalEnvelopeJson: envelope,
            envelopeHashHex: sha256.convert(utf8.encode(envelope)).toString(),
            messageText: message,
            createdAtUtc: createdAt,
            authorize: () async {
              if (activeCapsuleRootHex() != owner ||
                  !(await guard.signable(peer)).isSignable ||
                  activeCapsuleRootHex() != owner) {
                throw StateError('Chat authorization changed');
              }
            },
          );
      if (activeCapsuleRootHex() != owner) return changed;
      if (delivery.isSuccess) {
        return const CapsuleChatSendResult(
          status: CapsuleChatSendStatus.sent,
          message: 'Accepted by transport',
        );
      }
      return CapsuleChatSendResult(
        status:
            delivery.blockedByConsensus
                ? CapsuleChatSendStatus.blocked
                : CapsuleChatSendStatus.failed,
        message: delivery.errorMessage ?? 'Could not send the message.',
      );
    } catch (_) {
      if (activeCapsuleRootHex() != owner) return changed;
      return const CapsuleChatSendResult(
        status: CapsuleChatSendStatus.failed,
        message: 'Could not verify this conversation or save the message.',
      );
    }
  }

  CapsuleAddressService buildCapsuleAddressService() {
    return CapsuleAddressService(runtime: _runtime.capsuleAddressRuntime);
  }

  CapsuleContactLabelStore buildCapsuleContactLabelStore() {
    return CapsuleContactLabelStore(
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
  }

  PluginHostApiService buildPluginHostApiService() {
    final wasmRuntime = WasmPluginRuntimeService(
      invokeJson: _runtime.invokeWasmJson,
    );
    return PluginHostApiService(
      handlers: const [],
      resolveRuntimeBinding:
          const WasmPluginRegistryService().resolveRuntimeBinding,
      resolveRuntimeInvoke:
          (request, binding) =>
              wasmRuntime.invoke(request: request, binding: binding),
    );
  }

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  RelationshipService buildRelationshipService({String? activeCapsuleHex}) {
    return RelationshipService(
      loadRelationshipGroups: _ledgerView.loadRelationshipGroups,
      breakRelationship: _runtime.breakRelationship,
      breakRelationshipWithReference:
          _runtime.breakRelationshipWithDeliveryReference,
      persistLedgerSnapshot: _runtime.persistLedgerSnapshot,
      deliveryLifecycle: _deliveryLifecycle,
      activeCapsuleHex: activeCapsuleHex,
    );
  }

  SettingsService buildSettingsService() {
    final contactCards = CapsuleAddressService(
      runtime: _runtime.capsuleAddressRuntime,
    );
    return SettingsService(
      loadIsNeste: () => _stateManager.state.isNeste,
      loadSeed: _runtime.loadSeed,
      buildOwnCard: contactCards.buildOwnCard,
      exportOwnCardJson: contactCards.exportOwnCardJson,
      contactCards: contactCards,
      contactLabels: buildCapsuleContactLabelStore(),
    );
  }
}
