import 'dart:typed_data';

import '../services/capsule_persistence_service.dart';
import '../services/capsule_persistence_models.dart';
import 'capsule_address_runtime.dart';
import 'hivra_bindings.dart';
import 'invitation_actions_runtime.dart';
import 'ledger_view_runtime.dart';

abstract class AppRuntimeRuntime {
  LedgerViewRuntime get ledgerViewRuntime;

  InvitationActionsRuntime get invitationActionsRuntime;

  CapsuleAddressRuntime get capsuleAddressRuntime;

  Future<bool> bootstrapActiveCapsuleRuntime();

  Future<void> persistLedgerSnapshot();

  Uint8List? capsuleRootPublicKey();

  Uint8List? capsuleNostrPublicKey();

  Uint8List? loadSeed();

  String? exportLedger();

  String? invokeWasmJson({
    required Uint8List moduleBytes,
    required String entryExport,
    required Uint8List inputJsonBytes,
  });

  Future<Map<String, Object?>?> loadWorkerBootstrapArgs();

  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  );

  Future<CapsuleTraceReport> diagnoseCapsuleTraces();

  Future<CapsuleBootstrapReport> diagnoseBootstrapReport();

  bool verifyConsensusSignature({
    required String messageHashHex,
    required String participantIdHex,
    required String signatureHex,
  });

  String? signConsensusCommitment(String commitmentHashHex);
}

class HivraAppRuntimeRuntime implements AppRuntimeRuntime {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  @override
  late final LedgerViewRuntime ledgerViewRuntime =
      HivraLedgerViewRuntime(_hivra);

  @override
  late final InvitationActionsRuntime invitationActionsRuntime =
      HivraInvitationActionsRuntime(
    hivra: _hivra,
    persistence: _persistence,
  );

  @override
  late final CapsuleAddressRuntime capsuleAddressRuntime =
      HivraCapsuleAddressRuntime(_hivra);

  HivraAppRuntimeRuntime({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  @override
  Future<bool> bootstrapActiveCapsuleRuntime() {
    return _persistence.bootstrapActiveCapsuleRuntime(_hivra);
  }

  @override
  Future<void> persistLedgerSnapshot() async {
    await _persistence.persistLedgerSnapshot(_hivra);
  }

  @override
  Uint8List? capsuleRootPublicKey() => _hivra.capsuleRootPublicKey();

  @override
  Uint8List? capsuleNostrPublicKey() => _hivra.capsuleNostrPublicKey();

  @override
  Uint8List? loadSeed() => _hivra.loadSeed();

  @override
  String? exportLedger() => _hivra.exportLedger();

  @override
  String? invokeWasmJson({
    required Uint8List moduleBytes,
    required String entryExport,
    required Uint8List inputJsonBytes,
  }) {
    return _hivra.invokeWasmJson(
      moduleBytes: moduleBytes,
      entryExport: entryExport,
      inputJsonBytes: inputJsonBytes,
    );
  }

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs() {
    return _persistence.loadWorkerBootstrapArgs(_hivra);
  }

  @override
  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  ) {
    return _hivra.breakRelationship(peerPubkey, ownStarterId, peerStarterId);
  }

  @override
  Future<CapsuleTraceReport> diagnoseCapsuleTraces() {
    return _persistence.diagnoseCapsuleTraces(_hivra);
  }

  @override
  Future<CapsuleBootstrapReport> diagnoseBootstrapReport() {
    return _persistence.diagnoseBootstrapReport(_hivra);
  }

  @override
  bool verifyConsensusSignature({
    required String messageHashHex,
    required String participantIdHex,
    required String signatureHex,
  }) {
    final message32 = _hexToBytes(messageHashHex, 32);
    final pubkey32 = _hexToBytes(participantIdHex, 32);
    final signature64 = _hexToBytes(signatureHex, 64);
    if (message32 == null || pubkey32 == null || signature64 == null) {
      return false;
    }
    return _hivra.verifyEd25519Signature32Code(
          message32,
          pubkey32,
          signature64,
        ) ==
        0;
  }

  @override
  String? signConsensusCommitment(String commitmentHashHex) {
    final digest = _hexToBytes(commitmentHashHex, 32);
    if (digest == null) return null;
    final signature = _hivra.signRootDigest32(digest);
    if (signature == null || signature.length != 64) return null;
    return signature
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Uint8List? _hexToBytes(String value, int expectedBytes) {
    final normalized = value.trim().toLowerCase();
    final expectedHexLength = expectedBytes * 2;
    if (normalized.length != expectedHexLength ||
        !RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
      return null;
    }
    final out = Uint8List(expectedBytes);
    for (var i = 0; i < expectedBytes; i += 1) {
      final start = i * 2;
      out[i] = int.parse(normalized.substring(start, start + 2), radix: 16);
    }
    return out;
  }
}
