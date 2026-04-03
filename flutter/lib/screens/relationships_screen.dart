import 'package:flutter/material.dart';

import '../models/relationship.dart';
import '../models/relationship_peer_group.dart';
import '../models/starter.dart';
import '../services/relationship_service.dart';
import '../services/ui_feedback_service.dart';
import '../utils/hivra_id_format.dart';

class RelationshipsScreen extends StatefulWidget {
  final RelationshipService service;
  final Future<void> Function()? onLedgerChanged;

  const RelationshipsScreen({
    super.key,
    required this.service,
    this.onLedgerChanged,
  });

  @override
  State<RelationshipsScreen> createState() => _RelationshipsScreenState();
}

class _RelationshipsScreenState extends State<RelationshipsScreen> {
  List<RelationshipPeerGroup> _relationshipGroups = [];
  bool _isLoading = true;
  String? _filterKind;
  String? _breakingPeerPubkey;
  Map<String, String> _peerRootKeyByTransportB64 = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadRelationships();
  }

  Future<void> _loadRelationships() async {
    final groups = widget.service.loadRelationshipGroups();
    final peerRootKeys = await widget.service.loadPeerRootKeysByTransportBase64(
      groups.map((group) => group.peerPubkey),
    );
    if (!mounted) return;
    setState(() {
      _relationshipGroups = groups;
      _peerRootKeyByTransportB64 = peerRootKeys;
      _isLoading = false;
    });
  }

  Future<void> _confirmRelationshipTransition(
    Relationship relationship, {
    required bool remoteBreakPending,
    String? peerLabel,
  }) async {
    final displayPeer = peerLabel ?? relationship.peerDisplayName;
    final title =
        remoteBreakPending ? 'Confirm Break Request?' : 'Break Relationship?';
    final message = remoteBreakPending
        ? 'Peer requested to break relationship with $displayPeer. '
            'Confirm to append your local break fact and converge pairwise state. '
            'Your starter will NOT be burned.'
        : 'This will break your relationship with $displayPeer. '
            'Your starter will NOT be burned.';
    final confirmLabel = remoteBreakPending ? 'Confirm break' : 'Break';
    final confirmColor = remoteBreakPending ? Colors.orange : Colors.red;
    final failureMessage = remoteBreakPending
        ? 'Failed to confirm break request'
        : 'Failed to break relationship';
    final successMessage =
        remoteBreakPending ? 'Break request confirmed' : 'Relationship broken';
    final source = remoteBreakPending
        ? 'relationships.break.confirm_remote'
        : 'relationships.break';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (!mounted) return;
    setState(() => _breakingPeerPubkey = relationship.peerPubkey);
    UiFeedbackService.dismissCurrent(context);
    final ok = remoteBreakPending
        ? await widget.service.confirmRemoteBreak(relationship)
        : await widget.service.breakRelationship(relationship);
    if (!mounted) return;
    setState(() => _breakingPeerPubkey = null);

    if (!ok) {
      UiFeedbackService.showSnackBar(
        context,
        failureMessage,
        source: source,
        duration: const Duration(seconds: 3),
        enableCopy: false,
      );
      return;
    }
    await _loadRelationships();
    await widget.onLedgerChanged?.call();
    if (!mounted) return;
    UiFeedbackService.showSnackBar(
      context,
      successMessage,
      source: source,
      duration: const Duration(seconds: 2),
      enableCopy: false,
    );
  }

  Future<void> _chooseRelationshipAndApply({
    required RelationshipPeerGroup group,
    required List<Relationship> candidates,
    required bool remoteBreakPending,
  }) async {
    if (candidates.isEmpty) return;
    if (candidates.length == 1) {
      await _confirmRelationshipTransition(
        candidates.first,
        remoteBreakPending: remoteBreakPending,
        peerLabel: _peerDisplayName(group),
      );
      return;
    }

    final title = remoteBreakPending
        ? 'Confirm break with ${_peerDisplayName(group)}'
        : 'Break link with ${_peerDisplayName(group)}';
    final subtitle = remoteBreakPending
        ? 'Choose which pending remote break to confirm'
        : 'Choose which starter relationship to break';
    final trailingIcon = remoteBreakPending
        ? const Icon(Icons.check_circle_outline, color: Colors.orange)
        : const Icon(Icons.link_off, color: Colors.red);

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title),
              subtitle: Text(subtitle),
            ),
            ...candidates.map(
              (relationship) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: relationship.kind.color.withAlpha(40),
                  child: Text(
                    relationship.kind.displayName[0],
                    style: TextStyle(color: relationship.kind.color),
                  ),
                ),
                title: Text(relationship.kind.displayName),
                subtitle: Text(
                  'Own ${_shortId(relationship.ownStarterDisplayId)} · Peer ${_shortId(relationship.peerStarterDisplayId)}',
                ),
                trailing: trailingIcon,
                onTap: () async {
                  if (_breakingPeerPubkey != null) return;
                  Navigator.pop(context);
                  await _confirmRelationshipTransition(
                    relationship,
                    remoteBreakPending: remoteBreakPending,
                    peerLabel: _peerDisplayName(group),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _actOnGroup(RelationshipPeerGroup group) async {
    if (_breakingPeerPubkey != null) return;
    if (group.pendingRemoteBreakRelationships.isNotEmpty) {
      await _chooseRelationshipAndApply(
        group: group,
        candidates: group.pendingRemoteBreakRelationships,
        remoteBreakPending: true,
      );
      return;
    }
    await _chooseRelationshipAndApply(
      group: group,
      candidates: group.activeRelationships,
      remoteBreakPending: false,
    );
  }

  List<RelationshipPeerGroup> get _groupedRelationships {
    final filtered = _filterKind == null
        ? _relationshipGroups
        : _relationshipGroups
            .where((group) => group.activeKinds.any(
                  (kind) => kind.displayName == _filterKind,
                ))
            .toList();
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationships'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _filterKind = value == 'all' ? null : value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'all',
                child: Text('All'),
              ),
              ...StarterKind.values.map(
                (kind) => PopupMenuItem<String>(
                  value: kind.displayName,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: kind.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(kind.displayName),
                    ],
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRelationships,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupedRelationships.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No relationships yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Accept invitations to build your network',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  itemCount: _groupedRelationships.length,
                  itemBuilder: (context, index) {
                    final group = _groupedRelationships[index];
                    return _RelationshipPeerCard(
                      group: group,
                      displayPeerName: _peerDisplayName(group),
                      peerIdentityHint: _peerIdentityHint(group),
                      isBreaking: _breakingPeerPubkey != null &&
                          group.relationships.any(
                            (relationship) =>
                                relationship.peerPubkey == _breakingPeerPubkey,
                          ),
                      onBreak: group.activeRelationships.isEmpty
                          ? null
                          : () => _actOnGroup(group),
                    );
                  },
                ),
    );
  }

  String _shortId(String value) {
    if (value.length <= 10) return value;
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  String _peerDisplayName(RelationshipPeerGroup group) {
    final rootKey = _resolvedRootKey(group);
    if (rootKey != null && rootKey.isNotEmpty) {
      return HivraIdFormat.short(rootKey);
    }
    return group.peerDisplayName;
  }

  String _peerIdentityHint(RelationshipPeerGroup group) {
    final transportNpub = HivraIdFormat.short(
      HivraIdFormat.formatNostrKeyFromBase64(group.peerPubkey),
    );
    final rootKey = _resolvedRootKey(group);
    if (rootKey != null && rootKey.isNotEmpty) {
      return 'Root ${HivraIdFormat.short(rootKey)} · transport $transportNpub';
    }
    return 'Unknown root · transport $transportNpub';
  }

  String? _resolvedRootKey(RelationshipPeerGroup group) {
    final projectedRootB64 = group.preferredPeerRootPubkey;
    if (projectedRootB64 != null && projectedRootB64.isNotEmpty) {
      return HivraIdFormat.formatCapsuleKeyFromBase64(projectedRootB64);
    }
    final importedRootKey = _peerRootKeyByTransportB64[group.peerPubkey];
    if (importedRootKey != null && importedRootKey.isNotEmpty) {
      return importedRootKey;
    }
    return null;
  }
}

