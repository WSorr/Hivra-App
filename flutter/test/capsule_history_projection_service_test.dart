import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_history_projection_service.dart';

void main() {
  test(
    'maps the versioned Core HistoryView and keeps advisory hash stable',
    () {
      final invitationId = List<int>.filled(32, 1);
      final starterId = List<int>.filled(32, 2);
      final subject = CapsuleHistorySubject.invitation(
        invitationId: base64.encode(invitationId),
        displayLabel: 'Juice invitation',
      );
      String? requestSeen;
      final service = CapsuleHistoryProjectionService(
        exportLedger: () => '{"events":[]}',
        projectHistoryView: (ledger, request) {
          requestSeen = request;
          return _historyView(
            kind: 'invitation',
            primaryId: invitationId,
            entries: <Map<String, dynamic>>[
              _entry(
                index: 0,
                kind: 'InvitationSent',
                timestamp: 100,
                code: 'invitation_sent',
                ids: <List<int>>[invitationId, starterId],
              ),
              _entry(
                index: 2,
                kind: 'InvitationAccepted',
                timestamp: 102,
                code: 'invitation_accepted',
                ids: <List<int>>[invitationId, starterId],
              ),
            ],
          );
        },
      );

      final first = service.project(subject);
      final replay = service.project(subject);
      final request = jsonDecode(requestSeen!) as Map<String, dynamic>;

      expect(request['schema'], 'hivra.history_view.request');
      expect(request['version'], 1);
      expect(request['subject']['kind'], 'invitation');
      expect(request['subject']['primary_id'], invitationId);
      expect(first.entries.map((entry) => entry.eventKind), <String>[
        'InvitationSent',
        'InvitationAccepted',
      ]);
      expect(first.entries.first.summary, contains('sent with starter'));
      expect(first.entries.last.summary, contains('accepted'));
      expect(replay.projectionHashHex, first.projectionHashHex);
    },
  );

  test('relationship request carries transport and root aliases', () {
    final transport = List<int>.filled(32, 3);
    final root = List<int>.filled(32, 4);
    String? requestSeen;
    final service = CapsuleHistoryProjectionService(
      exportLedger: () => '{}',
      projectHistoryView: (_, request) {
        requestSeen = request;
        return _historyView(
          kind: 'relationship',
          primaryId: transport,
          secondaryId: root,
          entries: <Map<String, dynamic>>[
            _entry(
              index: 1,
              kind: 'RelationshipBroken',
              timestamp: 301,
              code: 'relationship_broken',
              ids: <List<int>>[transport],
            ),
          ],
        );
      },
    );

    final projection = service.project(
      CapsuleHistorySubject.relationship(
        peerTransportKey: base64.encode(transport),
        peerRootKey: base64.encode(root),
        displayLabel: 'Peer',
      ),
    );
    final request = jsonDecode(requestSeen!) as Map<String, dynamic>;

    expect(request['subject']['secondary_id'], root);
    expect(projection.entries.single.summary, contains('broken'));
  });

  test('fails closed for unavailable, stale, or mismatched Core views', () {
    final starter = List<int>.filled(32, 5);
    final subject = CapsuleHistorySubject.starter(
      starterId: base64.encode(starter),
      displayLabel: 'Starter',
    );

    CapsuleHistoryProjection project(String? view) =>
        CapsuleHistoryProjectionService(
          exportLedger: () => '{}',
          projectHistoryView: (_, unused) => view,
        ).project(subject);

    expect(project(null).entries, isEmpty);
    expect(
      project('{"schema":"hivra.history_view","version":2}').entries,
      isEmpty,
    );
    expect(
      project(
        _historyView(
          kind: 'starter',
          primaryId: List<int>.filled(32, 6),
          entries: const <Map<String, dynamic>>[],
        ),
      ).entries,
      isEmpty,
    );
  });
}

String _historyView({
  required String kind,
  required List<int> primaryId,
  List<int>? secondaryId,
  required List<Map<String, dynamic>> entries,
}) => jsonEncode(<String, dynamic>{
  'schema': 'hivra.history_view',
  'version': 1,
  'ledger_version': entries.length,
  'subject': <String, dynamic>{
    'kind': kind,
    'primary_id': primaryId,
    'secondary_id': secondaryId,
  },
  'entries': entries,
});

Map<String, dynamic> _entry({
  required int index,
  required String kind,
  required int timestamp,
  required String code,
  required List<List<int>> ids,
  int? starterKind,
  int? reason,
}) => <String, dynamic>{
  'ledger_index': index,
  'event_kind': kind,
  'timestamp': timestamp,
  'summary_code': code,
  'summary_ids': ids,
  'starter_kind': starterKind,
  'reason': reason,
};
