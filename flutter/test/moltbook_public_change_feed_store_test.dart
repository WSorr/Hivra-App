import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/moltbook_public_change_feed_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  late Directory home;
  late CapsuleFileStore files;
  late MoltbookPublicChangeFeedStore store;
  var activeRoot = _rootA;

  setUp(() async {
    activeRoot = _rootA;
    home = await Directory.systemTemp.createTemp('hivra_moltbook_changes_');
    files = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      atomicWrites: const AtomicFileWriteService(),
    );
    store = MoltbookPublicChangeFeedStore(
      fileStore: files,
      readActiveCapsuleRootHex: () => activeRoot,
    );
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  test(
    'exact source replay is idempotent and conflicting facts fail closed',
    () async {
      final first = await store.record(
        sourceId: 'change-42',
        category: 'hivra-development',
        facts: const <String>['One reviewed public fact.'],
      );
      final replay = await store.record(
        sourceId: 'change-42',
        category: 'hivra-development',
        facts: const <String>['One reviewed public fact.'],
      );

      expect(replay.commitmentHashHex, first.commitmentHashHex);
      expect(await store.load(), hasLength(1));
      await expectLater(
        store.record(
          sourceId: 'change-42',
          category: 'hivra-development',
          facts: const <String>['Different public fact.'],
        ),
        throwsStateError,
      );
    },
  );

  test('feed and drafted state remain Capsule scoped across restart', () async {
    final change = await store.record(
      sourceId: 'change-1',
      category: 'hivra-development',
      facts: const <String>['Restart keeps the same queued change.'],
    );
    await store.markDrafted(change.commitmentHashHex, 'd' * 64);

    final restarted = MoltbookPublicChangeFeedStore(
      fileStore: files,
      readActiveCapsuleRootHex: () => activeRoot,
    );
    expect((await restarted.load()).single.draftHashHex, 'd' * 64);

    activeRoot = _rootB;
    expect(await restarted.load(), isEmpty);
    activeRoot = _rootA;
    expect(await restarted.nextPending(), isNull);
  });

  test('next pending is oldest-first and cannot bind another draft', () async {
    final first = await store.record(
      sourceId: 'change-1',
      category: 'hivra-development',
      facts: const <String>['First public fact.'],
    );
    await store.record(
      sourceId: 'change-2',
      category: 'hivra-development',
      facts: const <String>['Second public fact.'],
    );

    expect((await store.nextPending())?.sourceId, 'change-1');
    await store.markDrafted(first.commitmentHashHex, 'a' * 64);
    expect((await store.nextPending())?.sourceId, 'change-2');
    await expectLater(
      store.markDrafted(first.commitmentHashHex, 'b' * 64),
      throwsStateError,
    );
  });

  test(
    'restart reconciles a durable draft written before the feed marker',
    () async {
      await store.record(
        sourceId: 'change-1',
        category: 'hivra-development',
        facts: const <String>['One confirmed public fact.'],
      );

      await store.reconcileDrafts(
        <({String bulletinId, String category, String draftHashHex})>[
          (
            bulletinId: 'change-1',
            category: 'hivra-development',
            draftHashHex: 'c' * 64,
          ),
        ],
      );

      expect((await store.load()).single.draftHashHex, 'c' * 64);
      expect(await store.nextPending(), isNull);
    },
  );

  test(
    'ambiguous durable drafts fail closed during restart reconciliation',
    () async {
      await store.record(
        sourceId: 'change-1',
        category: 'hivra-development',
        facts: const <String>['One confirmed public fact.'],
      );
      final drafts =
          <({String bulletinId, String category, String draftHashHex})>[
            (
              bulletinId: 'change-1',
              category: 'hivra-development',
              draftHashHex: 'a' * 64,
            ),
            (
              bulletinId: 'change-1',
              category: 'hivra-development',
              draftHashHex: 'b' * 64,
            ),
          ];

      await expectLater(store.reconcileDrafts(drafts), throwsStateError);
      expect((await store.load()).single.isPending, isTrue);
    },
  );

  test('retention stays bounded and preserves the newest changes', () async {
    for (
      var index = 0;
      index <= MoltbookPublicChangeFeedStore.maxChanges;
      index++
    ) {
      await store.record(
        sourceId: 'change-$index',
        category: 'hivra-development',
        facts: <String>['Public fact $index.'],
      );
    }

    final changes = await store.load();
    expect(changes, hasLength(MoltbookPublicChangeFeedStore.maxChanges));
    expect(changes.first.sourceId, 'change-1');
    expect(changes.last.sourceId, 'change-100');
  });

  test(
    'malformed commitment and oversized persisted feed fail closed',
    () async {
      final capsuleDir = await files.capsuleDirForHex(_rootA, create: true);
      final change = <String, dynamic>{
        'schema_version': 1,
        'source_id': 'change-1',
        'category': 'hivra-development',
        'facts': <String>['One fact.'],
        'commitment_hash_hex': '0' * 64,
        'recorded_at_utc': DateTime.utc(2026, 8, 13).toIso8601String(),
        'draft_hash_hex': null,
      };
      await files.writePluginState(
        capsuleDir,
        moltbookAmbassadorPluginId,
        'public_change_feed.v1.json',
        jsonEncode(<String, dynamic>{
          'schema_version': 1,
          'plugin_id': moltbookAmbassadorPluginId,
          'changes': <Map<String, dynamic>>[change],
        }),
      );
      await expectLater(store.load(), throwsFormatException);

      final validCommitment = MoltbookPublicChangeFeedStore.commitmentFor(
        sourceId: 'change-1',
        category: 'hivra-development',
        facts: const <String>['One fact.'],
      );
      change['commitment_hash_hex'] = validCommitment;
      await files.writePluginState(
        capsuleDir,
        moltbookAmbassadorPluginId,
        'public_change_feed.v1.json',
        jsonEncode(<String, dynamic>{
          'schema_version': 1,
          'plugin_id': moltbookAmbassadorPluginId,
          'changes': List<Map<String, dynamic>>.filled(
            MoltbookPublicChangeFeedStore.maxChanges + 1,
            change,
          ),
        }),
      );
      await expectLater(store.load(), throwsFormatException);
    },
  );
}

const String _rootA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _rootB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
