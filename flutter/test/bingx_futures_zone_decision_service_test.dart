import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_zone_decision_service.dart';

void main() {
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
      final result = service.decide(
        input: _inputForSweepUp(),
      );

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
            117
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
            99
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
            108
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
            119
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
            103
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
            109
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

    test('uses an untouched confirmed swing pivot as fresh liquidity', () {
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
            119
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
            104
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
            109
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

      expect(result.externalBuyRetest, 100);
      expect(result.anchorSource, '4h_fresh_low');
      expect(result.anchorExecutable, isTrue);
      expect(result.anchorLifecycle, 'fresh');
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

    test('current sweep reclaim is an executable new event', () {
      final base = _inputForSweepDown();
      final closes = List<num>.filled(base.microHighs.length, 88)
        ..[base.microHighs.length - 2] = 84
        ..[base.microHighs.length - 1] = 96;
      final result = service.decide(
        input: BingxFuturesZoneDecisionInput(
          midPrice: base.midPrice,
          fallbackSide: base.fallbackSide,
          requiredSide: 'buy',
          microHighs: base.microHighs,
          microLows: base.microLows,
          microCloses: closes,
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

      expect(result.anchorSource, 'micro_sweep_reclaim');
      expect(result.anchorExecutable, isTrue);
      expect(result.anchorLifecycle, 'reclaimed');
    });
  });
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
