import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_zone_decision_service.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';

void main() {
  group('original anchor revalidation', () {
    const service = BingxFuturesZoneDecisionService();
    final event = DateTime.utc(2026, 9, 20, 12);
    BingxFuturesCandle bar(
      int index, {
      num low = 101,
      num high = 103,
      bool closed = true,
      int minutes = 5,
      String timeframe = '5m',
    }) {
      final close = event.add(Duration(minutes: index * minutes));
      return BingxFuturesCandle(
        timeframe: timeframe,
        openTimeUtc:
            close.subtract(Duration(minutes: minutes)).toIso8601String(),
        closeTimeUtc: close.toIso8601String(),
        openDecimal: '102',
        highDecimal: '$high',
        lowDecimal: '$low',
        closeDecimal: '102',
        volumeBaseDecimal: '1',
        volumeQuoteDecimal: '102',
        isClosed: closed,
      );
    }

    String check(
      List<BingxFuturesCandle> bars, {
      String side = 'buy',
      String source = 'micro_sweep_reclaim',
      int age = 2,
    }) => service.revalidateAnchor(
      side: side,
      source: source,
      zoneLow: 100,
      zoneHigh: 102,
      eventAtUtc: event,
      nowUtc: event.add(Duration(minutes: age * 5)),
      candles: bars,
    );

    test('reclaim consumes only a later strict sweep on the original side', () {
      expect(
        check([bar(0, low: 90), bar(1, low: 100), bar(2)]),
        'anchor_valid',
      );
      expect(check([bar(0), bar(1, low: 99), bar(2)]), 'anchor_consumed');
      expect(
        check([bar(0), bar(1, high: 102), bar(2, high: 102)], side: 'sell'),
        'anchor_valid',
      );
      expect(
        check([bar(0), bar(1), bar(2, high: 102)], side: 'sell'),
        'anchor_consumed',
      );
    });

    test(
      'HTF revalidation requires parent binding and continuous parent coverage',
      () {
        final parent = <String, dynamic>{
          'strategy_version': '4h-sweep-reclaim-15m-v3',
          'timeframe': '4h',
          'side': 'buy',
          'low_decimal': '99',
          'high_decimal': '104',
          'confirmed_at_utc': event.toIso8601String(),
        };
        BingxFuturesCandle parentBar(int index, {num low = 101}) =>
            bar(index, low: low, minutes: 15, timeframe: '15m');
        String verify(
          List<BingxFuturesCandle> bars,
          Map<String, dynamic>? bound,
        ) => service.revalidateAnchor(
          side: 'buy',
          source: '4h_sweep_reclaim_15m',
          zoneLow: 100,
          zoneHigh: 102,
          eventAtUtc: event.add(const Duration(minutes: 15)),
          nowUtc: event.add(const Duration(minutes: 30)),
          candles: bars,
          parentZone: bound,
        );
        expect(
          verify([parentBar(0), parentBar(1), parentBar(2)], parent),
          'anchor_valid',
        );
        expect(
          verify([parentBar(0), parentBar(1), parentBar(2, low: 99.5)], parent),
          'anchor_consumed',
        );
        expect(
          verify([parentBar(0), parentBar(1, low: 98), parentBar(2)], parent),
          'anchor_consumed',
        );
        expect(
          verify([parentBar(1), parentBar(2)], parent),
          'anchor_unavailable',
        );
        expect(
          verify([parentBar(0), parentBar(1), parentBar(2)], null),
          'anchor_unavailable',
        );
        expect(
          verify(
            [parentBar(0), parentBar(1), parentBar(2)],
            {...parent, 'side': 'sell'},
          ),
          'anchor_unavailable',
        );
        expect(
          service.revalidateAnchor(
            side: 'buy',
            source: '4h_sweep_reclaim_5m',
            zoneLow: 100,
            zoneHigh: 102,
            eventAtUtc: event.add(const Duration(minutes: 5)),
            nowUtc: event.add(const Duration(minutes: 10)),
            candles: [bar(0), bar(1), bar(2)],
            parentZone: {
              ...parent,
              'strategy_version': '4h-sweep-reclaim-5m-v2',
            },
          ),
          'anchor_valid',
        );
      },
    );

    test('resting 4h zone is retained until a later 15m outer breach', () {
      final parent = <String, dynamic>{
        'strategy_version': bingxLiquidityStrategyVersion,
        'timeframe': '4h',
        'side': 'buy',
        'low_decimal': '100',
        'high_decimal': '102',
        'anchor_at_utc':
            event.subtract(const Duration(hours: 4)).toIso8601String(),
      };
      String verify(List<BingxFuturesCandle> bars) => service.revalidateAnchor(
        side: 'buy',
        source: '4h_active_liquidity_zone',
        zoneLow: 100,
        zoneHigh: 102,
        eventAtUtc: event,
        nowUtc: event.add(const Duration(minutes: 30)),
        candles: bars,
        parentZone: parent,
      );
      expect(
        verify([
          bar(0, minutes: 15, timeframe: '15m'),
          bar(1, minutes: 15, timeframe: '15m'),
          bar(2, minutes: 15, timeframe: '15m'),
        ]),
        'anchor_valid',
      );
      expect(
        verify([
          bar(0, minutes: 15, timeframe: '15m'),
          bar(1, low: 99, minutes: 15, timeframe: '15m'),
          bar(2, minutes: 15, timeframe: '15m'),
        ]),
        'anchor_consumed',
      );
      expect(
        verify([
          bar(0, minutes: 15, timeframe: '15m'),
          bar(2, minutes: 15, timeframe: '15m'),
        ]),
        'anchor_unavailable',
      );
    });
    test('resting 1h zone uses 5m coverage and rejects an outer breach', () {
      final parent = <String, dynamic>{
        'strategy_version': bingxHourlyLiquidityStrategyVersion,
        'timeframe': '1h',
        'side': 'buy',
        'low_decimal': '100',
        'high_decimal': '102',
        'anchor_at_utc':
            event.subtract(const Duration(hours: 1)).toIso8601String(),
      };
      String verify(List<BingxFuturesCandle> bars) => service.revalidateAnchor(
        side: 'buy',
        source: '1h_active_liquidity_zone',
        zoneLow: 100,
        zoneHigh: 102,
        eventAtUtc: event,
        nowUtc: event.add(const Duration(minutes: 10)),
        candles: bars,
        parentZone: parent,
      );
      expect(verify([bar(0), bar(1), bar(2)]), 'anchor_valid');
      expect(verify([bar(0), bar(1, low: 99), bar(2)]), 'anchor_consumed');
      expect(verify([bar(0), bar(2)]), 'anchor_unavailable');
      expect(
        service.revalidateAnchor(
          side: 'buy',
          source: '1h_active_liquidity_zone',
          zoneLow: 100,
          zoneHigh: 102,
          eventAtUtc: event,
          nowUtc: event.add(const Duration(minutes: 10)),
          candles: [bar(0), bar(1), bar(2)],
          parentZone: {
            ...parent,
            'strategy_version': bingxLiquidityStrategyVersion,
          },
        ),
        'anchor_unavailable',
      );
    });
    test('void consumes on inclusive near-edge touch for either side', () {
      expect(
        check([
          bar(0),
          bar(1, low: 103),
          bar(2, low: 103),
        ], source: 'micro_liquidity_void'),
        'anchor_valid',
      );
      expect(
        check([
          bar(0),
          bar(1, low: 102),
          bar(2, low: 103),
        ], source: 'micro_liquidity_void'),
        'anchor_consumed',
      );
      expect(
        check(
          [bar(0), bar(1, low: 98, high: 99), bar(2, low: 98, high: 99)],
          source: 'micro_liquidity_void',
          side: 'sell',
        ),
        'anchor_valid',
      );
      expect(
        check(
          [bar(0), bar(1, low: 98, high: 100), bar(2, low: 98, high: 99)],
          source: 'micro_liquidity_void',
          side: 'sell',
        ),
        'anchor_consumed',
      );
    });
    test(
      'missing, stale, duplicate and gapped coverage cannot authorize cancellation',
      () {
        for (final bars in <List<BingxFuturesCandle>>[
          [],
          [bar(1), bar(2)],
          [bar(0), bar(1)],
          [bar(0), bar(1), bar(1), bar(2)],
          [bar(0), bar(2, low: 99)],
          [bar(0), bar(1), bar(2), bar(3)],
        ]) {
          expect(check(bars), 'anchor_unavailable');
        }
      },
    );
    test('forming candle does not consume a confirmed anchor', () {
      expect(
        check([bar(0), bar(1), bar(2), bar(3, low: 90, closed: false)]),
        'anchor_valid',
      );
    });
    test('only untouched void expires after 24 closed bars', () {
      final bars = List.generate(26, (i) => bar(i, low: 103));
      expect(
        check(bars.take(25).toList(), source: 'micro_liquidity_void', age: 24),
        'anchor_valid',
      );
      expect(
        check(bars, source: 'micro_liquidity_void', age: 25),
        'anchor_expired',
      );
      expect(check(bars, age: 25), 'anchor_valid');
    });
  });
  group('BingxFuturesZoneDecisionService', () {
    const service = BingxFuturesZoneDecisionService();

    test('falls back to quote-based zone when structure is insufficient', () {
      const input = BingxFuturesZoneDecisionInput(
        midPrice: 100.0,
        fallbackSide: 'buy',
        microHighs: <num>[100, 101],
        microLows: <num>[99, 98],
        macroHighs: <num>[102, 103],
        macroLows: <num>[97, 96],
        higherHighs: <num>[],
        higherLows: <num>[],
        higherCloses: <num>[],
        dailyHighs: <num>[],
        dailyLows: <num>[],
        dailyCloses: <num>[],
        weeklyHighs: <num>[],
        weeklyLows: <num>[],
        recentMicroBars: 8,
        zoneNearBps: 15.0,
        zoneFarBps: 35.0,
      );

      final result = service.decide(input: input);

      expect(result.usedFallback, isTrue);
      expect(result.side, 'buy');
      expect(result.zoneSide, 'buyside');
      expect(result.source, 'fallback_quote');
      expect(result.zoneLow, closeTo(99.65, 0.0000001));
      expect(result.zoneHigh, closeTo(99.85, 0.0000001));
    });

    test('selects sell on clear sweep-up reversal', () {
      final result = service.decide(input: _inputForSweepUp());

      expect(result.usedFallback, isFalse);
      expect(result.side, 'sell');
      expect(result.zoneSide, 'sellside');
      expect(result.sideReason, 'sweep_up_reversal');
      expect(result.zoneHigh, greaterThan(result.zoneLow));
    });

    test('is deterministic for identical inputs', () {
      final first = service.decide(input: _inputForSweepDown());
      final second = service.decide(input: _inputForSweepDown());

      expect(first.side, second.side);
      expect(first.sideReason, second.sideReason);
      expect(first.zoneLow, second.zoneLow);
      expect(first.zoneHigh, second.zoneHigh);
      expect(first.anchorSource, second.anchorSource);
      expect(first.targetRetestPct, second.targetRetestPct);
      expect(first.strength, second.strength);
    });

    test('does not use liquidation proxy as executable entry anchor', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: base.midPrice,
          fallbackSide: base.fallbackSide,
          microHighs: base.microHighs,
          microLows: base.microLows,
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: base.higherHighs,
          higherLows: base.higherLows,
          higherCloses: base.higherCloses,
          dailyHighs: base.dailyHighs,
          dailyLows: base.dailyLows,
          dailyCloses: base.dailyCloses,
          weeklyHighs: base.weeklyHighs,
          weeklyLows: base.weeklyLows,
          liquidationSellLevels: const <num>[124.0],
          liquidationBuyLevels: const <num>[86.0],
          oiDeltaPct: 0.03,
          sessionDominancePct: 0.62,
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );

      expect(result.usedFallback, isFalse);
      expect(result.anchorSource, isNot(anyOf('liq_sell', 'liq_buy')));
      expect(result.strength, greaterThanOrEqualTo(50));
    });

    test('fresh structure without event time remains non executable', () {
      final base = _inputForSweepUp();
      BingxFuturesZoneDecisionInput input({List<num> proxies = const <num>[]}) {
        return BingxFuturesZoneDecisionInput(
          midPrice: 110,
          fallbackSide: 'buy',
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: const <num>[
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
          ],
          higherLows: const <num>[
            105,
            104,
            100,
            104,
            106,
            105,
            102,
            105,
            106,
            105,
            104,
            105,
          ],
          higherCloses: const <num>[
            112,
            110,
            104,
            108,
            114,
            111,
            106,
            109,
            113,
            108,
            107,
            109,
          ],
          dailyHighs: const <num>[],
          dailyLows: const <num>[],
          dailyCloses: const <num>[],
          weeklyHighs: const <num>[],
          weeklyLows: const <num>[],
          liquidationBuyLevels: proxies,
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        );
      }

      final withoutProxy = service.decide(input: input());
      final withProxy = service.decide(input: input(proxies: const <num>[102]));

      expect(withoutProxy.externalBuyRetest, 100);
      expect(withProxy.externalBuyRetest, 102);
      expect(withProxy.anchorSource, 'internal_diagnostic');
      expect(withProxy.anchorExecutable, isFalse);
      expect(withProxy.liquidityEventId, isNull);
    });

    test('locks zone calculation to upstream TVH side', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: base.midPrice,
          fallbackSide: base.fallbackSide,
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: base.higherHighs,
          higherLows: base.higherLows,
          higherCloses: base.higherCloses,
          dailyHighs: base.dailyHighs,
          dailyLows: base.dailyLows,
          dailyCloses: base.dailyCloses,
          weeklyHighs: base.weeklyHighs,
          weeklyLows: base.weeklyLows,
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );

      expect(result.side, 'buy');
      expect(result.zoneSide, 'buyside');
      expect(result.sideReason, 'tvh_side_locked');
      expect(result.zoneHigh, lessThan(base.midPrice));
    });

    test('does not reuse a pivot formed by sweeping prior liquidity', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: 110,
          fallbackSide: 'buy',
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: const <num>[
            120,
            119,
            118,
            119,
            120,
            118,
            117,
            118,
            119,
            117,
            116,
            117,
          ],
          higherLows: const <num>[
            105,
            104,
            100,
            103,
            106,
            102,
            98,
            101,
            104,
            100,
            95,
            99,
          ],
          higherCloses: const <num>[
            112,
            110,
            104,
            108,
            114,
            109,
            103,
            107,
            113,
            105,
            101,
            108,
          ],
          dailyHighs: const <num>[],
          dailyLows: const <num>[],
          dailyCloses: const <num>[],
          weeklyHighs: const <num>[],
          weeklyLows: const <num>[],
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );

      expect(result.externalBuyRetest, isNull);
      expect(result.anchorSource, 'internal_diagnostic');
    });

    test('does not reuse a fresh pivot after a later breach', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: 110,
          fallbackSide: 'buy',
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: const <num>[
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
          ],
          higherLows: const <num>[
            105,
            104,
            100,
            103,
            106,
            105,
            104,
            102,
            105,
            104,
            99,
            103,
          ],
          higherCloses: const <num>[
            112,
            110,
            104,
            108,
            114,
            111,
            109,
            106,
            113,
            108,
            104,
            109,
          ],
          dailyHighs: const <num>[],
          dailyLows: const <num>[],
          dailyCloses: const <num>[],
          weeklyHighs: const <num>[],
          weeklyLows: const <num>[],
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );

      expect(result.externalBuyRetest, isNull);
      expect(result.anchorSource, 'internal_diagnostic');
    });

    test('does not promote first post-sweep reaction pivot to fresh', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: 110,
          fallbackSide: 'buy',
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: const <num>[
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
            120,
            119,
            118,
          ],
          higherLows: const <num>[
            105,
            103,
            100,
            103,
            105,
            100,
            95,
            100,
            103,
            101,
            98,
            102,
            104,
            105,
            106,
          ],
          higherCloses: const <num>[
            112,
            110,
            104,
            108,
            114,
            109,
            101,
            107,
            113,
            106,
            103,
            108,
            114,
            112,
            111,
          ],
          dailyHighs: const <num>[],
          dailyLows: const <num>[],
          dailyCloses: const <num>[],
          weeklyHighs: const <num>[],
          weeklyLows: const <num>[],
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );

      expect(result.externalBuyRetest, isNull);
      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorExecutable, isFalse);
    });

    test('keeps timestamped untouched low as target-only liquidity', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          symbol: 'BTC-USDT',
          midPrice: 110,
          fallbackSide: 'buy',
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: const <num>[
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
            120,
            119,
            118,
            119,
          ],
          higherLows: const <num>[
            105,
            104,
            100,
            103,
            106,
            105,
            104,
            102,
            105,
            104,
            103,
            104,
          ],
          higherCloses: const <num>[
            112,
            110,
            104,
            108,
            114,
            111,
            109,
            106,
            113,
            108,
            107,
            109,
          ],
          higherCloseTimesUtc: List<String>.generate(
            12,
            (index) =>
                DateTime.utc(
                  2026,
                  8,
                  1,
                ).add(Duration(hours: 4 * index)).toIso8601String(),
          ),
          dailyHighs: const <num>[],
          dailyLows: const <num>[],
          dailyCloses: const <num>[],
          weeklyHighs: const <num>[],
          weeklyLows: const <num>[],
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );

      expect(result.externalBuyRetest, 100);
      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorExecutable, isFalse);
      expect(result.anchorLifecycle, 'unavailable');
      expect(result.liquidityEventId, isNull);
    });

    test('keeps timestamped untouched high as target-only liquidity', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          symbol: 'BTC-USDT',
          midPrice: 130,
          fallbackSide: 'sell',
          requiredSide: 'sell',
          microHighs: base.microLows.map<num>((price) => 240 - price).toList(),
          microLows: base.microHighs.map<num>((price) => 240 - price).toList(),
          macroHighs: base.macroLows.map<num>((price) => 240 - price).toList(),
          macroLows: base.macroHighs.map<num>((price) => 240 - price).toList(),
          higherHighs:
              [
                105,
                104,
                100,
                103,
                106,
                105,
                104,
                102,
                105,
                104,
                103,
                104,
              ].map<num>((price) => 240 - price).toList(),
          higherLows:
              [
                120,
                119,
                118,
                119,
                120,
                119,
                118,
                119,
                120,
                119,
                118,
                119,
              ].map<num>((price) => 240 - price).toList(),
          higherCloses:
              [
                112,
                110,
                104,
                108,
                114,
                111,
                109,
                106,
                113,
                108,
                107,
                109,
              ].map<num>((price) => 240 - price).toList(),
          higherCloseTimesUtc: List<String>.generate(
            12,
            (index) =>
                DateTime.utc(
                  2026,
                  8,
                  1,
                ).add(Duration(hours: 4 * index)).toIso8601String(),
          ),
          dailyHighs: const [],
          dailyLows: const [],
          dailyCloses: const [],
          weeklyHighs: const [],
          weeklyLows: const [],
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );
      expect(result.externalSellRetest, 140);
      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorLifecycle, 'unavailable');
      expect(result.anchorExecutable, isFalse);
      expect(result.liquidityEventId, isNull);
    });

    test('internal diagnostic low cannot authorize pending entry', () {
      final base = _inputForSweepUp();
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: base.midPrice,
          fallbackSide: base.fallbackSide,
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          microCloses: List<num>.filled(base.microHighs.length, 110),
          macroHighs: base.macroHighs,
          macroLows: base.macroLows,
          higherHighs: const <num>[],
          higherLows: const <num>[],
          higherCloses: const <num>[],
          dailyHighs: const <num>[],
          dailyLows: const <num>[],
          dailyCloses: const <num>[],
          weeklyHighs: const <num>[],
          weeklyLows: const <num>[],
          recentMicroBars: base.recentMicroBars,
          zoneNearBps: base.zoneNearBps,
          zoneFarBps: base.zoneFarBps,
        ),
      );

      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorExecutable, isFalse);
      expect(result.anchorLifecycle, 'unavailable');
    });

    test('window extrema without cluster evidence cannot authorize entry', () {
      for (final side in ['buy', 'sell']) {
        final result = service.decide(
          input: _microReclaimInput(side: side, clusters: const []),
        );
        expect(result.anchorExecutable, isFalse);
        expect(result.liquidityEventId, isNull);
      }
    });

    test('rejects invalid and ambiguous cluster evidence', () {
      for (final cluster in [
        _cluster(side: 'buyside'),
        _cluster(pivotCount: 2),
        _cluster(breached: false),
        _cluster(breach: 19),
        _cluster(breach: 30),
        _cluster(bottom: 'NaN'),
        _cluster(bottom: '101'),
      ]) {
        expect(
          service
              .decide(
                input: _microReclaimInput(side: 'buy', clusters: [cluster]),
              )
              .anchorExecutable,
          isFalse,
        );
      }
      expect(
        service
            .decide(
              input: _microReclaimInput(
                side: 'buy',
                clusters: [_cluster(), _cluster()],
              ),
            )
            .anchorExecutable,
        isFalse,
      );
    });

    test('consumed cluster cannot start another event after reclaim', () {
      expect(
        service
            .decide(input: _microReclaimInput(side: 'buy', reswept: true))
            .anchorExecutable,
        isFalse,
      );
    });

    test('4h sweep requires a later 15m confirmation inside its bounds', () {
      final result = service.decide(input: _htfReclaimInput(side: 'buy'));

      expect(result.anchorSource, '4h_sweep_reclaim_15m');
      expect(result.anchorExecutable, isTrue);
      expect(result.anchorLifecycle, 'reclaimed');
      expect(result.zoneLow, 88.5);
      expect(result.zoneHigh, 89.8);
      expect(result.parentZone!['low_decimal'], '88.00000000');
      expect(result.parentZone!['high_decimal'], '90.00000000');
    });

    test('active 4h sellside zone can stage a buy before a sweep', () {
      final input = _htfReclaimInput(
        side: 'buy',
        clusters: [_cluster(breached: false)],
        restingZoneEntry: true,
      );
      final first = service.decide(input: input);
      final again = service.decide(input: input);

      expect(first.anchorSource, '4h_active_liquidity_zone');
      expect(first.anchorExecutable, isTrue);
      expect(first.zoneLow, 90);
      expect(first.zoneHigh, 92);
      expect(
        first.parentZone?['strategy_version'],
        bingxLiquidityStrategyVersion,
      );
      expect(first.liquidityEventId, again.liquidityEventId);
    });
    test(
      'hourly zone uses one owner without daily or weekly target levels',
      () {
        final input = _htfReclaimInput(
          side: 'buy',
          clusters: [
            _cluster(breached: false),
            _cluster(
              side: 'buyside',
              breached: false,
              bottom: '98',
              top: '100',
            ),
          ],
          restingZoneEntry: true,
          strategyVersion: bingxHourlyLiquidityStrategyVersion,
        );
        final result = service.decide(input: input);
        expect(result.anchorExecutable, isTrue);
        expect(result.anchorSource, '1h_active_liquidity_zone');
        expect(result.parentZone?['timeframe'], '1h');
        expect(
          result.parentZone?['strategy_version'],
          bingxHourlyLiquidityStrategyVersion,
        );
        expect(result.externalSellRetestSource, '1h_active_opposite_liquidity');
      },
    );

    test('breached cluster cannot stage a new resting order', () {
      final result = service.decide(
        input: _htfReclaimInput(
          side: 'buy',
          clusters: [_cluster()],
          restingZoneEntry: true,
        ),
      );
      expect(result.anchorExecutable, isFalse);
    });

    test('15m crossing after the latest 4h close consumes resting entry', () {
      final result = service.decide(
        input: _htfReclaimInput(
          side: 'buy',
          clusters: [_cluster(breached: false)],
          restingZoneEntry: true,
          crossedAfterParent: true,
        ),
      );
      expect(result.anchorExecutable, isFalse);
    });

    test('gapped 15m coverage cannot stage a resting order', () {
      final result = service.decide(
        input: _htfReclaimInput(
          side: 'buy',
          clusters: [_cluster(breached: false)],
          restingZoneEntry: true,
          gapped: true,
        ),
      );
      expect(result.anchorExecutable, isFalse);
    });

    test(
      'parent binding rejects missing, conflicting and noncausal evidence',
      () {
        for (final side in ['buy', 'sell']) {
          expect(
            service
                .decide(input: _htfReclaimInput(side: side))
                .anchorExecutable,
            isTrue,
          );
          for (final input in [
            _htfReclaimInput(side: side, missingParentTimes: true),
            _htfReclaimInput(side: side, conflictingParent: true),
            _htfReclaimInput(side: side, microOutside: true),
            _htfReclaimInput(side: side, microBeforeParent: true),
            _htfReclaimInput(side: side, gapped: true),
            _htfReclaimInput(side: side, reswept: true),
            _htfReclaimInput(side: side, clusters: []),
          ]) {
            expect(service.decide(input: input).anchorExecutable, isFalse);
          }
        }
      },
    );

    test('fresh bullish void cannot authorize a standalone entry', () {
      final first = service.decide(input: _liquidityVoidInput(side: 'buy'));
      final second = service.decide(input: _liquidityVoidInput(side: 'buy'));

      expect(first.anchorExecutable, isFalse);
      expect(first.liquidityEventId, isNull);
      expect(second.liquidityEventId, first.liquidityEventId);
      expect(second.zoneLow, first.zoneLow);
      expect(second.zoneHigh, first.zoneHigh);
    });

    test('fresh bearish void cannot authorize a standalone entry', () {
      final result = service.decide(input: _liquidityVoidInput(side: 'sell'));

      expect(result.anchorExecutable, isFalse);
      expect(result.liquidityEventId, isNull);
    });

    test('does not reuse a liquidity void after price trades into it', () {
      final result = service.decide(
        input: _liquidityVoidInput(side: 'buy', touched: true),
      );

      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorExecutable, isFalse);
      expect(result.liquidityEventId, isNull);
    });

    test(
      'successive closed snapshots wait for reclaim and replay the same event',
      () {
        final untouched = service.decide(
          input: _htfReclaimInput(
            side: 'buy',
            visibleBars: 20,
            delayedReclaim: true,
            clusters: [_cluster(breached: false)],
          ),
        );
        final swept = service.decide(
          input: _htfReclaimInput(
            side: 'buy',
            visibleBars: 21,
            delayedReclaim: true,
          ),
        );
        final confirmedInput = _htfReclaimInput(
          side: 'buy',
          visibleBars: 22,
          delayedReclaim: true,
        );
        final confirmed = service.decide(input: confirmedInput);
        final recovered = const BingxFuturesZoneDecisionService().decide(
          input: confirmedInput,
        );
        expect(untouched.anchorExecutable, isFalse);
        expect(swept.anchorExecutable, isFalse);
        expect(confirmed.anchorExecutable, isTrue);
        expect(confirmed.anchorLifecycle, 'reclaimed');
        expect(recovered.liquidityEventId, confirmed.liquidityEventId);
        expect(recovered.zoneLow, confirmed.zoneLow);
        expect(recovered.zoneHigh, confirmed.zoneHigh);
      },
    );

    test('closed liquidity event zone ignores live quote drift', () {
      final first = service.decide(
        input: _htfReclaimInput(side: 'sell', midPrice: 96),
      );
      final second = service.decide(
        input: _htfReclaimInput(side: 'sell', midPrice: 96.4),
      );

      expect(first.anchorSource, '4h_sweep_reclaim_15m');
      expect(second.anchorSource, first.anchorSource);
      expect(first.liquidityEventId, isNotNull);
      expect(second.liquidityEventId, first.liquidityEventId);
      expect(second.latestClosedMicroBarAtUtc, first.latestClosedMicroBarAtUtc);
      expect(second.zoneLow, first.zoneLow);
      expect(second.zoneHigh, first.zoneHigh);
    });

    test('rejects reclaim candle whose body is too small relative to ATR', () {
      final result = service.decide(
        input: _htfReclaimInput(side: 'sell', weakBody: true),
      );

      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorExecutable, isFalse);
    });

    test('expires an unreclaimed sweep after the bounded bar window', () {
      final result = service.decide(
        input: _htfReclaimInput(side: 'buy', expired: true),
      );

      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorExecutable, isFalse);
    });

    test('later 4h sweep invalidates the original parent', () {
      final result = service.decide(
        input: _htfReclaimInput(side: 'sell', reswept: true),
      );

      expect(result.anchorSource, 'internal_diagnostic');
      expect(result.anchorExecutable, isFalse);
    });
  });
}

