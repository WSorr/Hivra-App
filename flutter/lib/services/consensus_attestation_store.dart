import 'dart:convert';

import '../models/consensus_models.dart';
import 'capsule_file_store.dart';

class ConsensusAttestationStore {
  final CapsuleFileStore _fileStore;

  const ConsensusAttestationStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
  }) : _fileStore = fileStore;

  Future<List<ConsensusAttestationEvidence>> load(String capsuleRootHex) async {
    final normalized = _normalizeHex64(capsuleRootHex);
    if (normalized == null) return const <ConsensusAttestationEvidence>[];
    final dir = await _fileStore.capsuleDirForHex(normalized, create: true);
    final raw = await _fileStore.readPairConsensusAttestations(dir);
    if (raw == null) return const <ConsensusAttestationEvidence>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <ConsensusAttestationEvidence>[];
      final items = decoded['attestations'];
      if (items is! List) return const <ConsensusAttestationEvidence>[];
      final out = <ConsensusAttestationEvidence>[];
      for (final item in items) {
        final evidence = ConsensusAttestationEvidence.fromJson(item);
        if (evidence != null) out.add(evidence);
      }
      out.sort((a, b) => a.recordKey.compareTo(b.recordKey));
      return List<ConsensusAttestationEvidence>.unmodifiable(out);
    } catch (_) {
      return const <ConsensusAttestationEvidence>[];
    }
  }

  Future<void> merge(
    String capsuleRootHex,
    Iterable<ConsensusAttestationEvidence> evidence,
  ) async {
    final normalized = _normalizeHex64(capsuleRootHex);
    if (normalized == null) return;
    final dir = await _fileStore.capsuleDirForHex(normalized, create: true);
    final current = await load(normalized);
    final byKey = <String, ConsensusAttestationEvidence>{
      for (final item in current) item.recordKey: item,
    };
    for (final item in evidence) {
      byKey[item.recordKey] = item;
    }
    final items = byKey.values.toList()
      ..sort((a, b) => a.recordKey.compareTo(b.recordKey));
    final rawJson = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'attestations': items.map((item) => item.toJson()).toList(),
    });
    await _fileStore.writePairConsensusAttestations(dir, rawJson);
  }

  List<ConsensusAttestationEvidence> matching({
    required Iterable<ConsensusAttestationEvidence> evidence,
    required List<String> pairRootsSorted,
    required String snapshotHashHex,
  }) {
    final roots = pairRootsSorted
        .map((item) => item.trim().toLowerCase())
        .toList(growable: false);
    final snapshot = snapshotHashHex.trim().toLowerCase();
    if (roots.length != 2 || _normalizeHex64(snapshot) == null) {
      return const <ConsensusAttestationEvidence>[];
    }
    return evidence
        .where(
          (item) =>
              item.snapshotHashHex == snapshot &&
              item.pairRootsSorted.length == 2 &&
              item.pairRootsSorted[0] == roots[0] &&
              item.pairRootsSorted[1] == roots[1],
        )
        .toList(growable: false);
  }

  String? _normalizeHex64(String value) {
    final normalized = value.trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
  }
}
