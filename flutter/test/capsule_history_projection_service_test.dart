import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_history_projection_service.dart';

void main() {
  test(
    'invitation history includes its lifecycle and relationship provenance',
    () {
      final invite = List<int>.filled(32, 1);
      final starter = List<int>.filled(32, 2);
      final peer = List<int>.filled(32, 3);
      final otherInvite = List<int>.filled(32, 9);
      final events = <Map<String, dynamic>>[
        _event(1, <int>[...invite, ...starter, ...peer], 100),
        _event(1, <int>[...otherInvite, ...starter, ...peer], 101),
        _event(2, <int>[...invite, ...peer, ...starter], 102),
        _event(7, <int>[
          ...peer,
          ...starter,
          ...List<int>.filled(32, 4),
          0,
          ...invite,
          ...peer,
          0,
          ...starter,
        ], 103),
      ];
      final service = _service(events);

      final projection = service.project(
        CapsuleHistorySubject.invitation(
          invitationId: base64.encode(invite),
          displayLabel: 'Juice invitation',
        ),
      );

      expect(projection.entries.map((entry) => entry.eventKind), <String>[
        'InvitationSent',
        'InvitationAccepted',
        'RelationshipEstablished',
      ]);
      expect(projection.entries.map((entry) => entry.ledgerIndex), <int>[
        0,
        2,
        3,
      ]);
    },
  );

  test(
    'starter history follows creation, invitation, relationship, and burn',
    () {
      final invite = List<int>.filled(32, 1);
      final starter = List<int>.filled(32, 2);
      final peer = List<int>.filled(32, 3);
      final nonce = List<int>.filled(32, 8);
      final events = <Map<String, dynamic>>[
        _event(5, <int>[...starter, ...nonce, 1, 1], 200),
        _event(1, <int>[...invite, ...starter, ...peer], 201),
        _event(8, <int>[...peer, ...starter], 202),
        _event(6, <int>[...starter, 0], 203),
      ];
      final service = _service(events);

      final projection = service.project(
        CapsuleHistorySubject.starter(
          starterId: base64.encode(starter),
          displayLabel: 'Spark starter',
        ),
      );

      expect(projection.entries, hasLength(4));
      expect(projection.entries.last.eventKind, 'StarterBurned');
    },
  );

  test('relationship history is peer-scoped and replay hash is stable', () {
    final peer = List<int>.filled(32, 3);
    final otherPeer = List<int>.filled(32, 7);
    final starter = List<int>.filled(32, 2);
    final events = <Map<String, dynamic>>[
      _event(8, <int>[...otherPeer, ...starter], 300),
      _event(8, <int>[...peer, ...starter], 301),
    ];
    final service = _service(events);
    final subject = CapsuleHistorySubject.relationship(
      peerTransportKey: base64.encode(peer),
      displayLabel: 'Peer',
    );

    final first = service.project(subject);
    final replay = service.project(subject);

    expect(first.entries, hasLength(1));
    expect(first.entries.single.ledgerIndex, 1);
    expect(replay.projectionHashHex, first.projectionHashHex);
  });
}

CapsuleHistoryProjectionService _service(List<Map<String, dynamic>> events) {
  final ledger = jsonEncode(<String, dynamic>{'events': events});
  return CapsuleHistoryProjectionService(exportLedger: () => ledger);
}

Map<String, dynamic> _event(int kind, List<int> payload, int timestamp) =>
    <String, dynamic>{'kind': kind, 'payload': payload, 'timestamp': timestamp};
