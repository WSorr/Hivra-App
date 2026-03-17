import 'dart:typed_data';

class CapsuleIndexEntry {
  final String pubKeyHex;
  final DateTime createdAt;
  final DateTime lastActive;
  final bool isGenesis;
  final bool isNeste;

  CapsuleIndexEntry({
    required this.pubKeyHex,
    required this.createdAt,
    required this.lastActive,
    required this.isGenesis,
    required this.isNeste,
  });

  Map<String, dynamic> toMap() => {
        'pubKeyHex': pubKeyHex,
        'createdAt': createdAt.toIso8601String(),
        'lastActive': lastActive.toIso8601String(),
        'isGenesis': isGenesis,
        'isNeste': isNeste,
      };

  static CapsuleIndexEntry fromMap(Map<String, dynamic> map) {
    final created = DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
        DateTime.now().toUtc();
    final last =
        DateTime.tryParse(map['lastActive']?.toString() ?? '') ?? created;
    return CapsuleIndexEntry(
      pubKeyHex: map['pubKeyHex']?.toString() ?? '',
      createdAt: created.toUtc(),
      lastActive: last.toUtc(),
      isGenesis: map['isGenesis'] == true,
      isNeste: map['isNeste'] != false,
    );
  }
}

class CapsuleLedgerSummary {
  final int starterCount;
  final int relationshipCount;
  final int pendingInvitations;
  final int ledgerVersion;
  final String ledgerHashHex;

  CapsuleLedgerSummary({
    required this.starterCount,
    required this.relationshipCount,
    required this.pendingInvitations,
    required this.ledgerVersion,
    required this.ledgerHashHex,
  });

  static CapsuleLedgerSummary empty() => CapsuleLedgerSummary(
        starterCount: 0,
        relationshipCount: 0,
        pendingInvitations: 0,
        ledgerVersion: 0,
        ledgerHashHex: '0',
      );
}

class CapsuleRuntimeBootstrap {
  final String pubKeyHex;
  final Uint8List seed;
  final bool isGenesis;
  final bool isNeste;
  final String? ledgerJson;

  CapsuleRuntimeBootstrap({
    required this.pubKeyHex,
    required this.seed,
    required this.isGenesis,
    required this.isNeste,
    required this.ledgerJson,
  });
}

class CapsuleTraceReport {
  final String? activePubKeyHex;
  final String? runtimePubKeyHex;
  final bool runtimeSeedExists;
  final bool indexHasEntry;
  final bool secureSeedExists;
  final bool fallbackSeedExists;
  final String capsuleDirPath;
  final bool capsuleDirExists;
  final bool ledgerFileExists;
  final bool stateFileExists;
  final bool backupFileExists;
  final String legacyDocsPath;
  final bool legacyLedgerExists;
  final bool legacyStateExists;
  final bool legacyBackupExists;

  CapsuleTraceReport({
    required this.activePubKeyHex,
    required this.runtimePubKeyHex,
    required this.runtimeSeedExists,
    required this.indexHasEntry,
    required this.secureSeedExists,
    required this.fallbackSeedExists,
    required this.capsuleDirPath,
    required this.capsuleDirExists,
    required this.ledgerFileExists,
    required this.stateFileExists,
    required this.backupFileExists,
    required this.legacyDocsPath,
    required this.legacyLedgerExists,
    required this.legacyStateExists,
    required this.legacyBackupExists,
  });

  String toMultilineString() {
    return [
      'activePubKeyHex: ${activePubKeyHex ?? "none"}',
      'runtimePubKeyHex: ${runtimePubKeyHex ?? "none"}',
      'runtimeSeedExists: $runtimeSeedExists',
      'indexHasEntry: $indexHasEntry',
      'secureSeedExists: $secureSeedExists',
      'fallbackSeedExists: $fallbackSeedExists',
      'capsuleDirPath: $capsuleDirPath',
      'capsuleDirExists: $capsuleDirExists',
      'ledgerFileExists: $ledgerFileExists',
      'stateFileExists: $stateFileExists',
      'backupFileExists: $backupFileExists',
      'legacyDocsPath: $legacyDocsPath',
      'legacyLedgerExists: $legacyLedgerExists',
      'legacyStateExists: $legacyStateExists',
      'legacyBackupExists: $legacyBackupExists',
    ].join('\n');
  }
}

class CapsuleBootstrapReport {
  final String? activePubKeyHex;
  final String? runtimePubKeyHex;
  final String bootstrapSource;
  final bool seedAvailable;
  final bool seedMatchesActiveCapsule;
  final bool stateFileExists;
  final bool ledgerFileExists;
  final bool backupFileExists;
  final bool workerBootstrapAvailable;
  final bool ledgerImportable;
  final String? issue;

  CapsuleBootstrapReport({
    required this.activePubKeyHex,
    required this.runtimePubKeyHex,
    required this.bootstrapSource,
    required this.seedAvailable,
    required this.seedMatchesActiveCapsule,
    required this.stateFileExists,
    required this.ledgerFileExists,
    required this.backupFileExists,
    required this.workerBootstrapAvailable,
    required this.ledgerImportable,
    required this.issue,
  });

  String toMultilineString() {
    return [
      'activePubKeyHex: ${activePubKeyHex ?? "none"}',
      'runtimePubKeyHex: ${runtimePubKeyHex ?? "none"}',
      'bootstrapSource: $bootstrapSource',
      'seedAvailable: $seedAvailable',
      'seedMatchesActiveCapsule: $seedMatchesActiveCapsule',
      'stateFileExists: $stateFileExists',
      'ledgerFileExists: $ledgerFileExists',
      'backupFileExists: $backupFileExists',
      'workerBootstrapAvailable: $workerBootstrapAvailable',
      'ledgerImportable: $ledgerImportable',
      'issue: ${issue ?? "none"}',
    ].join('\n');
  }
}
