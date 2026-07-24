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

  CapsuleContactLabelStore storeFor(String owner) {
    final writes = const AtomicFileWriteService();
    final dirs = UserVisibleDataDirectoryService(
      homeOverride: temp.path,
      atomicWrites: writes,
    );
    return CapsuleContactLabelStore(
      fileStore: CapsuleFileStore(dirs: dirs, atomicWrites: writes),
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
}
