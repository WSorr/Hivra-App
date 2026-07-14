import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_delivery_lifecycle_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/delivery_outbox_store.dart';
import 'package:hivra_app/services/delivery_transport_contract.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  const capsuleA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const capsuleB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  group('CapsuleDeliveryLifecycleService', () {
    late Directory tempHome;
    late DeliveryOutboxStore outbox;
    late DateTime now;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra_delivery_');
      outbox = DeliveryOutboxStore(
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
      now = DateTime.utc(2026, 7, 11, 12);
    });

    tearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('records a receipt against only the matching capsule outbox',
        () async {
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryRunner: (_) async => const CapsuleDeliveryCycleResult(code: 0),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleB,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
      );

      await lifecycle.recordCycle(
        capsuleHex: capsuleA,
        result: const CapsuleDeliveryCycleResult(
          code: 0,
          deliveryReceiptsJson:
              '{"receipts":[{"label":"InvitationSent","receipt":{"transport":"nostr"}}]}',
        ),
      );

      expect((await outbox.load(capsuleA)).single.status,
          DeliveryOutboxStatus.delivered);
      expect((await outbox.load(capsuleB)).single.status,
          DeliveryOutboxStatus.pending);
    });

    test('pump invokes one capsule retry runner and records the result',
        () async {
      final calls = <String>[];
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryDelays: const <Duration>[],
        retryRunner: (capsuleHex) async {
          calls.add(capsuleHex);
          return const CapsuleDeliveryCycleResult(
            code: 0,
            deliveryReceiptsJson:
                '{"receipts":[{"label":"RelationshipBrokenRetry","receipt":{"transport":"nostr"}}]}',
          );
        },
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.relationshipBroken,
        reason: DeliveryOutboxReason.localRelationshipBreak,
      );

      final result = await lifecycle.pumpDueNow(capsuleHex: capsuleA);

      expect(result?.code, 0);
      expect(calls, <String>[capsuleA]);
      expect((await outbox.load(capsuleA)).single.status,
          DeliveryOutboxStatus.delivered);
    });

    test('failed cycle retains an item with deterministic next attempt',
        () async {
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryDelays: const <Duration>[Duration(seconds: 8)],
        retryRunner: (_) async => const CapsuleDeliveryCycleResult(code: -1003),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationTerminal,
        reason: DeliveryOutboxReason.invitationTerminalRetry,
      );

      await lifecycle.recordCycle(
        capsuleHex: capsuleA,
        result: const CapsuleDeliveryCycleResult(
          code: -1003,
          lastError: 'relay timeout',
        ),
      );

      final item = (await outbox.load(capsuleA)).single;
      expect(item.status, DeliveryOutboxStatus.pending);
      expect(item.attempts, 1);
      expect(item.nextAttemptAt, now.add(const Duration(seconds: 8)));
      expect(item.lastError, 'relay timeout');
    });

    test('invitation terminal receipt accepts expired cancel delivery',
        () async {
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryRunner: (_) async => const CapsuleDeliveryCycleResult(code: 0),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationTerminal,
        reason: DeliveryOutboxReason.invitationTerminalRetry,
      );

      await lifecycle.recordCycle(
        capsuleHex: capsuleA,
        result: const CapsuleDeliveryCycleResult(
          code: 0,
          deliveryReceiptsJson:
              '{"receipts":[{"label":"InvitationExpired","receipt":{"transport":"nostr"}}]}',
        ),
      );

      expect((await outbox.load(capsuleA)).single.status,
          DeliveryOutboxStatus.delivered);
    });
  });
}
