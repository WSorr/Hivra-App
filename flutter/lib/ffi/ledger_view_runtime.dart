import 'dart:typed_data';

import 'hivra_bindings.dart';

abstract class LedgerViewRuntime {
  String? exportLedger();

  String? exportCapsuleStateJson();

  Uint8List? capsuleRuntimeOwnerPublicKey();
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
}
