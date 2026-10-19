import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hivra_app/models/external_effect_models.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/moltbook_provider_models.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/moltbook_feed_checkpoint_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  late Directory home;
  late CapsuleFileStore files;
  late MoltbookFeedCheckpointStore store;
  var activeRoot = _rootA;

  setUp(() async {
    activeRoot = _rootA;
    home = await Directory.systemTemp.createTemp('hivra_moltbook_checkpoint_');
    files = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      atomicWrites: const AtomicFileWriteService(),
    );
    store = MoltbookFeedCheckpointStore(
      fileStore: files,
      readActiveCapsuleRootHex: () => activeRoot,
    );
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  test(
    'settlement survives a crash before deletion without retaining publication history',
    () async {
      final completed = _processedWrite(
        'post-a',
        DateTime.utc(2026, 10, 19, 10),
      );
      await store.recordProcessedWrite(completed);
      final restarted = MoltbookFeedCheckpointStore(
        fileStore: files,
        readActiveCapsuleRootHex: () => activeRoot,
      );
      await restarted.recordProcessedWrite(completed);
      var usage = await restarted.writeUsage(
        'agent-1',
        'moltbook.post.create',
        DateTime.utc(2026, 10, 19, 10, 10),
      );
      expect(usage.writesToday, 1);
      expect(usage.minutesSinceLastWrite, 10);
      // A normal heartbeat checkpoint write must preserve the budget.
      await restarted.save(const MoltbookFeedCheckpoint.empty());
      await restarted.finishProcessedWrite(completed.operationId);
      final directory = await files.capsuleDirForHex(_rootA);
      final raw =
          (await files.readPluginState(
            directory,
            'hivra.contract.moltbook-ambassador.v1',
            'feed_checkpoint.v1.json',
          ))!;
      expect(raw, isNot(contains('Private draft body')));
      expect(raw, isNot(contains('post-a')));
      expect(raw, isNot(contains('receipt-a')));
      usage = await restarted.writeUsage(
        'agent-1',
        'moltbook.post.create',
        DateTime.utc(2026, 10, 20),
      );
      expect(usage.writesToday, 0);
      expect(
        (await restarted.writeUsage(
          'other-account',
          'moltbook.post.create',
          DateTime.utc(2026, 10, 19),
        )).writesToday,
        0,
      );
      await restarted.recordProcessedWrite(
        _processedWrite('post-b', DateTime.utc(2026, 10, 19, 11)),
      );
      await restarted.finishProcessedWrite('post-b');
      expect(
        (await restarted.writeUsage(
          'agent-1',
          'moltbook.post.create',
          DateTime.utc(2026, 10, 19, 11, 5),
        )).writesToday,
        2,
      );
      activeRoot = _rootB;
      expect(
        (await restarted.writeUsage(
          'agent-1',
          'moltbook.post.create',
          DateTime.utc(2026, 10, 19),
        )).writesToday,
        0,
      );
    },
  );

  test(
    'out-of-order legacy completion preserves the latest cooldown and day',
    () async {
      await store.recordProcessedWrite(
        _processedWrite('new', DateTime.utc(2026, 10, 19, 11)),
      );
      await store.finishProcessedWrite('new');
      await store.recordProcessedWrite(
        _processedWrite('old', DateTime.utc(2026, 10, 18, 11)),
      );
      await store.finishProcessedWrite('old');
      final usage = await store.writeUsage(
        'agent-1',
        'moltbook.post.create',
        DateTime.utc(2026, 10, 19, 11, 5),
      );
      expect(usage.writesToday, 1);
      expect(usage.minutesSinceLastWrite, 5);
    },
  );

  test('persists only bounded feed identity metadata', () async {
    final checkpoint = await store.save(
      const MoltbookFeedCheckpoint(
        newestPostId: 'post-2',
        processedPostIds: <String>['post-2', 'post-1'],
        lastObservedAtUtc: '2026-07-29T12:00:00.000Z',
        continuationCursor: 'older-page',
      ),
    );

    expect(checkpoint.newestPostId, 'post-2');
    expect(checkpoint.processedPostIds, <String>['post-2', 'post-1']);
    expect(checkpoint.continuationCursor, 'older-page');

    final capsuleDir = await files.capsuleDirForHex(_rootA);
    final stateDir = await files.pluginStateDirectory(
      capsuleDir,
      'hivra.contract.moltbook-ambassador.v1',
    );
    final raw =
        await File('${stateDir.path}/feed_checkpoint.v1.json').readAsString();
    expect(raw, isNot(contains('Remote body')));
    expect(raw, isNot(contains('Remote title')));
  });

  test('deduplicates ids and preserves newest-first bounded history', () async {
    await store.save(
      const MoltbookFeedCheckpoint(
        newestPostId: 'post-2',
        processedPostIds: <String>['post-2', 'post-1'],
        lastObservedAtUtc: '2026-07-29T12:00:00.000Z',
        continuationCursor: null,
      ),
    );

    final checkpoint = await store.save(
      const MoltbookFeedCheckpoint(
        newestPostId: 'post-3',
        processedPostIds: <String>['post-3', 'post-2', 'post-1'],
        lastObservedAtUtc: '2026-07-29T12:30:00.000Z',
        continuationCursor: null,
      ),
    );

    expect(checkpoint.processedPostIds, <String>['post-3', 'post-2', 'post-1']);
    expect(checkpoint.newestPostId, 'post-3');
  });

  test('fails closed when active capsule changes before persistence', () async {
    final hookedFiles = _HookFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      atomicWrites: const AtomicFileWriteService(),
      onWrite: () => activeRoot = _rootB,
    );
    store = MoltbookFeedCheckpointStore(
      fileStore: hookedFiles,
      readActiveCapsuleRootHex: () => activeRoot,
    );

    final future = store.save(
      const MoltbookFeedCheckpoint(
        newestPostId: 'post-1',
        processedPostIds: <String>['post-1'],
        lastObservedAtUtc: '2026-07-29T12:00:00.000Z',
        continuationCursor: null,
      ),
    );

    await expectLater(future, throwsA(isA<StateError>()));
  });
}

