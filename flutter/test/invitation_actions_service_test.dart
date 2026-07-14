import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
import 'package:hivra_app/services/invitation_actions_service.dart';

void main() {
  group('InvitationActionsService worker ledger application', () {
    test('restores selected runtime after persisting non-active worker ledger',
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
      );

      expect(runtime.persistedLedgers, <String, String>{
        workerCapsule: '{"owner":"b"}',
      });
      expect(runtime.appliedLedgers, isEmpty);
      expect(runtime.bootstrapActiveCalls, 1);
    });

    test('applies active worker ledger directly without re-bootstrap',
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
      expect(
        trace,
        <String>['first.worker.start', 'first.persist.start'],
      );

      firstPersistenceMayFinish.complete();
      expect(await first, 1);
      expect(await second, 2);
      expect(
        trace,
        <String>[
          'first.worker.start',
          'first.persist.start',
          'first.persist.done',
          'second.worker.start',
        ],
      );
    });

    test('does not serialize independent capsules behind each other', () async {
      final queue = CapsuleWorkerQueue();
      final firstMayFinish = Completer<void>();
      var secondStarted = false;

      final first = queue.run('aa', () async {
        await firstMayFinish.future;
      });
      final second = queue.run('bb', () async {
        secondStarted = true;
      });

      await second;
      expect(secondStarted, isTrue);
      firstMayFinish.complete();
      await first;
    });

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

class _FakeInvitationActionsRuntime implements InvitationActionsRuntime {
  _FakeInvitationActionsRuntime({required this.activeCapsuleHex});

  final String? activeCapsuleHex;
  final Map<String, String> persistedLedgers = <String, String>{};
  final List<String> appliedLedgers = <String>[];
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
    return null;
  }

  @override
  Future<void> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson,
  ) async {
    persistedLedgers[pubKeyHex] = ledgerJson;
  }

  @override
  Future<bool> persistLedgerSnapshot() async => true;

  @override
  Future<String?> resolveActiveCapsuleHex() async => activeCapsuleHex;
}
