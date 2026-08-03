import 'dart:async';
import 'dart:convert';

import '../models/consensus_models.dart';
import 'capsule_file_store.dart';

const int consensusAttestationStoreSchemaVersion = 2;
const int consensusAttestationResponseCheckpointLimit = 4096;
const Duration consensusAttestationResponseRetryDelay = Duration(minutes: 15);

enum ConsensusAttestationResponseReservationStatus {
  reserved,
  delivered,
  coolingDown,
  unavailable,
}

class ConsensusAttestationResponseReservation {
  final ConsensusAttestationResponseReservationStatus status;
  final DateTime? retryAfterUtc;

  const ConsensusAttestationResponseReservation({
    required this.status,
    this.retryAfterUtc,
  });

  bool get canSend =>
      status == ConsensusAttestationResponseReservationStatus.reserved;
}

class ConsensusAttestationStore {
  static Future<void> _mutationQueue = Future<void>.value();

  final CapsuleFileStore _fileStore;

  const ConsensusAttestationStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
  }) : _fileStore = fileStore;

  Future<List<ConsensusAttestationEvidence>> load(String capsuleRootHex) async {
    final normalized = _normalizeHex64(capsuleRootHex);
    if (normalized == null) return const <ConsensusAttestationEvidence>[];
    final snapshot = await _loadSnapshot(normalized);
    if (snapshot == null) return const <ConsensusAttestationEvidence>[];
    return List<ConsensusAttestationEvidence>.unmodifiable(
      snapshot.attestations,
    );
  }

  Future<List<ConsensusAttestationEvidence>> merge(
    String capsuleRootHex,
    Iterable<ConsensusAttestationEvidence> evidence,
  ) {
    final normalized = _normalizeHex64(capsuleRootHex);
    if (normalized == null) {
      return Future<List<ConsensusAttestationEvidence>>.value(
        const <ConsensusAttestationEvidence>[],
      );
    }
    return _serializeMutation(() async {
      final snapshot = await _loadSnapshot(normalized);
      if (snapshot == null) {
        throw StateError('Pair consensus attestation store is corrupt');
      }
      final byKey = <String, ConsensusAttestationEvidence>{
        for (final item in snapshot.attestations) item.recordKey: item,
      };
      final added = <ConsensusAttestationEvidence>[];
      for (final item in evidence) {
        if (byKey.containsKey(item.recordKey)) continue;
        byKey[item.recordKey] = item;
        added.add(item);
      }
      if (added.isEmpty && snapshot.schemaVersion == 2) {
        return const <ConsensusAttestationEvidence>[];
      }
      final next = _ConsensusAttestationStoreSnapshot(
        schemaVersion: consensusAttestationStoreSchemaVersion,
        attestations:
            byKey.values.toList()
              ..sort((a, b) => a.recordKey.compareTo(b.recordKey)),
        responseCheckpoints: snapshot.responseCheckpoints,
      );
      await _writeSnapshot(normalized, next);
      return List<ConsensusAttestationEvidence>.unmodifiable(added);
    });
  }

  Future<ConsensusAttestationResponseReservation> reserveResponse({
    required String capsuleRootHex,
    required String peerEvidenceRecordKey,
    required String localEvidenceRecordKey,
    required DateTime nowUtc,
  }) {
    final normalized = _normalizeHex64(capsuleRootHex);
    final now = nowUtc.toUtc();
    if (normalized == null ||
        !_validRecordKey(peerEvidenceRecordKey) ||
        !_validRecordKey(localEvidenceRecordKey)) {
      return Future<ConsensusAttestationResponseReservation>.value(
        const ConsensusAttestationResponseReservation(
          status: ConsensusAttestationResponseReservationStatus.unavailable,
        ),
      );
    }
    return _serializeMutation(() async {
      final snapshot = await _loadSnapshot(normalized);
      if (snapshot == null) {
        return const ConsensusAttestationResponseReservation(
          status: ConsensusAttestationResponseReservationStatus.unavailable,
        );
      }
      if (!_containsValidResponseEvidence(
        snapshot: snapshot,
        capsuleRootHex: normalized,
        peerEvidenceRecordKey: peerEvidenceRecordKey,
        localEvidenceRecordKey: localEvidenceRecordKey,
      )) {
        return const ConsensusAttestationResponseReservation(
          status: ConsensusAttestationResponseReservationStatus.unavailable,
        );
      }
      final existing = snapshot.responseCheckpoints.where(
        (item) =>
            item.peerEvidenceRecordKey == peerEvidenceRecordKey &&
            item.localEvidenceRecordKey == localEvidenceRecordKey,
      );
      if (existing.isNotEmpty) {
        final checkpoint = existing.single;
        if (checkpoint.delivered) {
          return const ConsensusAttestationResponseReservation(
            status: ConsensusAttestationResponseReservationStatus.delivered,
          );
        }
        if (now.isBefore(checkpoint.retryAfterUtc)) {
          return ConsensusAttestationResponseReservation(
            status: ConsensusAttestationResponseReservationStatus.coolingDown,
            retryAfterUtc: checkpoint.retryAfterUtc,
          );
        }
      } else if (snapshot.responseCheckpoints.length >=
          consensusAttestationResponseCheckpointLimit) {
        return const ConsensusAttestationResponseReservation(
          status: ConsensusAttestationResponseReservationStatus.unavailable,
        );
      }

      final retryAfterUtc = now.add(consensusAttestationResponseRetryDelay);
      final nextCheckpoint = _ConsensusAttestationResponseCheckpoint(
        peerEvidenceRecordKey: peerEvidenceRecordKey,
        localEvidenceRecordKey: localEvidenceRecordKey,
        delivered: false,
        retryAfterUtc: retryAfterUtc,
        updatedAtUtc: now,
      );
      final checkpoints =
          snapshot.responseCheckpoints
              .where(
                (item) =>
                    item.peerEvidenceRecordKey != peerEvidenceRecordKey ||
                    item.localEvidenceRecordKey != localEvidenceRecordKey,
              )
              .toList()
            ..add(nextCheckpoint)
            ..sort(_compareCheckpoints);
      await _writeSnapshot(
        normalized,
        _ConsensusAttestationStoreSnapshot(
          schemaVersion: consensusAttestationStoreSchemaVersion,
          attestations: snapshot.attestations,
          responseCheckpoints: checkpoints,
        ),
      );
      return ConsensusAttestationResponseReservation(
        status: ConsensusAttestationResponseReservationStatus.reserved,
        retryAfterUtc: retryAfterUtc,
      );
    });
  }

  Future<bool> markResponseDelivered({
    required String capsuleRootHex,
    required String peerEvidenceRecordKey,
    required String localEvidenceRecordKey,
    required DateTime nowUtc,
  }) {
    final normalized = _normalizeHex64(capsuleRootHex);
    final now = nowUtc.toUtc();
    if (normalized == null ||
        !_validRecordKey(peerEvidenceRecordKey) ||
        !_validRecordKey(localEvidenceRecordKey)) {
      return Future<bool>.value(false);
    }
    return _serializeMutation(() async {
      final snapshot = await _loadSnapshot(normalized);
      if (snapshot == null) return false;
      final index = snapshot.responseCheckpoints.indexWhere(
        (item) =>
            item.peerEvidenceRecordKey == peerEvidenceRecordKey &&
            item.localEvidenceRecordKey == localEvidenceRecordKey,
      );
      if (index < 0) return false;
      final current = snapshot.responseCheckpoints[index];
      if (current.delivered) return true;
      final checkpoints = List<_ConsensusAttestationResponseCheckpoint>.from(
        snapshot.responseCheckpoints,
      );
      checkpoints[index] = _ConsensusAttestationResponseCheckpoint(
        peerEvidenceRecordKey: peerEvidenceRecordKey,
        localEvidenceRecordKey: localEvidenceRecordKey,
        delivered: true,
        retryAfterUtc: current.retryAfterUtc,
        updatedAtUtc: now,
      );
      checkpoints.sort(_compareCheckpoints);
      await _writeSnapshot(
        normalized,
        _ConsensusAttestationStoreSnapshot(
          schemaVersion: consensusAttestationStoreSchemaVersion,
          attestations: snapshot.attestations,
          responseCheckpoints: checkpoints,
        ),
      );
      return true;
    });
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

  Future<_ConsensusAttestationStoreSnapshot?> _loadSnapshot(
    String capsuleRootHex,
  ) async {
    final dir = await _fileStore.capsuleDirForHex(capsuleRootHex, create: true);
    final raw = await _fileStore.readPairConsensusAttestations(dir);
    if (raw == null) {
      return const _ConsensusAttestationStoreSnapshot(
        schemaVersion: consensusAttestationStoreSchemaVersion,
        attestations: <ConsensusAttestationEvidence>[],
        responseCheckpoints: <_ConsensusAttestationResponseCheckpoint>[],
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final schemaVersion = (map['schema_version'] as num?)?.toInt();
      if (schemaVersion != 1 &&
          schemaVersion != consensusAttestationStoreSchemaVersion) {
        return null;
      }
      final rawAttestations = map['attestations'];
      if (rawAttestations is! List) return null;
      final attestations = <ConsensusAttestationEvidence>[];
      final evidenceKeys = <String>{};
      for (final item in rawAttestations) {
        final evidence = ConsensusAttestationEvidence.fromJson(item);
        if (evidence == null || !evidenceKeys.add(evidence.recordKey)) {
          return null;
        }
        attestations.add(evidence);
      }
      attestations.sort((a, b) => a.recordKey.compareTo(b.recordKey));
      final checkpoints = <_ConsensusAttestationResponseCheckpoint>[];
      if (schemaVersion == consensusAttestationStoreSchemaVersion) {
        final rawCheckpoints = map['response_checkpoints'];
        if (rawCheckpoints is! List ||
            rawCheckpoints.length >
                consensusAttestationResponseCheckpointLimit) {
          return null;
        }
        final checkpointKeys = <String>{};
        for (final item in rawCheckpoints) {
          final checkpoint = _ConsensusAttestationResponseCheckpoint.fromJson(
            item,
          );
          if (checkpoint == null || !checkpointKeys.add(checkpoint.identity)) {
            return null;
          }
          checkpoints.add(checkpoint);
        }
        checkpoints.sort(_compareCheckpoints);
      }
      return _ConsensusAttestationStoreSnapshot(
        schemaVersion: schemaVersion!,
        attestations: attestations,
        responseCheckpoints: checkpoints,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSnapshot(
    String capsuleRootHex,
    _ConsensusAttestationStoreSnapshot snapshot,
  ) async {
    final dir = await _fileStore.capsuleDirForHex(capsuleRootHex, create: true);
    await _fileStore.writePairConsensusAttestations(
      dir,
      jsonEncode(<String, dynamic>{
        'schema_version': consensusAttestationStoreSchemaVersion,
        'attestations': snapshot.attestations
            .map((item) => item.toJson())
            .toList(growable: false),
        'response_checkpoints': snapshot.responseCheckpoints
            .map((item) => item.toJson())
            .toList(growable: false),
      }),
    );
  }

  Future<T> _serializeMutation<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _mutationQueue = _mutationQueue.catchError((_) {}).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  String? _normalizeHex64(String value) {
    final normalized = value.trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
  }

  bool _containsValidResponseEvidence({
    required _ConsensusAttestationStoreSnapshot snapshot,
    required String capsuleRootHex,
    required String peerEvidenceRecordKey,
    required String localEvidenceRecordKey,
  }) {
    final peerMatches = snapshot.attestations
        .where((item) => item.recordKey == peerEvidenceRecordKey)
        .toList(growable: false);
    final localMatches = snapshot.attestations
        .where((item) => item.recordKey == localEvidenceRecordKey)
        .toList(growable: false);
    if (peerMatches.length != 1 || localMatches.length != 1) return false;
    final peer = peerMatches.single;
    final local = localMatches.single;
    return peer.signerRootHex != capsuleRootHex &&
        local.signerRootHex == capsuleRootHex &&
        peer.snapshotHashHex == local.snapshotHashHex &&
        peer.commitmentHashHex == local.commitmentHashHex &&
        peer.pairRootsSorted.length == 2 &&
        local.pairRootsSorted.length == 2 &&
        peer.pairRootsSorted[0] == local.pairRootsSorted[0] &&
        peer.pairRootsSorted[1] == local.pairRootsSorted[1];
  }
}

class _ConsensusAttestationStoreSnapshot {
  final int schemaVersion;
  final List<ConsensusAttestationEvidence> attestations;
  final List<_ConsensusAttestationResponseCheckpoint> responseCheckpoints;

  const _ConsensusAttestationStoreSnapshot({
    required this.schemaVersion,
    required this.attestations,
    required this.responseCheckpoints,
  });
}

class _ConsensusAttestationResponseCheckpoint {
  final String peerEvidenceRecordKey;
  final String localEvidenceRecordKey;
  final bool delivered;
  final DateTime retryAfterUtc;
  final DateTime updatedAtUtc;

  const _ConsensusAttestationResponseCheckpoint({
    required this.peerEvidenceRecordKey,
    required this.localEvidenceRecordKey,
    required this.delivered,
    required this.retryAfterUtc,
    required this.updatedAtUtc,
  });

  String get identity => '$peerEvidenceRecordKey\u0000$localEvidenceRecordKey';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'peer_evidence_record_key': peerEvidenceRecordKey,
    'local_evidence_record_key': localEvidenceRecordKey,
    'state': delivered ? 'delivered' : 'retry_after',
    'retry_after_utc': retryAfterUtc.toIso8601String(),
    'updated_at_utc': updatedAtUtc.toIso8601String(),
  };

  static _ConsensusAttestationResponseCheckpoint? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final peerEvidenceRecordKey =
        map['peer_evidence_record_key']?.toString() ?? '';
    final localEvidenceRecordKey =
        map['local_evidence_record_key']?.toString() ?? '';
    final state = map['state']?.toString();
    final retryAfterUtc = DateTime.tryParse(
      map['retry_after_utc']?.toString() ?? '',
    );
    final updatedAtUtc = DateTime.tryParse(
      map['updated_at_utc']?.toString() ?? '',
    );
    if (!_validRecordKey(peerEvidenceRecordKey) ||
        !_validRecordKey(localEvidenceRecordKey) ||
        (state != 'delivered' && state != 'retry_after') ||
        retryAfterUtc?.isUtc != true ||
        updatedAtUtc?.isUtc != true) {
      return null;
    }
    return _ConsensusAttestationResponseCheckpoint(
      peerEvidenceRecordKey: peerEvidenceRecordKey,
      localEvidenceRecordKey: localEvidenceRecordKey,
      delivered: state == 'delivered',
      retryAfterUtc: retryAfterUtc!,
      updatedAtUtc: updatedAtUtc!,
    );
  }
}

int _compareCheckpoints(
  _ConsensusAttestationResponseCheckpoint first,
  _ConsensusAttestationResponseCheckpoint second,
) => first.identity.compareTo(second.identity);

bool _validRecordKey(String value) =>
    value.isNotEmpty && value.length <= 512 && !value.contains('\u0000');
