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
}
