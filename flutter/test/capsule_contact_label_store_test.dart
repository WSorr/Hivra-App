import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_contact_label_store.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  late Directory temp;
  final ownerA = List<String>.filled(64, 'a').join();
  final ownerB = List<String>.filled(64, 'b').join();
  const peer = 'h1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq0w9v8';

  CapsuleFileStore files() {
    final writes = const AtomicFileWriteService();
    final dirs = UserVisibleDataDirectoryService(
      homeOverride: temp.path,
      atomicWrites: writes,
    );
    return CapsuleFileStore(dirs: dirs, atomicWrites: writes);
  }

  CapsuleContactLabelStore storeFor(String owner) {
    return CapsuleContactLabelStore(
      fileStore: files(),
      readActiveCapsuleRootHex: () => owner,
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('hivra-contact-labels-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('keeps labels local to their owning capsule', () async {
    final first = storeFor(ownerA);
    final second = storeFor(ownerB);

    await first.save(peerRootKey: peer, label: 'Alex');

    expect(await first.load(), equals(<String, String>{peer: 'Alex'}));
    expect(await second.load(), isEmpty);
  });

  test('empty label removes only the local presentation metadata', () async {
    final store = storeFor(ownerA);
    await store.save(peerRootKey: peer, label: 'Work Android');
    await store.save(peerRootKey: peer, label: '');

    expect(await store.load(), isEmpty);
  });

  for (final raw in <String>[
    '',
    '  ',
    '{broken',
    '[]',
    'null',
    '{"version":2,"labels":{"$peer":"Retained"}}',
    '{"version":1,"labels":[]}',
    '{"version":1,"labels":{"$peer":42}}',
    '{"version":1,"labels":{"unknown":"Retained"}}',
  ]) {
    test('failed rename retains unavailable names: $raw', () async {
      final store = storeFor(ownerA);
      final dir = await files().capsuleDirForHex(ownerA, create: true);
      final file = files().contactLabelsFile(dir);
      await file.writeAsString(raw);

      // Presentation retains its existing best-effort fallback.
      expect(await store.load(), isA<Map<String, String>>());
      await expectLater(
        store.save(peerRootKey: peer, label: 'Changed'),
        throwsFormatException,
      );
      expect(await file.readAsString(), raw);

      // Fixture repair does not leave the owner's queue stuck on the error.
      await file.writeAsString('{"version":1,"labels":{}}');
      await store.save(peerRootKey: peer, label: 'Recovered');
      expect(await storeFor(ownerA).load(), {peer: 'Recovered'});
    });
  }

  test('concurrent store instances retain both local names', () async {
    final otherPeer = 'h1${'r' * 58}';
    await Future.wait([
      storeFor(ownerA).save(peerRootKey: peer, label: 'First'),
      storeFor(ownerA).save(peerRootKey: otherPeer, label: 'Second'),
    ]);
    expect(await storeFor(ownerA).load(), {peer: 'First', otherPeer: 'Second'});
    final dir = await files().capsuleDirForHex(ownerA);
    expect(jsonDecode((await files().readContactLabels(dir))!)['version'], 1);
  });
}
