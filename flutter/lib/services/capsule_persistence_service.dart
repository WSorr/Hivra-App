import 'dart:convert';
import 'dart:io';
import 'package:bech32/bech32.dart';
import 'package:flutter/foundation.dart';

import '../ffi/capsule_runtime_bootstrap_runtime.dart';
import '../ffi/capsule_persistence_bindings.dart';
import 'capsule_backup_codec.dart';
import 'capsule_file_store.dart';
import 'capsule_identity_reconciler_service.dart';
import 'capsule_index_store.dart';
import 'capsule_ledger_summary_parser.dart';
import 'capsule_persistence_models.dart';
import 'capsule_runtime_bootstrap_service.dart';
import 'capsule_seed_store.dart';
import 'ledger_view_support.dart';
import 'user_visible_data_directory_service.dart';

@visibleForTesting
bool shouldRemoveCapsuleContactCardEntry({
  required String entryKey,
  required Object? entryValue,
  required String deleteKeyHex,
}) {
  final normalizedDeleteKey = _normalizeHex32ForCleanup(deleteKeyHex);
  if (normalizedDeleteKey == null) return false;

  final normalizedEntryKey = _normalizeHex32ForCleanup(entryKey);
  if (normalizedEntryKey == normalizedDeleteKey) return true;

  if (entryValue is! Map) return false;
  final map = Map<String, dynamic>.from(entryValue);

  final rootHex = _normalizeHex32ForCleanup(map['rootHex']?.toString());
  if (rootHex == normalizedDeleteKey) return true;

  final transports = map['transports'];
  if (transports is! Map) return false;
  final nostr = transports['nostr'];
  if (nostr is! Map) return false;
  final nostrHex = _normalizeHex32ForCleanup(
      Map<String, dynamic>.from(nostr)['hex']?.toString());
  return nostrHex == normalizedDeleteKey;
}

String? _normalizeHex32ForCleanup(String? value) {
  if (value == null) return null;
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(':', '')
      .replaceAll('-', '')
      .replaceAll(' ', '');
  final hex32 = RegExp(r'^[0-9a-f]{64}$');
  if (!hex32.hasMatch(normalized)) return null;
  return normalized;
}

class CapsulePersistenceService {
  static final CapsulePersistenceService _instance =
      CapsulePersistenceService._internal();

  factory CapsulePersistenceService() => _instance;

  CapsulePersistenceService._internal() {
    _runtimeBootstrapService =
        CapsuleRuntimeBootstrapService(_fileStore, _seedStore);
  }

  final CapsuleFileStore _fileStore = const CapsuleFileStore();
  final CapsuleIndexStore _indexStore = const CapsuleIndexStore();
  final CapsuleLedgerSummaryParser _summaryParser =
      const CapsuleLedgerSummaryParser();
  final CapsuleIdentityReconcilerService _identityReconciler =
      const CapsuleIdentityReconcilerService();
  final LedgerViewSupport _support = const LedgerViewSupport();
  final CapsuleSeedStore _seedStore = const CapsuleSeedStore();
  final UserVisibleDataDirectoryService _userVisibleDirs =
      const UserVisibleDataDirectoryService();
  late final CapsuleRuntimeBootstrapService _runtimeBootstrapService;

  Future<void> persistAfterCreate({
    required CapsulePersistenceBindings hivra,
    required Uint8List seed,
    required bool isGenesis,
    required bool isNeste,
  }) async {
    final pubKey = hivra.capsuleRuntimeOwnerPublicKey();
    final pubKeyHex = pubKey != null ? _bytesToHex(pubKey) : null;
    final index = await _readIndex();
    final duplicateSeedPubKeyHex = await _findCapsuleForSeed(
      index,
      seed,
      excludePubKeyHex: pubKeyHex,
    );
    if (duplicateSeedPubKeyHex != null) {
      final existingEntry = index.capsules[duplicateSeedPubKeyHex];
      await _storeSeedForCapsule(duplicateSeedPubKeyHex, seed);
      await _upsertCapsuleIndex(
        duplicateSeedPubKeyHex,
        isGenesis: existingEntry?.isGenesis,
        isNeste: existingEntry?.isNeste,
        identityMode: existingEntry?.identityMode ?? 'root_owner',
      );
      await _setActiveCapsule(duplicateSeedPubKeyHex);
      await _syncLocalCapsuleContactCards(hivra);
      return;
    }

    final dir = await _currentCapsuleDir(hivra, create: true);

    final state = <String, dynamic>{
      'isGenesis': isGenesis,
      'isNeste': isNeste,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'seedLength': seed.length,
    };
    await _fileStore.writeState(dir, state);

    final ledger = hivra.exportLedger();
    if (ledger != null && ledger.isNotEmpty) {
      await _fileStore.writeLedger(dir, ledger);

      final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: ledger,
        isGenesis: isGenesis,
        isNeste: isNeste,
      );
      await _fileStore.writeBackup(dir, backupJson);
    }

