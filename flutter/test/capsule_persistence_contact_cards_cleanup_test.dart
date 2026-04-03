import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_persistence_service.dart';

void main() {
  group('shouldRemoveCapsuleContactCardEntry', () {
    const rootHex =
        '2731da86268178f68d42479d8730f8a2b5c795d08480723c77fb19b6d890ff79';
    const nostrHex =
        'b62f784362aabca5fa72628018a9c2101635053bf3b8d31b5ae240b635364db5';

    final entryValue = <String, dynamic>{
      'version': 1,
      'rootHex': rootHex,
      'transports': {
        'nostr': {
          'hex': nostrHex,
        },
      },
    };

    test('matches by entry map key', () {
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey: rootHex,
          entryValue: entryValue,
          deleteKeyHex: rootHex,
        ),
        isTrue,
      );
    });

    test('matches by rootHex field', () {
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          entryValue: entryValue,
          deleteKeyHex: rootHex,
        ),
        isTrue,
      );
    });

    test('matches by transport nostr hex field', () {
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          entryValue: entryValue,
          deleteKeyHex: nostrHex,
        ),
        isTrue,
      );
    });

    test('does not match unrelated key', () {
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          entryValue: entryValue,
          deleteKeyHex:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        ),
        isFalse,
      );
    });
  });
}
