import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_market_snapshot_models.dart';

class BingxFuturesZoneDecisionInput {
  final String symbol;
  final num midPrice;
  final String fallbackSide;
  final String? requiredSide;
  final bool restingZoneEntry;
  final String strategyVersion;
  final List<num> microHighs;
  final List<num> microLows;
  final List<num> microOpens;
  final List<num> microCloses;
  final List<String> microCloseTimesUtc;
  final List<BingxDetectedLiquidityLevel> detectedLiquidityLevels;
  final List<num> macroHighs;
  final List<num> macroLows;
  final List<num> higherHighs;
  final List<num> higherLows;
  final List<num> higherOpens;
  final List<num> higherCloses;
  final List<String> higherCloseTimesUtc;
  final List<num> dailyHighs;
  final List<num> dailyLows;
  final List<num> dailyCloses;
  final List<String> dailyCloseTimesUtc;
  final List<num> weeklyHighs;
  final List<num> weeklyLows;
  final List<num> weeklyCloses;
  final List<String> weeklyCloseTimesUtc;
  final List<num> liquidationSellLevels;
  final List<num> liquidationBuyLevels;
  final num oiDeltaPct;
  final num sessionDominancePct;
  final int recentMicroBars;
  final double zoneNearBps;
  final double zoneFarBps;

  const BingxFuturesZoneDecisionInput({
    this.symbol = '',
    required this.midPrice,
    required this.fallbackSide,
    this.requiredSide,
    this.restingZoneEntry = false,
    this.strategyVersion = bingxLiquidityStrategyVersion,
    required this.microHighs,
    required this.microLows,
    this.microOpens = const <num>[],
    this.microCloses = const <num>[],
    this.microCloseTimesUtc = const <String>[],
    this.detectedLiquidityLevels = const <BingxDetectedLiquidityLevel>[],
    required this.macroHighs,
    required this.macroLows,
    required this.higherHighs,
    required this.higherLows,
    this.higherOpens = const <num>[],
    required this.higherCloses,
    this.higherCloseTimesUtc = const <String>[],
    required this.dailyHighs,
    required this.dailyLows,
    required this.dailyCloses,
    this.dailyCloseTimesUtc = const <String>[],
    required this.weeklyHighs,
    required this.weeklyLows,
    this.weeklyCloses = const <num>[],
    this.weeklyCloseTimesUtc = const <String>[],
    this.liquidationSellLevels = const <num>[],
    this.liquidationBuyLevels = const <num>[],
    this.oiDeltaPct = 0,
    this.sessionDominancePct = 0,
    required this.recentMicroBars,
    required this.zoneNearBps,
    required this.zoneFarBps,
  });
}

class BingxFuturesZoneDecisionResult {
  final String side;
  final String zoneSide;
  final num zoneLow;
  final num zoneHigh;
  final String source;
  final String sideReason;
  final num olderHigh;
  final num olderLow;
  final num recentHigh;
  final num recentLow;
  final bool sweepUp;
  final bool sweepDown;
  final String trend4h;
  final String trend1d;
  final int contextBias;
  final bool aligned;
  final bool contrarian;
  final bool needsFartherRetest;
  final num rangePct1h;
  final num rangePct4h;
  final num rangePct1d;
  final num rangePct1w;
  final num targetRetestPct;
  final num? externalSellRetest;
  final num? externalBuyRetest;
  final String? externalSellRetestSource;
  final String? externalBuyRetestSource;
  final String? externalSellRetestAtUtc;
  final String? externalBuyRetestAtUtc;
  final String anchorSource;
  final bool anchorExecutable;
  final String anchorLifecycle;
  final int strength;
  final bool usedFallback;
  final String? liquidityEventId;
  final String? liquidityEventAtUtc;
  final String? latestClosedMicroBarAtUtc;
  final Map<String, dynamic>? parentZone;

  const BingxFuturesZoneDecisionResult({
    required this.side,
    required this.zoneSide,
    required this.zoneLow,
    required this.zoneHigh,
    required this.source,
    required this.sideReason,
    required this.olderHigh,
    required this.olderLow,
    required this.recentHigh,
    required this.recentLow,
    required this.sweepUp,
    required this.sweepDown,
    required this.trend4h,
    required this.trend1d,
    required this.contextBias,
    required this.aligned,
    required this.contrarian,
    required this.needsFartherRetest,
    required this.rangePct1h,
    required this.rangePct4h,
    required this.rangePct1d,
    required this.rangePct1w,
    required this.targetRetestPct,
    required this.externalSellRetest,
    required this.externalBuyRetest,
    this.externalSellRetestSource,
    this.externalBuyRetestSource,
    this.externalSellRetestAtUtc,
    this.externalBuyRetestAtUtc,
    required this.anchorSource,
    required this.anchorExecutable,
    required this.anchorLifecycle,
    required this.strength,
    required this.usedFallback,
    this.liquidityEventId,
    this.liquidityEventAtUtc,
    this.latestClosedMicroBarAtUtc,
    this.parentZone,
  });
}

class _ExternalLevelPoint {
  final num price;
  final num weight;
  final String source;
  final String? eventAtUtc;

  const _ExternalLevelPoint({
    required this.price,
    required this.weight,
    required this.source,
    required this.eventAtUtc,
  });
}

enum _LiquidityLevelLifecycle {
  fresh,
  sweepOrigin,
  postSweepReaction,
  consumed,
}

class _SwingPivot {
  final int index;
  final num price;
  final _LiquidityLevelLifecycle lifecycle;

  const _SwingPivot({
    required this.index,
    required this.price,
    required this.lifecycle,
  });
}

class _ExternalRetestLevel {
  final num price;
  final String source;
  final num distancePct;
  final String? eventAtUtc;

  const _ExternalRetestLevel({
    required this.price,
    required this.source,
    required this.distancePct,
    required this.eventAtUtc,
  });
}

class _MicroReclaimEvent {
  final num anchorPrice;
  final num zoneLow;
  final num zoneHigh;
  final int sweepIndex;
  final int reclaimIndex;

  const _MicroReclaimEvent({
    required this.anchorPrice,
    required this.zoneLow,
    required this.zoneHigh,
    required this.sweepIndex,
    required this.reclaimIndex,
  });
}

