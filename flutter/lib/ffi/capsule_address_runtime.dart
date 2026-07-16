import 'dart:typed_data';

import 'hivra_bindings.dart';

abstract class CapsuleAddressRuntime {
  Uint8List? capsuleRootPublicKey();

  Uint8List? capsuleNostrPublicKey();

  Uint8List? signRootDigest32(Uint8List message32);

  bool verifyRootDigest32({
    required Uint8List message32,
    required Uint8List pubkey32,
    required Uint8List signature64,
  });
}

class HivraCapsuleAddressRuntime implements CapsuleAddressRuntime {
  final HivraBindings _hivra;

  HivraCapsuleAddressRuntime([HivraBindings? hivra])
      : _hivra = hivra ?? HivraBindings();

  @override
  Uint8List? capsuleRootPublicKey() => _hivra.capsuleRootPublicKey();

  @override
  Uint8List? capsuleNostrPublicKey() => _hivra.capsuleNostrPublicKey();

  @override
  Uint8List? signRootDigest32(Uint8List message32) {
    return _hivra.signRootDigest32(message32);
  }

  @override
  bool verifyRootDigest32({
    required Uint8List message32,
    required Uint8List pubkey32,
    required Uint8List signature64,
  }) {
    return _hivra.verifyEd25519Signature32Code(
          message32,
          pubkey32,
          signature64,
        ) ==
        0;
  }
}
