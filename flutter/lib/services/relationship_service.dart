import 'dart:convert';
import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import '../models/relationship.dart';
import '../models/relationship_peer_group.dart';
import 'capsule_persistence_service.dart';
import 'ledger_view_service.dart';

class RelationshipService {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  RelationshipService(
    this._hivra, {
    CapsulePersistenceService? persistence,
  }) : _persistence = persistence ?? CapsulePersistenceService();

  List<RelationshipPeerGroup> loadRelationshipGroups() {
    return LedgerViewService(_hivra).loadRelationshipGroups();
  }

  Future<bool> breakRelationship(Relationship relationship) async {
    final peer = _decodeB64_32(relationship.peerPubkey);
    final own = _decodeB64_32(relationship.ownStarterId);
    final peerStarter = _decodeB64_32(relationship.peerStarterId);
    if (peer == null || own == null || peerStarter == null) {
      return false;
    }

    final ok = _hivra.breakRelationship(peer, own, peerStarter);
    if (!ok) return false;
    await _persistence.persistLedgerSnapshot(_hivra);
    return true;
  }

  Uint8List? _decodeB64_32(String value) {
    try {
      final bytes = base64.decode(value);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }
}
