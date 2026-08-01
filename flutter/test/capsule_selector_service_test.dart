import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/capsule_selector_runtime.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
import 'package:hivra_app/services/capsule_selector_service.dart';

CapsuleSelectorItem _item({
  required String pubKeyHex,
  required String displayKeyText,
  required String network,
  required int ledgerVersion,
  required DateTime lastActive,
  DateTime? createdAt,
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
    createdAt: createdAt ?? lastActive,
  );
}

class _ActivationRuntime implements CapsuleSelectorRuntime {
  final Object? activationError;

  _ActivationRuntime({this.activationError});

  @override
  Future<void> activateCapsule(String pubKeyHex) async {
    if (activationError != null) throw activationError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PublicSummaryRuntime implements CapsuleSelectorRuntime {
  final List<CapsuleIndexEntry> entries;
  int publicSummaryCalls = 0;
  int activationCalls = 0;

  _PublicSummaryRuntime(this.entries);

  @override
  Future<List<CapsuleIndexEntry>> listCapsules() async => entries;

  @override
  Future<CapsuleLedgerSummary> loadPublicCapsuleSummary(
    String pubKeyHex,
  ) async {
    publicSummaryCalls += 1;
    return CapsuleLedgerSummary(
      starterCount: 5,
      relationshipCount: 2,
      pendingInvitations: 1,
      ledgerVersion: 7,
      ledgerHashHex: 'abc',
    );
  }

  @override
  Future<void> activateCapsule(String pubKeyHex) async {
    activationCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  test(
    'loads selector rows from public summaries without activation',
    () async {
      final now = DateTime.utc(2026, 8, 1, 12);
      final runtime = _PublicSummaryRuntime(<CapsuleIndexEntry>[
        CapsuleIndexEntry(
          pubKeyHex: List.filled(32, 'aa').join(),
          createdAt: now,
          lastActive: now,
          isGenesis: true,
          isNeste: true,
          identityMode: 'root_owner',
        ),
        CapsuleIndexEntry(
          pubKeyHex: List.filled(32, 'bb').join(),
          createdAt: now.add(const Duration(minutes: 1)),
          lastActive: now,
          isGenesis: false,
          isNeste: true,
          identityMode: 'root_owner',
        ),
      ]);

      final capsules = await CapsuleSelectorService(runtime).loadCapsules();

      expect(capsules, hasLength(2));
      expect(runtime.publicSummaryCalls, equals(2));
      expect(runtime.activationCalls, isZero);
      expect(capsules.every((capsule) => capsule.starterCount == 5), isTrue);
    },
  );

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
      hasSeedByPubKey: <String, bool>{rootHex: true, legacyHex: true},
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
      hasSeedByPubKey: <String, bool>{nesteHex: true, hoodHex: true},
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
      hasSeedByPubKey: <String, bool>{oldHex: true, newHex: true},
      identityModeByPubKey: <String, String>{
        oldHex: 'root_owner',
        newHex: 'root_owner',
      },
    );

    expect(collapsed, hasLength(1));
    expect(collapsed.single.publicKeyHex, equals(newHex));
  });

  test('keeps selector order stable when last active timestamps change', () {
    final createdA = DateTime.utc(2026, 3, 31, 10);
    final createdB = createdA.add(const Duration(minutes: 1));
    final capsuleA = List.filled(32, '11').join();
    final capsuleB = List.filled(32, '22').join();

    List<String> orderedKeys({required bool activateB}) {
      final items = CapsuleSelectorService.collapseDisplayDuplicates(
        <CapsuleSelectorItem>[
          _item(
            pubKeyHex: capsuleA,
            displayKeyText: 'h1capsule-a',
            network: 'NESTE',
            ledgerVersion: 1,
            createdAt: createdA,
            lastActive:
                activateB ? createdA : createdB.add(const Duration(hours: 1)),
          ),
          _item(
            pubKeyHex: capsuleB,
            displayKeyText: 'h1capsule-b',
            network: 'NESTE',
            ledgerVersion: 1,
            createdAt: createdB,
            lastActive:
                activateB ? createdB.add(const Duration(hours: 1)) : createdB,
          ),
        ],
        hasSeedByPubKey: <String, bool>{capsuleA: true, capsuleB: true},
        identityModeByPubKey: <String, String>{
          capsuleA: 'root_owner',
          capsuleB: 'root_owner',
        },
      );
      return items.map((item) => item.publicKeyHex).toList();
    }

    expect(orderedKeys(activateB: false), equals(<String>[capsuleA, capsuleB]));
    expect(orderedKeys(activateB: true), equals(<String>[capsuleA, capsuleB]));
  });

  test('maps a missing capsule seed to recovery-required outcome', () async {
    final service = CapsuleSelectorService(
      _ActivationRuntime(
        activationError: const CapsuleSeedRequiredException('aa'),
      ),
    );

    expect(await service.activateCapsule('aa'), isFalse);
  });

  test('does not hide unrelated activation failures', () async {
    final service = CapsuleSelectorService(
      _ActivationRuntime(activationError: StateError('ledger damaged')),
    );

    expect(() => service.activateCapsule('aa'), throwsA(isA<StateError>()));
  });
}
