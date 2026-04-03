import 'dart:typed_data';

import '../ffi/app_runtime_runtime.dart';
import 'capsule_address_service.dart';
import 'capsule_state_manager.dart';
import 'consensus_runtime_service.dart';
import 'invitation_actions_service.dart';
import 'invitation_delivery_service.dart';
import 'invitation_intent_handler.dart';
import 'ledger_view_service.dart';
import 'manual_consensus_check_service.dart';
import 'plugin_execution_guard_service.dart';
import 'plugin_demo_contract_runner_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';
import 'temperature_tomorrow_contract_service.dart';
import 'plugin_host_api_service.dart';

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

  TemperatureTomorrowContractService buildTemperatureTomorrowContractService() {
    final consensus = buildConsensusRuntimeService();
    return TemperatureTomorrowContractService(
      readSignable: consensus.signable,
    );
  }

  PluginDemoContractRunnerService buildPluginDemoContractRunnerService() {
    final consensus = buildConsensusRuntimeService();
    final contract = TemperatureTomorrowContractService(
      readSignable: consensus.signable,
    );
    return PluginDemoContractRunnerService(
      readChecks: consensus.checks,
      contractService: contract,
    );
  }

  PluginHostApiService buildPluginHostApiService() {
    final demoRunner = buildPluginDemoContractRunnerService();
    return PluginHostApiService(
      runTemperatureDemo: demoRunner.runTemperatureTomorrowDemo,
    );
  }

  RelationshipService buildRelationshipService() {
    return RelationshipService(
      loadRelationshipGroups: _ledgerView.loadRelationshipGroups,
      breakRelationship: _runtime.breakRelationship,
      persistLedgerSnapshot: _runtime.persistLedgerSnapshot,
    );
  }

  SettingsService buildSettingsService() {
    final contactCards = CapsuleAddressService(
      runtime: _runtime.capsuleAddressRuntime,
    );
    return SettingsService(
      loadIsNeste: () => _stateManager.state.isNeste,
      loadSeed: _runtime.loadSeed,
      diagnoseCapsuleTraces: _runtime.diagnoseCapsuleTraces,
      diagnoseBootstrapReport: _runtime.diagnoseBootstrapReport,
      buildOwnCard: contactCards.buildOwnCard,
      exportOwnCardJson: contactCards.exportOwnCardJson,
      contactCards: contactCards,
    );
  }
}
