import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/ffi/capsule_draft_runtime.dart';
import 'package:hivra_app/services/first_launch_service.dart';

class _FakeCapsuleDraftRuntime implements CapsuleDraftRuntime {
  final Uint8List seed;
  final String? error;
  final bool throwOnSeed;
  bool? lastIsGenesis;
  bool? lastIsNeste;

  _FakeCapsuleDraftRuntime({
    required this.seed,
    this.error,
    this.throwOnSeed = false,
  });

  @override
  Uint8List generateRandomSeed() {
    if (throwOnSeed) {
      throw StateError('seed generation failed');
    }
    return seed;
  }

  @override
  String? createCapsuleError(
    Uint8List seed, {
    required bool isGenesis,
    bool isNeste = true,
  }) {
    lastIsGenesis = isGenesis;
    lastIsNeste = isNeste;
    return error;
  }
}

void main() {
  test('creates genesis draft when runtime returns no error', () {
    final runtime = _FakeCapsuleDraftRuntime(
      seed: Uint8List.fromList(List<int>.generate(32, (i) => i)),
    );
    final service = FirstLaunchService(runtime);

    final result = service.createCapsuleDraft('genesis');

    expect(result.isSuccess, isTrue);
    expect(result.seed, runtime.seed);
    expect(result.isGenesis, isTrue);
    expect(runtime.lastIsGenesis, isTrue);
    expect(runtime.lastIsNeste, isTrue);
  });

  test('creates proto draft with isGenesis=false', () {
    final runtime = _FakeCapsuleDraftRuntime(
      seed: Uint8List.fromList(List<int>.filled(32, 7)),
    );
    final service = FirstLaunchService(runtime);

    final result = service.createCapsuleDraft('proto');

    expect(result.isSuccess, isTrue);
    expect(result.isGenesis, isFalse);
    expect(runtime.lastIsGenesis, isFalse);
    expect(runtime.lastIsNeste, isTrue);
  });

  test('returns failure when runtime rejects capsule draft', () {
    final runtime = _FakeCapsuleDraftRuntime(
      seed: Uint8List.fromList(List<int>.filled(32, 1)),
      error: 'capsule creation blocked',
    );
    final service = FirstLaunchService(runtime);

    final result = service.createCapsuleDraft('genesis');

    expect(result.isSuccess, isFalse);
    expect(result.seed, isNull);
    expect(result.errorMessage, 'capsule creation blocked');
  });

  test('returns failure when runtime throws', () {
    final runtime = _FakeCapsuleDraftRuntime(
      seed: Uint8List.fromList(List<int>.filled(32, 1)),
      throwOnSeed: true,
    );
    final service = FirstLaunchService(runtime);

    final result = service.createCapsuleDraft('genesis');

    expect(result.isSuccess, isFalse);
    expect(result.seed, isNull);
    expect(result.errorMessage, contains('seed generation failed'));
  });
}
