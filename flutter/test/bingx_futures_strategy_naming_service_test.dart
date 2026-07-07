import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_strategy_naming_service.dart';

void main() {
  const service = BingxFuturesStrategyNamingService();

  test('names directional TVH decisions consistently', () {
    expect(
      service.tagForDecision(BingxTvhDecisionKind.long),
      'tvh_long_breakout_v1',
    );
    expect(
      service.tagForDecision(BingxTvhDecisionKind.short),
      'tvh_short_breakdown_v1',
    );
  });

  test('does not name non-actionable TVH decisions', () {
    expect(service.tagForDecision(BingxTvhDecisionKind.noSignal), isNull);
    expect(service.tagForDecision(BingxTvhDecisionKind.blocked), isNull);
  });
}
