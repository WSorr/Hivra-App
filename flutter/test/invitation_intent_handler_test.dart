import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
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
      expect(
          results[0].message, 'Fetched invitation deliveries: 2 new event(s)');
      expect(
          results[1].message, 'Fetched invitation deliveries: 2 new event(s)');
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
      expect(first.message, 'No new invitation deliveries');
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
      expect(secondCapsuleResult.message, 'No new invitation deliveries');
      expect(firstCapsuleRepeatResult.message, 'Skipped duplicate quick fetch');
    });
  });

  group('InvitationIntentHandler expiry sweep', () {
    test('auto-expires only overdue outgoing pending invitations', () async {
      String idForByte(int value) =>
          base64.encode(Uint8List.fromList(List<int>.filled(32, value)));

      final now = DateTime.now();
      final overdueOutgoingPending = Invitation(
        id: idForByte(11),
        fromPubkey: idForByte(21),
        toPubkey: idForByte(31),
        kind: StarterKind.juice,
        status: InvitationStatus.pending,
        sentAt: now.subtract(const Duration(hours: 26)),
        expiresAt: now.subtract(const Duration(hours: 2)),
      );
      final freshOutgoingPending = Invitation(
        id: idForByte(12),
        fromPubkey: idForByte(22),
        toPubkey: idForByte(32),
        kind: StarterKind.spark,
        status: InvitationStatus.pending,
        sentAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(hours: 23)),
      );
      final overdueIncomingPending = Invitation(
        id: idForByte(13),
        fromPubkey: idForByte(23),
        toPubkey: null,
        kind: StarterKind.seed,
        status: InvitationStatus.pending,
        sentAt: now.subtract(const Duration(hours: 30)),
        expiresAt: now.subtract(const Duration(hours: 6)),
      );
      final overdueOutgoingAccepted = Invitation(
        id: idForByte(14),
        fromPubkey: idForByte(24),
        toPubkey: idForByte(34),
        kind: StarterKind.pulse,
        status: InvitationStatus.accepted,
        sentAt: now.subtract(const Duration(hours: 30)),
        expiresAt: now.subtract(const Duration(hours: 6)),
      );

      final actions = _FakeInvitationActionsService();
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => <Invitation>[
          overdueOutgoingPending,
          freshOutgoingPending,
          overdueIncomingPending,
          overdueOutgoingAccepted,
        ],
        fetchInvitationsQuickAction: () async =>
            const InvitationWorkerResult(code: 0),
      );

      final result = await handler.fetchInvitationsQuick();

      expect(result.code, 0);
      expect(
          actions.canceledInvitationIds, <String>[overdueOutgoingPending.id]);
    });

    test('runs expiry sweep even when quick fetch is skipped by cooldown',
        () async {
      String idForByte(int value) =>
          base64.encode(Uint8List.fromList(List<int>.filled(32, value)));

      final now = DateTime.now();
      final candidate = Invitation(
        id: idForByte(51),
        fromPubkey: idForByte(61),
        toPubkey: idForByte(71),
        kind: StarterKind.kick,
        status: InvitationStatus.pending,
        sentAt: now.subtract(const Duration(hours: 20)),
        expiresAt: now.add(const Duration(hours: 4)),
      );
      var invitations = <Invitation>[candidate];

      final actions = _FakeInvitationActionsService();
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'capsule-expiry-cooldown',
        invitationsLoader: () => invitations,
        fetchInvitationsQuickAction: () async =>
            const InvitationWorkerResult(code: 0),
      );

      final first = await handler.fetchInvitationsQuick();
      expect(first.message, 'No new invitation deliveries');
      expect(actions.canceledInvitationIds, isEmpty);

      invitations = <Invitation>[
        Invitation(
          id: candidate.id,
          fromPubkey: candidate.fromPubkey,
          toPubkey: candidate.toPubkey,
          kind: candidate.kind,
          status: candidate.status,
          sentAt: candidate.sentAt,
          expiresAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final second = await handler.fetchInvitationsQuick();
      expect(second.message, 'Skipped duplicate quick fetch');
      expect(actions.canceledInvitationIds, <String>[candidate.id]);
    });

    test('runs expiry sweep even when full fetch returns receive failure',
        () async {
      String idForByte(int value) =>
          base64.encode(Uint8List.fromList(List<int>.filled(32, value)));

      final now = DateTime.now();
      final overdueOutgoingPending = Invitation(
        id: idForByte(81),
        fromPubkey: idForByte(91),
        toPubkey: idForByte(101),
        kind: StarterKind.spark,
        status: InvitationStatus.pending,
        sentAt: now.subtract(const Duration(hours: 30)),
        expiresAt: now.subtract(const Duration(hours: 6)),
      );

      final actions = _FakeInvitationActionsService();
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => <Invitation>[overdueOutgoingPending],
        fetchInvitationsAction: () async =>
            const InvitationWorkerResult(code: -5),
      );

      final result = await handler.fetchInvitations();

      expect(result.code, -5);
      expect(result.message, 'Failed to fetch invitation deliveries');
      expect(
          actions.canceledInvitationIds, <String>[overdueOutgoingPending.id]);
    });
  });

  group('InvitationIntentHandler send semantics', () {
    test('treats timeout with local ledger as recorded pending', () async {
      final actions = _FakeInvitationActionsService()
        ..sendResult = const InvitationWorkerResult(
          code: -12,
          ledgerJson: '{"owner":"x","events":[]}',
          lastError:
              'Send invitation failed: delivery transport rejected message (code -12)',
        );
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
      );

      final result = await handler.sendInvitation(Uint8List(32), 0);
      expect(result.code, 0);
      expect(result.message, contains('timed out'));
      expect(result.message, contains('Local pending invitation is recorded'));
    });

    test('keeps timeout as failure when worker ledger is missing', () async {
      final actions = _FakeInvitationActionsService()
        ..sendResult = const InvitationWorkerResult(
          code: -12,
          ledgerJson: null,
          lastError:
              'Send invitation failed: delivery transport rejected message (code -12)',
        );
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
      );

      final result = await handler.sendInvitation(Uint8List(32), 0);
      expect(result.code, -12);
      expect(result.message, contains('timed out'));
      expect(result.message,
          isNot(contains('Local pending invitation is recorded')));
    });
  });
}

class _FakeInvitationActionsService extends InvitationActionsService {
  _FakeInvitationActionsService()
      : super(runtime: _NoopInvitationActionsRuntime());

  final List<String> canceledInvitationIds = <String>[];
  InvitationWorkerResult sendResult = const InvitationWorkerResult(code: 0);

  @override
  Future<InvitationWorkerResult> sendInvitation(
    Uint8List toPubkey,
    int starterSlot,
  ) async {
    return sendResult;
  }

  @override
  Future<bool> cancelInvitation(Uint8List invitationId) async {
    canceledInvitationIds.add(base64.encode(invitationId));
    return true;
  }
}

class _NoopInvitationActionsRuntime implements InvitationActionsRuntime {
  @override
  Future<bool> applyLedgerSnapshotIfNotStale(String ledgerJson) async => true;

  @override
  bool expireInvitation(Uint8List invitationId) => true;

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs() async =>
      <String, Object?>{};

  @override
  Future<void> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson,
  ) async {}

  @override
  Future<bool> persistLedgerSnapshot() async => true;

  @override
  Future<String?> resolveActiveCapsuleHex() async => 'test';
}
