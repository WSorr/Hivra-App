import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/ledger_view_support.dart';

void main() {
  group('LedgerViewSupport.kindLabel', () {
    const support = LedgerViewSupport();

    test('maps known numeric kinds', () {
      expect(support.kindLabel(1), equals('InvitationSent'));
      expect(support.kindLabel(9), equals('InvitationReceived'));
    });

    test('keeps string kind as-is and formats unknown int', () {
      expect(support.kindLabel('CustomKind'), equals('CustomKind'));
      expect(support.kindLabel(42), equals('Kind(42)'));
    });
  });

  group('LedgerViewSupport.payloadBytes', () {
    const support = LedgerViewSupport();

    test('decodes hex payload string', () {
      final bytes = support.payloadBytes('0a0b0c');
      expect(bytes, equals(Uint8List.fromList([10, 11, 12])));
    });

    test('decodes base64 payload string', () {
      final bytes = support.payloadBytes('AQID');
      expect(bytes, equals(Uint8List.fromList([1, 2, 3])));
    });

    test('rejects invalid list byte values', () {
      final bytes = support.payloadBytes(<dynamic>[1, 300, 3]);
      expect(bytes, isEmpty);
    });
  });
}
