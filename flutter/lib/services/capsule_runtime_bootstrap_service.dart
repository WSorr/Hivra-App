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

    String? ledgerJson = await _fileStore.readLedger(dir);
    if (ledgerJson == null) {
      final backupJson = await _fileStore.readBackup(dir);
      if (backupJson != null) {
        final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
        if (extracted != null && extracted.trim().isNotEmpty) {
          ledgerJson = extracted;
        }
      }
    }

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

    final ledgerJson = await _fileStore.readLedger(dir);
    if (ledgerJson != null) {
      hivra.importLedger(ledgerJson);
    } else {
      final backupJson = await _fileStore.readBackup(dir);
      if (backupJson != null) {
        final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
        if (extracted != null && extracted.trim().isNotEmpty) {
          hivra.importLedger(extracted);
        }
      }
    }

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
}
