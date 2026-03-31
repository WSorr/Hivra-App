import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/screens/invitations_screen.dart';

Invitation _invitation({
  required String id,
  required InvitationStatus status,
  required bool incoming,
}) {
  final now = DateTime.utc(2026, 3, 31, 12, 0, 0);
  return Invitation(
    id: id,
    fromPubkey: 'ZmFrZS1mcm9tLWtleS0wMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=',
    toPubkey: incoming
        ? null
        : 'ZmFrZS10by1rZXktMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw',
    kind: StarterKind.juice,
    status: status,
    sentAt: now,
    expiresAt: now.add(const Duration(hours: 24)),
  );
}

void main() {
  test('bucketInvitationsForUi keeps actionable queues pending-only', () {
    final buckets = bucketInvitationsForUi(
      <Invitation>[
        _invitation(
            id: 'in_pending', status: InvitationStatus.pending, incoming: true),
        _invitation(
            id: 'in_accepted',
            status: InvitationStatus.accepted,
            incoming: true),
        _invitation(
            id: 'out_pending',
            status: InvitationStatus.pending,
            incoming: false),
        _invitation(
            id: 'out_rejected',
            status: InvitationStatus.rejected,
            incoming: false),
      ],
      const <String>{},
    );

    expect(
      buckets.incomingPending.map((inv) => inv.id).toList(),
      equals(<String>['in_pending']),
    );
    expect(
      buckets.outgoingPending.map((inv) => inv.id).toList(),
      equals(<String>['out_pending']),
    );
    expect(
      buckets.history.map((inv) => inv.id).toSet(),
      equals(<String>{'in_accepted', 'out_rejected'}),
    );
  });

  test('bucketInvitationsForUi hides locally resolved incoming pending rows',
      () {
    final buckets = bucketInvitationsForUi(
      <Invitation>[
        _invitation(
            id: 'pending_a', status: InvitationStatus.pending, incoming: true),
        _invitation(
            id: 'pending_b', status: InvitationStatus.pending, incoming: true),
      ],
      const <String>{'pending_b'},
    );

    expect(
      buckets.incomingPending.map((inv) => inv.id).toList(),
      equals(<String>['pending_a']),
    );
    expect(buckets.outgoingPending, isEmpty);
    expect(buckets.history, isEmpty);
  });
}
