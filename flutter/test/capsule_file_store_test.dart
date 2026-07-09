import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDocsDir;
  late CapsuleFileStore store;
  const capsuleHex =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  setUp(() async {
    tempDocsDir =
        await Directory.systemTemp.createTemp('hivra_file_store_test_');
    store = CapsuleFileStore(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('readState returns null when state file is missing', () async {
    final dir = await store.capsuleDirForHex(capsuleHex, create: true);

    final state = await store.readState(dir);

    expect(state, isNull);
  });

  test('readState returns parsed map for valid state json', () async {
    final dir = await store.capsuleDirForHex(capsuleHex, create: true);
    await store.stateFile(dir).writeAsString('{"active":true,"count":2}');

    final state = await store.readState(dir);

    expect(state, isNotNull);
    expect(state!['active'], isTrue);
    expect(state['count'], 2);
  });

  test('readState returns null for non-map json', () async {
    final dir = await store.capsuleDirForHex(capsuleHex, create: true);
    await store.stateFile(dir).writeAsString('["not","a","map"]');

    final state = await store.readState(dir);

    expect(state, isNull);
  });

  test('writes state ledger and backup without leaving temp files', () async {
    final dir = await store.capsuleDirForHex(capsuleHex, create: true);

    await store.writeState(dir, <String, dynamic>{'isNeste': true});
    await store.writeLedger(dir, '{"owner":[],"events":[]}');
    await store.writeBackup(dir, '{"schema":"hivra.capsule_backup"}');

    expect(await store.stateFile(dir).readAsString(), contains('isNeste'));
    expect(await store.ledgerFile(dir).readAsString(), contains('events'));
    expect(await store.backupFile(dir).readAsString(), contains('schema'));

    final tempFiles = <FileSystemEntity>[];
    await for (final entry in dir.list()) {
      if (entry is File && entry.path.contains('.tmp.')) {
        tempFiles.add(entry);
      }
    }
    expect(tempFiles, isEmpty);
  });

  test('atomic byte writes persist bytes without leaving temp files', () async {
    const atomicWrites = AtomicFileWriteService();
    final target = File('${tempDocsDir.path}/plugin.zip');

    await atomicWrites.writeBytes(target, const <int>[0, 1, 2, 3, 255]);

    expect(await target.readAsBytes(), const <int>[0, 1, 2, 3, 255]);
    final tempFiles = <FileSystemEntity>[];
    await for (final entry in tempDocsDir.list()) {
      if (entry is File && entry.path.contains('.tmp.')) {
        tempFiles.add(entry);
      }
    }
    expect(tempFiles, isEmpty);
  });
}
