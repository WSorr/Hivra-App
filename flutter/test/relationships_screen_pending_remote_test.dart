import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/relationships_screen.dart';

void main() {
  test('computeNewPendingRemoteBreakKeys returns newly appeared keys only', () {
    final newKeys = computeNewPendingRemoteBreakKeys(
      currentPendingKeys: <String>{'a', 'b'},
      previousPendingKeys: <String>{'a'},
      notifiedKeys: <String>{},
    );

    expect(newKeys, equals(<String>{'b'}));
  });

  test('computeNewPendingRemoteBreakKeys suppresses already notified keys', () {
    final prunedNotified = pruneNotifiedPendingRemoteBreakKeys(
      notifiedKeys: <String>{'a', 'b'},
      currentPendingKeys: <String>{'a'},
    );
    final newKeys = computeNewPendingRemoteBreakKeys(
      currentPendingKeys: <String>{'a'},
      previousPendingKeys: <String>{},
      notifiedKeys: prunedNotified,
    );

    expect(prunedNotified, equals(<String>{'a'}));
    expect(newKeys, isEmpty);
  });

  test('key becomes notifiable again after it leaves pending set', () {
    final prunedAfterClear = pruneNotifiedPendingRemoteBreakKeys(
      notifiedKeys: <String>{'a'},
      currentPendingKeys: <String>{},
    );
    final newKeys = computeNewPendingRemoteBreakKeys(
      currentPendingKeys: <String>{'a'},
      previousPendingKeys: <String>{},
      notifiedKeys: prunedAfterClear,
    );

    expect(prunedAfterClear, isEmpty);
    expect(newKeys, equals(<String>{'a'}));
  });

  test('suppresses repeated pending-remote toast inside cooldown window', () {
    final now = DateTime.utc(2026, 4, 19, 1, 30, 0);
    final lastShownAt = now.subtract(const Duration(seconds: 3));
    final suppressed = shouldSuppressPendingRemoteBreakNotification(
      now: now,
      lastShownAt: lastShownAt,
      cooldown: const Duration(seconds: 8),
    );

    expect(suppressed, isTrue);
  });

  test('allows pending-remote toast after cooldown elapsed', () {
    final now = DateTime.utc(2026, 4, 19, 1, 30, 0);
    final lastShownAt = now.subtract(const Duration(seconds: 12));
    final suppressed = shouldSuppressPendingRemoteBreakNotification(
      now: now,
      lastShownAt: lastShownAt,
      cooldown: const Duration(seconds: 8),
    );

    expect(suppressed, isFalse);
  });

  test('defers pending-remote notifications until baseline is ready', () {
    expect(
      shouldDeferPendingRemoteBreakNotifications(baselineReady: false),
      isTrue,
    );
    expect(
      shouldDeferPendingRemoteBreakNotifications(baselineReady: true),
      isFalse,
    );
  });
}
