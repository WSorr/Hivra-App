import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';

import 'capsule_address_service.dart';

class SettingsService {
  final bool Function() _loadIsNeste;
  final Uint8List? Function() _loadSeed;
  final Future<CapsuleAddressCard?> Function() _buildOwnCard;
  final Future<String?> Function() _exportOwnCardJson;
  final Future<String> Function() _loadAppVersionLabel;
  final CapsuleAddressService _contactCards;

  SettingsService({
    required bool Function() loadIsNeste,
    required Uint8List? Function() loadSeed,
    required Future<CapsuleAddressCard?> Function() buildOwnCard,
    required Future<String?> Function() exportOwnCardJson,
    Future<String> Function() loadAppVersionLabel = _defaultAppVersionLabel,
    CapsuleAddressService contactCards = const CapsuleAddressService(),
  })  : _loadIsNeste = loadIsNeste,
        _loadSeed = loadSeed,
        _buildOwnCard = buildOwnCard,
        _exportOwnCardJson = exportOwnCardJson,
        _loadAppVersionLabel = loadAppVersionLabel,
        _contactCards = contactCards;

  static Future<String> _defaultAppVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    final suffix = build.isEmpty ? '' : ' ($build)';
    return 'Hivra v${info.version}$suffix';
  }

  bool loadIsNeste() {
    return _loadIsNeste();
  }

  Uint8List? loadSeed() => _loadSeed();

  Future<int> contactCount() => _contactCards.contactCount();

  Future<CapsuleAddressCard?> buildOwnCard() => _buildOwnCard();

  Future<String?> exportOwnCardJson() => _exportOwnCardJson();

  Future<String> appVersionLabel() => _loadAppVersionLabel();

  Future<void> importCardJson(String raw) => _contactCards.importCardJson(raw);

  Future<List<CapsuleAddressCard>> listTrustedCards() =>
      _contactCards.listTrustedCards();

  Future<bool> removeTrustedCard(String rootKey) =>
      _contactCards.removeTrustedCard(rootKey);
}
