import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_chat_contract_service.dart';
import 'package:hivra_app/services/consensus_processor.dart';

void main() {
  group('CapsuleChatContractService', () {
    test('blocks when consensus path is not signable', () {
      final service = CapsuleChatContractService(
        readSignable: (_) => const ConsensusSignableResult(
          preview: null,
          blockingFacts: <ConsensusBlockingFact>[
            ConsensusBlockingFact(code: 'pending_invitation', subjectId: 'abc'),
          ],
        ),
      );

      final result = service.execute(
        peerHex: _peerHex,
        clientMessageId: 'msg-1',
        messageText: 'hello',
        createdAtUtc: '2026-04-04T10:00:00Z',
      );

      expect(result.isExecutable, isFalse);
      expect(result.envelope, isNull);
      expect(
        result.blockingFacts.map((fact) => fact.code),
        contains('pending_invitation'),
      );
    });

    test('produces deterministic envelope hash for identical inputs', () {
      final service = CapsuleChatContractService(
        readSignable: (_) => const ConsensusSignableResult(
          preview: ConsensusPreview(
            peerHex: _peerHex,
            peerLabel: 'peer',
            invitationCount: 1,
            relationshipCount: 1,
            hashHex:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            canonicalJson: '{}',
            blockingFacts: <ConsensusBlockingFact>[],
          ),
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      );

      final first = service.execute(
        peerHex: _peerHex,
        clientMessageId: 'msg-1',
        messageText: 'hello',
        createdAtUtc: '2026-04-04T10:00:00Z',
      );
      final second = service.execute(
        peerHex: _peerHex,
        clientMessageId: 'msg-1',
        messageText: 'hello',
        createdAtUtc: '2026-04-04T10:00:00Z',
      );

      expect(first.isExecutable, isTrue);
      expect(second.isExecutable, isTrue);
      expect(first.envelope, isNotNull);
      expect(first.envelope!.envelopeHashHex, second.envelope!.envelopeHashHex);
      expect(first.envelope!.canonicalJson, second.envelope!.canonicalJson);
    });
  });
}

const String _peerHex =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
