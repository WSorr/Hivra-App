import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import 'capsule_address_service.dart';
import 'capsule_persistence_models.dart';
import 'capsule_persistence_service.dart';
import 'capsule_state_manager.dart';

class SettingsService {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;
  final CapsuleAddressService _contactCards;

  SettingsService(
    this._hivra, {
    CapsulePersistenceService? persistence,
    CapsuleAddressService contactCards = const CapsuleAddressService(),
  })  : _persistence = persistence ?? CapsulePersistenceService(),
        _contactCards = contactCards;

  bool loadIsNeste() {
    return CapsuleStateManager(_hivra).state.isNeste;
  }

  Uint8List? loadSeed() => _hivra.loadSeed();

  Future<CapsuleTraceReport> diagnoseCapsuleTraces() {
    return _persistence.diagnoseCapsuleTraces(_hivra);
  }

  Future<CapsuleBootstrapReport> diagnoseBootstrapReport() {
    return _persistence.diagnoseBootstrapReport(_hivra);
  }

  Future<int> contactCount() => _contactCards.contactCount();

  Future<CapsuleAddressCard?> buildOwnCard() => _contactCards.buildOwnCard(_hivra);

  Future<String?> exportOwnCardJson() => _contactCards.exportOwnCardJson(_hivra);

  Future<void> importCardJson(String raw) => _contactCards.importCardJson(raw);

  Future<List<CapsuleAddressCard>> listTrustedCards() =>
      _contactCards.listTrustedCards();

  Future<bool> removeTrustedCard(String rootKey) =>
      _contactCards.removeTrustedCard(rootKey);
}