class _RelationshipPeerCard extends StatelessWidget {
  final RelationshipPeerGroup group;
  final String displayPeerName;
  final String peerIdentityHint;
  final VoidCallback? onBreak;
  final bool isBreaking;

  const _RelationshipPeerCard({
    required this.group,
    required this.displayPeerName,
    required this.peerIdentityHint,
    this.onBreak,
    this.isBreaking = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeKinds = group.activeKinds;

    return Card(
      elevation: group.isActive ? 2 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: group.isActive ? null : Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: group.isActive ? Colors.transparent : Colors.red.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: activeKinds.isEmpty
                    ? Colors.grey.withAlpha(36)
                    : activeKinds.first.color.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  displayPeerName[0],
                  style: TextStyle(
                    color: activeKinds.isEmpty
                        ? Colors.grey
                        : activeKinds.first.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayPeerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (!group.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Broken',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    peerIdentityHint,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...activeKinds.map(
                        (kind) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: kind.color.withAlpha(30),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: kind.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                kind.displayName,
                                style: TextStyle(
                                  color: kind.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (group.brokenRelationships.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(24),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${group.brokenRelationships.length} broken',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (group.pendingRemoteBreakRelationships.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(30),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${group.pendingRemoteBreakRelationships.length} break pending',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group.isActive
                        ? '${group.activeRelationships.length} active starter link${group.activeRelationships.length == 1 ? '' : 's'}'
                        : 'No active starter links',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  if (group.pendingRemoteBreakRelationships.isNotEmpty)
                    const Text(
                      'Peer requested break. Confirm from this screen to converge pairwise state.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  if (group.pendingRemoteBreakRelationships.isNotEmpty)
                    const SizedBox(height: 4),
                  Text(
                    'Since ${_formatDate(group.latestEstablishedAt)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (group.isActive && onBreak != null)
              IconButton(
                icon: isBreaking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        group.pendingRemoteBreakRelationships.isNotEmpty
                            ? Icons.check_circle_outline
                            : Icons.link_off,
                        color: group.pendingRemoteBreakRelationships.isNotEmpty
                            ? Colors.orange
                            : Colors.red,
                      ),
                onPressed: onBreak,
                tooltip: group.pendingRemoteBreakRelationships.isNotEmpty
                    ? (group.pendingRemoteBreakRelationships.length == 1
                        ? 'Confirm break request'
                        : 'Choose break request to confirm')
                    : (group.activeRelationships.length == 1
                        ? 'Break relationship'
                        : 'Choose relationship to break'),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30} months';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours';
    } else {
      return 'Just now';
    }
  }
}
