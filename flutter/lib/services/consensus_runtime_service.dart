import 'dart:typed_data';

import '../models/consensus_models.dart';
import 'consensus_processor.dart';

typedef LedgerExporter = String? Function();
typedef TransportKeyReader = Uint8List? Function();
typedef RootKeyReader = Uint8List? Function();
typedef PairViewProjector =
    String? Function(String ledgerJson, Uint8List? localTransportKey);

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
  final RootKeyReader _readLocalRootKey;
  final ConsensusSignatureVerifier? _verifySignature;
  final PairViewProjector _projectPairView;
  final ConsensusProcessor _processor;

  const ConsensusRuntimeService({
    required LedgerExporter exportLedger,
    required TransportKeyReader readLocalTransportKey,
    RootKeyReader? readLocalRootKey,
    ConsensusSignatureVerifier? verifySignature,
    PairViewProjector projectPairView = _unavailablePairViewProjector,
    ConsensusProcessor processor = const ConsensusProcessor(),
  }) : _exportLedger = exportLedger,
       _readLocalTransportKey = readLocalTransportKey,
       _readLocalRootKey = readLocalRootKey ?? _nullKeyReader,
       _verifySignature = verifySignature,
       _projectPairView = projectPairView,
       _processor = processor;

  List<ConsensusPreview> preview() {
    final inputs = _runtimeInputs();
    if (inputs == null) return const <ConsensusPreview>[];
    return _processor.preview(inputs.pairViewJson);
  }

  List<ConsensusCheck> checks() {
    final inputs = _runtimeInputs();
    if (inputs == null) return const <ConsensusCheck>[];
    final previews = _processor.preview(inputs.pairViewJson);
    return previews
        .map((preview) {
          return ConsensusCheck(
            peerHex: preview.peerHex,
            peerLabel: preview.peerLabel,
            invitationCount: preview.invitationCount,
            relationshipCount: preview.relationshipCount,
            hashHex: preview.hashHex,
            canonicalJson: preview.canonicalJson,
            isSignable: preview.isSignable,
            blockingFacts: preview.blockingFacts,
          );
        })
        .toList(growable: false);
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
    return _processor.signable(inputs.pairViewJson, peerHex: peerHex);
  }

  ConsensusVerifyResult verify({
    required String expectedHashHex,
    required List<ConsensusVerifyParticipant> participants,
  }) {
    return _processor.verify(
      expectedHashHex: expectedHashHex,
      participants: participants,
      verifySignature: _verifySignature,
    );
  }

  _ConsensusRuntimeInputs? _runtimeInputs() {
    final ledgerJson = _exportLedger();
    final localTransportKey = _readLocalTransportKey();
    final localRootKey = _readLocalRootKey();
    final hasTransport =
        localTransportKey != null && localTransportKey.length == 32;
    final hasRoot = localRootKey != null && localRootKey.length == 32;
    if (ledgerJson == null || (!hasTransport && !hasRoot)) {
      return null;
    }
    final pairViewJson = _projectPairView(
      ledgerJson,
      hasTransport ? localTransportKey : null,
    );
    if (pairViewJson == null) return null;

    return _ConsensusRuntimeInputs(pairViewJson: pairViewJson);
  }
}

class _ConsensusRuntimeInputs {
  final String pairViewJson;

  const _ConsensusRuntimeInputs({required this.pairViewJson});
}

Uint8List? _nullKeyReader() => null;
String? _unavailablePairViewProjector(String _, Uint8List? unused) => null;
