import 'dart:async';

enum BingxFuturesDroneMode {
  situational,
  interactive,
}

class BingxFuturesDroneCycleInput {
  final String snapshotHashHex;
  final String policyHashHex;
  final Map<String, dynamic> context;

  const BingxFuturesDroneCycleInput({
    required this.snapshotHashHex,
    required this.policyHashHex,
    this.context = const <String, dynamic>{},
  });
}

class BingxFuturesDroneDecisionEnvelope {
  final String decisionHashHex;
  final Map<String, dynamic> payload;

  const BingxFuturesDroneDecisionEnvelope({
    required this.decisionHashHex,
    required this.payload,
  });
}

typedef BingxFuturesDronePipeline = FutureOr<BingxFuturesDroneDecisionEnvelope>
    Function(BingxFuturesDroneCycleInput input);

class BingxFuturesModeOrchestratorService {
  final BingxFuturesDronePipeline _pipeline;

  const BingxFuturesModeOrchestratorService({
    required BingxFuturesDronePipeline pipeline,
  }) : _pipeline = pipeline;

  Future<BingxFuturesDroneDecisionEnvelope> runSituational({
    required BingxFuturesDroneCycleInput input,
  }) async {
    return await Future<BingxFuturesDroneDecisionEnvelope>.value(
      _pipeline(input),
    );
  }

  Future<List<BingxFuturesDroneDecisionEnvelope>> runInteractive({
    required List<BingxFuturesDroneCycleInput> cycles,
  }) async {
    final results = <BingxFuturesDroneDecisionEnvelope>[];
    for (final cycle in cycles) {
      results.add(
        await Future<BingxFuturesDroneDecisionEnvelope>.value(
          _pipeline(cycle),
        ),
      );
    }
    return results;
  }

  Future<bool> verifyModeParity({
    required BingxFuturesDroneCycleInput input,
  }) async {
    final situational = await runSituational(input: input);
    final interactive =
        await runInteractive(cycles: <BingxFuturesDroneCycleInput>[
      input,
    ]);
    final firstInteractive = interactive.first;
    return situational.decisionHashHex == firstInteractive.decisionHashHex;
  }
}
