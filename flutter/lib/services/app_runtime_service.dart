import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../ffi/app_runtime_runtime.dart';
import '../models/plugin_host_api_models.dart';
import '../models/wasm_plugin_models.dart';
import 'bingx_futures_credential_store.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_order_tracking_store.dart';
import 'capsule_address_service.dart';
import 'capsule_diagnostics_service.dart';
import 'capsule_state_manager.dart';
import 'capsule_chat_delivery_service.dart';
import 'consensus_runtime_service.dart';
import 'invitation_actions_service.dart';
import 'invitation_delivery_service.dart';
import 'invitation_intent_handler.dart';
import 'ledger_view_service.dart';
import 'manual_consensus_check_service.dart';
import 'plugin_execution_guard_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';
import 'plugin_host_api_service.dart';
import 'plugin_contract_handlers.dart';
import 'plugin_host_contract_handler.dart';
import 'wasm_plugin_registry_service.dart';
import 'wasm_plugin_runtime_service.dart';

class AppRuntimeService {
  final AppRuntimeRuntime _runtime;
  late final CapsuleStateManager _stateManager;
  late final InvitationActionsService _invitationActions;
  late final InvitationIntentHandler _invitationIntents;
  late final LedgerViewService _ledgerView;

  AppRuntimeService({
    AppRuntimeRuntime? runtime,
  }) : _runtime = runtime ?? HivraAppRuntimeRuntime() {
    _ledgerView = LedgerViewService(runtime: _runtime.ledgerViewRuntime);
    _stateManager = CapsuleStateManager(_ledgerView);
    _invitationActions = InvitationActionsService(
      runtime: _runtime.invitationActionsRuntime,
    );
    _invitationIntents = InvitationIntentHandler(
      actions: _invitationActions,
      delivery: const InvitationDeliveryService(),
      stateManager: _stateManager,
      ledgerView: _ledgerView,
    );
  }

  CapsuleStateManager get stateManager => _stateManager;
  InvitationIntentHandler get invitationIntents => _invitationIntents;
  LedgerViewService get ledgerView => _ledgerView;

  Future<bool> bootstrapActiveCapsuleRuntime() {
    return _runtime.bootstrapActiveCapsuleRuntime();
  }

  Future<void> persistLedgerSnapshot() {
    return _runtime.persistLedgerSnapshot();
  }

  Uint8List? capsuleRootPublicKey() => _runtime.capsuleRootPublicKey();
  Uint8List? capsuleNostrPublicKey() => _runtime.capsuleNostrPublicKey();
  String? exportLedger() => _runtime.exportLedger();

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
    );
  }

  PluginExecutionGuardService buildPluginExecutionGuardService() {
    return PluginExecutionGuardService(
      consensus: buildConsensusRuntimeService(),
    );
  }

  ManualConsensusCheckService buildManualConsensusCheckService() {
    return ManualConsensusCheckService(
      consensus: buildConsensusRuntimeService(),
    );
  }

  CapsuleDiagnosticsService buildCapsuleDiagnosticsService() {
    return CapsuleDiagnosticsService(
      diagnoseBootstrap: _runtime.diagnoseBootstrapReport,
      diagnoseTrace: _runtime.diagnoseCapsuleTraces,
    );
  }

  CapsuleChatDeliveryService buildCapsuleChatDeliveryService() {
    final addressService = CapsuleAddressService(
      runtime: _runtime.capsuleAddressRuntime,
    );
    return CapsuleChatDeliveryService(
      runtime: _runtime,
      manualChecks: buildManualConsensusCheckService(),
      loadRelationships: _ledgerView.loadRelationships,
      listTrustedCards: addressService.listTrustedCards,
    );
  }

  CapsuleAddressService buildCapsuleAddressService() {
    return CapsuleAddressService(
      runtime: _runtime.capsuleAddressRuntime,
    );
  }

  PluginHostApiService buildPluginHostApiService() {
    final consensus = buildConsensusRuntimeService();
    final wasmRuntime = WasmPluginRuntimeService(
      invokeJson: _runtime.invokeWasmJson,
    );
    return PluginHostApiService(
      handlers: <PluginHostContractHandler>[
        BingxFuturesPluginContractHandler(
          readSignable: consensus.signable,
        ),
        CapsuleChatPluginContractHandler(
          readSignable: consensus.signable,
        ),
      ],
      resolveRuntimeBinding: _resolvePluginRuntimeBinding,
      resolveRuntimeInvoke: (request, binding) => wasmRuntime.invoke(
        request: request,
        binding: binding,
      ),
    );
  }

  BingxFuturesCredentialStore buildBingxFuturesCredentialStore() {
    return BingxFuturesCredentialStore(
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
  }

  BingxFuturesExchangeService buildBingxFuturesExchangeService() {
    return BingxFuturesExchangeService();
  }

  BingxFuturesOrderTrackingStore buildBingxFuturesOrderTrackingStore() {
    return BingxFuturesOrderTrackingStore(
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
  }

  Future<PluginRuntimeBinding> _resolvePluginRuntimeBinding(
    String pluginId,
  ) async {
    final normalizedPluginId = pluginId.trim();
    if (normalizedPluginId.isEmpty) {
      return const PluginRuntimeBinding.hostFallback();
    }

    final registry = const WasmPluginRegistryService();
    final records = await registry.loadPlugins();
    final pluginsDir = await registry.pluginsDirectory();
    for (final record in records) {
      final recordPluginId = record.pluginId?.trim();
      if (recordPluginId == null || recordPluginId.isEmpty) {
        continue;
      }
      if (recordPluginId != normalizedPluginId) {
        continue;
      }
      final packageDigestHex = await _resolvePackageDigestHex(
        registry: registry,
        record: record,
      );
      final packagePath = '${pluginsDir.path}/${record.storedFileName}';
      return PluginRuntimeBinding.externalPackage(
        packageId: record.id,
        packageVersion: record.pluginVersion,
        packageKind: record.packageKind,
        packageDigestHex: packageDigestHex,
        packageFilePath: packagePath,
        runtimeAbi: record.runtimeAbi,
        runtimeEntryExport: record.runtimeEntryExport,
        runtimeModulePath: record.runtimeModulePath,
        contractKind: record.contractKind,
        capabilities: record.capabilities,
      );
    }

    return const PluginRuntimeBinding.hostFallback();
  }

  Future<String?> _resolvePackageDigestHex({
    required WasmPluginRegistryService registry,
    required WasmPluginRecord record,
  }) async {
    final pluginsDir = await registry.pluginsDirectory();
    final packagePath = '${pluginsDir.path}/${record.storedFileName}';
    final packageFile = File(packagePath);
    if (!await packageFile.exists()) {
      return null;
    }
    final bytes = await packageFile.readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }
    return sha256.convert(bytes).toString();
  }

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  RelationshipService buildRelationshipService({
    String? activeCapsuleHex,
  }) {
    return RelationshipService(
      loadRelationshipGroups: _ledgerView.loadRelationshipGroups,
      breakRelationship: _runtime.breakRelationship,
      persistLedgerSnapshot: _runtime.persistLedgerSnapshot,
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
    );
  }
}
