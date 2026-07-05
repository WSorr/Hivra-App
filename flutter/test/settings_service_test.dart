import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/settings_service.dart';

class _FakeCapsuleAddressService extends CapsuleAddressService {
  int count = 0;
  String? imported;
  String? removedRootKey;
  List<CapsuleAddressCard> cards = <CapsuleAddressCard>[];

  @override
  Future<int> contactCount() async => count;

  @override
  Future<void> importCardJson(String raw) async {
    imported = raw;
  }

  @override
  Future<List<CapsuleAddressCard>> listTrustedCards() async => cards;

  @override
  Future<bool> removeTrustedCard(String rootKey) async {
    removedRootKey = rootKey;
    return true;
  }
}

void main() {
  test('reads seed and neste flag through injected boundaries', () async {
    final seed = Uint8List.fromList(List<int>.filled(32, 3));

    final service = SettingsService(
      loadIsNeste: () => true,
      loadSeed: () => seed,
      buildOwnCard: () async => null,
      exportOwnCardJson: () async => null,
      contactCards: _FakeCapsuleAddressService(),
    );

    expect(service.loadIsNeste(), isTrue);
    expect(service.loadSeed(), seed);
  });

  test(
      'delegates contact-card management to contact service and card boundaries',
      () async {
    final fakeContacts = _FakeCapsuleAddressService()
      ..count = 2
      ..cards = <CapsuleAddressCard>[
        const CapsuleAddressCard(
          rootKey: 'h1abc',
          rootHex: '11',
          nostrNpub: 'npub1abc',
          nostrHex: '22',
        ),
      ];
    final card = const CapsuleAddressCard(
      rootKey: 'h1self',
      rootHex: 'aa',
      nostrNpub: 'npub1self',
      nostrHex: 'bb',
    );

    final service = SettingsService(
      loadIsNeste: () => true,
      loadSeed: () => null,
      buildOwnCard: () async => card,
      exportOwnCardJson: () async => '{"version":1}',
      contactCards: fakeContacts,
    );

    expect(await service.contactCount(), 2);
    expect(await service.buildOwnCard(), same(card));
    expect(await service.exportOwnCardJson(), '{"version":1}');

    await service.importCardJson('{"root":"peer"}');
    expect(fakeContacts.imported, '{"root":"peer"}');

    expect(await service.listTrustedCards(), fakeContacts.cards);
    expect(await service.removeTrustedCard('h1abc'), isTrue);
    expect(fakeContacts.removedRootKey, 'h1abc');
  });
}
