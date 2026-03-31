import 'dart:typed_data';

import 'hivra_bindings.dart';

abstract class CapsuleDraftRuntime {
  Uint8List generateRandomSeed();

  String? createCapsuleError(
    Uint8List seed, {
    required bool isGenesis,
    bool isNeste = true,
  });
}

class HivraCapsuleDraftRuntime implements CapsuleDraftRuntime {
  final HivraBindings _hivra;

  HivraCapsuleDraftRuntime([HivraBindings? hivra])
      : _hivra = hivra ?? HivraBindings();

  @override
  Uint8List generateRandomSeed() => _hivra.generateRandomSeed();

  @override
  String? createCapsuleError(
    Uint8List seed, {
    required bool isGenesis,
    bool isNeste = true,
  }) {
    return _hivra.createCapsuleError(
      seed,
      isNeste: isNeste,
      isGenesis: isGenesis,
      ownerMode: HivraBindings.rootOwnerMode,
    );
  }
}
