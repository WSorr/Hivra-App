import 'dart:typed_data';

import 'capsule_address_service.dart';
import 'capsule_persistence_models.dart';

class SettingsService {
  final bool Function() _loadIsNeste;
  final Uint8List? Function() _loadSeed;
  final Future<CapsuleTraceReport> Function() _diagnoseCapsuleTraces;
  final Future<CapsuleBootstrapReport> Function() _diagnoseBootstrapReport;
  final Future<CapsuleAddressCard?> Function() _buildOwnCard;
  final Future<String?> Function() _exportOwnCardJson;
  final CapsuleAddressService _contactCards;

  SettingsService({
    required bool Function() loadIsNeste,
    required Uint8List? Function() loadSeed,
    required Future<CapsuleTraceReport> Function() diagnoseCapsuleTraces,
    required Future<CapsuleBootstrapReport> Function() diagnoseBootstrapReport,
    required Future<CapsuleAddressCard?> Function() buildOwnCard,
    required Future<String?> Function() exportOwnCardJson,
    CapsuleAddressService contactCards = const CapsuleAddressService(),
  })  : _loadIsNeste = loadIsNeste,
        _loadSeed = loadSeed,
        _diagnoseCapsuleTraces = diagnoseCapsuleTraces,
        _diagnoseBootstrapReport = diagnoseBootstrapReport,
        _buildOwnCard = buildOwnCard,
        _exportOwnCardJson = exportOwnCardJson,
        _contactCards = contactCards;

  bool loadIsNeste() {
    return _loadIsNeste();
  }

  Uint8List? loadSeed() => _loadSeed();

  Future<CapsuleTraceReport> diagnoseCapsuleTraces() {
    return _diagnoseCapsuleTraces();
  }

  Future<CapsuleBootstrapReport> diagnoseBootstrapReport() {
    return _diagnoseBootstrapReport();
  }

  Future<int> contactCount() => _contactCards.contactCount();

  Future<CapsuleAddressCard?> buildOwnCard() => _buildOwnCard();

  Future<String?> exportOwnCardJson() => _exportOwnCardJson();

  Future<void> importCardJson(String raw) => _contactCards.importCardJson(raw);

  Future<List<CapsuleAddressCard>> listTrustedCards() =>
      _contactCards.listTrustedCards();

  Future<bool> removeTrustedCard(String rootKey) =>
      _contactCards.removeTrustedCard(rootKey);
}
