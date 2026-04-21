import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/screens/invitations_screen.dart';
import 'package:hivra_app/services/invitation_intent_handler.dart';

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

  test(
      'bucketInvitationsForUi keeps terminal invites in history even when local resolved set contains same ids',
      () {
    final buckets = bucketInvitationsForUi(
      <Invitation>[
        _invitation(
            id: 'acc', status: InvitationStatus.accepted, incoming: true),
        _invitation(
            id: 'rej', status: InvitationStatus.rejected, incoming: true),
        _invitation(
            id: 'exp', status: InvitationStatus.expired, incoming: false),
      ],
      const <String>{'acc', 'rej', 'exp'},
    );

    expect(buckets.incomingPending, isEmpty);
    expect(buckets.outgoingPending, isEmpty);
    expect(
      buckets.history.map((inv) => inv.id).toSet(),
      equals(<String>{'acc', 'rej', 'exp'}),
    );
  });

  test('shouldRetainLocalResolvedIncoming keeps local suppression on success',
      () {
    const result = InvitationIntentResult(code: 0, message: 'ok');
    expect(shouldRetainLocalResolvedIncoming(result), isTrue);
  });

  test('shouldRetainLocalResolvedIncoming clears local suppression on failure',
      () {
    const result = InvitationIntentResult(code: -1, message: 'fail');
    expect(shouldRetainLocalResolvedIncoming(result), isFalse);
  });

  test(
      'mergeQueuedInvitationFetchRequest keeps quick+silent only when both requests are quick+silent',
      () {
    final merged = mergeQueuedInvitationFetchRequest(
      queuedSilent: true,
      queuedQuick: true,
      incomingSilent: true,
      incomingQuick: true,
    );
    expect(merged.silent, isTrue);
    expect(merged.quick, isTrue);
  });

  test(
      'mergeQueuedInvitationFetchRequest escalates to non-silent when any request is non-silent',
      () {
    final merged = mergeQueuedInvitationFetchRequest(
      queuedSilent: true,
      queuedQuick: true,
      incomingSilent: false,
      incomingQuick: true,
    );
    expect(merged.silent, isFalse);
    expect(merged.quick, isTrue);
  });

  test(
      'mergeQueuedInvitationFetchRequest escalates to full fetch when any request is non-quick',
      () {
    final merged = mergeQueuedInvitationFetchRequest(
      queuedSilent: true,
      queuedQuick: true,
      incomingSilent: true,
      incomingQuick: false,
    );
    expect(merged.silent, isTrue);
    expect(merged.quick, isFalse);
  });

  test(
      'pruneLocallyResolvedIncomingIds drops suppression when invitation is absent',
      () {
    final kept = pruneLocallyResolvedIncomingIds(
      resolvedIds: const <String>{'inv_1'},
      projectedInvitations: const <Invitation>[],
    );

    expect(kept, isEmpty);
  });

  test(
      'pruneLocallyResolvedIncomingIds removes suppression when invitation becomes terminal',
      () {
    final kept = pruneLocallyResolvedIncomingIds(
      resolvedIds: const <String>{'inv_2'},
      projectedInvitations: <Invitation>[
        _invitation(
          id: 'inv_2',
          status: InvitationStatus.accepted,
          incoming: true,
        ),
      ],
    );

    expect(kept, isEmpty);
  });

  test(
      'pruneLocallyResolvedIncomingIds keeps suppression while incoming invitation remains pending',
      () {
    final kept = pruneLocallyResolvedIncomingIds(
      resolvedIds: const <String>{'inv_3'},
      projectedInvitations: <Invitation>[
        _invitation(
          id: 'inv_3',
          status: InvitationStatus.pending,
          incoming: true,
        ),
      ],
    );

    expect(kept, equals(const <String>{'inv_3'}));
  });
}
