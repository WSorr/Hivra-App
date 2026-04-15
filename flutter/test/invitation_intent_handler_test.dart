import 'dart:convert';
import 'dart:async';
import 'dart:collection';
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

    test('does not apply cooldown after failed quick fetch', () async {
      var calls = 0;
      final handler = InvitationIntentHandler(
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'capsule-fail',
        fetchInvitationsQuickAction: () async {
          calls += 1;
          if (calls == 1) {
            return const InvitationWorkerResult(code: -5);
          }
          return const InvitationWorkerResult(code: 0);
        },
      );

      final first = await handler.fetchInvitationsQuick();
      final second = await handler.fetchInvitationsQuick();

      expect(calls, 2);
      expect(first.code, -5);
      expect(first.message, 'Failed to fetch invitation deliveries [code: -5]');
      expect(second.code, 0);
      expect(second.message, 'No new invitation deliveries');
    });

    test('does not apply cooldown dedupe for unknown capsule identity',
        () async {
      var calls = 0;
      final handler = InvitationIntentHandler(
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'unknown',
        fetchInvitationsQuickAction: () async {
          calls += 1;
          return const InvitationWorkerResult(code: 0);
        },
      );

      final first = await handler.fetchInvitationsQuick();
      final second = await handler.fetchInvitationsQuick();

      expect(calls, 2);
      expect(first.message, 'No new invitation deliveries');
      expect(second.message, 'No new invitation deliveries');
    });

    test('does not coalesce concurrent quick fetch for unknown capsule',
        () async {
      var calls = 0;
      final completerA = Completer<InvitationWorkerResult>();
      final completerB = Completer<InvitationWorkerResult>();
      final queue = Queue<Completer<InvitationWorkerResult>>()
        ..add(completerA)
        ..add(completerB);
      final handler = InvitationIntentHandler(
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'unknown',
        fetchInvitationsQuickAction: () {
          calls += 1;
          return queue.removeFirst().future;
        },
      );

      final first = handler.fetchInvitationsQuick();
      final second = handler.fetchInvitationsQuick();
      expect(calls, 2);

      completerA.complete(const InvitationWorkerResult(code: 1));
      completerB.complete(const InvitationWorkerResult(code: 2));
      final results = await Future.wait(<Future<InvitationIntentResult>>[
        first,
        second,
      ]);

      expect(results, hasLength(2));
      expect(results[0].code, 1);
      expect(results[1].code, 2);
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
      final overdueOutgoingProjectionExpired = Invitation(
        id: idForByte(15),
        fromPubkey: idForByte(25),
        toPubkey: idForByte(35),
        kind: StarterKind.kick,
        status: InvitationStatus.expired,
        sentAt: now.subtract(const Duration(hours: 30)),
        expiresAt: now.subtract(const Duration(hours: 6)),
        respondedAt: now.subtract(const Duration(hours: 6)),
      );
      final overdueOutgoingLedgerExpired = Invitation(
        id: idForByte(16),
        fromPubkey: idForByte(26),
        toPubkey: idForByte(36),
        kind: StarterKind.seed,
        status: InvitationStatus.expired,
        sentAt: now.subtract(const Duration(hours: 30)),
        expiresAt: now.subtract(const Duration(hours: 6)),
        respondedAt: now.subtract(const Duration(hours: 5)),
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
          overdueOutgoingProjectionExpired,
          overdueOutgoingLedgerExpired,
        ],
        fetchInvitationsQuickAction: () async =>
            const InvitationWorkerResult(code: 0),
      );

      final result = await handler.fetchInvitationsQuick();

      expect(result.code, 0);
      expect(actions.canceledInvitationIds, <String>[
        overdueOutgoingPending.id,
        overdueOutgoingProjectionExpired.id,
      ]);
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
      expect(
          result.message, 'Failed to fetch invitation deliveries [code: -5]');
      expect(
          actions.canceledInvitationIds, <String>[overdueOutgoingPending.id]);
    });

    test('includes ffi diagnostics on receive failure when available',
        () async {
      final handler = InvitationIntentHandler(
        delivery: const InvitationDeliveryService(),
        fetchInvitationsAction: () async => const InvitationWorkerResult(
          code: -5,
          lastError: 'receive failed: relay timeout',
        ),
      );

      final result = await handler.fetchInvitations();

      expect(result.code, -5);
      expect(
        result.message,
        'Failed to fetch invitation deliveries [code: -5; ffi: receive failed: relay timeout]',
      );
    });
  });

  group('InvitationIntentHandler send semantics', () {
    test('coalesces concurrent duplicate sends for same capsule slot/peer',
        () async {
      final actions = _FakeInvitationActionsService();
      final completer = Completer<InvitationWorkerResult>();
      actions.onSend = (_, __) => completer.future;
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'capsule-send-a',
      );
      final recipient = Uint8List.fromList(List<int>.filled(32, 42));

      final first = handler.sendInvitation(recipient, 1);
      final second = handler.sendInvitation(recipient, 1);
      expect(actions.sendCalls, 1);

      completer.complete(const InvitationWorkerResult(code: 0));
      final results = await Future.wait(<Future<InvitationIntentResult>>[
        first,
        second,
      ]);

      expect(results[0].code, 0);
      expect(results[1].code, 0);
      expect(results[0].message, 'Invitation sent');
      expect(results[1].message, 'Invitation sent');
    });

    test('allows repeated send after previous in-flight send completes',
        () async {
      final actions = _FakeInvitationActionsService();
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        activeCapsuleHexResolver: () => 'capsule-send-b',
      );
      final recipient = Uint8List.fromList(List<int>.filled(32, 43));

      final first = await handler.sendInvitation(recipient, 1);
      final second = await handler.sendInvitation(recipient, 1);

      expect(first.code, 0);
      expect(second.code, 0);
      expect(actions.sendCalls, 2);
    });

    test('treats timeout as recorded when new pending appears after send',
        () async {
      final recipient = Uint8List.fromList(List<int>.filled(32, 51));
      final recipientB64 = base64.encode(recipient);
      List<Invitation> projectedInvitations = <Invitation>[];
      final actions = _FakeInvitationActionsService()
        ..onSend = (_, __) async {
          projectedInvitations = <Invitation>[
            Invitation(
              id: base64.encode(Uint8List.fromList(List<int>.filled(32, 90))),
              fromPubkey:
                  base64.encode(Uint8List.fromList(List<int>.filled(32, 91))),
              toPubkey: recipientB64,
              kind: StarterKind.juice,
              starterSlot: 0,
              status: InvitationStatus.pending,
              sentAt: DateTime.now(),
            ),
          ];
          return const InvitationWorkerResult(
            code: -12,
            ledgerJson: '{"owner":"x","events":[]}',
            lastError:
                'Send invitation failed: delivery transport rejected message (code -12)',
          );
        };
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => projectedInvitations,
      );

      final result = await handler.sendInvitation(recipient, 0);
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

    test(
        'keeps timeout as failure when worker ledger exists but no new pending is projected',
        () async {
      final recipient = Uint8List.fromList(List<int>.filled(32, 57));
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
        invitationsLoader: () => const <Invitation>[],
      );

      final result = await handler.sendInvitation(recipient, 0);
      expect(result.code, -12);
      expect(result.message, contains('timed out'));
      expect(result.message,
          isNot(contains('Local pending invitation is recorded')));
    });

    test('does not treat projection-only pending as confirmed delivery',
        () async {
      final recipient = Uint8List.fromList(List<int>.filled(32, 52));
      final recipientB64 = base64.encode(recipient);
      List<Invitation> projectedInvitations = <Invitation>[];
      final actions = _FakeInvitationActionsService()
        ..onSend = (_, __) async {
          projectedInvitations = <Invitation>[
            Invitation(
              id: base64.encode(Uint8List.fromList(List<int>.filled(32, 91))),
              fromPubkey:
                  base64.encode(Uint8List.fromList(List<int>.filled(32, 92))),
              toPubkey: recipientB64,
              kind: StarterKind.juice,
              starterSlot: 2,
              status: InvitationStatus.pending,
              sentAt: DateTime.now(),
            ),
          ];
          return const InvitationWorkerResult(
            code: -1003,
            ledgerJson: null,
            lastError: 'send worker timeout',
          );
        };
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => projectedInvitations,
      );

      final result = await handler.sendInvitation(recipient, 2);
      expect(result.code, -1003);
      expect(result.message, contains('was not confirmed'));
      expect(result.message, contains('code: -1003'));
      expect(actions.fetchQuickCalls, 1);
    });

    test('does not treat pre-existing pending as newly recorded pending',
        () async {
      final recipient = Uint8List.fromList(List<int>.filled(32, 54));
      final recipientB64 = base64.encode(recipient);
      final existingPendingId =
          base64.encode(Uint8List.fromList(List<int>.filled(32, 95)));
      final projectedInvitations = <Invitation>[
        Invitation(
          id: existingPendingId,
          fromPubkey:
              base64.encode(Uint8List.fromList(List<int>.filled(32, 96))),
          toPubkey: recipientB64,
          kind: StarterKind.kick,
          starterSlot: 4,
          status: InvitationStatus.pending,
          sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ];
      final actions = _FakeInvitationActionsService()
        ..sendResult = const InvitationWorkerResult(
          code: -1003,
          ledgerJson: null,
          lastError: 'send worker timeout',
        )
        ..onFetchQuick = () async => const InvitationWorkerResult(code: 0);
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => projectedInvitations,
      );

      final result = await handler.sendInvitation(recipient, 4);
      expect(result.code, -1003);
      expect(result.message,
          isNot(contains('Local pending invitation is recorded')));
      expect(actions.fetchQuickCalls, 1);
    });

    test(
        'does not treat old pending that appears late in projection as newly recorded',
        () async {
      final recipient = Uint8List.fromList(List<int>.filled(32, 55));
      final recipientB64 = base64.encode(recipient);
      List<Invitation> projectedInvitations = <Invitation>[];
      final actions = _FakeInvitationActionsService()
        ..onSend = (_, __) async {
          projectedInvitations = <Invitation>[
            Invitation(
              id: base64.encode(Uint8List.fromList(List<int>.filled(32, 97))),
              fromPubkey:
                  base64.encode(Uint8List.fromList(List<int>.filled(32, 98))),
              toPubkey: recipientB64,
              kind: StarterKind.seed,
              starterSlot: 1,
              status: InvitationStatus.pending,
              sentAt: DateTime.now().subtract(const Duration(minutes: 5)),
            ),
          ];
          return const InvitationWorkerResult(
            code: -1003,
            ledgerJson: null,
            lastError: 'send worker timeout',
          );
        }
        ..onFetchQuick = () async => const InvitationWorkerResult(code: 0);
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => projectedInvitations,
      );

      final result = await handler.sendInvitation(recipient, 1);
      expect(result.code, -1003);
      expect(result.message,
          isNot(contains('Local pending invitation is recorded')));
      expect(actions.fetchQuickCalls, 1);
    });

    test(
        'reconciles timeout via quick fetch and marks pending as locally recorded',
        () async {
      final recipient = Uint8List.fromList(List<int>.filled(32, 53));
      final recipientB64 = base64.encode(recipient);
      List<Invitation> projectedInvitations = <Invitation>[];
      final actions = _FakeInvitationActionsService()
        ..sendResult = const InvitationWorkerResult(
          code: -1003,
          ledgerJson: null,
          lastError: 'send worker timeout',
        )
        ..onFetchQuick = () async {
          projectedInvitations = <Invitation>[
            Invitation(
              id: base64.encode(Uint8List.fromList(List<int>.filled(32, 93))),
              fromPubkey:
                  base64.encode(Uint8List.fromList(List<int>.filled(32, 94))),
              toPubkey: recipientB64,
              kind: StarterKind.spark,
              starterSlot: 3,
              status: InvitationStatus.pending,
              sentAt: DateTime.now(),
            ),
          ];
          return const InvitationWorkerResult(code: 1);
        };
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => projectedInvitations,
      );

      final result = await handler.sendInvitation(recipient, 3);
      expect(result.code, 0);
      expect(result.message, contains('Local pending invitation is recorded'));
      expect(actions.fetchQuickCalls, 1);
    });
  });

  group('InvitationIntentHandler accept semantics', () {
    test('short-circuits accept when invitation is already terminal locally',
        () async {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 61));
      final actions = _FakeInvitationActionsService()
        ..acceptResult = const InvitationWorkerResult(code: -12);
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => <Invitation>[
          Invitation(
            id: base64.encode(invitationId),
            fromPubkey:
                base64.encode(Uint8List.fromList(List<int>.filled(32, 62))),
            toPubkey: null,
            kind: StarterKind.juice,
            status: InvitationStatus.accepted,
            sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
            respondedAt: DateTime.now(),
          ),
        ],
      );

      final result = await handler.acceptInvitation(
        invitationId,
        Uint8List.fromList(List<int>.filled(32, 62)),
      );
      expect(result.code, 0);
      expect(result.message, 'Invitation already resolved');
      expect(actions.acceptCalls, 0);
    });

    test('rejects accept for outgoing invitation context', () async {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 63));
      final actions = _FakeInvitationActionsService();
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => <Invitation>[
          Invitation(
            id: base64.encode(invitationId),
            fromPubkey:
                base64.encode(Uint8List.fromList(List<int>.filled(32, 64))),
            toPubkey:
                base64.encode(Uint8List.fromList(List<int>.filled(32, 65))),
            kind: StarterKind.juice,
            status: InvitationStatus.pending,
            sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ],
      );

      final result = await handler.acceptInvitation(
        invitationId,
        Uint8List.fromList(List<int>.filled(32, 64)),
      );
      expect(result.code, -1);
      expect(result.message, 'Only incoming invitations can be accepted');
      expect(actions.acceptCalls, 0);
    });

    test('treats transport timeout with local ledger as recorded acceptance',
        () async {
      final actions = _FakeInvitationActionsService()
        ..acceptResult = const InvitationWorkerResult(
          code: -12,
          ledgerJson: '{"owner":"x","events":[]}',
          lastError:
              'Accept invitation delivery failed but local acceptance is recorded (code -12)',
        );
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
      );

      final result =
          await handler.acceptInvitation(Uint8List(32), Uint8List(32));
      expect(result.code, 0);
      expect(result.message, contains('timed out'));
      expect(result.message, contains('Local acceptance is recorded'));
    });

    test(
        'keeps transport timeout as failure when worker ledger payload is missing',
        () async {
      final actions = _FakeInvitationActionsService()
        ..acceptResult = const InvitationWorkerResult(
          code: -12,
          ledgerJson: null,
          lastError:
              'Accept invitation delivery failed but local acceptance is recorded (code -12)',
        );
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
      );

      final result =
          await handler.acceptInvitation(Uint8List(32), Uint8List(32));
      expect(result.code, -12);
      expect(result.message, contains('timed out'));
      expect(result.message, isNot(contains('Local acceptance is recorded')));
    });

    test('treats worker timeout as recorded when local accepted is projected',
        () async {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 66));
      final invitationIdB64 = base64.encode(invitationId);
      final fromPubkey = Uint8List.fromList(List<int>.filled(32, 67));
      final fromPubkeyB64 = base64.encode(fromPubkey);
      List<Invitation> projectedInvitations = <Invitation>[
        Invitation(
          id: invitationIdB64,
          fromPubkey: fromPubkeyB64,
          toPubkey: null,
          kind: StarterKind.spark,
          status: InvitationStatus.pending,
          sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ];
      final actions = _FakeInvitationActionsService()
        ..onAccept = (_, __) async {
          projectedInvitations = <Invitation>[
            Invitation(
              id: invitationIdB64,
              fromPubkey: fromPubkeyB64,
              toPubkey: null,
              kind: StarterKind.spark,
              status: InvitationStatus.accepted,
              sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
              respondedAt: DateTime.now(),
            ),
          ];
          return const InvitationWorkerResult(
            code: -1003,
            ledgerJson: null,
            lastError: 'accept worker timeout',
          );
        };
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => projectedInvitations,
      );

      final result = await handler.acceptInvitation(invitationId, fromPubkey);
      expect(result.code, 0);
      expect(result.message, contains('Local acceptance is recorded'));
      expect(result.message, contains('code: -1003'));
    });
  });

  group('InvitationIntentHandler reject semantics', () {
    Invitation incomingPendingInvitation() {
      final now = DateTime.now();
      final invitationId = Uint8List.fromList(List<int>.filled(32, 41));
      return Invitation(
        id: base64.encode(invitationId),
        fromPubkey: base64.encode(Uint8List.fromList(List<int>.filled(32, 42))),
        toPubkey: null,
        kind: StarterKind.juice,
        status: InvitationStatus.pending,
        sentAt: now.subtract(const Duration(minutes: 1)),
      );
    }

    test('treats transport timeout with local ledger as recorded rejection',
        () async {
      final invitation = incomingPendingInvitation();
      final actions = _FakeInvitationActionsService()
        ..rejectResult = const InvitationWorkerResult(
          code: -12,
          ledgerJson: '{"owner":"x","events":[]}',
          lastError:
              'Reject invitation delivery failed but local rejection is recorded (code -12)',
        );
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
      );

      final result = await handler.rejectInvitation(invitation);
      expect(result.code, 0);
      expect(result.message, contains('timed out'));
      expect(result.message, contains('Local rejection is recorded'));
    });

    test(
        'keeps reject timeout as failure when worker ledger payload is missing',
        () async {
      final invitation = incomingPendingInvitation();
      final actions = _FakeInvitationActionsService()
        ..rejectResult = const InvitationWorkerResult(
          code: -12,
          ledgerJson: null,
          lastError:
              'Reject invitation delivery failed but local rejection is recorded (code -12)',
        );
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
      );

      final result = await handler.rejectInvitation(invitation);
      expect(result.code, -1);
      expect(result.message, contains('timed out'));
      expect(result.message, isNot(contains('Local rejection is recorded')));
    });

    test('short-circuits reject when invitation is already terminal locally',
        () async {
      final invitation = Invitation(
        id: base64.encode(Uint8List.fromList(List<int>.filled(32, 71))),
        fromPubkey: base64.encode(Uint8List.fromList(List<int>.filled(32, 72))),
        toPubkey: null,
        kind: StarterKind.spark,
        status: InvitationStatus.rejected,
        sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
        respondedAt: DateTime.now(),
      );
      final actions = _FakeInvitationActionsService()
        ..rejectResult = const InvitationWorkerResult(code: -12);
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => <Invitation>[invitation],
      );

      final result = await handler.rejectInvitation(invitation);
      expect(result.code, 0);
      expect(result.message, 'Invitation already resolved');
      expect(actions.rejectCalls, 0);
    });

    test('rejects reject for outgoing invitation context', () async {
      final invitation = Invitation(
        id: base64.encode(Uint8List.fromList(List<int>.filled(32, 73))),
        fromPubkey: base64.encode(Uint8List.fromList(List<int>.filled(32, 74))),
        toPubkey: base64.encode(Uint8List.fromList(List<int>.filled(32, 75))),
        kind: StarterKind.pulse,
        status: InvitationStatus.pending,
        sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final actions = _FakeInvitationActionsService();
      final handler = InvitationIntentHandler(
        actions: actions,
        delivery: const InvitationDeliveryService(),
        invitationsLoader: () => <Invitation>[invitation],
      );

      final result = await handler.rejectInvitation(invitation);
      expect(result.code, -1);
      expect(result.message, 'Only incoming invitations can be rejected');
      expect(actions.rejectCalls, 0);
    });
  });
}

