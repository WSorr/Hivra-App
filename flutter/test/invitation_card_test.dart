import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/widgets/invitation_card.dart';

void main() {
  Finder expiresRowFinder() => find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data?.startsWith('Expires ') == true,
      );

  Invitation invitation({
    required InvitationStatus status,
    required bool incoming,
    DateTime? expiresAt,
    DateTime? respondedAt,
  }) {
    final now = DateTime.now();
    return Invitation(
      id: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      fromPubkey: 'ZmFrZS1mcm9tLWtleS0wMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=',
      toPubkey: incoming
          ? null
          : 'ZmFrZS10by1rZXktMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw',
      kind: StarterKind.juice,
      status: status,
      sentAt: now.subtract(const Duration(minutes: 5)),
      expiresAt: expiresAt,
      respondedAt: respondedAt,
    );
  }

  Future<void> pumpCard(WidgetTester tester, Invitation invitation) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvitationCard(invitation: invitation),
        ),
      ),
    );
  }

  testWidgets('shows expires row for outgoing pending invitation',
      (WidgetTester tester) async {
    final inv = invitation(
      status: InvitationStatus.pending,
      incoming: false,
      expiresAt: DateTime.now().add(const Duration(hours: 3)),
    );

    await pumpCard(tester, inv);

    expect(expiresRowFinder(), findsOneWidget);
  });

  testWidgets('does not show expires row for accepted invitation',
      (WidgetTester tester) async {
    final inv = invitation(
      status: InvitationStatus.accepted,
      incoming: false,
      expiresAt: DateTime.now().add(const Duration(hours: 3)),
      respondedAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    await pumpCard(tester, inv);

    expect(expiresRowFinder(), findsNothing);
    expect(find.text('Accepted'), findsWidgets);
  });

  testWidgets('does not show expires row for incoming pending invitation',
      (WidgetTester tester) async {
    final inv = invitation(
      status: InvitationStatus.pending,
      incoming: true,
      expiresAt: DateTime.now().add(const Duration(hours: 3)),
    );

    await pumpCard(tester, inv);

    expect(expiresRowFinder(), findsNothing);
  });
}
