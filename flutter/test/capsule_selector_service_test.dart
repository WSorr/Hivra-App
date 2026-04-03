import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_selector_service.dart';

CapsuleSelectorItem _item({
  required String pubKeyHex,
  required String displayKeyText,
  required String network,
  required int ledgerVersion,
  required DateTime lastActive,
}) {
  return CapsuleSelectorItem(
    id: pubKeyHex,
    publicKeyHex: pubKeyHex,
    displayKeyText: displayKeyText,
    network: network,
    starterCount: 0,
    relationshipCount: 0,
    pendingInvitations: 0,
    ledgerVersion: ledgerVersion,
    ledgerHashHex: '0',
    lastActive: lastActive,
    createdAt: lastActive,
  );
}

void main() {
  test('prefers bootstrap-derived network label over stale index value', () {
    final label = CapsuleSelectorService.networkLabelForCapsule(
      indexIsNeste: true,
      bootstrapIsNeste: false,
    );

    expect(label, equals('HOOD'));
  });

  test('falls back to index network label when bootstrap is unavailable', () {
    final label = CapsuleSelectorService.networkLabelForCapsule(
      indexIsNeste: true,
      bootstrapIsNeste: null,
    );

    expect(label, equals('NESTE'));
  });

  test('collapses duplicate display entries and prefers seeded root_owner', () {
    final now = DateTime.utc(2026, 3, 31, 10, 0, 0);
    final rootHex = List.filled(32, 'aa').join();
    final legacyHex = List.filled(32, 'bb').join();

    final collapsed = CapsuleSelectorService.collapseDisplayDuplicates(
      <CapsuleSelectorItem>[
        _item(
          pubKeyHex: legacyHex,
          displayKeyText: 'h1samecapsule',
          network: 'NESTE',
          ledgerVersion: 12,
          lastActive: now,
        ),
        _item(
          pubKeyHex: rootHex,
          displayKeyText: 'h1samecapsule',
          network: 'NESTE',
          ledgerVersion: 11,
          lastActive: now.subtract(const Duration(minutes: 5)),
        ),
      ],
      hasSeedByPubKey: <String, bool>{
        rootHex: true,
        legacyHex: true,
      },
      identityModeByPubKey: <String, String>{
        rootHex: 'root_owner',
        legacyHex: 'legacy_nostr_owner',
      },
    );

    expect(collapsed, hasLength(1));
    expect(collapsed.single.publicKeyHex, equals(rootHex));
  });

  test('does not collapse same display key across different networks', () {
    final now = DateTime.utc(2026, 3, 31, 10, 0, 0);
    final nesteHex = List.filled(32, 'cc').join();
    final hoodHex = List.filled(32, 'dd').join();

    final collapsed = CapsuleSelectorService.collapseDisplayDuplicates(
      <CapsuleSelectorItem>[
        _item(
          pubKeyHex: nesteHex,
          displayKeyText: 'h1capsule',
          network: 'NESTE',
          ledgerVersion: 1,
          lastActive: now,
        ),
        _item(
          pubKeyHex: hoodHex,
          displayKeyText: 'h1capsule',
          network: 'HOOD',
          ledgerVersion: 1,
          lastActive: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      hasSeedByPubKey: <String, bool>{
        nesteHex: true,
        hoodHex: true,
      },
      identityModeByPubKey: <String, String>{
        nesteHex: 'root_owner',
        hoodHex: 'root_owner',
      },
    );

    expect(collapsed, hasLength(2));
    expect(
      collapsed.map((item) => item.publicKeyHex).toSet(),
      equals(<String>{nesteHex, hoodHex}),
    );
  });

  test('prefers newer ledger version when seed and mode are equal', () {
    final now = DateTime.utc(2026, 3, 31, 10, 0, 0);
    final oldHex = List.filled(32, 'ee').join();
    final newHex = List.filled(32, 'ff').join();

    final collapsed = CapsuleSelectorService.collapseDisplayDuplicates(
      <CapsuleSelectorItem>[
        _item(
          pubKeyHex: oldHex,
          displayKeyText: 'h1dup',
          network: 'NESTE',
          ledgerVersion: 3,
          lastActive: now,
        ),
        _item(
          pubKeyHex: newHex,
          displayKeyText: 'h1dup',
          network: 'NESTE',
          ledgerVersion: 9,
          lastActive: now.subtract(const Duration(hours: 1)),
        ),
      ],
      hasSeedByPubKey: <String, bool>{
        oldHex: true,
        newHex: true,
      },
      identityModeByPubKey: <String, String>{
        oldHex: 'root_owner',
        newHex: 'root_owner',
      },
    );

    expect(collapsed, hasLength(1));
    expect(collapsed.single.publicKeyHex, equals(newHex));
  });
}
