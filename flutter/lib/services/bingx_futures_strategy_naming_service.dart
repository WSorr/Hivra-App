import '../models/bingx_futures_tvh_rule_models.dart';

class BingxFuturesStrategyNamingService {
  const BingxFuturesStrategyNamingService();

  String? tagForDecision(BingxTvhDecisionKind decision) {
    return switch (decision) {
      BingxTvhDecisionKind.long => 'tvh_long_breakout_v1',
      BingxTvhDecisionKind.short => 'tvh_short_breakdown_v1',
      BingxTvhDecisionKind.noSignal || BingxTvhDecisionKind.blocked => null,
    };
  }
}
