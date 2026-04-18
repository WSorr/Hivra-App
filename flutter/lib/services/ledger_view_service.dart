import 'dart:convert';
import 'dart:typed_data';

import '../ffi/ledger_view_runtime.dart';
import '../models/invitation.dart';
import '../models/relationship.dart';
import '../models/relationship_peer_group.dart';
import 'capsule_ledger_summary_parser.dart';
import 'capsule_ledger_snapshot.dart';
import 'invitation_projection_service.dart';
import 'ledger_view_support.dart';
import 'relationship_projection_service.dart';

typedef LedgerExporter = String? Function();
typedef CapsuleStateExporter = String? Function();
typedef RuntimeOwnerKeyReader = Uint8List? Function();
typedef RuntimeTransportKeyReader = Uint8List? Function();

class LedgerViewService {
  final LedgerExporter _exportLedger;
  final CapsuleStateExporter _exportCapsuleState;
  final RuntimeOwnerKeyReader _readRuntimeOwnerPublicKey;
  final RuntimeTransportKeyReader _readRuntimeTransportPublicKey;
  final LedgerViewSupport _support;
  final CapsuleLedgerSummaryParser _summaryParser;
  late final InvitationProjectionService _invitationProjection;
  late final RelationshipProjectionService _relationshipProjection;

  LedgerViewService({required LedgerViewRuntime runtime})
      : _exportLedger = runtime.exportLedger,
        _exportCapsuleState = runtime.exportCapsuleStateJson,
        _readRuntimeOwnerPublicKey = runtime.capsuleRuntimeOwnerPublicKey,
        _readRuntimeTransportPublicKey =
            runtime.capsuleRuntimeTransportPublicKey,
        _support = const LedgerViewSupport(),
        _summaryParser = const CapsuleLedgerSummaryParser() {
    _invitationProjection = InvitationProjectionService.withOwnerKeyProvider(
      _readRuntimeOwnerPublicKey,
      _support,
      runtimeTransportPublicKey: _readRuntimeTransportPublicKey,
    );
    _relationshipProjection =
        RelationshipProjectionService.withOwnerKeyProvider(
      _readRuntimeOwnerPublicKey,
      _support,
      runtimeTransportPublicKey: _readRuntimeTransportPublicKey,
    );
  }

  LedgerViewService.withSources({
    required LedgerExporter exportLedger,
    required CapsuleStateExporter exportCapsuleState,
    required RuntimeOwnerKeyReader readRuntimeOwnerPublicKey,
    RuntimeTransportKeyReader? readRuntimeTransportPublicKey,
    LedgerViewSupport support = const LedgerViewSupport(),
    CapsuleLedgerSummaryParser summaryParser =
        const CapsuleLedgerSummaryParser(),
  })  : _exportLedger = exportLedger,
        _exportCapsuleState = exportCapsuleState,
        _readRuntimeOwnerPublicKey = readRuntimeOwnerPublicKey,
        _readRuntimeTransportPublicKey =
            readRuntimeTransportPublicKey ?? _emptyRuntimeTransportKey,
        _support = support,
        _summaryParser = summaryParser {
    _invitationProjection = InvitationProjectionService.withOwnerKeyProvider(
      _readRuntimeOwnerPublicKey,
      _support,
      runtimeTransportPublicKey: _readRuntimeTransportPublicKey,
    );
    _relationshipProjection =
        RelationshipProjectionService.withOwnerKeyProvider(
      _readRuntimeOwnerPublicKey,
      _support,
      runtimeTransportPublicKey: _readRuntimeTransportPublicKey,
    );
  }

  static Uint8List? _emptyRuntimeTransportKey() => null;

