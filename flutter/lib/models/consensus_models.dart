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

class ConsensusAttestationCommitment {
  final List<String> pairRootsSorted;
  final String snapshotHashHex;
  final String canonicalJson;
  final String commitmentHashHex;

  const ConsensusAttestationCommitment({
    required this.pairRootsSorted,
    required this.snapshotHashHex,
    required this.canonicalJson,
    required this.commitmentHashHex,
  });
}

class ConsensusAttestationEvidence {
  final int schemaVersion;
  final List<String> pairRootsSorted;
  final String snapshotHashHex;
  final String commitmentHashHex;
  final String signerRootHex;
  final String signatureHex;
  final String createdAtUtc;

  const ConsensusAttestationEvidence({
    required this.schemaVersion,
    required this.pairRootsSorted,
    required this.snapshotHashHex,
    required this.commitmentHashHex,
    required this.signerRootHex,
    required this.signatureHex,
    required this.createdAtUtc,
  });

  String get recordKey =>
      '${pairRootsSorted.join(':')}::$snapshotHashHex::$signerRootHex';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': schemaVersion,
        'pair_roots_sorted': pairRootsSorted,
        'snapshot_hash': snapshotHashHex,
        'commitment_hash': commitmentHashHex,
        'signer_root': signerRootHex,
        'signature': signatureHex,
        'created_at_utc': createdAtUtc,
      };

  static ConsensusAttestationEvidence? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final schemaVersion = _asInt(map['schema_version']);
    final roots = _asStringList(map['pair_roots_sorted']);
    final snapshotHashHex =
        map['snapshot_hash']?.toString().trim().toLowerCase() ?? '';
    final commitmentHashHex =
        map['commitment_hash']?.toString().trim().toLowerCase() ?? '';
    final signerRootHex =
        map['signer_root']?.toString().trim().toLowerCase() ?? '';
    final signatureHex =
        map['signature']?.toString().trim().toLowerCase() ?? '';
    final createdAtUtc = map['created_at_utc']?.toString().trim() ?? '';
    if (schemaVersion != 1 ||
        roots.length != 2 ||
        !_isHex(roots[0], 64) ||
        !_isHex(roots[1], 64) ||
        roots[0].compareTo(roots[1]) >= 0 ||
        !_isHex(snapshotHashHex, 64) ||
        !_isHex(commitmentHashHex, 64) ||
        !_isHex(signerRootHex, 64) ||
        !_isHex(signatureHex, 128) ||
        !roots.contains(signerRootHex) ||
        DateTime.tryParse(createdAtUtc)?.isUtc != true) {
      return null;
    }
    return ConsensusAttestationEvidence(
      schemaVersion: schemaVersion!,
      pairRootsSorted: List<String>.unmodifiable(roots),
      snapshotHashHex: snapshotHashHex,
      commitmentHashHex: commitmentHashHex,
      signerRootHex: signerRootHex,
      signatureHex: signatureHex,
      createdAtUtc: createdAtUtc,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim().toLowerCase())
        .toList(growable: false);
  }

  static bool _isHex(String value, int length) =>
      value.length == length && RegExp(r'^[0-9a-f]+$').hasMatch(value);
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
