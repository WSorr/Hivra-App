import 'dart:typed_data';

import 'hivra_bindings.dart';

abstract class CapsuleRuntimeBootstrapRuntime {
  int get legacyNostrOwnerMode;

  int get rootOwnerMode;

  Uint8List? capsuleRuntimeOwnerPublicKey();

  Uint8List? capsuleRootPublicKey();

  Uint8List? loadSeed();

  String? exportLedger();

  bool saveSeed(Uint8List seed);

  bool createCapsule(
    Uint8List seed, {
    required bool isGenesis,
    required bool isNeste,
    required int ownerMode,
  });

  bool importLedger(String ledgerJson);

  Uint8List? seedRootPublicKey(Uint8List seed);

  Uint8List? seedNostrPublicKey(Uint8List seed);
}

class HivraCapsuleRuntimeBootstrapRuntime
    implements CapsuleRuntimeBootstrapRuntime {
  final HivraBindings _hivra;

  HivraCapsuleRuntimeBootstrapRuntime([HivraBindings? hivra])
      : _hivra = hivra ?? HivraBindings();

  @override
  int get legacyNostrOwnerMode => HivraBindings.legacyNostrOwnerMode;

  @override
  int get rootOwnerMode => HivraBindings.rootOwnerMode;

  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() =>
      _hivra.capsuleRuntimeOwnerPublicKey();

  @override
  Uint8List? capsuleRootPublicKey() => _hivra.capsuleRootPublicKey();

  @override
  Uint8List? loadSeed() => _hivra.loadSeed();

  @override
  String? exportLedger() => _hivra.exportLedger();

  @override
  bool saveSeed(Uint8List seed) => _hivra.saveSeed(seed);

  @override
  bool createCapsule(
    Uint8List seed, {
    required bool isGenesis,
    required bool isNeste,
    required int ownerMode,
  }) {
    return _hivra.createCapsule(
      seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      ownerMode: ownerMode,
    );
  }

  @override
  bool importLedger(String ledgerJson) => _hivra.importLedger(ledgerJson);

  @override
  Uint8List? seedRootPublicKey(Uint8List seed) =>
      _hivra.seedRootPublicKey(seed);

  @override
  Uint8List? seedNostrPublicKey(Uint8List seed) =>
      _hivra.seedNostrPublicKey(seed);
}
