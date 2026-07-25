import 'dart:async';

/// Serializes all workers that bootstrap the process-global Rust FFI runtime.
///
/// A worker may target any capsule, but no two workers may overlap: bootstrap
/// replaces the active native capsule and transport state for the process.
class CapsuleFfiWorkerQueue {
  static final CapsuleFfiWorkerQueue shared = CapsuleFfiWorkerQueue();

  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(String capsuleHex, Future<T> Function() operation) {
    final key = capsuleHex.trim().toLowerCase();
    if (key.isEmpty) {
      return Future<T>.error(
        ArgumentError.value(capsuleHex, 'capsuleHex', 'must not be empty'),
      );
    }

    final result = Completer<T>();
    _tail = _tail.catchError((_) {}).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
