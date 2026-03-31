import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
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

CapsuleTraceReport _fakeTraceReport() {
  return CapsuleTraceReport(
    activePubKeyHex: 'active',
    runtimePubKeyHex: 'runtime',
    runtimeSeedExists: true,
    indexHasEntry: true,
    secureSeedExists: true,
    fallbackSeedExists: false,
    capsuleDirPath: '/tmp/capsule',
    capsuleDirExists: true,
    ledgerFileExists: true,
    stateFileExists: true,
    backupFileExists: true,
    legacyDocsPath: '/tmp/docs',
    legacyLedgerExists: false,
    legacyStateExists: false,
    legacyBackupExists: false,
  );
}

CapsuleBootstrapReport _fakeBootstrapReport() {
  return CapsuleBootstrapReport(
    activePubKeyHex: 'active',
    runtimePubKeyHex: 'runtime',
    rootPubKeyHex: 'root',
    nostrPubKeyHex: 'nostr',
    identityMode: 'root_owner',
    bootstrapSource: 'ledger',
    seedAvailable: true,
    seedMatchesActiveCapsule: true,
    rootMatchesActiveCapsule: true,
    nostrMatchesActiveCapsule: false,
    runtimeMatchesRoot: true,
    runtimeMatchesNostr: false,
    stateFileExists: true,
    ledgerFileExists: true,
    backupFileExists: true,
    workerBootstrapAvailable: true,
    ledgerImportable: true,
    issue: null,
  );
}

void main() {
  test('reads seed, neste flag, and diagnostics through injected boundaries',
      () async {
    final seed = Uint8List.fromList(List<int>.filled(32, 3));
    final trace = _fakeTraceReport();
    final bootstrap = _fakeBootstrapReport();

    final service = SettingsService(
      loadIsNeste: () => true,
      loadSeed: () => seed,
      diagnoseCapsuleTraces: () async => trace,
      diagnoseBootstrapReport: () async => bootstrap,
      buildOwnCard: () async => null,
      exportOwnCardJson: () async => null,
      contactCards: _FakeCapsuleAddressService(),
    );

    expect(service.loadIsNeste(), isTrue);
    expect(service.loadSeed(), seed);
    expect(await service.diagnoseCapsuleTraces(), same(trace));
    expect(await service.diagnoseBootstrapReport(), same(bootstrap));
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
      diagnoseCapsuleTraces: () async => _fakeTraceReport(),
      diagnoseBootstrapReport: () async => _fakeBootstrapReport(),
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
