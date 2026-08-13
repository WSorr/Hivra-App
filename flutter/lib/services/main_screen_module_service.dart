import 'app_runtime_service.dart';
import 'ai_tooling_module_service.dart';
import 'capsule_history_ai_advisor_service.dart';
import 'capsule_history_projection_service.dart';
import 'capsule_passive_receive_coordinator.dart';
import 'capsule_chat_delivery_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';

class MainScreenModule {
  final RelationshipService Function({String? activeCapsuleHex})
  relationshipService;
  final SettingsService Function() settingsService;
  final CapsulePassiveReceiveCoordinator passiveReceive;
  final CapsuleChatDeliveryService chatDelivery;
  final CapsuleHistoryProjectionService capsuleHistory;
  final CapsuleHistoryAiAdvisorService capsuleHistoryAi;

  const MainScreenModule({
    required this.relationshipService,
    required this.settingsService,
    required this.passiveReceive,
    required this.chatDelivery,
    required this.capsuleHistory,
    required this.capsuleHistoryAi,
  });
}

class MainScreenModuleService {
  final AppRuntimeService runtime;

  const MainScreenModuleService({required this.runtime});

  MainScreenModule build() {
    final aiTooling = AiToolingModuleService(runtime: runtime);
    return MainScreenModule(
      relationshipService: runtime.buildRelationshipService,
      settingsService: runtime.buildSettingsService,
      passiveReceive: runtime.passiveReceive,
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
      capsuleHistory: CapsuleHistoryProjectionService(
        exportLedger: runtime.exportLedger,
        projectHistoryView: runtime.projectHistoryViewV1,
      ),
      capsuleHistoryAi: aiTooling.buildCapsuleHistoryAiAdvisorService(),
    );
  }
}
