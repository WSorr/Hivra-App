import 'dart:async';

import '../models/capsule_chat_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import 'app_runtime_service.dart';
import 'capsule_chat_delivery_service.dart';
import 'consensus_attestation_exchange_service.dart';
import 'manual_consensus_check_service.dart';
import 'plugin_host_api_service.dart';
import 'ui_event_log_service.dart';
import 'wasm_plugin_registry_service.dart';
import 'wasm_plugin_source_catalog_service.dart';

enum PluginChatSendStatus {
  sent,
  syncing,
  blocked,
  rejected,
  failed,
  capsuleChanged,
}

class PluginChatSendResult {
  final PluginChatSendStatus status;
  final String message;
  final PluginHostApiResponse? hostResponse;
  final CapsuleChatDeliverySendResult? delivery;

  const PluginChatSendResult({
    required this.status,
    required this.message,
    this.hostResponse,
    this.delivery,
  });

  bool get isSuccess => status == PluginChatSendStatus.sent;
}

class PluginRuntimeModule {
  final WasmPluginRegistryService registry;
  final WasmPluginSourceCatalogService sourceCatalog;
  final ManualConsensusCheckService manualChecks;
  final PluginHostApiService pluginHostApi;
  final ConsensusAttestationExchangeService attestationExchange;
  final CapsuleChatDeliveryService chatDelivery;
  final UiEventLogService uiLog;
  final String? Function() _readActiveCapsuleRootHex;

