import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/relationship_service.dart';

void main() {
  Relationship sampleRelationship({
    String peerPubkey = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
    String ownStarterId = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
    String peerStarterId = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=',
  }) {
    return Relationship(
      peerPubkey: peerPubkey,
      kind: StarterKind.juice,
      ownStarterId: ownStarterId,
      peerStarterId: peerStarterId,
      establishedAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('breakRelationship returns false for invalid ids', () async {
    var breakCalls = 0;
    var persistCalls = 0;
    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) {
        breakCalls += 1;
        return true;
      },
      persistLedgerSnapshot: () async {
        persistCalls += 1;
      },
    );

    final ok = await service.breakRelationship(
      sampleRelationship(peerPubkey: 'invalid'),
    );

    expect(ok, isFalse);
    expect(breakCalls, equals(0));
    expect(persistCalls, equals(0));
  });

  test('breakRelationship calls breaker and persists on success', () async {
    var breakCalls = 0;
    var persistCalls = 0;
    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) {
        breakCalls += 1;
        return true;
      },
      persistLedgerSnapshot: () async {
        persistCalls += 1;
      },
    );

    final ok = await service.breakRelationship(sampleRelationship());

    expect(ok, isTrue);
    expect(breakCalls, equals(1));
    expect(persistCalls, equals(1));
  });

  test('confirmRemoteBreak delegates through break flow', () async {
    var breakCalls = 0;
    var persistCalls = 0;
    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) {
        breakCalls += 1;
        return true;
      },
      persistLedgerSnapshot: () async {
        persistCalls += 1;
      },
    );

    final ok = await service.confirmRemoteBreak(sampleRelationship());

    expect(ok, isTrue);
    expect(breakCalls, equals(1));
    expect(persistCalls, equals(1));
  });
}
