import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hivra_app/models/bingx_futures_exchange_execution_models.dart';
import 'package:hivra_app/models/bingx_futures_signal_rank_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/screens/trading_drone_screen.dart';

void main() {
  test('reconciliation feedback is scoped and distinguishes tests from effects', () {
    final state = BingxFuturesOrderTrackingState(
      trackedSymbol: null,
      trackedOrderId: null,
      managedOrderIds: const [],
      managedOrderSymbols: const {},
      stopLossPercent: null,
      takeProfitRiskReward: null,
      liquidityEventEffectClaims: {
        for (final testOrder in [false, true])
          '$testOrder': BingxLiquidityEventEffectClaim(
            liquidityEventId: '$testOrder',
            clientOrderId: testOrder ? 'test-client' : 'live-client',
            orderId: null,
            symbol: 'DOGE-USDT',
            side: 'buy',
            testOrder: testOrder,
            status: BingxLiquidityEventEffectClaimStatus.confirmed,
            lifecycleDiagnostic: 'provider_status_unknown:FAILED',
            recordedAtUtc: '2026-09-05T00:00:00Z',
          ),
      },
    );
    final result = BingxFuturesManagedOrderReconciliationResult(
      status: BingxFuturesManagedOrderReconciliationStatus.reconciled,
      capsuleRootHex: 'capsule-a',
      state: state,
      activeCount: 0,
      terminalCount: 7,
      unresolvedCount: 1,
      diagnostics: const [],
    );
    final notice = tradingReconciliationNotice(result, 'capsule-a')!;
    expect(notice, contains('Completed 7 · Needs review 1'));
    expect(notice, contains('not necessarily filled'));
    expect(notice, contains('DOGE-USDT · live-client'));
    expect(notice, contains('BingX reports FAILED; final outcome unverified'));
    expect(notice, contains('Do not recreate'));
    expect(notice, contains('Test records are retained separately'));
    expect(notice, isNot(contains('test-client')));
    expect(tradingReconciliationNotice(result, 'capsule-b'), isNull);
    expect(tradingReconciliationNotice(result, null), isNull);
    expect(tradingReconciliationNotice(null, 'capsule-a'), isNull);
  });

  test('paused process does not imply disabled startup', () {
    for (final details in ['', ' session_state=active cycles=0 effects=0 '
      'last_scheduled_check=none next_check=2026-09-05T02:00:00Z last_outcome=none']) {
      final enabled = tradingRemoteRunnerStatusLabel('active=inactive enabled=enabled$details');
      expect(enabled, contains('Runner paused'));
      expect(enabled, contains('WARNING: autostart enabled'));
      expect(enabled, isNot(contains('Autostart: not enabled')));
      for (final state in ['linked', 'disabled']) {
        expect(tradingRemoteRunnerStatusLabel('active=inactive enabled=$state$details'),
          contains('Autostart: not enabled'));
      }
      for (final value in ['', ' enabled=unexpected']) {
        expect(tradingRemoteRunnerStatusLabel('active=inactive$value$details'),
          contains('pause persistence is not verified'));
      }
    }
    expect(tradingRemoteRunnerStatusLabel('active=inactive enabled=enabled enabled=disabled'),
      contains('Runner status unknown'));
  });
  test('remote status reports retained outcomes, not process success', () {
    const wire =
        'active=active enabled=linked session_state=active cycles=1 effects=0 '
        'last_scheduled_check=2026-09-04T16:50:00+00:00 '
        'next_check=2026-09-04T16:55:00+00:00 '
        'last_outcome=blocked:market_proposal_blocked';
    expect(tradingRemoteRunnerStatusLabel(wire), contains('Checks: 1'));
    expect(tradingRemoteRunnerStatusLabel(wire), contains('No order:'));
    expect(tradingRemoteRunnerStatusLabel(wire), contains('Next scheduled'));
    expect(
      tradingRemoteRunnerStatusLabel(
        wire.replaceFirst('active=active', 'active=inactive'),
      ),
      isNot(contains('Next scheduled')),
    );
    for (final invalid in [
      '',
      'Ready',
      '$wire active=active',
      wire.replaceFirst('cycles=1', 'cycles=-1'),
      wire.replaceFirst('effects=0', 'effects=2'),
      wire.replaceFirst('2026-09-04T16:55:00+00:00', 'invalid'),
      wire.replaceFirst('blocked:market_proposal_blocked', 'executed'),
    ]) {
      expect(tradingRemoteRunnerStatusLabel(invalid), contains('unknown'));
    }
    expect(
      tradingRemoteRunnerStatusLabel('active=active'),
      contains('details unavailable'),
    );
    final terminal = wire
        .replaceFirst('session_state=active', 'session_state=stopped')
        .replaceFirst('effects=0', 'effects=1')
        .replaceFirst(
          'next_check=2026-09-04T16:55:00+00:00',
          'next_check=none',
        );
    expect(
      tradingRemoteRunnerStatusLabel(
        terminal.replaceFirst(
          'blocked:market_proposal_blocked',
          'effect:unresolved:test=false',
        ),
      ),
      contains('reconciliation required'),
    );
    expect(
      tradingRemoteRunnerStatusLabel(
        terminal.replaceFirst(
          'blocked:market_proposal_blocked',
          'effect:succeeded:test=true',
        ),
      ),
      contains('not a live order'),
    );
    expect(
      tradingRemoteRunnerStatusLabel(
        terminal.replaceFirst(
          'blocked:market_proposal_blocked',
          'effect:succeeded:test=false',
        ),
      ),
      contains('Provider receipt confirmed'),
    );
  });

  test('defaults to live and restores test only from an active mandate', () {
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

    final selectedSymbol = TextEditingController(text: 'DOGE-USDT');
    final selectedNotional = TextEditingController(text: '100');
    addTearDown(selectedSymbol.dispose);
    addTearDown(selectedNotional.dispose);
    expect(
      restoreTradingMandateSelection(
        mandate: live,
        nowUtc: now,
        symbol: selectedSymbol,
        maximumNotional: selectedNotional,
      ),
      isTrue,
    );
    expect(selectedSymbol.text, 'BTC-USDT');
    expect(selectedNotional.text, live.maxOrderNotionalQuoteDecimal);
    selectedNotional.text = '7';
    expect(
      restoreTradingMandateSelection(
        mandate: live,
        nowUtc: now.add(const Duration(days: 1)),
        symbol: selectedSymbol,
        maximumNotional: selectedNotional,
      ),
      isFalse,
    );
    expect(selectedNotional.text, '7');

    expect(
      tradingUsesTestEndpointAfterRestore(mandate: live, nowUtc: now),
      isFalse,
    );
    expect(
      tradingUsesTestEndpointAfterRestore(
        mandate: live,
        nowUtc: now.add(const Duration(hours: 2)),
      ),
      isFalse,
    );
    expect(
      tradingUsesTestEndpointAfterRestore(mandate: null, nowUtc: now),
      isFalse,
    );
    final test = BingxFuturesTradingMandate.issue(
      capsuleRootHex: 'a' * 64,
      accountBindingHashHex: 'b' * 64,
      symbol: 'BTC-USDT',
      testOrder: true,
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
      tradingUsesTestEndpointAfterRestore(mandate: test, nowUtc: now),
      isTrue,
    );
  });

  test(
    'remote receipts become durable before local reconciliation starts',
    () async {
      var remoteReceiptDurable = false;
      var localReconciliationStarted = false;

      await restoreTradingDroneOrderState(
        restoreRemoteCompletedEffects: () async {
          await Future<void>.delayed(Duration.zero);
          remoteReceiptDurable = true;
          return true;
        },
        restoreOpenOrdersTrackingState: () async {
          localReconciliationStarted = true;
          expect(remoteReceiptDurable, isTrue);
        },
      );

      expect(localReconciliationStarted, isTrue);
    },
  );

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

  test('order budget label is explicit and grammatical', () {
    expect(tradingOrderBudgetLabel(1), '1 exchange order');
    expect(tradingOrderBudgetLabel(8), '8 exchange orders');
  });

  test('unsupported restored effect budget falls back fail-closed', () {
    final oversized = BingxFuturesTradingMandate.issue(
      capsuleRootHex: 'a' * 64,
      accountBindingHashHex: 'b' * 64,
      symbol: 'BTC-USDT',
      testOrder: false,
      issuedAtUtc: issuedAt,
      expiresAtUtc: issuedAt.add(const Duration(hours: 1)),
      maxOrderNotionalQuoteDecimal: '10',
      maxRiskPerTradePercent: 2,
      maxDailyLossPercent: 5,
      maxConcurrentPositions: 1,
      cooldownAfterLossStreak: 2,
      cooldownMinutes: 60,
      maxEffects: 256,
    );

    expect(tradingRestoredEffectBudget(oversized), 1);
    expect(tradingRestoredEffectBudget(mandate), 32);
  });

  test('prepared intent is not labelled as executed effect', () {
    expect(tradingIntentStatusLabel(null), 'idle');
    expect(tradingIntentStatusLabel(PluginHostApiStatus.executed), 'prepared');
  });

  test('prepared intent is executable only under its active exact mandate', () {
    final now = issuedAt.add(const Duration(minutes: 1));

    expect(
      tradingHasExecutableIntent(
        status: PluginHostApiStatus.executed,
        hasResult: true,
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        selectedMaxNotional: '100',
        selectedMaxEffects: 32,
        testOrder: true,
        nowUtc: now,
      ),
      isTrue,
    );
    expect(
      tradingHasExecutableIntent(
        status: PluginHostApiStatus.executed,
        hasResult: true,
        mandate: mandate.revoke(now),
        droneEnabled: false,
        selectedSymbol: 'XRP-USDT',
        selectedMaxNotional: '100',
        selectedMaxEffects: 32,
        testOrder: true,
        nowUtc: now,
      ),
      isFalse,
    );
  });

  test('exact export selection must match active mandate symbol and mode', () {
    final now = issuedAt.add(const Duration(minutes: 1));

    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'xrp-usdt',
        selectedMaxNotional: '100.0',
        selectedMaxEffects: 32,
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
        selectedMaxNotional: '100',
        selectedMaxEffects: 32,
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
        selectedMaxNotional: '100',
        selectedMaxEffects: 32,
        testOrder: false,
        nowUtc: now,
      ),
      isFalse,
    );
    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        selectedMaxNotional: '6.969',
        selectedMaxEffects: 32,
        testOrder: true,
        nowUtc: now,
      ),
      isFalse,
    );
  });

  test('effect budget is an exact part of the authorized selection', () {
    final now = issuedAt.add(const Duration(minutes: 1));

    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        selectedMaxNotional: '100',
        selectedMaxEffects: 1,
        testOrder: true,
        nowUtc: now,
      ),
      isFalse,
    );
    expect(
      tradingMandateSelectionNotice(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        selectedMaxNotional: '100',
        selectedMaxEffects: 1,
        testOrder: true,
        nowUtc: now,
      ),
      contains(
        '32 exchange orders. Selected XRP-USDT TEST at max 100 USDT and '
        '1 exchange order',
      ),
    );
  });

  test('mandate notional comparison is numeric and fail-closed', () {
    expect(
      tradingMandateMaxNotionalMatches(
        mandate: mandate,
        selectedMaxNotional: '100.0000',
      ),
      isTrue,
    );
    expect(
      tradingMandateMaxNotionalMatches(
        mandate: mandate,
        selectedMaxNotional: '6.969',
      ),
      isFalse,
    );
    expect(
      tradingMandateMaxNotionalMatches(
        mandate: mandate,
        selectedMaxNotional: 'not-a-number',
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
        selectedMaxNotional: '100',
        selectedMaxEffects: 32,
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
        selectedMaxNotional: '100',
        selectedMaxEffects: 32,
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
