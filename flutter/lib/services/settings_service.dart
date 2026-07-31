import 'dart:io';
import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';

import 'capsule_address_service.dart';
import 'capsule_contact_label_store.dart';
import 'user_visible_data_directory_service.dart';

class SettingsService {
  final bool Function() _loadIsNeste;
  final Uint8List? Function() _loadSeed;
  final Future<CapsuleAddressCard?> Function() _buildOwnCard;
  final Future<String?> Function() _exportOwnCardJson;
  final Future<String> Function() _loadAppVersionLabel;
  final Future<String> Function() _openLocalDataFolder;
  final CapsuleAddressService _contactCards;
  final CapsuleContactLabelStore _contactLabels;

  SettingsService({
    required bool Function() loadIsNeste,
    required Uint8List? Function() loadSeed,
    required Future<CapsuleAddressCard?> Function() buildOwnCard,
    required Future<String?> Function() exportOwnCardJson,
    Future<String> Function() loadAppVersionLabel = _defaultAppVersionLabel,
    Future<String> Function() openLocalDataFolder = _defaultOpenLocalDataFolder,
    CapsuleAddressService contactCards = const CapsuleAddressService(),
    CapsuleContactLabelStore? contactLabels,
  }) : _loadIsNeste = loadIsNeste,
       _loadSeed = loadSeed,
       _buildOwnCard = buildOwnCard,
       _exportOwnCardJson = exportOwnCardJson,
       _loadAppVersionLabel = loadAppVersionLabel,
       _openLocalDataFolder = openLocalDataFolder,
       _contactCards = contactCards,
       _contactLabels =
           contactLabels ??
           CapsuleContactLabelStore(readActiveCapsuleRootHex: () => null);

  static Future<String> _defaultAppVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    final suffix = build.isEmpty ? '' : ' ($build)';
    return 'Hivra v${info.version}$suffix';
  }

  static Future<String> _defaultOpenLocalDataFolder() async {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'The local data folder is managed by the operating system.',
      );
    }
    final directory = await const UserVisibleDataDirectoryService()
        .rootDirectory(create: true);
    final result = await Process.run('open', <String>[directory.path]);
    if (result.exitCode != 0) {
      throw StateError('Finder could not open the local data folder.');
    }
    return directory.path;
  }

  bool loadIsNeste() {
    return _loadIsNeste();
  }

  Uint8List? loadSeed() => _loadSeed();

  Future<int> contactCount() => _contactCards.contactCount();

  Future<CapsuleAddressCard?> buildOwnCard() => _buildOwnCard();

  Future<String?> exportOwnCardJson() => _exportOwnCardJson();

  Future<String> appVersionLabel() => _loadAppVersionLabel();

  Future<String> openLocalDataFolder() => _openLocalDataFolder();

  Future<void> importCardJson(String raw) => _contactCards.importCardJson(raw);

  Future<void> importCardPayload(String raw) =>
      _contactCards.importCardPayload(raw);

  Future<List<CapsuleAddressCard>> listTrustedCards() =>
      _contactCards.listTrustedCards();

  Future<bool> removeTrustedCard(String rootKey) =>
      _contactCards.removeTrustedCard(rootKey);

  Future<Map<String, String>> loadContactLabels() => _contactLabels.load();

  Future<void> saveContactLabel({
    required String peerRootKey,
    required String label,
  }) => _contactLabels.save(peerRootKey: peerRootKey, label: label);
}
