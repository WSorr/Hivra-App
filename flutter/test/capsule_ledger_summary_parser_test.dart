import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_ledger_summary_parser.dart';

void main() {
  group('CapsuleLedgerSummaryParser', () {
    const parser = CapsuleLedgerSummaryParser();

    String toHex(Uint8List bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    List<int> rep(int value) => List<int>.filled(32, value);

    List<int> invitationSentPayload({
      required int invitationByte,
      required int starterByte,
      required List<int> toPubkey,
      int starterKindByte = 0,
    }) {
      return <int>[
        ...rep(invitationByte),
        ...rep(starterByte),
        ...toPubkey,
        starterKindByte,
      ];
    }

    List<int> invitationAcceptedPayload({
      required int invitationByte,
      required int fromByte,
      required int createdStarterByte,
    }) {
      return <int>[
        ...rep(invitationByte),
        ...rep(fromByte),
        ...rep(createdStarterByte),
      ];
    }

    List<int> invitationRejectedPayload({
      required int invitationByte,
      int reason = 1,
    }) {
      return <int>[
        ...rep(invitationByte),
        reason,
      ];
    }

    List<int> invitationExpiredPayload({
      required int invitationByte,
    }) {
      return rep(invitationByte);
    }

    Map<String, dynamic> event({
      required String kind,
      required List<int> payload,
      required int timestamp,
      required List<int> signer,
    }) {
      return <String, dynamic>{
        'kind': kind,
        'payload': payload,
        'timestamp': timestamp,
        'signer': signer,
      };
    }

    test('pending count follows invitation terminal precedence', () {
      final self = rep(0xaa);
      final peer = rep(0xbb);
      final otherPeer = rep(0xcc);
      const t0 = 1800000000000;

      final ledger = jsonEncode(<String, dynamic>{
        'owner': self,
        'events': <Map<String, dynamic>>[
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x11,
              starterByte: 0x21,
              toPubkey: peer,
            ),
            timestamp: t0 + 1,
            signer: self,
          ),
          event(
            kind: 'InvitationAccepted',
            payload: invitationAcceptedPayload(
              invitationByte: 0x11,
              fromByte: 0xbb,
              createdStarterByte: 0x31,
            ),
            timestamp: t0 + 2,
            signer: peer,
          ),
          event(
            kind: 'InvitationRejected',
            payload: invitationRejectedPayload(invitationByte: 0x11),
            timestamp: t0 + 3,
            signer: peer,
          ),
          event(
            kind: 'InvitationExpired',
            payload: invitationExpiredPayload(invitationByte: 0x11),
            timestamp: t0 + 4,
            signer: peer,
          ),
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x12,
              starterByte: 0x22,
              toPubkey: otherPeer,
            ),
            timestamp: t0 + 5,
            signer: self,
          ),
        ],
      });

      final summary = parser.parse(ledger, toHex);
      expect(summary.pendingInvitations, equals(1));
    });

    test('pending count includes incoming invitation offers', () {
      final self = rep(0xaa);
      final peer = rep(0xbb);
      const t0 = 1800000100000;

      final ledger = jsonEncode(<String, dynamic>{
        'owner': self,
        'events': <Map<String, dynamic>>[
          event(
            kind: 'InvitationReceived',
            payload: invitationSentPayload(
              invitationByte: 0x13,
              starterByte: 0x23,
              toPubkey: self,
            ),
            timestamp: t0 + 1,
            signer: peer,
          ),
        ],
      });

      final summary = parser.parse(ledger, toHex);
      expect(summary.pendingInvitations, equals(1));
    });

    test('parseBytesField decodes hex and base64 payload strings', () {
      expect(parser.parseBytesField('0a0b0c'), equals(<int>[10, 11, 12]));
      expect(parser.parseBytesField('AQID'), equals(<int>[1, 2, 3]));
    });

    test('parseBytesField preserves empty list and rejects invalid values', () {
      expect(parser.parseBytesField(<int>[]), equals(<int>[]));
      expect(parser.parseBytesField(<dynamic>[1, 300]), isNull);
      expect(parser.parseBytesField(''), isNull);
      expect(parser.parseBytesField(42), isNull);
    });
  });
}
