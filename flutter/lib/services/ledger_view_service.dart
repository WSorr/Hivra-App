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

String? _emptyInvitationCurrentView(String _) => jsonEncode(<String, Object>{
  'schema': 'hivra.invitation_current_view',
  'version': 1,
  'ledger_version': 0,
  'invitations': <Object>[],
});

String? _emptyRelationshipCurrentView(String _, Uint8List? transport) =>
    jsonEncode(<String, Object>{
      'schema': 'hivra.relationship_current_view',
      'version': 1,
      'ledger_version': 0,
      'active_peer_count': 0,
      'relationships': <Object>[],
    });

class LedgerViewService {
  final LedgerExporter _exportLedger;
  final CapsuleStateExporter _exportCapsuleState;
  final RuntimeOwnerKeyReader _readRuntimeOwnerPublicKey;
  final RuntimeTransportKeyReader _readRuntimeTransportPublicKey;
  final InvitationCurrentViewProjector _projectInvitationCurrentView;
  final RelationshipCurrentViewProjector _projectRelationshipCurrentView;
  final LedgerViewSupport _support;
  final CapsuleLedgerSummaryParser _summaryParser;
  late final InvitationProjectionService _invitationProjection;
  late final RelationshipProjectionService _relationshipProjection;

  LedgerViewService({required LedgerViewRuntime runtime})
    : _exportLedger = runtime.exportLedger,
      _exportCapsuleState = runtime.exportCapsuleStateJson,
      _readRuntimeOwnerPublicKey = runtime.capsuleRuntimeOwnerPublicKey,
      _readRuntimeTransportPublicKey = runtime.capsuleRuntimeTransportPublicKey,
      _projectInvitationCurrentView = runtime.projectInvitationCurrentViewV1,
      _projectRelationshipCurrentView =
          ((ledgerJson, localTransportPublicKey) =>
              runtime.projectRelationshipCurrentViewV1(
                ledgerJson,
                localTransportPublicKey: localTransportPublicKey,
              )),
      _support = const LedgerViewSupport(),
      _summaryParser = const CapsuleLedgerSummaryParser() {
    _invitationProjection = InvitationProjectionService(
      _projectInvitationCurrentView,
    );
    _relationshipProjection = RelationshipProjectionService(
      _projectRelationshipCurrentView,
      runtimeTransportPublicKey: _readRuntimeTransportPublicKey,
    );
  }

  LedgerViewService.withSources({
    required LedgerExporter exportLedger,
    required CapsuleStateExporter exportCapsuleState,
    required RuntimeOwnerKeyReader readRuntimeOwnerPublicKey,
    RuntimeTransportKeyReader? readRuntimeTransportPublicKey,
    InvitationCurrentViewProjector projectInvitationCurrentView =
        _emptyInvitationCurrentView,
    RelationshipCurrentViewProjector projectRelationshipCurrentView =
        _emptyRelationshipCurrentView,
    LedgerViewSupport support = const LedgerViewSupport(),
    CapsuleLedgerSummaryParser summaryParser =
        const CapsuleLedgerSummaryParser(),
  }) : _exportLedger = exportLedger,
       _exportCapsuleState = exportCapsuleState,
       _readRuntimeOwnerPublicKey = readRuntimeOwnerPublicKey,
       _readRuntimeTransportPublicKey =
           readRuntimeTransportPublicKey ?? _emptyRuntimeTransportKey,
       _projectInvitationCurrentView = projectInvitationCurrentView,
       _projectRelationshipCurrentView = projectRelationshipCurrentView,
       _support = support,
       _summaryParser = summaryParser {
    _invitationProjection = InvitationProjectionService(
      _projectInvitationCurrentView,
    );
    _relationshipProjection = RelationshipProjectionService(
      _projectRelationshipCurrentView,
      runtimeTransportPublicKey: _readRuntimeTransportPublicKey,
    );
  }

  static Uint8List? _emptyRuntimeTransportKey() => null;

  CapsuleLedgerSnapshot loadCapsuleSnapshot() {
    final root = _exportLedgerRoot();
    final capsuleState = _exportCapsuleStateRoot();
    final pubKey =
        _bytes32List(capsuleState?['public_key']) ??
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

    final stateVersion =
        capsuleState?['version'] is num
            ? (capsuleState!['version'] as num).toInt()
            : null;
    final starterIds =
        stateVersion == events.length
            ? _starterIdsFromCapsuleState(capsuleState)
            : List<Uint8List?>.filled(5, null);
    final starterKinds = _starterKindsFromCapsuleState(
      capsuleState,
      starterIds,
    );
    final starterCount = starterIds.whereType<Uint8List>().length;

    final version = stateVersion ?? events.length;
    final rawHash =
        capsuleState?['ledger_head_commitment'] ??
        root['head_commitment_v5'] ??
        capsuleState?['ledger_hash'] ??
        root['last_hash'];
    final hashHex = _ledgerHashHex(rawHash);

    final invitations = loadInvitations(root: root, starterIds: starterIds);
    final sharedCounters = _summaryParser.projectSharedCounters(
      invitationCurrentViewJson: _projectInvitationCurrentView(
        jsonEncode(root),
      ),
      relationshipCurrentViewJson: _projectRelationshipCurrentView(
        jsonEncode(root),
        _readRuntimeTransportPublicKey(),
      ),
    );
    final lockedStarterSlots =
        invitations
            .where(
              (invitation) =>
                  invitation.status == InvitationStatus.pending &&
                  invitation.starterSlot != null,
            )
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

  String _ledgerHashHex(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is List) {
      final bytes = _support.payloadBytes(raw);
      if (bytes.isNotEmpty || raw.isEmpty) {
        return bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
      }
    }
    return raw == null ? '0' : raw.toString();
  }

  List<Invitation> loadInvitations({
    Map<String, dynamic>? root,
    List<Uint8List?>? starterIds,
  }) {
    final ledgerRoot = root ?? _exportLedgerRoot();
    if (ledgerRoot == null) return <Invitation>[];
    return _invitationProjection.loadInvitations(ledgerRoot);
  }

  List<Relationship> loadRelationships({Map<String, dynamic>? root}) {
    final ledgerRoot = root ?? _exportLedgerRoot();
    if (ledgerRoot == null) return <Relationship>[];
    return _relationshipProjection.loadRelationships(ledgerRoot);
  }

  List<RelationshipPeerGroup> loadRelationshipGroups({
    Map<String, dynamic>? root,
  }) {
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

  List<String?> _starterKindsFromCapsuleState(
    Map<String, dynamic>? root,
    List<Uint8List?> starterIds,
  ) {
    final projectedKinds = root?['starter_kinds'];
    if (projectedKinds is! List || projectedKinds.length != 5) {
      return List<String?>.generate(
        5,
        (index) => starterIds[index] == null ? null : 'Unknown',
      );
    }

    return List<String?>.generate(5, (index) {
      if (starterIds[index] == null) return null;
      final rawKind = projectedKinds[index];
      if (rawKind is! num || rawKind < 0 || rawKind > 4) return 'Unknown';
      return _support.starterKindFromByte(rawKind.toInt()).displayName;
    });
  }
}
