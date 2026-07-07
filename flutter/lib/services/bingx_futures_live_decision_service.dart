import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_live_decision_models.dart';
import '../models/bingx_futures_market_snapshot_models.dart';
import '../models/bingx_futures_tvh_rule_models.dart';
import 'bingx_futures_feature_extractor_service.dart';
import 'bingx_futures_market_snapshot_service.dart';
import 'bingx_futures_tvh_rule_engine_service.dart';
import 'bingx_futures_zone_decision_service.dart';

class BingxFuturesLiveDecisionService {
  static const double _trendGateRetestPctThreshold = 0.07;
  static const double _momentumGateZoneDistancePctThreshold = 0.018;

  final BingxFuturesMarketSnapshotService _snapshotService;
  final BingxFuturesFeatureExtractorService _featureExtractor;
  final BingxFuturesTvhRuleEngineService _ruleEngine;
  final BingxFuturesZoneDecisionService _zoneDecision;

  const BingxFuturesLiveDecisionService({
    BingxFuturesMarketSnapshotService snapshotService =
        const BingxFuturesMarketSnapshotService(),
    BingxFuturesFeatureExtractorService featureExtractor =
        const BingxFuturesFeatureExtractorService(),
    BingxFuturesTvhRuleEngineService ruleEngine =
        const BingxFuturesTvhRuleEngineService(),
    BingxFuturesZoneDecisionService zoneDecision =
        const BingxFuturesZoneDecisionService(),
  })  : _snapshotService = snapshotService,
        _featureExtractor = featureExtractor,
        _ruleEngine = ruleEngine,
        _zoneDecision = zoneDecision;

