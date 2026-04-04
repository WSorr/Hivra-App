import 'dart:typed_data';

import 'package:bech32/bech32.dart';
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
    List<int> convertBits(List<int> data, int from, int to, bool pad) {
      var acc = 0;
      var bits = 0;
      final result = <int>[];
      final maxValue = (1 << to) - 1;

      for (final value in data) {
        if (value < 0 || (value >> from) != 0) {
          throw ArgumentError('invalid value');
        }
        acc = (acc << from) | value;
        bits += from;
        while (bits >= to) {
          bits -= to;
          result.add((acc >> bits) & maxValue);
        }
      }

      if (pad) {
        if (bits > 0) {
          result.add((acc << (to - bits)) & maxValue);
        }
      } else if (bits >= from || ((acc << (to - bits)) & maxValue) != 0) {
        throw ArgumentError('invalid padding');
      }

      return result;
    }

    String encodeBech32(String hrp, String hex) {
      final bytes = Uint8List.fromList(<int>[
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      final words = convertBits(bytes, 8, 5, true);
      return bech32.encode(Bech32(hrp, words));
    }

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

    test('matches by root bech32 entry key', () {
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey: encodeBech32('h', rootHex),
          entryValue: entryValue,
          deleteKeyHex: rootHex,
        ),
        isTrue,
      );
    });

    test('matches by npub entry key', () {
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey: encodeBech32('npub', nostrHex),
          entryValue: entryValue,
          deleteKeyHex: nostrHex,
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

    test('matches by legacy rootKey field when rootHex is absent', () {
      final legacy = <String, dynamic>{
        'version': 1,
        'rootKey': encodeBech32('h', rootHex),
        'transports': {
          'nostr': {
            'npub': encodeBech32('npub', nostrHex),
          },
        },
      };
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          entryValue: legacy,
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

    test('matches by transport nostr npub field when hex is absent', () {
      final legacy = <String, dynamic>{
        'version': 1,
        'rootHex': rootHex,
        'transports': {
          'nostr': {
            'npub': encodeBech32('npub', nostrHex),
          },
        },
      };
      expect(
        shouldRemoveCapsuleContactCardEntry(
          entryKey:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          entryValue: legacy,
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