class BingxFuturesZoneDecisionService {
  static const strategyVersion = bingxLiquidityStrategyVersion;
  String revalidateAnchor({
    required String side,
    required String source,
    required num zoneLow,
    required num zoneHigh,
    required DateTime eventAtUtc,
    required DateTime nowUtc,
    required List<BingxFuturesCandle> candles,
    Map<String, dynamic>? parentZone,
  }) {
    final isHourlyStrategy = source == '1h_active_liquidity_zone';
    final isRestingStrategy =
        source == '4h_active_liquidity_zone' || isHourlyStrategy;
    final isCurrentStrategy = source == '4h_sweep_reclaim_15m';
    final isLegacyParentStrategy = source == '4h_sweep_reclaim_5m';
    final isParentStrategy =
        isRestingStrategy || isCurrentStrategy || isLegacyParentStrategy;
    final uses15m = isRestingStrategy || isCurrentStrategy;
    final interval = Duration(
      minutes:
          isHourlyStrategy
              ? 5
              : uses15m
              ? 15
              : 5,
    );
    final timeframe =
        isHourlyStrategy
            ? '5m'
            : uses15m
            ? '15m'
            : '5m';
    final now = nowUtc.toUtc();
    final event = eventAtUtc.toUtc();
    if (!const {'buy', 'sell'}.contains(side) ||
        !const {
          'micro_sweep_reclaim',
          'micro_liquidity_void',
          '4h_sweep_reclaim_5m',
          '4h_sweep_reclaim_15m',
          '4h_active_liquidity_zone',
          '1h_active_liquidity_zone',
        }.contains(source) ||
        !zoneLow.isFinite ||
        !zoneHigh.isFinite ||
        zoneLow <= 0 ||
        zoneHigh <= zoneLow ||
        event.isAfter(now)) {
      return 'anchor_unavailable';
    }
    DateTime? parentAt;
    num? parentLow;
    num? parentHigh;
    if (isParentStrategy) {
      parentAt =
          DateTime.tryParse(
            parentZone?[isRestingStrategy
                        ? 'anchor_at_utc'
                        : 'confirmed_at_utc']
                    ?.toString() ??
                '',
          )?.toUtc();
      parentLow = num.tryParse(parentZone?['low_decimal']?.toString() ?? '');
      parentHigh = num.tryParse(parentZone?['high_decimal']?.toString() ?? '');
      final expectedStrategyVersion =
          isHourlyStrategy
              ? bingxHourlyLiquidityStrategyVersion
              : isRestingStrategy
              ? strategyVersion
              : isCurrentStrategy
              ? '4h-sweep-reclaim-15m-v3'
              : '4h-sweep-reclaim-5m-v2';
      if (parentZone?['strategy_version'] != expectedStrategyVersion ||
          parentZone?['timeframe'] != (isHourlyStrategy ? '1h' : '4h') ||
          parentZone?['side'] != side ||
          parentAt == null ||
          parentLow == null ||
          parentHigh == null ||
          !parentLow.isFinite ||
          !parentHigh.isFinite ||
          parentLow <= 0 ||
          parentLow > zoneLow ||
          parentHigh < zoneHigh ||
          (isRestingStrategy
              ? event.isBefore(parentAt)
              : event.difference(parentAt) < interval)) {
        return 'anchor_unavailable';
      }
    }
    final closed =
        candles.where((c) => c.timeframe == timeframe && c.isClosed).toList();
    closed.sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    final coverageStart = isRestingStrategy ? event : parentAt ?? event;
    var previous = coverageStart;
    var covered = false;
    var consumed = false;
    for (final candle in closed) {
      final at = DateTime.tryParse(candle.closeTimeUtc)?.toUtc();
      final low = num.tryParse(candle.lowDecimal);
      final high = num.tryParse(candle.highDecimal);
      if (at == null ||
          at.isAfter(now) ||
          low == null ||
          high == null ||
          !low.isFinite ||
          !high.isFinite ||
          low <= 0 ||
          high < low) {
        return 'anchor_unavailable';
      }
      if (at.isBefore(coverageStart)) continue;
      if (!covered) {
        if (at != coverageStart) return 'anchor_unavailable';
        covered = true;
        continue;
      }
      if (at.difference(previous) != interval) return 'anchor_unavailable';
      previous = at;
      consumed =
          consumed ||
          (!isRestingStrategy &&
              parentAt != null &&
              (side == 'buy' ? low < parentLow! : high > parentHigh!)) ||
          (at.isAfter(event) &&
              _anchorConsumed(
                side: side,
                source: source,
                low: low,
                high: high,
                zoneLow: zoneLow,
                zoneHigh: zoneHigh,
              ));
    }
    if (!covered || now.difference(previous) >= interval) {
      return 'anchor_unavailable';
    }
    if (consumed) return 'anchor_consumed';
    if (source == 'micro_liquidity_void' &&
        previous.difference(event).inMinutes ~/ interval.inMinutes >
            _liquidityVoidMaxAgeBars) {
      return 'anchor_expired';
    }
    return 'anchor_valid';
  }

  bool _anchorConsumed({
    required String side,
    required String source,
    required num low,
    required num high,
    required num zoneLow,
    required num zoneHigh,
  }) =>
      source == 'micro_liquidity_void'
          ? (side == 'buy' ? low <= zoneHigh : high >= zoneLow)
          : (side == 'buy' ? low < zoneLow : high > zoneHigh);

  static const int _parentReclaimMaxAgeBars = 8;
  static const double _microReclaimMinBodyAtr = 0.5;
  static const int _liquidityVoidMaxAgeBars = 24;

  const BingxFuturesZoneDecisionService();

  bool _hourly(BingxFuturesZoneDecisionInput input) =>
      input.strategyVersion == bingxHourlyLiquidityStrategyVersion;

