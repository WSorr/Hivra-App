import 'package:flutter/material.dart';

import '../models/relationship.dart';
import '../models/relationship_peer_group.dart';
import '../models/starter.dart';
import '../services/relationship_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRelationships();
  }

  Future<void> _loadRelationships() async {
    setState(() {
      _relationshipGroups = widget.service.loadRelationshipGroups();
      _isLoading = false;
    });
  }

  Future<void> _confirmBreakRelationship(Relationship relationship) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Break Relationship?'),
        content: Text(
          'This will break your relationship with ${relationship.peerDisplayName}. '
          'Your starter will NOT be burned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final ok = await widget.service.breakRelationship(relationship);
              if (!mounted) return;
              navigator.pop();
              if (!ok) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to break relationship')),
                );
                return;
              }
              await _loadRelationships();
              await widget.onLedgerChanged?.call();
            },
            child: const Text('Break'),
          ),
        ],
      ),
    );
  }

  Future<void> _breakGroup(RelationshipPeerGroup group) async {
    final active = group.activeRelationships;
    if (active.isEmpty) return;

    if (active.length == 1) {
      await _confirmBreakRelationship(active.first);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Break link with ${group.peerDisplayName}'),
              subtitle: const Text('Choose which starter relationship to break'),
            ),
            ...active.map(
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
                trailing: const Icon(Icons.link_off, color: Colors.red),
                onTap: () async {
                  Navigator.pop(context);
                  await _confirmBreakRelationship(relationship);
                },
              ),
            ),
          ],
        ),
      ),
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
                      onBreak: group.activeRelationships.isEmpty
                          ? null
                          : () => _breakGroup(group),
                    );
                  },
                ),
    );
  }

  String _shortId(String value) {
    if (value.length <= 10) return value;
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }
}

class _RelationshipPeerCard extends StatelessWidget {
  final RelationshipPeerGroup group;
  final VoidCallback? onBreak;

  const _RelationshipPeerCard({
    required this.group,
    this.onBreak,
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
                  group.peerDisplayName[0],
                  style: TextStyle(
                    color:
                        activeKinds.isEmpty ? Colors.grey : activeKinds.first.color,
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
                          group.peerDisplayName,
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
                  Text(
                    'Since ${_formatDate(group.latestEstablishedAt)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (group.isActive && onBreak != null)
              IconButton(
                icon: const Icon(Icons.link_off, color: Colors.red),
                onPressed: onBreak,
                tooltip: group.activeRelationships.length == 1
                    ? 'Break relationship'
                    : 'Choose relationship to break',
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