BingxFuturesZoneDecisionInput _htfReclaimInput({
  required String side,
  String strategyVersion = bingxLiquidityStrategyVersion,
  bool restingZoneEntry = false,
  bool crossedAfterParent = false,
  num midPrice = 96,
  bool weakBody = false,
  bool expired = false,
  bool reswept = false,
  bool delayedReclaim = false,
  int visibleBars = 30,
  List<BingxDetectedLiquidityLevel>? clusters,
  bool missingParentTimes = false,
  bool microOutside = false,
  bool microBeforeParent = false,
  bool gapped = false,
  bool conflictingParent = false,
}) {
  final hourly = strategyVersion == bingxHourlyLiquidityStrategyVersion;
  final buy = side == 'buy';
  final highs = List<num>.filled(visibleBars, 99);
  final lows = List<num>.filled(visibleBars, 91);
  final opens = List<num>.filled(visibleBars, 95);
  final closes = List<num>.filled(visibleBars, 95);
  if (visibleBars > 20) {
    highs[20] = buy ? 96 : 102;
    lows[20] = buy ? 88 : 94;
    opens[20] = buy ? 89 : 101;
    closes[20] = expired || delayedReclaim ? opens[20] : (buy ? 91 : 99);
  }
  if (expired) {
    for (var i = 21; i < visibleBars; i++) {
      highs[i] = buy ? 89.9 : 102;
      lows[i] = buy ? 88 : 100.1;
      opens[i] = closes[i] = buy ? 89 : 101;
    }
  }
  if (delayedReclaim && visibleBars > 21) {
    opens[21] = buy ? 89 : 101;
    closes[21] = buy ? 91 : 99;
    lows[21] = buy ? 89 : 94;
    highs[21] = buy ? 96 : 101;
  }
  if (reswept && visibleBars > 25) {
    if (buy) {
      lows[25] = 87;
    } else {
      highs[25] = 103;
    }
  }
  if (conflictingParent) {
    highs[20] = 102;
    lows[20] = 88;
    closes[20] = 95;
  }
  final start = DateTime.utc(2026, 9, 1);
  final times = List.generate(
    visibleBars,
    (i) => start.add(Duration(hours: (hourly ? 1 : 4) * i)).toIso8601String(),
  );
  final parentIndex = delayedReclaim ? 21 : 20;
  final known = start.add(Duration(hours: (hourly ? 1 : 4) * parentIndex));
  final microStart = known.subtract(Duration(minutes: hourly ? 60 : 300));
  final microCount = ((visibleBars - 1 - parentIndex) * (hourly ? 12 : 16) + 25)
      .clamp(25, 600);
  final microHighs = List<num>.filled(microCount, buy ? 89.8 : 101.5);
  final microLows = List<num>.filled(microCount, buy ? 88.5 : 100.2);
  if (restingZoneEntry && buy) {
    if (hourly) {
      final lastParentClose = DateTime.parse(times.last);
      for (var index = 0; index < microCount; index++) {
        if (microStart
            .add(Duration(minutes: 5 * index))
            .isAfter(lastParentClose)) {
          microLows[index] = 93;
        }
      }
    }
    microLows[microCount - 1] = crossedAfterParent ? 89 : 93;
    for (var index = microCount - 5; index < microCount - 1; index++) {
      microLows[index] = 93;
    }
  }
  final microOpens = List<num>.filled(microCount, buy ? 89 : 101);
  final microCloses = List<num>.from(microOpens);
  final confirmation = microBeforeParent ? 19 : 21;
  microOpens[confirmation] = buy ? 88.6 : 101.3;
  microCloses[confirmation] =
      weakBody ? microOpens[confirmation] : (buy ? 89.6 : 100.3);
  if (microOutside) microHighs[confirmation] = buy ? 90.1 : 102.1;
  final microTimes = List.generate(
    microCount,
    (i) =>
        microStart
            .add(Duration(minutes: (hourly ? 5 : 15) * i))
            .toIso8601String(),
  );
  if (gapped) microTimes[22] = microTimes[21];
  return BingxFuturesZoneDecisionInput(
    symbol: 'DOGE-USDT',
    midPrice: midPrice,
    fallbackSide: side,
    requiredSide: side,
    restingZoneEntry: restingZoneEntry,
    strategyVersion: strategyVersion,
    detectedLiquidityLevels:
        clusters ??
        [
          buy
              ? _cluster()
              : _cluster(side: 'buyside', bottom: '98', top: '100'),
          if (conflictingParent)
            buy
                ? _cluster(side: 'buyside', bottom: '98', top: '100')
                : _cluster(),
        ],
    microHighs: microHighs,
    microLows: microLows,
    microOpens: microOpens,
    microCloses: microCloses,
    microCloseTimesUtc: microTimes,
    macroHighs: List<num>.filled(40, 105),
    macroLows: List<num>.filled(40, 85),
    higherHighs: highs,
    higherLows: lows,
    higherOpens: opens,
    higherCloses: closes,
    higherCloseTimesUtc: missingParentTimes ? [] : times,
    dailyHighs: const [],
    dailyLows: const [],
    dailyCloses: const [],
    weeklyHighs: const [],
    weeklyLows: const [],
    recentMicroBars: 10,
    zoneNearBps: 15,
    zoneFarBps: 35,
  );
}

