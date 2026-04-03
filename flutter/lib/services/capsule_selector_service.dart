import 'package:flutter/foundation.dart';

import '../ffi/capsule_selector_runtime.dart';

class CapsuleSelectorItem {
  final String id;
  final String publicKeyHex;
  final String displayKeyText;
  final String network;
  final int starterCount;
  final int relationshipCount;
  final int pendingInvitations;
  final int ledgerVersion;
  final String ledgerHashHex;
  final DateTime lastActive;
  final DateTime createdAt;

  CapsuleSelectorItem({
    required this.id,
    required this.publicKeyHex,
    required this.displayKeyText,
    required this.network,
    required this.starterCount,
    required this.relationshipCount,
    required this.pendingInvitations,
    required this.ledgerVersion,
    required this.ledgerHashHex,
    required this.lastActive,
    required this.createdAt,
  });
}

class CapsuleSelectorService {
  final CapsuleSelectorRuntime _runtime;

  CapsuleSelectorService([CapsuleSelectorRuntime? runtime])
      : _runtime = runtime ?? HivraCapsuleSelectorRuntime();

  Future<List<CapsuleSelectorItem>> loadCapsules() async {
    final entries = await _runtime.listCapsules();
    final seedByHex = <String, bool>{};
    final ownerByHex = <String, String?>{};
    final bootstrapNesteByHex = <String, bool?>{};

    for (final entry in entries) {
      seedByHex[entry.pubKeyHex] =
          await _runtime.hasStoredSeed(entry.pubKeyHex);
      ownerByHex[entry.pubKeyHex] =
          await _runtime.loadCapsuleLedgerOwnerHex(entry.pubKeyHex);
      bootstrapNesteByHex[entry.pubKeyHex] = null;
      if (seedByHex[entry.pubKeyHex] == true) {
        final bootstrap = await _runtime.loadRuntimeBootstrap(entry.pubKeyHex);
        bootstrapNesteByHex[entry.pubKeyHex] = bootstrap?.isNeste;
      }
    }

    final filteredEntries = entries.where((entry) {
      final pubKeyHex = entry.pubKeyHex;
      if (seedByHex[pubKeyHex] == true) return true;

      // Hide ghost aliases without seed when other seeded capsules clearly
      // point to them as ledger owner.
      final hasSeededOwnerRef = entries.any((other) {
        if (other.pubKeyHex == pubKeyHex) return false;
        return seedByHex[other.pubKeyHex] == true &&
            ownerByHex[other.pubKeyHex] == pubKeyHex;
      });
      return !hasSeededOwnerRef;
    }).toList();

    final capsules = <CapsuleSelectorItem>[];

    for (final entry in filteredEntries) {
      var summary = await _runtime.loadCapsuleSummary(entry.pubKeyHex);
      if (summary.ledgerHashHex == '7fffffffffffffff') {
        final hasSeed = await _runtime.hasStoredSeed(entry.pubKeyHex);
        if (hasSeed) {
          final refreshed =
              await _runtime.refreshCapsuleSnapshot(entry.pubKeyHex);
          if (refreshed) {
            summary = await _runtime.loadCapsuleSummary(entry.pubKeyHex);
          }
        }
      }

      capsules.add(
        CapsuleSelectorItem(
          id: entry.pubKeyHex,
          publicKeyHex: entry.pubKeyHex,
          displayKeyText:
              await _runtime.resolveDisplayCapsuleKey(entry.pubKeyHex),
          network: networkLabelForCapsule(
            indexIsNeste: entry.isNeste,
            bootstrapIsNeste: bootstrapNesteByHex[entry.pubKeyHex],
          ),
          starterCount: summary.starterCount,
          relationshipCount: summary.relationshipCount,
          pendingInvitations: summary.pendingInvitations,
          ledgerVersion: summary.ledgerVersion,
          ledgerHashHex: summary.ledgerHashHex,
          lastActive: entry.lastActive,
          createdAt: entry.createdAt,
        ),
      );
    }

    return collapseDisplayDuplicates(
      capsules,
      hasSeedByPubKey: seedByHex,
      identityModeByPubKey: {
        for (final entry in filteredEntries)
          entry.pubKeyHex: entry.identityMode,
      },
    );
  }

