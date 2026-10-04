import 'dart:async';
import 'dart:io';

import '../models/capsule_chat_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import '../models/wasm_plugin_models.dart';
import 'ai_doctor_credential_store.dart';
import 'app_runtime_service.dart';
import 'capsule_ai_runtime_service.dart';
import 'capsule_chat_delivery_service.dart';
import 'capsule_contact_label_store.dart';
import 'capsule_file_store.dart';
import 'capsule_passive_receive_coordinator.dart';
import 'capsule_scoped_secret_vault.dart';
import 'consensus_attestation_exchange_service.dart';
import 'external_effect_service.dart';
import 'manual_consensus_check_service.dart';
import 'moltbook_ambassador_configuration_store.dart';
import 'moltbook_connection_service.dart';
import 'moltbook_cycle_trigger_service.dart';
import 'moltbook_draft_store.dart';
import 'moltbook_external_effect_adapter.dart';
import 'moltbook_feed_checkpoint_store.dart';
import 'moltbook_public_bulletin_ai_service.dart';
import 'moltbook_public_change_feed_store.dart';
import 'moltbook_public_repository_source_adapter.dart';
import 'moltbook_publication_service.dart';
import 'moltbook_provider_adapter.dart';
import 'moltbook_runtime_module.dart';
import 'plugin_workspace_runtime.dart';
import 'plugin_workspace_remote_service.dart';
import 'wasm_plugin_package_preflight_service.dart';
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

class PluginRuntimeModule extends PluginWorkspaceRuntime {
  final WasmPluginSourceCatalogService sourceCatalog;
  final ManualConsensusCheckService manualChecks;
  final ConsensusAttestationExchangeService attestationExchange;
  final CapsuleChatDeliveryService chatDelivery;
  final CapsulePassiveReceivePort passiveReceive;
  final CapsuleContactLabelStore contactLabels;
  final UiEventLogService uiLog;
  final MoltbookRuntimeModule moltbook;
  final CapsuleFileStore _fileStore;
  final CapsuleScopedSecretVault _secretVault;
  final String? Function() _readActiveCapsuleRootHex;
  final PluginWorkspaceRemoteService? _providedRemote;
  late final PluginWorkspaceRemoteService _remote =
      _providedRemote ??
      PluginWorkspaceRemoteService(
        files: _fileStore,
        vault: _secretVault,
        registry: registry,
      );

  PluginRuntimeModule({
    required super.registry,
    required this.sourceCatalog,
    required this.manualChecks,
    required super.pluginHostApi,
    required this.attestationExchange,
    required this.chatDelivery,
    required this.passiveReceive,
    required this.contactLabels,
    required this.uiLog,
    required this.moltbook,
    required super.fileStore,
    required CapsuleScopedSecretVault secretVault,
    required super.readActiveCapsuleRootHex,
    super.market,
    PluginWorkspaceRemoteService? workspaceRemote,
  }) : _fileStore = fileStore,
       _providedRemote = workspaceRemote,
       _secretVault = secretVault,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       super(
         readCredentials:
             ({required owner, required pluginId}) => secretVault.loadSecret(
               capsuleHex: owner,
               pluginId: pluginId,
               providerId: 'bingx',
               accountId: 'primary',
               secretName: 'credentials',
             ),
         writeCredentials:
             ({required owner, required pluginId, required value}) =>
                 value == null
                     ? secretVault.deleteAccount(
                       capsuleHex: owner,
                       pluginId: pluginId,
                       providerId: 'bingx',
                       accountId: 'primary',
                     )
                     : secretVault.saveSecret(
                       capsuleHex: owner,
                       pluginId: pluginId,
                       providerId: 'bingx',
                       accountId: 'primary',
                       secretName: 'credentials',
                       secretValue: value,
                     ),
       );

  Future<void> removePlugin(WasmPluginRecord record) async {
    await _retireWorkspacePackage(record.pluginId, uninstall: true);
    // Stop admission first, then let in-flight continuations fail before
    // deleting state; otherwise a late write can recreate an uninstalled plugin.
    await registry.removePlugin(record.id);
    final pluginId = record.pluginId?.trim();
    if (pluginId != null && pluginId.isNotEmpty) {
      stopWorkspaceScheduling(pluginId: pluginId);
      await drainWorkspaceActions(pluginId);
      await _secretVault.deletePlugin(pluginId);
      await _fileStore.deletePluginStateFromAllCapsules(
        pluginId,
        preserveFileNames: const {
          'external_effects.v1.json',
          'workspace-execution.v1.json',
        },
      );
    }
  }

