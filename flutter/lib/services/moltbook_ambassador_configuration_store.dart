import 'dart:convert';

import '../models/moltbook_ambassador_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_file_store.dart';

class MoltbookAmbassadorConfigurationStore {
  static const String _fileName = 'configuration.v1.json';

  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;

  const MoltbookAmbassadorConfigurationStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    required String? Function() readActiveCapsuleRootHex,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  Future<MoltbookAmbassadorConfiguration> load() async {
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) {
      return MoltbookAmbassadorConfiguration.defaults();
    }
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    final raw = await _fileStore.readPluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _fileName,
    );
    if (raw == null) return MoltbookAmbassadorConfiguration.defaults();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException(
        'Moltbook ambassador configuration must be a JSON object',
      );
    }
    return MoltbookAmbassadorConfiguration.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<void> save(MoltbookAmbassadorConfiguration configuration) async {
    configuration.validate();
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) {
      throw StateError('Active capsule identity is unavailable');
    }
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    await _fileStore.writePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _fileName,
      const JsonEncoder.withIndent('  ').convert(configuration.toJson()),
    );
  }

  Future<void> delete() async {
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) return;
    final capsuleDir = await _fileStore.capsuleDirForHex(ownerHex);
    await _fileStore.deletePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _fileName,
    );
  }

  String? _activeOwnerHex() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }
}
