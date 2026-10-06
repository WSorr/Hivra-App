import 'dart:io';

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
