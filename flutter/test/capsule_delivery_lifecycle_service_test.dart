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
  const deliveryReference =
      '1111111111111111111111111111111111111111111111111111111111111111';
  const completeReceipt =
      '"accepted_by":"wss://relay.example","envelope_id":"event-1",'
      '"message_kind":1,"recipient":['
      '17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,'
      '17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17],'
      '"failed_before_accept":0';

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

    test('records a receipt against only the matching capsule outbox', () async {
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryRunner:
            (capsuleHex, _) async => CapsuleDeliveryCycleResult(
              code: 0,
              deliveryReceiptsJson:
                  capsuleHex == capsuleA
                      ? '{"receipts":[{"label":"InvitationSent","correlation_id_hex":"$deliveryReference","receipt":{"transport":"nostr",$completeReceipt}}]}'
                      : null,
            ),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
        deliveryReference: deliveryReference,
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleB,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
        deliveryReference: deliveryReference,
      );

      await lifecycle.pumpDueNow(capsuleHex: capsuleA);

      expect(
        (await outbox.load(capsuleA)).single.status,
        DeliveryOutboxStatus.published,
      );
      expect(
        (await outbox.load(capsuleB)).single.status,
        DeliveryOutboxStatus.pending,
      );
    });

    test(
      'pump invokes one capsule retry runner and records the result',
      () async {
        final calls = <String>[];
        final lifecycle = CapsuleDeliveryLifecycleService(
          outbox: outbox,
          now: () => now,
          retryDelays: const <Duration>[],
          retryRunner: (capsuleHex, _) async {
            calls.add(capsuleHex);
            return const CapsuleDeliveryCycleResult(
              code: 0,
              deliveryReceiptsJson:
                  '{"receipts":[{"label":"RelationshipBrokenRetry","correlation_id_hex":"$deliveryReference","receipt":{"transport":"nostr",$completeReceipt}}]}',
            );
          },
        );
        await lifecycle.enqueue(
          capsuleHex: capsuleA,
          kind: DeliveryOutboxKind.relationshipBroken,
          reason: DeliveryOutboxReason.localRelationshipBreak,
          deliveryReference: deliveryReference,
        );

        final result = await lifecycle.pumpDueNow(capsuleHex: capsuleA);

        expect(result?.code, 0);
        expect(calls, <String>[capsuleA]);
        expect(
          (await outbox.load(capsuleA)).single.status,
          DeliveryOutboxStatus.published,
        );
      },
    );

    test(
      'failed cycle retains an item with deterministic next attempt',
      () async {
        final lifecycle = CapsuleDeliveryLifecycleService(
          outbox: outbox,
          now: () => now,
          retryDelays: const <Duration>[Duration(days: 1)],
          retryRunner:
              (_, _) async => const CapsuleDeliveryCycleResult(
                code: -1003,
                lastError: 'relay timeout',
              ),
        );
        await lifecycle.enqueue(
          capsuleHex: capsuleA,
          kind: DeliveryOutboxKind.invitationTerminal,
          reason: DeliveryOutboxReason.invitationTerminalRetry,
          deliveryReference: deliveryReference,
        );

        await lifecycle.pumpDueNow(capsuleHex: capsuleA);

        final item = (await outbox.load(capsuleA)).single;
        expect(item.status, DeliveryOutboxStatus.pending);
        expect(item.attempts, 1);
        expect(item.nextAttemptAt, now.add(const Duration(days: 1)));
        expect(item.lastError, 'relay timeout');
      },
    );

    test('invitation terminal receipt accepts expired cancel delivery', () async {
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryRunner:
            (_, _) async => const CapsuleDeliveryCycleResult(
              code: 0,
              deliveryReceiptsJson:
                  '{"receipts":[{"label":"InvitationExpired","correlation_id_hex":"$deliveryReference","receipt":{"transport":"nostr",$completeReceipt}}]}',
            ),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationTerminal,
        reason: DeliveryOutboxReason.invitationTerminalRetry,
        deliveryReference: deliveryReference,
      );

      await lifecycle.pumpDueNow(capsuleHex: capsuleA);

      expect(
        (await outbox.load(capsuleA)).single.status,
        DeliveryOutboxStatus.published,
      );
    });

    test('relay publication stops retries after a matching receipt', () async {
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryDelays: const <Duration>[Duration(seconds: 8)],
        retryRunner:
            (_, _) async => const CapsuleDeliveryCycleResult(
              code: 0,
              deliveryReceiptsJson:
                  '{"receipts":[{"label":"InvitationSent","correlation_id_hex":"$deliveryReference","receipt":{"transport":"nostr",$completeReceipt}}]}',
            ),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
        deliveryReference: deliveryReference,
      );

      await lifecycle.pumpDueNow(capsuleHex: capsuleA);
      var item = (await outbox.load(capsuleA)).single;
      expect(item.status, DeliveryOutboxStatus.published);
      expect(item.attempts, 1);
      expect(item.recipientHex, '11' * 32);
      expect(item.adapterAcceptedBy, 'wss://relay.example');
      expect(item.adapterEnvelopeId, 'event-1');
      expect(item.publishedAt, now);
      expect(
        await outbox.due(
          capsuleHex: capsuleA,
          now: now.add(const Duration(seconds: 8)),
        ),
        isEmpty,
      );
    });

    test('incomplete adapter receipt cannot resolve a delivery fact', () async {
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryRunner:
            (_, _) async => const CapsuleDeliveryCycleResult(
              code: 0,
              deliveryReceiptsJson:
                  '{"receipts":[{"label":"InvitationSent","correlation_id_hex":"$deliveryReference","receipt":{"transport":"nostr"}}]}',
            ),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
        deliveryReference: deliveryReference,
      );

      await lifecycle.pumpDueNow(capsuleHex: capsuleA);

      final item = (await outbox.load(capsuleA)).single;
      expect(item.status, DeliveryOutboxStatus.pending);
      expect(item.recipientHex, isNull);
      expect(item.adapterEnvelopeId, isNull);
    });

    test(
      'failed core delivery remains retryable beyond legacy attempt limit',
      () async {
        final lifecycle = CapsuleDeliveryLifecycleService(
          outbox: outbox,
          now: () => now,
          retryDelays: const <Duration>[Duration(days: 1)],
          retryRunner:
              (_, _) async => const CapsuleDeliveryCycleResult(code: -1003),
        );
        await lifecycle.enqueue(
          capsuleHex: capsuleA,
          kind: DeliveryOutboxKind.invitationSent,
          reason: DeliveryOutboxReason.sendInvitationRetry,
          deliveryReference: deliveryReference,
        );

        for (var attempt = 0; attempt < 8; attempt++) {
          await lifecycle.pumpDueNow(capsuleHex: capsuleA);
          now = (await outbox.load(capsuleA)).single.nextAttemptAt;
        }

        final item = (await outbox.load(capsuleA)).single;
        expect(item.status, DeliveryOutboxStatus.pending);
        expect(item.attempts, 8);
        expect(await outbox.due(capsuleHex: capsuleA, now: now), hasLength(1));
      },
    );

    test('quarantined aggregate record never invokes retry runner', () async {
      var calls = 0;
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryDelays: const <Duration>[],
        retryRunner: (_, _) async {
          calls += 1;
          return const CapsuleDeliveryCycleResult(code: -1004);
        },
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
      );

      expect(await lifecycle.pumpDueNow(capsuleHex: capsuleA), isNull);
      expect(calls, 0);
      expect(
        (await outbox.load(capsuleA)).single.status,
        DeliveryOutboxStatus.quarantined,
      );
    });

    test('receipt publishes only its correlated invitation fact', () async {
      const invitationA =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const invitationB =
          '2222222222222222222222222222222222222222222222222222222222222222';
      final lifecycle = CapsuleDeliveryLifecycleService(
        outbox: outbox,
        now: () => now,
        retryRunner:
            (_, _) async => const CapsuleDeliveryCycleResult(
              code: 0,
              deliveryReceiptsJson:
                  '{"receipts":[{"label":"InvitationSent","correlation_id_hex":"$invitationA","receipt":{"transport":"nostr",$completeReceipt}}]}',
            ),
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
        deliveryReference: invitationA,
      );
      await lifecycle.enqueue(
        capsuleHex: capsuleA,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
        deliveryReference: invitationB,
      );

      await lifecycle.pumpDueNow(capsuleHex: capsuleA);

      final items = await outbox.load(capsuleA);
      final byReference = <String?, DeliveryOutboxItem>{
        for (final item in items) item.deliveryReference: item,
      };
      expect(byReference[invitationA]?.status, DeliveryOutboxStatus.published);
      expect(byReference[invitationB]?.status, DeliveryOutboxStatus.pending);
    });

    test(
      'exact retry without a receipt supersedes only its own item',
      () async {
        const invitationA =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        const invitationB =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        final lifecycle = CapsuleDeliveryLifecycleService(
          outbox: outbox,
          now: () => now,
          retryRunner: (_, item) async {
            if (item.deliveryReference == invitationA) {
              // The ledger-derived offer no longer exists because a terminal
              // fact superseded it before publication.
              return const CapsuleDeliveryCycleResult(code: 0);
            }
            return const CapsuleDeliveryCycleResult(code: -1003);
          },
        );
        await lifecycle.enqueue(
          capsuleHex: capsuleA,
          kind: DeliveryOutboxKind.invitationSent,
          reason: DeliveryOutboxReason.sendInvitationRetry,
          deliveryReference: invitationA,
        );
        await lifecycle.enqueue(
          capsuleHex: capsuleA,
          kind: DeliveryOutboxKind.invitationSent,
          reason: DeliveryOutboxReason.sendInvitationRetry,
          deliveryReference: invitationB,
        );

        await lifecycle.pumpDueNow(capsuleHex: capsuleA);

        final items = await outbox.load(capsuleA);
        final byReference = <String?, DeliveryOutboxItem>{
          for (final item in items) item.deliveryReference: item,
        };
        expect(
          byReference[invitationA]?.status,
          DeliveryOutboxStatus.superseded,
        );
        expect(byReference[invitationB]?.status, DeliveryOutboxStatus.pending);
      },
    );
  });
}
