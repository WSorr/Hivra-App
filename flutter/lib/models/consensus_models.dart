class ConsensusBlockingFact {
  final String code;
  final String? subjectId;

  const ConsensusBlockingFact({
    required this.code,
    this.subjectId,
  });

  String get key => subjectId == null ? code : '$code:$subjectId';

  String get label => switch (code) {
        'pending_invitation' => subjectId == null
            ? 'Pending invitation'
            : 'Pending invitation ${_shortId(subjectId!)}',
        'relationship_broken' => subjectId == null
            ? 'Relationship broken'
            : 'Relationship broken ${_shortId(subjectId!)}',
        'pending_remote_break' => subjectId == null
            ? 'Pending remote break'
            : 'Pending remote break ${_shortId(subjectId!)}',
        'no_active_relationship' => subjectId == null
            ? 'No active relationship'
            : 'No active relationship with ${_shortId(subjectId!)}',
        'consensus_runtime_unavailable' => 'Consensus runtime unavailable',
        'invalid_local_transport_key' => 'Invalid local transport key',
        'consensus_peer_not_selected' => 'Consensus peer not selected',
        'consensus_peer_not_found' => 'Consensus peer not found',
        'invalid_peer_id' => 'Invalid peer id',
        'invalid_expected_hash' => 'Invalid expected hash',
        'empty_signature_set' => 'Empty signature set',
        'duplicate_participant' => subjectId == null
            ? 'Duplicate participant'
            : 'Duplicate participant ${_shortId(subjectId!)}',
        'invalid_hash' => subjectId == null
            ? 'Invalid participant hash'
            : 'Invalid participant hash ${_shortId(subjectId!)}',
        'hash_mismatch' => subjectId == null
            ? 'Hash mismatch'
            : 'Hash mismatch ${_shortId(subjectId!)}',
        'missing_signature' => subjectId == null
            ? 'Missing signature'
            : 'Missing signature ${_shortId(subjectId!)}',
        'invalid_signature' => subjectId == null
            ? 'Invalid signature'
            : 'Invalid signature ${_shortId(subjectId!)}',
        'signature_verifier_unavailable' =>
          'Consensus signature verifier unavailable',
        _ => key,
      };

  static String _shortId(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}..${value.substring(value.length - 6)}';
  }
}

enum ConsensusVerifyState {
  match,
  mismatch,
}

class ConsensusPreview {
  final String peerHex;
  final String peerLabel;
  final int invitationCount;
  final int relationshipCount;
  final String hashHex;
  final String canonicalJson;
  final List<ConsensusBlockingFact> blockingFacts;

  const ConsensusPreview({
    required this.peerHex,
    required this.peerLabel,
    required this.invitationCount,
    required this.relationshipCount,
    required this.hashHex,
    required this.canonicalJson,
    required this.blockingFacts,
  });

  bool get isSignable => blockingFacts.isEmpty;
}

class ConsensusSignableResult {
  final ConsensusPreview? preview;
  final List<ConsensusBlockingFact> blockingFacts;

  const ConsensusSignableResult({
    required this.preview,
    required this.blockingFacts,
  });

  bool get isSignable => preview != null && blockingFacts.isEmpty;

  String? get hashHex => isSignable ? preview!.hashHex : null;
}

class ConsensusVerifyParticipant {
  final String participantId;
  final String hashHex;
  final String? signatureHex;

  const ConsensusVerifyParticipant({
    required this.participantId,
    required this.hashHex,
    this.signatureHex,
  });
}

typedef ConsensusSignatureVerifier = bool Function({
  required String messageHashHex,
  required String participantIdHex,
  required String signatureHex,
});

class ConsensusVerifyResult {
  final ConsensusVerifyState state;
  final List<ConsensusBlockingFact> blockingFacts;

  const ConsensusVerifyResult({
    required this.state,
    required this.blockingFacts,
  });

  bool get isMatch =>
      state == ConsensusVerifyState.match && blockingFacts.isEmpty;
}