  @visibleForTesting
  static List<CapsuleSelectorItem> collapseDisplayDuplicates(
    List<CapsuleSelectorItem> items, {
    required Map<String, bool> hasSeedByPubKey,
    required Map<String, String> identityModeByPubKey,
  }) {
    final byDisplay = <String, CapsuleSelectorItem>{};

    for (final item in items) {
      final key = '${item.network}|${item.displayKeyText}';
      final current = byDisplay[key];
      if (current == null ||
          _preferForDisplay(
            candidate: item,
            current: current,
            hasSeedByPubKey: hasSeedByPubKey,
            identityModeByPubKey: identityModeByPubKey,
          )) {
        byDisplay[key] = item;
      }
    }

    final collapsed = byDisplay.values.toList()
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return collapsed;
  }

  static bool _preferForDisplay({
    required CapsuleSelectorItem candidate,
    required CapsuleSelectorItem current,
    required Map<String, bool> hasSeedByPubKey,
    required Map<String, String> identityModeByPubKey,
  }) {
    final candidateSeed = hasSeedByPubKey[candidate.publicKeyHex] == true;
    final currentSeed = hasSeedByPubKey[current.publicKeyHex] == true;
    if (candidateSeed != currentSeed) return candidateSeed;

    final candidateMode = identityModeByPubKey[candidate.publicKeyHex] ?? '';
    final currentMode = identityModeByPubKey[current.publicKeyHex] ?? '';
    final candidateModeScore = _identityModeScore(candidateMode);
    final currentModeScore = _identityModeScore(currentMode);
    if (candidateModeScore != currentModeScore) {
      return candidateModeScore > currentModeScore;
    }

    if (candidate.ledgerVersion != current.ledgerVersion) {
      return candidate.ledgerVersion > current.ledgerVersion;
    }

    if (candidate.lastActive != current.lastActive) {
      return candidate.lastActive.isAfter(current.lastActive);
    }

    return candidate.publicKeyHex.compareTo(current.publicKeyHex) < 0;
  }

  static int _identityModeScore(String mode) {
    switch (mode) {
      case 'root_owner':
        return 2;
      case 'legacy_nostr_owner':
        return 1;
      default:
        return 0;
    }
  }

  @visibleForTesting
  static String networkLabelForCapsule({
    required bool indexIsNeste,
    required bool? bootstrapIsNeste,
  }) {
    final isNeste = bootstrapIsNeste ?? indexIsNeste;
    return isNeste ? 'NESTE' : 'HOOD';
  }

  bool seedExists() => _runtime.seedExists();

  Future<void> activateCapsule(String pubKeyHex) {
    return _runtime.activateCapsule(pubKeyHex);
  }

  Future<String?> importCapsuleFromBackupJson(String raw) {
    return _runtime.importCapsuleFromBackupJson(raw);
  }

  Future<bool> hasStoredSeed(String pubKeyHex) {
    return _runtime.hasStoredSeed(pubKeyHex);
  }

  Future<String?> exportCapsuleBackupToPath(
    String pubKeyHex,
    String targetPath,
  ) {
    return _runtime.exportCapsuleBackupToPath(pubKeyHex, targetPath);
  }

  Future<void> deleteCapsule(String pubKeyHex) {
    return _runtime.deleteCapsule(pubKeyHex);
  }

  bool validateMnemonic(String phrase) => _runtime.validateMnemonic(phrase);

  Uint8List mnemonicToSeed(String phrase) => _runtime.mnemonicToSeed(phrase);

  Future<bool> seedMatchesCapsule(Uint8List seed, String pubKeyHex) {
    return _runtime.seedMatchesCapsule(seed, pubKeyHex);
  }

  Future<void> saveSeedForCapsule(String pubKeyHex, Uint8List seed) {
    return _runtime.saveSeedForCapsule(pubKeyHex, seed);
  }
}
