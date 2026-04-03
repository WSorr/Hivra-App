import 'dart:convert';
import 'dart:typed_data';

import '../models/relationship.dart';
import '../models/relationship_peer_group.dart';
import 'capsule_address_service.dart';

typedef RelationshipGroupsLoader = List<RelationshipPeerGroup> Function();
typedef RelationshipBreaker = bool Function(
  Uint8List peerPubkey,
  Uint8List ownStarterId,
  Uint8List peerStarterId,
);
typedef LedgerSnapshotPersister = Future<void> Function();

class RelationshipService {
  final RelationshipGroupsLoader _loadRelationshipGroups;
  final RelationshipBreaker _breakRelationship;
  final LedgerSnapshotPersister _persistLedgerSnapshot;
  final CapsuleAddressService _addressService;

  RelationshipService({
    required RelationshipGroupsLoader loadRelationshipGroups,
    required RelationshipBreaker breakRelationship,
    required LedgerSnapshotPersister persistLedgerSnapshot,
    CapsuleAddressService? addressService,
  })  : _loadRelationshipGroups = loadRelationshipGroups,
        _breakRelationship = breakRelationship,
        _persistLedgerSnapshot = persistLedgerSnapshot,
        _addressService = addressService ?? const CapsuleAddressService();

  List<RelationshipPeerGroup> loadRelationshipGroups() {
    return _loadRelationshipGroups();
  }

  Future<Map<String, String>> loadPeerRootKeysByTransportBase64(
    Iterable<String> peerPubkeys,
  ) async {
    final cards = await _addressService.listTrustedCards();
    final rootByHex = <String, String>{};
    final rootByTransportHex = <String, String>{};

    for (final card in cards) {
      final rootHex = _normalizeHex32(card.rootHex);
      if (rootHex != null) {
        rootByHex[rootHex] = card.rootKey;
      }
      final nostrHex = _normalizeHex32(card.nostrHex);
      if (nostrHex != null) {
        rootByTransportHex[nostrHex] = card.rootKey;
      }
    }

    final result = <String, String>{};
    for (final peerPubkey in peerPubkeys) {
      final bytes = _decodeB64_32(peerPubkey);
      if (bytes == null) continue;
      final hex = _hex(bytes);
      final rootKey = rootByHex[hex] ?? rootByTransportHex[hex];
      if (rootKey != null && rootKey.isNotEmpty) {
        result[peerPubkey] = rootKey;
      }
    }
    return result;
  }

  Future<bool> breakRelationship(Relationship relationship) async {
    final peer = _decodeB64_32(relationship.peerPubkey);
    final own = _decodeB64_32(relationship.ownStarterId);
    final peerStarter = _decodeB64_32(relationship.peerStarterId);
    if (peer == null || own == null || peerStarter == null) {
      return false;
    }

    final ok = _breakRelationship(peer, own, peerStarter);
    if (!ok) return false;
    await _persistLedgerSnapshot();
    return true;
  }

  Future<bool> confirmRemoteBreak(Relationship relationship) {
    return breakRelationship(relationship);
  }

  Uint8List? _decodeB64_32(String value) {
    try {
      final bytes = base64.decode(value);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  String? _normalizeHex32(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
    final hex32 = RegExp(r'^[0-9a-f]{64}$');
    if (!hex32.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }
}
