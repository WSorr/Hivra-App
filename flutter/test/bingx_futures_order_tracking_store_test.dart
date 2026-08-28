import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/services/bingx_futures_order_tracking_store.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  group('BingxFuturesOrderTrackingStore', () {
    test('saves and restores tracking state for active capsule', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-order-tracking-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      String? activeCapsuleHex =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => activeCapsuleHex,
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );

      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: 'bnb-usdt',
          trackedOrderId: 'ord-1',
          managedOrderIds: <String>['ord-1', 'ord-2'],
          managedOrderSymbols: <String, String>{
            'ord-1': 'BNB-USDT',
            'ord-2': 'BNB-USDT',
          },
          managedOrderProvenance: <String, BingxManagedOrderProvenance>{
            'ord-1': BingxManagedOrderProvenance(
              orderId: 'ord-1',
              symbol: 'BNB-USDT',
              side: 'sell',
              testOrder: false,
              intentHashHex: 'intent-1',
              canonicalIntentJson: '{"symbol":"BNB-USDT","side":"sell"}',
              externalEffectOperationId:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              marketSnapshotHashHex: 'market-1',
              featureHashHex: 'feature-1',
              tvhDecisionHashHex: 'tvh-1',
              liveDecisionHashHex: 'live-1',
              recordedAtUtc: '2026-06-12T12:00:00.000Z',
            ),
          },
          droneEnabled: false,
          stopLossPercent: 10.0,
          takeProfitRiskReward: 2.0,
        ),
      );
      final restored = await store.load();
      expect(restored, isNotNull);
      expect(restored!.trackedSymbol, 'BNB-USDT');
      expect(restored.trackedOrderId, 'ord-1');
      expect(restored.managedOrderIds, <String>['ord-1', 'ord-2']);
      expect(restored.managedOrderSymbols, <String, String>{
        'ord-1': 'BNB-USDT',
        'ord-2': 'BNB-USDT',
      });
      expect(restored.managedOrderProvenance.keys, <String>['ord-1']);
      expect(restored.droneEnabled, isFalse);
      expect(
        restored.managedOrderProvenance['ord-1']!.liveDecisionHashHex,
        'live-1',
      );
      expect(restored.managedOrderProvenance['ord-1']!.testOrder, isFalse);
      expect(
        restored.managedOrderProvenance['ord-1']!.externalEffectOperationId,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(restored.stopLossPercent, 10.0);
      expect(restored.takeProfitRiskReward, 2.0);
    });

    test('returns null on malformed persisted json', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-order-tracking-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      const capsuleHex =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final dir = await fileStore.capsuleDirForHex(capsuleHex, create: true);
      final file = File('${dir.path}/bingx_futures_order_tracking.v1.json');
      await file.writeAsString('{not-json', flush: true);

      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => capsuleHex,
        fileStore: fileStore,
      );
      final restored = await store.load();
      expect(restored, isNull);
    });

    test('loads v1 state without managed order provenance', () {
      final restored = BingxFuturesOrderTrackingState.fromJsonMap(
        <String, dynamic>{
          'version': 1,
          'tracked_symbol': 'BTC-USDT',
          'tracked_order_id': 'ord-legacy',
          'managed_order_ids': <String>['ord-legacy'],
          'managed_order_symbols': <String, String>{'ord-legacy': 'BTC-USDT'},
        },
      );

      expect(restored, isNotNull);
      expect(restored!.managedOrderIds, <String>['ord-legacy']);
      expect(restored.managedOrderProvenance, isEmpty);
      expect(restored.droneEnabled, isNull);
    });

    test('drops malformed provenance without losing valid tracking state', () {
      final restored = BingxFuturesOrderTrackingState.fromJsonMap(
        <String, dynamic>{
          'version': 2,
          'managed_order_ids': <String>['ord-1'],
          'managed_order_symbols': <String, String>{'ord-1': 'SOL-USDT'},
          'managed_order_provenance': <String, dynamic>{
            'ord-1': <String, dynamic>{
              'order_id': 'ord-1',
              'symbol': 'SOL-USDT',
              'side': 'invalid',
            },
          },
        },
      );

      expect(restored, isNotNull);
      expect(restored!.managedOrderIds, <String>['ord-1']);
      expect(restored.managedOrderProvenance, isEmpty);
    });

    test('rejects malformed remote effect lineage', () {
      expect(
        BingxManagedOrderProvenance.fromJsonMap(<String, dynamic>{
          'order_id': 'ord-1',
          'symbol': 'SOL-USDT',
          'side': 'buy',
          'test_order': false,
          'intent_hash_hex': 'intent-1',
          'canonical_intent_json': '{"symbol":"SOL-USDT"}',
          'external_effect_operation_id': 'invalid',
          'recorded_at_utc': '2026-08-28T00:00:00.000Z',
        }),
        isNull,
      );
    });

    test('isolates state by capsule scope', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-order-tracking-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      String? activeCapsuleHex =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => activeCapsuleHex,
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );

      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: 'BTC-USDT',
          trackedOrderId: 'ord-c',
          managedOrderIds: <String>['ord-c'],
          managedOrderSymbols: <String, String>{'ord-c': 'BTC-USDT'},
          droneEnabled: false,
          stopLossPercent: 7.0,
          takeProfitRiskReward: 1.5,
        ),
      );
      final firstEventId = List<String>.filled(64, 'c').join();
      expect(
        await store.reserveLiquidityEventEffect(
          liquidityEventId: firstEventId,
          clientOrderId: 'hivra-capsule-c',
          symbol: 'BTC-USDT',
          side: 'buy',
          testOrder: false,
          recordedAtUtc: '2026-08-11T12:00:00.000Z',
        ),
        BingxLiquidityEventEffectReservation.acquired,
      );

      activeCapsuleHex =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      expect(await store.load(), isNull);
      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: 'SOL-USDT',
          trackedOrderId: 'ord-d',
          managedOrderIds: <String>['ord-d'],
          managedOrderSymbols: <String, String>{'ord-d': 'SOL-USDT'},
          droneEnabled: true,
          stopLossPercent: 12.0,
          takeProfitRiskReward: 3.0,
        ),
      );

      activeCapsuleHex =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      final first = await store.load();
      expect(first, isNotNull);
      expect(first!.trackedSymbol, 'BTC-USDT');
      expect(first.trackedOrderId, 'ord-c');
      expect(first.managedOrderSymbols, <String, String>{'ord-c': 'BTC-USDT'});
      expect(first.droneEnabled, isFalse);
      expect(first.stopLossPercent, 7.0);
      expect(first.takeProfitRiskReward, 1.5);
      expect(first.liquidityEventEffectClaims, hasLength(1));

      activeCapsuleHex =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final second = await store.load();
      expect(second, isNotNull);
      expect(second!.trackedSymbol, 'SOL-USDT');
      expect(second.trackedOrderId, 'ord-d');
      expect(second.managedOrderSymbols, <String, String>{'ord-d': 'SOL-USDT'});
      expect(second.droneEnabled, isTrue);
      expect(second.stopLossPercent, 12.0);
      expect(second.takeProfitRiskReward, 3.0);
      expect(second.liquidityEventEffectClaims, isEmpty);
    });

    test('clears persisted file when saved state is empty', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-order-tracking-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      const capsuleHex =
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => capsuleHex,
        fileStore: fileStore,
      );

      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: 'ETH-USDT',
          trackedOrderId: 'ord-e',
          managedOrderIds: <String>['ord-e'],
          managedOrderSymbols: <String, String>{'ord-e': 'ETH-USDT'},
          stopLossPercent: 10.0,
          takeProfitRiskReward: 2.0,
        ),
      );
      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: null,
          trackedOrderId: null,
          managedOrderIds: <String>[],
          managedOrderSymbols: <String, String>{},
          stopLossPercent: null,
          takeProfitRiskReward: null,
        ),
      );

      final dir = await fileStore.capsuleDirForHex(capsuleHex, create: false);
      final file = File('${dir.path}/bingx_futures_order_tracking.v1.json');
      expect(await file.exists(), isFalse);
      expect(await store.load(), isNull);
    });

    test('persists risk settings even without managed order state', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-order-tracking-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      const capsuleHex =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => capsuleHex,
        fileStore: fileStore,
      );

      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: null,
          trackedOrderId: null,
          managedOrderIds: <String>[],
          managedOrderSymbols: <String, String>{},
          stopLossPercent: 5.0,
          takeProfitRiskReward: 3.0,
        ),
      );

      final restored = await store.load();
      expect(restored, isNotNull);
      expect(restored!.trackedSymbol, isNull);
      expect(restored.trackedOrderId, isNull);
      expect(restored.managedOrderIds, isEmpty);
      expect(restored.managedOrderSymbols, isEmpty);
      expect(restored.stopLossPercent, 5.0);
      expect(restored.takeProfitRiskReward, 3.0);
    });

    test('persists an explicit Capsule pause without order state', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-trading-pause-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      const capsuleHex =
          '1212121212121212121212121212121212121212121212121212121212121212';
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => capsuleHex,
        fileStore: fileStore,
      );

      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: null,
          trackedOrderId: null,
          managedOrderIds: <String>[],
          managedOrderSymbols: <String, String>{},
          droneEnabled: false,
          stopLossPercent: null,
          takeProfitRiskReward: null,
        ),
      );

      final restarted = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => capsuleHex,
        fileStore: fileStore,
      );
      final restored = await restarted.load();
      expect(restored, isNotNull);
      expect(restored!.droneEnabled, isFalse);
      expect(restored.isEmpty, isFalse);
    });

    test('serializes, bounds, and restores liquidity event claims', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-event-claim-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });
      const capsuleHex =
          'abababababababababababababababababababababababababababababababab';
      BingxFuturesOrderTrackingStore buildStore() {
        return BingxFuturesOrderTrackingStore(
          readActiveCapsuleRootHex: () => capsuleHex,
          fileStore: CapsuleFileStore(
            dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
          ),
        );
      }

      final store = buildStore();
      final eventId = List<String>.filled(64, '1').join();
      final concurrent =
          await Future.wait(<Future<BingxLiquidityEventEffectReservation>>[
            store.reserveLiquidityEventEffect(
              liquidityEventId: eventId,
              clientOrderId: 'hivra-event-1',
              symbol: 'BTC-USDT',
              side: 'buy',
              testOrder: false,
              recordedAtUtc: '2026-08-11T10:00:00.000Z',
            ),
            store.reserveLiquidityEventEffect(
              liquidityEventId: eventId,
              clientOrderId: 'hivra-event-1',
              symbol: 'BTC-USDT',
              side: 'buy',
              testOrder: false,
              recordedAtUtc: '2026-08-11T10:00:00.000Z',
            ),
          ]);
      expect(
        concurrent.where(
          (value) => value == BingxLiquidityEventEffectReservation.acquired,
        ),
        hasLength(1),
      );
      expect(
        await buildStore().reserveLiquidityEventEffect(
          liquidityEventId: eventId,
          clientOrderId: 'hivra-event-1',
          symbol: 'BTC-USDT',
          side: 'buy',
          testOrder: false,
          recordedAtUtc: '2026-08-11T10:01:00.000Z',
        ),
        BingxLiquidityEventEffectReservation.alreadyClaimed,
      );
      expect(
        await buildStore().reserveLiquidityEventEffect(
          liquidityEventId: eventId,
          clientOrderId: 'hivra-event-1-test',
          symbol: 'BTC-USDT',
          side: 'buy',
          testOrder: true,
          recordedAtUtc: '2026-08-11T10:02:00.000Z',
        ),
        BingxLiquidityEventEffectReservation.acquired,
      );

      for (var index = 0; index < 260; index += 1) {
        final id = index.toRadixString(16).padLeft(64, '0');
        await store.reserveLiquidityEventEffect(
          liquidityEventId: id,
          clientOrderId: 'hivra-$index',
          symbol: 'BTC-USDT',
          side: 'sell',
          testOrder: false,
          recordedAtUtc:
              DateTime.utc(
                2026,
                8,
                12,
              ).add(Duration(seconds: index)).toIso8601String(),
        );
      }
      final restored = await buildStore().load();
      expect(restored, isNotNull);
      expect(restored!.liquidityEventEffectClaims, hasLength(256));
    });

    test('mandate commitment and atomic effect budget fail closed', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-trading-mandate-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      const capsuleHex =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const accountHex =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final now = DateTime.utc(2026, 8, 16, 10);
      final mandate = BingxFuturesTradingMandate.issue(
        capsuleRootHex: capsuleHex,
        accountBindingHashHex: accountHex,
        symbol: 'BTC-USDT',
        testOrder: true,
        issuedAtUtc: now,
        expiresAtUtc: now.add(const Duration(hours: 1)),
        maxOrderNotionalQuoteDecimal: '100',
        maxRiskPerTradePercent: 2,
        maxDailyLossPercent: 5,
        maxConcurrentPositions: 3,
        cooldownAfterLossStreak: 2,
        cooldownMinutes: 60,
        maxEffects: 1,
      );
      final encoded = mandate.toJson();
      expect(
        BingxFuturesTradingMandate.fromJsonMap(encoded)?.mandateId,
        mandate.mandateId,
      );
      for (final key in <String>[
        'capsule_root_hex',
        'account_binding_hash_hex',
        'symbol',
        'test_order',
        'expires_at_utc',
        'max_order_notional_quote_decimal',
        'max_effects',
      ]) {
        final mutation = <String, dynamic>{...encoded};
        mutation[key] = switch (key) {
          'capsule_root_hex' => List<String>.filled(64, 'c').join(),
          'account_binding_hash_hex' => List<String>.filled(64, 'd').join(),
          'symbol' => 'ETH-USDT',
          'test_order' => false,
          'expires_at_utc' =>
            now.add(const Duration(minutes: 30)).toIso8601String(),
          'max_order_notional_quote_decimal' => '101',
          _ => 2,
        };
        expect(
          BingxFuturesTradingMandate.fromJsonMap(mutation),
          isNull,
          reason: key,
        );
      }
      final missing = <String, dynamic>{...encoded}..remove('symbol');
      final unknown = <String, dynamic>{...encoded, 'authority': true};
      expect(BingxFuturesTradingMandate.fromJsonMap(missing), isNull);
      expect(BingxFuturesTradingMandate.fromJsonMap(unknown), isNull);

      final admission = BingxFuturesRemoteMandateAdmission.issue(
        mandate: mandate,
        runnerKeyId:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        signCommitment: (commitment) => '$commitment$commitment',
      );
      expect(admission, isNotNull);
      expect(
        admission!.commitmentHashHex,
        '534c820cf2ff116730e7f649620bd390e4e1c4ff12bb931051cd07d7a8fa7f92',
      );
      bool verifyAdmission({
        required String messageHashHex,
        required String participantIdHex,
        required String signatureHex,
      }) =>
          participantIdHex == capsuleHex &&
          signatureHex == '$messageHashHex$messageHashHex';
      expect(
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
          untrustedWireBytes: admission.canonicalJson.codeUnits,
          verifySignature: verifyAdmission,
        )?.operationId,
        admission.operationId,
      );
      final admissionJson = admission.toJson();
      for (final mutation in <Map<String, dynamic>>[
        <String, dynamic>{
          ...admissionJson,
          'contract_version': 'trading-remote-mandate-admission-v1',
        },
        <String, dynamic>{...admissionJson, 'runner_key_id': accountHex},
        <String, dynamic>{...admissionJson, 'signature_suite': 'legacy-v0'},
        <String, dynamic>{...admissionJson, 'operation_id': accountHex},
        <String, dynamic>{...admissionJson, 'operation_kind': 'account_write'},
        <String, dynamic>{
          ...admissionJson,
          'read_scope': <String>['balance', 'positions', 'all_orders'],
        },
        <String, dynamic>{
          ...admissionJson,
          'read_scope': <String>['positions', 'balance', 'open_orders'],
        },
        <String, dynamic>{...admissionJson, 'max_uses': 2},
        <String, dynamic>{
          ...admissionJson,
          'signature_hex': List<String>.filled(128, '0').join(),
        },
        <String, dynamic>{
          ...admissionJson,
          'mandate': <String, dynamic>{
            ...mandate.toJson(),
            'symbol': 'ETH-USDT',
          },
        },
        <String, dynamic>{...admissionJson, 'unknown': true},
      ]) {
        expect(
          BingxFuturesRemoteMandateAdmission.parseAndVerify(
            untrustedWireBytes: jsonEncode(mutation).codeUnits,
            verifySignature: verifyAdmission,
          ),
          isNull,
        );
      }
      final reordered = <String, dynamic>{
        'operation_id': admission.operationId,
        'contract_version': BingxFuturesRemoteMandateAdmission.contractVersion,
        for (final entry in admissionJson.entries)
          if (entry.key != 'operation_id' && entry.key != 'contract_version')
            entry.key: entry.value,
      };
      expect(
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
          untrustedWireBytes: jsonEncode(reordered).codeUnits,
          verifySignature: verifyAdmission,
        ),
        isNull,
      );
      expect(
        BingxFuturesRemoteMandateAdmission.issue(
          mandate: mandate.revoke(now),
          runnerKeyId: admission.runnerKeyId,
          signCommitment: (commitment) => '$commitment$commitment',
        ),
        isNull,
      );

      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => capsuleHex,
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
      await store.save(
        BingxFuturesOrderTrackingState(
          trackedSymbol: null,
          trackedOrderId: null,
          managedOrderIds: const <String>[],
          managedOrderSymbols: const <String, String>{},
          droneEnabled: true,
          tradingMandate: mandate,
          stopLossPercent: null,
          takeProfitRiskReward: null,
        ),
      );
      Future<BingxLiquidityEventEffectReservation> reserve(String event) =>
          store.reserveLiquidityEventEffect(
            liquidityEventId: event,
            clientOrderId: 'mandate-$event',
            symbol: 'BTC-USDT',
            side: 'buy',
            testOrder: true,
            recordedAtUtc:
                now.add(const Duration(minutes: 1)).toIso8601String(),
            accountBindingHashHex: accountHex,
            mandateId: mandate.mandateId,
          );
      expect(
        await reserve(List<String>.filled(64, '1').join()),
        BingxLiquidityEventEffectReservation.acquired,
      );
      expect(
        await reserve(List<String>.filled(64, '2').join()),
        BingxLiquidityEventEffectReservation.unavailable,
      );
      final restored = await store.load();
      expect(
        restored!.liquidityEventEffectClaims.values.single.mandateId,
        mandate.mandateId,
      );
    });
  });
}
