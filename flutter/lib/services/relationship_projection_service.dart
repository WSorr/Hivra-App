import 'dart:convert';
import 'dart:typed_data';

import '../models/relationship.dart';
import '../models/relationship_peer_group.dart';
import '../models/starter.dart';

typedef RelationshipCurrentViewProjector =
    String? Function(String ledgerJson, Uint8List? localTransportPublicKey);

/// Maps the versioned Core relationship view into Flutter UI models.
///
/// Relationship lifecycle replay, signer classification, and episode
/// precedence belong to Core. This adapter must not inspect ledger events.
class RelationshipProjectionService {
  final RelationshipCurrentViewProjector _projectCurrentView;
  final Uint8List? Function()? _runtimeTransportPublicKey;

  const RelationshipProjectionService(
    this._projectCurrentView, {
    Uint8List? Function()? runtimeTransportPublicKey,
  }) : _runtimeTransportPublicKey = runtimeTransportPublicKey;

  List<Relationship> loadRelationships(Map<String, dynamic> ledgerRoot) {
    final projected = _projectCurrentView(
      jsonEncode(ledgerRoot),
      _runtimeTransportPublicKey?.call(),
    );
    if (projected == null || projected.trim().isEmpty) {
      return <Relationship>[];
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(projected);
    } on FormatException {
      return <Relationship>[];
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 'hivra.relationship_current_view' ||
        decoded['version'] != 1 ||
        decoded['relationships'] is! List) {
      return <Relationship>[];
    }

    final relationships = <Relationship>[];
    for (final raw in decoded['relationships'] as List) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final peer = _bytes(row['peer_pubkey'], 32);
      final peerRoot = _bytes(row['peer_root_pubkey'], 32);
      final peerIdentity = _bytes(row['peer_identity'], 32);
      final ownStarter = _bytes(row['own_starter_id'], 32);
      final peerStarter = _bytes(row['peer_starter_id'], 32);
      final kind = _starterKind(row['starter_kind']);
      final establishedAt = _timestamp(row['established_at']);
      final status = row['status'];
      if (peer == null ||
          peerIdentity == null ||
          ownStarter == null ||
          peerStarter == null ||
          kind == null ||
          establishedAt == null ||
          (status != 'active' &&
              status != 'pending_remote_break' &&
              status != 'broken')) {
        continue;
      }

      relationships.add(
        Relationship(
          peerPubkey: base64.encode(peer),
          peerRootPubkey:
              peerRoot != null
                  ? base64.encode(peerRoot)
                  : (_equalBytes(peerIdentity, peer)
                      ? null
                      : base64.encode(peerIdentity)),
          kind: kind,
          ownStarterId: base64.encode(ownStarter),
          peerStarterId: base64.encode(peerStarter),
          establishedAt: establishedAt,
          isActive: status != 'broken',
          hasPendingRemoteBreak: status == 'pending_remote_break',
        ),
      );
    }
    relationships.sort(
      (left, right) => right.establishedAt.compareTo(left.establishedAt),
    );
    return relationships;
  }

  List<RelationshipPeerGroup> loadRelationshipGroups(
    Map<String, dynamic> root,
  ) {
    final relationships = loadRelationships(root);
    final byPeer = <String, List<Relationship>>{};
    final representativeByPeer = <String, Relationship>{};
    for (final relationship in relationships) {
      final peerIdentity =
          relationship.peerRootPubkey ?? relationship.peerPubkey;
      byPeer
          .putIfAbsent(peerIdentity, () => <Relationship>[])
          .add(relationship);
      final representative = representativeByPeer[peerIdentity];
      if (representative == null ||
          relationship.establishedAt.isAfter(representative.establishedAt)) {
        representativeByPeer[peerIdentity] = relationship;
      }
    }

    final groups =
        byPeer.entries
            .map(
              (entry) => RelationshipPeerGroup(
                peerPubkey:
                    representativeByPeer[entry.key]?.peerPubkey ??
                    entry.value.first.peerPubkey,
                relationships: entry.value,
              ),
            )
            .toList();
    groups.sort(
      (left, right) =>
          right.latestEstablishedAt.compareTo(left.latestEstablishedAt),
    );
    return groups;
  }

  List<int>? _bytes(Object? raw, int length) {
    if (raw == null) return null;
    if (raw is! List || raw.length != length) return null;
    final result = <int>[];
    for (final value in raw) {
      if (value is! num || value < 0 || value > 255) return null;
      result.add(value.toInt());
    }
    return result;
  }

  bool _equalBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  StarterKind? _starterKind(Object? raw) {
    if (raw is! num) return null;
    return switch (raw.toInt()) {
      0 => StarterKind.juice,
      1 => StarterKind.spark,
      2 => StarterKind.seed,
      3 => StarterKind.pulse,
      4 => StarterKind.kick,
      _ => null,
    };
  }

  DateTime? _timestamp(Object? raw) {
    if (raw is! num || raw <= 0) return null;
    final value = raw.toInt();
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
