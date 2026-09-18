import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_exchange_execution_models.dart';
import 'package:hivra_app/models/bingx_futures_live_decision_models.dart';
import 'package:hivra_app/models/bingx_futures_signal_rank_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/screens/trading_drone_screen.dart';
import 'package:hivra_app/services/bingx_futures_mode_orchestrator_service.dart';

void main() {
  const remoteSessionId =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  test('symbol picker prioritizes exact and prefix matches', () {
    expect(
      tradingFilterPerpetualSymbols(const <String>[
        'NCCOGASOLINE2USD-USDT',
        'RESOLV-USDT',
        'SOL-USDC',
        'SOL-USDT',
        'SOLV-USDT',
      ], 'sol-usdt'),
      const <String>['SOL-USDT'],
    );
    expect(
      tradingFilterPerpetualSymbols(const <String>[
        'RESOLV-USDT',
        'SOL-USDC',
        'SOL-USDT',
      ], 'sol'),
      const <String>['SOL-USDC', 'SOL-USDT', 'RESOLV-USDT'],
    );
  });

  test('symbol picker resolves the tapped row from the current query', () {
    const symbols = <String>['0G-USDT', '1000000MOG-USDT', 'SOL-USDT'];
    expect(tradingPerpetualSymbolAt(symbols, '', 0), '0G-USDT');
    expect(tradingPerpetualSymbolAt(symbols, 'SOL-USDT', 0), 'SOL-USDT');
    expect(tradingPerpetualSymbolAt(symbols, 'SOL-USDT', 1), isNull);
  });

  test('pending sizing uses the exact zone-mid entry price', () {
    expect(
      tradingPendingSizingReferencePrice(
        zoneLowDecimal: '0.0801',
        zoneHighDecimal: '0.0803',
      ),
      '0.0802',
    );
    expect(
      tradingPendingSizingReferencePrice(
        zoneLowDecimal: '0.1017',
        zoneHighDecimal: '0.1019',
      ),
      '0.1018',
    );
    expect(
      tradingPendingSizingReferencePrice(
        zoneLowDecimal: '0.0803',
        zoneHighDecimal: '0.0801',
      ),
      isNull,
    );
  });

  test('remote receipt replaces stale screen tracking before persistence', () {
    final managedOrderIds = <String>{'sol-order'};
    final managedOrderSymbols = <String, String>{'sol-order': 'SOL-USDT'};
    final managedOrderProvenance = <String, BingxManagedOrderProvenance>{
      'sol-order': _managedOrderProvenance(
        orderId: 'sol-order',
        symbol: 'SOL-USDT',
      ),
    };
    final retained = BingxFuturesOrderTrackingState(
      trackedSymbol: 'SOL-USDT',
      trackedOrderId: 'sol-order',
      managedOrderIds: const <String>['sol-order'],
      managedOrderSymbols: const <String, String>{'sol-order': 'SOL-USDT'},
      managedOrderProvenance: <String, BingxManagedOrderProvenance>{
        'sol-order': managedOrderProvenance['sol-order']!,
        'ach-order': _managedOrderProvenance(
          orderId: 'ach-order',
          symbol: 'ACH-USDT',
          diagnostic: 'remote_effect_receipt_imported',
        ),
      },
      stopLossPercent: 1,
      takeProfitRiskReward: 2,
    );

    tradingSynchronizeManagedOrderState(
      state: retained,
      managedOrderIds: managedOrderIds,
      managedOrderSymbols: managedOrderSymbols,
      managedOrderProvenance: managedOrderProvenance,
    );

    final nextPersisted = BingxFuturesOrderTrackingState(
      trackedSymbol: retained.trackedSymbol,
      trackedOrderId: retained.trackedOrderId,
      managedOrderIds: managedOrderIds.toList(growable: false),
      managedOrderSymbols: Map<String, String>.of(managedOrderSymbols),
      managedOrderProvenance: Map<String, BingxManagedOrderProvenance>.of(
        managedOrderProvenance,
      ),
      stopLossPercent: retained.stopLossPercent,
      takeProfitRiskReward: retained.takeProfitRiskReward,
    );
    expect(nextPersisted.managedOrderIds, <String>['sol-order']);
    expect(nextPersisted.managedOrderProvenance, contains('ach-order'));
    expect(
      nextPersisted.managedOrderProvenance['ach-order']!.lifecycleDiagnostic,
      'remote_effect_receipt_imported',
    );
  });

  test(
    'active remote authority keeps local order refresh observation-only',
    () {
      const running =
          'active=active enabled=linked session_state=active '
          'session_operation_id=$remoteSessionId cycles=2 effects=1 '
          'last_scheduled_check=2026-09-14T02:00:00Z '
          'next_check=2026-09-14T02:05:00Z '
          'last_outcome=effect:succeeded:test=false';
      const paused =
          'active=inactive enabled=linked session_state=active '
          'session_operation_id=$remoteSessionId cycles=2 effects=1 '
          'last_scheduled_check=2026-09-14T02:00:00Z '
          'next_check=2026-09-14T02:05:00Z '
          'last_outcome=effect:succeeded:test=false';
      const terminal =
          'active=inactive enabled=linked session_state=completed '
          'session_operation_id=$remoteSessionId cycles=2 effects=1 '
          'last_scheduled_check=2026-09-14T02:00:00Z '
          'next_check=none last_outcome=effect:succeeded:test=false';

      for (final status in <String?>[running, paused, null, 'malformed']) {
        expect(
          tradingMayMutateManagedOrdersLocally(
            remoteRunnerConfigured: true,
            remoteRunnerStatusWire: status,
          ),
          isFalse,
        );
      }
      expect(
        tradingMayMutateManagedOrdersLocally(
          remoteRunnerConfigured: true,
          remoteRunnerStatusWire: terminal,
        ),
        isTrue,
      );
      expect(
        tradingMayMutateManagedOrdersLocally(
          remoteRunnerConfigured: false,
          remoteRunnerStatusWire: null,
        ),
        isTrue,
      );
    },
  );

  test('unknown Runner order restores receipt before reconciliation', () {
    const remoteOrder = BingxFuturesOpenOrder(
      orderId: 'remote-order',
      clientOrderId: 'hivra-liquidity-event',
      symbol: 'DOGE-USDT',
      side: 'SELL',
      positionSide: 'SHORT',
      orderType: 'TRIGGER_LIMIT',
      status: 'NEW',
      priceDecimal: '0.09159',
      triggerPriceDecimal: '0.09151',
      quantityDecimal: '946',
      executedQuantityDecimal: '0',
      createdAtMs: 1,
    );

    expect(
      tradingShouldRestoreRemoteEffectsBeforeOrderReconciliation(
        remoteRunnerConfigured: true,
        hasVerifiedRemoteSession: true,
        providerSnapshot: const <BingxFuturesOpenOrder>[remoteOrder],
        managedOrderProvenance: const <String, BingxManagedOrderProvenance>{},
      ),
      isTrue,
    );
    expect(
      tradingShouldRestoreRemoteEffectsBeforeOrderReconciliation(
        remoteRunnerConfigured: true,
        hasVerifiedRemoteSession: true,
        providerSnapshot: const <BingxFuturesOpenOrder>[remoteOrder],
        managedOrderProvenance: <String, BingxManagedOrderProvenance>{
          'remote-order': _managedOrderProvenance(
            orderId: 'remote-order',
            symbol: 'DOGE-USDT',
            diagnostic: 'remote_effect_receipt_imported',
          ),
        },
      ),
      isFalse,
    );
    expect(
      tradingShouldRestoreRemoteEffectsBeforeOrderReconciliation(
        remoteRunnerConfigured: true,
        hasVerifiedRemoteSession: true,
        providerSnapshot: const <BingxFuturesOpenOrder>[
          BingxFuturesOpenOrder(
            orderId: 'manual-order',
            clientOrderId: 'manual-order',
            symbol: 'DOGE-USDT',
            side: 'SELL',
            positionSide: 'SHORT',
            orderType: 'LIMIT',
            status: 'NEW',
            priceDecimal: '0.09159',
            triggerPriceDecimal: null,
            quantityDecimal: '946',
            executedQuantityDecimal: '0',
            createdAtMs: 2,
          ),
        ],
        managedOrderProvenance: const <String, BingxManagedOrderProvenance>{},
      ),
      isFalse,
    );
    expect(
      tradingShouldRestoreRemoteEffectsBeforeOrderReconciliation(
        remoteRunnerConfigured: false,
        hasVerifiedRemoteSession: true,
        providerSnapshot: const <BingxFuturesOpenOrder>[remoteOrder],
        managedOrderProvenance: const <String, BingxManagedOrderProvenance>{},
      ),
      isFalse,
    );
  });

  test(
    'successful local cancellation disappears from stale provider snapshot',
    () {
      final visible = tradingOpenOrdersAfterLifecycleChanges(
        providerSnapshot: const <BingxFuturesOpenOrder>[
          BingxFuturesOpenOrder(
            orderId: 'managed-canceled',
            symbol: 'ACH-USDT',
            side: 'BUY',
            positionSide: 'BOTH',
            orderType: 'TRIGGER_LIMIT',
            status: 'NEW',
            priceDecimal: '0.004680',
            triggerPriceDecimal: '0.004685',
            quantityDecimal: '1696',
            executedQuantityDecimal: '0',
            createdAtMs: 1,
          ),
          BingxFuturesOpenOrder(
            orderId: 'manual-open',
            symbol: 'SOL-USDT',
            side: 'SELL',
            positionSide: 'BOTH',
            orderType: 'LIMIT',
            status: 'NEW',
            priceDecimal: '250',
            triggerPriceDecimal: null,
            quantityDecimal: '1',
            executedQuantityDecimal: '0',
            createdAtMs: 2,
          ),
        ],
        canceledOrderIds: const <String>{'managed-canceled'},
      );

      expect(visible.map((order) => order.orderId), <String>['manual-open']);
    },
  );

  test('signal rank input is bounded and keeps ready candidates first', () {
    final candidates = <BingxFuturesSignalRankCandidate>[
      for (var index = 0; index < 14; index += 1)
        _rankCandidate('N${index.toString().padLeft(2, '0')}-USDT'),
      _rankCandidate('READY-B-USDT', ready: true),
      _rankCandidate('READY-A-USDT', ready: true),
    ];

    final bounded = tradingBoundedSignalRankCandidates(candidates);
    final reversed = tradingBoundedSignalRankCandidates(
      candidates.reversed.toList(growable: false),
    );

    expect(bounded, hasLength(tradingSignalRankCandidateLimit));
    expect(bounded.take(2).map((candidate) => candidate.symbol), <String>[
      'READY-A-USDT',
      'READY-B-USDT',
    ]);
    expect(
      reversed.map((candidate) => candidate.symbol),
      bounded.map((candidate) => candidate.symbol),
    );
  });

  test('remote session rejects an SL outside current leverage buffer', () {
    expect(
      tradingRemoteSessionStopLossNotice(
        stopLossPercent: 5,
        leverageVerified: true,
        longLeverage: 20,
        shortLeverage: 20,
        nominalStopLossLimitPercent: 5,
      ),
      contains('Choose SL below 5.00%'),
    );
    expect(
      tradingRemoteSessionStopLossNotice(
        stopLossPercent: 4,
        leverageVerified: true,
        longLeverage: 20,
        shortLeverage: 20,
        nominalStopLossLimitPercent: 5,
      ),
      isNull,
    );
  });

  test(
    'reconciliation feedback is scoped and distinguishes tests from effects',
    () {
      final state = BingxFuturesOrderTrackingState(
        trackedSymbol: null,
        trackedOrderId: null,
        managedOrderIds: const [],
        managedOrderSymbols: const {},
        managedOrderProvenance: const {
          'closed-order': BingxManagedOrderProvenance(
            orderId: 'closed-order',
            symbol: 'ZIL-USDT',
            side: 'sell',
            testOrder: false,
            intentHashHex: 'intent',
            canonicalIntentJson: '{}',
            positionId: 'position-1',
            positionLifecycleStatus: BingxManagedPositionLifecycleStatus.closed,
            netPnlQuoteDecimal: '-0.83',
            closedAtUtc: '2026-09-06T13:00:00.000Z',
            marketSnapshotHashHex: null,
            featureHashHex: null,
            tvhDecisionHashHex: null,
            liveDecisionHashHex: null,
            recordedAtUtc: '2026-09-06T12:00:00.000Z',
          ),
        },
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
      final details = tradingReconciliationDetails(result, 'capsule-a')!;
      expect(notice, contains('No active orders · 1 needs review'));
      expect(notice, contains('not recreate'));
      expect(notice, isNot(contains('live-client')));
      expect(details, contains('may mean filled'));
      expect(details, contains('DOGE-USDT · live-client'));
      expect(
        details,
        contains('BingX reports FAILED; final outcome unverified'),
      );
      expect(details, contains('Test records are retained separately'));
      expect(details, contains('ZIL-USDT position closed · net -0.83 USDT'));
      expect(details, isNot(contains('test-client')));
      expect(tradingReconciliationNotice(result, 'capsule-b'), isNull);
      expect(tradingReconciliationDetails(result, 'capsule-b'), isNull);
      expect(tradingReconciliationNotice(result, null), isNull);
      expect(tradingReconciliationNotice(null, 'capsule-a'), isNull);
    },
  );

  test('account changes stay concise until reconciliation details expand', () {
    const state = BingxFuturesOrderTrackingState(
      trackedSymbol: null,
      trackedOrderId: null,
      managedOrderIds: <String>[],
      managedOrderSymbols: <String, String>{},
      managedOrderProvenance: <String, BingxManagedOrderProvenance>{
        '2091062608844660736': BingxManagedOrderProvenance(
          orderId: '2091062608844660736',
          symbol: 'DOGE-USDT',
          side: 'buy',
          testOrder: false,
          intentHashHex: 'intent',
          canonicalIntentJson: '{}',
          lifecycleStatus: BingxManagedOrderLifecycleStatus.unresolved,
          lifecycleDiagnostic: 'account_binding_mismatch',
          marketSnapshotHashHex: null,
          featureHashHex: null,
          tvhDecisionHashHex: null,
          liveDecisionHashHex: null,
          recordedAtUtc: '2026-09-06T12:00:00.000Z',
        ),
      },
      stopLossPercent: null,
      takeProfitRiskReward: null,
    );
    const result = BingxFuturesManagedOrderReconciliationResult(
      status: BingxFuturesManagedOrderReconciliationStatus.reconciled,
      capsuleRootHex: 'capsule-a',
      state: state,
      activeCount: 0,
      terminalCount: 0,
      unresolvedCount: 1,
      diagnostics: <String>[],
    );

    final notice = tradingReconciliationNotice(result, 'capsule-a')!;
    final details = tradingReconciliationDetails(result, 'capsule-a')!;
    expect(notice, contains('earlier records belong to another BingX account'));
    expect(notice, isNot(contains('2091062608844660736')));
    expect(notice, isNot(contains('account_binding_mismatch')));
    expect(details, contains('2091062608844660736'));
    expect(details, contains('different BingX account'));
  });

  test('paused process does not imply disabled startup', () {
    for (final details in [
      '',
      ' session_state=active session_operation_id=$remoteSessionId '
          'cycles=0 effects=0 '
          'last_scheduled_check=none next_check=2026-09-05T02:00:00Z last_outcome=none',
    ]) {
      final enabled = tradingRemoteRunnerStatusLabel(
        'active=inactive enabled=enabled$details',
      );
      expect(enabled, contains('Runner paused'));
      expect(enabled, contains('WARNING: autostart enabled'));
      expect(enabled, isNot(contains('Autostart: not enabled')));
      for (final state in ['linked', 'disabled']) {
        expect(
          tradingRemoteRunnerStatusLabel(
            'active=inactive enabled=$state$details',
          ),
          contains('Autostart: not enabled'),
        );
      }
      for (final value in ['', ' enabled=unexpected']) {
        expect(
          tradingRemoteRunnerStatusLabel('active=inactive$value$details'),
          contains('pause persistence is not verified'),
        );
      }
    }
    expect(
      tradingRemoteRunnerStatusLabel(
        'active=inactive enabled=enabled enabled=disabled',
      ),
      contains('Runner status unknown'),
    );
  });

  test('failed Runner does not present retained authority as execution', () {
    const failed =
        'active=failed enabled=enabled session_state=active '
        'session_operation_id=$remoteSessionId cycles=14 effects=0 '
        'last_scheduled_check=2026-09-14T08:25:00Z '
        'next_check=2026-09-14T08:30:00Z '
        'last_outcome=blocked:active_order_exists';

    final label = tradingRemoteRunnerStatusLabel(
      failed,
      authorizedMaxEffects: 2,
    );

    expect(label, contains('Runner failed · Authorization remains active'));
    expect(label, contains('The Runner is stopped'));
    expect(label, contains('No checks or orders can occur'));
    expect(label, isNot(contains('Session active')));
    expect(label, isNot(contains('Next scheduled check')));
  });

  test('Runner explains an existing market order as duplicate protection', () {
    const running =
        'active=active enabled=linked session_state=active '
        'session_operation_id=$remoteSessionId cycles=12 effects=0 '
        'last_scheduled_check=2026-09-17T12:40:00Z '
        'next_check=2026-09-17T12:45:00Z '
        'last_outcome=blocked:active_order_exists';

    final label = tradingRemoteRunnerStatusLabel(
      running,
      authorizedMaxEffects: 2,
    );

    expect(label, contains('already has an open order'));
    expect(label, contains('waiting to avoid a duplicate'));
    expect(label, isNot(contains('active order exists')));
  });

  test('Runner distinguishes managed and external pending orders', () {
    const prefix =
        'active=active enabled=linked session_state=active '
        'session_operation_id=$remoteSessionId cycles=12 effects=0 '
        'last_scheduled_check=2026-09-17T12:40:00Z '
        'next_check=2026-09-17T12:45:00Z last_outcome=';

    final managed = tradingRemoteRunnerStatusLabel(
      '${prefix}blocked:managed_order_active',
      authorizedMaxEffects: 2,
    );
    final external = tradingRemoteRunnerStatusLabel(
      '${prefix}blocked:external_order_active',
      authorizedMaxEffects: 2,
    );
    final unknown = tradingRemoteRunnerStatusLabel(
      '${prefix}blocked:order_ownership_unavailable',
      authorizedMaxEffects: 2,
    );

    expect(managed, contains('this Runner already has a pending order'));
    expect(external, contains('not owned by this session'));
    expect(unknown, contains('could not be verified'));
  });

  test('operator-owned order conflict explains automatic Runner pause', () {
    const prefix = 'active=inactive enabled=enabled operator_hold=';
    const suffix =
        ' session_state=active session_operation_id=$remoteSessionId '
        'cycles=13 effects=0 '
        'last_scheduled_check=2026-09-17T12:45:00Z '
        'next_check=none last_outcome=';

    final external = tradingRemoteRunnerStatusLabel(
      '${prefix}external_order_active${suffix}blocked:external_order_active',
      authorizedMaxEffects: 2,
    );
    final unknown = tradingRemoteRunnerStatusLabel(
      '${prefix}order_ownership_unavailable${suffix}blocked:order_ownership_unavailable',
      authorizedMaxEffects: 2,
    );

    expect(external, contains('Runner paused'));
    expect(external, contains('resume this signed session'));
    expect(external, contains('Startup blocked until'));
    expect(unknown, contains('Runner paused'));
    expect(unknown, contains('before resuming'));
  });

  test('Runner rejects an operator hold that is not bound to its outcome', () {
    const inconsistent =
        'active=inactive enabled=enabled '
        'operator_hold=external_order_active session_state=active '
        'session_operation_id=$remoteSessionId '
        'cycles=13 effects=0 '
        'last_scheduled_check=2026-09-17T12:45:00Z '
        'next_check=none '
        'last_outcome=blocked:managed_order_active';

    expect(
      tradingRemoteRunnerStatusLabel(inconsistent, authorizedMaxEffects: 2),
      'Runner status unknown. Refresh to retry.',
    );
  });

  test('Runner actions preserve one retained session lifecycle', () {
    const running =
        'active=active enabled=linked session_state=active '
        'session_operation_id=$remoteSessionId cycles=1 effects=0 '
        'last_scheduled_check=2026-09-04T16:50:00+00:00 '
        'next_check=2026-09-04T16:55:00+00:00 '
        'last_outcome=blocked:market_proposal_blocked';
    final paused = running.replaceFirst('active=active', 'active=inactive');
    final terminal = paused
        .replaceFirst('session_state=active', 'session_state=completed')
        .replaceFirst(
          'next_check=2026-09-04T16:55:00+00:00',
          'next_check=none',
        );

    expect(tradingRemoteRunnerIsRunning(running), isTrue);
    expect(tradingRemoteRunnerCanPause(running), isTrue);
    expect(tradingRemoteRunnerCanResume(running), isFalse);
    expect(tradingRemoteRunnerCanResume(paused), isTrue);
    expect(tradingRemoteRunnerCanPause(paused), isFalse);
    expect(tradingRemoteRunnerCanRevoke(running), isTrue);
    expect(tradingRemoteRunnerCanRevoke(paused), isTrue);
    expect(tradingRemoteRunnerCanRevoke(terminal), isFalse);
    expect(tradingRemoteRunnerCanStartSession(raw: paused), isFalse);
    expect(tradingRemoteRunnerCanStartSession(raw: terminal), isTrue);
    final enabledTerminal = terminal.replaceFirst(
      'enabled=linked',
      'enabled=enabled',
    );
    expect(
      tradingRemoteRunnerStatusLabel(enabledTerminal),
      contains('Runner stopped'),
    );
    expect(
      tradingRemoteRunnerStatusLabel(enabledTerminal),
      contains('finished session cannot trade'),
    );
    expect(tradingRemoteRunnerCanStartSession(raw: enabledTerminal), isTrue);
    expect(
      tradingRemoteRunnerCanStartSession(
        raw: paused.replaceFirst('enabled=linked', 'enabled=enabled'),
      ),
      isFalse,
    );
    expect(tradingRemoteRunnerCanResume('$paused active=inactive'), isFalse);

    expect(
      tradingRemoteRunnerMayHoldAuthority(
        configured: true,
        statusWire: running,
      ),
      isTrue,
    );
    expect(
      tradingRemoteRunnerMayHoldAuthority(configured: true, statusWire: paused),
      isTrue,
    );
    expect(
      tradingRemoteRunnerMayHoldAuthority(
        configured: true,
        statusWire: terminal,
      ),
      isFalse,
    );
    expect(
      tradingRemoteRunnerMayHoldAuthority(
        configured: true,
        statusWire: terminal.replaceFirst('active=inactive', 'active=active'),
      ),
      isTrue,
      reason: 'an inconsistent live process must fail closed',
    );
    expect(
      tradingRemoteRunnerMayHoldAuthority(
        configured: true,
        statusWire: 'malformed',
      ),
      isTrue,
    );
    expect(
      tradingRemoteRunnerMayHoldAuthority(
        configured: false,
        statusWire: running,
      ),
      isFalse,
    );
    expect(
      tradingRemoteRunnerMayHoldAuthority(
        configured: true,
        statusWire: running,
      ),
      isTrue,
    );
    const absent = 'active=inactive enabled=linked session_state=absent';
    expect(
      tradingRemoteRunnerMayHoldAuthority(configured: true, statusWire: absent),
      isFalse,
    );
    expect(tradingRemoteRunnerCanStartSession(raw: absent), isTrue);
    expect(tradingRemoteRunnerCanRevoke(absent), isFalse);
    expect(
      tradingRemoteRunnerStatusLabel(absent),
      contains('No signed trading session'),
    );
    const unavailable =
        'active=inactive enabled=linked session_state=unavailable';
    expect(
      tradingRemoteRunnerMayHoldAuthority(
        configured: true,
        statusWire: unavailable,
      ),
      isTrue,
    );
    expect(tradingRemoteRunnerCanStartSession(raw: unavailable), isFalse);
  });

  test('verified Runner session summary names exact market and limits', () {
    final issuedAt = DateTime.utc(2026, 9, 8, 10);
    final mandate = BingxFuturesTradingMandate.issue(
      capsuleRootHex: 'a' * 64,
      accountBindingHashHex: 'b' * 64,
      symbol: 'SOL-USDT',
      testOrder: false,
      issuedAtUtc: issuedAt,
      expiresAtUtc: issuedAt.add(const Duration(hours: 24)),
      maxOrderNotionalQuoteDecimal: '17',
      maxRiskPerTradePercent: 2,
      maxDailyLossPercent: 5,
      maxConcurrentPositions: 1,
      cooldownAfterLossStreak: 2,
      cooldownMinutes: 60,
      maxEffects: 1,
    );
    final session =
        BingxFuturesRemoteMandateAdmission.issueDeterministicSession(
          mandate: mandate,
          runnerKeyId: 'c' * 64,
          strategyPolicy:
              BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
                stopLossPercent: 2,
                minimumRiskReward: 2.5,
                includeOpenOrders: true,
              ),
          startsAtUtc: issuedAt.add(const Duration(minutes: 15)),
          intervalSeconds: 300,
          maxCycles: 24,
          signCommitment: (_) => 'd' * 128,
        );
    expect(session, isNotNull);
    final verifiedSession = session!;

    final summary = tradingRemoteRunnerSessionDetailsLabel(verifiedSession);
    expect(summary, contains('SOL-USDT · LIVE'));
    expect(summary, contains('Limit 17 USDT · Up to 1 exchange request'));
    expect(summary, contains('SL 2% · Minimum R:R 2.5'));
    expect(summary, contains('Checks every 5 min · Up to 24 checks'));
    expect(summary, contains('Capsule aaaaaaaa · Account bbbbbbbb'));

    final currentStatus =
        'active=active enabled=linked session_state=active '
        'session_operation_id=${verifiedSession.operationId} cycles=0 effects=0 '
        'last_scheduled_check=none '
        'next_check=2026-09-08T10:15:00Z last_outcome=none';
    expect(
      tradingRemoteRunnerCurrentSession(
        statusWire: currentStatus,
        retainedSession: verifiedSession,
      ),
      same(verifiedSession),
    );
    expect(
      tradingRemoteRunnerCurrentSession(
        statusWire: currentStatus.replaceFirst(
          verifiedSession.operationId,
          remoteSessionId,
        ),
        retainedSession: verifiedSession,
      ),
      isNull,
      reason: 'local evidence cannot define a different VPS session',
    );
    expect(
      tradingRemoteRunnerCurrentSession(
        statusWire: currentStatus
            .replaceFirst('session_state=active', 'session_state=stopped')
            .replaceFirst('next_check=2026-09-08T10:15:00Z', 'next_check=none'),
        retainedSession: verifiedSession,
      ),
      isNull,
      reason: 'terminal VPS state removes operational authority',
    );
  });
  test('remote status reports retained outcomes, not process success', () {
    const wire =
        'active=active enabled=linked session_state=active '
        'session_operation_id=$remoteSessionId cycles=1 effects=0 '
        'last_scheduled_check=2026-09-04T16:50:00+00:00 '
        'next_check=2026-09-04T16:55:00+00:00 '
        'last_outcome=blocked:market_proposal_blocked';
    expect(tradingRemoteRunnerStatusLabel(wire), contains('Checks: 1'));
    expect(tradingRemoteRunnerStatusLabel(wire), contains('No order:'));
    expect(tradingRemoteRunnerStatusLabel(wire), contains('Next scheduled'));
    expect(
      tradingRemoteRunnerStatusLabel(wire, authorizedMaxEffects: 4),
      contains('Exchange requests used: 0 of 4 · Remaining: 4'),
    );
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
      wire.replaceFirst('session_operation_id=$remoteSessionId ', ''),
      wire.replaceFirst(remoteSessionId, 'not-a-session-id'),
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
    expect(
      tradingRemoteRunnerStatusLabel(
        terminal.replaceFirst(
          'blocked:market_proposal_blocked',
          'effect:succeeded:test=false',
        ),
        authorizedMaxEffects: 1,
      ),
      allOf(
        contains('Exchange requests used: 1 of 1 · Remaining: 0'),
        contains('exchange-request limit was reached'),
      ),
    );
  });

  test('order budget copy explains the finite Runner session', () {
    expect(tradingOrderBudgetNotice(1), contains('stops after its first'));
    expect(tradingOrderBudgetNotice(4), contains('stops after 4'));
  });

  test('runner summary distinguishes configuration and live status', () {
    expect(
      tradingRemoteRunnerSummaryLabel(
        loading: true,
        configured: false,
        unavailable: false,
        statusWire: null,
      ),
      contains('Checking'),
    );
    expect(
      tradingRemoteRunnerSummaryLabel(
        loading: false,
        configured: false,
        unavailable: false,
        statusWire: null,
      ),
      contains('No VPS Runner'),
    );
    expect(
      tradingRemoteRunnerSummaryLabel(
        loading: false,
        configured: true,
        unavailable: false,
        statusWire: null,
      ),
      contains('Refresh to unlock'),
    );
    expect(
      tradingRemoteRunnerSummaryLabel(
        loading: false,
        configured: true,
        unavailable: true,
        statusWire: null,
      ),
      contains('unavailable'),
    );
    expect(
      tradingRemoteRunnerSummaryLabel(
        loading: false,
        configured: true,
        unavailable: false,
        statusWire:
            'active=active enabled=linked session_state=active '
            'session_operation_id=$remoteSessionId cycles=0 '
            'effects=0 last_scheduled_check=none '
            'next_check=2026-09-06T12:00:00Z last_outcome=none',
      ),
      contains('Runner running'),
    );
  });

  test('Runner controls separate setup, authorization, and resume', () {
    expect(
      tradingRemoteRunnerPrimaryActionLabel(
        configured: false,
        running: false,
        resumable: false,
      ),
      'Set up VPS Runner',
    );
    expect(
      tradingRemoteRunnerPrimaryActionEnabled(
        configured: false,
        running: false,
        resumable: false,
        canStart: false,
        localActive: false,
      ),
      isTrue,
    );
    expect(
      tradingRemoteRunnerControlNotice(
        configured: false,
        running: false,
        resumable: false,
      ),
      contains('do not need to pause'),
    );
    expect(
      tradingRemoteRunnerPrimaryActionLabel(
        configured: true,
        running: false,
        resumable: false,
      ),
      'Authorize VPS session',
    );
    expect(
      tradingRemoteRunnerPrimaryActionEnabled(
        configured: true,
        running: false,
        resumable: false,
        canStart: true,
        localActive: false,
      ),
      isTrue,
    );
    expect(
      tradingRemoteRunnerPrimaryActionLabel(
        configured: true,
        running: false,
        resumable: true,
      ),
      'Resume VPS session',
    );
    expect(
      tradingRemoteRunnerPrimaryActionEnabled(
        configured: true,
        running: false,
        resumable: true,
        canStart: false,
        localActive: false,
      ),
      isTrue,
    );
    expect(
      tradingRemoteRunnerPrimaryActionEnabled(
        configured: true,
        running: false,
        resumable: true,
        canStart: false,
        localActive: true,
      ),
      isFalse,
      reason: 'local startup owns the automation lane until it stops',
    );
    expect(
      tradingRemoteRunnerControlNotice(
        configured: true,
        running: false,
        resumable: false,
      ),
      contains('renewal is required'),
    );
    expect(
      tradingRemoteRunnerControlNotice(
        configured: true,
        running: true,
        resumable: false,
      ),
      contains('Pausing this app does not stop it'),
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
    'VPS startup defers both remote unlock and local reconciliation',
    () async {
      var localReconciliationStarted = false;

      await restoreTradingDroneOrderState(
        remoteRunnerConfigured: true,
        restoreOpenOrdersTrackingState: ({required reconcile}) async {
          localReconciliationStarted = reconcile;
        },
      );

      expect(localReconciliationStarted, isFalse);
    },
  );

  test('local startup reconciles without opening the remote secret', () async {
    var localReconciliationStarted = false;

    await restoreTradingDroneOrderState(
      remoteRunnerConfigured: false,
      restoreOpenOrdersTrackingState: ({required reconcile}) async {
        localReconciliationStarted = reconcile;
      },
    );

    expect(localReconciliationStarted, isTrue);
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

  test('order budget label is explicit and grammatical', () {
    expect(tradingOrderBudgetLabel(1), '1 exchange request');
    expect(tradingOrderBudgetLabel(8), '8 exchange requests');
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
    expect(tradingIntentStatusLabel(null), 'No setup prepared');
    expect(
      tradingIntentStatusLabel(PluginHostApiStatus.executed),
      'Order ready for review',
    );
  });

  test('trading controls use product language for the primary journey', () {
    expect(
      tradingControlStateLabel(loaded: false, saving: false, enabled: false),
      'Loading trading control',
    );
    expect(
      tradingControlStateLabel(loaded: true, saving: false, enabled: true),
      'Bounded authority active',
    );
    expect(
      tradingControlStateLabel(loaded: true, saving: false, enabled: false),
      'No active authority',
    );
    expect(
      tradingControlStateLabel(
        loaded: true,
        saving: false,
        enabled: false,
        remoteSessionRunning: true,
        remoteMayHoldAuthority: true,
      ),
      'VPS authority active',
    );
    expect(
      tradingControlStateLabel(
        loaded: true,
        saving: false,
        enabled: false,
        remoteMayHoldAuthority: true,
      ),
      'VPS authority retained',
    );
    expect(
      tradingMarketCheckActionLabel(running: false, progress: 'ignored'),
      'Inspect current setup',
    );
    expect(
      tradingMarketInspectionMessage(
        prepared: false,
        autonomous: true,
        reason: 'The market has already moved beyond the bounded retest.',
      ),
      isNull,
    );
    expect(
      tradingMarketInspectionMessage(
        prepared: false,
        autonomous: false,
        reason: 'The market has already moved beyond the bounded retest.',
      ),
      contains('A running watcher keeps checking for the next fresh zone.'),
    );
    expect(
      tradingOrderActionLabel(
        executing: false,
        hasExecutableIntent: false,
        testOrder: false,
      ),
      'No order prepared',
    );
    expect(
      tradingOrderActionLabel(
        executing: false,
        hasExecutableIntent: true,
        testOrder: false,
      ),
      'Review and Place Order',
    );
    expect(
      tradingOrderActionLabel(
        executing: false,
        hasExecutableIntent: true,
        testOrder: true,
      ),
      'Validate Without Order',
    );
    expect(
      tradingLocalRunnerActionLabel(starting: false, running: false),
      'Run on this computer',
    );
    expect(
      tradingLocalRunnerActionLabel(starting: false, running: true),
      'Stop on this computer',
    );
    expect(tradingRunnerMarketActionLabel(' sol-usdt '), 'Market: SOL-USDT');
    expect(
      tradingRunnerMarketActionLabel(
        'DOGE-USDT',
        remoteSessionSymbol: ' ach-usdt ',
      ),
      'VPS market: ACH-USDT',
    );
    expect(tradingRunnerMarketActionLabel(''), 'Choose market');
    expect(
      tradingLocalRunnerStatusLabel(null),
      contains('while Hivra and this Trading workspace stay open'),
    );
    expect(
      tradingLocalRunnerStatusLabel(
        BingxFuturesInteractiveRunnerSnapshot(
          capsuleScope:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          phase: BingxFuturesInteractiveRunnerPhase.waiting,
          completedCycles: 50,
          lastOutcome: 'blocked:session_stream_unavailable',
          nextCycleAtUtc: DateTime.utc(2026, 9, 10, 5, 55),
          lastError: null,
        ),
      ),
      'Watching on this computer · 50 attempts · '
      'BingX market connection unavailable · next check 05:55 UTC',
    );
    expect(
      tradingLocalRunnerStatusLabel(
        const BingxFuturesInteractiveRunnerSnapshot(
          capsuleScope:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          phase: BingxFuturesInteractiveRunnerPhase.waiting,
          completedCycles: 1,
          lastOutcome: 'blocked:market_volume_activation_unavailable',
          nextCycleAtUtc: null,
          lastError: null,
        ),
      ),
      'Watching on this computer · 1 attempt · '
      'waiting for clearer market volume',
    );
    expect(
      tradingLocalRunnerStatusLabel(
        const BingxFuturesInteractiveRunnerSnapshot(
          capsuleScope:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          phase: BingxFuturesInteractiveRunnerPhase.waiting,
          completedCycles: 2,
          lastOutcome: 'blocked:liquidity_anchor_unavailable',
          nextCycleAtUtc: null,
          lastError: null,
        ),
      ),
      'Watching on this computer · 2 attempts · '
      'waiting for a fresh liquidity zone',
    );
    expect(
      tradingLocalRunnerOutcomeLabel(
        'blocked:momentum_gate_short_missed_retest',
      ),
      'waiting for the next bounded retest',
    );
  });

  test('local runner start reauthorizes a changed market without scan', () {
    expect(
      tradingLocalRunnerRequiresAuthorization(
        droneEnabled: true,
        selectionNotice: null,
      ),
      isFalse,
    );
    expect(
      tradingLocalRunnerRequiresAuthorization(
        droneEnabled: true,
        selectionNotice: 'Selected market differs from the active mandate.',
      ),
      isTrue,
    );
    expect(
      tradingLocalRunnerRequiresAuthorization(
        droneEnabled: false,
        selectionNotice: null,
      ),
      isTrue,
    );
  });

  test('local automation cannot overlap retained VPS authority', () {
    expect(
      tradingLocalRunnerActionEnabled(
        starting: false,
        running: false,
        remoteMayHoldAuthority: true,
      ),
      isFalse,
    );
    expect(
      tradingLocalRunnerActionEnabled(
        starting: false,
        running: false,
        remoteMayHoldAuthority: false,
      ),
      isTrue,
    );
    expect(
      tradingLocalRunnerActionEnabled(
        starting: false,
        running: true,
        remoteMayHoldAuthority: true,
      ),
      isTrue,
      reason: 'the stop action must remain available',
    );
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
        '32 exchange requests. Selected XRP-USDT TEST at max 100 USDT and '
        '1 exchange request',
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
    final fittedMandate = BingxFuturesTradingMandate.issue(
      capsuleRootHex: 'a' * 64,
      accountBindingHashHex: 'b' * 64,
      symbol: 'DOGE-USDT',
      testOrder: false,
      issuedAtUtc: issuedAt,
      expiresAtUtc: issuedAt.add(const Duration(hours: 24)),
      maxOrderNotionalQuoteDecimal: '19.318544',
      maxRiskPerTradePercent: 2,
      maxDailyLossPercent: 5,
      maxConcurrentPositions: 1,
      cooldownAfterLossStreak: 2,
      cooldownMinutes: 60,
      maxEffects: 1,
    );
    expect(
      tradingMandateMaxNotionalMatches(
        mandate: fittedMandate,
        selectedMaxNotional: '19.318544000000003',
      ),
      isTrue,
    );
    expect(
      tradingMandateMaxNotionalMatches(
        mandate: fittedMandate,
        selectedMaxNotional: '19.31854401',
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
      'Snapshot 2026-08-20T10:39:15.000Z. Candidates are observations; '
      'Check Market validates current conditions.',
    );
  });

  test('product labels do not present ranked observations as executable', () {
    expect(tradingSignalBucketProductLabel('ready'), 'CANDIDATE');
    expect(tradingSignalBucketProductLabel('near'), 'WATCH');
    expect(tradingSignalBucketProductLabel('blocked'), 'BLOCKED');
    expect(tradingSignalBucketProductLabel('no_signal'), 'NO SIGNAL');
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

BingxFuturesSignalRankCandidate _rankCandidate(
  String symbol, {
  bool ready = false,
}) {
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  return BingxFuturesSignalRankCandidate(
    symbol: symbol,
    decision: BingxFuturesLiveDecisionResult(
      canPrepareIntent: ready,
      decision:
          ready ? BingxTvhDecisionKind.short : BingxTvhDecisionKind.noSignal,
      side: ready ? 'sell' : null,
      zoneSide: ready ? 'sellside' : null,
      zoneLowDecimal: ready ? '1' : null,
      zoneHighDecimal: ready ? '2' : null,
      zoneConflict: false,
      marketSnapshotHashHex: hash,
      featureHashHex: hash,
      tvhDecisionHashHex: hash,
      liveDecisionHashHex: hash,
      canonicalJson: '{}',
      reasons: const [],
      trend15m: 'flat',
      trend4h: 'flat',
      trend1d: 'flat',
      trendGateBlocked: false,
      trendGateCode: 'ok',
      zoneAnchorSource: ready ? '1d_fresh_high' : null,
      zoneAnchorExecutable: ready,
      zoneAnchorLifecycle: ready ? 'fresh' : null,
      zoneEvaluationSide: ready ? 'sell' : null,
    ),
  );
}

BingxManagedOrderProvenance _managedOrderProvenance({
  required String orderId,
  required String symbol,
  String? diagnostic,
}) => BingxManagedOrderProvenance(
  orderId: orderId,
  symbol: symbol,
  side: 'sell',
  testOrder: false,
  intentHashHex: 'intent-$orderId',
  canonicalIntentJson: '{}',
  lifecycleStatus: BingxManagedOrderLifecycleStatus.unresolved,
  lifecycleDiagnostic: diagnostic,
  marketSnapshotHashHex: null,
  featureHashHex: null,
  tvhDecisionHashHex: null,
  liveDecisionHashHex: null,
  recordedAtUtc: '2026-09-13T19:45:06.470566Z',
);