class _HookFileStore extends CapsuleFileStore {
  final void Function() onWrite;

  _HookFileStore({
    required super.dirs,
    required super.atomicWrites,
    required this.onWrite,
  });

  @override
  Future<void> writePluginState(
    Directory capsuleDir,
    String pluginId,
    String fileName,
    String rawJson,
  ) async {
    await super.writePluginState(capsuleDir, pluginId, fileName, rawJson);
    onWrite();
  }
}

const String _rootA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _rootB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ExternalEffectOperation _processedWrite(String id, DateTime time) {
  final payload = jsonEncode({'content': 'Private draft body'});
  final timestamp = time.toIso8601String();
  return ExternalEffectOperation(
    ownerCapsuleHex: _rootA,
    operationId: id,
    pluginId: 'hivra.contract.moltbook-ambassador.v1',
    providerId: 'moltbook',
    accountBindingId: 'agent-1',
    effectKind: 'moltbook.post.create',
    canonicalPayloadJson: payload,
    payloadHashHex: sha256.convert(utf8.encode(payload)).toString(),
    state: ExternalEffectState.succeeded,
    approvalEvidenceHashHex: 'a' * 64,
    attemptCount: 1,
    revision: 3,
    createdAtUtc: timestamp,
    updatedAtUtc: timestamp,
    approvedAtUtc: timestamp,
    lastErrorCode: null,
    lastErrorMessage: null,
    requiredAction: null,
    receipt: ExternalEffectReceipt(
      operationId: id,
      providerId: 'moltbook',
      providerReceiptId: 'receipt-a',
      evidenceHashHex: 'b' * 64,
      receivedAtUtc: timestamp,
    ),
  );
}
