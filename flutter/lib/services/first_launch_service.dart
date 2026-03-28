import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';

class CreateCapsuleDraftResult {
  final bool isSuccess;
  final Uint8List? seed;
  final bool isGenesis;
  final String? errorMessage;

  const CreateCapsuleDraftResult._({
    required this.isSuccess,
    required this.seed,
    required this.isGenesis,
    this.errorMessage,
  });

  const CreateCapsuleDraftResult.success({
    required Uint8List seed,
    required bool isGenesis,
  }) : this._(
          isSuccess: true,
          seed: seed,
          isGenesis: isGenesis,
        );

  const CreateCapsuleDraftResult.failure(String message)
      : this._(
          isSuccess: false,
          seed: null,
          isGenesis: false,
          errorMessage: message,
        );
}

class FirstLaunchService {
  final HivraBindings _hivra;

  FirstLaunchService([HivraBindings? hivra]) : _hivra = hivra ?? HivraBindings();

  CreateCapsuleDraftResult createCapsuleDraft(String type) {
    try {
      final seed = _hivra.generateRandomSeed();
      final isGenesis = type == 'genesis';
      final error = _hivra.createCapsuleError(
        seed,
        isNeste: true,
        isGenesis: isGenesis,
        ownerMode: HivraBindings.rootOwnerMode,
      );
      if (error != null) {
        return CreateCapsuleDraftResult.failure(error);
      }
      return CreateCapsuleDraftResult.success(
        seed: seed,
        isGenesis: isGenesis,
      );
    } catch (e) {
      return CreateCapsuleDraftResult.failure(e.toString());
    }
  }
}
