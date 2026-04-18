import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';

void main() {
  group('chatSendShouldRetry', () {
    test('retries for transient timeout/transport codes', () {
      expect(chatSendShouldRetry(code: -1003), isTrue);
      expect(chatSendShouldRetry(code: -11), isTrue);
      expect(chatSendShouldRetry(code: -12), isTrue);
      expect(chatSendShouldRetry(code: -13), isTrue);
      expect(chatSendShouldRetry(code: -6), isTrue);
    });

    test('retries when error message signals transient relay issues', () {
      expect(
        chatSendShouldRetry(
          code: -1,
          errorMessage: 'relay connection dropped',
        ),
        isTrue,
      );
      expect(
        chatSendShouldRetry(
          code: -1,
          errorMessage: 'timed out while publishing',
        ),
        isTrue,
      );
    });

    test('does not retry deterministic validation failures', () {
      expect(
        chatSendShouldRetry(
          code: -1,
          errorMessage: 'peer_hex must be a 64-char lowercase hex',
        ),
        isFalse,
      );
    });
  });

  group('tradeSignalInboxRecordId', () {
    test('separates same signal_id from different peers', () {
      const signalId = 'sig-123';
      final a = tradeSignalInboxRecordId(
        fromHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        signalId: signalId,
        timestampMs: 1,
        payloadJson: '{"x":1}',
      );
      final b = tradeSignalInboxRecordId(
        fromHex:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        signalId: signalId,
        timestampMs: 1,
        payloadJson: '{"x":1}',
      );

      expect(a, isNot(equals(b)));
    });

    test('keeps stable id for same peer and same signal_id', () {
      const fromHex =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      const signalId = 'sig-123';
      final first = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: signalId,
        timestampMs: 11,
        payloadJson: '{"x":1}',
      );
      final second = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: signalId,
        timestampMs: 12,
        payloadJson: '{"x":2}',
      );

      expect(first, equals(second));
    });

    test('falls back to deterministic hash when signal_id is empty', () {
      const fromHex =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final first = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: '',
        timestampMs: 10,
        payloadJson: '{"a":1}',
      );
      final second = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: '',
        timestampMs: 10,
        payloadJson: '{"a":1}',
      );
      final third = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: '',
        timestampMs: 11,
        payloadJson: '{"a":1}',
      );

      expect(first, equals(second));
      expect(first, isNot(equals(third)));
    });
  });
}
