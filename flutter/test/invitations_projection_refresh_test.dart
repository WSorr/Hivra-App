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
}
