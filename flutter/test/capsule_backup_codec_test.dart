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
      final backup =
          CapsuleBackupCodec.encodeBackupEnvelope(ledgerJson: ledger);

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
      final ownerHex = List<int>.filled(32, 0xaa)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
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
  });
}
