import 'dart:typed_data';

import 'app_runtime_service.dart';
import 'capsule_state_manager.dart';
import 'manual_consensus_check_service.dart';

class LedgerInspectorModule {
  final CapsuleStateManager stateManager;
  final ManualConsensusCheckService manualConsensusChecks;
  final Uint8List? Function() capsuleRootPublicKey;
  final String? Function() exportLedger;

  const LedgerInspectorModule({
    required this.stateManager,
    required this.manualConsensusChecks,
    required this.capsuleRootPublicKey,
    required this.exportLedger,
  });
}

class LedgerInspectorModuleService {
  final AppRuntimeService runtime;

  const LedgerInspectorModuleService({
    required this.runtime,
  });

  LedgerInspectorModule build() {
    return LedgerInspectorModule(
      stateManager: runtime.stateManager,
      manualConsensusChecks: runtime.buildManualConsensusCheckService(),
      capsuleRootPublicKey: runtime.capsuleRootPublicKey,
      exportLedger: runtime.exportLedger,
    );
  }
}
