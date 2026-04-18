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
    String Function(Uint8List bytes) toHex, {
    Uint8List? runtimeOwnerPublicKey,
    Uint8List? runtimeTransportPublicKey,
  }) {
    if (json.trim().isEmpty) return CapsuleLedgerSummary.empty();
    try {
      final ledger = _support.exportLedgerRoot(json);
      if (ledger == null) return CapsuleLedgerSummary.empty();
      final events = _support.events(ledger);

      final activeStartersById = <String, int>{};
      final burnedStarterIds = <String>{};

      for (final eventRaw in events) {
        if (eventRaw is! Map) continue;
        final event = Map<String, dynamic>.from(eventRaw);
        final kind = _support.kindCode(event['kind']);
        final payload = _support.payloadBytes(event['payload']);

        switch (kind) {
          case 5:
            final starter = _parseStarterCreated(payload);
            if (starter != null) {
              final starterIdHex = toHex(Uint8List.fromList(starter.starterId));
              if (burnedStarterIds.contains(starterIdHex)) {
                break;
              }
              if (activeStartersById.containsKey(starterIdHex)) {
                break;
              }
              activeStartersById[starterIdHex] = starter.kindCode;
            }
            break;
          case 6:
            final burnedId = _parseStarterBurnedId(payload);
            if (burnedId != null) {
              final starterIdHex = toHex(Uint8List.fromList(burnedId));
              activeStartersById.remove(starterIdHex);
              burnedStarterIds.add(starterIdHex);
            }
            break;
          default:
            break;
        }
      }

      final starterCount = activeStartersById.length.clamp(0, 5);
      final sharedCounters = projectSharedCountersFromLedgerRoot(
        ledger,
        runtimeOwnerPublicKey: runtimeOwnerPublicKey,
        runtimeTransportPublicKey: runtimeTransportPublicKey,
      );
      final ledgerVersion = events.length;
      final ledgerHashHex = _parseLedgerHashHex(ledger['last_hash']);

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
      runtimeTransportPublicKey: runtimeTransportPublicKey == null
          ? null
          : () => runtimeTransportPublicKey,
    );
    final relationshipProjection =
        RelationshipProjectionService.withOwnerKeyProvider(
      readOwner,
      _support,
      runtimeTransportPublicKey: runtimeTransportPublicKey == null
          ? null
          : () => runtimeTransportPublicKey,
    );
    final relationshipCount = relationshipProjection
        .loadRelationshipGroups(ledger)
        .where((group) => group.isActive)
        .length
        .clamp(0, 9999);
    final pendingInvitations = projection
        .loadInvitations(
          ledger,
          starterIds: starterIds,
        )
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

  _StarterRecord? _parseStarterCreated(Uint8List payload) {
    if (payload.length < 66) return null;
    final kindCode = payload[64];
    if (kindCode < 0 || kindCode > 4) return null;
    final starterId = payload.sublist(0, 32);
    return _StarterRecord(kindCode: kindCode, starterId: starterId);
  }

  Uint8List? _parseStarterBurnedId(Uint8List payload) {
    if (payload.length < 32) return null;
    return payload.sublist(0, 32);
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

class _StarterRecord {
  final int kindCode;
  final Uint8List starterId;

  _StarterRecord({required this.kindCode, required this.starterId});
}
