import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_signal_rank_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/screens/trading_drone_screen.dart';

void main() {
  test('restores endpoint mode from an active mandate only', () {
    final now = DateTime.utc(2026, 8, 22, 10);
    final live = BingxFuturesTradingMandate.issue(
      capsuleRootHex: 'a' * 64,
      accountBindingHashHex: 'b' * 64,
      symbol: 'BTC-USDT',
      testOrder: false,
      issuedAtUtc: now.subtract(const Duration(hours: 1)),
      expiresAtUtc: now.add(const Duration(hours: 1)),
      maxOrderNotionalQuoteDecimal: '10',
      maxRiskPerTradePercent: 2,
      maxDailyLossPercent: 5,
      maxConcurrentPositions: 1,
      cooldownAfterLossStreak: 2,
      cooldownMinutes: 60,
      maxEffects: 1,
    );

    expect(
      tradingUsesTestEndpointAfterRestore(mandate: live, nowUtc: now),
      isFalse,
    );
    expect(
      tradingUsesTestEndpointAfterRestore(
        mandate: live,
        nowUtc: now.add(const Duration(hours: 2)),
      ),
      isTrue,
    );
    expect(
      tradingUsesTestEndpointAfterRestore(mandate: null, nowUtc: now),
      isTrue,
    );
  });

  final issuedAt = DateTime.utc(2026, 8, 20, 10);
  final mandate = BingxFuturesTradingMandate.issue(
    capsuleRootHex: List<String>.filled(32, '11').join(),
    accountBindingHashHex: List<String>.filled(32, '22').join(),
    symbol: 'XRP-USDT',
    testOrder: true,
    issuedAtUtc: issuedAt,
    expiresAtUtc: issuedAt.add(const Duration(hours: 24)),
    maxOrderNotionalQuoteDecimal: '100',
    maxRiskPerTradePercent: 2,
    maxDailyLossPercent: 5,
    maxConcurrentPositions: 3,
    cooldownAfterLossStreak: 2,
    cooldownMinutes: 60,
    maxEffects: 32,
  );

  test('signal scan action remains refresh after results exist', () {
    expect(tradingSignalScanActionLabel(scanning: false), 'Refresh Scan');
    expect(tradingSignalScanActionLabel(scanning: true), 'Scanning');
  });

  test('prepared intent is not labelled as executed effect', () {
    expect(tradingIntentStatusLabel(null), 'idle');
    expect(tradingIntentStatusLabel(PluginHostApiStatus.executed), 'prepared');
  });

  test('exact export selection must match active mandate symbol and mode', () {
    final now = issuedAt.add(const Duration(minutes: 1));

    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'xrp-usdt',
        testOrder: true,
        nowUtc: now,
      ),
      isTrue,
    );
    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'ADA-USDT',
        testOrder: true,
        nowUtc: now,
      ),
      isFalse,
    );
    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        testOrder: false,
        nowUtc: now,
      ),
      isFalse,
    );
  });

  test('expired mandate is fail-closed and receives explicit feedback', () {
    final expiredAt = issuedAt.add(const Duration(hours: 25));

    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        testOrder: true,
        nowUtc: expiredAt,
      ),
      isFalse,
    );
    expect(
      tradingMandateSelectionNotice(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        testOrder: true,
        nowUtc: expiredAt,
      ),
      'Trading mandate expired. Re-authorize before exact export.',
    );
  });

  test('scan snapshot is explicitly observational and timestamped', () {
    expect(
      tradingSignalSnapshotLabel(DateTime.utc(2026, 8, 20, 10, 39, 15)),
      'Snapshot 2026-08-20T10:39:15.000Z. READY is observational; '
      'Run Intent revalidates current market.',
    );
  });

  test('fresh ready rank overrides stale UI side for canonical cycle', () {
    const entries = <BingxFuturesSignalRankEntry>[
      BingxFuturesSignalRankEntry(
        symbol: 'BNB-USDT',
        bucket: 'ready',
        score: 10555,
        decision: 'short',
        side: 'sell',
        zoneLowDecimal: '745.41',
        zoneHighDecimal: '746.76',
        trendGateCode: 'ok',
        canPrepareIntent: true,
        liveDecisionHashHex: 'ranked-hash',
        failedReasonCodes: <String>['long_trade_imbalance'],
      ),
    ];

    expect(
      tradingPreferredSideForCycle(
        symbol: 'bnb-usdt',
        currentSide: 'buy',
        rankedEntries: entries,
      ),
      'sell',
    );
  });

  test('blocked cycle cannot replace the selected execution side', () {
    expect(
      tradingSideAfterCycle(
        currentSide: 'sell',
        cyclePrepared: false,
        decisionSide: 'buy',
      ),
      'sell',
    );
    expect(
      tradingSideAfterCycle(
        currentSide: 'sell',
        cyclePrepared: true,
        decisionSide: 'buy',
      ),
      'buy',
    );
  });

  test('blocked cycle cannot replace the selected execution zone side', () {
    expect(
      tradingZoneSideAfterCycle(
        currentZoneSide: 'sellside',
        cyclePrepared: false,
        decisionZoneSide: 'buyside',
      ),
      'sellside',
    );
    expect(
      tradingZoneSideAfterCycle(
        currentZoneSide: 'sellside',
        cyclePrepared: true,
        decisionZoneSide: 'buyside',
      ),
      'buyside',
    );
  });

  test('only a prepared executable decision projects a pending zone', () {
    expect(
      tradingCycleProjectsExecutableZone(
        cyclePrepared: true,
        decisionCanPrepareIntent: true,
      ),
      isTrue,
    );
    expect(
      tradingCycleProjectsExecutableZone(
        cyclePrepared: false,
        decisionCanPrepareIntent: true,
      ),
      isFalse,
    );
    expect(
      tradingCycleProjectsExecutableZone(
        cyclePrepared: false,
        decisionCanPrepareIntent: false,
      ),
      isFalse,
    );
  });

  test('ranked order side maps to the matching liquidity zone side', () {
    expect(tradingZoneSideForOrderSide('buy'), 'buyside');
    expect(tradingZoneSideForOrderSide('sell'), 'sellside');
  });

  test('managed order revalidation always locks its existing side', () {
    expect(tradingManagedOrderStructuralSide('SELL'), 'sell');
    expect(tradingManagedOrderStructuralSide('BUY'), 'buy');
    expect(tradingManagedOrderStructuralSide('unknown'), isNull);
  });

  test(
    'restart resumes an unresolved live effect without a known order id',
    () {
      final eventId = List<String>.filled(64, 'a').join();
      final state = BingxFuturesOrderTrackingState(
        trackedSymbol: null,
        trackedOrderId: null,
        managedOrderIds: const <String>[],
        managedOrderSymbols: const <String, String>{},
        liquidityEventEffectClaims: <String, BingxLiquidityEventEffectClaim>{
          'live|$eventId': BingxLiquidityEventEffectClaim(
            liquidityEventId: eventId,
            clientOrderId: 'hivra-live-recovery',
            symbol: 'SOL-USDT',
            side: 'sell',
            testOrder: false,
            status: BingxLiquidityEventEffectClaimStatus.reserved,
            orderId: null,
            recordedAtUtc: '2026-08-22T00:00:00.000Z',
          ),
        },
        stopLossPercent: null,
        takeProfitRiskReward: null,
      );

      expect(tradingReconciliationResumeSymbol(state), 'SOL-USDT');
    },
  );

  test('terminal and test-only effects do not keep provider polling alive', () {
    BingxLiquidityEventEffectClaim claim({
      required String eventId,
      required bool testOrder,
      required BingxManagedOrderLifecycleStatus lifecycle,
    }) => BingxLiquidityEventEffectClaim(
      liquidityEventId: eventId,
      clientOrderId: 'hivra-$eventId',
      symbol: 'BNB-USDT',
      side: 'buy',
      testOrder: testOrder,
      status: BingxLiquidityEventEffectClaimStatus.confirmed,
      orderId: 'order-$eventId',
      lifecycleStatus: lifecycle,
      recordedAtUtc: '2026-08-22T00:00:00.000Z',
    );

    final testEvent = List<String>.filled(64, 'b').join();
    final terminalEvent = List<String>.filled(64, 'c').join();
    final state = BingxFuturesOrderTrackingState(
      trackedSymbol: null,
      trackedOrderId: null,
      managedOrderIds: const <String>[],
      managedOrderSymbols: const <String, String>{},
      liquidityEventEffectClaims: <String, BingxLiquidityEventEffectClaim>{
        'test|$testEvent': claim(
          eventId: testEvent,
          testOrder: true,
          lifecycle: BingxManagedOrderLifecycleStatus.unresolved,
        ),
        'live|$terminalEvent': claim(
          eventId: terminalEvent,
          testOrder: false,
          lifecycle: BingxManagedOrderLifecycleStatus.cancelled,
        ),
      },
      stopLossPercent: null,
      takeProfitRiskReward: null,
    );

    expect(tradingReconciliationResumeSymbol(state), isNull);
  });
}
