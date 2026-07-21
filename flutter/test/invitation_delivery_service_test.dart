import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/invitation_delivery_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/utils/hivra_id_format.dart';

class _TestDataDirectory extends UserVisibleDataDirectoryService {
  final Directory directory;

  const _TestDataDirectory(this.directory);

  @override
  Future<Directory> rootDirectory({bool create = false}) async {
    if (create) await directory.create(recursive: true);
    return directory;
  }
}

void main() {
  late Directory directory;
  late CapsuleAddressService addressBook;
  late InvitationDeliveryService delivery;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hivra_invite_address_');
    addressBook = CapsuleAddressService(dirs: _TestDataDirectory(directory));
    delivery = InvitationDeliveryService(contactCards: addressBook);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'resolves and stores a pasted contact card without a separate key',
    () async {
      final root = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final nostr = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));
      final card = _card(root, nostr);

      final result = await delivery.resolveRecipientAddress(
        jsonEncode(card.toJson()),
      );

      expect(result.isSuccess, isTrue);
      expect(result.transportRecipient, orderedEquals(nostr));
      expect(await addressBook.hasKnownNostrEndpoint(card.rootKey), isTrue);
    },
  );

  test('resolves a QR contact payload without a separate key', () async {
    final root = Uint8List.fromList(List<int>.generate(32, (i) => i + 2));
    final nostr = Uint8List.fromList(List<int>.generate(32, (i) => 180 - i));
    final card = _card(root, nostr);

    final result = await delivery.resolveRecipientAddress(card.toQrPayload());

    expect(result.isSuccess, isTrue);
    expect(result.transportRecipient, orderedEquals(nostr));
  });

  test('rejects own pasted contact card', () async {
    final root = Uint8List.fromList(List<int>.generate(32, (i) => i + 3));
    final nostr = Uint8List.fromList(List<int>.generate(32, (i) => 160 - i));

    final result = await delivery.resolveRecipientAddress(
      jsonEncode(_card(root, nostr).toJson()),
      selfRootKey: root,
      selfNostrKey: nostr,
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains("can't invite"));
  });
}

CapsuleAddressCard _card(Uint8List root, Uint8List nostr) => CapsuleAddressCard(
  rootKey: HivraIdFormat.formatCapsuleKeyBytes(root),
  rootHex: _hex(root),
  nostrNpub: _hex(nostr),
  nostrHex: _hex(nostr),
);

String _hex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