    if (pubKeyHex != null) {
      final identityMode = _detectIdentityMode(hivra, pubKeyHex);
      await _storeSeedForCapsule(pubKeyHex, seed);
      await _upsertCapsuleIndex(
        pubKeyHex,
        isGenesis: isGenesis,
        isNeste: isNeste,
        identityMode: identityMode,
      );
      await _setActiveCapsule(pubKeyHex);
      await _syncLocalCapsuleContactCards(hivra);
    }
  }

  Future<bool> bootstrapRuntimeFromDisk(
      CapsulePersistenceBindings hivra) async {
    final seed = hivra.loadSeed();
    if (seed == null) return false;

    final state = await _readStateForCurrentCapsule(hivra);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;

    if (!hivra.createCapsule(seed, isGenesis: isGenesis, isNeste: isNeste)) {
      return false;
    }

    await importLedgerIfExists(hivra);
    return true;
  }

  Future<bool> importLedgerIfExists(CapsulePersistenceBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra);
    final ledgerJson = await _fileStore.readLedger(dir);
    if (ledgerJson != null && hivra.importLedger(ledgerJson)) {
      await _touchActiveCapsule(hivra);
      return true;
    }
    return importBackupEnvelopeIfExists(hivra);
  }

  Future<bool> persistLedgerSnapshot(CapsulePersistenceBindings hivra) async {
    final ledger = hivra.exportLedger();
    if (ledger == null || ledger.isEmpty) return false;

    final dir = await _currentCapsuleDir(hivra, create: true);
    await _fileStore.writeLedger(dir, ledger);
    await _touchActiveCapsule(hivra);
    return true;
  }

  Future<bool> applyLedgerSnapshotIfNotStale(
    CapsulePersistenceBindings hivra,
    String ledgerJson,
  ) async {
    if (ledgerJson.trim().isEmpty) return false;

    final current = hivra.exportLedger();
    if (_isIncomingLedgerStale(
      incomingLedgerJson: ledgerJson,
      existingLedgerJson: current,
    )) {
      return false;
    }

    if (!hivra.importLedger(ledgerJson)) {
      return false;
    }
    await persistLedgerSnapshot(hivra);
    return true;
  }

  Future<bool> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson,
  ) async {
    if (pubKeyHex.isEmpty || ledgerJson.trim().isEmpty) return false;
    final ownerHex = _extractOwnerHex(ledgerJson);
    final targetPubKeyHex = ownerHex ?? pubKeyHex;
    final dir = await _capsuleDirForHex(targetPubKeyHex, create: true);
    final existingLedger = await _fileStore.readLedger(dir);
    if (_isIncomingLedgerStale(
      incomingLedgerJson: ledgerJson,
      existingLedgerJson: existingLedger,
    )) {
      return false;
    }
    await _fileStore.writeLedger(dir, ledgerJson);
    // Keep index heartbeat fresh for the capsule that actually produced worker output,
    // but do not switch active capsule.
    await _upsertCapsuleIndex(targetPubKeyHex);
    return true;
  }

  Future<String?> exportBackupEnvelope(CapsulePersistenceBindings hivra) async {
    final ledger = hivra.exportLedger();
    if (ledger == null || ledger.isEmpty) return null;

    final state = await _readStateForCurrentCapsule(hivra);
    final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
      ledgerJson: ledger,
      isGenesis: state?['isGenesis'] == true,
      isNeste: state?['isNeste'] != false,
    );

    final dir = await _currentCapsuleDir(hivra, create: true);
    await _fileStore.writeBackup(dir, backupJson);
    await _touchActiveCapsule(hivra);
    return _fileStore.backupPath(dir);
  }

  Future<String?> exportBackupEnvelopeToUserDirectory(
      CapsulePersistenceBindings hivra) async {
    final ledger = hivra.exportLedger();
    if (ledger == null || ledger.isEmpty) return null;

    final state = await _readStateForCurrentCapsule(hivra);
    final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
      ledgerJson: ledger,
      isGenesis: state?['isGenesis'] == true,
      isNeste: state?['isNeste'] != false,
    );

    final backupsDir = await _userVisibleDirs.backupsDirectory(create: true);
    final file = File(
      '${backupsDir.path}/capsule-backup-${DateTime.now().toIso8601String()}.json',
    );
    await file.writeAsString(backupJson, flush: true);
    return file.path;
  }

  Future<String?> exportBackupEnvelopeToPath(
    CapsulePersistenceBindings hivra,
    String targetPath,
  ) async {
    final ledger = hivra.exportLedger();
    if (ledger == null || ledger.isEmpty) return null;

    final state = await _readStateForCurrentCapsule(hivra);
    final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
      ledgerJson: ledger,
      isGenesis: state?['isGenesis'] == true,
      isNeste: state?['isNeste'] != false,
    );

    final outFile = File(targetPath);
    await outFile.writeAsString(backupJson, flush: true);
    return outFile.path;
  }

  Future<bool> importBackupEnvelopeIfExists(
      CapsulePersistenceBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra);
    final backupJson = await _fileStore.readBackup(dir);
    if (backupJson == null) return false;
    final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
    if (ledgerJson == null) return false;
    final imported = hivra.importLedger(ledgerJson);
    if (imported) {
      await _touchActiveCapsule(hivra);
    }
    return imported;
  }

  Future<void> clearPersistedData(CapsulePersistenceBindings hivra,
      {bool includeBackup = false}) async {
    final dir = await _currentCapsuleDir(hivra);
    await _fileStore.clearPersisted(dir, includeBackup: includeBackup);
  }

  Future<String?> resolveActiveCapsuleHex(
      CapsulePersistenceBindings hivra) async {
    await _reconcileCapsuleIdentityIndex(hivra);
    final index = await _readIndex();
    final activeHex = index.activePubKeyHex;
    if (activeHex != null && activeHex.isNotEmpty) {
      final activeBootstrap = await loadRuntimeBootstrap(
        activeHex,
        hivra: hivra,
      );
      if (activeBootstrap != null) {
        return activeHex;
      }

      final recovered = await _recoverActiveCapsuleHexFromIndex(index,
          exclude: {activeHex}, hivra: hivra);
      if (recovered != null) {
        await _setActiveCapsule(recovered);
        return recovered;
      }
    }

    final pubKey = hivra.capsuleRuntimeOwnerPublicKey();
    if (pubKey != null && pubKey.length == 32) {
      return _bytesToHex(pubKey);
    }
    return null;
  }

  Future<bool> bootstrapActiveCapsuleRuntime(
      CapsulePersistenceBindings hivra) async {
    var activeHex = await resolveActiveCapsuleHex(hivra);
    if (activeHex == null || activeHex.isEmpty) {
      return bootstrapRuntimeFromDisk(hivra);
    }

    var bootstrap = await loadRuntimeBootstrap(
      activeHex,
      hivra: hivra,
    );
    if (bootstrap == null) {
      final index = await _readIndex();
      final recovered = await _recoverActiveCapsuleHexFromIndex(
        index,
        exclude: {activeHex},
        hivra: hivra,
      );
      if (recovered == null) {
        return bootstrapRuntimeFromDisk(hivra);
      }
      await _setActiveCapsule(recovered);
      activeHex = recovered;
      bootstrap = await loadRuntimeBootstrap(
        activeHex,
        hivra: hivra,
      );
      if (bootstrap == null) {
        return bootstrapRuntimeFromDisk(hivra);
      }
    }

    if (!hivra.saveSeed(bootstrap.seed)) return false;
    if (!hivra.createCapsule(
      bootstrap.seed,
      isGenesis: bootstrap.isGenesis,
      isNeste: bootstrap.isNeste,
      ownerMode: _ownerModeCode(bootstrap.identityMode),
    )) {
      return false;
    }

    if (!_importBootstrapLedgerCandidates(hivra, bootstrap)) {
      return false;
    }

    await _setActiveCapsule(activeHex);
    await _syncLocalCapsuleContactCards(hivra);
    return true;
  }

  Future<String?> diagnoseActiveCapsuleBootstrap(
      CapsulePersistenceBindings hivra) async {
    final activeHex = await resolveActiveCapsuleHex(hivra);
    if (activeHex == null || activeHex.isEmpty) {
      return 'No active capsule selected';
    }

    final bootstrap = await loadRuntimeBootstrap(
      activeHex,
      hivra: hivra,
    );
    if (bootstrap == null) {
      return 'No bootstrap data for capsule $activeHex';
    }

    if (!hivra.saveSeed(bootstrap.seed)) {
      return 'Failed to save seed for capsule $activeHex';
    }

    if (!hivra.createCapsule(
      bootstrap.seed,
      isGenesis: bootstrap.isGenesis,
      isNeste: bootstrap.isNeste,
      ownerMode: _ownerModeCode(bootstrap.identityMode),
    )) {
      return 'Failed to create runtime capsule for $activeHex';
    }

    final runtimePubKey = hivra.capsuleRuntimeOwnerPublicKey();
    final runtimeHex = runtimePubKey != null && runtimePubKey.length == 32
        ? _bytesToHex(runtimePubKey)
        : null;
    if (runtimeHex != activeHex) {
      return 'Seed/pubkey mismatch: expected $activeHex, got ${runtimeHex ?? 'none'}';
    }

    if (!_importBootstrapLedgerCandidates(hivra, bootstrap)) {
      return 'Failed to import ledger for capsule $activeHex';
    }

    return null;
  }

  Future<CapsuleBootstrapReport> diagnoseBootstrapReport(
      CapsulePersistenceBindings hivra) async {
    final activeHex = await resolveActiveCapsuleHex(hivra);
    final runtimePubKey = hivra.capsuleRuntimeOwnerPublicKey();
    final runtimeHex = runtimePubKey != null && runtimePubKey.length == 32
        ? _bytesToHex(runtimePubKey)
        : null;
    final rootPubKey = hivra.capsuleRootPublicKey();
    final rootHex = rootPubKey != null && rootPubKey.length == 32
        ? _bytesToHex(rootPubKey)
        : null;
    final nostrPubKey = hivra.capsuleNostrPublicKey();
    final nostrHex = nostrPubKey != null && nostrPubKey.length == 32
        ? _bytesToHex(nostrPubKey)
        : null;
    final runtimeMatchesRoot = runtimeHex != null && runtimeHex == rootHex;
    final runtimeMatchesNostr = runtimeHex != null && runtimeHex == nostrHex;
    final identityMode = runtimeMatchesRoot
        ? 'root_owner'
        : runtimeMatchesNostr
            ? 'legacy_nostr_owner'
            : 'mixed_or_unknown';

    if (activeHex == null || activeHex.isEmpty) {
      return CapsuleBootstrapReport(
        activePubKeyHex: null,
        runtimePubKeyHex: runtimeHex,
        rootPubKeyHex: rootHex,
        nostrPubKeyHex: nostrHex,
        identityMode: identityMode,
        bootstrapSource: 'none',
        seedAvailable: false,
        seedMatchesActiveCapsule: false,
        rootMatchesActiveCapsule: false,
        nostrMatchesActiveCapsule: false,
        runtimeMatchesRoot: runtimeMatchesRoot,
        runtimeMatchesNostr: runtimeMatchesNostr,
        stateFileExists: false,
        ledgerFileExists: false,
        backupFileExists: false,
        workerBootstrapAvailable: false,
        ledgerImportable: false,
        issue: 'No active capsule selected',
      );
    }

    final capsuleDir = await _capsuleDirForHex(activeHex);
    final stateFileExists = await _fileStore.stateFile(capsuleDir).exists();
    final ledgerFileExists = await _fileStore.ledgerFile(capsuleDir).exists();
    final backupFileExists = await _fileStore.backupFile(capsuleDir).exists();
    final bootstrapSource = ledgerFileExists
        ? 'ledger'
        : backupFileExists
            ? 'backup'
            : 'none';

    final seed = await _loadSeedForCapsule(activeHex);
    final seedAvailable = seed != null;
    final seedMatches = seed != null
        ? await seedMatchesCapsule(
            hivra,
            seed,
            activeHex,
            identityMode: identityMode,
          )
        : false;
    final seedRootPubKey = seed != null ? hivra.seedRootPublicKey(seed) : null;
    final seedRootHex = seedRootPubKey != null && seedRootPubKey.length == 32
        ? _bytesToHex(seedRootPubKey)
        : null;
    final seedNostrPubKey =
        seed != null ? hivra.seedNostrPublicKey(seed) : null;
    final seedNostrHex = seedNostrPubKey != null && seedNostrPubKey.length == 32
        ? _bytesToHex(seedNostrPubKey)
        : null;

    final bootstrap = await loadRuntimeBootstrap(
      activeHex,
      hivra: hivra,
    );
    final workerBootstrap = await loadWorkerBootstrapArgs(hivra);
    final issue = await diagnoseActiveCapsuleBootstrap(hivra);

    return CapsuleBootstrapReport(
      activePubKeyHex: activeHex,
      runtimePubKeyHex: runtimeHex,
      rootPubKeyHex: rootHex,
      nostrPubKeyHex: nostrHex,
      identityMode: identityMode,
      bootstrapSource: bootstrapSource,
      seedAvailable: seedAvailable,
      seedMatchesActiveCapsule: seedMatches,
      rootMatchesActiveCapsule: seedRootHex != null && activeHex == seedRootHex,
      nostrMatchesActiveCapsule:
          seedNostrHex != null && activeHex == seedNostrHex,
      runtimeMatchesRoot: runtimeMatchesRoot,
      runtimeMatchesNostr: runtimeMatchesNostr,
      stateFileExists: stateFileExists,
      ledgerFileExists: ledgerFileExists,
      backupFileExists: backupFileExists,
      workerBootstrapAvailable: workerBootstrap != null,
      ledgerImportable: bootstrap?.ledgerImportCandidates.isNotEmpty == true,
      issue: issue,
    );
  }

  bool _importBootstrapLedgerCandidates(
    CapsulePersistenceBindings hivra,
    CapsuleRuntimeBootstrap bootstrap,
  ) {
    final candidates = bootstrap.ledgerImportCandidates
        .where((candidate) => candidate.trim().isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return true;
    }

    for (final candidate in candidates) {
      if (hivra.importLedger(candidate)) {
        return true;
      }
    }
    return false;
  }

  Future<CapsuleTraceReport> diagnoseCapsuleTraces(
      CapsulePersistenceBindings hivra) async {
    final activeHex = await resolveActiveCapsuleHex(hivra);
    final runtimePubKey = hivra.capsuleRuntimeOwnerPublicKey();
    final runtimeHex = runtimePubKey != null && runtimePubKey.length == 32
        ? _bytesToHex(runtimePubKey)
        : null;
    final runtimeSeedExists = hivra.seedExists();

    final index = await _readIndex();
    final docs = await _fileStore.docsDirectory();

    var capsuleDirPath = docs.path;
    var capsuleDirExists = false;
    var ledgerFileExists = false;
    var stateFileExists = false;
    var backupFileExists = false;
    var indexHasEntry = false;
    var secureSeedExists = false;
    var fallbackSeedExists = false;

    if (activeHex != null && activeHex.isNotEmpty) {
      indexHasEntry = index.capsules.containsKey(activeHex);
      secureSeedExists = await _seedStore.readSecureEncoded(activeHex) != null;
      fallbackSeedExists = await _seedStore.hasFallback(activeHex);

      final capsuleDir = await _fileStore.capsuleDirForHex(activeHex);
      capsuleDirPath = capsuleDir.path;
      capsuleDirExists = await capsuleDir.exists();
      ledgerFileExists = await _fileStore.ledgerFile(capsuleDir).exists();
      stateFileExists = await _fileStore.stateFile(capsuleDir).exists();
      backupFileExists = await _fileStore.backupFile(capsuleDir).exists();
    }

    return CapsuleTraceReport(
      activePubKeyHex: activeHex,
      runtimePubKeyHex: runtimeHex,
      runtimeSeedExists: runtimeSeedExists,
      indexHasEntry: indexHasEntry,
      secureSeedExists: secureSeedExists,
      fallbackSeedExists: fallbackSeedExists,
      capsuleDirPath: capsuleDirPath,
      capsuleDirExists: capsuleDirExists,
      ledgerFileExists: ledgerFileExists,
      stateFileExists: stateFileExists,
      backupFileExists: backupFileExists,
      legacyDocsPath: docs.path,
      legacyLedgerExists: await _fileStore.legacyLedgerFile(docs).exists(),
      legacyStateExists: await _fileStore.legacyStateFile(docs).exists(),
      legacyBackupExists: await _fileStore.legacyBackupFile(docs).exists(),
    );
  }

  Future<void> deleteActiveCapsule(CapsulePersistenceBindings hivra) async {
    final pubKeyHex = await resolveActiveCapsuleHex(hivra);
    if (pubKeyHex == null || pubKeyHex.isEmpty) return;
    await deleteCapsule(pubKeyHex, deleteLocalData: true, hivra: hivra);
  }

  Future<String> getCurrentBackupPath(CapsulePersistenceBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra, create: true);
    return _fileStore.backupPath(dir);
  }

  Future<String> getCurrentLedgerPath(CapsulePersistenceBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra, create: true);
    return _fileStore.ledgerPath(dir);
  }

  Future<List<CapsuleIndexEntry>> listCapsules(
      {CapsulePersistenceBindings? hivra}) async {
    if (hivra != null) {
      await _ensureIndexFromCurrentSeed(hivra);
      await _reconcileCapsuleIdentityIndex(hivra);
    }
    final index = await _readIndex();
    final entries = <CapsuleIndexEntry>[];
    for (final entry in index.capsules.values) {
      entries.add(entry);
    }
    entries.sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return entries;
  }

  Future<CapsuleLedgerSummary> loadCapsuleSummary(String pubKeyHex) async {
    final capsuleDir = await _capsuleDirForHex(pubKeyHex);
    final raw = await _fileStore.readLedger(capsuleDir);
    if (raw == null) {
      return CapsuleLedgerSummary.empty();
    }
    try {
      return _summaryParser.parse(raw, _bytesToHex);
    } catch (_) {
      return CapsuleLedgerSummary.empty();
    }
  }

  Future<String?> loadCapsuleLedgerOwnerHex(String pubKeyHex) async {
    return _readLedgerOwnerHexForCapsule(pubKeyHex);
  }

  Future<String> resolveDisplayCapsuleKey(
    CapsulePersistenceBindings hivra,
    String pubKeyHex,
  ) async {
    final currentRoot = hivra.capsuleRootPublicKey();
    final currentLegacy = hivra.capsuleRuntimeOwnerPublicKey();
    if (currentRoot != null &&
        currentRoot.length == 32 &&
        currentLegacy != null &&
        currentLegacy.length == 32 &&
        _bytesToHex(currentLegacy) == pubKeyHex) {
      return _encodeCapsuleKey(currentRoot);
    }

    final seed = await _loadSeedForCapsule(pubKeyHex);
    if (seed != null) {
      final rootPubKey = hivra.seedRootPublicKey(seed);
      if (rootPubKey != null && rootPubKey.length == 32) {
        return _encodeCapsuleKey(rootPubKey);
      }
    }

    return _encodeCapsuleKey(_hexToBytes(pubKeyHex));
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(
    String pubKeyHex, {
    CapsulePersistenceBindings? hivra,
  }) async {
    final index = await _readIndex();
    return _runtimeBootstrapService.loadRuntimeBootstrap(
      pubKeyHex,
      identityMode:
          _identityModeForCapsule(indexEntry: index.capsules[pubKeyHex]),
      runtime:
          hivra != null ? HivraCapsuleRuntimeBootstrapRuntime(hivra) : null,
      bytesToHex: _bytesToHex,
    );
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrapForCurrent(
      CapsulePersistenceBindings hivra) async {
    return _runtimeBootstrapService.loadRuntimeBootstrapForCurrent(
      HivraCapsuleRuntimeBootstrapRuntime(hivra),
      bytesToHex: _bytesToHex,
    );
  }

  Future<Map<String, Object?>?> loadWorkerBootstrapArgs(
      CapsulePersistenceBindings hivra) async {
    final activeHex = await resolveActiveCapsuleHex(hivra);
    CapsuleRuntimeBootstrap? bootstrap;
    if (activeHex != null && activeHex.isNotEmpty) {
      bootstrap = await loadRuntimeBootstrap(activeHex);
    }
    bootstrap ??= await loadRuntimeBootstrapForCurrent(hivra);
    if (bootstrap == null) return null;

    return <String, Object?>{
      'activeCapsuleHex': activeHex,
      'seed': bootstrap.seed,
      'isGenesis': bootstrap.isGenesis,
      'isNeste': bootstrap.isNeste,
      'identityMode': bootstrap.identityMode,
      'ledgerJson': bootstrap.ledgerJson,
    };
  }

  Future<String?> exportCapsuleBackupToPath(
      String pubKeyHex, String targetPath) async {
    final capsuleDir = await _capsuleDirForHex(pubKeyHex);
    final ledgerJson = await _fileStore.readLedger(capsuleDir);
    if (ledgerJson == null) return null;

    final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
      ledgerJson: ledgerJson,
    );
    final outFile = File(targetPath);
    await outFile.writeAsString(backupJson, flush: true);
    return outFile.path;
  }

  Future<bool> refreshCapsuleSnapshot(
      CapsulePersistenceBindings hivra, String pubKeyHex) async {
    final index = await _readIndex();
    return _runtimeBootstrapService.refreshCapsuleSnapshot(
      HivraCapsuleRuntimeBootstrapRuntime(hivra),
      pubKeyHex,
      identityMode:
          _identityModeForCapsule(indexEntry: index.capsules[pubKeyHex]),
      bytesToHex: _bytesToHex,
    );
  }

  Future<String?> importCapsuleFromBackupJson(String rawJson) async {
    final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(rawJson);
    if (ledgerJson == null) return null;

    final ownerHex = _extractOwnerHex(ledgerJson);
    if (ownerHex == null) return null;

    final capsuleDir = await _capsuleDirForHex(ownerHex, create: true);
    await _fileStore.writeLedger(capsuleDir, ledgerJson);
    await _fileStore.writeBackup(capsuleDir, rawJson);

    final meta = _extractBackupMeta(rawJson);
    await _upsertCapsuleIndex(
      ownerHex,
      isGenesis: meta?.isGenesis,
      isNeste: meta?.isNeste,
    );
    await _setActiveCapsule(ownerHex);
    return ownerHex;
  }

  Future<void> deleteCapsule(
    String pubKeyHex, {
    bool deleteLocalData = false,
    CapsulePersistenceBindings? hivra,
  }) async {
    final index = await _readIndex();
    final keysToDelete = await _resolveDeleteKeys(
      pubKeyHex,
      index: index,
      hivra: hivra,
    );

    if (hivra != null) {
      final currentPubKey = hivra.capsuleRuntimeOwnerPublicKey();
      final currentHex = currentPubKey != null && currentPubKey.length == 32
          ? _bytesToHex(currentPubKey)
          : null;
      if (currentHex != null && keysToDelete.contains(currentHex)) {
        hivra.resetCapsule();
      }
    }

    for (final key in keysToDelete) {
      if (deleteLocalData) {
        await _fileStore.deleteCapsuleDir(key);
        await _deleteLegacyFilesForCapsule(key);
        await _cleanupCapsuleArtifactsEverywhere(key);
      }
      await _seedStore.deleteSeed(key);
      index.capsules.remove(key);
      if (index.activePubKeyHex == key) {
        index.activePubKeyHex = null;
      }
    }

    if (index.activePubKeyHex == null || index.activePubKeyHex!.isEmpty) {
      index.activePubKeyHex = await _recoverActiveCapsuleHexFromIndex(index);
    }
    await _writeIndex(index);
  }

  Future<bool> hasStoredSeed(String pubKeyHex) async {
    return _seedStore.hasStoredSeed(pubKeyHex);
  }

  Future<bool> seedMatchesCapsule(
    CapsulePersistenceBindings hivra,
    Uint8List seed,
    String pubKeyHex, {
    String identityMode = 'root_owner',
  }) async {
    if (identityMode == 'root_owner') {
      final derivedPubKey = hivra.seedRootPublicKey(seed);
      if (derivedPubKey == null || derivedPubKey.length != 32) return false;
      return _bytesToHex(derivedPubKey) == pubKeyHex;
    }

    if (identityMode == 'legacy_nostr_owner') {
      final derivedPubKey = hivra.seedNostrPublicKey(seed);
      if (derivedPubKey == null || derivedPubKey.length != 32) return false;
      return _bytesToHex(derivedPubKey) == pubKeyHex;
    }

    final rootPubKey = hivra.seedRootPublicKey(seed);
    if (rootPubKey != null &&
        rootPubKey.length == 32 &&
        _bytesToHex(rootPubKey) == pubKeyHex) {
      return true;
    }

    final nostrPubKey = hivra.seedNostrPublicKey(seed);
    if (nostrPubKey != null &&
        nostrPubKey.length == 32 &&
        _bytesToHex(nostrPubKey) == pubKeyHex) {
      return true;
    }

    return false;
  }

  String _identityModeForCapsule({CapsuleIndexEntry? indexEntry}) {
    return indexEntry?.identityMode ?? 'root_owner';
  }

  int _ownerModeCode(String identityMode) {
    return identityMode == 'legacy_nostr_owner'
        ? CapsulePersistenceOwnerMode.legacyNostrOwnerMode
        : CapsulePersistenceOwnerMode.rootOwnerMode;
  }

  Future<void> saveSeedForCapsule(String pubKeyHex, Uint8List seed) async {
    await _storeSeedForCapsule(pubKeyHex, seed);
  }

  Future<void> activateCapsule(
      CapsulePersistenceBindings hivra, String pubKeyHex) async {
    await _reconcileCapsuleIdentityIndex(hivra);
    final index = await _readIndex();
    final targetEntry = index.capsules[pubKeyHex];
    final targetIdentityMode = _identityModeForCapsule(indexEntry: targetEntry);
    final storedSeed = await _loadSeedForCapsule(pubKeyHex);
    if (storedSeed != null) {
      final seedMatchesTarget = await seedMatchesCapsule(
        hivra,
        storedSeed,
        pubKeyHex,
        identityMode: targetIdentityMode,
      );
      if (!seedMatchesTarget) {
        final seedOwner = await _findOwnerForSeed(
          hivra,
          index,
          storedSeed,
          excludePubKeyHex: pubKeyHex,
        );
        final ownerSuffix = seedOwner == null
            ? ''
            : ' Seed belongs to another capsule: $seedOwner.';
        throw Exception(
          'Stored seed does not match selected capsule.$ownerSuffix Restore this capsule from its seed phrase.',
        );
      }
      if (!hivra.saveSeed(storedSeed)) {
        throw Exception('Failed to save seed into runtime');
      }
    } else {
      // Fallback: if current keychain seed matches target pubkey, keep it.
      final currentPubKey = hivra.capsuleRuntimeOwnerPublicKey();
      final currentHex = currentPubKey != null && currentPubKey.length == 32
          ? _bytesToHex(currentPubKey)
          : null;
      if (currentHex != pubKeyHex) {
        throw Exception('Seed not found for capsule');
      }
      final currentSeed = hivra.loadSeed();
      if (currentSeed != null) {
        final seedMatchesTarget = await seedMatchesCapsule(
          hivra,
          currentSeed,
          pubKeyHex,
          identityMode: targetIdentityMode,
        );
        if (!seedMatchesTarget) {
          throw Exception(
            'Runtime seed does not match selected capsule. Restore this capsule from its seed phrase.',
          );
        }
        await _storeSeedForCapsule(pubKeyHex, currentSeed);
      }
    }
    await _setActiveCapsule(pubKeyHex);
    await _syncLocalCapsuleContactCards(hivra);
  }

  Future<Map<String, dynamic>?> _readStateForCurrentCapsule(
      CapsulePersistenceBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra);
    return _fileStore.readState(dir);
  }

  Future<Directory> _currentCapsuleDir(CapsulePersistenceBindings? hivra,
      {bool create = false}) async {
    final docs = await _fileStore.docsDirectory();
    String? capsuleId;
    if (hivra != null) {
      final pubKey = hivra.capsuleRuntimeOwnerPublicKey();
      if (pubKey != null && pubKey.length == 32) {
        capsuleId = _bytesToHex(pubKey);
      }
    }
    if (capsuleId == null || capsuleId.isEmpty) return docs;

    final dir = await _fileStore.capsuleDirForHex(capsuleId, create: false);
    final existed = await dir.exists();
    if (create && !existed) {
      await _fileStore.capsuleDirForHex(capsuleId, create: true);
      await _migrateLegacyToCapsuleDir(docs, dir, capsuleId);
    }
    return dir;
  }

  Future<Directory> _capsuleDirForHex(String pubKeyHex,
      {bool create = false}) async {
    final docs = await _fileStore.docsDirectory();
    final dir = await _fileStore.capsuleDirForHex(pubKeyHex, create: false);
    final existed = await dir.exists();
    if (create && !existed) {
      await _fileStore.capsuleDirForHex(pubKeyHex, create: true);
      await _migrateLegacyToCapsuleDir(docs, dir, pubKeyHex);
    }
    return dir;
  }

  Future<void> _migrateLegacyToCapsuleDir(
    Directory docs,
    Directory target,
    String pubKeyHex,
  ) async {
    final legacyState = _fileStore.legacyStateFile(docs);
    final legacyLedger = _fileStore.legacyLedgerFile(docs);
    final legacyBackup = _fileStore.legacyBackupFile(docs);

    if (!await legacyLedger.exists()) return;
    try {
      final raw = await legacyLedger.readAsString();
      final ledger = _parseLedgerRoot(raw);
      if (ledger == null) return;
      final ownerHex = _ownerHexFromLedgerRoot(ledger);
      if (ownerHex != pubKeyHex) return;
    } catch (_) {
      return;
    }

    if (await legacyState.exists()) {
      await legacyState
          .rename('${target.path}/${CapsuleFileStore.stateFileName}');
    }
    if (await legacyLedger.exists()) {
      await legacyLedger
          .rename('${target.path}/${CapsuleFileStore.ledgerFileName}');
    }
    if (await legacyBackup.exists()) {
      await legacyBackup
          .rename('${target.path}/${CapsuleFileStore.backupFileName}');
    }
  }

  Future<void> _deleteLegacyFilesForCapsule(String pubKeyHex) async {
    final docs = await _fileStore.docsDirectory();
    final legacyLedger = _fileStore.legacyLedgerFile(docs);
    if (!await legacyLedger.exists()) return;

    try {
      final raw = await legacyLedger.readAsString();
      final ledger = _parseLedgerRoot(raw);
      if (ledger == null) return;
      final ownerHex = _ownerHexFromLedgerRoot(ledger);
      if (ownerHex != pubKeyHex) return;
    } catch (_) {
      return;
    }

    final legacyState = _fileStore.legacyStateFile(docs);
    final legacyBackup = _fileStore.legacyBackupFile(docs);
    if (await legacyState.exists()) {
      await legacyState.delete();
    }
    if (await legacyLedger.exists()) {
      await legacyLedger.delete();
    }
    if (await legacyBackup.exists()) {
      await legacyBackup.delete();
    }
  }

  Future<void> _cleanupCapsuleArtifactsEverywhere(String pubKeyHex) async {
    final currentRoot = await _fileStore.docsDirectory();
    await _removeCapsuleArtifactsUnderRoot(currentRoot, pubKeyHex);

    final legacyDocs =
        await _userVisibleDirs.legacyContainerDocumentsDirectory();
    if (legacyDocs == null) return;
    await _removeCapsuleArtifactsUnderRoot(legacyDocs, pubKeyHex);
    await _removeCapsuleArtifactsUnderRoot(
      Directory('${legacyDocs.path}/Hivra'),
      pubKeyHex,
    );
  }

  Future<void> _removeCapsuleArtifactsUnderRoot(
    Directory root,
    String pubKeyHex,
  ) async {
    if (!await root.exists()) return;

    final capsulesDir = Directory('${root.path}/capsules');
    final capsuleDir = Directory('${capsulesDir.path}/$pubKeyHex');
    if (await capsuleDir.exists()) {
      await capsuleDir.delete(recursive: true);
    }

    await _removeCapsuleFromIndexFile(
      File('${capsulesDir.path}/capsules_index.json'),
      pubKeyHex,
    );
    await _removeCapsuleFromSeedsFile(
      File('${capsulesDir.path}/capsule_seeds.json'),
      pubKeyHex,
    );
    await _removeCapsuleFromContactCards(
      File('${root.path}/capsule_contact_cards.json'),
      pubKeyHex,
    );
  }

  Future<void> _removeCapsuleFromIndexFile(
    File indexFile,
    String pubKeyHex,
  ) async {
    if (!await indexFile.exists()) return;
    try {
      final raw = await indexFile.readAsString();
      final root = _parseJsonMap(raw);
      if (root == null) return;

      final active = root['active']?.toString();
      final capsulesRaw = root['capsules'];
      if (capsulesRaw is! Map) return;

      final capsules = Map<String, dynamic>.from(capsulesRaw);
      capsules.remove(pubKeyHex);
      root['capsules'] = capsules;
      if (active == pubKeyHex) {
        root['active'] = null;
      }
      await indexFile.writeAsString(jsonEncode(root), flush: true);
    } catch (_) {}
  }

  Future<void> _removeCapsuleFromSeedsFile(
    File seedsFile,
    String pubKeyHex,
  ) async {
    if (!await seedsFile.exists()) return;
    try {
      final raw = await seedsFile.readAsString();
      final map = _parseJsonMap(raw);
      if (map == null) return;
      map.remove(pubKeyHex);
      await seedsFile.writeAsString(jsonEncode(map), flush: true);
    } catch (_) {}
  }

  Future<void> _removeCapsuleFromContactCards(
    File cardsFile,
    String pubKeyHex,
  ) async {
    if (!await cardsFile.exists()) return;
    try {
      final raw = await cardsFile.readAsString();
      final cards = _parseJsonMap(raw);
      if (cards == null) return;
      final keysToRemove = <String>[];
      for (final entry in cards.entries) {
        if (shouldRemoveCapsuleContactCardEntry(
          entryKey: entry.key,
          entryValue: entry.value,
          deleteKeyHex: pubKeyHex,
        )) {
          keysToRemove.add(entry.key);
        }
      }
      for (final key in keysToRemove) {
        cards.remove(key);
      }
      await cardsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(cards),
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _storeSeedForCapsule(String pubKeyHex, Uint8List seed) async {
    await _seedStore.storeSeed(pubKeyHex, seed);
  }

  Future<Uint8List?> _loadSeedForCapsule(String pubKeyHex) async {
    return _seedStore.loadSeed(pubKeyHex);
  }

  Future<Set<String>> _resolveDeleteKeys(
    String pubKeyHex, {
    required CapsulesIndex index,
    CapsulePersistenceBindings? hivra,
  }) async {
    final keys = <String>{pubKeyHex};

    var baseSeed = await _loadSeedForCapsule(pubKeyHex);
    if (baseSeed == null && hivra != null) {
      final targetEntry = index.capsules[pubKeyHex];
      for (final entry in index.capsules.values) {
        final candidateSeed = await _loadSeedForCapsule(entry.pubKeyHex);
        if (candidateSeed == null) continue;
        if (await seedMatchesCapsule(
          hivra,
          candidateSeed,
          pubKeyHex,
          identityMode: _identityModeForCapsule(indexEntry: targetEntry),
        )) {
          baseSeed = candidateSeed;
          break;
        }
      }
    }

    if (baseSeed != null && hivra != null) {
      final rootHex = _hexFromKey(hivra.seedRootPublicKey(baseSeed));
      final nostrHex = _hexFromKey(hivra.seedNostrPublicKey(baseSeed));
      if (rootHex != null && rootHex.isNotEmpty) keys.add(rootHex);
      if (nostrHex != null && nostrHex.isNotEmpty) keys.add(nostrHex);
    }

    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in index.capsules.values) {
        final candidateHex = entry.pubKeyHex;
        if (candidateHex.isEmpty || keys.contains(candidateHex)) continue;

        final candidateSeed = await _loadSeedForCapsule(candidateHex);
        if (baseSeed != null &&
            candidateSeed != null &&
            _sameBytes(candidateSeed, baseSeed)) {
          keys.add(candidateHex);
          changed = true;
          continue;
        }

        if (candidateSeed == null) {
          final ownerHex = await _readLedgerOwnerHexForCapsule(candidateHex);
          if (ownerHex != null && keys.contains(ownerHex)) {
            keys.add(candidateHex);
            changed = true;
          }
        }
      }
    }

    return keys;
  }

  Future<String?> _readLedgerOwnerHexForCapsule(String pubKeyHex) async {
    final capsuleDir = await _capsuleDirForHex(pubKeyHex);
    final ledgerJson = await _fileStore.readLedger(capsuleDir);
    if (ledgerJson == null || ledgerJson.isEmpty) return null;
    return _extractOwnerHex(ledgerJson);
  }

  Future<void> _reconcileCapsuleIdentityIndex(
      CapsulePersistenceBindings hivra) async {
    final index = await _readIndex();
    if (index.capsules.length < 2) return;

    final bindingsByPubKey = <String, CapsuleIdentityBinding>{};
    for (final entry in index.capsules.values) {
      final pubKeyHex = entry.pubKeyHex;
      if (pubKeyHex.isEmpty) continue;
      final seed = await _loadSeedForCapsule(pubKeyHex);
      if (seed == null) continue;

      bindingsByPubKey[pubKeyHex] = CapsuleIdentityBinding(
        seedFingerprint: base64.encode(seed),
        rootPubKeyHex: _hexFromKey(hivra.seedRootPublicKey(seed)),
        nostrPubKeyHex: _hexFromKey(hivra.seedNostrPublicKey(seed)),
      );
    }

    final reconciled = _identityReconciler.reconcile(
      index: index,
      bindingsByPubKey: bindingsByPubKey,
    );
    final resultIndex = reconciled.index;
    if (reconciled.seedAliasToCanonical.isEmpty &&
        _sameIndexState(index, resultIndex)) {
      return;
    }

    for (final move in reconciled.seedAliasToCanonical.entries) {
      final aliasPubKeyHex = move.key;
      final canonicalPubKeyHex = move.value;
      final aliasSeed = await _loadSeedForCapsule(aliasPubKeyHex);
      if (aliasSeed != null) {
        await _storeSeedForCapsule(canonicalPubKeyHex, aliasSeed);
      }
    }
    for (final aliasPubKeyHex in reconciled.seedAliasToCanonical.keys) {
      await _seedStore.deleteSeed(aliasPubKeyHex);
    }

    await _writeIndex(resultIndex);
  }

  Future<void> _syncLocalCapsuleContactCards(
      CapsulePersistenceBindings hivra) async {
    final index = await _readIndex();
    if (index.capsules.isEmpty) return;

    final cardsFile = await _contactCardsFile();
    final cards = await _readContactCards(cardsFile);
    var changed = false;

    for (final entry in index.capsules.values) {
      final seed = await _loadSeedForCapsule(entry.pubKeyHex);
      if (seed == null) continue;

      final root = hivra.seedRootPublicKey(seed);
      final nostr = hivra.seedNostrPublicKey(seed);
      if (root == null ||
          root.length != 32 ||
          nostr == null ||
          nostr.length != 32) {
        continue;
      }

      final rootBytes = Uint8List.fromList(root);
      final nostrBytes = Uint8List.fromList(nostr);
      final rootHex = _bytesToHex(rootBytes);
      final expected = <String, dynamic>{
        'version': 1,
        'rootKey': _encodeCapsuleKey(rootBytes),
        'rootHex': rootHex,
        'transports': {
          'nostr': {
            'npub': _encodeBech32Key('npub', nostrBytes),
            'hex': _bytesToHex(nostrBytes),
          },
        },
      };

      final existing = cards[rootHex];
      if (_normalizedJson(existing) != _normalizedJson(expected)) {
        cards[rootHex] = expected;
        changed = true;
      }
    }

    if (!changed) return;
    await cardsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(cards),
      flush: true,
    );
  }

  Future<File> _contactCardsFile() async {
    final root = await _userVisibleDirs.rootDirectory(create: true);
    final file = File('${root.path}/capsule_contact_cards.json');
    if (!await file.exists()) {
      await file.writeAsString('{}', flush: true);
    }
    return file;
  }

  Future<Map<String, dynamic>> _readContactCards(File file) async {
    try {
      final raw = await file.readAsString();
      return _parseJsonMap(raw) ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _normalizedJson(Object? value) {
    if (value is Map<String, dynamic>) return jsonEncode(value);
    if (value is Map) return jsonEncode(Map<String, dynamic>.from(value));
    return '';
  }

  bool _sameIndexState(CapsulesIndex a, CapsulesIndex b) {
    if (a.activePubKeyHex != b.activePubKeyHex) return false;
    if (a.capsules.length != b.capsules.length) return false;
    for (final entry in a.capsules.entries) {
      final other = b.capsules[entry.key];
      if (other == null) return false;
      final current = entry.value;
      if (current.pubKeyHex != other.pubKeyHex) return false;
      if (current.createdAt != other.createdAt) return false;
      if (current.lastActive != other.lastActive) return false;
      if (current.isGenesis != other.isGenesis) return false;
      if (current.isNeste != other.isNeste) return false;
      if (current.identityMode != other.identityMode) return false;
    }
    return true;
  }

  Future<String?> _findCapsuleForSeed(
    CapsulesIndex index,
    Uint8List seed, {
    String? excludePubKeyHex,
  }) async {
    for (final entry in index.capsules.values) {
      final pubKeyHex = entry.pubKeyHex;
      if (pubKeyHex.isEmpty || pubKeyHex == excludePubKeyHex) continue;
      final storedSeed = await _loadSeedForCapsule(pubKeyHex);
      if (storedSeed == null) continue;
      if (_sameBytes(seed, storedSeed)) {
        return pubKeyHex;
      }
    }
    return null;
  }

  Future<String?> _findOwnerForSeed(
    CapsulePersistenceBindings hivra,
    CapsulesIndex index,
    Uint8List seed, {
    String? excludePubKeyHex,
  }) async {
    for (final entry in index.capsules.values) {
      final pubKeyHex = entry.pubKeyHex;
      if (pubKeyHex.isEmpty || pubKeyHex == excludePubKeyHex) continue;
      final matches = await seedMatchesCapsule(
        hivra,
        seed,
        pubKeyHex,
        identityMode: _identityModeForCapsule(indexEntry: entry),
      );
      if (matches) {
        return pubKeyHex;
      }
    }
    return null;
  }

  bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<String?> _recoverActiveCapsuleHexFromIndex(
    CapsulesIndex index, {
    Set<String> exclude = const <String>{},
    CapsulePersistenceBindings? hivra,
  }) async {
    final candidates = index.capsules.values.toList()
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));

    for (final entry in candidates) {
      final pubKeyHex = entry.pubKeyHex;
      if (pubKeyHex.isEmpty || exclude.contains(pubKeyHex)) continue;
      if (!await _seedStore.hasStoredSeed(pubKeyHex)) continue;
      if (hivra == null) {
        return pubKeyHex;
      }
      final bootstrap = await loadRuntimeBootstrap(
        pubKeyHex,
        hivra: hivra,
      );
      if (bootstrap != null) {
        return pubKeyHex;
      }
    }
    return null;
  }

  String? _hexFromKey(Uint8List? key) {
    if (key == null || key.length != 32) return null;
    return _bytesToHex(key);
  }

  Future<void> _touchActiveCapsule(CapsulePersistenceBindings hivra) async {
    final runtimeHex = _hexFromKey(hivra.capsuleRuntimeOwnerPublicKey());
    if (runtimeHex == null || runtimeHex.isEmpty) return;

    final rootHex = _hexFromKey(hivra.capsuleRootPublicKey());
    final index = await _readIndex();
    final activeHex = index.activePubKeyHex;

    var pubKeyHex = runtimeHex;
    if (activeHex != null &&
        activeHex.isNotEmpty &&
        (activeHex == runtimeHex || activeHex == rootHex)) {
      pubKeyHex = activeHex;
    } else if (rootHex != null &&
        rootHex.isNotEmpty &&
        await _seedStore.hasStoredSeed(rootHex)) {
      pubKeyHex = rootHex;
    } else if (activeHex != null &&
        activeHex.isNotEmpty &&
        await _seedStore.hasStoredSeed(activeHex)) {
      pubKeyHex = activeHex;
    }

    await _upsertCapsuleIndex(
      pubKeyHex,
      identityMode: _detectIdentityMode(hivra, pubKeyHex),
    );
    await _setActiveCapsule(pubKeyHex);
    await _reconcileCapsuleIdentityIndex(hivra);
  }

  Future<void> _upsertCapsuleIndex(
    String pubKeyHex, {
    bool? isGenesis,
    bool? isNeste,
    String? identityMode,
  }) async {
    await _indexStore.upsert(
      pubKeyHex,
      isGenesis: isGenesis,
      isNeste: isNeste,
      identityMode: identityMode,
    );
  }

  Future<void> _setActiveCapsule(String pubKeyHex) async {
    await _indexStore.setActive(pubKeyHex);
  }

  Future<CapsulesIndex> _readIndex() async {
    return _indexStore.read();
  }

  Future<void> _writeIndex(CapsulesIndex index) async {
    await _indexStore.write(index);
  }

  Future<void> _ensureIndexFromCurrentSeed(
      CapsulePersistenceBindings hivra) async {
    final index = await _readIndex();
    if (index.capsules.isNotEmpty) return;
    if (!hivra.seedExists()) return;
    final pubKey = hivra.capsuleRuntimeOwnerPublicKey();
    if (pubKey == null || pubKey.length != 32) return;
    final pubKeyHex = _bytesToHex(pubKey);

    await _capsuleDirForHex(pubKeyHex, create: true);
    final currentSeed = hivra.loadSeed();
    if (currentSeed != null) {
      await _storeSeedForCapsule(pubKeyHex, currentSeed);
    }
    final state = await _readStateForCapsuleHex(pubKeyHex);
    await _upsertCapsuleIndex(
      pubKeyHex,
      isGenesis: state?['isGenesis'] == true,
      isNeste: state?['isNeste'] != false,
      identityMode: _detectIdentityMode(hivra, pubKeyHex),
    );
    await _setActiveCapsule(pubKeyHex);
  }

  String _detectIdentityMode(
      CapsulePersistenceBindings hivra, String pubKeyHex) {
    final rootPubKey = hivra.capsuleRootPublicKey();
    final rootHex = rootPubKey != null && rootPubKey.length == 32
        ? _bytesToHex(rootPubKey)
        : null;
    if (rootHex != null && rootHex == pubKeyHex) {
      return 'root_owner';
    }

    final nostrPubKey = hivra.capsuleNostrPublicKey();
    final nostrHex = nostrPubKey != null && nostrPubKey.length == 32
        ? _bytesToHex(nostrPubKey)
        : null;
    if (nostrHex != null && nostrHex == pubKeyHex) {
      return 'legacy_nostr_owner';
    }

    return 'mixed_or_unknown';
  }

  Future<Map<String, dynamic>?> _readStateForCapsuleHex(
      String pubKeyHex) async {
    final dir = await _capsuleDirForHex(pubKeyHex);
    return _fileStore.readState(dir);
  }

  String _bytesToHex(Uint8List bytes) {
    final b = StringBuffer();
    for (final byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  Uint8List _hexToBytes(String hex) {
    final normalized = hex.length.isEven ? hex : '0$hex';
    final out = Uint8List(normalized.length ~/ 2);
    for (var i = 0; i < normalized.length; i += 2) {
      out[i ~/ 2] = int.parse(normalized.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  String _encodeCapsuleKey(Uint8List bytes) {
    return _encodeBech32Key('h', bytes);
  }

  String _encodeBech32Key(String hrp, Uint8List bytes) {
    final words = _convertBits(bytes, 8, 5, true);
    return bech32.encode(Bech32(hrp, words));
  }

  List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxValue = (1 << to) - 1;

    for (final value in data) {
      if (value < 0 || (value >> from) != 0) {
        throw ArgumentError('Invalid key byte for bech32 conversion');
      }
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxValue);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (to - bits)) & maxValue);
      }
    } else if (bits >= from || ((acc << (to - bits)) & maxValue) != 0) {
      throw ArgumentError('Invalid bech32 padding');
    }

    return result;
  }

  String? _extractOwnerHex(String ledgerJson) {
    final ledger = _parseLedgerRoot(ledgerJson);
    if (ledger == null) return null;
    return _ownerHexFromLedgerRoot(ledger);
  }

  int? _extractLedgerEventCount(String? ledgerJson) {
    final root = _parseLedgerRoot(ledgerJson);
    if (root == null) return null;
    return _support.events(root).length;
  }

  String? _extractLedgerHash(String? ledgerJson) {
    final root = _parseLedgerRoot(ledgerJson);
    if (root == null) return null;
    return root['last_hash']?.toString();
  }

  bool _isIncomingLedgerStale({
    required String incomingLedgerJson,
    required String? existingLedgerJson,
  }) {
    if (existingLedgerJson == null || existingLedgerJson.trim().isEmpty) {
      return false;
    }

    final incomingCount = _extractLedgerEventCount(incomingLedgerJson);
    final existingCount = _extractLedgerEventCount(existingLedgerJson);
    if (incomingCount == null || existingCount == null) {
      return false;
    }

    if (incomingCount < existingCount) {
      return true;
    }

    if (incomingCount > existingCount) {
      return false;
    }

    final incomingHash = _extractLedgerHash(incomingLedgerJson);
    final existingHash = _extractLedgerHash(existingLedgerJson);
    if (incomingHash == null || existingHash == null) {
      return false;
    }
    return incomingHash != existingHash;
  }

  _BackupMeta? _extractBackupMeta(String rawJson) {
    final map = _parseJsonMap(rawJson);
    if (map == null) return null;
    final metaRaw = map['meta'];
    if (metaRaw is! Map) return null;
    final meta = Map<String, dynamic>.from(metaRaw);
    return _BackupMeta(
      isGenesis: meta['is_genesis'] == true
          ? true
          : (meta['is_genesis'] == false ? false : null),
      isNeste: meta['is_neste'] == true
          ? true
          : (meta['is_neste'] == false ? false : null),
    );
  }

  Map<String, dynamic>? _parseLedgerRoot(String? ledgerJson) {
    return _support.exportLedgerRoot(ledgerJson);
  }

  Map<String, dynamic>? _parseJsonMap(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _ownerHexFromLedgerRoot(Map<String, dynamic> ledger) {
    final ownerBytes = _summaryParser.parseBytesField(ledger['owner']);
    if (ownerBytes == null || ownerBytes.length != 32) return null;
    return _bytesToHex(Uint8List.fromList(ownerBytes));
  }
}

class _BackupMeta {
  final bool? isGenesis;
  final bool? isNeste;

  _BackupMeta({required this.isGenesis, required this.isNeste});
}
