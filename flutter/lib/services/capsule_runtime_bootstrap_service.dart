import 'dart:convert';
import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import 'capsule_backup_codec.dart';
import 'capsule_file_store.dart';
import 'capsule_persistence_models.dart';
import 'capsule_seed_store.dart';

class CapsuleRuntimeBootstrapService {
  final CapsuleFileStore _fileStore;
  final CapsuleSeedStore _seedStore;

  const CapsuleRuntimeBootstrapService(this._fileStore, this._seedStore);

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(
    String pubKeyHex, {
    String identityMode = 'root_owner',
    HivraBindings? hivra,
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final seed = hivra == null
        ? await _seedStore.loadSeed(pubKeyHex)
        : await _seedStore.loadValidatedSeed(
            pubKeyHex,
            isValidSeed: (seed) => _seedMatchesCapsule(
              hivra,
              seed,
              pubKeyHex,
              bytesToHex,
              identityMode: identityMode,
            ),
            persistValidatedSeed: (seed) =>
                _seedStore.storeSeed(pubKeyHex, seed),
          );
    if (seed == null) return null;

    final dir = await _fileStore.capsuleDirForHex(pubKeyHex, create: true);
    final state = await _fileStore.readState(dir);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;

    final ledgerCandidate = _ledgerCandidateForCapsule(
      await _fileStore.readLedger(dir),
      pubKeyHex,
      bytesToHex,
      source: _LedgerSource.ledger,
    );
    _LedgerCandidate? backupCandidate;
    final backupJson = await _fileStore.readBackup(dir);
    if (backupJson != null) {
      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
      backupCandidate = _ledgerCandidateForCapsule(
        extracted,
        pubKeyHex,
        bytesToHex,
        source: _LedgerSource.backup,
      );
    }
    final ledgerJson = _selectPreferredLedgerCandidate(
      ledgerCandidate,
      backupCandidate,
    )?.json;

    return CapsuleRuntimeBootstrap(
      pubKeyHex: pubKeyHex,
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      identityMode: identityMode,
      ledgerJson: ledgerJson,
    );
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrapForCurrent(
    HivraBindings hivra, {
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final pubKey = hivra.capsuleRuntimeOwnerPublicKey();
    final seed = hivra.loadSeed();
    if (pubKey == null || pubKey.length != 32 || seed == null) return null;

    final dir = await _fileStore.currentCapsuleDir(
      hivra,
      bytesToHex: bytesToHex,
      create: false,
    );
    final state = await _fileStore.readState(dir);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;
    final ledgerJson = hivra.exportLedger();
    final runtimeOwner = hivra.capsuleRuntimeOwnerPublicKey();
    final rootPubKey = hivra.capsuleRootPublicKey();
    final runtimeHex = runtimeOwner != null && runtimeOwner.length == 32
        ? bytesToHex(runtimeOwner)
        : null;
    final rootHex = rootPubKey != null && rootPubKey.length == 32
        ? bytesToHex(rootPubKey)
        : null;
    final identityMode = runtimeHex != null && runtimeHex == rootHex
        ? 'root_owner'
        : 'legacy_nostr_owner';

    return CapsuleRuntimeBootstrap(
      pubKeyHex: bytesToHex(pubKey),
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      identityMode: identityMode,
      ledgerJson:
          (ledgerJson != null && ledgerJson.isNotEmpty) ? ledgerJson : null,
    );
  }

  Future<bool> refreshCapsuleSnapshot(
    HivraBindings hivra,
    String pubKeyHex, {
    String identityMode = 'root_owner',
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final seed = await _seedStore.loadValidatedSeed(
      pubKeyHex,
      isValidSeed: (seed) => _seedMatchesCapsule(
        hivra,
        seed,
        pubKeyHex,
        bytesToHex,
        identityMode: identityMode,
      ),
      persistValidatedSeed: (seed) => _seedStore.storeSeed(pubKeyHex, seed),
    );
    if (seed == null) return false;
    if (!hivra.saveSeed(seed)) return false;

    final dir = await _fileStore.capsuleDirForHex(pubKeyHex, create: true);
    final state = await _fileStore.readState(dir);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;
    if (!hivra.createCapsule(
      seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      ownerMode: identityMode == 'legacy_nostr_owner'
          ? HivraBindings.legacyNostrOwnerMode
          : HivraBindings.rootOwnerMode,
    )) {
      return false;
    }

    final storedLedgerJson = await _fileStore.readLedger(dir);
    final ledgerCandidate = _ledgerCandidateForCapsule(
      storedLedgerJson,
      pubKeyHex,
      bytesToHex,
      source: _LedgerSource.ledger,
    );
    final backupJson = await _fileStore.readBackup(dir);
    final hasStoredHistory = (storedLedgerJson?.trim().isNotEmpty ?? false) ||
        (backupJson?.trim().isNotEmpty ?? false);
    var importedHistory = false;

    _LedgerCandidate? backupCandidate;
    if (backupJson != null) {
      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
      backupCandidate = _ledgerCandidateForCapsule(
        extracted,
        pubKeyHex,
        bytesToHex,
        source: _LedgerSource.backup,
      );
    }
    final preferred = _selectPreferredLedgerCandidate(
      ledgerCandidate,
      backupCandidate,
    );
    if (preferred != null) {
      if (!hivra.importLedger(preferred.json)) return false;
      importedHistory = true;
    }
    if (hasStoredHistory && !importedHistory) return false;

    final exported = hivra.exportLedger();
    if (exported == null || exported.isEmpty) return false;
    await _fileStore.writeLedger(dir, exported);
    return true;
  }

  Future<bool> _seedMatchesCapsule(
    HivraBindings hivra,
    Uint8List seed,
    String pubKeyHex,
    String Function(Uint8List bytes) bytesToHex, {
    required String identityMode,
  }) async {
    if (identityMode == 'root_owner') {
      final derivedPubKey = hivra.seedRootPublicKey(seed);
      if (derivedPubKey == null || derivedPubKey.length != 32) return false;
      return bytesToHex(derivedPubKey) == pubKeyHex;
    }

    if (identityMode == 'legacy_nostr_owner') {
      final derivedPubKey = hivra.seedNostrPublicKey(seed);
      if (derivedPubKey == null || derivedPubKey.length != 32) return false;
      return bytesToHex(derivedPubKey) == pubKeyHex;
    }

    final rootPubKey = hivra.seedRootPublicKey(seed);
    if (rootPubKey != null &&
        rootPubKey.length == 32 &&
        bytesToHex(rootPubKey) == pubKeyHex) {
      return true;
    }

    final nostrPubKey = hivra.seedNostrPublicKey(seed);
    if (nostrPubKey != null &&
        nostrPubKey.length == 32 &&
        bytesToHex(nostrPubKey) == pubKeyHex) {
      return true;
    }

    return false;
  }

  _LedgerCandidate? _ledgerCandidateForCapsule(String? ledgerJson,
      String pubKeyHex, String Function(Uint8List bytes) bytesToHex,
      {required _LedgerSource source}) {
    if (ledgerJson == null || ledgerJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(ledgerJson);
      if (decoded is! Map) return null;
      final ledger = Map<String, dynamic>.from(decoded);
      final events = ledger['events'];
      if (events is! List) return null;
      final owner = _parseBytes32Field(ledger['owner']);
      if (owner == null) return null;
      if (bytesToHex(Uint8List.fromList(owner)) != pubKeyHex) return null;
      return _LedgerCandidate(
        source: source,
        json: jsonEncode(ledger),
        eventCount: events.length,
      );
    } catch (_) {
      return null;
    }
  }

  _LedgerCandidate? _selectPreferredLedgerCandidate(
    _LedgerCandidate? ledger,
    _LedgerCandidate? backup,
  ) {
    if (ledger == null) return backup;
    if (backup == null) return ledger;

    if (backup.eventCount > ledger.eventCount) {
      return backup;
    }
    if (ledger.eventCount > backup.eventCount) {
      return ledger;
    }
    // Deterministic tie-breaker: prefer ledger.json on equal history length.
    return ledger.source == _LedgerSource.ledger ? ledger : backup;
  }

  List<int>? _parseBytes32Field(dynamic raw) {
    if (raw is List) {
      if (raw.length != 32) return null;
      final out = <int>[];
      for (final item in raw) {
        if (item is! num) return null;
        final value = item.toInt();
        if (value < 0 || value > 255) return null;
        out.add(value);
      }
      return out;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed)) {
        final out = <int>[];
        for (var i = 0; i < trimmed.length; i += 2) {
          out.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
        }
        return out;
      }
      try {
        final bytes = base64Decode(trimmed);
        return bytes.length == 32 ? bytes : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

enum _LedgerSource { ledger, backup }

class _LedgerCandidate {
  final _LedgerSource source;
  final String json;
  final int eventCount;

  const _LedgerCandidate({
    required this.source,
    required this.json,
    required this.eventCount,
  });
}
