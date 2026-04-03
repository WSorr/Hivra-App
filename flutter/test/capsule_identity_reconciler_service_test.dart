import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_identity_reconciler_service.dart';
import 'package:hivra_app/services/capsule_index_store.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';

CapsuleIndexEntry _entry({
  required String pubKeyHex,
  required DateTime createdAt,
  required DateTime lastActive,
  required String identityMode,
  bool isGenesis = false,
  bool isNeste = true,
}) {
  return CapsuleIndexEntry(
    pubKeyHex: pubKeyHex,
    createdAt: createdAt,
    lastActive: lastActive,
    isGenesis: isGenesis,
    isNeste: isNeste,
    identityMode: identityMode,
  );
}

void main() {
  const service = CapsuleIdentityReconcilerService();

  test('merges duplicate seed aliases into root owner and remaps active', () {
    final now = DateTime.utc(2026, 4, 1, 0, 0, 0);
    final rootHex = List.filled(32, 'aa').join();
    final legacyHex = List.filled(32, 'bb').join();
    final index = CapsulesIndex(
      activePubKeyHex: legacyHex,
      capsules: <String, CapsuleIndexEntry>{
        rootHex: _entry(
          pubKeyHex: rootHex,
          createdAt: now.subtract(const Duration(hours: 2)),
          lastActive: now.subtract(const Duration(minutes: 30)),
          identityMode: 'root_owner',
          isGenesis: false,
        ),
        legacyHex: _entry(
          pubKeyHex: legacyHex,
          createdAt: now.subtract(const Duration(hours: 1)),
          lastActive: now,
          identityMode: 'legacy_nostr_owner',
          isGenesis: true,
        ),
      },
    );

    final result = service.reconcile(
      index: index,
      bindingsByPubKey: <String, CapsuleIdentityBinding>{
        rootHex: CapsuleIdentityBinding(
          seedFingerprint: 'seed-1',
          rootPubKeyHex: rootHex,
          nostrPubKeyHex: legacyHex,
        ),
        legacyHex: CapsuleIdentityBinding(
          seedFingerprint: 'seed-1',
          rootPubKeyHex: rootHex,
          nostrPubKeyHex: legacyHex,
        ),
      },
    );

    expect(result.seedAliasToCanonical, equals(<String, String>{legacyHex: rootHex}));
    expect(result.index.activePubKeyHex, equals(rootHex));
    expect(result.index.capsules.keys, equals(<String>[rootHex]));
    final canonical = result.index.capsules[rootHex]!;
    expect(canonical.identityMode, equals('root_owner'));
    expect(canonical.isGenesis, isTrue);
    expect(canonical.lastActive, equals(now));
  });

  test('keeps active entry as canonical when no root match is present', () {
    final now = DateTime.utc(2026, 4, 1, 0, 0, 0);
    final one = List.filled(32, '11').join();
    final two = List.filled(32, '22').join();
    final index = CapsulesIndex(
      activePubKeyHex: two,
      capsules: <String, CapsuleIndexEntry>{
        one: _entry(
          pubKeyHex: one,
          createdAt: now.subtract(const Duration(days: 1)),
          lastActive: now.subtract(const Duration(hours: 2)),
          identityMode: 'mixed_or_unknown',
        ),
        two: _entry(
          pubKeyHex: two,
          createdAt: now.subtract(const Duration(hours: 12)),
          lastActive: now.subtract(const Duration(hours: 1)),
          identityMode: 'mixed_or_unknown',
        ),
      },
    );

    final result = service.reconcile(
      index: index,
      bindingsByPubKey: <String, CapsuleIdentityBinding>{
        one: const CapsuleIdentityBinding(
          seedFingerprint: 'seed-x',
          rootPubKeyHex: null,
          nostrPubKeyHex: null,
        ),
        two: const CapsuleIdentityBinding(
          seedFingerprint: 'seed-x',
          rootPubKeyHex: null,
          nostrPubKeyHex: null,
        ),
      },
    );

    expect(result.index.activePubKeyHex, equals(two));
    expect(result.index.capsules.keys, equals(<String>[two]));
    expect(result.seedAliasToCanonical, equals(<String, String>{one: two}));
  });

  test('normalizes identity mode from binding even without alias merge', () {
    final now = DateTime.utc(2026, 4, 1, 0, 0, 0);
    final rootHex = List.filled(32, '33').join();
    final index = CapsulesIndex(
      activePubKeyHex: rootHex,
      capsules: <String, CapsuleIndexEntry>{
        rootHex: _entry(
          pubKeyHex: rootHex,
          createdAt: now,
          lastActive: now,
          identityMode: 'legacy_nostr_owner',
        ),
      },
    );

    final result = service.reconcile(
      index: index,
      bindingsByPubKey: <String, CapsuleIdentityBinding>{
        rootHex: CapsuleIdentityBinding(
          seedFingerprint: 'seed-z',
          rootPubKeyHex: rootHex,
          nostrPubKeyHex: List.filled(32, '44').join(),
        ),
      },
    );

    expect(result.seedAliasToCanonical, isEmpty);
    expect(result.index.capsules[rootHex]!.identityMode, equals('root_owner'));
  });
}
