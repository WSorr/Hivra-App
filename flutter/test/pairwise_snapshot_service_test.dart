import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/pairwise_snapshot_service.dart';

void main() {
  group('PairwiseSnapshotService', () {
    const service = PairwiseSnapshotService();

    test('handles numeric event kinds with shared ledger kind mapping', () {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 1));
      final ownStarter = Uint8List.fromList(List<int>.filled(32, 2));
      final peerTransport = Uint8List.fromList(List<int>.filled(32, 3));
      final peerRoot = Uint8List.fromList(List<int>.filled(32, 4));
      final peerStarter = Uint8List.fromList(List<int>.filled(32, 5));
      final sender = Uint8List.fromList(List<int>.filled(32, 6));
      final senderStarter = Uint8List.fromList(List<int>.filled(32, 7));
      final acceptedFrom = Uint8List.fromList(List<int>.filled(32, 8));
      final acceptedCreated = Uint8List.fromList(List<int>.filled(32, 9));
      final localTransport = Uint8List.fromList(List<int>.filled(32, 11));

      final invitationSentPayload = <int>[
        ...invitationId,
        ...ownStarter,
        ...peerTransport,
        1,
      ];
      final relationshipEstablishedPayload = <int>[
        ...peerRoot,
        ...ownStarter,
        ...peerStarter,
        1,
        ...invitationId,
        ...sender,
        1,
        ...senderStarter,
      ];
      final invitationAcceptedPayload = <int>[
        ...invitationId,
        ...acceptedFrom,
        ...acceptedCreated,
      ];

      final events = <Map<String, dynamic>>[
        <String, dynamic>{'kind': 1, 'payload': invitationSentPayload},
        <String, dynamic>{
          'kind': 7,
          'payload': relationshipEstablishedPayload,
        },
        <String, dynamic>{'kind': 2, 'payload': invitationAcceptedPayload},
      ];

      final snapshots = service.buildSnapshots(events, localTransport);

      expect(snapshots.length, 1);
      final row = snapshots.first;
      expect(row.invitationCount, 1);
      expect(row.relationshipCount, 1);
      expect(row.canonicalJson.contains('"status": "accepted"'), isTrue);
      expect(row.canonicalJson.contains('"relationship_kind": 1'), isTrue);
    });
  });
}
