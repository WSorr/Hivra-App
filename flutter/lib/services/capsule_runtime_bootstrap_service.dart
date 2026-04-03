import 'dart:convert';
import 'dart:typed_data';

import '../ffi/capsule_runtime_bootstrap_runtime.dart';
import 'capsule_backup_codec.dart';
import 'capsule_file_store.dart';
import 'capsule_ledger_summary_parser.dart';
import 'capsule_persistence_models.dart';
import 'capsule_seed_store.dart';
import 'ledger_view_support.dart';

class CapsuleRuntimeBootstrapService {
  final CapsuleFileStore _fileStore;
  final CapsuleSeedStore _seedStore;
  final CapsuleLedgerSummaryParser _summaryParser;
  final LedgerViewSupport _support;

  const CapsuleRuntimeBootstrapService(
    this._fileStore,
    this._seedStore, {
    CapsuleLedgerSummaryParser summaryParser =
        const CapsuleLedgerSummaryParser(),
    LedgerViewSupport support = const LedgerViewSupport(),
  })  : _summaryParser = summaryParser,
        _support = support;

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(
    String pubKeyHex, {
    String identityMode = 'root_owner',
    CapsuleRuntimeBootstrapRuntime? runtime,
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final seed = runtime == null
        ? await _seedStore.loadSeed(pubKeyHex)
        : await _seedStore.loadValidatedSeed(
            pubKeyHex,
            isValidSeed: (seed) => _seedMatchesCapsule(
              runtime,
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
    final stateGenesis = _stateGenesis(state);
    final stateNeste = _stateNeste(state);

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
    final orderedCandidates = _orderedLedgerCandidates(
      ledgerCandidate,
      backupCandidate,
    );
    final primaryLedgerRoot = orderedCandidates.isNotEmpty
        ? _parseLedgerRoot(orderedCandidates.first.json)
        : null;
    final ledgerJson =
        orderedCandidates.isNotEmpty ? orderedCandidates.first.json : null;
    final isGenesis = _support.inferGenesisFromLedgerRoot(primaryLedgerRoot) ??
        stateGenesis ??
        false;
    final isNeste = _support.inferNesteFromLedgerRoot(primaryLedgerRoot) ??
        stateNeste ??
        true;

    return CapsuleRuntimeBootstrap(
      pubKeyHex: pubKeyHex,
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      identityMode: identityMode,
      ledgerJson: ledgerJson,
      ledgerImportCandidates:
          orderedCandidates.map((candidate) => candidate.json).toList(),
    );
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrapForCurrent(
    CapsuleRuntimeBootstrapRuntime runtime, {
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final pubKey = runtime.capsuleRuntimeOwnerPublicKey();
    final seed = runtime.loadSeed();
    if (pubKey == null || pubKey.length != 32 || seed == null) return null;

    final dir = await _fileStore.currentCapsuleDir(
      runtime.capsuleRuntimeOwnerPublicKey,
      bytesToHex: bytesToHex,
      create: false,
    );
    final state = await _fileStore.readState(dir);
    final stateGenesis = _stateGenesis(state);
    final stateNeste = _stateNeste(state);
    final ledgerJson = runtime.exportLedger();
    final ledgerRoot = _parseLedgerRoot(ledgerJson);
    final isGenesis = _support.inferGenesisFromLedgerRoot(ledgerRoot) ??
        stateGenesis ??
        false;
    final isNeste =
        _support.inferNesteFromLedgerRoot(ledgerRoot) ?? stateNeste ?? true;
    final runtimeOwner = runtime.capsuleRuntimeOwnerPublicKey();
    final rootPubKey = runtime.capsuleRootPublicKey();
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
      ledgerImportCandidates: (ledgerJson != null && ledgerJson.isNotEmpty)
          ? <String>[ledgerJson]
          : const <String>[],
    );
  }

  Future<bool> refreshCapsuleSnapshot(
    CapsuleRuntimeBootstrapRuntime runtime,
    String pubKeyHex, {
    String identityMode = 'root_owner',
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final seed = await _seedStore.loadValidatedSeed(
      pubKeyHex,
      isValidSeed: (seed) => _seedMatchesCapsule(
        runtime,
        seed,
        pubKeyHex,
        bytesToHex,
        identityMode: identityMode,
      ),
      persistValidatedSeed: (seed) => _seedStore.storeSeed(pubKeyHex, seed),
    );
    if (seed == null) return false;
    if (!runtime.saveSeed(seed)) return false;

    final dir = await _fileStore.capsuleDirForHex(pubKeyHex, create: true);
    final state = await _fileStore.readState(dir);
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
    final orderedCandidates = _orderedLedgerCandidates(
      ledgerCandidate,
      backupCandidate,
    );
    final primaryLedgerRoot = orderedCandidates.isNotEmpty
        ? _parseLedgerRoot(orderedCandidates.first.json)
        : null;
    final isGenesis = _support.inferGenesisFromLedgerRoot(primaryLedgerRoot) ??
        _stateGenesis(state) ??
        false;
    final isNeste = _support.inferNesteFromLedgerRoot(primaryLedgerRoot) ??
        _stateNeste(state) ??
        true;
    if (!runtime.createCapsule(
      seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      ownerMode: identityMode == 'legacy_nostr_owner'
          ? runtime.legacyNostrOwnerMode
          : runtime.rootOwnerMode,
    )) {
      return false;
    }

    for (final candidate in orderedCandidates) {
      if (!runtime.importLedger(candidate.json)) {
        continue;
      }
      importedHistory = true;
      break;
    }
    if (hasStoredHistory && !importedHistory) return false;

    final exported = runtime.exportLedger();
    if (exported == null || exported.isEmpty) return false;
    await _fileStore.writeLedger(dir, exported);
    return true;
  }

  Future<bool> _seedMatchesCapsule(
    CapsuleRuntimeBootstrapRuntime runtime,
    Uint8List seed,
    String pubKeyHex,
    String Function(Uint8List bytes) bytesToHex, {
    required String identityMode,
  }) async {
    if (identityMode == 'root_owner') {
      final derivedPubKey = runtime.seedRootPublicKey(seed);
      if (derivedPubKey == null || derivedPubKey.length != 32) return false;
      return bytesToHex(derivedPubKey) == pubKeyHex;
    }

    if (identityMode == 'legacy_nostr_owner') {
      final derivedPubKey = runtime.seedNostrPublicKey(seed);
      if (derivedPubKey == null || derivedPubKey.length != 32) return false;
      return bytesToHex(derivedPubKey) == pubKeyHex;
    }

    final rootPubKey = runtime.seedRootPublicKey(seed);
    if (rootPubKey != null &&
        rootPubKey.length == 32 &&
        bytesToHex(rootPubKey) == pubKeyHex) {
      return true;
    }

    final nostrPubKey = runtime.seedNostrPublicKey(seed);
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
    final ledger = _parseLedgerRoot(ledgerJson);
    if (ledger == null) return null;
    final events = _support.events(ledger);
    final owner = _summaryParser.parseBytesField(ledger['owner']);
    if (owner == null || owner.length != 32) return null;
    if (bytesToHex(Uint8List.fromList(owner)) != pubKeyHex) return null;
    return _LedgerCandidate(
      source: source,
      json: jsonEncode(ledger),
      eventCount: events.length,
      tailTimestamp: _extractTailTimestamp(events),
    );
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
    if (ledger.tailTimestamp != null &&
        backup.tailTimestamp != null &&
        ledger.tailTimestamp != backup.tailTimestamp) {
      return (backup.tailTimestamp! > ledger.tailTimestamp!) ? backup : ledger;
    }
    // Deterministic tie-breaker: prefer ledger.json on equal history length.
    return ledger.source == _LedgerSource.ledger ? ledger : backup;
  }

  List<_LedgerCandidate> _orderedLedgerCandidates(
    _LedgerCandidate? ledger,
    _LedgerCandidate? backup,
  ) {
    final primary = _selectPreferredLedgerCandidate(ledger, backup);
    if (primary == null) return const <_LedgerCandidate>[];

    final secondary = identical(primary, ledger)
        ? backup
        : identical(primary, backup)
            ? ledger
            : null;
    if (secondary == null) return <_LedgerCandidate>[primary];
    return <_LedgerCandidate>[primary, secondary];
  }

  int? _extractTailTimestamp(List<dynamic> events) {
    int? tail;
    for (final raw in events) {
      if (raw is! Map) continue;
      final event = Map<String, dynamic>.from(raw);
      final ts = _parseTimestamp(event['timestamp']);
      if (ts == null) continue;
      if (tail == null || ts > tail) {
        tail = ts;
      }
    }
    return tail;
  }

  int? _parseTimestamp(dynamic raw) {
    if (raw is int) return raw >= 0 ? raw : null;
    if (raw is num) {
      final value = raw.toInt();
      return value >= 0 ? value : null;
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      if (text.startsWith('0x') || text.startsWith('0X')) {
        return int.tryParse(text.substring(2), radix: 16);
      }
      return int.tryParse(text);
    }
    return null;
  }

  Map<String, dynamic>? _parseLedgerRoot(String? ledgerJson) {
    return _support.exportLedgerRoot(ledgerJson);
  }

  bool? _stateGenesis(Map<String, dynamic>? state) {
    final raw = state?['isGenesis'];
    return raw is bool ? raw : null;
  }

  bool? _stateNeste(Map<String, dynamic>? state) {
    final raw = state?['isNeste'];
    return raw is bool ? raw : null;
  }
}

enum _LedgerSource { ledger, backup }

class _LedgerCandidate {
  final _LedgerSource source;
  final String json;
  final int eventCount;
  final int? tailTimestamp;

  const _LedgerCandidate({
    required this.source,
    required this.json,
    required this.eventCount,
    required this.tailTimestamp,
  });
}
