import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/moltbook_public_change_feed_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test(
    'public changes reject credential and private identifier material',
    () async {
      for (final fact in <String>[
        'api_key=AIza${'x' * 24}',
        'seed phrase: alpha beta gamma delta',
        'Capsule ${'h1${'a' * 32}'} changed.',
        'Commitment ${'a' * 64}',
      ]) {
        await expectLater(
          store.record(
            sourceId: 'sensitive-${fact.hashCode.abs()}',
            category: 'hivra-development',
            facts: <String>[fact],
          ),
          throwsFormatException,
        );
      }
      expect(await store.load(), isEmpty);
    },
  );

  test('bundled manifest is atomic, idempotent, and Capsule scoped', () async {
    final inserted = await store.ingestManifest(
      _manifest(),
      allowedTopics: const <String>{'hivra-development'},
    );
    expect(inserted.single.sourceId, 'hivra-chat-workspace-2026-08-14');

    final replay = await store.ingestManifest(
      _manifest(),
      allowedTopics: const <String>{'hivra-development'},
    );
    expect(replay, isEmpty);
    expect(await store.load(), hasLength(1));

    final restarted = MoltbookPublicChangeFeedStore(
      fileStore: files,
      readActiveCapsuleRootHex: () => activeRoot,
    );
    expect(
      await restarted.ingestManifest(
        _manifest(),
        allowedTopics: const <String>{'hivra-development'},
      ),
      isEmpty,
    );

    activeRoot = _rootB;
    expect(
      await restarted.ingestManifest(
        _manifest(),
        allowedTopics: const <String>{'hivra-development'},
      ),
      hasLength(1),
    );
    expect(await restarted.load(), hasLength(1));
  });

  test(
    'packaged manifest produces independent pending public changes',
    () async {
      final raw = await rootBundle.loadString(
        'assets/moltbook_public_changes.v1.json',
      );
      final inserted = await store.ingestManifest(
        raw,
        allowedTopics:
            MoltbookAmbassadorConfiguration.defaults().allowedTopics.toSet(),
      );

      expect(inserted, hasLength(2));
      expect(inserted.map((change) => change.sourceId), <String>[
        'moltbook-product-cycle-2026-08-29',
        'moltbook-gemini-verification-2026-08-30',
      ]);
      expect((await store.nextPending())?.sourceId, inserted.first.sourceId);
    },
  );

  test(
    'bundled manifest rejects malformed and conflicting input atomically',
    () async {
      final malformed = jsonDecode(_manifest()) as Map<String, dynamic>;
      (malformed['changes'] as List).add(<String, dynamic>{
        'source_id': 'invalid change id',
        'category': 'hivra-development',
        'facts': <String>['This entry must reject the complete manifest.'],
      });
      await expectLater(
        store.ingestManifest(
          jsonEncode(malformed),
          allowedTopics: const <String>{'hivra-development'},
        ),
        throwsFormatException,
      );
      expect(await store.load(), isEmpty);

      await store.ingestManifest(
        _manifest(),
        allowedTopics: const <String>{'hivra-development'},
      );
      final conflicting = jsonDecode(_manifest()) as Map<String, dynamic>;
      ((conflicting['changes'] as List).single
          as Map<String, dynamic>)['facts'] = <String>[
        'Different facts cannot reuse this source id.',
      ];
      await expectLater(
        store.ingestManifest(
          jsonEncode(conflicting),
          allowedTopics: const <String>{'hivra-development'},
        ),
        throwsStateError,
      );
      expect((await store.load()).single.facts, <String>[
        'Chat presents retained messages in a conversation timeline.',
      ]);
    },
  );

  test('bundled manifest rejects duplicate source ids atomically', () async {
    final duplicate = jsonDecode(_manifest()) as Map<String, dynamic>;
    (duplicate['changes'] as List).add(
      Map<String, dynamic>.from((duplicate['changes'] as List).single as Map),
    );

    await expectLater(
      store.ingestManifest(
        jsonEncode(duplicate),
        allowedTopics: const <String>{'hivra-development'},
      ),
      throwsFormatException,
    );
    expect(await store.load(), isEmpty);
  });

  test('Capsule switch aborts bundled manifest persistence', () async {
    var ownerReads = 0;
    final switchingStore = MoltbookPublicChangeFeedStore(
      fileStore: files,
      readActiveCapsuleRootHex: () {
        ownerReads++;
        return ownerReads == 1 ? _rootA : _rootB;
      },
    );

    await expectLater(
      switchingStore.ingestManifest(
        _manifest(),
        allowedTopics: const <String>{'hivra-development'},
      ),
      throwsStateError,
    );
    activeRoot = _rootA;
    expect(await store.load(), isEmpty);
    activeRoot = _rootB;
    expect(await store.load(), isEmpty);
  });

  test(
    'bundled manifest rejects unknown fields and skips disallowed topics',
    () async {
      final unknown = jsonDecode(_manifest()) as Map<String, dynamic>;
      unknown['unexpected'] = true;
      await expectLater(
        store.ingestManifest(
          jsonEncode(unknown),
          allowedTopics: const <String>{'hivra-development'},
        ),
        throwsFormatException,
      );
      expect(
        await store.ingestManifest(
          _manifest(),
          allowedTopics: const <String>{'capsule-runtime'},
        ),
        isEmpty,
      );
      expect(await store.load(), isEmpty);
    },
  );

  test('bundled manifest rejects oversized raw input before parsing', () async {
    await expectLater(
      store.ingestManifest(
        ' ' * (MoltbookPublicChangeFeedStore.maxManifestCharacters + 1),
        allowedTopics: const <String>{'hivra-development'},
      ),
      throwsFormatException,
    );
    expect(await store.load(), isEmpty);
  });

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

String _manifest() => jsonEncode(<String, dynamic>{
  'schema_version': 1,
  'producer_id': 'hivra.bundled_public_changes',
  'changes': <Map<String, dynamic>>[
    <String, dynamic>{
      'source_id': 'hivra-chat-workspace-2026-08-14',
      'category': 'hivra-development',
      'facts': <String>[
        'Chat presents retained messages in a conversation timeline.',
      ],
    },
  ],
});
