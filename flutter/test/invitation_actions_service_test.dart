import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/invitation_actions_service.dart';

void main() {
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
