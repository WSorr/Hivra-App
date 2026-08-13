import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/invitations_screen.dart';

void main() {
  test(
    'explicit refresh reloads invitations when ledger version is unchanged',
    () {
      expect(
        shouldReloadInvitationsProjection(
          previousCapsuleHex: 'capsule-a',
          currentCapsuleHex: 'capsule-a',
          previousLedgerVersion: 7,
          currentLedgerVersion: 7,
          previousRefreshRevision: 2,
          currentRefreshRevision: 3,
        ),
        isTrue,
      );
    },
  );

  test('unchanged projection inputs do not trigger a redundant reload', () {
    expect(
      shouldReloadInvitationsProjection(
        previousCapsuleHex: 'capsule-a',
        currentCapsuleHex: 'capsule-a',
        previousLedgerVersion: 7,
        currentLedgerVersion: 7,
        previousRefreshRevision: 2,
        currentRefreshRevision: 2,
      ),
      isFalse,
    );
  });

  testWidgets('successful explicit refresh shows the invitation result', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showInvitationUserMessage(context, 'Invitation refresh complete');
    await tester.pump();

    expect(find.text('Invitation refresh complete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