BingxDetectedLiquidityLevel _cluster({
  String side = 'sellside',
  int pivotCount = 3,
  bool breached = true,
  int breach = 20,
  String bottom = '90',
  String top = '92',
}) => BingxDetectedLiquidityLevel(
  side: side,
  levelClass: 'internal',
  centerPriceDecimal: '91',
  zoneTopDecimal: top,
  zoneBottomDecimal: bottom,
  pivotCount: pivotCount,
  breached: breached,
  anchorIndex: 7,
  breachedIndex: breach,
);

BingxFuturesZoneDecisionInput _microReclaimInput({
  required String side,
  num midPrice = 96,
  bool weakBody = false,
  bool expired = false,
  bool excessiveRetests = false,
  bool reswept = false,
  List<BingxDetectedLiquidityLevel>? clusters,
  int visibleBars = 30,
  bool delayedReclaim = false,
}) {
  final highs = List<num>.filled(30, 96);
  final lows = List<num>.filled(30, 94);
  final opens = List<num>.filled(30, 95);
  final closes = List<num>.filled(30, 95);
  highs[0] = 100;
  lows[1] = 90;

  if (side == 'buy') {
    lows[20] = 88;
    opens[20] = weakBody ? 90.8 : 89;
    closes[20] = expired ? 89 : 91;
    if (weakBody) closes[20] = 91;
  } else {
    highs[20] = 102;
    opens[20] = weakBody ? 99.2 : 101;
    closes[20] = expired || excessiveRetests ? 101 : 99;
    if (weakBody) closes[20] = 99;
  }

  if (expired) {
    for (var index = 21; index < 30; index += 1) {
      opens[index] = side == 'buy' ? 89 : 101;
      closes[index] = opens[index];
      highs[index] = 99;
      lows[index] = 91;
    }
  }

  if (excessiveRetests) {
    for (var index = 21; index <= 25; index += 1) {
      final below = index.isOdd;
      highs[index] = index < 25 ? 101 : 99;
      lows[index] = 98;
      opens[index] = below ? 99.2 : 100.8;
      closes[index] = below ? 99 : 101;
    }
    for (var index = 26; index < 30; index += 1) {
      highs[index] = 99;
      lows[index] = 97;
      opens[index] = 98;
      closes[index] = 98;
    }
  }

  if (reswept) lows[25] = 87;
  if (delayedReclaim) {
    opens[20] = 91;
    closes[20] = 89;
    lows[21] = 89;
    opens[21] = 89;
    closes[21] = 93;
  }
  return BingxFuturesZoneDecisionInput(
    symbol: 'DOGE-USDT',
    detectedLiquidityLevels:
        clusters ??
        [
          side == 'buy'
              ? _cluster()
              : _cluster(side: 'buyside', bottom: '98', top: '100'),
        ],
    midPrice: midPrice,
    fallbackSide: side,
    requiredSide: side,
    microHighs: highs.take(visibleBars).toList(),
    microLows: lows.take(visibleBars).toList(),
    microOpens: opens.take(visibleBars).toList(),
    microCloses: closes.take(visibleBars).toList(),
    microCloseTimesUtc: List<String>.generate(
      visibleBars,
      (index) =>
          DateTime.utc(
            2026,
            8,
            21,
            10,
          ).add(Duration(minutes: index * 5)).toIso8601String(),
    ),
    macroHighs: List<num>.filled(40, 105),
    macroLows: List<num>.filled(40, 85),
    higherHighs: const <num>[],
    higherLows: const <num>[],
    higherCloses: const <num>[],
    dailyHighs: const <num>[],
    dailyLows: const <num>[],
    dailyCloses: const <num>[],
    weeklyHighs: const <num>[],
    weeklyLows: const <num>[],
    recentMicroBars: 10,
    zoneNearBps: 15,
    zoneFarBps: 35,
  );
}

