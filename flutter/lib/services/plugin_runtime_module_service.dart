import 'app_runtime_service.dart';
import 'capsule_chat_delivery_service.dart';
import 'manual_consensus_check_service.dart';
import 'plugin_host_api_service.dart';
import 'ui_event_log_service.dart';
import 'wasm_plugin_registry_service.dart';
import 'wasm_plugin_source_catalog_service.dart';

class PluginRuntimeModule {
  final WasmPluginRegistryService registry;
  final WasmPluginSourceCatalogService sourceCatalog;
  final ManualConsensusCheckService manualChecks;
  final PluginHostApiService pluginHostApi;
  final CapsuleChatDeliveryService chatDelivery;
  final UiEventLogService uiLog;

  const PluginRuntimeModule({
    required this.registry,
    required this.sourceCatalog,
    required this.manualChecks,
    required this.pluginHostApi,
    required this.chatDelivery,
    required this.uiLog,
  });
}

class PluginRuntimeModuleService {
  final AppRuntimeService runtime;

  const PluginRuntimeModuleService({
    required this.runtime,
  });

  PluginRuntimeModule build() {
    return PluginRuntimeModule(
      registry: const WasmPluginRegistryService(),
      sourceCatalog: const WasmPluginSourceCatalogService(),
      manualChecks: runtime.buildManualConsensusCheckService(),
      pluginHostApi: runtime.buildPluginHostApiService(),
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
      uiLog: const UiEventLogService(),
    );
  }
}
