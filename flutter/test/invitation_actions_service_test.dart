import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
import 'package:hivra_app/services/capsule_delivery_lifecycle_service.dart';
import 'package:hivra_app/services/delivery_outbox_store.dart';
import 'package:hivra_app/services/invitation_actions_service.dart';

void main() {
  group('InvitationActionsService worker ledger application', () {
    test(
      'rejects a retry whose worker bootstrap belongs to another capsule',
      () async {
        const requestedCapsule =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        const wrongCapsule =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        final runtime = _FakeInvitationActionsRuntime(
          activeCapsuleHex: requestedCapsule,
          workerBootstrap: <String, Object?>{
            'activeCapsuleHex': wrongCapsule,
            'seed': Uint8List(32),
          },
        );
        final service = InvitationActionsService(runtime: runtime);

        final result = await service.retryPendingDelivery(
          capsuleHex: requestedCapsule,
          item: DeliveryOutboxItem(
            id: 'test',
            capsuleHex: requestedCapsule,
            transport: 'nostr',
            kind: 'InvitationSent',
            reason: 'test',
            createdAt: DateTime.utc(2026),
            nextAttemptAt: DateTime.utc(2026),
            attempts: 0,
            status: DeliveryOutboxStatus.pending,
          ),
        );

        expect(result.code, -1004);
        expect(runtime.workerBootstrapRequests, <String?>[requestedCapsule]);
      },
    );

    test(
      'restores selected runtime after persisting non-active worker ledger',
      () async {
        final runtime = _FakeInvitationActionsRuntime(
          activeCapsuleHex:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        final service = InvitationActionsService(
          runtime: runtime,
          workerQueue: CapsuleWorkerQueue(),
        );
        const workerCapsule =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

        await service.applyWorkerLedgerResultForTest(
          bootstrapActiveHex: workerCapsule,
          ledgerJson: '{"owner":"b"}',
          capsuleStateJson: '{"version":1}',
        );

        expect(runtime.persistedLedgers, <String, String>{
          workerCapsule: '{"owner":"b"}',
        });
        expect(runtime.appliedLedgers, isEmpty);
        expect(runtime.persistedStates[workerCapsule], '{"version":1}');
        expect(runtime.bootstrapActiveCalls, 1);
      },
    );

    test(
      'applies active worker ledger directly without re-bootstrap',
      () async {
        const activeCapsule =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        final runtime = _FakeInvitationActionsRuntime(
          activeCapsuleHex: activeCapsule,
        );
        final service = InvitationActionsService(
          runtime: runtime,
          workerQueue: CapsuleWorkerQueue(),
        );

        await service.applyWorkerLedgerResultForTest(
          bootstrapActiveHex: activeCapsule,
          ledgerJson: '{"owner":"a"}',
        );

        expect(runtime.persistedLedgers, isEmpty);
        expect(runtime.appliedLedgers, <String>['{"owner":"a"}']);
        expect(runtime.bootstrapActiveCalls, 0);
      },
    );

    test('restores only locally owned terminal delivery obligations', () async {
      const activeCapsule =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const ledgerJson = '{"events":[]}';
      final acceptedIncoming = List<int>.filled(32, 17);
      final rejectedIncoming = List<int>.filled(32, 34);
      final expiredOutgoing = List<int>.filled(32, 51);
      final lifecycle = _RecordingDeliveryLifecycle();
      final service = InvitationActionsService(
        runtime: _FakeInvitationActionsRuntime(
          activeCapsuleHex: activeCapsule,
          invitationViews: <String, String>{
            ledgerJson: _invitationView(<Map<String, Object?>>[
              _invitationRow(
                id: acceptedIncoming,
                direction: 'incoming',
                status: 'accepted',
              ),
              _invitationRow(
                id: rejectedIncoming,
                direction: 'incoming',
                status: 'rejected',
              ),
              _invitationRow(
                id: expiredOutgoing,
                direction: 'outgoing',
                status: 'expired',
              ),
              _invitationRow(
                id: List<int>.filled(32, 68),
                direction: 'outgoing',
                status: 'accepted',
                respondedByLocal: false,
              ),
              _invitationRow(
                id: List<int>.filled(32, 85),
                direction: 'incoming',
                status: 'expired',
                respondedByLocal: false,
              ),
            ]),
          },
        ),
        deliveryLifecycle: lifecycle,
      );

      await service.reconcileTerminalOutboxForTest(<String, Object?>{
        'activeCapsuleHex': activeCapsule,
        'ledgerJson': ledgerJson,
      });

      expect(lifecycle.references, <String>[
        List<String>.filled(32, '11').join(),
        List<String>.filled(32, '22').join(),
        List<String>.filled(32, '33').join(),
      ]);
    });

    test(
      'recovers local terminal after remote revoke without UI kind',
      () async {
        final lifecycle = _RecordingDeliveryLifecycle();
        final row = _invitationRow(
          id: List<int>.filled(32, 17),
          direction: 'incoming',
          status: 'expired',
        )..['starter_kind'] = null;
        final service = InvitationActionsService(
          runtime: _FakeInvitationActionsRuntime(
            activeCapsuleHex: List<String>.filled(32, 'aa').join(),
            invitationViews: {
              '{}': _invitationView([row]),
            },
          ),
          deliveryLifecycle: lifecycle,
        );
        await service.reconcileTerminalOutboxForTest({
          'activeCapsuleHex': List<String>.filled(32, 'aa').join(),
          'ledgerJson': '{}',
        });
        expect(lifecycle.references, [List<String>.filled(32, '11').join()]);
      },
    );

    test('binds a new offer to the one added canonical invitation', () {
      const beforeLedger = '{"ledger":"before"}';
      const afterLedger = '{"ledger":"after"}';
      final existingId = List<int>.filled(32, 17);
      final addedId = List<int>.filled(32, 34);
      final service = InvitationActionsService(
        runtime: _FakeInvitationActionsRuntime(
          activeCapsuleHex:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          invitationViews: <String, String>{
            beforeLedger: _invitationView(<Map<String, Object?>>[
              _invitationRow(
                id: existingId,
                direction: 'outgoing',
                status: 'pending',
              ),
            ]),
            afterLedger: _invitationView(<Map<String, Object?>>[
              _invitationRow(
                id: existingId,
                direction: 'outgoing',
                status: 'pending',
              ),
              _invitationRow(
                id: addedId,
                direction: 'outgoing',
                status: 'pending',
              ),
            ]),
          },
        ),
      );

      expect(
        service.newOutgoingInvitationReferenceForTest(
          beforeLedgerJson: beforeLedger,
          afterLedgerJson: afterLedger,
        ),
        List<String>.filled(32, '22').join(),
      );
    });

    test('invalid before projection cannot make an existing offer new', () {
      const beforeLedger = '{"ledger":"before"}';
      const afterLedger = '{"ledger":"after"}';
      final existing = _invitationRow(
        id: List<int>.filled(32, 17),
        direction: 'outgoing',
        status: 'pending',
      );
      final invalidViews = <String?>[
        null,
        '{broken',
        '{"schema":"wrong","version":1}',
        _invitationView(<Map<String, Object?>>[
          <String, Object?>{...existing, 'invitation_id': null},
        ]),
        _invitationView(<Map<String, Object?>>[
          <String, Object?>{...existing, 'has_local_terminal': null},
        ]),
        _invitationView(<Map<String, Object?>>[existing, existing]),
      ];
      for (final invalidView in invalidViews) {
        final service = InvitationActionsService(
          runtime: _FakeInvitationActionsRuntime(
            activeCapsuleHex: List<String>.filled(32, 'aa').join(),
            invitationViews: <String, String>{
              if (invalidView != null) beforeLedger: invalidView,
              afterLedger: _invitationView(<Map<String, Object?>>[existing]),
            },
          ),
        );
        expect(
          service.newOutgoingInvitationReferenceForTest(
            beforeLedgerJson: beforeLedger,
            afterLedgerJson: afterLedger,
          ),
          isNull,
          reason: 'Invalid before evidence must not become an empty set',
        );
      }
    });

    test('rejects ambiguous or malformed canonical offer projection', () {
      const beforeLedger = '{"ledger":"before"}';
      const ambiguousLedger = '{"ledger":"ambiguous"}';
      const malformedLedger = '{"ledger":"malformed"}';
      final service = InvitationActionsService(
        runtime: _FakeInvitationActionsRuntime(
          activeCapsuleHex:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          invitationViews: <String, String>{
            beforeLedger: _invitationView(const <Map<String, Object?>>[]),
            ambiguousLedger: _invitationView(<Map<String, Object?>>[
              _invitationRow(
                id: List<int>.filled(32, 17),
                direction: 'outgoing',
                status: 'pending',
              ),
              _invitationRow(
                id: List<int>.filled(32, 34),
                direction: 'outgoing',
                status: 'pending',
              ),
            ]),
            malformedLedger: '{"schema":"wrong","version":1}',
          },
        ),
      );

      expect(
        service.newOutgoingInvitationReferenceForTest(
          beforeLedgerJson: beforeLedger,
          afterLedgerJson: ambiguousLedger,
        ),
        isNull,
      );
      expect(
        service.newOutgoingInvitationReferenceForTest(
          beforeLedgerJson: beforeLedger,
          afterLedgerJson: malformedLedger,
        ),
        isNull,
      );
    });
  });

  group('CapsuleWorkerQueue', () {
    test('keeps one capsule serialized through result persistence', () async {
      final queue = CapsuleWorkerQueue();
      final firstWorkerMayFinish = Completer<void>();
      final firstPersistenceMayFinish = Completer<void>();
      final trace = <String>[];

      final first = queue.run('aa', () async {
        trace.add('first.worker.start');
        await firstWorkerMayFinish.future;
        trace.add('first.persist.start');
        await firstPersistenceMayFinish.future;
        trace.add('first.persist.done');
        return 1;
      });
      final second = queue.run('aa', () async {
        trace.add('second.worker.start');
        return 2;
      });

      await Future<void>.delayed(Duration.zero);
      expect(trace, <String>['first.worker.start']);

      firstWorkerMayFinish.complete();
      await Future<void>.delayed(Duration.zero);
      expect(trace, <String>['first.worker.start', 'first.persist.start']);

      firstPersistenceMayFinish.complete();
      expect(await first, 1);
      expect(await second, 2);
      expect(trace, <String>[
        'first.worker.start',
        'first.persist.start',
        'first.persist.done',
        'second.worker.start',
      ]);
    });

    test(
      'serializes different capsules because the FFI runtime is global',
      () async {
        final queue = CapsuleWorkerQueue();
        final firstMayFinish = Completer<void>();
        var secondStarted = false;

        final first = queue.run('aa', () async {
          await firstMayFinish.future;
        });
        final second = queue.run('bb', () async {
          secondStarted = true;
        });

        await Future<void>.delayed(Duration.zero);
        expect(secondStarted, isFalse);
        firstMayFinish.complete();
        await first;
        await second;
        expect(secondStarted, isTrue);
      },
    );

    test('continues a capsule queue after an operation fails', () async {
      final queue = CapsuleWorkerQueue();

      final first = queue.run<void>('aa', () async {
        throw StateError('worker failed');
      });
      final second = queue.run('aa', () async => 'continued');

      await expectLater(first, throwsStateError);
      expect(await second, 'continued');
    });
  });
}

String _invitationView(List<Map<String, Object?>> invitations) {
  return jsonEncode(<String, Object?>{
    'schema': 'hivra.invitation_current_view',
    'version': 1,
    'ledger_version': invitations.length,
    'invitations': invitations,
  });
}

Map<String, Object?> _invitationRow({
  required List<int> id,
  required String direction,
  required String status,
  bool respondedByLocal = true,
}) {
  return <String, Object?>{
    'invitation_id': id,
    'starter_id': List<int>.filled(32, 1),
    'direction': direction,
    'from_pubkey': List<int>.filled(32, 2),
    'from_root_pubkey': null,
    'from_card_signature': null,
    'to_pubkey': direction == 'outgoing' ? List<int>.filled(32, 3) : null,
    'starter_kind': 0,
    'starter_slot': direction == 'outgoing' ? 0 : null,
    'status': status,
    'sent_at': 1,
    'responded_at': status == 'pending' ? null : 2,
    'has_local_terminal': status != 'pending' && respondedByLocal,
    'rejection_reason': status == 'rejected' ? 'other' : null,
  };
}

class _RecordingDeliveryLifecycle extends CapsuleDeliveryLifecycleService {
  final List<String> references = <String>[];

  _RecordingDeliveryLifecycle()
    : super(
        retryRunner:
            (_, _) async => const CapsuleDeliveryCycleResult(code: -1004),
      );

  @override
  Future<bool> ensureEnqueued({
    required String? capsuleHex,
    required String kind,
    required String reason,
    String? deliveryReference,
  }) async {
    if (deliveryReference != null) references.add(deliveryReference);
    return true;
  }
}

class _FakeInvitationActionsRuntime implements InvitationActionsRuntime {
  _FakeInvitationActionsRuntime({
    required this.activeCapsuleHex,
    this.workerBootstrap,
    this.invitationViews = const <String, String>{},
  });

  final String? activeCapsuleHex;
  final Map<String, Object?>? workerBootstrap;
  final Map<String, String> invitationViews;
  final Map<String, String> persistedLedgers = <String, String>{};
  final Map<String, String> persistedStates = <String, String>{};
  final List<String> appliedLedgers = <String>[];
  final List<String?> workerBootstrapRequests = <String?>[];
  int bootstrapActiveCalls = 0;

  @override
  Future<bool> applyLedgerSnapshotIfNotStale(String ledgerJson) async {
    appliedLedgers.add(ledgerJson);
    return true;
  }

  @override
  Future<bool> bootstrapActiveCapsuleRuntime() async {
    bootstrapActiveCalls += 1;
    return true;
  }

  @override
  int expireInvitationCode(Uint8List invitationId) => 0;

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs({
    String? capsuleHex,
  }) async {
    workerBootstrapRequests.add(capsuleHex);
    return workerBootstrap;
  }

  @override
  Future<void> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson, {
    String? capsuleStateJson,
  }) async {
    persistedLedgers[pubKeyHex] = ledgerJson;
    if (capsuleStateJson != null) {
      persistedStates[pubKeyHex] = capsuleStateJson;
    }
  }

  @override
  String? projectInvitationCurrentViewV1(String ledgerJson) {
    return invitationViews[ledgerJson];
  }

  @override
  Future<bool> persistLedgerSnapshot() async => true;

  @override
  Future<String?> resolveActiveCapsuleHex() async => activeCapsuleHex;
}
