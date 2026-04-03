import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/invitation_actions_service.dart';
import 'package:hivra_app/services/invitation_delivery_service.dart';
import 'package:hivra_app/services/invitation_intent_handler.dart';

void main() {
  group('InvitationIntentHandler quick fetch dedupe', () {
    test('coalesces concurrent quick fetch for same capsule', () async {
      var calls = 0;
      final completer = Completer<InvitationWorkerResult>();
      final handler = InvitationIntentHandler(
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'capsule-a',
        fetchInvitationsQuickAction: () {
          calls += 1;
          return completer.future;
        },
      );

      final first = handler.fetchInvitationsQuick();
      final second = handler.fetchInvitationsQuick();
      expect(calls, 1);

      completer.complete(const InvitationWorkerResult(code: 2));
      final results = await Future.wait(<Future<InvitationIntentResult>>[
        first,
        second,
      ]);

      expect(results, hasLength(2));
      expect(results[0].code, 2);
      expect(results[1].code, 2);
      expect(results[0].message, 'Fetched invitation deliveries: 2 new event(s)');
      expect(results[1].message, 'Fetched invitation deliveries: 2 new event(s)');
    });

    test('skips repeated quick fetch within cooldown for same capsule',
        () async {
      var calls = 0;
      final handler = InvitationIntentHandler(
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'capsule-b',
        fetchInvitationsQuickAction: () async {
          calls += 1;
          return const InvitationWorkerResult(code: 0);
        },
      );

      final first = await handler.fetchInvitationsQuick();
      final second = await handler.fetchInvitationsQuick();

      expect(calls, 1);
      expect(first.code, 0);
      expect(first.message, 'Fetched invitation deliveries: 0 new event(s)');
      expect(second.code, 0);
      expect(second.message, 'Skipped duplicate quick fetch');
    });

    test('tracks cooldown independently per capsule', () async {
      var calls = 0;
      var activeCapsule = 'capsule-c1';
      final handler = InvitationIntentHandler(
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => activeCapsule,
        fetchInvitationsQuickAction: () async {
          calls += 1;
          return const InvitationWorkerResult(code: 0);
        },
      );

      await handler.fetchInvitationsQuick();
      activeCapsule = 'capsule-c2';
      final secondCapsuleResult = await handler.fetchInvitationsQuick();
      activeCapsule = 'capsule-c1';
      final firstCapsuleRepeatResult = await handler.fetchInvitationsQuick();

      expect(calls, 2);
      expect(secondCapsuleResult.message,
          'Fetched invitation deliveries: 0 new event(s)');
      expect(firstCapsuleRepeatResult.message, 'Skipped duplicate quick fetch');
    });
  });
}

