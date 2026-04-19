import 'dart:async';

import 'package:flutter/material.dart';

import '../models/relationship.dart';
import '../models/relationship_peer_group.dart';
import '../models/starter.dart';
import '../services/relationship_service.dart';
import '../services/ui_feedback_service.dart';
import '../utils/peer_identity_format.dart';

@visibleForTesting
Set<String> pruneNotifiedPendingRemoteBreakKeys({
  required Set<String> notifiedKeys,
  required Set<String> currentPendingKeys,
}) {
  return notifiedKeys.intersection(currentPendingKeys);
}

@visibleForTesting
Set<String> computeNewPendingRemoteBreakKeys({
  required Set<String> currentPendingKeys,
  required Set<String> previousPendingKeys,
  required Set<String> notifiedKeys,
}) {
  return currentPendingKeys
      .difference(previousPendingKeys)
      .difference(notifiedKeys);
}

@visibleForTesting
bool shouldSuppressPendingRemoteBreakNotification({
  required DateTime now,
  required DateTime? lastShownAt,
  Duration cooldown = const Duration(seconds: 8),
}) {
  if (lastShownAt == null) return false;
  return now.difference(lastShownAt) < cooldown;
}

@visibleForTesting
bool shouldDeferPendingRemoteBreakNotifications({
  required bool baselineReady,
}) {
  return !baselineReady;
}

class RelationshipsScreen extends StatefulWidget {
  final RelationshipService service;
  final Future<void> Function()? onLedgerChanged;
  final Future<void> Function()? onSyncTransport;

  const RelationshipsScreen({
    super.key,
    required this.service,
    this.onLedgerChanged,
    this.onSyncTransport,
  });

  @override
  State<RelationshipsScreen> createState() => _RelationshipsScreenState();
}

class _RelationshipsScreenState extends State<RelationshipsScreen> {
  static const Duration _pendingRemoteBreakNotificationCooldown =
      Duration(seconds: 8);
  List<RelationshipPeerGroup> _relationshipGroups = [];
  bool _isLoading = true;
  bool _isSyncingTransport = false;
  Future<void>? _loadRelationshipsInFlight;
  int _peerRootLookupGeneration = 0;
  Set<String> _notifiedPendingRemoteBreakKeys = <String>{};
  final Map<String, DateTime> _lastPendingRemoteBreakNotificationAtByKey =
      <String, DateTime>{};
  bool _pendingRemoteBreakBaselineReady = false;
  String? _filterKind;
  String? _breakingPeerPubkey;
  Map<String, String> _peerRootKeyByTransportB64 = const <String, String>{};

