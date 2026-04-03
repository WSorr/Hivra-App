import 'dart:typed_data';

import 'hivra_bindings.dart';

abstract class CapsuleAddressRuntime {
  Uint8List? capsuleRootPublicKey();

  Uint8List? capsuleNostrPublicKey();
}

class HivraCapsuleAddressRuntime implements CapsuleAddressRuntime {
  final HivraBindings _hivra;

  HivraCapsuleAddressRuntime([HivraBindings? hivra])
      : _hivra = hivra ?? HivraBindings();

  @override
  Uint8List? capsuleRootPublicKey() => _hivra.capsuleRootPublicKey();

  @override
  Uint8List? capsuleNostrPublicKey() => _hivra.capsuleNostrPublicKey();
}
