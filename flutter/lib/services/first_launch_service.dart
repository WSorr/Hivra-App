import 'dart:typed_data';

import '../ffi/capsule_draft_runtime.dart';

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
  final CapsuleDraftRuntime _runtime;

  FirstLaunchService([CapsuleDraftRuntime? runtime])
      : _runtime = runtime ?? HivraCapsuleDraftRuntime();

  CreateCapsuleDraftResult createCapsuleDraft(String type) {
    try {
      final seed = _runtime.generateRandomSeed();
      final isGenesis = type == 'genesis';
      final error = _runtime.createCapsuleError(
        seed,
        isNeste: true,
        isGenesis: isGenesis,
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