BingxFuturesZoneDecisionInput _liquidityVoidInput({
  required String side,
  bool touched = false,
}) {
  final isBuy = side == 'buy';
  final highs = List<num>.filled(30, isBuy ? 110 : 92);
  final lows = List<num>.filled(30, isBuy ? 106 : 88);
  final opens = List<num>.filled(30, isBuy ? 107 : 91);
  final closes = List<num>.filled(30, isBuy ? 108 : 90);

  if (isBuy) {
    highs[20] = 100;
    lows[20] = 98;
    opens[20] = 99;
    closes[20] = 99.5;
    highs[22] = 106;
    lows[22] = 104;
    opens[22] = 101;
    closes[22] = 105;
    if (touched) lows[27] = 103;
  } else {
    highs[20] = 102;
    lows[20] = 100;
    opens[20] = 101;
    closes[20] = 100.5;
    highs[22] = 96;
    lows[22] = 94;
    opens[22] = 99;
    closes[22] = 95;
    if (touched) highs[27] = 97;
  }

  return BingxFuturesZoneDecisionInput(
    symbol: 'DOGE-USDT',
    midPrice: isBuy ? 108 : 90,
    fallbackSide: side,
    requiredSide: side,
    microHighs: highs,
    microLows: lows,
    microOpens: opens,
    microCloses: closes,
    microCloseTimesUtc: List<String>.generate(
      30,
      (index) =>
          DateTime.utc(
            2026,
            9,
            18,
          ).add(Duration(minutes: index * 5)).toIso8601String(),
    ),
    detectedLiquidityLevels: const <BingxDetectedLiquidityLevel>[],
    macroHighs: List<num>.filled(40, 115),
    macroLows: List<num>.filled(40, 85),
    higherHighs: const <num>[],
    higherLows: const <num>[],
    higherCloses: const <num>[],
    dailyHighs: const <num>[],
    dailyLows: const <num>[],
    dailyCloses: const <num>[],
    weeklyHighs: const <num>[],
    weeklyLows: const <num>[],
    weeklyCloses: const <num>[],
    recentMicroBars: 10,
    zoneNearBps: 15,
    zoneFarBps: 35,
  );
}

