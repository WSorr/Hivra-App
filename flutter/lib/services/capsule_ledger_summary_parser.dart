import 'dart:typed_data';

import 'capsule_persistence_models.dart';
import 'invitation_projection_service.dart';
import 'ledger_view_support.dart';
import 'relationship_projection_service.dart';
import '../models/invitation.dart';

class CapsuleLedgerSummaryParser {
  final LedgerViewSupport _support;

  const CapsuleLedgerSummaryParser({
    LedgerViewSupport support = const LedgerViewSupport(),
  }) : _support = support;

  CapsuleLedgerSummary parse(
    String json,
    String Function(Uint8List bytes) _, {
    Object? coreProjection,
    Uint8List? runtimeOwnerPublicKey,
    Uint8List? runtimeTransportPublicKey,
  }) {
    if (json.trim().isEmpty) return CapsuleLedgerSummary.empty();
    try {
      final ledger = _support.exportLedgerRoot(json);
      if (ledger == null) return CapsuleLedgerSummary.empty();
      final events = _support.events(ledger);

      final ledgerVersion = events.length;
      final ledgerHashHex = _parseLedgerHashHex(ledger['last_hash']);
      final starterCount = _starterCountFromCoreProjection(
        coreProjection,
        ledgerVersion: ledgerVersion,
        ledgerHashHex: ledgerHashHex,
      );
      final sharedCounters = projectSharedCountersFromLedgerRoot(
        ledger,
        runtimeOwnerPublicKey: runtimeOwnerPublicKey,
        runtimeTransportPublicKey: runtimeTransportPublicKey,
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

  ({int relationshipCount, int pendingInvitations})
  projectSharedCountersFromLedgerRoot(
    Map<String, dynamic> ledger, {
    Uint8List? runtimeOwnerPublicKey,
    Uint8List? runtimeTransportPublicKey,
    List<Uint8List?> starterIds = const <Uint8List?>[],
  }) {
    final ownerBytes = parseBytesField(ledger['owner']);
    Uint8List? readOwner() {
      if (runtimeOwnerPublicKey != null && runtimeOwnerPublicKey.length == 32) {
        return Uint8List.fromList(runtimeOwnerPublicKey);
      }
      if (ownerBytes != null && ownerBytes.length == 32) {
        return Uint8List.fromList(ownerBytes);
      }
      return null;
    }

    final projection = InvitationProjectionService.withOwnerKeyProvider(
      readOwner,
      _support,
      runtimeTransportPublicKey:
          runtimeTransportPublicKey == null
              ? null
              : () => runtimeTransportPublicKey,
    );
    final relationshipProjection =
        RelationshipProjectionService.withOwnerKeyProvider(
          readOwner,
          _support,
          runtimeTransportPublicKey:
              runtimeTransportPublicKey == null
                  ? null
                  : () => runtimeTransportPublicKey,
        );
    final relationshipCount = relationshipProjection
        .loadRelationshipGroups(ledger)
        .where((group) => group.isActive)
        .length
        .clamp(0, 9999);
    final pendingInvitations = projection
        .loadInvitations(ledger, starterIds: starterIds)
        .where((invitation) => invitation.status == InvitationStatus.pending)
        .length
        .clamp(0, 9999);

    return (
      relationshipCount: relationshipCount,
      pendingInvitations: pendingInvitations,
    );
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
    if (_parseLedgerHashHex(projection['ledger_hash']) != ledgerHashHex) {
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
    return '0';
  }
}
