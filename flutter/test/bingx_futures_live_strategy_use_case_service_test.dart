import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/bingx_futures_live_strategy_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_live_snapshot_builder_service.dart';
import 'package:hivra_app/services/bingx_futures_live_strategy_use_case_service.dart';

void main() {
  group('BingxFuturesLiveStrategyUseCaseService', () {
    test('returns typed snapshot failure without evaluating decision',
        () async {
      var decisionEvaluated = false;
      final service = BingxFuturesLiveStrategyUseCaseService(
        exchange: BingxFuturesExchangeService(),
        loadSnapshot: ({
          required exchange,
          required symbol,
          credentials,
        }) async =>
            const BingxFuturesLiveSnapshotBuildResult(
          isSuccess: false,
          errorCode: 'quote_unavailable',
          errorMessage: 'Quote unavailable',
          snapshotInput: null,
          symbol: 'BTC-USDT',
        ),
        evaluateDecision: (_) {
          decisionEvaluated = true;
          throw StateError('must not evaluate');
        },
      );

      final result = await service.execute(
        const BingxFuturesLiveStrategyCommand(
          symbol: 'BTC-USDT',
          credentials: null,
          isConsensusSignable: true,
          blockingFactCodes: <String>[],
          recentMicroBars: 8,
          zoneNearBps: 15,
          zoneFarBps: 35,
          zoneEvaluationSide: null,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'quote_unavailable');
      expect(result.diagnostic, contains('symbol=BTC-USDT'));
      expect(decisionEvaluated, isFalse);
    });
  });
}