  CapsuleLedgerSnapshot loadCapsuleSnapshot() {
    final root = _exportLedgerRoot();
    final capsuleState = _exportCapsuleStateRoot();
    final pubKey = _bytes32List(capsuleState?['public_key']) ??
        _readRuntimeOwnerPublicKey() ??
        Uint8List(0);

    if (root == null) {
      return CapsuleLedgerSnapshot(
        publicKey: pubKey,
        starterCount: 0,
        relationshipCount: 0,
        pendingInvitations: 0,
        version: 0,
        ledgerHashHex: '0',
        hasLedgerHistory: false,
        starterIds: List<Uint8List?>.filled(5, null),
        starterKinds: List<String?>.filled(5, null),
        lockedStarterSlots: const <int>{},
      );
    }
    final events = _support.events(root);
    if (events.isEmpty) {
      return CapsuleLedgerSnapshot(
        publicKey: pubKey,
        starterCount: 0,
        relationshipCount: 0,
        pendingInvitations: 0,
        version: 0,
        ledgerHashHex: '0',
        hasLedgerHistory: false,
        starterIds: List<Uint8List?>.filled(5, null),
        starterKinds: List<String?>.filled(5, null),
        lockedStarterSlots: const <int>{},
      );
    }

    final starterIds = _starterIdsFromCapsuleState(capsuleState);
    final starterKinds = _starterKindsFromLedger(root, starterIds);
    final starterCount = starterIds.whereType<Uint8List>().length;

    final version = capsuleState?['version'] is num
        ? (capsuleState!['version'] as num).toInt()
        : events.length;
    final rawHash = capsuleState?['ledger_hash'] ?? root['last_hash'];
    final hashHex = rawHash == null ? '0' : rawHash.toString();

    final invitations = loadInvitations(root: root, starterIds: starterIds);
    final sharedCounters = _summaryParser.projectSharedCountersFromLedgerRoot(
      root,
      runtimeOwnerPublicKey: _readRuntimeOwnerPublicKey(),
      runtimeTransportPublicKey: _readRuntimeTransportPublicKey(),
      starterIds: starterIds,
    );
    final lockedStarterSlots = invitations
        .where((invitation) =>
            invitation.status == InvitationStatus.pending &&
            invitation.starterSlot != null)
        .map((invitation) => invitation.starterSlot!)
        .toSet();

    return CapsuleLedgerSnapshot(
      publicKey: pubKey,
      starterCount: starterCount,
      relationshipCount: sharedCounters.relationshipCount,
      pendingInvitations: sharedCounters.pendingInvitations,
      version: version,
      ledgerHashHex: hashHex,
      hasLedgerHistory: true,
      starterIds: starterIds,
      starterKinds: starterKinds,
      lockedStarterSlots: lockedStarterSlots,
    );
  }

  List<Invitation> loadInvitations({
    Map<String, dynamic>? root,
    List<Uint8List?>? starterIds,
  }) {
    final ledgerRoot = root ?? _exportLedgerRoot();
    if (ledgerRoot == null) return <Invitation>[];
    return _invitationProjection.loadInvitations(
      ledgerRoot,
      starterIds:
          starterIds ?? _starterIdsFromCapsuleState(_exportCapsuleStateRoot()),
    );
  }

  List<Relationship> loadRelationships({Map<String, dynamic>? root}) {
    final ledgerRoot = root ?? _exportLedgerRoot();
    if (ledgerRoot == null) return <Relationship>[];
    return _relationshipProjection.loadRelationships(ledgerRoot);
  }

  List<RelationshipPeerGroup> loadRelationshipGroups(
      {Map<String, dynamic>? root}) {
    final ledgerRoot = root ?? _exportLedgerRoot();
    if (ledgerRoot == null) return <RelationshipPeerGroup>[];
    return _relationshipProjection.loadRelationshipGroups(ledgerRoot);
  }

  Map<String, dynamic>? _exportLedgerRoot() {
    return _support.exportLedgerRoot(_exportLedger());
  }

  Map<String, dynamic>? _exportCapsuleStateRoot() {
    return _support.exportLedgerRoot(_exportCapsuleState());
  }

  Uint8List? _bytes32List(dynamic raw) {
    if (raw is! List || raw.length != 32) return null;
    final out = <int>[];
    for (final item in raw) {
      if (item is! num) return null;
      final value = item.toInt();
      if (value < 0 || value > 255) return null;
      out.add(value);
    }
    return Uint8List.fromList(out);
  }

  List<Uint8List?> _starterIdsFromCapsuleState(Map<String, dynamic>? root) {
    final slots = root?['slots'];
    if (slots is! List || slots.length != 5) {
      return List<Uint8List?>.filled(5, null);
    }

    return List<Uint8List?>.generate(5, (index) {
      final slot = slots[index];
      if (slot == null) return null;
      return _bytes32List(slot);
    });
  }

  List<String?> _starterKindsFromLedger(
    Map<String, dynamic> root,
    List<Uint8List?> starterIds,
  ) {
    final byId = <String, String>{};
    for (final event in _support.events(root)) {
      if (_support.kindCode(event['kind']) != 5) continue;
      final payload = _support.payloadBytes(event['payload']);
      if (payload.length != 66) continue;
      final id = base64.encode(payload.sublist(0, 32));
      byId[id] = _support.starterKindFromByte(payload[64]).displayName;
    }

    return List<String?>.generate(5, (index) {
      final starterId = starterIds[index];
      if (starterId == null) return null;
      return byId[base64.encode(starterId)] ?? 'Unknown';
    });
  }
}
