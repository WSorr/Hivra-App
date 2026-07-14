import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_state_manager.dart';

void main() {
  CapsuleState stateFor(int byte) => CapsuleState(
        publicKey: Uint8List.fromList(List<int>.filled(32, byte)),
        starterCount: 0,
        relationshipCount: 0,
        pendingInvitations: 0,
        version: 0,
        ledgerHashHex: '0',
        hasLedgerHistory: false,
        isNeste: true,
        starterIds: const <Uint8List?>[],
        starterKinds: const <String?>[],
        lockedStarterSlots: const <int>{},
      );

  test('accepts projection only for the pinned capsule selection', () {
    final selected = List<String>.filled(32, 'aa').join();
    final other = List<String>.filled(32, 'bb').join();

    expect(
      capsuleStateMatchesSelection(
        state: stateFor(0xaa),
        selectedCapsuleHex: selected,
      ),
      isTrue,
    );
    expect(
      capsuleStateMatchesSelection(
        state: stateFor(0xbb),
        selectedCapsuleHex: selected,
        runtimeRootHex: other,
      ),
      isFalse,
    );
  });

  test('accepts legacy runtime owner only when root matches selection', () {
    final selectedRoot = List<String>.filled(32, 'cc').join();

    expect(
      capsuleStateMatchesSelection(
        state: stateFor(0xdd),
        selectedCapsuleHex: selectedRoot,
        runtimeRootHex: selectedRoot,
      ),
      isTrue,
    );
  });
}
