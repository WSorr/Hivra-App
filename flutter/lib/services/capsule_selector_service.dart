import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../ffi/hivra_bindings.dart';
import 'capsule_persistence_service.dart';

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
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  CapsuleSelectorService({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  Future<List<CapsuleSelectorItem>> loadCapsules() async {
    final entries = await _persistence.listCapsules(hivra: _hivra);
    final seedByHex = <String, bool>{};
    final ownerByHex = <String, String?>{};

    for (final entry in entries) {
      seedByHex[entry.pubKeyHex] =
          await _persistence.hasStoredSeed(entry.pubKeyHex);
      ownerByHex[entry.pubKeyHex] =
          await _persistence.loadCapsuleLedgerOwnerHex(entry.pubKeyHex);
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
      var summary = await _persistence.loadCapsuleSummary(entry.pubKeyHex);
      if (summary.ledgerHashHex == '7fffffffffffffff') {
        final hasSeed = await _persistence.hasStoredSeed(entry.pubKeyHex);
        if (hasSeed) {
          final refreshed = await _persistence.refreshCapsuleSnapshot(
            _hivra,
            entry.pubKeyHex,
          );
          if (refreshed) {
            summary = await _persistence.loadCapsuleSummary(entry.pubKeyHex);
          }
        }
      }

      capsules.add(
        CapsuleSelectorItem(
          id: entry.pubKeyHex,
          publicKeyHex: entry.pubKeyHex,
          displayKeyText: await _persistence.resolveDisplayCapsuleKey(
              _hivra, entry.pubKeyHex),
          network: entry.isNeste ? 'NESTE' : 'HOOD',
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

  bool seedExists() => _hivra.seedExists();

  Future<void> activateCapsule(String pubKeyHex) {
    return _persistence.activateCapsule(_hivra, pubKeyHex);
  }

  Future<String?> importCapsuleFromBackupJson(String raw) {
    return _persistence.importCapsuleFromBackupJson(raw);
  }

  Future<bool> hasStoredSeed(String pubKeyHex) {
    return _persistence.hasStoredSeed(pubKeyHex);
  }

  Future<String?> exportCapsuleBackupToPath(
    String pubKeyHex,
    String targetPath,
  ) {
    return _persistence.exportCapsuleBackupToPath(pubKeyHex, targetPath);
  }

  Future<void> deleteCapsule(String pubKeyHex) {
    return _persistence.deleteCapsule(
      pubKeyHex,
      deleteLocalData: true,
      hivra: _hivra,
    );
  }

  bool validateMnemonic(String phrase) => _hivra.validateMnemonic(phrase);

  Uint8List mnemonicToSeed(String phrase) => _hivra.mnemonicToSeed(phrase);

  Future<bool> seedMatchesCapsule(Uint8List seed, String pubKeyHex) {
    return _persistence.seedMatchesCapsule(
      _hivra,
      seed,
      pubKeyHex,
    );
  }

  Future<void> saveSeedForCapsule(String pubKeyHex, Uint8List seed) {
    return _persistence.saveSeedForCapsule(pubKeyHex, seed);
  }
}
