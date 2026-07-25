import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/delivery_outbox_store.dart';
import 'package:hivra_app/services/delivery_transport_contract.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  group('DeliveryOutboxStore', () {
    late Directory tempHome;
    late DeliveryOutboxStore store;
    const capsuleHex =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra_outbox_test_');
      store = DeliveryOutboxStore(
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
    });

    tearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('enqueue is idempotent and writes capsule-scoped outbox file', () async {
      final now = DateTime.utc(2026, 7, 5, 10);

      await store.enqueue(
        capsuleHex: capsuleHex,
        transport: DeliveryTransportId.nostr,
        kind: DeliveryOutboxKind.relationshipBroken,
        reason: DeliveryOutboxReason.localRelationshipBreak,
        now: now,
      );
      await store.enqueue(
        capsuleHex: capsuleHex,
        transport: DeliveryTransportId.nostr,
        kind: DeliveryOutboxKind.relationshipBroken,
        reason: DeliveryOutboxReason.localRelationshipBreak,
        now: now.add(const Duration(seconds: 5)),
      );

      final items = await store.load(capsuleHex);
      expect(items, hasLength(1));
      expect(items.single.id, hasLength(64));
      expect(items.single.transport, DeliveryTransportId.nostr);
      expect(items.single.kind, DeliveryOutboxKind.relationshipBroken);
      expect(items.single.reason, DeliveryOutboxReason.localRelationshipBreak);
      expect(items.single.status, DeliveryOutboxStatus.pending);
      expect(items.single.nextAttemptAt, now.add(const Duration(seconds: 5)));

      final file = File(
        '${tempHome.path}/Documents/Hivra/capsules/$capsuleHex/delivery_outbox.json',
      );
      expect(await file.exists(), isTrue);
    });

    test('due, markAttempt, and markPublished are deterministic', () async {
      final now = DateTime.utc(2026, 7, 5, 10);
      await store.enqueue(
        capsuleHex: capsuleHex,
        transport: DeliveryTransportId.nostr,
        kind: DeliveryOutboxKind.invitationSent,
        reason: DeliveryOutboxReason.sendInvitationRetry,
        now: now,
      );

      final due = await store.due(capsuleHex: capsuleHex, now: now);
      expect(due, hasLength(1));

      await store.markAttempt(
        capsuleHex: capsuleHex,
        itemId: due.single.id,
        nextAttemptAt: now.add(const Duration(seconds: 20)),
        lastError: 'relay timeout',
      );
      final afterAttempt = await store.load(capsuleHex);
      expect(afterAttempt.single.attempts, 1);
      expect(afterAttempt.single.lastError, 'relay timeout');
      expect(await store.due(capsuleHex: capsuleHex, now: now), isEmpty);

      await store.markAttempt(
        capsuleHex: capsuleHex,
        itemId: due.single.id,
        nextAttemptAt: now.add(const Duration(seconds: 40)),
      );
      final afterSuccessAttempt = await store.load(capsuleHex);
      expect(afterSuccessAttempt.single.attempts, 2);
      expect(afterSuccessAttempt.single.lastError, isNull);

      await store.markPublished(
        capsuleHex: capsuleHex,
        itemId: due.single.id,
        nextAttemptAt: now.add(const Duration(minutes: 1)),
      );
      expect(
        (await store.load(capsuleHex)).single.status,
        DeliveryOutboxStatus.published,
      );
    });

    test('migrates legacy delivered state to relay publication', () {
      final item = DeliveryOutboxItem.fromJson(<String, Object?>{
        'id': 'legacy',
        'capsule_hex': capsuleHex,
        'transport': DeliveryTransportId.nostr,
        'kind': DeliveryOutboxKind.invitationSent,
        'reason': DeliveryOutboxReason.sendInvitationRetry,
        'created_at': '2026-07-05T10:00:00Z',
        'next_attempt_at': '2026-07-05T10:00:00Z',
        'attempts': 0,
        'status': 'delivered',
        'last_error': null,
      });

      expect(item?.status, DeliveryOutboxStatus.published);
    });

    test('revives legacy retry-exhausted core delivery', () {
      final item = DeliveryOutboxItem.fromJson(<String, Object?>{
        'id': 'legacy-dead',
        'capsule_hex': capsuleHex,
        'transport': DeliveryTransportId.nostr,
        'kind': DeliveryOutboxKind.invitationSent,
        'reason': DeliveryOutboxReason.sendInvitationRetry,
        'created_at': '2026-07-05T10:00:00Z',
        'next_attempt_at': '2026-07-05T10:00:00Z',
        'attempts': 7,
        'status': 'dead',
      });

      expect(item?.status, DeliveryOutboxStatus.pending);
      expect(item?.attempts, 7);
    });

    test(
      'keeps distinct immutable invitation facts as distinct outbox items',
      () async {
        final now = DateTime.utc(2026, 7, 5, 10);
        const invitationA =
            '1111111111111111111111111111111111111111111111111111111111111111';
        const invitationB =
            '2222222222222222222222222222222222222222222222222222222222222222';

        await store.enqueue(
          capsuleHex: capsuleHex,
          transport: DeliveryTransportId.nostr,
          kind: DeliveryOutboxKind.invitationSent,
          reason: DeliveryOutboxReason.sendInvitationRetry,
          deliveryReference: invitationA,
          now: now,
        );
        await store.enqueue(
          capsuleHex: capsuleHex,
          transport: DeliveryTransportId.nostr,
          kind: DeliveryOutboxKind.invitationSent,
          reason: DeliveryOutboxReason.sendInvitationRetry,
          deliveryReference: invitationB,
          now: now,
        );

        final items = await store.load(capsuleHex);
        expect(items, hasLength(2));
        expect(
          items.map((item) => item.deliveryReference),
          containsAll(<String>[invitationA, invitationB]),
        );
      },
    );
  });
}
