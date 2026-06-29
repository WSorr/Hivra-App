import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ffi/capsule_selector_runtime.dart';
import 'capsule_persistence_models.dart';
import 'ui_event_log_service.dart';

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
  final UiEventLogService _uiLog;

  CapsuleSelectorService([
    CapsuleSelectorRuntime? runtime,
    UiEventLogService uiLog = const UiEventLogService(),
  ])  : _runtime = runtime ?? HivraCapsuleSelectorRuntime(),
        _uiLog = uiLog;

  Future<List<CapsuleSelectorItem>> loadCapsules() async {
    await _uiLog.log('capsule.selector.service', 'list.start');
    final entries = await _runtime.listCapsules();
    await _uiLog.log(
      'capsule.selector.service',
      'list.done count=${entries.length}',
    );
    final filteredEntries = entries;

    final capsules = <CapsuleSelectorItem>[];

    for (final entry in filteredEntries) {
      final shortHex = _shortHex(entry.pubKeyHex);
      await _uiLog.log('capsule.selector.service', 'summary.start $shortHex');
      var summary = await _withSelectorTimeout(
        'summary',
        shortHex,
        () => _runtime.loadCapsuleSummary(entry.pubKeyHex),
        fallback: CapsuleLedgerSummary.empty(),
      );
      await _uiLog.log(
        'capsule.selector.service',
        'summary.done $shortHex ledgerVersion=${summary.ledgerVersion}',
      );
      if (summary.ledgerHashHex == '7fffffffffffffff') {
        await _uiLog.log(
          'capsule.selector.service',
          'summary.placeholder $shortHex',
        );
      }

      capsules.add(
        CapsuleSelectorItem(
          id: entry.pubKeyHex,
          publicKeyHex: entry.pubKeyHex,
          displayKeyText: entry.pubKeyHex,
          network: networkLabelForCapsule(
            indexIsNeste: entry.isNeste,
            bootstrapIsNeste: null,
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

    final collapsed = collapseDisplayDuplicates(
      capsules,
      hasSeedByPubKey: {
        for (final entry in filteredEntries) entry.pubKeyHex: true,
      },
      identityModeByPubKey: {
        for (final entry in filteredEntries)
          entry.pubKeyHex: entry.identityMode,
      },
    );
    await _uiLog.log(
      'capsule.selector.service',
      'collapse.done count=${collapsed.length}',
    );
    return collapsed;
  }

  String _shortHex(String? value) {
    final hex = value?.trim() ?? '';
    if (hex.length <= 12) return hex.isEmpty ? '-' : hex;
    return '${hex.substring(0, 8)}..${hex.substring(hex.length - 4)}';
  }

  Future<T> _withSelectorTimeout<T>(
    String phase,
    String shortHex,
    Future<T> Function() operation, {
    required T fallback,
  }) async {
    try {
      return await operation().timeout(const Duration(seconds: 2));
    } on TimeoutException {
      await _uiLog.log(
        'capsule.selector.service',
        '$phase.timeout $shortHex seconds=2',
      );
      return fallback;
    } catch (error) {
      await _uiLog.log(
        'capsule.selector.service',
        '$phase.error $shortHex $error',
      );
      return fallback;
    }
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