  Future<void> _showBreakProgressDialog({required bool remoteBreakPending}) {
    final message = remoteBreakPending
        ? 'Confirming break request...'
        : 'Breaking relationship...';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapFromLedgerThenSync());
  }

  Future<void> _bootstrapFromLedgerThenSync() async {
    await _loadRelationships();
    unawaited(_syncTransportAndReload(silent: true));
  }

  Future<void> _loadRelationships({bool forceFresh = false}) async {
    final inFlight = _loadRelationshipsInFlight;
    if (inFlight != null) {
      await inFlight;
      if (!forceFresh) {
        return;
      }
    }

    final operation = _loadRelationshipsImpl();
    _loadRelationshipsInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_loadRelationshipsInFlight, operation)) {
        _loadRelationshipsInFlight = null;
      }
    }
  }

  Future<void> _loadRelationshipsImpl() async {
    final previousPendingBreakKeys =
        _pendingRemoteBreakKeysForGroups(_relationshipGroups);
    final groups = widget.service.loadRelationshipGroups();
    if (!mounted) return;
    setState(() {
      _relationshipGroups = groups;
      _isLoading = false;
    });

    _notifyNewPendingRemoteBreaks(
      groups: groups,
      previousPendingBreakKeys: previousPendingBreakKeys,
    );

    final lookupGeneration = ++_peerRootLookupGeneration;
    final peerRootKeys = await widget.service.loadPeerRootKeysForGroups(groups);
    if (!mounted || lookupGeneration != _peerRootLookupGeneration) return;
    setState(() {
      _peerRootKeyByTransportB64 = peerRootKeys;
    });
  }

  Future<void> _syncTransportAndReload({bool silent = false}) async {
    if (_isSyncingTransport) return;
    _isSyncingTransport = true;
    try {
      final sync = widget.onSyncTransport;
      if (sync != null) {
        await sync();
      }
    } finally {
      _isSyncingTransport = false;
    }
    await _loadRelationships(forceFresh: true);
    await widget.onLedgerChanged?.call();
    if (!silent && mounted) {
      UiFeedbackService.showSnackBar(
        context,
        'Relationships refreshed',
        source: 'relationships.refresh',
        duration: const Duration(seconds: 2),
        enableCopy: false,
      );
    }
  }

  Set<String> _pendingRemoteBreakKeysForGroups(
    List<RelationshipPeerGroup> groups,
  ) {
    final keys = <String>{};
    for (final group in groups) {
      for (final relationship in group.pendingRemoteBreakRelationships) {
        keys.add(_relationshipProjectionKey(relationship));
      }
    }
    return keys;
  }

  String _relationshipProjectionKey(Relationship relationship) {
    return '${relationship.peerPubkey}:${relationship.ownStarterId}:${relationship.peerStarterId}';
  }

  String _pendingRemoteBreakNotificationKey(
    List<RelationshipPeerGroup> affectedGroups,
  ) {
    if (affectedGroups.length == 1) {
      return affectedGroups.first.peerPubkey;
    }
    final peers = affectedGroups
        .map((group) => group.peerPubkey)
        .toList(growable: false)
      ..sort();
    return peers.join('|');
  }

  void _notifyNewPendingRemoteBreaks({
    required List<RelationshipPeerGroup> groups,
    required Set<String> previousPendingBreakKeys,
  }) {
    final currentPendingBreakKeys = _pendingRemoteBreakKeysForGroups(groups);
    if (shouldDeferPendingRemoteBreakNotifications(
      baselineReady: _pendingRemoteBreakBaselineReady,
    )) {
      _pendingRemoteBreakBaselineReady = true;
      _notifiedPendingRemoteBreakKeys = pruneNotifiedPendingRemoteBreakKeys(
        notifiedKeys: _notifiedPendingRemoteBreakKeys,
        currentPendingKeys: currentPendingBreakKeys,
      );
      return;
    }

    _notifiedPendingRemoteBreakKeys = pruneNotifiedPendingRemoteBreakKeys(
      notifiedKeys: _notifiedPendingRemoteBreakKeys,
      currentPendingKeys: currentPendingBreakKeys,
    );
    final newPendingBreakKeys = computeNewPendingRemoteBreakKeys(
      currentPendingKeys: currentPendingBreakKeys,
      previousPendingKeys: previousPendingBreakKeys,
      notifiedKeys: _notifiedPendingRemoteBreakKeys,
    );
    if (newPendingBreakKeys.isEmpty || !mounted) {
      return;
    }

    final affectedGroups = groups.where((group) {
      return group.pendingRemoteBreakRelationships.any(
        (relationship) => newPendingBreakKeys
            .contains(_relationshipProjectionKey(relationship)),
      );
    }).toList();
    if (affectedGroups.isEmpty) {
      _notifiedPendingRemoteBreakKeys.addAll(newPendingBreakKeys);
      return;
    }

    final now = DateTime.now();
    final staleThreshold = now.subtract(
      Duration(
        seconds: _pendingRemoteBreakNotificationCooldown.inSeconds * 2,
      ),
    );
    _lastPendingRemoteBreakNotificationAtByKey
        .removeWhere((_, shownAt) => shownAt.isBefore(staleThreshold));
    final notificationKey = _pendingRemoteBreakNotificationKey(affectedGroups);
    final lastShownAt =
        _lastPendingRemoteBreakNotificationAtByKey[notificationKey];
    final suppressByCooldown = shouldSuppressPendingRemoteBreakNotification(
      now: now,
      lastShownAt: lastShownAt,
      cooldown: _pendingRemoteBreakNotificationCooldown,
    );
    if (suppressByCooldown) {
      _notifiedPendingRemoteBreakKeys.addAll(newPendingBreakKeys);
      return;
    }

    final message = affectedGroups.length == 1
        ? 'Break request received from ${_peerDisplayName(affectedGroups.first)}'
        : 'Received ${newPendingBreakKeys.length} break requests';

    UiFeedbackService.showSnackBar(
      context,
      message,
      source: 'relationships.break.pending_remote',
      duration: const Duration(seconds: 2),
      enableCopy: false,
    );
    _lastPendingRemoteBreakNotificationAtByKey[notificationKey] = now;
    _notifiedPendingRemoteBreakKeys.addAll(newPendingBreakKeys);
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
    _showBreakProgressDialog(remoteBreakPending: remoteBreakPending);
    bool ok = false;
    try {
      ok = remoteBreakPending
          ? await widget.service.confirmRemoteBreak(relationship)
          : await widget.service.breakRelationship(relationship);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    }
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
    await _loadRelationships(forceFresh: true);
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
            onPressed:
                _isSyncingTransport ? null : () => _syncTransportAndReload(),
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
    return PeerIdentityFormat.displayName(
      transportPubkeyB64: group.peerPubkey,
      rootCapsuleKey: _resolvedRootKey(group),
    );
  }

  String _peerIdentityHint(RelationshipPeerGroup group) {
    return PeerIdentityFormat.identityHint(
      transportPubkeyB64: group.peerPubkey,
      rootCapsuleKey: _resolvedRootKey(group),
    );
  }

  String? _resolvedRootKey(RelationshipPeerGroup group) {
    return widget.service.resolvePeerRootDisplayKey(
      group: group,
      importedRootKeyByTransportB64: _peerRootKeyByTransportB64,
    );
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
                onPressed: isBreaking ? null : onBreak,
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
