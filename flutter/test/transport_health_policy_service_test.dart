import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/transport_health_policy_service.dart';

void main() {
  group('TransportHealthPolicyService', () {
    test('applies capsule-scoped timeout backoff and clears on success', () {
      var now = DateTime.utc(2026, 7, 11, 0, 0);
      final service = TransportHealthPolicyService(
        now: () => now,
        timeoutBackoff: const <Duration>[Duration(seconds: 30)],
      );

      expect(
        service
            .canRun(
              capsuleHex: 'capsule-a',
            )
            .isAllowed,
        isTrue,
      );

      service.recordResult(
        capsuleHex: 'capsule-a',
        code: -1003,
      );

      final blocked = service.canRun(
        capsuleHex: 'capsule-a',
      );
      expect(blocked.isAllowed, isFalse);
      expect(blocked.code, -3101);
      expect(blocked.cooldownRemaining.inSeconds, 30);

      expect(
        service
            .canRun(
              capsuleHex: 'capsule-b',
            )
            .isAllowed,
        isTrue,
      );
      expect(
        service
            .canRun(
              capsuleHex: 'capsule-a',
              manualRetry: true,
            )
            .isAllowed,
        isTrue,
      );

      now = now.add(const Duration(seconds: 10));
      service.recordResult(
        capsuleHex: 'capsule-a',
        code: 0,
      );

      expect(
        service
            .canRun(
              capsuleHex: 'capsule-a',
            )
            .isAllowed,
        isTrue,
      );
    });

    test('ignores unknown capsule identity', () {
      final service = TransportHealthPolicyService(
        timeoutBackoff: const <Duration>[Duration(minutes: 1)],
      );

      service.recordResult(
        capsuleHex: 'unknown',
        code: -1003,
      );

      expect(
        service
            .canRun(
              capsuleHex: 'unknown',
            )
            .isAllowed,
        isTrue,
      );
    });
  });
}
