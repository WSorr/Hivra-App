import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/services/bingx_futures_order_tracking_store.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  group('BingxFuturesOrderTrackingStore', () {
    test('saves and restores tracking state for active capsule', () async {
      final tempHome =
          await Directory.systemTemp.createTemp('hivra-order-tracking-test-');
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
              marketSnapshotHashHex: 'market-1',
              featureHashHex: 'feature-1',
              tvhDecisionHashHex: 'tvh-1',
              liveDecisionHashHex: 'live-1',
              recordedAtUtc: '2026-06-12T12:00:00.000Z',
            ),
          },
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
      expect(
        restored.managedOrderProvenance['ord-1']!.liveDecisionHashHex,
        'live-1',
      );
      expect(restored.managedOrderProvenance['ord-1']!.testOrder, isFalse);
      expect(restored.stopLossPercent, 10.0);
      expect(restored.takeProfitRiskReward, 2.0);
    });

    test('returns null on malformed persisted json', () async {
      final tempHome =
          await Directory.systemTemp.createTemp('hivra-order-tracking-test-');
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
          'managed_order_symbols': <String, String>{
            'ord-legacy': 'BTC-USDT',
          },
        },
      );

      expect(restored, isNotNull);
      expect(restored!.managedOrderIds, <String>['ord-legacy']);
      expect(restored.managedOrderProvenance, isEmpty);
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

    test('isolates state by capsule scope', () async {
      final tempHome =
          await Directory.systemTemp.createTemp('hivra-order-tracking-test-');
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
          stopLossPercent: 7.0,
          takeProfitRiskReward: 1.5,
        ),
      );

      activeCapsuleHex =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      await store.save(
        const BingxFuturesOrderTrackingState(
          trackedSymbol: 'SOL-USDT',
          trackedOrderId: 'ord-d',
          managedOrderIds: <String>['ord-d'],
          managedOrderSymbols: <String, String>{'ord-d': 'SOL-USDT'},
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
      expect(first.stopLossPercent, 7.0);
      expect(first.takeProfitRiskReward, 1.5);

      activeCapsuleHex =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final second = await store.load();
      expect(second, isNotNull);
      expect(second!.trackedSymbol, 'SOL-USDT');
      expect(second.trackedOrderId, 'ord-d');
      expect(second.managedOrderSymbols, <String, String>{'ord-d': 'SOL-USDT'});
      expect(second.stopLossPercent, 12.0);
      expect(second.takeProfitRiskReward, 3.0);
    });

    test('clears persisted file when saved state is empty', () async {
      final tempHome =
          await Directory.systemTemp.createTemp('hivra-order-tracking-test-');
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
      final tempHome =
          await Directory.systemTemp.createTemp('hivra-order-tracking-test-');
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
  });
}
