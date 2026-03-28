import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/ledger_view_support.dart';

void main() {
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
