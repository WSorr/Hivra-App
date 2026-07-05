import 'dart:typed_data';

import 'capsule_address_service.dart';

class SettingsService {
  final bool Function() _loadIsNeste;
  final Uint8List? Function() _loadSeed;
  final Future<CapsuleAddressCard?> Function() _buildOwnCard;
  final Future<String?> Function() _exportOwnCardJson;
  final CapsuleAddressService _contactCards;

  SettingsService({
    required bool Function() loadIsNeste,
    required Uint8List? Function() loadSeed,
    required Future<CapsuleAddressCard?> Function() buildOwnCard,
    required Future<String?> Function() exportOwnCardJson,
    CapsuleAddressService contactCards = const CapsuleAddressService(),
  })  : _loadIsNeste = loadIsNeste,
        _loadSeed = loadSeed,
        _buildOwnCard = buildOwnCard,
        _exportOwnCardJson = exportOwnCardJson,
        _contactCards = contactCards;

  bool loadIsNeste() {
    return _loadIsNeste();
  }

  Uint8List? loadSeed() => _loadSeed();

  Future<int> contactCount() => _contactCards.contactCount();

  Future<CapsuleAddressCard?> buildOwnCard() => _buildOwnCard();

  Future<String?> exportOwnCardJson() => _exportOwnCardJson();

  Future<void> importCardJson(String raw) => _contactCards.importCardJson(raw);

  Future<List<CapsuleAddressCard>> listTrustedCards() =>
      _contactCards.listTrustedCards();

  Future<bool> removeTrustedCard(String rootKey) =>
      _contactCards.removeTrustedCard(rootKey);
}