  Future<WasmPluginRecord> installPluginFromFile(File file) async {
    final inspected = await const WasmPluginPackagePreflightService().inspect(
      file,
    );
    await _retireWorkspacePackage(inspected.pluginId);
    return registry.installPluginFromFile(
      file,
      validateRecord: (record) {
        if (record.pluginId != inspected.pluginId) {
          throw StateError('Installation input changed');
        }
      },
    );
  }

  Future<WasmPluginRecord> installPluginFromSource(
    WasmPluginSourceCatalogEntry entry,
  ) => sourceCatalog.installFromSourceEntry(
    entry,
    beforeInstall: _retireWorkspacePackage,
  );

  Future<void> _retireWorkspacePackage(
    String? pluginId, {
    bool uninstall = false,
  }) async {
    final records = (await registry.loadPlugins()).where(
      (r) =>
          r.pluginId == pluginId &&
          r.contractKind == pluginWorkspaceContractKind,
    );
    if (records.isEmpty) return;
    final record = records.single;
    final root = await _fileStore.capsulesRoot();
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      final owner = entity.path.split(Platform.pathSeparator).last;
      if (entity is! Directory || !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) {
        continue;
      }
      final grant = await super.readWorkspaceExecution(
        record,
        enforceHost: false,
        ownerCapsuleHex: owner,
      );
      if (grant?['executor'] == 'vps') {
        final c = await _remote.connection(owner, record.pluginId!);
        if (c == null || c['executor_id'] != grant!['executor_id']) {
          throw StateError(
            'Reconnect the assigned VPS before updating/removing this package',
          );
        }
        final result = await _remote.request(c, 'return');
        await restoreWorkspaceFromVps(
          record: record,
          executorId: c['executor_id'] as String,
          checkpoint: Map<String, dynamic>.from(result['checkpoint'] as Map),
          ownerCapsuleHex: owner,
        );
      }
      if (uninstall) {
        final c = await _remote.connection(owner, record.pluginId!);
        if (c != null && c['package_id'] != null) {
          await _remote.uninstall(c);
        }
      }
      // Replacement never inherits the old package's execution grant, including
      // grants in inactive Capsules. The runtime rejects the old binding.
    }
    stopWorkspaceScheduling(pluginId: record.pluginId);
  }

  Future<void> connectWorkspaceVps({
    required WasmPluginRecord record,
    required String host,
    required int port,
    required String password,
    required Future<bool> Function(String) trustPeer,
  }) async {
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
    );
    if (grant?['executor'] == 'vps') {
      throw StateError('Return to online mode before reinstalling the VPS');
    }
    final binding = await registry.resolveRuntimeBinding(record.pluginId!);
    if (binding.packageId != record.id) throw StateError('Package changed');
    await _remote.connect(
      owner: owner,
      record: record,
      host: host,
      port: port,
      password: password,
      trustPeer: trustPeer,
      stillOwned: () => activeCapsuleRootHex() == owner,
    );
  }

  Future<void> useWorkspaceOnline(WasmPluginRecord record) async {
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
    );
    if (grant?['executor'] == 'vps') {
      final c = await _remote.connection(owner, record.pluginId!);
      if (c == null || c['executor_id'] != grant!['executor_id']) {
        throw StateError('Assigned VPS connection is unavailable');
      }
      final result = await _remote.request(c, 'return');
      await restoreWorkspaceFromVps(
        record: record,
        executorId: c['executor_id'] as String,
        checkpoint: Map<String, dynamic>.from(result['checkpoint'] as Map),
      );
    }
    await _remote.selectOnline(owner, record.pluginId!);
  }

  @override
  Future<Map<String, dynamic>> runWorkspaceAction({
    required WasmPluginRecord record,
    required String action,
    Map<String, dynamic> settings = const {},
    String? optionsForField,
    Map<String, String>? credentials,
    Map<String, dynamic>? approvedOrder,
    int? executionRevision,
  }) async {
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
    );
    final c = await _remote.connection(owner, record.pluginId!);
    if (grant?['executor'] == 'vps') {
      if (c == null || c['executor_id'] != grant!['executor_id']) {
        throw StateError('Assigned VPS is unavailable; no local fallback');
      }
      if (credentials != null) {
        throw StateError(
          'Return to online mode before replacing exchange credentials',
        );
      }
      // Recover a lost adoption acknowledgement with the exact frozen source
      // checkpoint. Server replay never restores older state or renews authority.
      await _remote.request(c, 'adopt', {
        'checkpoint': await releaseWorkspaceToVps(
          record,
          executorId: c['executor_id'] as String,
        ),
      });
      final result = await _remote.request(
        c,
        action == 'open' && optionsForField == null ? 'status' : 'action',
        action == 'open' && optionsForField == null
            ? const {}
            : {
              'action': action,
              'settings': settings,
              'options_field': optionsForField,
              'approved_order': approvedOrder,
            },
      );
      if (result['view'] is! Map) {
        throw StateError(
          'VPS observation unavailable; its lifecycle is not verified',
        );
      }
      if (activeCapsuleRootHex() != owner ||
          (await registry.resolveRuntimeBinding(record.pluginId!)).packageId !=
              record.id) {
        throw StateError('Capsule or package changed');
      }
      if (optionsForField != null) {
        return Map<String, dynamic>.from(result['view'] as Map);
      }
      return {
        ...Map<String, dynamic>.from(result['view'] as Map),
        'host_connection': {
          'target': 'vps',
          'host': c['host'],
          'health': result['runner']['state'],
          'observation_error': result['observation_error'],
        },
      };
    }
    final view = await super.runWorkspaceAction(
      record: record,
      action: action,
      settings: settings,
      optionsForField: optionsForField,
      credentials: credentials,
      approvedOrder: approvedOrder,
      executionRevision: executionRevision,
    );
    if (optionsForField != null) return view;
    return {
      ...view,
      'host_connection': {
        'target': c?['selected'] == true ? 'vps' : 'local',
        'host': c?['host'],
        'health': 'not_started',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> setWorkspaceExecution({
    required WasmPluginRecord record,
    required bool enabled,
    Map<String, dynamic>? approvedScope,
    Map<String, dynamic> settings = const {},
    String? releaseToExecutorId,
  }) async {
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
    );
    var c = await _remote.connection(owner, record.pluginId!);
    if (grant?['executor'] == 'vps') {
      if (c == null || c['executor_id'] != grant!['executor_id']) {
        throw StateError('Reconnect the assigned VPS');
      }
      if (!enabled) {
        await setReleasedWorkspaceEntries(
          record,
          executorId: c['executor_id'] as String,
          enabled: false,
        );
        await _remote.request(c, 'adopt', {
          'checkpoint': await releaseWorkspaceToVps(
            record,
            executorId: c['executor_id'] as String,
          ),
        });
      }
      await _remote.request(c, 'execution', {
        'enabled': enabled,
        'settings': settings,
        'scope': approvedScope,
      });
      if (enabled) {
        await setReleasedWorkspaceEntries(
          record,
          executorId: c['executor_id'] as String,
          enabled: true,
          expectedRevision: grant['revision'] as int,
        );
      }
      return runWorkspaceAction(record: record, action: 'open');
    }
    if (enabled && c?['selected'] == true) {
      c = await _remote.ensurePackage(owner, record);
      if (activeCapsuleRootHex() != owner) throw StateError('Capsule changed');
      await super.setWorkspaceExecution(
        record: record,
        enabled: true,
        approvedScope: approvedScope,
        settings: settings,
        releaseToExecutorId: c['executor_id'] as String,
      );
      final checkpoint = await releaseWorkspaceToVps(
        record,
        executorId: c['executor_id'] as String,
      );
      await _remote.request(c, 'adopt', {'checkpoint': checkpoint});
      return runWorkspaceAction(record: record, action: 'open');
    }
    return super.setWorkspaceExecution(
      record: record,
      enabled: enabled,
      approvedScope: approvedScope,
      settings: settings,
      releaseToExecutorId: releaseToExecutorId,
    );
  }

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
        final envelopeHash =
            response.result?['envelope_hash_hex']?.toString().toLowerCase() ??
            '';
        final canonicalMessageText =
            response.result?['message_text']?.toString() ?? normalizedMessage;
        final canonicalCreatedAtUtc =
            response.result?['created_at_utc']?.toString() ?? createdAtUtc;
        final CapsuleChatDeliverySendResult delivery;
        try {
          delivery = await chatDelivery.sendCanonicalEnvelopeWithTimeline(
            capsuleRootHex: operationCapsuleHex,
            peerHex: normalizedPeer,
            canonicalEnvelopeJson: canonicalEnvelopeJson,
            envelopeHashHex: envelopeHash,
            messageText: canonicalMessageText,
            createdAtUtc: canonicalCreatedAtUtc,
          );
        } catch (error) {
          await uiLog.log(
            'chat.send.timeline.error',
            'owner=$operationCapsuleHex phase=prepare error=${_safeError(error)}',
          );
          return const PluginChatSendResult(
            status: PluginChatSendStatus.failed,
            message:
                'Message was not sent because Chat history could not be saved',
          );
        }
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

  String _safeError(Object error) {
    final compact = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 240 ? compact : compact.substring(0, 240);
  }

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
  static final MoltbookCycleTriggerService _moltbookCycleTriggers =
      MoltbookCycleTriggerService();

  final AppRuntimeService runtime;
  final ExternalEffectAdapterResolver? externalEffectAdapterResolver;
  final CapsuleFileStore fileStore;

  const PluginRuntimeModuleService({
    required this.runtime,
    this.externalEffectAdapterResolver,
    this.fileStore = const CapsuleFileStore(),
  });

  PluginRuntimeModule build() {
    final activeCapsuleRootHex = runtime.activeCapsuleRootHex;
    final secretVault = CapsuleScopedSecretVault();
    final provider = MoltbookProviderAdapter();
    final connection = MoltbookConnectionService(
      fileStore: fileStore,
      secretVault: secretVault,
      observer: provider,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
    final moltbookAdapter = MoltbookExternalEffectAdapter(
      secretVault: secretVault,
      provider: provider,
    );
    final effects = ExternalEffectService(
      readActiveCapsuleRootHex: activeCapsuleRootHex,
      resolveAdapter:
          externalEffectAdapterResolver ??
          (providerId) =>
              providerId == MoltbookConnectionService.providerId
                  ? moltbookAdapter
                  : null,
      fileStore: fileStore,
    );
    final aiRuntime = CapsuleAiRuntimeService(
      credentialStore: AiDoctorCredentialStore.shared,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
    final uiLog = const UiEventLogService();
    final pluginHostApi = runtime.buildPluginHostApiService();
    final moltbook = MoltbookRuntimeModule(
      pluginHostApi: pluginHostApi,
      uiLog: uiLog,
      moltbookConnection: connection,
      moltbookDrafts: MoltbookDraftStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      moltbookFeedCheckpoint: MoltbookFeedCheckpointStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      moltbookPublications: MoltbookPublicationService(
        connection: connection,
        effects: effects,
      ),
      moltbookPublicBulletinAi: MoltbookPublicBulletinAiService(
        runtime: aiRuntime,
      ),
      moltbookPublicChanges: MoltbookPublicChangeFeedStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      moltbookCycleTriggers: _moltbookCycleTriggers,
      publicRepositorySource: MoltbookPublicRepositorySourceAdapter(),
      ambassadorConfiguration: MoltbookAmbassadorConfigurationStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
    return PluginRuntimeModule(
      registry: const WasmPluginRegistryService(),
      sourceCatalog: const WasmPluginSourceCatalogService(),
      manualChecks: runtime.buildManualConsensusCheckService(),
      pluginHostApi: pluginHostApi,
      attestationExchange: runtime.buildConsensusAttestationExchangeService(),
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
      passiveReceive: runtime.passiveReceive,
      contactLabels: runtime.buildCapsuleContactLabelStore(),
      uiLog: uiLog,
      moltbook: moltbook,
      secretVault: secretVault,
      fileStore: fileStore,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
  }
}