  const PluginRuntimeModule({
    required this.registry,
    required this.sourceCatalog,
    required this.manualChecks,
    required this.pluginHostApi,
    required this.attestationExchange,
    required this.chatDelivery,
    required this.uiLog,
    required String? Function() readActiveCapsuleRootHex,
  }) : _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  Future<PluginChatSendResult> sendChatMessage({
    required String peerHex,
    required String messageText,
  }) async {
    final normalizedPeer = peerHex.trim().toLowerCase();
    final normalizedMessage = messageText.trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedPeer)) {
      return const PluginChatSendResult(
        status: PluginChatSendStatus.rejected,
        message: 'Choose a valid consensus peer before sending',
      );
    }
    if (normalizedMessage.isEmpty) {
      return const PluginChatSendResult(
        status: PluginChatSendStatus.rejected,
        message: 'Message text cannot be empty',
      );
    }

    final operationCapsuleHex =
        _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (operationCapsuleHex == null || operationCapsuleHex.length != 64) {
      return const PluginChatSendResult(
        status: PluginChatSendStatus.failed,
        message: 'Active capsule identity is unavailable',
      );
    }

    await uiLog.log(
      'chat.send.request',
      'owner=$operationCapsuleHex peer=${normalizedPeer.substring(0, 8)}.. '
          'fullPeer=$normalizedPeer textBytes=${normalizedMessage.length}',
    );
    final attestation = await attestationExchange.ensureForPeer(normalizedPeer);
    await uiLog.log(
      'chat.attestation.ensure',
      'owner=$operationCapsuleHex peer=${normalizedPeer.substring(0, 8)}.. '
          'status=${attestation.status.name} '
          'receive=${attestation.receiveCode}/${attestation.receivedCount}/${attestation.storedCount} '
          'mismatch=${attestation.mismatchedEvidenceCount} '
          'sent=${attestation.localEvidenceSent} send=${attestation.sendCode ?? "-"}',
    );
    if (!_isStillOwnedBy(operationCapsuleHex)) {
      return _capsuleChanged(operationCapsuleHex);
    }
    if (!attestation.isReady) {
      return PluginChatSendResult(
        status:
            attestation.status == ConsensusAttestationExchangeStatus.syncing
                ? PluginChatSendStatus.syncing
                : PluginChatSendStatus.blocked,
        message:
            attestation.message ?? 'Pair consensus attestation is not ready',
      );
    }

    final createdAtUtc = DateTime.now().toUtc().toIso8601String();
    final response = await pluginHostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: capsuleChatPluginId,
        method: postCapsuleChatMethod,
        args: <String, dynamic>{
          'peer_hex': normalizedPeer,
          'client_message_id': 'ui-${DateTime.now().microsecondsSinceEpoch}',
          'message_text': normalizedMessage,
          'created_at_utc': createdAtUtc,
        },
      ),
    );
    if (!_isStillOwnedBy(operationCapsuleHex)) {
      return _capsuleChanged(operationCapsuleHex, hostResponse: response);
    }

    switch (response.status) {
      case PluginHostApiStatus.executed:
        final canonicalEnvelopeJson =
            response.result?['canonical_envelope_json']?.toString() ?? '';
        final delivery = await chatDelivery.sendCanonicalEnvelope(
          peerHex: normalizedPeer,
          canonicalEnvelopeJson: canonicalEnvelopeJson,
          expectedCapsuleRootHex: operationCapsuleHex,
        );
        if (!delivery.isSuccess) {
          await uiLog.log(
            'chat.send.transport.error',
            'owner=$operationCapsuleHex code=${delivery.code} '
                'blocked=${delivery.blockedByConsensus} '
                'deliveryPeer=${delivery.deliveryPeerHex ?? "none"} '
                'message=${delivery.errorMessage ?? "unknown"}',
          );
          return PluginChatSendResult(
            status: PluginChatSendStatus.failed,
            message:
                delivery.errorMessage ??
                'Chat transport failed (code ${delivery.code})',
            hostResponse: response,
            delivery: delivery,
          );
        }
        final envelopeHash =
            response.result?['envelope_hash_hex']?.toString() ?? '';
        final shortHash =
            envelopeHash.length >= 12
                ? '${envelopeHash.substring(0, 12)}..'
                : envelopeHash;
        await uiLog.log(
          'chat.send.success',
          'owner=$operationCapsuleHex peer=${normalizedPeer.substring(0, 8)}.. '
              'deliveryPeer=${delivery.deliveryPeerHex ?? "none"} '
              'receipts=${delivery.deliveryReceiptCount} '
              'hash=${shortHash.isEmpty ? "none" : shortHash} '
              'source=${response.executionSource}',
        );
        return PluginChatSendResult(
          status: PluginChatSendStatus.sent,
          message: 'Message sent${shortHash.isEmpty ? "" : " · $shortHash"}',
          hostResponse: response,
          delivery: delivery,
        );
      case PluginHostApiStatus.blocked:
        final message =
            response.blockingFacts.isEmpty
                ? 'Consensus guard blocked execution'
                : response.blockingFacts.first.label;
        await uiLog.log('chat.send.blocked', message);
        return PluginChatSendResult(
          status: PluginChatSendStatus.blocked,
          message: message,
          hostResponse: response,
        );
      case PluginHostApiStatus.rejected:
        final message = response.errorMessage ?? 'Chat request rejected';
        await uiLog.log(
          'chat.send.rejected',
          '$message code=${response.errorCode ?? "none"}',
        );
        return PluginChatSendResult(
          status: PluginChatSendStatus.rejected,
          message: message,
          hostResponse: response,
        );
    }
  }

  bool _isStillOwnedBy(String operationCapsuleHex) =>
      _readActiveCapsuleRootHex()?.trim().toLowerCase() == operationCapsuleHex;

  PluginChatSendResult _capsuleChanged(
    String operationCapsuleHex, {
    PluginHostApiResponse? hostResponse,
  }) {
    final activeCapsuleHex = _readActiveCapsuleRootHex() ?? 'none';
    unawaited(
      uiLog.log(
        'chat.send.aborted',
        'reason=capsule_changed owner=$operationCapsuleHex active=$activeCapsuleHex',
      ),
    );
    return PluginChatSendResult(
      status: PluginChatSendStatus.capsuleChanged,
      message: 'Message not sent because the active capsule changed',
      hostResponse: hostResponse,
    );
  }
}

class PluginRuntimeModuleService {
  final AppRuntimeService runtime;

  const PluginRuntimeModuleService({required this.runtime});

  PluginRuntimeModule build() {
    return PluginRuntimeModule(
      registry: const WasmPluginRegistryService(),
      sourceCatalog: const WasmPluginSourceCatalogService(),
      manualChecks: runtime.buildManualConsensusCheckService(),
      pluginHostApi: runtime.buildPluginHostApiService(),
      attestationExchange: runtime.buildConsensusAttestationExchangeService(),
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
      uiLog: const UiEventLogService(),
      readActiveCapsuleRootHex: runtime.activeCapsuleRootHex,
    );
  }
}
