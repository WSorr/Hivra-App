import 'ai_capsule_inspection_service.dart';
import 'ai_doctor_chat_service.dart';
import 'ai_doctor_credential_store.dart';
import 'capsule_history_ai_advisor_service.dart';
import 'ai_plugin_audit_service.dart';
import 'app_runtime_service.dart';
import 'capsule_ai_runtime_service.dart';

class AiToolingModuleService {
  final AppRuntimeService _runtime;

  const AiToolingModuleService({required AppRuntimeService runtime})
    : _runtime = runtime;

  AiToolingModule buildModule() {
    final aiRuntime = _buildCapsuleAiRuntime();
    return AiToolingModule(
      capsuleInspection: buildCapsuleInspectionService(),
      capsuleAnalystChat: buildCapsuleAnalystChatService(runtime: aiRuntime),
      pluginAudit: buildPluginAuditService(),
    );
  }

  AiCapsuleInspectionService buildCapsuleInspectionService() {
    return AiCapsuleInspectionService(
      ledgerView: _runtime.ledgerView,
      consensus: _runtime.buildConsensusRuntimeService(),
      diagnostics: _runtime.buildCapsuleDiagnosticsService(),
      readActiveCapsuleHex: _runtime.activeCapsuleRootHex,
    );
  }

  AiDoctorChatService buildCapsuleAnalystChatService({
    CapsuleInferenceRuntime? runtime,
  }) {
    return AiDoctorChatService(runtime: runtime ?? _buildCapsuleAiRuntime());
  }

  CapsuleHistoryAiAdvisorService buildCapsuleHistoryAiAdvisorService() {
    return CapsuleHistoryAiAdvisorService(runtime: _buildCapsuleAiRuntime());
  }

  AiPluginAuditService buildPluginAuditService() {
    return const AiPluginAuditService();
  }

  CapsuleAiRuntimeService _buildCapsuleAiRuntime() {
    return CapsuleAiRuntimeService(
      credentialStore: AiDoctorCredentialStore.shared,
      readActiveCapsuleRootHex: _runtime.activeCapsuleRootHex,
    );
  }
}

class AiToolingModule {
  final AiCapsuleInspectionService capsuleInspection;
  final AiDoctorChatService capsuleAnalystChat;
  final AiPluginAuditService pluginAudit;

  const AiToolingModule({
    required this.capsuleInspection,
    required this.capsuleAnalystChat,
    required this.pluginAudit,
  });
}
