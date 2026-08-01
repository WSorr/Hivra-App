import 'dart:typed_data';
import 'dart:convert';

import 'capsule_persistence_models.dart';
import 'ledger_view_support.dart';

class CapsuleLedgerSummaryParser {
  final LedgerViewSupport _support;

  const CapsuleLedgerSummaryParser({
    LedgerViewSupport support = const LedgerViewSupport(),
  }) : _support = support;

  CapsuleLedgerSummary parse(
    String json,
    String Function(Uint8List bytes) _, {
    Object? coreProjection,
    String? invitationCurrentViewJson,
    String? relationshipCurrentViewJson,
  }) {
    if (json.trim().isEmpty) return CapsuleLedgerSummary.empty();
    try {
      final ledger = _support.exportLedgerRoot(json);
      if (ledger == null) return CapsuleLedgerSummary.empty();
      final events = _support.events(ledger);

      final ledgerVersion = events.length;
      final ledgerHashHex = _ledgerHeadIdentity(ledger);
      final starterCount = _starterCountFromCoreProjection(
        coreProjection,
        ledgerVersion: ledgerVersion,
        ledgerHashHex: ledgerHashHex,
      );
      final sharedCounters = projectSharedCounters(
        invitationCurrentViewJson: invitationCurrentViewJson,
        relationshipCurrentViewJson: relationshipCurrentViewJson,
      );
      return CapsuleLedgerSummary(
        starterCount: starterCount,
        relationshipCount: sharedCounters.relationshipCount,
        pendingInvitations: sharedCounters.pendingInvitations,
        ledgerVersion: ledgerVersion,
        ledgerHashHex: ledgerHashHex,
      );
    } catch (_) {
      return CapsuleLedgerSummary.empty();
    }
  }

  ({int relationshipCount, int pendingInvitations}) projectSharedCounters({
    String? invitationCurrentViewJson,
    String? relationshipCurrentViewJson,
  }) {
    final relationshipCount = _activeRelationshipPeerCount(
      relationshipCurrentViewJson,
    ).clamp(0, 9999);
    final pendingInvitations = _pendingInvitationCount(
      invitationCurrentViewJson,
    ).clamp(0, 9999);

    return (
      relationshipCount: relationshipCount,
      pendingInvitations: pendingInvitations,
    );
  }

  int _pendingInvitationCount(String? currentViewJson) {
    if (currentViewJson == null || currentViewJson.trim().isEmpty) return 0;
    try {
      final root = jsonDecode(currentViewJson);
      if (root is! Map ||
          root['schema'] != 'hivra.invitation_current_view' ||
          root['version'] != 1 ||
          root['invitations'] is! List) {
        return 0;
      }
      return (root['invitations'] as List)
          .where((row) => row is Map && row['status'] == 'pending')
          .length;
    } catch (_) {
      return 0;
    }
  }

  int _activeRelationshipPeerCount(String? currentViewJson) {
    if (currentViewJson == null || currentViewJson.trim().isEmpty) return 0;
    try {
      final root = jsonDecode(currentViewJson);
      if (root is! Map ||
          root['schema'] != 'hivra.relationship_current_view' ||
          root['version'] != 1 ||
          root['active_peer_count'] is! num) {
        return 0;
      }
      final count = (root['active_peer_count'] as num).toInt();
      return count < 0 ? 0 : count;
    } catch (_) {
      return 0;
    }
  }

  List<int>? parseBytesField(dynamic raw) {
    if (raw is List) {
      final bytes = _support.payloadBytes(raw);
      if (bytes.isEmpty && raw.isNotEmpty) return null;
      return bytes;
    }
    if (raw is String) {
      final bytes = _support.payloadBytes(raw);
      if (bytes.isEmpty) return null;
      return bytes;
    }
    return null;
  }

  int _starterCountFromCoreProjection(
    Object? raw, {
    required int ledgerVersion,
    required String ledgerHashHex,
  }) {
    if (raw is! Map) return 0;
    final projection = Map<String, dynamic>.from(raw);
    final version = projection['version'];
    if (version is! num || version.toInt() != ledgerVersion) return 0;
    final projectionHash =
        projection['ledger_head_commitment'] != null
            ? _parseLedgerHashHex(projection['ledger_head_commitment'])
            : _parseLedgerHashHex(projection['ledger_hash']);
    if (projectionHash != ledgerHashHex) {
      return 0;
    }
    final slots = projection['slots'];
    if (slots is! List || slots.length != 5) return 0;
    return slots.where((slot) => _isStarterId(slot)).length;
  }

  bool _isStarterId(Object? raw) {
    if (raw is! List || raw.length != 32) return false;
    return raw.every((byte) => byte is num && byte >= 0 && byte <= 255);
  }

  String _parseLedgerHashHex(dynamic raw) {
    if (raw == null) return '0';
    if (raw is int) {
      return raw.toUnsigned(64).toRadixString(16);
    }
    if (raw is double) {
      return raw.toInt().toUnsigned(64).toRadixString(16);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return '0';
      final dec = int.tryParse(trimmed);
      if (dec != null) return dec.toUnsigned(64).toRadixString(16);
      final hex = trimmed.startsWith('0x') ? trimmed.substring(2) : trimmed;
      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
        return hex.toLowerCase();
      }
    }
    if (raw is List) {
      final bytes = _support.payloadBytes(raw);
      if (bytes.isNotEmpty || raw.isEmpty) {
        return bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
      }
    }
    return '0';
  }

  String _ledgerHeadIdentity(Map<String, dynamic> ledger) {
    final v5Head = _parseLedgerHashHex(ledger['head_commitment_v5']);
    if (v5Head != '0') {
      return v5Head;
    }
    return _parseLedgerHashHex(ledger['last_hash']);
  }
}
