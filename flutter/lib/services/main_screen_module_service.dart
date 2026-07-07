import 'app_runtime_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';

class MainScreenModule {
  final RelationshipService Function({String? activeCapsuleHex})
      relationshipService;
  final SettingsService Function() settingsService;

  const MainScreenModule({
    required this.relationshipService,
    required this.settingsService,
  });
}

class MainScreenModuleService {
  final AppRuntimeService runtime;

  const MainScreenModuleService({
    required this.runtime,
  });

  MainScreenModule build() {
    return MainScreenModule(
      relationshipService: runtime.buildRelationshipService,
      settingsService: runtime.buildSettingsService,
    );
  }
}