class _FakeInvitationActionsService extends InvitationActionsService {
  _FakeInvitationActionsService()
      : super(runtime: _NoopInvitationActionsRuntime());

  final List<String> canceledInvitationIds = <String>[];
  InvitationWorkerResult sendResult = const InvitationWorkerResult(code: 0);
  Future<InvitationWorkerResult> Function(Uint8List toPubkey, int starterSlot)?
      onSend;
  Future<InvitationWorkerResult> Function(
    Uint8List invitationId,
    Uint8List fromPubkey,
  )? onAccept;
  Future<InvitationWorkerResult> Function(
    Uint8List invitationId,
    int reason,
  )? onReject;
  int sendCalls = 0;
  InvitationWorkerResult acceptResult = const InvitationWorkerResult(code: 0);
  InvitationWorkerResult rejectResult = const InvitationWorkerResult(code: 0);
  InvitationWorkerResult fetchQuickResult =
      const InvitationWorkerResult(code: -5);
  Future<InvitationWorkerResult> Function()? onFetchQuick;
  int acceptCalls = 0;
  int rejectCalls = 0;
  int fetchQuickCalls = 0;

  @override
  Future<InvitationWorkerResult> sendInvitation(
      Uint8List toPubkey, int starterSlot,
      {String? capsuleHex}) async {
    sendCalls += 1;
    final handler = onSend;
    if (handler != null) {
      return handler(toPubkey, starterSlot);
    }
    return sendResult;
  }

  @override
  Future<InvitationWorkerResult> acceptInvitation(
      Uint8List invitationId, Uint8List fromPubkey,
      {String? capsuleHex}) async {
    acceptCalls += 1;
    final handler = onAccept;
    if (handler != null) {
      return handler(invitationId, fromPubkey);
    }
    return acceptResult;
  }

  @override
  Future<InvitationWorkerResult> rejectInvitation(
      Uint8List invitationId, int reason,
      {String? capsuleHex}) async {
    rejectCalls += 1;
    final handler = onReject;
    if (handler != null) {
      return handler(invitationId, reason);
    }
    return rejectResult;
  }

  @override
  Future<InvitationWorkerResult> fetchInvitationsQuick(
      {String? capsuleHex}) async {
    fetchQuickCalls += 1;
    final handler = onFetchQuick;
    if (handler != null) {
      return handler();
    }
    return fetchQuickResult;
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
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs({
    String? capsuleHex,
  }) async =>
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