  BingxFuturesLiveDecisionResult decide(BingxFuturesLiveDecisionInput input) {
    final snapshot = _snapshotService.build(input.snapshotInput);
    final features = _featureExtractor.extract(snapshot);
    final tvhDecision = _ruleEngine.evaluate(
      features: features,
      fundingRateDecimal: input.snapshotInput.funding.fundingRateDecimal,
      isConsensusSignable: input.isConsensusSignable,
      blockingFactCodes: input.blockingFactCodes,
      policy: input.policy,
    );

    final decisionSide = switch (tvhDecision.decision) {
      BingxTvhDecisionKind.long => 'buy',
      BingxTvhDecisionKind.short => 'sell',
      BingxTvhDecisionKind.noSignal || BingxTvhDecisionKind.blocked => null,
    };
    final requestedZoneSide = _normalizeSide(input.zoneEvaluationSide);
    final zoneEvaluationSide = decisionSide ?? requestedZoneSide;

    BingxFuturesZoneDecisionResult? zone;
    if (zoneEvaluationSide != null) {
      zone = _zoneDecision.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: _parsePositiveDecimal(
            input.snapshotInput.prices.lastTradePriceDecimal,
            field: 'last_trade_price_decimal',
          ),
          fallbackSide: zoneEvaluationSide,
          requiredSide: zoneEvaluationSide,
          microHighs: _readHighs(input.snapshotInput.candles, '5m'),
          microLows: _readLows(input.snapshotInput.candles, '5m'),
          microCloses: _readCloses(input.snapshotInput.candles, '5m'),
          macroHighs: _readHighs(input.snapshotInput.candles, '1h'),
          macroLows: _readLows(input.snapshotInput.candles, '1h'),
          higherHighs: _readHighs(input.snapshotInput.candles, '4h'),
          higherLows: _readLows(input.snapshotInput.candles, '4h'),
          higherCloses: _readCloses(input.snapshotInput.candles, '4h'),
          dailyHighs: _readHighs(input.snapshotInput.candles, '1d'),
          dailyLows: _readLows(input.snapshotInput.candles, '1d'),
          dailyCloses: _readCloses(input.snapshotInput.candles, '1d'),
          weeklyHighs: _readHighs(input.snapshotInput.candles, '1w'),
          weeklyLows: _readLows(input.snapshotInput.candles, '1w'),
          weeklyCloses: _readCloses(input.snapshotInput.candles, '1w'),
          liquidationSellLevels: _readLiquidationLevels(
            input.snapshotInput.liquidityLevels,
            side: 'sellside',
          ),
          liquidationBuyLevels: _readLiquidationLevels(
            input.snapshotInput.liquidityLevels,
            side: 'buyside',
          ),
          oiDeltaPct: _readOpenInterestDeltaPct(input.snapshotInput),
          sessionDominancePct: _readSessionDominancePct(input.snapshotInput),
          recentMicroBars: input.recentMicroBars,
          zoneNearBps: input.zoneNearBps,
          zoneFarBps: input.zoneFarBps,
        ),
      );
    }

    final zoneConflict = zone != null && zone.side != zoneEvaluationSide;
    final trendGateCode = _evaluateTrendGate(
      side: decisionSide,
      features: features,
      zone: zone,
    );
    final trendGateBlocked = trendGateCode != 'ok';
    final canPrepareIntent = decisionSide != null &&
        zone != null &&
        !zoneConflict &&
        !trendGateBlocked;

    final mergedReasons = <BingxTvhDecisionReason>[
      ...tvhDecision.reasons,
      BingxTvhDecisionReason(
        code: 'zone_side_alignment',
        passed: !zoneConflict,
        detail: zone == null
            ? 'zone_unavailable'
            : 'evaluation_side=$zoneEvaluationSide zone_side=${zone.side}',
      ),
      BingxTvhDecisionReason(
        code: trendGateCode,
        passed: !trendGateBlocked,
        detail: trendGateBlocked ? 'trend_gate_blocked' : 'trend_gate_ok',
      ),
    ];
    return _buildResult(
      snapshot: snapshot,
      tvhDecision: tvhDecision,
      side: decisionSide,
      zoneEvaluationSide: zoneEvaluationSide,
      zone: zone,
      zoneConflict: zoneConflict,
      trendGateBlocked: trendGateBlocked,
      trendGateCode: trendGateCode,
      canPrepareIntent: canPrepareIntent,
      reasons: mergedReasons,
      trend15m: features.trendDirection.name,
      trend4h: zone?.trend4h ?? 'flat',
      trend1d: zone?.trend1d ?? 'flat',
    );
  }

  BingxFuturesLiveDecisionResult _buildResult({
    required BingxFuturesMarketSnapshotDigest snapshot,
    required BingxTvhDecisionResult tvhDecision,
    required String? side,
    required String? zoneEvaluationSide,
    required BingxFuturesZoneDecisionResult? zone,
    required bool zoneConflict,
    required bool trendGateBlocked,
    required String trendGateCode,
    required bool canPrepareIntent,
    required List<BingxTvhDecisionReason> reasons,
    required String trend15m,
    required String trend4h,
    required String trend1d,
  }) {
    final zoneLowDecimal =
        zone == null ? null : _formatDecimal(zone.zoneLow, scale: 8);
    final zoneHighDecimal =
        zone == null ? null : _formatDecimal(zone.zoneHigh, scale: 8);
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'contract': 'bingx_futures_live_decision_v1',
      'market_snapshot_hash_hex': snapshot.marketSnapshotHashHex,
      'feature_hash_hex': tvhDecision.featureHashHex,
      'tvh_decision_hash_hex': tvhDecision.decisionHashHex,
      'decision': tvhDecision.decision.name,
      'can_prepare_intent': canPrepareIntent,
      'trend_bundle': <String, dynamic>{
        'trend_15m': trend15m,
        'trend_4h': trend4h,
        'trend_1d': trend1d,
      },
      'trend_gate': <String, dynamic>{
        'blocked': trendGateBlocked,
        'code': trendGateCode,
      },
      'side': side,
      'zone_evaluation_side': zoneEvaluationSide,
      'zone': zone == null
          ? null
          : <String, dynamic>{
              'side': zone.zoneSide,
              'low_decimal': zoneLowDecimal,
              'high_decimal': zoneHighDecimal,
              'source': zone.source,
              'side_reason': zone.sideReason,
              'conflict': zoneConflict,
              'target_retest_pct': zone.targetRetestPct,
              'needs_farther_retest': zone.needsFartherRetest,
              'anchor_source': zone.anchorSource,
              'anchor_executable': zone.anchorExecutable,
              'anchor_lifecycle': zone.anchorLifecycle,
            },
      'reason_codes': reasons
          .map((reason) => <String, dynamic>{
                'code': reason.code,
                'passed': reason.passed,
              })
          .toList(),
    });
    final liveHash = sha256.convert(utf8.encode(canonical)).toString();
    return BingxFuturesLiveDecisionResult(
      canPrepareIntent: canPrepareIntent,
      decision: tvhDecision.decision,
      side: side,
      zoneSide: zone?.zoneSide,
      zoneLowDecimal: zoneLowDecimal,
      zoneHighDecimal: zoneHighDecimal,
      zoneConflict: zoneConflict,
      marketSnapshotHashHex: snapshot.marketSnapshotHashHex,
      featureHashHex: tvhDecision.featureHashHex,
      tvhDecisionHashHex: tvhDecision.decisionHashHex,
      liveDecisionHashHex: liveHash,
      canonicalJson: canonical,
      reasons: List<BingxTvhDecisionReason>.unmodifiable(reasons),
      trend15m: trend15m,
      trend4h: trend4h,
      trend1d: trend1d,
      trendGateBlocked: trendGateBlocked,
      trendGateCode: trendGateCode,
      zoneAnchorSource: zone?.anchorSource,
      zoneAnchorExecutable: zone?.anchorExecutable ?? false,
      zoneAnchorLifecycle: zone?.anchorLifecycle,
      zoneEvaluationSide: zoneEvaluationSide,
    );
  }

  String? _normalizeSide(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'buy' => 'buy',
      'sell' => 'sell',
      _ => null,
    };
  }

  String _evaluateTrendGate({
    required String? side,
    required BingxFuturesFeatureExtractionResult features,
    required BingxFuturesZoneDecisionResult? zone,
  }) {
    if (side == null || zone == null) return 'ok';
    if (!zone.anchorExecutable) {
      return 'liquidity_anchor_unavailable';
    }
    final trend4h = zone.trend4h.trim().toLowerCase();
    final trend1d = zone.trend1d.trim().toLowerCase();
    final isStrongDownContinuation =
        features.trendDirection == BingxTrendDirection.bearish &&
            trend4h == 'bear' &&
            trend1d == 'bear';
    final isStrongUpContinuation =
        features.trendDirection == BingxTrendDirection.bullish &&
            trend4h == 'bull' &&
            trend1d == 'bull';

    final targetRetestPct = zone.targetRetestPct.toDouble();
    final zoneDistancePct = _zoneDistanceFromMid(
      side: side,
      zone: zone,
    );
    if (side == 'sell' &&
        isStrongDownContinuation &&
        !zone.sweepUp &&
        zoneDistancePct >= _momentumGateZoneDistancePctThreshold) {
      return 'momentum_gate_short_missed_retest';
    }
    if (side == 'buy' &&
        isStrongUpContinuation &&
        !zone.sweepDown &&
        zoneDistancePct >= _momentumGateZoneDistancePctThreshold) {
      return 'momentum_gate_long_missed_retest';
    }
    if (side == 'sell' &&
        isStrongDownContinuation &&
        zone.needsFartherRetest &&
        targetRetestPct >= _trendGateRetestPctThreshold) {
      return 'trend_gate_short_far_retest';
    }
    if (side == 'buy' &&
        isStrongUpContinuation &&
        zone.needsFartherRetest &&
        targetRetestPct >= _trendGateRetestPctThreshold) {
      return 'trend_gate_long_far_retest';
    }
    return 'ok';
  }

  double _zoneDistanceFromMid({
    required String side,
    required BingxFuturesZoneDecisionResult zone,
  }) {
    final mid = (zone.recentHigh + zone.recentLow) / 2;
    if (mid <= 0) return 0;
    if (side == 'sell') {
      final distance = ((zone.zoneLow - mid) / mid).toDouble();
      return distance.clamp(0, 1).toDouble();
    }
    final distance = ((mid - zone.zoneHigh) / mid).toDouble();
    return distance.clamp(0, 1).toDouble();
  }

  List<num> _readHighs(List<BingxFuturesCandle> candles, String timeframe) {
    return _readSeries(candles, timeframe, (candle) => candle.highDecimal);
  }

  List<num> _readLows(List<BingxFuturesCandle> candles, String timeframe) {
    return _readSeries(candles, timeframe, (candle) => candle.lowDecimal);
  }

  List<num> _readCloses(List<BingxFuturesCandle> candles, String timeframe) {
    return _readSeries(candles, timeframe, (candle) => candle.closeDecimal);
  }

  List<num> _readSeries(
    List<BingxFuturesCandle> candles,
    String timeframe,
    String Function(BingxFuturesCandle candle) read,
  ) {
    final normalized = timeframe.trim().toLowerCase();
    final rows = candles
        .where((candle) => candle.timeframe.trim().toLowerCase() == normalized)
        .toList()
      ..sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    return rows
        .map((candle) => _parsePositiveDecimal(read(candle), field: timeframe))
        .toList(growable: false);
  }

  num _parsePositiveDecimal(String raw, {required String field}) {
    final parsed = num.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      throw FormatException('$field must be a positive decimal');
    }
    return parsed;
  }

  String _formatDecimal(num value, {required int scale}) {
    return value.toStringAsFixed(scale).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  List<num> _readLiquidationLevels(
    List<BingxFuturesLiquidityLevel> levels, {
    required String side,
  }) {
    return levels
        .where(
          (level) =>
              level.kind.trim().toLowerCase() == 'liquidation' &&
              level.side.trim().toLowerCase() == side,
        )
        .map((level) => _parsePositiveDecimal(level.priceDecimal, field: side))
        .toList(growable: false);
  }

  num _readOpenInterestDeltaPct(BingxFuturesMarketSnapshotInput input) {
    if (input.openInterest.length < 2) return 0;
    final sorted = input.openInterest.toList()
      ..sort(
        (a, b) => a.timestampUtc.compareTo(b.timestampUtc),
      );
    final first = _parsePositiveDecimal(
      sorted.first.openInterestDecimal,
      field: 'open_interest_first',
    );
    final last = _parsePositiveDecimal(
      sorted.last.openInterestDecimal,
      field: 'open_interest_last',
    );
    if (first <= 0) return 0;
    return (last - first) / first;
  }

  num _readSessionDominancePct(BingxFuturesMarketSnapshotInput input) {
    if (input.sessionVolumes.isEmpty) return 0;
    final volumes = input.sessionVolumes
        .map((session) => num.tryParse(session.volumeDecimal) ?? 0)
        .where((value) => value > 0)
        .toList(growable: false);
    if (volumes.isEmpty) return 0;
    final total = volumes.fold<num>(0, (acc, value) => acc + value);
    if (total <= 0) return 0;
    final maxVolume = volumes.reduce((a, b) => a > b ? a : b);
    return maxVolume / total;
  }
}
