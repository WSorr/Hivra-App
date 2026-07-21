import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ffi/app_runtime_runtime.dart';
import '../ffi/consensus_attestation_runtime.dart';
import '../models/consensus_models.dart';
import 'consensus_attestation_store.dart';
import 'consensus_processor.dart';
import 'consensus_runtime_service.dart';
import 'transport_health_policy_service.dart';

const Duration _attestationSendWorkerTimeout = Duration(seconds: 35);
const Duration _attestationReceiveWorkerTimeout = Duration(seconds: 30);

typedef ConsensusAttestationWorkerRunner =
    Future<Map<String, Object?>> Function(Map<String, Object?> args);
typedef ConsensusAttestationNowUtc = DateTime Function();

Future<Map<String, Object?>> _defaultSendWorkerRunner(
  Map<String, Object?> args,
) {
  return compute<Map<String, Object?>, Map<String, Object?>>(
    sendConsensusAttestationInWorker,
    args,
  );
}

Future<Map<String, Object?>> _defaultReceiveWorkerRunner(
  Map<String, Object?> args,
) {
  return compute<Map<String, Object?>, Map<String, Object?>>(
    receiveConsensusAttestationsInWorker,
    args,
  );
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();

class ConsensusAttestationSendResult {
  final bool isSuccess;
  final int code;
  final String? errorMessage;
  final ConsensusAttestationEvidence? evidence;
  final String? deliveryReceiptsJson;

  const ConsensusAttestationSendResult({
    required this.isSuccess,
    required this.code,
    required this.errorMessage,
    required this.evidence,
    this.deliveryReceiptsJson,
  });
}

class ConsensusAttestationReceiveResult {
  final int code;
  final String? errorMessage;
  final int receivedCount;
  final int storedCount;
  final int rejectedCount;
  final List<ConsensusAttestationEvidence> storedEvidence;

  const ConsensusAttestationReceiveResult({
    required this.code,
    required this.errorMessage,
    required this.receivedCount,
    required this.storedCount,
    required this.rejectedCount,
    this.storedEvidence = const <ConsensusAttestationEvidence>[],
  });
}

class ConsensusAttestationSyncService {
  final AppRuntimeRuntime _runtime;
  final ConsensusRuntimeService _consensus;
  final ConsensusAttestationStore _store;
  final ConsensusProcessor _processor;
  final ConsensusAttestationWorkerRunner _sendWorkerRunner;
  final ConsensusAttestationWorkerRunner _receiveWorkerRunner;
  final ConsensusAttestationNowUtc _nowUtc;
  final TransportHealthPolicyService _transportHealth;

  ConsensusAttestationSyncService({
    required AppRuntimeRuntime runtime,
    required ConsensusRuntimeService consensus,
    ConsensusAttestationStore store = const ConsensusAttestationStore(),
    ConsensusProcessor processor = const ConsensusProcessor(),
    ConsensusAttestationWorkerRunner sendWorkerRunner =
        _defaultSendWorkerRunner,
    ConsensusAttestationWorkerRunner receiveWorkerRunner =
        _defaultReceiveWorkerRunner,
    ConsensusAttestationNowUtc nowUtc = _defaultNowUtc,
    TransportHealthPolicyService? transportHealth,
  }) : _runtime = runtime,
       _consensus = consensus,
       _store = store,
       _processor = processor,
       _sendWorkerRunner = sendWorkerRunner,
       _receiveWorkerRunner = receiveWorkerRunner,
       _nowUtc = nowUtc,
       _transportHealth =
           transportHealth ?? TransportHealthPolicyService.shared;

  Future<ConsensusAttestationEvidence?> createLocalEvidence({
    required String peerRootHex,
  }) async {
    final localRootHex = _localRootHex();
    if (localRootHex == null) return null;
    final signable = _consensus.signable(peerRootHex);
    final snapshotHashHex = signable.hashHex;
    if (!signable.isSignable || snapshotHashHex == null) return null;
    final commitment = _processor.buildAttestationCommitment(
      localRootHex: localRootHex,
      peerRootHex: peerRootHex,
      snapshotHashHex: snapshotHashHex,
    );
    if (commitment == null) return null;
    final signatureHex = _runtime.signConsensusCommitment(
      commitment.commitmentHashHex,
    );
    if (signatureHex == null || !_isHex(signatureHex, 128)) return null;
    final evidence = ConsensusAttestationEvidence(
      schemaVersion: 1,
      pairRootsSorted: commitment.pairRootsSorted,
      snapshotHashHex: commitment.snapshotHashHex,
      commitmentHashHex: commitment.commitmentHashHex,
      signerRootHex: localRootHex,
      signatureHex: signatureHex,
      createdAtUtc: _nowUtc().toIso8601String(),
    );
    if (!_verifyEvidence(evidence)) return null;
    await _store.merge(localRootHex, <ConsensusAttestationEvidence>[evidence]);
    return evidence;
  }

  Future<ConsensusAttestationSendResult> sendLocalEvidence({
    required String peerRootHex,
    required String peerTransportHex,
  }) async {
    final evidence = await createLocalEvidence(peerRootHex: peerRootHex);
    if (evidence == null) {
      return const ConsensusAttestationSendResult(
        isSuccess: false,
        code: -2001,
        errorMessage: 'Local pair consensus attestation is not signable',
        evidence: null,
      );
    }
    final peerBytes = _hexToBytes(peerTransportHex);
    if (peerBytes == null) {
      return ConsensusAttestationSendResult(
        isSuccess: false,
        code: -1,
        errorMessage: 'peer_transport_hex must be a 64-char lowercase hex',
        evidence: evidence,
      );
    }
    final bootstrap = await _runtime.loadWorkerBootstrapArgs();
    if (bootstrap == null) {
      return ConsensusAttestationSendResult(
        isSuccess: false,
        code: -1004,
        errorMessage: 'Consensus attestation worker bootstrap unavailable',
        evidence: evidence,
      );
    }

    final workerResult = await _sendWorkerRunner(<String, Object?>{
      ...bootstrap,
      'toPubkey': peerBytes,
      'payloadJson': jsonEncode(evidence.toJson()),
    }).timeout(
      _attestationSendWorkerTimeout,
      onTimeout:
          () => <String, Object?>{
            'result': -1003,
            'lastError':
                'Pair consensus attestation send timed out locally; relay delivery may still complete',
          },
    );
    final code = (workerResult['result'] as int?) ?? -1003;
    final error = workerResult['lastError'] as String?;
    final receipts = workerResult['deliveryReceiptsJson'] as String?;
    return ConsensusAttestationSendResult(
      isSuccess: code == 0,
      code: code,
      errorMessage: code == 0 ? null : error,
      evidence: evidence,
      deliveryReceiptsJson: receipts,
    );
  }

  Future<ConsensusAttestationReceiveResult> receiveAndStore() async {
    final localRootHex = _localRootHex();
    if (localRootHex == null) {
      return const ConsensusAttestationReceiveResult(
        code: -2002,
        errorMessage: 'Local root key unavailable',
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      );
    }
    final health = _transportHealth.canRun(capsuleHex: localRootHex);
    if (!health.isAllowed) {
      return ConsensusAttestationReceiveResult(
        code: health.code,
        errorMessage: health.message,
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      );
    }
    final bootstrap = await _runtime.loadWorkerBootstrapArgs();
    if (bootstrap == null) {
      return const ConsensusAttestationReceiveResult(
        code: -1004,
        errorMessage: 'Consensus attestation worker bootstrap unavailable',
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      );
    }

    final transport = await _receiveWorkerRunner(bootstrap).timeout(
      _attestationReceiveWorkerTimeout,
      onTimeout:
          () => <String, Object?>{
            'result': -1003,
            'json': null,
            'lastError': 'Pair consensus attestation fetch timed out',
          },
    );
    final code = (transport['result'] as int?) ?? -1003;
    _transportHealth.recordResult(capsuleHex: localRootHex, code: code);
    final rawJson = transport['json'] as String?;
    final error = transport['lastError'] as String?;
    if (code < 0) {
      return ConsensusAttestationReceiveResult(
        code: code,
        errorMessage: error,
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      );
    }
    if (rawJson == null || rawJson.trim().isEmpty) {
      return ConsensusAttestationReceiveResult(
        code: code,
        errorMessage: null,
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      );
    }

    final List<dynamic> decoded;
    try {
      final value = jsonDecode(rawJson);
      if (value is! List) {
        return const ConsensusAttestationReceiveResult(
          code: -2003,
          errorMessage: 'Pair consensus attestation receive shape invalid',
          receivedCount: 0,
          storedCount: 0,
          rejectedCount: 0,
        );
      }
      decoded = value;
    } catch (_) {
      return const ConsensusAttestationReceiveResult(
        code: -2003,
        errorMessage: 'Pair consensus attestation receive JSON invalid',
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      );
    }

    final verified = <ConsensusAttestationEvidence>[];
    var rejected = 0;
    for (final item in decoded) {
      if (item is! Map) {
        rejected += 1;
        continue;
      }
      final payloadJson = item['payload_json']?.toString();
      if (payloadJson == null || payloadJson.trim().isEmpty) {
        rejected += 1;
        continue;
      }
      final payload = _parseEvidencePayload(payloadJson);
      if (payload == null ||
          !payload.pairRootsSorted.contains(localRootHex) ||
          !_verifyEvidence(payload)) {
        rejected += 1;
        continue;
      }
      verified.add(payload);
    }
    if (verified.isNotEmpty) {
      await _store.merge(localRootHex, verified);
    }
    return ConsensusAttestationReceiveResult(
      code: code,
      errorMessage: null,
      receivedCount: decoded.length,
      storedCount: verified.length,
      rejectedCount: rejected,
      storedEvidence: List<ConsensusAttestationEvidence>.unmodifiable(verified),
    );
  }

  Future<List<ConsensusAttestationEvidence>> loadVerifiedForPair({
    required String peerRootHex,
  }) async {
    final localRootHex = _localRootHex();
    if (localRootHex == null) return const <ConsensusAttestationEvidence>[];
    final signable = _consensus.signable(peerRootHex);
    final snapshotHashHex = signable.hashHex;
    if (!signable.isSignable || snapshotHashHex == null) {
      return const <ConsensusAttestationEvidence>[];
    }
    final commitment = _processor.buildAttestationCommitment(
      localRootHex: localRootHex,
      peerRootHex: peerRootHex,
      snapshotHashHex: snapshotHashHex,
    );
    if (commitment == null) return const <ConsensusAttestationEvidence>[];
    final evidence = await _store.load(localRootHex);
    return _store
        .matching(
          evidence: evidence.where(_verifyEvidence),
          pairRootsSorted: commitment.pairRootsSorted,
          snapshotHashHex: commitment.snapshotHashHex,
        )
        .toList(growable: false);
  }

  Future<List<ConsensusAttestationEvidence>> loadVerifiedPairEvidence({
    required String peerRootHex,
  }) async {
    final localRootHex = _localRootHex();
    if (localRootHex == null) return const <ConsensusAttestationEvidence>[];
    final peer = peerRootHex.trim().toLowerCase();
    if (!_isHex(peer, 64) || peer == localRootHex) {
      return const <ConsensusAttestationEvidence>[];
    }
    final pairRoots = <String>[localRootHex, peer]..sort();
    final evidence = await _store.load(localRootHex);
    return evidence
        .where(_verifyEvidence)
        .where(
          (item) =>
              item.pairRootsSorted.length == 2 &&
              item.pairRootsSorted[0] == pairRoots[0] &&
              item.pairRootsSorted[1] == pairRoots[1],
        )
        .toList(growable: false);
  }

  String? localRootHex() => _localRootHex();

  ConsensusAttestationEvidence? _parseEvidencePayload(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      return ConsensusAttestationEvidence.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  bool _verifyEvidence(ConsensusAttestationEvidence evidence) {
    final localRootHex = _localRootHex();
    if (localRootHex == null ||
        !evidence.pairRootsSorted.contains(localRootHex)) {
      return false;
    }
    final otherRoots = evidence.pairRootsSorted
        .where((root) => root != localRootHex)
        .toList(growable: false);
    if (otherRoots.length != 1) return false;
    final otherRoot = otherRoots.single;
    final commitment = _processor.buildAttestationCommitment(
      localRootHex: localRootHex,
      peerRootHex: otherRoot,
      snapshotHashHex: evidence.snapshotHashHex,
    );
    if (commitment == null ||
        commitment.commitmentHashHex != evidence.commitmentHashHex ||
        commitment.pairRootsSorted[0] != evidence.pairRootsSorted[0] ||
        commitment.pairRootsSorted[1] != evidence.pairRootsSorted[1]) {
      return false;
    }
    return _runtime.verifyConsensusSignature(
      messageHashHex: evidence.commitmentHashHex,
      participantIdHex: evidence.signerRootHex,
      signatureHex: evidence.signatureHex,
    );
  }

  String? _localRootHex() {
    final root = _runtime.capsuleRootPublicKey();
    if (root == null || root.length != 32) return null;
    return _hex(root);
  }

  Uint8List? _hexToBytes(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_isHex(normalized, 64)) return null;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i += 1) {
      final start = i * 2;
      out[i] = int.parse(normalized.substring(start, start + 2), radix: 16);
    }
    return out;
  }

  String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  bool _isHex(String value, int length) =>
      value.length == length && RegExp(r'^[0-9a-f]+$').hasMatch(value);
}