BingxFuturesZoneDecisionInput _inputForSweepUp() {
  final microHighs = <num>[
    101,
    102,
    103,
    104,
    105,
    106,
    106,
    107,
    108,
    109,
    110,
    110,
    109,
    110,
    111,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    118,
    119,
    120,
  ];
  final microLows = <num>[
    95,
    95,
    96,
    96,
    97,
    97,
    97,
    98,
    98,
    98,
    99,
    99,
    99,
    99,
    100,
    100,
    100,
    101,
    101,
    101,
    102,
    102,
    102,
    103,
    103,
  ];
  return BingxFuturesZoneDecisionInput(
    midPrice: 110.0,
    fallbackSide: 'buy',
    microHighs: microHighs,
    microLows: microLows,
    microCloses: List<num>.generate(25, (i) => 98 + i * 0.5),
    macroHighs: List<num>.generate(96, (i) => 104 + (i % 18)),
    macroLows: List<num>.generate(96, (i) => 88 + (i % 12)),
    higherHighs: List<num>.generate(96, (i) => 106 + (i % 20)),
    higherLows: List<num>.generate(96, (i) => 90 + (i % 14)),
    higherCloses: List<num>.generate(96, (i) => 95 + i * 0.15),
    dailyHighs: List<num>.generate(90, (i) => 108 + (i % 22)),
    dailyLows: List<num>.generate(90, (i) => 84 + (i % 16)),
    dailyCloses: List<num>.generate(90, (i) => 96 + i * 0.18),
    weeklyHighs: List<num>.generate(52, (i) => 112 + (i % 14)),
    weeklyLows: List<num>.generate(52, (i) => 82 + (i % 10)),
    weeklyCloses: List<num>.generate(52, (i) => 96 + i * 0.2),
    recentMicroBars: 8,
    zoneNearBps: 15.0,
    zoneFarBps: 35.0,
  );
}

