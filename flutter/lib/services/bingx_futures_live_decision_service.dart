import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bingx_futures_feature_extractor_service.dart';
import 'bingx_futures_market_snapshot_service.dart';
import 'bingx_futures_tvh_rule_engine_service.dart';
import 'bingx_futures_zone_decision_service.dart';

class BingxFuturesLiveDecisionInput {
  final BingxFuturesMarketSnapshotInput snapshotInput;
  final bool isConsensusSignable;
  final List<String> blockingFactCodes;
  final int recentMicroBars;
  final double zoneNearBps;
  final double zoneFarBps;
  final BingxTvhPolicy policy;

  const BingxFuturesLiveDecisionInput({
    required this.snapshotInput,
    required this.isConsensusSignable,
    this.blockingFactCodes = const <String>[],
    this.recentMicroBars = 8,
    this.zoneNearBps = 15.0,
    this.zoneFarBps = 35.0,
    this.policy = const BingxTvhPolicy(),
  });
}

class BingxFuturesLiveDecisionResult {
  final bool canPrepareIntent;
  final BingxTvhDecisionKind decision;
  final String? side;
  final String? zoneSide;
  final String? zoneLowDecimal;
  final String? zoneHighDecimal;
  final bool zoneConflict;
  final String marketSnapshotHashHex;
  final String featureHashHex;
  final String tvhDecisionHashHex;
  final String liveDecisionHashHex;
  final String canonicalJson;
  final List<BingxTvhDecisionReason> reasons;

  const BingxFuturesLiveDecisionResult({
    required this.canPrepareIntent,
    required this.decision,
    required this.side,
    required this.zoneSide,
    required this.zoneLowDecimal,
    required this.zoneHighDecimal,
    required this.zoneConflict,
    required this.marketSnapshotHashHex,
    required this.featureHashHex,
    required this.tvhDecisionHashHex,
    required this.liveDecisionHashHex,
    required this.canonicalJson,
    required this.reasons,
  });
}

class BingxFuturesLiveDecisionService {
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

    final side = switch (tvhDecision.decision) {
      BingxTvhDecisionKind.long => 'buy',
      BingxTvhDecisionKind.short => 'sell',
      BingxTvhDecisionKind.noSignal || BingxTvhDecisionKind.blocked => null,
    };

    BingxFuturesZoneDecisionResult? zone;
    if (side != null) {
      zone = _zoneDecision.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: _parsePositiveDecimal(
            input.snapshotInput.prices.lastTradePriceDecimal,
            field: 'last_trade_price_decimal',
          ),
          fallbackSide: side,
          microHighs: _readHighs(input.snapshotInput.candles, '5m'),
          microLows: _readLows(input.snapshotInput.candles, '5m'),
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

    final zoneConflict = zone != null && zone.side != side;
    final canPrepareIntent = side != null && zone != null && !zoneConflict;
    return _buildResult(
      snapshot: snapshot,
      tvhDecision: tvhDecision,
      side: side,
      zone: zone,
      zoneConflict: zoneConflict,
      canPrepareIntent: canPrepareIntent,
    );
  }

  BingxFuturesLiveDecisionResult _buildResult({
    required BingxFuturesMarketSnapshotDigest snapshot,
    required BingxTvhDecisionResult tvhDecision,
    required String? side,
    required BingxFuturesZoneDecisionResult? zone,
    required bool zoneConflict,
    required bool canPrepareIntent,
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
      'side': side,
      'zone': zone == null
          ? null
          : <String, dynamic>{
              'side': zone.zoneSide,
              'low_decimal': zoneLowDecimal,
              'high_decimal': zoneHighDecimal,
              'source': zone.source,
              'side_reason': zone.sideReason,
              'conflict': zoneConflict,
            },
      'reason_codes': tvhDecision.reasons
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
      reasons: List<BingxTvhDecisionReason>.unmodifiable(tvhDecision.reasons),
    );
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
