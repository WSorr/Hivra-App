import 'dart:typed_data';

import 'hivra_bindings.dart';

bool _bootstrapWorkerRuntime(HivraBindings hivra, Map<String, Object?> args) {
  final seed = args['seed'] as Uint8List;
  final isGenesis = args['isGenesis'] as bool;
  final isNeste = args['isNeste'] as bool;
  final identityMode = args['identityMode'] as String? ?? 'root_owner';
  final ledgerJson = args['ledgerJson'] as String?;

  if (!hivra.saveSeed(seed)) return false;
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
  if (ledgerJson != null &&
      ledgerJson.isNotEmpty &&
      !hivra.importLedger(ledgerJson)) {
    return false;
  }
  return true;
}

Map<String, Object?> sendCapsuleChatInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{
      'result': -1004,
      'lastError': 'Worker bootstrap failed',
    };
  }

  final toPubkey = args['toPubkey'] as Uint8List;
  final payloadJson = args['payloadJson'] as String;
  final result = hivra.sendCapsuleChatCode(toPubkey, payloadJson);
  final lastError = hivra.lastErrorMessage();
  return <String, Object?>{
    'result': result,
    'lastError': lastError,
  };
}

Map<String, Object?> receiveCapsuleChatInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{
      'result': -1004,
      'json': null,
      'lastError': 'Worker bootstrap failed',
    };
  }

  final result = hivra.receiveCapsuleChatJson();
  return <String, Object?>{
    'result': result.code,
    'json': result.json,
    'lastError': hivra.lastErrorMessage(),
  };
}
