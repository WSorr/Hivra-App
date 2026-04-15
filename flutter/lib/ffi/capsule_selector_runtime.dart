import 'dart:typed_data';

import '../services/capsule_persistence_models.dart';
import '../services/capsule_persistence_service.dart';
import 'hivra_bindings.dart';

abstract class CapsuleSelectorRuntime {
  Future<List<CapsuleIndexEntry>> listCapsules();

  Future<bool> hasStoredSeed(String pubKeyHex);

  Future<String?> loadCapsuleLedgerOwnerHex(String pubKeyHex);

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(String pubKeyHex);

  Future<CapsuleLedgerSummary> loadCapsuleSummary(String pubKeyHex);

  Future<bool> refreshCapsuleSnapshot(String pubKeyHex);

  Future<String> resolveDisplayCapsuleKey(String pubKeyHex);

  bool seedExists();

  Future<void> activateCapsule(String pubKeyHex);

  Future<String?> importCapsuleFromBackupJson(String raw);

  Future<String?> exportCapsuleBackupToPath(
      String pubKeyHex, String targetPath);

  Future<void> deleteCapsule(String pubKeyHex);

  bool validateMnemonic(String phrase);

  Uint8List mnemonicToSeed(String phrase);

  Future<bool> seedMatchesCapsule(Uint8List seed, String pubKeyHex);

  Future<void> saveSeedForCapsule(String pubKeyHex, Uint8List seed);
}

class HivraCapsuleSelectorRuntime implements CapsuleSelectorRuntime {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  HivraCapsuleSelectorRuntime({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  @override
  Future<List<CapsuleIndexEntry>> listCapsules() {
    return _persistence.listCapsules(hivra: _hivra);
  }

  @override
  Future<bool> hasStoredSeed(String pubKeyHex) {
    return _persistence.hasStoredSeed(pubKeyHex);
  }

  @override
  Future<String?> loadCapsuleLedgerOwnerHex(String pubKeyHex) {
    return _persistence.loadCapsuleLedgerOwnerHex(pubKeyHex);
  }

  @override
  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(String pubKeyHex) {
    return _persistence.loadRuntimeBootstrap(pubKeyHex, hivra: _hivra);
  }

  @override
  Future<CapsuleLedgerSummary> loadCapsuleSummary(String pubKeyHex) {
    return _persistence.loadCapsuleSummary(pubKeyHex, hivra: _hivra);
  }

  @override
  Future<bool> refreshCapsuleSnapshot(String pubKeyHex) {
    return _persistence.refreshCapsuleSnapshot(_hivra, pubKeyHex);
  }

  @override
  Future<String> resolveDisplayCapsuleKey(String pubKeyHex) {
    return _persistence.resolveDisplayCapsuleKey(_hivra, pubKeyHex);
  }

  @override
  bool seedExists() => _hivra.seedExists();

  @override
  Future<void> activateCapsule(String pubKeyHex) {
    return _persistence.activateCapsule(_hivra, pubKeyHex);
  }

  @override
  Future<String?> importCapsuleFromBackupJson(String raw) {
    return _persistence.importCapsuleFromBackupJson(raw);
  }

  @override
  Future<String?> exportCapsuleBackupToPath(
      String pubKeyHex, String targetPath) {
    return _persistence.exportCapsuleBackupToPath(pubKeyHex, targetPath);
  }

  @override
  Future<void> deleteCapsule(String pubKeyHex) {
    return _persistence.deleteCapsule(
      pubKeyHex,
      deleteLocalData: true,
      hivra: _hivra,
    );
  }

  @override
  bool validateMnemonic(String phrase) => _hivra.validateMnemonic(phrase);

  @override
  Uint8List mnemonicToSeed(String phrase) => _hivra.mnemonicToSeed(phrase);

  @override
  Future<bool> seedMatchesCapsule(Uint8List seed, String pubKeyHex) {
    return _persistence.seedMatchesCapsule(_hivra, seed, pubKeyHex);
  }

  @override
  Future<void> saveSeedForCapsule(String pubKeyHex, Uint8List seed) {
    return _persistence.saveSeedForCapsule(pubKeyHex, seed);
  }
}
