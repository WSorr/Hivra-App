import 'dart:typed_data';

import 'consensus_processor.dart';
import 'ledger_view_support.dart';

typedef LedgerExporter = String? Function();
typedef TransportKeyReader = Uint8List? Function();

class ConsensusCheck {
  final String peerHex;
  final String peerLabel;
  final int invitationCount;
  final int relationshipCount;
  final String hashHex;
  final String canonicalJson;
  final bool isSignable;
  final List<ConsensusBlockingFact> blockingFacts;

  const ConsensusCheck({
    required this.peerHex,
    required this.peerLabel,
    required this.invitationCount,
    required this.relationshipCount,
    required this.hashHex,
    required this.canonicalJson,
    required this.isSignable,
    required this.blockingFacts,
  });
}

class ConsensusRuntimeService {
  final LedgerExporter _exportLedger;
  final TransportKeyReader _readLocalTransportKey;
  final LedgerViewSupport _support;
  final ConsensusProcessor _processor;

  const ConsensusRuntimeService({
    required LedgerExporter exportLedger,
    required TransportKeyReader readLocalTransportKey,
    LedgerViewSupport support = const LedgerViewSupport(),
    ConsensusProcessor processor = const ConsensusProcessor(),
  })  : _exportLedger = exportLedger,
        _readLocalTransportKey = readLocalTransportKey,
        _support = support,
        _processor = processor;

  List<ConsensusPreview> preview() {
    final inputs = _runtimeInputs();
    if (inputs == null) return const <ConsensusPreview>[];
    return _processor.preview(inputs.events, inputs.localTransportKey);
  }

  List<ConsensusCheck> checks() {
    final previews = preview();
    return previews.map((preview) {
      final signableResult = signable(preview.peerHex);
      return ConsensusCheck(
        peerHex: preview.peerHex,
        peerLabel: preview.peerLabel,
        invitationCount: preview.invitationCount,
        relationshipCount: preview.relationshipCount,
        hashHex: preview.hashHex,
        canonicalJson: preview.canonicalJson,
        isSignable: signableResult.isSignable,
        blockingFacts: signableResult.blockingFacts,
      );
    }).toList(growable: false);
  }

  ConsensusSignableResult signable(String peerHex) {
    final inputs = _runtimeInputs();
    if (inputs == null) {
      return const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'consensus_runtime_unavailable'),
        ],
      );
    }
    return _processor.signable(
      inputs.events,
      inputs.localTransportKey,
      peerHex: peerHex,
    );
  }

  ConsensusVerifyResult verify({
    required String expectedHashHex,
    required List<ConsensusVerifyParticipant> participants,
  }) {
    return _processor.verify(
      expectedHashHex: expectedHashHex,
      participants: participants,
    );
  }

  _ConsensusRuntimeInputs? _runtimeInputs() {
    final ledgerRoot = _support.exportLedgerRoot(_exportLedger());
    final localTransportKey = _readLocalTransportKey();
    if (ledgerRoot == null ||
        localTransportKey == null ||
        localTransportKey.length != 32) {
      return null;
    }

    final rawEvents = _support.events(ledgerRoot);
    final events = <Map<String, dynamic>>[];
    for (final event in rawEvents) {
      if (event is Map) {
        events.add(Map<String, dynamic>.from(event));
      }
    }

    return _ConsensusRuntimeInputs(
      events: List<Map<String, dynamic>>.unmodifiable(events),
      localTransportKey: localTransportKey,
    );
  }
}

class _ConsensusRuntimeInputs {
  final List<Map<String, dynamic>> events;
  final Uint8List localTransportKey;

  const _ConsensusRuntimeInputs({
    required this.events,
    required this.localTransportKey,
  });
}
