import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_index_store.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _DelayedAtomicFileWriteService extends AtomicFileWriteService {
  int concurrentWrites = 0;
  int maxConcurrentWrites = 0;

  @override
  Future<void> writeString(File target, String contents) async {
    concurrentWrites += 1;
    if (concurrentWrites > maxConcurrentWrites) {
      maxConcurrentWrites = concurrentWrites;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await super.writeString(target, contents);
    } finally {
      concurrentWrites -= 1;
    }
  }
}

class _TestUserVisibleDataDirectoryService
    extends UserVisibleDataDirectoryService {
  final Directory _root;

  const _TestUserVisibleDataDirectoryService(this._root);

  @override
  Future<Directory> rootDirectory({bool create = false}) async {
    if (create && !await _root.exists()) {
      await _root.create(recursive: true);
    }
    return _root;
  }

  @override
  Future<Directory> capsulesDirectory({bool create = false}) async {
    final dir = Directory('${_root.path}/capsules');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDocsDir;
  late CapsuleIndexStore store;

  setUp(() async {
    tempDocsDir =
        await Directory.systemTemp.createTemp('hivra_index_store_test_');
    store = CapsuleIndexStore(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('preserves active capsule across write/read roundtrip', () async {
    const capsuleA =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const capsuleB =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    await store.upsert(capsuleA, isGenesis: true, isNeste: true);
    await store.upsert(capsuleB, isGenesis: false, isNeste: true);
    await store.setActive(capsuleB);

    final index = await store.read();
    expect(index.activePubKeyHex, equals(capsuleB));
    expect(index.capsules.keys.toSet(), equals({capsuleA, capsuleB}));
  });

  test('serializes metadata upsert with explicit active selection', () async {
    const capsuleA =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const capsuleB =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final writes = _DelayedAtomicFileWriteService();
    final serializedStore = CapsuleIndexStore(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      atomicWrites: writes,
    );

    await serializedStore.upsert(capsuleA);
    await serializedStore.upsert(capsuleB);
    await serializedStore.setActive(capsuleA);

    await Future.wait(<Future<void>>[
      serializedStore.setActive(capsuleB),
      serializedStore.upsert(capsuleA),
      serializedStore.upsert(capsuleB),
    ]);

    final index = await serializedStore.read();
    expect(index.activePubKeyHex, capsuleB);
    expect(writes.maxConcurrentWrites, 1);
  });

  test('reconciled metadata cannot overwrite a newer active selection',
      () async {
    const capsuleA =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const capsuleB =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    await store.upsert(capsuleA);
    await store.upsert(capsuleB);
    await store.setActive(capsuleA);
    final staleReconciledIndex = await store.read();

    await store.setActive(capsuleB);
    await store.writePreservingActive(staleReconciledIndex);

    final index = await store.read();
    expect(index.activePubKeyHex, capsuleB);
  });

  test('writes index without leaving temp files', () async {
    const capsuleA =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    await store.upsert(capsuleA, isGenesis: true, isNeste: true);
    await store.setActive(capsuleA);

    final capsulesRoot = Directory('${tempDocsDir.path}/capsules');
    final indexFile = File('${capsulesRoot.path}/capsules_index.json');
    expect(await indexFile.exists(), isTrue);
    expect(await indexFile.readAsString(), contains(capsuleA));

    final tempFiles = <FileSystemEntity>[];
    await for (final entry in capsulesRoot.list()) {
      if (entry is File && entry.path.contains('.tmp.')) {
        tempFiles.add(entry);
      }
    }
    expect(tempFiles, isEmpty);
  });

  test('drops stale active pointer when capsule entry is missing', () async {
    const staleActive =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    const existingCapsule =
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    final capsulesRoot = Directory('${tempDocsDir.path}/capsules');
    await capsulesRoot.create(recursive: true);
    final indexFile = File('${capsulesRoot.path}/capsules_index.json');

    await indexFile.writeAsString(
      '{"active":"$staleActive","capsules":{"$existingCapsule":{"pubKeyHex":"$existingCapsule","createdAt":"2026-03-28T00:00:00.000Z","lastActive":"2026-03-28T00:00:00.000Z","isGenesis":false,"isNeste":true,"identityMode":"root_owner"}}}',
      flush: true,
    );

    final index = await store.read();

    expect(index.activePubKeyHex, isNull);
    expect(index.capsules.containsKey(existingCapsule), isTrue);
  });

  test('defaults missing identity mode to root_owner', () async {
    const capsuleHex =
        'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
    final capsulesRoot = Directory('${tempDocsDir.path}/capsules');
    await capsulesRoot.create(recursive: true);
    final indexFile = File('${capsulesRoot.path}/capsules_index.json');

    await indexFile.writeAsString(
      '{"active":"$capsuleHex","capsules":{"$capsuleHex":{"pubKeyHex":"$capsuleHex","createdAt":"2026-03-28T00:00:00.000Z","lastActive":"2026-03-28T00:00:00.000Z","isGenesis":false,"isNeste":true}}}',
      flush: true,
    );

    final index = await store.read();
    final entry = index.capsules[capsuleHex];
    expect(entry, isNotNull);
    expect(entry!.identityMode, equals('root_owner'));
  });

  test('repairs missing index entries from capsule directories', () async {
    const indexedCapsule =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const missingCapsule =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final capsulesRoot = Directory('${tempDocsDir.path}/capsules');
    await capsulesRoot.create(recursive: true);
    final indexedDir = Directory('${capsulesRoot.path}/$indexedCapsule');
    final missingDir = Directory('${capsulesRoot.path}/$missingCapsule');
    await indexedDir.create(recursive: true);
    await missingDir.create(recursive: true);

    final missingState = File('${missingDir.path}/capsule_state.json');
    await missingState.writeAsString(
      jsonEncode({
        'isGenesis': true,
        'isNeste': false,
        'identityMode': 'legacy_nostr_owner',
      }),
      flush: true,
    );

    final indexFile = File('${capsulesRoot.path}/capsules_index.json');
    await indexFile.writeAsString(
      jsonEncode({
        'active': indexedCapsule,
        'capsules': {
          indexedCapsule: {
            'pubKeyHex': indexedCapsule,
            'createdAt': '2026-03-28T00:00:00.000Z',
            'lastActive': '2026-03-28T00:00:00.000Z',
            'isGenesis': false,
            'isNeste': true,
            'identityMode': 'root_owner',
          },
        },
      }),
      flush: true,
    );

    final index = await store.read();
    expect(
        index.capsules.keys.toSet(), equals({indexedCapsule, missingCapsule}));
    final repaired = index.capsules[missingCapsule];
    expect(repaired, isNotNull);
    expect(repaired!.isGenesis, isTrue);
    expect(repaired.isNeste, isFalse);
    expect(repaired.identityMode, equals('legacy_nostr_owner'));
  });
}
