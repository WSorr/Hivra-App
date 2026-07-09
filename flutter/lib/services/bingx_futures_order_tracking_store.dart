import 'dart:convert';
import 'dart:io';

import '../models/bingx_futures_order_tracking_models.dart';
import 'atomic_file_write_service.dart';
import 'capsule_file_store.dart';

class BingxFuturesOrderTrackingStore {
  static const String _stateFileName = 'bingx_futures_order_tracking.v1.json';

  final String? Function() _readActiveCapsuleRootHex;
  final CapsuleFileStore _fileStore;
  final AtomicFileWriteService _atomicWrites;

  const BingxFuturesOrderTrackingStore({
    required String? Function() readActiveCapsuleRootHex,
    CapsuleFileStore? fileStore,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  })  : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
        _fileStore = fileStore ?? const CapsuleFileStore(),
        _atomicWrites = atomicWrites;

  Future<void> save(BingxFuturesOrderTrackingState state) async {
    final file = await _stateFileForActiveCapsule(createDir: true);
    if (file == null) return;
    if (state.isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await _atomicWrites.writeString(file, jsonEncode(state.toJson()));
  }

  Future<BingxFuturesOrderTrackingState?> load() async {
    final file = await _stateFileForActiveCapsule(createDir: false);
    if (file == null || !await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return BingxFuturesOrderTrackingState.fromJsonMap(decoded);
      }
      if (decoded is Map) {
        return BingxFuturesOrderTrackingState.fromJsonMap(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> clear() async {
    final file = await _stateFileForActiveCapsule(createDir: false);
    if (file == null || !await file.exists()) return;
    await file.delete();
  }

  Future<File?> _stateFileForActiveCapsule({required bool createDir}) async {
    final capsuleHex = _normalizeCapsuleHex(_readActiveCapsuleRootHex());
    if (capsuleHex == null) return null;
    final capsuleDir = await _fileStore.capsuleDirForHex(
      capsuleHex,
      create: createDir,
    );
    return File('${capsuleDir.path}/$_stateFileName');
  }

  String? _normalizeCapsuleHex(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.length != 64) return null;
    const hex = '0123456789abcdef';
    for (var i = 0; i < normalized.length; i++) {
      if (!hex.contains(normalized[i])) return null;
    }
    return normalized;
  }
}
