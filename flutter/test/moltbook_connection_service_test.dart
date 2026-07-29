import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/moltbook_provider_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';
import 'package:hivra_app/services/moltbook_connection_service.dart';
import 'package:hivra_app/services/moltbook_provider_adapter.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  late Directory home;
  late CapsuleFileStore files;
  late _FakeSecureStorage secureStorage;
  late CapsuleScopedSecretVault vault;
  late _FakeObserver observer;
  late MoltbookConnectionService service;
  var activeRoot = _rootA;

  setUp(() async {
    activeRoot = _rootA;
    home = await Directory.systemTemp.createTemp('hivra_moltbook_connect_');
    files = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      atomicWrites: const AtomicFileWriteService(),
    );
    secureStorage = _FakeSecureStorage();
    vault = CapsuleScopedSecretVault(secureStorage: secureStorage);
    observer = _FakeObserver();
    service = MoltbookConnectionService(
      fileStore: files,
      secretVault: vault,
      observer: observer,
      readActiveCapsuleRootHex: () => activeRoot,
      now: () => DateTime.utc(2026, 7, 26, 12),
    );
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  test(
    'verifies before storing and persists only non-secret binding',
    () async {
      final binding = await service.connect('secret-key');

      expect(observer.keys, <String>['secret-key']);
      expect(binding.accountId, 'agent-1');
      expect((await service.loadBinding())?.accountName, 'Hivra Agent');
      final capsuleDir = await files.capsuleDirForHex(_rootA);
      final raw = await files.readPluginState(
        capsuleDir,
        moltbookAmbassadorPluginId,
        'connection.v1.json',
      );
      expect(raw, isNot(contains('secret-key')));
      expect(raw, isNot(contains('api_key')));
      expect(await _loadSecret(vault, _rootA, 'agent-1'), 'secret-key');
    },
  );

  test('screen-safe binding load does not read secure storage', () async {
    await service.connect('secret-key');
    secureStorage.readCount = 0;

    expect((await service.loadBinding())?.accountId, 'agent-1');
    expect(secureStorage.readCount, 0);
  });

  test('account replacement removes the previous credential', () async {
    await service.connect('first-key');
    observer.accountId = 'agent-2';
    observer.accountName = 'Second Agent';

    await service.connect('second-key');

    expect(await _loadSecret(vault, _rootA, 'agent-1'), isNull);
    expect(await _loadSecret(vault, _rootA, 'agent-2'), 'second-key');
    expect((await service.loadBinding())?.accountId, 'agent-2');
  });

  test('disconnect removes secret before local binding', () async {
    await service.connect('secret-key');

    await service.disconnect();

    expect(await service.loadBinding(), isNull);
    expect(await _loadSecret(vault, _rootA, 'agent-1'), isNull);
  });

  test('rejects completion after active capsule changes', () async {
    observer.onObserve = () => activeRoot = _rootB;

    await expectLater(
      service.connect('secret-key'),
      throwsA(isA<StateError>()),
    );
    expect(await _loadSecret(vault, _rootA, 'agent-1'), isNull);
  });

  test(
    'rolls back binding when capsule changes after metadata write',
    () async {
      final hookedFiles = _HookFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
        atomicWrites: const AtomicFileWriteService(),
        onWrite: () => activeRoot = _rootB,
      );
      service = MoltbookConnectionService(
        fileStore: hookedFiles,
        secretVault: vault,
        observer: observer,
        readActiveCapsuleRootHex: () => activeRoot,
        now: () => DateTime.utc(2026, 7, 26, 12),
      );

      await expectLater(
        service.connect('secret-key'),
        throwsA(isA<StateError>()),
      );

      activeRoot = _rootA;
      expect(await service.loadBinding(), isNull);
      expect(await _loadSecret(vault, _rootA, 'agent-1'), isNull);
    },
  );

  test('refresh rejects a credential resolving to another account', () async {
    await service.connect('secret-key');
    observer.accountId = 'agent-2';

    await expectLater(service.refresh(), throwsA(isA<StateError>()));
    expect((await service.loadBinding())?.accountId, 'agent-1');
  });

  test(
    'home observation uses the bound key without persisting remote data',
    () async {
      await service.connect('secret-key');

      final home = await service.observeHome();

      expect(home.unreadNotificationCount, 2);
      expect(observer.homeKeys, <String>['secret-key']);
      final capsuleDir = await files.capsuleDirForHex(_rootA);
      final stateDir = await files.pluginStateDirectory(
        capsuleDir,
        moltbookAmbassadorPluginId,
      );
      expect(
        await stateDir
            .list()
            .where((entry) => entry.path.contains('home'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'feed observation uses the bound key without persisting remote data',
    () async {
      await service.connect('secret-key');

      final feed = await service.observeFeed();

      expect(feed.posts.single.postId, 'post-1');
      expect(observer.feedKeys, <String>['secret-key']);
      final capsuleDir = await files.capsuleDirForHex(_rootA);
      final stateDir = await files.pluginStateDirectory(
        capsuleDir,
        moltbookAmbassadorPluginId,
      );
      expect(
        await stateDir
            .list()
            .where((entry) => entry.path.contains('feed'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'heartbeat loads one credential for home and feed observations',
    () async {
      await service.connect('secret-key');
      secureStorage.readCount = 0;

      final heartbeat = await service.observeHeartbeat();

      expect(heartbeat.home.unreadNotificationCount, 2);
      expect(heartbeat.feed.posts.single.postId, 'post-1');
      expect(secureStorage.readCount, lessThanOrEqualTo(1));
      expect(observer.homeKeys, <String>['secret-key']);
      expect(observer.feedKeys, <String>['secret-key']);
    },
  );

  test('heartbeat follows at most one continuation page', () async {
    await service.connect('secret-key');
    observer.firstPageHasMore = true;

    final heartbeat = await service.observeHeartbeat();

    expect(heartbeat.feed.posts.map((post) => post.postId), <String>[
      'post-1',
      'post-2',
    ]);
    expect(observer.feedLimits, <int>[15, 10]);
    expect(observer.feedCursors, <String?>[null, 'next-page']);
  });

  test('heartbeat stops pagination when a processed post is reached', () async {
    await service.connect('secret-key');
    observer.firstPageHasMore = true;

    final heartbeat = await service.observeHeartbeat(
      processedPostIds: const <String>{'post-1'},
    );

    expect(heartbeat.feed.posts.map((post) => post.postId), <String>['post-1']);
    expect(observer.feedLimits, <int>[15]);
    expect(observer.feedCursors, <String?>[null]);
  });
}

class _FakeObserver implements MoltbookObservePort {
  final List<String> keys = <String>[];
  final List<String> homeKeys = <String>[];
  final List<String> feedKeys = <String>[];
  final List<int> feedLimits = <int>[];
  final List<String?> feedCursors = <String?>[];
  String accountId = 'agent-1';
  String accountName = 'Hivra Agent';
  bool firstPageHasMore = false;
  void Function()? onObserve;

  @override
  Future<MoltbookAccountObservation> observeAccount(String apiKey) async {
    keys.add(apiKey);
    onObserve?.call();
    return MoltbookAccountObservation(
      accountId: accountId,
      name: accountName,
      description: 'Test agent',
      karma: 1,
      followerCount: 2,
      followingCount: 3,
      postsCount: 4,
      commentsCount: 5,
      isClaimed: true,
      isActive: true,
      rateLimit: const MoltbookRateLimitSnapshot(
        limit: 60,
        remaining: 59,
        resetEpochSeconds: 1,
        retryAfterSeconds: null,
      ),
    );
  }

  @override
  Future<MoltbookHomeObservation> observeHome(String apiKey) async {
    homeKeys.add(apiKey);
    return const MoltbookHomeObservation(
      accountName: 'Hivra Agent',
      karma: 7,
      unreadNotificationCount: 2,
      suggestedActions: <String>['Read notifications'],
      rateLimit: MoltbookRateLimitSnapshot(
        limit: 60,
        remaining: 58,
        resetEpochSeconds: 1,
        retryAfterSeconds: null,
      ),
    );
  }

  @override
  Future<MoltbookFeedObservation> observeFeed(
    String apiKey, {
    String sort = 'new',
    int limit = 15,
    String? cursor,
  }) async {
    feedKeys.add(apiKey);
    feedLimits.add(limit);
    feedCursors.add(cursor);
    final isSecondPage = cursor != null;
    return MoltbookFeedObservation(
      posts: <MoltbookFeedPost>[
        MoltbookFeedPost(
          postId: isSecondPage ? 'post-2' : 'post-1',
          title: isSecondPage ? 'An older post' : 'A useful post',
          content: 'Public content',
          authorId: 'author-1',
          authorName: 'Agent',
          submoltName: 'general',
          score: 1,
          commentCount: 0,
          isVerified: true,
          isSpam: false,
          createdAtUtc:
              isSecondPage
                  ? '2026-07-29T09:00:00.000Z'
                  : '2026-07-29T10:00:00.000Z',
        ),
      ],
      hasMore: !isSecondPage && firstPageHasMore,
      nextCursor: !isSecondPage && firstPageHasMore ? 'next-page' : null,
      rateLimit: const MoltbookRateLimitSnapshot(
        limit: 60,
        remaining: 57,
        resetEpochSeconds: 1,
        retryAfterSeconds: null,
      ),
    );
  }
}

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  int readCount = 0;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCount += 1;
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class _HookFileStore extends CapsuleFileStore {
  final void Function() onWrite;

  const _HookFileStore({
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

Future<String?> _loadSecret(
  CapsuleScopedSecretVault vault,
  String capsuleHex,
  String accountId,
) {
  return vault.loadSecret(
    capsuleHex: capsuleHex,
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountId: accountId,
    secretName: 'api_key',
  );
}

const String _rootA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _rootB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
