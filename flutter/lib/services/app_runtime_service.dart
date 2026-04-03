import 'dart:typed_data';

import '../ffi/capsule_address_runtime.dart';
import '../ffi/hivra_bindings.dart';
import '../ffi/invitation_actions_runtime.dart';
import '../ffi/ledger_view_runtime.dart';
import 'capsule_address_service.dart';
import 'capsule_persistence_service.dart';
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
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;
  late final CapsuleStateManager _stateManager;
  late final InvitationActionsService _invitationActions;
  late final InvitationIntentHandler _invitationIntents;
  late final LedgerViewService _ledgerView;

  AppRuntimeService({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService() {
    _ledgerView = LedgerViewService(runtime: HivraLedgerViewRuntime(_hivra));
    _stateManager = CapsuleStateManager(_ledgerView);
    _invitationActions = InvitationActionsService(
      runtime: HivraInvitationActionsRuntime(
        hivra: _hivra,
        persistence: _persistence,
      ),
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
    return _persistence.bootstrapActiveCapsuleRuntime(_hivra);
  }

  Future<void> persistLedgerSnapshot() {
    return _persistence.persistLedgerSnapshot(_hivra);
  }

  Uint8List? capsuleRootPublicKey() => _hivra.capsuleRootPublicKey();
  Uint8List? capsuleNostrPublicKey() => _hivra.capsuleNostrPublicKey();
  String? exportLedger() => _hivra.exportLedger();

  ConsensusRuntimeService buildConsensusRuntimeService() {
    return ConsensusRuntimeService(
      exportLedger: _hivra.exportLedger,
      readLocalTransportKey: _hivra.capsuleNostrPublicKey,
      readLocalRootKey: _hivra.capsuleRootPublicKey,
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
      breakRelationship: _hivra.breakRelationship,
      persistLedgerSnapshot: () => _persistence.persistLedgerSnapshot(_hivra),
    );
  }

  SettingsService buildSettingsService() {
    final contactCards = CapsuleAddressService(
      runtime: HivraCapsuleAddressRuntime(_hivra),
    );
    return SettingsService(
      loadIsNeste: () => _stateManager.state.isNeste,
      loadSeed: _hivra.loadSeed,
      diagnoseCapsuleTraces: () => _persistence.diagnoseCapsuleTraces(_hivra),
      diagnoseBootstrapReport: () =>
          _persistence.diagnoseBootstrapReport(_hivra),
      buildOwnCard: contactCards.buildOwnCard,
      exportOwnCardJson: contactCards.exportOwnCardJson,
      contactCards: contactCards,
    );
  }
}
