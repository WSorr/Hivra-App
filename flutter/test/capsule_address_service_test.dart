import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/utils/hivra_id_format.dart';

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
  late CapsuleAddressService service;

  setUp(() async {
    tempDocsDir =
        await Directory.systemTemp.createTemp('hivra_address_service_test_');
    service = CapsuleAddressService(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('imports, lists, resolves and removes trusted card', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final nostrBytes =
        Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
    final rootKey = HivraIdFormat.formatCapsuleKeyBytes(rootBytes);
    final rootHex = _toHex(rootBytes);
    final nostrHex = _toHex(nostrBytes);

    final rawCard = jsonEncode({
      'version': 1,
      'rootKey': rootKey,
      'rootHex': rootHex,
      'transports': {
        'nostr': {'npub': nostrHex, 'hex': nostrHex},
      },
    });

    await service.importCardJson(rawCard);

    expect(await service.contactCount(), 1);

    final listed = await service.listTrustedCards();
    expect(listed.length, 1);
    expect(listed.first.rootKey, rootKey);
    expect(listed.first.rootHex, rootHex);
    expect(listed.first.nostrHex, nostrHex);

    final resolved = await service.resolveNostrRecipient(rootKey);
    expect(resolved, isNotNull);
    expect(_toHex(resolved!), nostrHex);

    expect(await service.removeTrustedCard(rootKey), isTrue);
    expect(await service.removeTrustedCard(rootKey), isFalse);
    expect(await service.contactCount(), 0);
  });

  test('throws on non-object contact card json', () async {
    expect(
      () => service.importCardJson('["invalid"]'),
      throwsA(isA<FormatException>()),
    );
  });

  test('gracefully handles malformed cards file root shape', () async {
    final cardsFile = File('${tempDocsDir.path}/capsule_contact_cards.json');
    await cardsFile.writeAsString('["bad-root-shape"]', flush: true);

    final listed = await service.listTrustedCards();

    expect(listed, isEmpty);
    expect(await service.contactCount(), 0);
  });
}

String _toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