  ({String side, num low, num high, String anchorAtUtc})? _selectRestingCluster(
    BingxFuturesZoneDecisionInput input,
  ) {
    final hourly = _hourly(input);
    if (!_continuousTimes(
          input.higherCloseTimesUtc,
          Duration(hours: hourly ? 1 : 4),
          input.higherHighs.length,
        ) ||
        !_continuousTimes(
          input.microCloseTimesUtc,
          Duration(minutes: hourly ? 5 : 15),
          input.microHighs.length,
        ) ||
        input.microLows.length != input.microHighs.length) {
      return null;
    }
    final candidates =
        <
          ({String side, num low, num high, String anchorAtUtc, num distance})
        >[];
    for (final level in input.detectedLiquidityLevels) {
      final side = switch (level.side) {
        'sellside' => 'buy',
        'buyside' => 'sell',
        _ => null,
      };
      final low = num.tryParse(level.zoneBottomDecimal);
      final high = num.tryParse(level.zoneTopDecimal);
      if (side == null ||
          (input.requiredSide != null && input.requiredSide != side) ||
          level.breached ||
          level.pivotCount < 3 ||
          level.anchorIndex < 0 ||
          level.anchorIndex >= input.higherCloseTimesUtc.length ||
          low == null ||
          high == null ||
          !low.isFinite ||
          !high.isFinite ||
          low <= 0 ||
          high <= low ||
          (side == 'buy' ? input.midPrice <= high : input.midPrice >= low)) {
        continue;
      }
      final lastParentClose =
          DateTime.parse(input.higherCloseTimesUtc.last).toUtc();
      if (hourly &&
          !input.microCloseTimesUtc.contains(
            lastParentClose.toIso8601String(),
          )) {
        continue;
      }
      var crossedSinceParentClose = false;
      for (var index = 0; index < input.microCloseTimesUtc.length; index++) {
        final at = DateTime.tryParse(input.microCloseTimesUtc[index])?.toUtc();
        if (at == null || !at.isAfter(lastParentClose)) continue;
        if (side == 'buy'
            ? input.microLows[index] < low
            : input.microHighs[index] > high) {
          crossedSinceParentClose = true;
          break;
        }
      }
      if (crossedSinceParentClose) continue;
      candidates.add((
        side: side,
        low: low,
        high: high,
        anchorAtUtc: input.higherCloseTimesUtc[level.anchorIndex],
        distance: side == 'buy' ? input.midPrice - high : low - input.midPrice,
      ));
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    if (candidates.isEmpty ||
        (candidates.length > 1 &&
            candidates[0].distance == candidates[1].distance)) {
      return null;
    }
    final selected = candidates.first;
    return (
      side: selected.side,
      low: selected.low,
      high: selected.high,
      anchorAtUtc: selected.anchorAtUtc,
    );
  }

  Iterable<_ExternalLevelPoint> _activeOppositeLevels(
    BingxFuturesZoneDecisionInput input, {
    required String side,
  }) sync* {
    for (final level in input.detectedLiquidityLevels) {
      final low = num.tryParse(level.zoneBottomDecimal);
      final high = num.tryParse(level.zoneTopDecimal);
      if (level.side != side ||
          level.breached ||
          level.pivotCount < 3 ||
          low == null ||
          high == null ||
          !low.isFinite ||
          !high.isFinite ||
          low <= 0 ||
          high <= low ||
          level.anchorIndex < 0 ||
          level.anchorIndex >= input.higherCloseTimesUtc.length) {
        continue;
      }
      yield _ExternalLevelPoint(
        price: (low + high) / 2,
        weight: 1.25,
        source:
            _hourly(input)
                ? '1h_active_opposite_liquidity'
                : '4h_active_opposite_liquidity',
        eventAtUtc: input.higherCloseTimesUtc[level.anchorIndex],
      );
    }
  }

  BingxFuturesZoneDecisionResult decide({
    required BingxFuturesZoneDecisionInput input,
  }) {
    if (input.strategyVersion != bingxLiquidityStrategyVersion &&
        input.strategyVersion != bingxHourlyLiquidityStrategyVersion) {
      throw const FormatException('unsupported liquidity strategy');
    }
    final hourly = _hourly(input);
    final mid = input.midPrice;
    if (mid <= 0) {
      throw const FormatException('midPrice must be greater than zero');
    }

    if (input.microHighs.length < 20 ||
        input.microLows.length < 20 ||
        input.macroHighs.length < 20 ||
        input.macroLows.length < 20) {
      final fallbackSide = _normalizeSide(
        input.requiredSide ?? input.fallbackSide,
      );
      final nearDelta = mid * (input.zoneNearBps / 10000.0);
      final farDelta = mid * (input.zoneFarBps / 10000.0);
      final zoneLow = fallbackSide == 'buy' ? mid - farDelta : mid + nearDelta;
      final zoneHigh = fallbackSide == 'buy' ? mid - nearDelta : mid + farDelta;
      return BingxFuturesZoneDecisionResult(
        side: fallbackSide,
        zoneSide: fallbackSide == 'buy' ? 'buyside' : 'sellside',
        zoneLow: zoneLow,
        zoneHigh: zoneHigh,
        source: 'fallback_quote',
        sideReason: 'fallback_quote',
        olderHigh: 0,
        olderLow: 0,
        recentHigh: 0,
        recentLow: 0,
        sweepUp: false,
        sweepDown: false,
        trend4h: 'flat',
        trend1d: 'flat',
        contextBias: 0,
        aligned: false,
        contrarian: false,
        needsFartherRetest: false,
        rangePct1h: 0,
        rangePct4h: 0,
        rangePct1d: 0,
        rangePct1w: 0,
        targetRetestPct: 0,
        externalSellRetest: null,
        externalBuyRetest: null,
        anchorSource: 'fallback',
        anchorExecutable: false,
        anchorLifecycle: 'unavailable',
        strength: 0,
        usedFallback: true,
        latestClosedMicroBarAtUtc: _lastOrNull(input.microCloseTimesUtc),
      );
    }

    final microSplit = input.microHighs.length - input.recentMicroBars;
    if (microSplit < 5) {
      throw const FormatException('not enough structure bars');
    }

    final olderMicroHighs = input.microHighs.sublist(0, microSplit);
    final olderMicroLows = input.microLows.sublist(0, microSplit);
    final recentMicroHighs = input.microHighs.sublist(microSplit);
    final recentMicroLows = input.microLows.sublist(microSplit);

    final olderHigh = olderMicroHighs.reduce((a, b) => a > b ? a : b);
    final olderLow = olderMicroLows.reduce((a, b) => a < b ? a : b);
    final recentHigh = recentMicroHighs.reduce((a, b) => a > b ? a : b);
    final recentLow = recentMicroLows.reduce((a, b) => a < b ? a : b);

    final macroHigh = input.macroHighs.reduce((a, b) => a > b ? a : b);
    final macroLow = input.macroLows.reduce((a, b) => a < b ? a : b);
    final macroRange = macroHigh - macroLow;

    final closedStructurePrice =
        input.microCloses.isNotEmpty && input.microCloses.last > 0
            ? input.microCloses.last
            : (macroHigh + macroLow) / 2;
    final minWidth = closedStructurePrice * 0.0010;
    final maxWidth = closedStructurePrice * 0.0040;
    final widthFromMacro = macroRange * 0.08;
    final width = _clamp(widthFromMacro, minWidth, maxWidth);
    final fallbackWidth = _fallbackZoneWidth(
      mid: mid,
      zoneNearBps: input.zoneNearBps,
      zoneFarBps: input.zoneFarBps,
    );

    final sweepUp = recentHigh > olderHigh;
    final sweepDown = recentLow < olderLow;
    final higherBias = _trendBiasFromCloses(input.higherCloses, window: 12);
    final dailyBias =
        hourly ? 0 : _trendBiasFromCloses(input.dailyCloses, window: 10);
    final contextBias = higherBias + dailyBias;
    final parents = <({String side, _MicroReclaimEvent event})>[];
    if (!input.restingZoneEntry &&
        _continuousTimes(
          input.higherCloseTimesUtc,
          const Duration(hours: 4),
          input.higherHighs.length,
        )) {
      for (final side in const ['buy', 'sell']) {
        for (final cluster in input.detectedLiquidityLevels) {
          final event = _reclaimFromCluster(
            side: side,
            highs: input.higherHighs,
            lows: input.higherLows,
            opens: input.higherOpens,
            closes: input.higherCloses,
            cluster: cluster,
            eventStartIndex: 1,
          );
          if (event != null) parents.add((side: side, event: event));
        }
      }
    }
    // A flow preference cannot select between conflicting parent scenarios.
    parents.sort(
      (a, b) => b.event.reclaimIndex.compareTo(a.event.reclaimIndex),
    );
    final unambiguous =
        parents.isNotEmpty &&
        parents.map((p) => p.side).toSet().length == 1 &&
        (parents.length == 1 ||
            parents[0].event.reclaimIndex != parents[1].event.reclaimIndex);
    final parent = unambiguous ? parents.first : null;
    final resting =
        input.restingZoneEntry ? _selectRestingCluster(input) : null;
    final sideDecision =
        resting != null
            ? (
              side: resting.side,
              reason:
                  hourly
                      ? '1h_active_liquidity_zone'
                      : '4h_active_liquidity_zone',
            )
            : parent != null
            ? (side: parent.side, reason: '4h_sweep_reclaim')
            : input.requiredSide == null
            ? _selectAutoSide(
              sweepUp: sweepUp,
              sweepDown: sweepDown,
              higherBias: higherBias,
              dailyBias: dailyBias,
              contextBias: contextBias,
              mid: mid,
              olderHigh: olderHigh,
              olderLow: olderLow,
              recentHigh: recentHigh,
              recentLow: recentLow,
            )
            : (
              side: _normalizeSide(input.requiredSide!),
              reason: 'tvh_side_locked',
            );

    final selectedSide = sideDecision.side;
    final reversalSignal = selectedSide == 'sell' ? sweepUp : sweepDown;
    final microReclaim =
        input.restingZoneEntry || parent == null
            ? null
            : _confirmParent(input, parent.event, selectedSide);
    final parentZone =
        resting != null
            ? <String, dynamic>{
              'strategy_version': input.strategyVersion,
              'timeframe': hourly ? '1h' : '4h',
              'side': resting.side,
              'low_decimal': resting.low.toStringAsFixed(8),
              'high_decimal': resting.high.toStringAsFixed(8),
              'anchor_at_utc': resting.anchorAtUtc,
            }
            : input.restingZoneEntry || parent == null
            ? null
            : <String, dynamic>{
              'strategy_version': '4h-sweep-reclaim-15m-v3',
              'timeframe': '4h',
              'side': parent.side,
              'low_decimal': parent.event.zoneLow.toStringAsFixed(8),
              'high_decimal': parent.event.zoneHigh.toStringAsFixed(8),
              'sweep_at_utc':
                  input.higherCloseTimesUtc[parent.event.sweepIndex],
              'confirmed_at_utc':
                  input.higherCloseTimesUtc[parent.event.reclaimIndex],
            };
    final aligned =
        (selectedSide == 'buy' && contextBias > 0) ||
        (selectedSide == 'sell' && contextBias < 0);
    final contrarian =
        (selectedSide == 'buy' && contextBias < 0) ||
        (selectedSide == 'sell' && contextBias > 0);
    final macroVolPct = macroRange / mid;

    num higherRangePct = macroVolPct;
    if (input.higherHighs.isNotEmpty && input.higherLows.isNotEmpty) {
      final higherHigh = input.higherHighs.reduce((a, b) => a > b ? a : b);
      final higherLow = input.higherLows.reduce((a, b) => a < b ? a : b);
      higherRangePct = (higherHigh - higherLow) / mid;
    }
    num dailyRangePct = higherRangePct;
    if (input.dailyHighs.isNotEmpty && input.dailyLows.isNotEmpty) {
      final dayHigh = input.dailyHighs.reduce((a, b) => a > b ? a : b);
      final dayLow = input.dailyLows.reduce((a, b) => a < b ? a : b);
      dailyRangePct = (dayHigh - dayLow) / mid;
    }
    num weeklyRangePct = dailyRangePct;
    if (input.weeklyHighs.isNotEmpty && input.weeklyLows.isNotEmpty) {
      final weekHigh = input.weeklyHighs.reduce((a, b) => a > b ? a : b);
      final weekLow = input.weeklyLows.reduce((a, b) => a < b ? a : b);
      weeklyRangePct = (weekHigh - weekLow) / mid;
    }

    var targetRetestDistancePct =
        hourly
            ? _clamp(macroVolPct * 0.42, 0.002, 0.05)
            : _clamp(
              [
                macroVolPct * 1.9,
                higherRangePct * 0.42,
                dailyRangePct * 0.26,
                weeklyRangePct * 0.14,
              ].reduce((a, b) => a > b ? a : b),
              0.02,
              0.11,
            );
    if (!hourly && input.oiDeltaPct.abs() >= 0.015) {
      targetRetestDistancePct = _clamp(
        targetRetestDistancePct + 0.006,
        0.02,
        0.11,
      );
    }
    if (!hourly && input.sessionDominancePct >= 0.55) {
      targetRetestDistancePct = _clamp(
        targetRetestDistancePct + 0.004,
        0.02,
        0.11,
      );
    } else if (!hourly &&
        input.sessionDominancePct > 0 &&
        input.sessionDominancePct <= 0.38) {
      targetRetestDistancePct = _clamp(
        targetRetestDistancePct - 0.003,
        0.02,
        0.11,
      );
    }
    final needsFartherRetest =
        !hourly &&
        ((!reversalSignal && !aligned) ||
            (selectedSide == 'sell' && dailyBias > 0) ||
            (selectedSide == 'buy' && dailyBias < 0));
    if (needsFartherRetest) {
      targetRetestDistancePct = _clamp(
        targetRetestDistancePct + 0.012,
        0.02,
        0.11,
      );
    }

    final externalHighCandidates = <_ExternalLevelPoint>[
      if (input.restingZoneEntry)
        ..._activeOppositeLevels(input, side: 'buyside'),
      ..._freshSwingLevels(
        highs: input.higherHighs,
        lows: input.higherLows,
        closes: input.higherCloses,
        side: 'high',
        source: hourly ? '1h_fresh_high' : '4h_fresh_high',
        weight: 1.00,
        closeTimesUtc: input.higherCloseTimesUtc,
      ),
      if (!hourly)
        ..._freshSwingLevels(
          highs: input.dailyHighs,
          lows: input.dailyLows,
          closes: input.dailyCloses,
          side: 'high',
          source: '1d_fresh_high',
          weight: 1.25,
          closeTimesUtc: input.dailyCloseTimesUtc,
        ),
      if (!hourly)
        ..._freshSwingLevels(
          highs: input.weeklyHighs,
          lows: input.weeklyLows,
          closes: input.weeklyCloses,
          side: 'high',
          source: '1w_fresh_high',
          weight: 1.55,
          closeTimesUtc: input.weeklyCloseTimesUtc,
        ),
    ];
    final externalLowCandidates = <_ExternalLevelPoint>[
      if (input.restingZoneEntry)
        ..._activeOppositeLevels(input, side: 'sellside'),
      ..._freshSwingLevels(
        highs: input.higherHighs,
        lows: input.higherLows,
        closes: input.higherCloses,
        side: 'low',
        source: hourly ? '1h_fresh_low' : '4h_fresh_low',
        weight: 1.00,
        closeTimesUtc: input.higherCloseTimesUtc,
      ),
      if (!hourly)
        ..._freshSwingLevels(
          highs: input.dailyHighs,
          lows: input.dailyLows,
          closes: input.dailyCloses,
          side: 'low',
          source: '1d_fresh_low',
          weight: 1.25,
          closeTimesUtc: input.dailyCloseTimesUtc,
        ),
      if (!hourly)
        ..._freshSwingLevels(
          highs: input.weeklyHighs,
          lows: input.weeklyLows,
          closes: input.weeklyCloses,
          side: 'low',
          source: '1w_fresh_low',
          weight: 1.55,
          closeTimesUtc: input.weeklyCloseTimesUtc,
        ),
    ];
    final externalSellRetest = _selectRetestLevelAbove(
      _applyLiquidationConfluence(
        externalHighCandidates,
        input.liquidationSellLevels,
      ),
      mid,
      minDistancePct: hourly ? 0.002 : 0.008,
      targetDistancePct: targetRetestDistancePct,
      maxDistancePct: hourly ? 0.05 : 0.14,
      preferFarther: !hourly && needsFartherRetest,
    );
    final externalBuyRetest = _selectRetestLevelBelow(
      _applyLiquidationConfluence(
        externalLowCandidates,
        input.liquidationBuyLevels,
      ),
      mid,
      minDistancePct: hourly ? 0.002 : 0.008,
      targetDistancePct: targetRetestDistancePct,
      maxDistancePct: hourly ? 0.05 : 0.14,
      preferFarther: !hourly && needsFartherRetest,
    );

    var anchorSource = 'internal_diagnostic';
    var anchorExecutable = false;
    var anchorLifecycle = 'unavailable';
    String? liquidityEventAtUtc;

    num zoneLow;
    num zoneHigh;
    if (selectedSide == 'sell') {
      var anchorHigh = olderHigh;
      if (resting != null) {
        anchorHigh = resting.high;
        anchorSource =
            hourly ? '1h_active_liquidity_zone' : '4h_active_liquidity_zone';
        anchorExecutable = true;
        anchorLifecycle = 'active';
        liquidityEventAtUtc = input.higherCloseTimesUtc.last;
        zoneLow = resting.low;
        zoneHigh = resting.high;
      } else if (microReclaim != null) {
        anchorHigh = microReclaim.anchorPrice;
        anchorSource = '4h_sweep_reclaim_15m';
        anchorExecutable = true;
        anchorLifecycle = 'reclaimed';
        liquidityEventAtUtc = _atOrNull(
          input.microCloseTimesUtc,
          microReclaim.reclaimIndex,
        );
        zoneLow = microReclaim.zoneLow;
        zoneHigh = microReclaim.zoneHigh;
      } else {
        zoneLow = anchorHigh - width * 0.55;
        zoneHigh = anchorHigh - width * 0.05;
      }
    } else {
      var anchorLow = olderLow;
      if (resting != null) {
        anchorLow = resting.low;
        anchorSource =
            hourly ? '1h_active_liquidity_zone' : '4h_active_liquidity_zone';
        anchorExecutable = true;
        anchorLifecycle = 'active';
        liquidityEventAtUtc = input.higherCloseTimesUtc.last;
        zoneLow = resting.low;
        zoneHigh = resting.high;
      } else if (microReclaim != null) {
        anchorLow = microReclaim.anchorPrice;
        anchorSource = '4h_sweep_reclaim_15m';
        anchorExecutable = true;
        anchorLifecycle = 'reclaimed';
        liquidityEventAtUtc = _atOrNull(
          input.microCloseTimesUtc,
          microReclaim.reclaimIndex,
        );
        zoneLow = microReclaim.zoneLow;
        zoneHigh = microReclaim.zoneHigh;
      } else {
        zoneLow = anchorLow + width * 0.05;
        zoneHigh = anchorLow + width * 0.55;
      }
    }

    if (zoneHigh <= 0 || zoneLow <= 0 || zoneHigh <= zoneLow) {
      anchorSource = 'internal_diagnostic';
      anchorExecutable = false;
      anchorLifecycle = 'unavailable';
      liquidityEventAtUtc = null;
      zoneLow =
          selectedSide == 'buy'
              ? mid - fallbackWidth
              : mid + fallbackWidth * 0.40;
      zoneHigh =
          selectedSide == 'buy'
              ? mid - fallbackWidth * 0.40
              : mid + fallbackWidth;
    }

    var strength = 50;
    if (reversalSignal) strength += 20;
    if (aligned) strength += 15;
    if (contrarian) strength -= 15;
    if (anchorExecutable) strength += 10;
    if (macroVolPct > 0.02) {
      strength += 10;
    } else if (macroVolPct < 0.008) {
      strength -= 8;
    }
    if (input.oiDeltaPct > 0.005) {
      strength += 6;
    } else if (input.oiDeltaPct < -0.005) {
      strength -= 6;
    }
    if (input.sessionDominancePct >= 0.55) {
      strength += 4;
    } else if (input.sessionDominancePct > 0 &&
        input.sessionDominancePct <= 0.38) {
      strength -= 4;
    }
    strength = strength.clamp(0, 100).toInt();

    final liquidityEventId =
        parentZone != null && anchorExecutable && input.symbol.trim().isNotEmpty
            ? sha256
                .convert(
                  utf8.encode(
                    jsonEncode(<String, dynamic>{
                      'symbol': input.symbol.trim().toUpperCase(),
                      'parent':
                          resting == null
                              ? parentZone
                              : <String, dynamic>{
                                'strategy_version': input.strategyVersion,
                                'side': resting.side,
                                'anchor_at_utc': resting.anchorAtUtc,
                              },
                    }),
                  ),
                )
                .toString()
            : null;
    return BingxFuturesZoneDecisionResult(
      side: selectedSide,
      zoneSide: selectedSide == 'buy' ? 'buyside' : 'sellside',
      zoneLow: zoneLow,
      zoneHigh: zoneHigh,
      source: 'mtf_sweep_retest',
      sideReason: sideDecision.reason,
      olderHigh: olderHigh,
      olderLow: olderLow,
      recentHigh: recentHigh,
      recentLow: recentLow,
      sweepUp: sweepUp,
      sweepDown: sweepDown,
      trend4h: _trendLabel(higherBias),
      trend1d: _trendLabel(dailyBias),
      contextBias: contextBias,
      aligned: aligned,
      contrarian: contrarian,
      needsFartherRetest: needsFartherRetest,
      rangePct1h: macroVolPct,
      rangePct4h: higherRangePct,
      rangePct1d: dailyRangePct,
      rangePct1w: weeklyRangePct,
      targetRetestPct: targetRetestDistancePct,
      externalSellRetest: externalSellRetest?.price,
      externalBuyRetest: externalBuyRetest?.price,
      externalSellRetestSource: externalSellRetest?.source,
      externalBuyRetestSource: externalBuyRetest?.source,
      externalSellRetestAtUtc: externalSellRetest?.eventAtUtc,
      externalBuyRetestAtUtc: externalBuyRetest?.eventAtUtc,
      anchorSource: anchorSource,
      anchorExecutable: anchorExecutable,
      anchorLifecycle: anchorLifecycle,
      strength: strength,
      usedFallback: false,
      liquidityEventId: liquidityEventId,
      liquidityEventAtUtc: liquidityEventAtUtc,
      latestClosedMicroBarAtUtc: _lastOrNull(input.microCloseTimesUtc),
      parentZone: parentZone == null ? null : Map.unmodifiable(parentZone),
    );
  }

  String _normalizeSide(String side) {
    final normalized = side.trim().toLowerCase();
    if (normalized == 'buy' || normalized == 'sell') return normalized;
    return 'sell';
  }

  bool _continuousTimes(List<String> times, Duration interval, int count) {
    if (count == 0 || times.length != count) return false;
    DateTime? previous;
    for (final value in times) {
      final time = DateTime.tryParse(value)?.toUtc();
      if (time == null ||
          !value.endsWith('Z') ||
          (previous != null && time.difference(previous) != interval)) {
        return false;
      }
      previous = time;
    }
    return true;
  }

  bool _validOhlc(
    List<num> highs,
    List<num> lows,
    List<num> opens,
    List<num> closes,
  ) {
    if (highs.length != lows.length ||
        highs.length != opens.length ||
        highs.length != closes.length) {
      return false;
    }
    for (var i = 0; i < highs.length; i++) {
      if (![
            highs[i],
            lows[i],
            opens[i],
            closes[i],
          ].every((v) => v.isFinite && v > 0) ||
          lows[i] > highs[i] ||
          opens[i] < lows[i] ||
          opens[i] > highs[i] ||
          closes[i] < lows[i] ||
          closes[i] > highs[i]) {
        return false;
      }
    }
    return true;
  }

  _MicroReclaimEvent? _confirmParent(
    BingxFuturesZoneDecisionInput input,
    _MicroReclaimEvent parent,
    String side,
  ) {
    final count = input.microHighs.length;
    if (!_validOhlc(
          input.microHighs,
          input.microLows,
          input.microOpens,
          input.microCloses,
        ) ||
        !_continuousTimes(
          input.microCloseTimesUtc,
          const Duration(minutes: 15),
          count,
        )) {
      return null;
    }
    final knownAt =
        DateTime.parse(input.higherCloseTimesUtc[parent.reclaimIndex]).toUtc();
    final first = DateTime.parse(input.microCloseTimesUtc.first).toUtc();
    final last = DateTime.parse(input.microCloseTimesUtc.last).toUtc();
    final latestParentBar =
        DateTime.parse(input.higherCloseTimesUtc.last).toUtc();
    if (first.isAfter(knownAt) ||
        !last.isAfter(knownAt) ||
        last.isBefore(latestParentBar) ||
        last.difference(latestParentBar) >= const Duration(hours: 4)) {
      return null;
    }
    _MicroReclaimEvent? confirmed;
    for (var index = 0; index < count; index++) {
      final at = DateTime.parse(input.microCloseTimesUtc[index]).toUtc();
      if (!at.isAfter(knownAt)) continue;
      final low = input.microLows[index];
      final high = input.microHighs[index];
      if (side == 'buy' ? low < parent.zoneLow : high > parent.zoneHigh) {
        return null;
      }
      if (confirmed != null) {
        if (side == 'buy'
            ? low < confirmed.zoneLow
            : high > confirmed.zoneHigh) {
          return null;
        }
        continue;
      }
      if (index < 14 ||
          low < parent.zoneLow ||
          high > parent.zoneHigh ||
          high <= low) {
        continue;
      }
      final open = input.microOpens[index];
      final close = input.microCloses[index];
      final atr = _atrAt(
        highs: input.microHighs,
        lows: input.microLows,
        closes: input.microCloses,
        index: index,
      );
      if ((side == 'buy' ? close > open : close < open) &&
          atr > 0 &&
          (close - open).abs() >= atr * _microReclaimMinBodyAtr) {
        confirmed = _MicroReclaimEvent(
          anchorPrice: parent.anchorPrice,
          zoneLow: low,
          zoneHigh: high,
          sweepIndex: index,
          reclaimIndex: index,
        );
      }
    }
    return confirmed;
  }

  _MicroReclaimEvent? _reclaimFromCluster({
    required String side,
    required List<num> highs,
    required List<num> lows,
    required List<num> opens,
    required List<num> closes,
    required BingxDetectedLiquidityLevel cluster,
    required int eventStartIndex,
  }) {
    if (!_validOhlc(highs, lows, opens, closes) ||
        highs.length < 15 ||
        eventStartIndex <= 0 ||
        eventStartIndex >= highs.length) {
      return null;
    }

    final breach = cluster.breachedIndex;
    final top = num.tryParse(cluster.zoneTopDecimal);
    final bottom = num.tryParse(cluster.zoneBottomDecimal);
    if (cluster.side != (side == 'buy' ? 'sellside' : 'buyside') ||
        cluster.pivotCount < 3 ||
        !cluster.breached ||
        breach == null ||
        breach < eventStartIndex ||
        breach >= highs.length ||
        cluster.anchorIndex < 0 ||
        cluster.anchorIndex >= breach ||
        top == null ||
        bottom == null ||
        !top.isFinite ||
        !bottom.isFinite ||
        bottom <= 0 ||
        top <= bottom) {
      return null;
    }
    final level = side == 'buy' ? bottom : top;
    if (!(side == 'buy' ? lows[breach] < level : highs[breach] > level)) {
      return null;
    }
    int? sweepIndex;
    num? sweepExtreme;
    _MicroReclaimEvent? latestConfirmed;

    for (var index = breach; index < highs.length; index += 1) {
      if (latestConfirmed != null) {
        if (side == 'buy'
            ? lows[index] < sweepExtreme!
            : highs[index] > sweepExtreme!) {
          return null;
        }
        continue;
      }
      final swept = side == 'buy' ? lows[index] < bottom : highs[index] > top;
      if (swept) {
        final extreme = side == 'buy' ? lows[index] : highs[index];
        if (sweepIndex == null) {
          sweepIndex = index;
          sweepExtreme = extreme;
        } else if (side == 'buy'
            ? extreme < sweepExtreme!
            : extreme > sweepExtreme!) {
          sweepExtreme = extreme;
        }
      }
      if (sweepIndex == null || sweepExtreme == null) continue;

      final age = index - sweepIndex;
      if (age > _parentReclaimMaxAgeBars) {
        return null;
      }

      final reclaimed =
          side == 'buy' ? closes[index] > level : closes[index] < level;
      if (reclaimed) {
        latestConfirmed = _MicroReclaimEvent(
          anchorPrice: sweepExtreme,
          zoneLow: side == 'buy' ? sweepExtreme : top,
          zoneHigh: side == 'buy' ? bottom : sweepExtreme,
          sweepIndex: sweepIndex,
          reclaimIndex: index,
        );
      }
    }
    return latestConfirmed;
  }

  num _atrAt({
    required List<num> highs,
    required List<num> lows,
    required List<num> closes,
    required int index,
  }) {
    final first = (index - 13).clamp(0, index);
    var total = 0.0;
    var count = 0;
    for (var cursor = first; cursor <= index; cursor += 1) {
      final range = highs[cursor] - lows[cursor];
      final trueRange =
          cursor == 0
              ? range
              : <num>[
                range,
                (highs[cursor] - closes[cursor - 1]).abs(),
                (lows[cursor] - closes[cursor - 1]).abs(),
              ].reduce((a, b) => a > b ? a : b);
      total += trueRange.toDouble();
      count += 1;
    }
    return count == 0 ? 0 : total / count;
  }

  List<_ExternalLevelPoint> _freshSwingLevels({
    required List<num> highs,
    required List<num> lows,
    required List<num> closes,
    required String side,
    required String source,
    required num weight,
    required List<String> closeTimesUtc,
  }) {
    if (highs.length != lows.length ||
        highs.length != closes.length ||
        highs.length < 5) {
      return const <_ExternalLevelPoint>[];
    }
    final pivots = <_SwingPivot>[];
    _SwingPivot? previousPivot;
    for (var index = 2; index < highs.length - 2; index += 1) {
      final isHigh = side == 'high';
      final price = isHigh ? highs[index] : lows[index];
      final isPivot =
          isHigh
              ? price > highs[index - 1] &&
                  price >= highs[index - 2] &&
                  price > highs[index + 1] &&
                  price >= highs[index + 2]
              : price < lows[index - 1] &&
                  price <= lows[index - 2] &&
                  price < lows[index + 1] &&
                  price <= lows[index + 2];
      if (!isPivot) continue;

      final isSweepOrigin =
          previousPivot != null &&
          (isHigh ? price > previousPivot.price : price < previousPivot.price);
      final isPostSweepReaction =
          previousPivot?.lifecycle == _LiquidityLevelLifecycle.sweepOrigin &&
          !isSweepOrigin;
      var consumed = false;
      for (var later = index + 1; later < highs.length; later += 1) {
        if (isHigh ? highs[later] > price : lows[later] < price) {
          consumed = true;
          break;
        }
      }
      final lifecycle =
          consumed
              ? _LiquidityLevelLifecycle.consumed
              : isSweepOrigin
              ? _LiquidityLevelLifecycle.sweepOrigin
              : isPostSweepReaction
              ? _LiquidityLevelLifecycle.postSweepReaction
              : _LiquidityLevelLifecycle.fresh;
      final pivot = _SwingPivot(
        index: index,
        price: price,
        lifecycle: lifecycle,
      );
      pivots.add(pivot);
      previousPivot = pivot;
    }
    return pivots
        .where((pivot) => pivot.lifecycle == _LiquidityLevelLifecycle.fresh)
        .map(
          (pivot) => _ExternalLevelPoint(
            price: pivot.price,
            weight: weight,
            source: source,
            eventAtUtc: _atOrNull(closeTimesUtc, pivot.index),
          ),
        )
        .toList(growable: false);
  }

  num _fallbackZoneWidth({
    required num mid,
    required double zoneNearBps,
    required double zoneFarBps,
  }) {
    return mid * ((zoneFarBps - zoneNearBps) / 10000.0);
  }

  num _clamp(num value, num min, num max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  int _trendBiasFromCloses(List<num> closes, {int window = 12}) {
    if (closes.length < window * 2) return 0;
    final recent = closes.sublist(closes.length - window);
    final prior = closes.sublist(
      closes.length - (window * 2),
      closes.length - window,
    );
    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
    final priorAvg = prior.reduce((a, b) => a + b) / prior.length;
    if (priorAvg <= 0) return 0;
    final drift = (recentAvg - priorAvg) / priorAvg;
    if (drift > 0.003) return 1;
    if (drift < -0.003) return -1;
    return 0;
  }

  String _trendLabel(int bias) {
    return switch (bias) {
      > 0 => 'bull',
      < 0 => 'bear',
      _ => 'flat',
    };
  }

  ({String side, String reason}) _selectAutoSide({
    required bool sweepUp,
    required bool sweepDown,
    required int higherBias,
    required int dailyBias,
    required int contextBias,
    required num mid,
    required num olderHigh,
    required num olderLow,
    required num recentHigh,
    required num recentLow,
  }) {
    if (sweepUp && !sweepDown) {
      return (side: 'sell', reason: 'sweep_up_reversal');
    }
    if (sweepDown && !sweepUp) {
      return (side: 'buy', reason: 'sweep_down_reversal');
    }
    if (contextBias >= 2) {
      return (side: 'buy', reason: 'mtf_bull_alignment');
    }
    if (contextBias <= -2) {
      return (side: 'sell', reason: 'mtf_bear_alignment');
    }
    if (dailyBias > 0 && higherBias >= 0) {
      return (side: 'buy', reason: 'higher_tf_bull_bias');
    }
    if (dailyBias < 0 && higherBias <= 0) {
      return (side: 'sell', reason: 'higher_tf_bear_bias');
    }

    final refHigh = recentHigh > olderHigh ? recentHigh : olderHigh;
    final refLow = recentLow < olderLow ? recentLow : olderLow;
    final distToHighPct = ((refHigh - mid) / mid).abs();
    final distToLowPct = ((mid - refLow) / mid).abs();
    if (distToHighPct < distToLowPct * 0.72) {
      return (side: 'sell', reason: 'near_upper_liquidity');
    }
    if (distToLowPct < distToHighPct * 0.72) {
      return (side: 'buy', reason: 'near_lower_liquidity');
    }
    return (side: 'sell', reason: 'balanced_tiebreak_sell');
  }

  _ExternalRetestLevel? _selectRetestLevelAbove(
    List<_ExternalLevelPoint> levels,
    num reference, {
    required num minDistancePct,
    required num targetDistancePct,
    num maxDistancePct = 0.20,
    bool preferFarther = false,
  }) {
    _ExternalRetestLevel? best;
    num bestScore = -1e9;
    final target = targetDistancePct.clamp(minDistancePct, maxDistancePct);
    for (final level in levels) {
      if (level.price <= reference) continue;
      final distancePct = (level.price - reference) / reference;
      if (distancePct < minDistancePct || distancePct > maxDistancePct) {
        continue;
      }
      final deltaToTarget = (distancePct - target).abs();
      final closenessScore = 1.0 - (deltaToTarget / maxDistancePct);
      final tooClosePenalty = distancePct < target * 0.65 ? 0.22 : 0.0;
      final fartherBias = preferFarther ? distancePct * 1.35 : 0.0;
      final score =
          closenessScore + level.weight + fartherBias - tooClosePenalty;
      if (best == null || score > bestScore) {
        bestScore = score;
        best = _ExternalRetestLevel(
          price: level.price,
          source: level.source,
          distancePct: distancePct,
          eventAtUtc: level.eventAtUtc,
        );
      }
    }
    return best;
  }

  List<_ExternalLevelPoint> _applyLiquidationConfluence(
    List<_ExternalLevelPoint> levels,
    List<num> liquidationLevels,
  ) {
    final canonicalLiquidationLevels =
        liquidationLevels.where((value) => value > 0).toList()..sort();
    if (canonicalLiquidationLevels.isEmpty) return levels;
    return levels
        .map((level) {
          final nearestBps = canonicalLiquidationLevels
              .map(
                (value) => ((value - level.price).abs() / level.price) * 10000,
              )
              .reduce((left, right) => left < right ? left : right);
          final bonus =
              nearestBps <= 20
                  ? 0.45
                  : nearestBps <= 50
                  ? 0.25
                  : nearestBps <= 100
                  ? 0.10
                  : 0.0;
          return _ExternalLevelPoint(
            price: level.price,
            weight: level.weight + bonus,
            source: level.source,
            eventAtUtc: level.eventAtUtc,
          );
        })
        .toList(growable: false);
  }

  _ExternalRetestLevel? _selectRetestLevelBelow(
    List<_ExternalLevelPoint> levels,
    num reference, {
    required num minDistancePct,
    required num targetDistancePct,
    num maxDistancePct = 0.20,
    bool preferFarther = false,
  }) {
    _ExternalRetestLevel? best;
    num bestScore = -1e9;
    final target = targetDistancePct.clamp(minDistancePct, maxDistancePct);
    for (final level in levels) {
      if (level.price >= reference) continue;
      final distancePct = (reference - level.price) / reference;
      if (distancePct < minDistancePct || distancePct > maxDistancePct) {
        continue;
      }
      final deltaToTarget = (distancePct - target).abs();
      final closenessScore = 1.0 - (deltaToTarget / maxDistancePct);
      final tooClosePenalty = distancePct < target * 0.65 ? 0.22 : 0.0;
      final fartherBias = preferFarther ? distancePct * 1.35 : 0.0;
      final score =
          closenessScore + level.weight + fartherBias - tooClosePenalty;
      if (best == null || score > bestScore) {
        bestScore = score;
        best = _ExternalRetestLevel(
          price: level.price,
          source: level.source,
          distancePct: distancePct,
          eventAtUtc: level.eventAtUtc,
        );
      }
    }
    return best;
  }

  String? _lastOrNull(List<String> values) {
    if (values.isEmpty) return null;
    final normalized = values.last.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _atOrNull(List<String> values, int index) {
    if (index < 0 || index >= values.length) return null;
    final normalized = values[index].trim();
    return normalized.isEmpty ? null : normalized;
  }
}
