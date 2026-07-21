import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'atomic_file_write_service.dart';
import 'user_visible_data_directory_service.dart';

class CapsuleFileStore {
  static const String stateFileName = 'capsule_state.json';
  static const String ledgerFileName = 'ledger.json';
  static const String backupFileName = 'capsule-backup.v1.json';
  static const String deliveryOutboxFileName = 'delivery_outbox.json';
  static const String chatDeferredInboxFileName = 'chat_deferred_inbox.v1.json';
  static const String pairConsensusAttestationsFileName =
      'pair_consensus_attestations.json';
  static const String capsulesDirName = 'capsules';

  final UserVisibleDataDirectoryService _dirs;
  final AtomicFileWriteService _atomicWrites;

  const CapsuleFileStore({
    UserVisibleDataDirectoryService? dirs,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _dirs = dirs ?? const UserVisibleDataDirectoryService(),
       _atomicWrites = atomicWrites;

  Future<Directory> docsDirectory() async {
    return _dirs.rootDirectory(create: true);
  }

  Future<Directory> capsulesRoot({bool create = false}) async {
    final docs = await docsDirectory();
    final root = Directory('${docs.path}/$capsulesDirName');
    if (create && !await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> capsuleDirForHex(
    String pubKeyHex, {
    bool create = false,
  }) async {
    final root = await capsulesRoot(create: create);
    final dir = Directory('${root.path}/$pubKeyHex');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> currentCapsuleDir(
    Uint8List? Function()? runtimeOwnerPublicKey, {
    required String Function(Uint8List bytes) bytesToHex,
    bool create = false,
  }) async {
    final docs = await docsDirectory();
    final root = await capsulesRoot(create: create);

    String? capsuleId;
    if (runtimeOwnerPublicKey != null) {
      final pubKey = runtimeOwnerPublicKey();
      if (pubKey != null && pubKey.length == 32) {
        capsuleId = bytesToHex(pubKey);
      }
    }

    if (capsuleId == null || capsuleId.isEmpty) {
      return docs;
    }

    final dir = Directory('${root.path}/$capsuleId');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File stateFile(Directory dir) => File('${dir.path}/$stateFileName');

  File ledgerFile(Directory dir) => File('${dir.path}/$ledgerFileName');

  File backupFile(Directory dir) => File('${dir.path}/$backupFileName');

  File deliveryOutboxFile(Directory dir) =>
      File('${dir.path}/$deliveryOutboxFileName');

  File chatDeferredInboxFile(Directory dir) =>
      File('${dir.path}/$chatDeferredInboxFileName');

  File pairConsensusAttestationsFile(Directory dir) =>
      File('${dir.path}/$pairConsensusAttestationsFileName');

  Future<Map<String, dynamic>?> readState(Directory dir) async {
    final file = stateFile(dir);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return _parseJsonMap(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeState(Directory dir, Map<String, dynamic> state) async {
    await _atomicWrites.writeString(stateFile(dir), jsonEncode(state));
  }

  Future<bool> writeCoreProjection(
    Directory dir,
    String? projectionJson,
  ) async {
    if (projectionJson == null || projectionJson.trim().isEmpty) return false;
    try {
      final projection = _parseJsonMap(projectionJson);
      if (projection == null ||
          projection['version'] is! num ||
          projection['ledger_hash'] == null ||
          projection['slots'] is! List) {
        return false;
      }
      final state = await readState(dir) ?? <String, dynamic>{};
      state['coreProjection'] = projection;
      await writeState(dir, state);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> readLedger(Directory dir) async {
    final file = ledgerFile(dir);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return raw.trim().isEmpty ? null : raw;
  }

  Future<void> writeLedger(Directory dir, String ledgerJson) async {
    await _atomicWrites.writeString(ledgerFile(dir), ledgerJson);
  }

  Future<String?> readBackup(Directory dir) async {
    final file = backupFile(dir);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return raw.trim().isEmpty ? null : raw;
  }

  Future<void> writeBackup(Directory dir, String backupJson) async {
    await _atomicWrites.writeString(backupFile(dir), backupJson);
  }

  Future<String?> readDeliveryOutbox(Directory dir) async {
    final file = deliveryOutboxFile(dir);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return raw.trim().isEmpty ? null : raw;
  }

  Future<void> writeDeliveryOutbox(Directory dir, String rawJson) async {
    await _atomicWrites.writeString(deliveryOutboxFile(dir), rawJson);
  }

  Future<String?> readChatDeferredInbox(Directory dir) async {
    final file = chatDeferredInboxFile(dir);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return raw.trim().isEmpty ? null : raw;
  }

  Future<void> writeChatDeferredInbox(Directory dir, String rawJson) async {
    await _atomicWrites.writeString(chatDeferredInboxFile(dir), rawJson);
  }

  Future<String?> readPairConsensusAttestations(Directory dir) async {
    final file = pairConsensusAttestationsFile(dir);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return raw.trim().isEmpty ? null : raw;
  }

  Future<void> writePairConsensusAttestations(
    Directory dir,
    String rawJson,
  ) async {
    await _atomicWrites.writeString(
      pairConsensusAttestationsFile(dir),
      rawJson,
    );
  }

  Future<void> clearPersisted(
    Directory dir, {
    bool includeBackup = false,
  }) async {
    final state = stateFile(dir);
    final ledger = ledgerFile(dir);
    final backup = backupFile(dir);
    if (await state.exists()) await state.delete();
    if (await ledger.exists()) await ledger.delete();
    if (includeBackup && await backup.exists()) await backup.delete();
  }

  Future<String> backupPath(Directory dir) async {
    return backupFile(dir).path;
  }

  Future<String> ledgerPath(Directory dir) async {
    return ledgerFile(dir).path;
  }

  Future<void> deleteCapsuleDir(String pubKeyHex) async {
    final dir = await capsuleDirForHex(pubKeyHex);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  File legacyStateFile(Directory docs) => File('${docs.path}/$stateFileName');

  File legacyLedgerFile(Directory docs) => File('${docs.path}/$ledgerFileName');

  File legacyBackupFile(Directory docs) => File('${docs.path}/$backupFileName');

  Map<String, dynamic>? _parseJsonMap(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }
}