BingxFuturesZoneDecisionInput _inputForSweepDown() {
  final microHighs = <num>[
    112,
    111,
    111,
    110,
    110,
    109,
    108,
    108,
    107,
    107,
    106,
    106,
    105,
    105,
    104,
    104,
    103,
    103,
    102,
    102,
    102,
    101,
    101,
    100,
    100,
  ];
  final microLows = <num>[
    98,
    97,
    97,
    96,
    96,
    95,
    95,
    94,
    94,
    93,
    93,
    92,
    92,
    91,
    91,
    90,
    90,
    89,
    89,
    88,
    87,
    86,
    85,
    84,
    83,
  ];
  return BingxFuturesZoneDecisionInput(
    midPrice: 95.0,
    fallbackSide: 'sell',
    microHighs: microHighs,
    microLows: microLows,
    microCloses: List<num>.generate(26, (i) => 108 - i * 0.5),
    macroHighs: List<num>.generate(96, (i) => 110 - (i % 17)),
    macroLows: List<num>.generate(96, (i) => 82 - (i % 8) * 0.2),
    higherHighs: List<num>.generate(96, (i) => 108 - (i % 12) * 0.3),
    higherLows: List<num>.generate(96, (i) => 80 - (i % 8) * 0.2),
    higherCloses: List<num>.generate(96, (i) => 110 - i * 0.16),
    dailyHighs: List<num>.generate(90, (i) => 109 - (i % 13) * 0.25),
    dailyLows: List<num>.generate(90, (i) => 79 - (i % 7) * 0.2),
    dailyCloses: List<num>.generate(90, (i) => 108 - i * 0.17),
    weeklyHighs: List<num>.generate(52, (i) => 112 - (i % 9) * 0.5),
    weeklyLows: List<num>.generate(52, (i) => 76 - (i % 6) * 0.4),
    weeklyCloses: List<num>.generate(52, (i) => 108 - i * 0.2),
    recentMicroBars: 8,
    zoneNearBps: 15.0,
    zoneFarBps: 35.0,
  );
}
