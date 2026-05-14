import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_mode_orchestrator_service.dart';

void main() {
  group('BingxFuturesModeOrchestratorService', () {
    test('runs situational mode through shared pipeline', () async {
      var calls = 0;
      final service = BingxFuturesModeOrchestratorService(
        pipeline: (input) {
          calls += 1;
          return BingxFuturesDroneDecisionEnvelope(
            decisionHashHex: '${input.snapshotHashHex}:${input.policyHashHex}',
            payload: <String, dynamic>{
              'snapshot': input.snapshotHashHex,
              'policy': input.policyHashHex,
            },
          );
        },
      );

      final result = await service.runSituational(
        input: const BingxFuturesDroneCycleInput(
          snapshotHashHex: 'snap-a',
          policyHashHex: 'policy-a',
        ),
      );

      expect(calls, 1);
      expect(result.decisionHashHex, 'snap-a:policy-a');
      expect(result.payload['snapshot'], 'snap-a');
    });

    test('runs interactive mode sequentially through shared pipeline',
        () async {
      final seen = <String>[];
      final service = BingxFuturesModeOrchestratorService(
        pipeline: (input) {
          final marker = '${input.snapshotHashHex}:${input.policyHashHex}';
          seen.add(marker);
          return BingxFuturesDroneDecisionEnvelope(
            decisionHashHex: marker,
            payload: <String, dynamic>{'marker': marker},
          );
        },
      );

      final results = await service.runInteractive(
        cycles: const <BingxFuturesDroneCycleInput>[
          BingxFuturesDroneCycleInput(
            snapshotHashHex: 'snap-1',
            policyHashHex: 'policy-1',
          ),
          BingxFuturesDroneCycleInput(
            snapshotHashHex: 'snap-2',
            policyHashHex: 'policy-1',
          ),
        ],
      );

      expect(seen, <String>['snap-1:policy-1', 'snap-2:policy-1']);
      expect(results.length, 2);
      expect(results.first.decisionHashHex, 'snap-1:policy-1');
      expect(results.last.decisionHashHex, 'snap-2:policy-1');
    });

    test('verifies mode parity for identical cycle input', () async {
      final service = BingxFuturesModeOrchestratorService(
        pipeline: (input) => BingxFuturesDroneDecisionEnvelope(
          decisionHashHex: '${input.snapshotHashHex}:${input.policyHashHex}',
          payload: const <String, dynamic>{'ok': true},
        ),
      );

      final parity = await service.verifyModeParity(
        input: const BingxFuturesDroneCycleInput(
          snapshotHashHex: 'snap-parity',
          policyHashHex: 'policy-parity',
        ),
      );

      expect(parity, isTrue);
    });
  });
}
