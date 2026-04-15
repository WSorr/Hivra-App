import 'dart:typed_data';

import 'hivra_bindings.dart';

abstract class LedgerViewRuntime {
  String? exportLedger();

  String? exportCapsuleStateJson();

  Uint8List? capsuleRuntimeOwnerPublicKey();

  Uint8List? capsuleRuntimeTransportPublicKey();
}

class HivraLedgerViewRuntime implements LedgerViewRuntime {
  final HivraBindings _hivra;

  HivraLedgerViewRuntime([HivraBindings? hivra])
      : _hivra = hivra ?? HivraBindings();

  @override
  String? exportLedger() => _hivra.exportLedger();

  @override
  String? exportCapsuleStateJson() => _hivra.exportCapsuleStateJson();

  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() =>
      _hivra.capsuleRuntimeOwnerPublicKey();

  @override
  Uint8List? capsuleRuntimeTransportPublicKey() =>
      _hivra.capsuleNostrPublicKey();
}
