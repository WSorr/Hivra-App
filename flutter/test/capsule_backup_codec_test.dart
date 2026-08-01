import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_backup_codec.dart';

void main() {
  group('CapsuleBackupCodec.tryExtractLedgerJson', () {
    test('extracts ledger from valid v1 envelope', () {
      final ledger = jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, 7),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent'},
        ],
      });
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: ledger,
      );

      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backup);

      expect(extracted, isNotNull);
      final decoded = jsonDecode(extracted!) as Map<String, dynamic>;
      expect(decoded['owner'], equals(List<int>.filled(32, 7)));
      expect((decoded['events'] as List).length, 1);
    });

    test('accepts valid legacy raw ledger json', () {
      final raw = jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, 9),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'StarterCreated'},
        ],
      });

      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(raw);

      expect(extracted, isNotNull);
    });

    test('rejects envelope with malformed owner bytes', () {
      final malformedEnvelope = jsonEncode(<String, dynamic>{
        'schema': CapsuleBackupCodec.schema,
        'version': CapsuleBackupCodec.version,
        'ledger': <String, dynamic>{
          'owner': <int>[1, 2, 3],
          'events': <Object>[],
        },
      });

      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(
        malformedEnvelope,
      );

      expect(extracted, isNull);
    });

    test('rejects raw ledger when events is not a list', () {
      final malformedRaw = jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, 1),
        'events': <String, dynamic>{'bad': true},
      });

      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(malformedRaw);

      expect(extracted, isNull);
    });

    test('accepts owner as 64-char hex string', () {
      final ownerHex =
          List<int>.filled(
            32,
            0xaa,
          ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final raw = jsonEncode(<String, dynamic>{
        'owner': ownerHex,
        'events': <Object>[],
      });

      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(raw);

      expect(extracted, isNotNull);
    });

    test('accepts owner as base64 for 32 bytes', () {
      final ownerBase64 = base64Encode(List<int>.filled(32, 0xbb));
      final raw = jsonEncode(<String, dynamic>{
        'owner': ownerBase64,
        'events': <Object>[],
      });

      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(raw);

      expect(extracted, isNotNull);
    });

    test('preserves continuous v5 evidence through backup envelope', () {
      final ledger = <String, dynamic>{
        'owner': List<int>.filled(32, 0xaa),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'version': 5,
            'kind': 'InvitationSent',
            'payload': <int>[1, 2, 3],
            'timestamp': 123,
            'signature': List<int>.filled(64, 0xbb),
            'signer': List<int>.filled(32, 0xcc),
          },
        ],
        'last_hash': '0',
        'head_commitment_v5': List<String>.filled(32, '11').join(),
        'continuity_v5': <String, dynamic>{
          'anchor': <String, dynamic>{
            'Fresh': <String, dynamic>{'owner': List<int>.filled(32, 0xaa)},
          },
          'legacy_event_count': 0,
          'receipts': <Map<String, dynamic>>[
            <String, dynamic>{
              'sequence': 0,
              'previous_commitment': List<int>.filled(32, 0x22),
              'signature': List<int>.filled(64, 0x33),
            },
          ],
        },
      };

      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: jsonEncode(ledger),
      );
      final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backup);

      expect(extracted, isNotNull);
      expect(jsonDecode(extracted!), equals(ledger));
    });
  });
}
