import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/relationship_projection_service.dart';

void main() {
  group('RelationshipProjectionService', () {
    test('maps the versioned Core view without inspecting ledger events', () {
      Uint8List? observedTransport;
      final service = RelationshipProjectionService((ledgerJson, transport) {
        expect(jsonDecode(ledgerJson), contains('events'));
        observedTransport = transport;
        return _view(<Map<String, Object?>>[
          _row(status: 'active', establishedAt: 1700000000),
          _row(
            peer: 7,
            ownStarter: 8,
            peerStarter: 9,
            kind: 3,
            status: 'pending_remote_break',
            establishedAt: 1700000100,
          ),
          _row(
            peer: 10,
            ownStarter: 11,
            peerStarter: 12,
            kind: 4,
            status: 'broken',
            establishedAt: 1700000050,
          ),
        ]);
      }, runtimeTransportPublicKey: () => Uint8List.fromList(_bytes(99)));

      final relationships = service.loadRelationships(<String, dynamic>{
        'events': <Object>[],
      });

      expect(observedTransport, orderedEquals(_bytes(99)));
      expect(relationships, hasLength(3));
      expect(relationships[0].kind, StarterKind.pulse);
      expect(relationships[0].isActive, isTrue);
      expect(relationships[0].hasPendingRemoteBreak, isTrue);
      expect(relationships[1].kind, StarterKind.kick);
      expect(relationships[1].isActive, isFalse);
      expect(relationships[2].kind, StarterKind.juice);
    });

    test('fails closed for malformed or unsupported projector output', () {
      for (final output in <String?>[
        null,
        '',
        '{',
        jsonEncode(<String, Object?>{
          'schema': 'hivra.relationship_current_view',
          'version': 2,
          'relationships': <Object>[],
        }),
      ]) {
        final service = RelationshipProjectionService((_, transport) => output);
        expect(service.loadRelationships(<String, dynamic>{}), isEmpty);
      }
    });

    test('drops invalid rows rather than manufacturing relationships', () {
      final service = RelationshipProjectionService(
        (_, transport) => _view(<Map<String, Object?>>[
          _row(status: 'active'),
          <String, Object?>{
            ..._row(status: 'active'),
            'own_starter_id': <int>[1, 2],
          },
          <String, Object?>{..._row(status: 'active'), 'status': 'unknown'},
        ]),
      );

      expect(service.loadRelationships(<String, dynamic>{}), hasLength(1));
    });

    test('groups canonical rows by root identity while preserving links', () {
      final sharedRoot = _bytes(42);
      final service = RelationshipProjectionService(
        (_, transport) => _view(<Map<String, Object?>>[
          _row(peer: 1, peerRoot: sharedRoot, ownStarter: 10),
          _row(peer: 2, peerIdentity: sharedRoot, ownStarter: 11),
          _row(peer: 3, ownStarter: 12),
        ]),
      );

      final groups = service.loadRelationshipGroups(<String, dynamic>{});

      expect(groups, hasLength(2));
      expect(
        groups.map((group) => group.relationships.length),
        containsAll(<int>[1, 2]),
      );
    });
  });
}

String _view(List<Map<String, Object?>> rows) => jsonEncode(<String, Object?>{
  'schema': 'hivra.relationship_current_view',
  'version': 1,
  'ledger_version': 3,
  'active_peer_count': 1,
  'relationships': rows,
});

Map<String, Object?> _row({
  int peer = 1,
  List<int>? peerRoot,
  List<int>? peerIdentity,
  int ownStarter = 2,
  int peerStarter = 3,
  int kind = 0,
  String status = 'active',
  int establishedAt = 1700000000,
}) => <String, Object?>{
  'peer_pubkey': _bytes(peer),
  'peer_root_pubkey': peerRoot,
  'peer_identity': peerIdentity ?? peerRoot ?? _bytes(peer),
  'own_starter_id': _bytes(ownStarter),
  'peer_starter_id': _bytes(peerStarter),
  'starter_kind': kind,
  'established_at': establishedAt,
  'status': status,
};

List<int> _bytes(int value) => List<int>.filled(32, value);
