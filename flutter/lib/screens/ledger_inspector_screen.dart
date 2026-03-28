import 'dart:convert';

import 'package:bech32/bech32.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_runtime_service.dart';
import '../services/capsule_state_manager.dart';
import '../utils/hivra_id_format.dart';

class LedgerInspectorScreen extends StatefulWidget {
  final AppRuntimeService runtime;

  LedgerInspectorScreen({
    super.key,
    AppRuntimeService? runtime,
  }) : runtime = runtime ?? AppRuntimeService();

  @override
  State<LedgerInspectorScreen> createState() => _LedgerInspectorScreenState();
}

class _LedgerInspectorScreenState extends State<LedgerInspectorScreen> {
  late final CapsuleStateManager _stateManager;

  bool _isLoading = true;
  String? _error;
  String _rawLedgerJson = '';
  CapsuleState? _capsuleState;
  String _ledgerOwnerB64 = 'No key';
  String _rootDisplayKey = 'No key';
  List<_LedgerEventRow> _recentEvents = const <_LedgerEventRow>[];
  List<_PairwiseSnapshotRow> _pairwiseSnapshots = const <_PairwiseSnapshotRow>[];
  Map<String, int> _eventCounts = const <String, int>{};

  @override
  void initState() {
    super.initState();
    _stateManager = widget.runtime.stateManager;
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _stateManager.refreshWithFullState();
      final state = _stateManager.state;
      final ownerB64 = state.publicKey.isEmpty ? 'No key' : base64.encode(state.publicKey);
      final rootPubKey = widget.runtime.capsuleRootPublicKey();
      final rootDisplayKey = rootPubKey == null || rootPubKey.isEmpty
          ? 'No key'
          : _encodeCapsulePublicKey(rootPubKey);

      final raw = widget.runtime.exportLedger();
      if (raw == null || raw.trim().isEmpty) {
        setState(() {
          _capsuleState = state;
          _ledgerOwnerB64 = ownerB64;
          _rootDisplayKey = rootDisplayKey;
          _rawLedgerJson = '';
          _recentEvents = const <_LedgerEventRow>[];
          _eventCounts = const <String, int>{};
          _error = 'Ledger export returned empty result';
          _isLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        setState(() {
          _capsuleState = state;
          _ledgerOwnerB64 = ownerB64;
          _rootDisplayKey = rootDisplayKey;
          _rawLedgerJson = raw;
          _recentEvents = const <_LedgerEventRow>[];
          _eventCounts = const <String, int>{};
          _error = 'Ledger JSON has unsupported shape';
          _isLoading = false;
        });
        return;
      }

      final events = _readEvents(decoded);
      final counts = <String, int>{};
      final rows = <_LedgerEventRow>[];

      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        final kindLabel = _kindLabel(event['kind']);
        counts[kindLabel] = (counts[kindLabel] ?? 0) + 1;

        rows.add(
          _LedgerEventRow(
            index: i,
            kind: kindLabel,
            timestamp: _timestampLabel(event['timestamp']),
            payloadSize: _payloadSize(event['payload']),
            signer: _shortSigner(event['signer']),
            details: _decodeEventDetails(kindLabel, event['payload']),
          ),
        );
      }

      final recent = rows.reversed.take(40).toList(growable: false);
      final snapshots = _buildPairwiseSnapshots(
        events,
        widget.runtime.capsuleNostrPublicKey() ?? Uint8List(0),
      );

      setState(() {
        _capsuleState = state;
        _ledgerOwnerB64 = ownerB64;
        _rootDisplayKey = rootDisplayKey;
        _rawLedgerJson = raw;
        _recentEvents = recent;
        _pairwiseSnapshots = snapshots;
        _eventCounts = counts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to read ledger: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _readEvents(Map<String, dynamic> root) {
    final rawEvents = root['events'];
    if (rawEvents is! List) return const <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final item in rawEvents) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  String _kindLabel(dynamic kind) {
    if (kind is String) return kind;
    if (kind is int) {
      switch (kind) {
        case 0:
          return 'CapsuleCreated';
        case 1:
          return 'InvitationSent';
        case 9:
          return 'InvitationReceived';
        case 2:
          return 'InvitationAccepted';
        case 3:
          return 'InvitationRejected';
        case 4:
          return 'InvitationExpired';
        case 5:
          return 'StarterCreated';
        case 6:
          return 'StarterBurned';
        case 7:
          return 'RelationshipEstablished';
        case 8:
          return 'RelationshipBroken';
      }
      return 'Kind($kind)';
    }
    return 'Unknown';
  }

  String _timestampLabel(dynamic timestamp) {
    if (timestamp is! num) return 'n/a';
    final raw = timestamp.toInt();
    if (raw <= 0) return 'n/a';

    // Support multiple possible timestamp units from different backends.
    int epochMs;
    if (raw >= 1000000000000000000) {
      // nanoseconds
      epochMs = raw ~/ 1000000;
    } else if (raw >= 1000000000000000) {
      // microseconds
      epochMs = raw ~/ 1000;
    } else if (raw >= 1000000000000) {
      // milliseconds
      epochMs = raw;
    } else if (raw >= 1000000000) {
      // seconds
      epochMs = raw * 1000;
    } else {
      // Likely logical counter/version, not wall-clock Unix time.
      return 'logical:$raw';
    }

    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
    if (dt.year < 2020 || dt.year > 2100) {
      return 'logical:$raw';
    }

    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$mi:$ss UTC';
  }

  int _payloadSize(dynamic payload) {
    if (payload is List) return payload.length;
    if (payload is String) {
      try {
        return base64.decode(payload).length;
      } catch (_) {
        return payload.length;
      }
    }
    return 0;
  }

  String _shortSigner(dynamic signer) {
    if (signer is List) {
      final bytes = signer.whereType<num>().map((v) => v.toInt()).toList(growable: false);
      if (bytes.length == 32) {
        return HivraIdFormat.short(
          HivraIdFormat.formatCapsuleKeyBytes(Uint8List.fromList(bytes)),
        );
      }
      if (bytes.isNotEmpty) return _short(base64.encode(bytes));
    }
    if (signer is String && signer.isNotEmpty) return _short(signer);
    return 'n/a';
  }

  String _short(String value, {int start = 10, int end = 6}) {
    if (value.length <= start + end + 3) return value;
    return '${value.substring(0, start)}...${value.substring(value.length - end)}';
  }

  List<_PairwiseSnapshotRow> _buildPairwiseSnapshots(
    List<Map<String, dynamic>> events,
    Uint8List localTransportKey,
  ) {
    if (localTransportKey.isEmpty || localTransportKey.length != 32) {
      return const <_PairwiseSnapshotRow>[];
    }

    final localTransportHex = _hex(localTransportKey);
    final inviteFactsById = <String, _PairwiseInviteFact>{};
    final inviteTransportPeerById = <String, String>{};
    final inviteRootPeerById = <String, String>{};
    final transportPeerToRootPeer = <String, String>{};
    final relationshipFactsByPeer = <String, List<_PairwiseRelationshipFact>>{};

    for (final event in events) {
      final kind = _kindLabel(event['kind']);
      final payload = _payloadBytes(event['payload']);
      final signer = _bytes32(event['signer']);

      if ((kind == 'InvitationSent' || kind == 'InvitationReceived') && payload.length >= 96) {
        final invitationId = _hex(payload.sublist(0, 32));
        final fact = inviteFactsById.putIfAbsent(invitationId, () => _PairwiseInviteFact(invitationId));
        final transportPeerHex = kind == 'InvitationReceived' && signer != null
            ? _hex(signer)
            : _hex(payload.sublist(64, 96));
        inviteTransportPeerById[invitationId] = transportPeerHex;
        final starterKind = payload.length >= 97 ? payload[96] : null;
        if (starterKind != null) {
          fact.starterKinds.add(starterKind);
        }
      } else if (kind == 'RelationshipEstablished' && payload.length == 194) {
        final peerRootHex = _hex(payload.sublist(0, 32));
        final invitationId = _hex(payload.sublist(97, 129));
        inviteRootPeerById[invitationId] = peerRootHex;
        final transportPeerHex = inviteTransportPeerById[invitationId];
        if (transportPeerHex != null) {
          transportPeerToRootPeer[transportPeerHex] = peerRootHex;
        }
        final relationship = _PairwiseRelationshipFact(
          invitationId: invitationId,
          relationshipKind: payload[96],
          starterPair: <String>[
            _hex(payload.sublist(32, 64)),
            _hex(payload.sublist(64, 96)),
          ]..sort(),
        );
        relationshipFactsByPeer.putIfAbsent(peerRootHex, () => <_PairwiseRelationshipFact>[]).add(relationship);
      }
    }

    for (final entry in inviteTransportPeerById.entries) {
      inviteRootPeerById.putIfAbsent(entry.key, () => transportPeerToRootPeer[entry.value] ?? '');
    }
    inviteRootPeerById.removeWhere((_, value) => value.isEmpty);

    for (final event in events) {
      final kind = _kindLabel(event['kind']);
      final payload = _payloadBytes(event['payload']);
      if (payload.length < 32) continue;

      final invitationId = _hex(payload.sublist(0, 32));
      final fact = inviteFactsById[invitationId];
      if (fact == null) continue;

      switch (kind) {
        case 'InvitationAccepted':
          fact.accepted = true;
          break;
        case 'InvitationRejected':
          if (payload.length >= 33) {
            fact.rejected = true;
            fact.rejectReasons.add(payload[32]);
          }
          break;
        case 'InvitationExpired':
          fact.expired = true;
          break;
      }
    }

    final inviteFactsByPeer = <String, List<_PairwiseInviteFact>>{};
    for (final entry in inviteFactsById.entries) {
      final peerRootHex = inviteRootPeerById[entry.key];
      if (peerRootHex == null || peerRootHex.isEmpty || entry.value.status == 'pending') {
        continue;
      }
      inviteFactsByPeer.putIfAbsent(peerRootHex, () => <_PairwiseInviteFact>[]).add(entry.value);
    }

    final snapshots = <_PairwiseSnapshotRow>[];
    final peers = <String>{...inviteFactsByPeer.keys, ...relationshipFactsByPeer.keys}.toList()..sort();

    for (final peerRootHex in peers) {
      final pairRoots = <String>[localTransportHex, peerRootHex]..sort();
      final finalizedInvitations = (inviteFactsByPeer[peerRootHex] ?? <_PairwiseInviteFact>[])..sort((a, b) => a.invitationId.compareTo(b.invitationId));
      final relationships = (relationshipFactsByPeer[peerRootHex] ?? <_PairwiseRelationshipFact>[])..sort((a, b) {
        final inviteCmp = a.invitationId.compareTo(b.invitationId);
        if (inviteCmp != 0) return inviteCmp;
        final kindCmp = a.relationshipKind.compareTo(b.relationshipKind);
        if (kindCmp != 0) return kindCmp;
        return a.starterPair.join(':').compareTo(b.starterPair.join(':'));
      });

      final snapshot = <String, dynamic>{
        'schema_version': 1,
        'pair_transport_keys_sorted': pairRoots,
        'finalized_invitations': finalizedInvitations.map((fact) {
          final item = <String, dynamic>{
            'invitation_id': fact.invitationId,
            'status': fact.status,
          };
          if (fact.starterKinds.isNotEmpty) {
            item['starter_kinds'] = fact.starterKinds.toList()..sort();
          }
          if (fact.rejected && fact.rejectReasons.isNotEmpty) {
            item['reject_reason'] = (fact.rejectReasons.toList()..sort()).first;
          }
          return item;
        }).toList(growable: false),
        'active_relationships': relationships.map((rel) => <String, dynamic>{
          'invitation_id': rel.invitationId,
          'relationship_kind': rel.relationshipKind,
          'starter_pair': rel.starterPair,
        }).toList(growable: false),
      };

      final canonical = jsonEncode(snapshot);
      final digest = sha256.convert(utf8.encode(canonical)).toString();
      snapshots.add(
        _PairwiseSnapshotRow(
          peerHex: peerRootHex,
          peerLabel: _keyLabel(_bytesFromHex(peerRootHex)),
          invitationCount: finalizedInvitations.length,
          relationshipCount: relationships.length,
          hashHex: digest,
          canonicalJson: const JsonEncoder.withIndent('  ').convert(snapshot),
        ),
      );
    }

    return snapshots;
  }

  List<String> _decodeEventDetails(String kind, dynamic payloadRaw) {
    final payload = _payloadBytes(payloadRaw);
    if (payload.isEmpty) return const <String>[];

    switch (kind) {
      case 'CapsuleCreated':
        if (payload.length >= 2) {
          return <String>[
            'network ${_networkLabel(payload[0])}',
            'capsule ${_capsuleTypeLabel(payload[1])}',
          ];
        }
        break;
      case 'InvitationSent':
      case 'InvitationReceived':
        if (payload.length >= 96) {
          final details = <String>[
            'invite ${_starterLabel(payload.sublist(0, 32))}',
            'starter ${_starterLabel(payload.sublist(32, 64))}',
            'to ${_keyLabel(payload.sublist(64, 96))}',
          ];
          if (payload.length >= 97) {
            details.add('kind ${_starterKindLabel(payload[96])}');
          }
          return details;
        }
        break;
      case 'InvitationAccepted':
        if (payload.length >= 96) {
          return <String>[
            'invite ${_starterLabel(payload.sublist(0, 32))}',
            'from ${_keyLabel(payload.sublist(32, 64))}',
            'created ${_starterLabel(payload.sublist(64, 96))}',
          ];
        }
        break;
      case 'InvitationRejected':
        if (payload.length >= 33) {
          return <String>[
            'invite ${_starterLabel(payload.sublist(0, 32))}',
            'reason ${_rejectReasonLabel(payload[32])}',
          ];
        }
        break;
      case 'InvitationExpired':
        if (payload.length >= 32) {
          return <String>['invite ${_starterLabel(payload.sublist(0, 32))}'];
        }
        break;
      case 'StarterCreated':
        if (payload.length >= 66) {
          return <String>[
            'starter ${_starterLabel(payload.sublist(0, 32))}',
            'kind ${_starterKindLabel(payload[64])}',
            'network ${_networkLabel(payload[65])}',
          ];
        }
        break;
      case 'StarterBurned':
        if (payload.length >= 33) {
          return <String>[
            'starter ${_starterLabel(payload.sublist(0, 32))}',
            'reason ${_rejectReasonLabel(payload[32])}',
          ];
        }
        break;
      case 'RelationshipEstablished':
        if (payload.length >= 97) {
          final details = <String>[
            'peer ${_keyLabel(payload.sublist(0, 32))}',
            'own ${_starterLabel(payload.sublist(32, 64))}',
            'peerstarter ${_starterLabel(payload.sublist(64, 96))}',
            'kind ${_starterKindLabel(payload[96])}',
          ];
          if (payload.length >= 194) {
            details.addAll(<String>[
              'invite ${_starterLabel(payload.sublist(97, 129))}',
              'sender ${_keyLabel(payload.sublist(129, 161))}',
              'sender kind ${_starterKindLabel(payload[161])}',
              'sender starter ${_starterLabel(payload.sublist(162, 194))}',
            ]);
          }
          return details;
        }
        break;
      case 'RelationshipBroken':
        if (payload.length >= 64) {
          return <String>[
            'peer ${_keyLabel(payload.sublist(0, 32))}',
            'own ${_starterLabel(payload.sublist(32, 64))}',
          ];
        }
        break;
    }

    return const <String>[];
  }

  Uint8List _payloadBytes(dynamic payload) {
    if (payload is List) {
      return Uint8List.fromList(
        payload.whereType<num>().map((v) => v.toInt()).toList(growable: false),
      );
    }
    if (payload is String) {
      try {
        return Uint8List.fromList(base64.decode(payload));
      } catch (_) {
        return Uint8List(0);
      }
    }
    return Uint8List(0);
  }

  Uint8List? _bytes32(dynamic raw) {
    if (raw is List) {
      final bytes = raw.whereType<num>().map((v) => v.toInt()).toList(growable: false);
      if (bytes.length == 32) return Uint8List.fromList(bytes);
    }
    if (raw is String) {
      try {
        final decoded = base64.decode(raw);
        if (decoded.length == 32) return Uint8List.fromList(decoded);
      } catch (_) {}
    }
    return null;
  }

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _bytesFromHex(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(out);
  }

  String _keyLabel(List<int> bytes) =>
      HivraIdFormat.short(HivraIdFormat.formatCapsuleKeyBytes(Uint8List.fromList(bytes)));

  String _starterLabel(List<int> bytes) =>
      HivraIdFormat.short(HivraIdFormat.formatStarterIdBytes(Uint8List.fromList(bytes)));

  String _starterKindLabel(int value) {
    switch (value) {
      case 0:
        return 'Juice';
      case 1:
        return 'Spark';
      case 2:
        return 'Seed';
      case 3:
        return 'Pulse';
      case 4:
        return 'Kick';
      default:
        return 'Kind($value)';
    }
  }

  String _rejectReasonLabel(int value) {
    switch (value) {
      case 0:
        return 'EmptySlot';
      case 1:
        return 'Other';
      default:
        return 'Reason($value)';
    }
  }

  String _networkLabel(int value) {
    switch (value) {
      case 0:
        return 'HOOD';
      case 1:
        return 'NESTE';
      default:
        return 'Network($value)';
    }
  }

  String _capsuleTypeLabel(int value) {
    switch (value) {
      case 0:
        return 'Leaf';
      case 1:
        return 'Relay';
      default:
        return 'Type($value)';
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final state = _capsuleState;
    final distribution = _eventCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ledger Inspector')),
        body: const Center(child: Text('Ledger inspector state unavailable')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger Inspector'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Copy raw ledger JSON',
            onPressed: _rawLedgerJson.isEmpty
                ? null
                : () => _copyToClipboard(_rawLedgerJson, 'Ledger JSON'),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionTitle('Capsule'),
                      _infoCard(
                        children: [
                          _kv('Capsule root', _short(_rootDisplayKey, start: 16, end: 10), trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: _rootDisplayKey == 'No key'
                                ? null
                                : () => _copyToClipboard(_rootDisplayKey, 'Capsule root identity'),
                          )),
                          _kv('Ledger owner (base64)', _short(_ledgerOwnerB64, start: 14, end: 8), trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: _ledgerOwnerB64 == 'No key'
                                ? null
                                : () => _copyToClipboard(_ledgerOwnerB64, 'Ledger owner key'),
                          )),
                          _kv('Network', state.isNeste ? 'NESTE' : 'HOOD'),
                          _kv('Ledger version', state.version.toString()),
                          _kv('Ledger hash', _short(state.ledgerHashHex, start: 12, end: 8), trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: state.ledgerHashHex.isEmpty ? null : () => _copyToClipboard(state.ledgerHashHex, 'Ledger hash'),
                          )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('State Counters'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _counterChip('Starters', state.starterCount, Colors.blue),
                          _counterChip('Relationships', state.relationshipCount, Colors.green),
                          _counterChip('Pending', state.pendingInvitations, Colors.orange),
                          _counterChip('Events', _recentEvents.length, Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('Event Distribution'),
                      _infoCard(
                        children: distribution
                            .map<Widget>((e) => _kv(e.key, e.value.toString()))
                            .toList(growable: false),
                      ),
                      if (_pairwiseSnapshots.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _sectionTitle('Pairwise Transport Snapshot Preview'),
                        ..._pairwiseSnapshots.map(
                          (snapshot) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          snapshot.peerLabel,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Copy snapshot JSON',
                                        onPressed: () => _copyToClipboard(
                                          snapshot.canonicalJson,
                                          'Pairwise snapshot JSON',
                                        ),
                                        icon: const Icon(Icons.copy, size: 18),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'hash ${_short(snapshot.hashHex, start: 18, end: 12)}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _detailChip('invites ${snapshot.invitationCount}'),
                                      _detailChip('relationships ${snapshot.relationshipCount}'),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding: EdgeInsets.zero,
                                    title: const Text('Canonical JSON'),
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF211E27),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFF3A3646)),
                                        ),
                                        child: SelectableText(
                                          snapshot.canonicalJson,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _sectionTitle('Recent Events (latest 40)'),
                      if (_recentEvents.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No events available'),
                          ),
                        )
                      else
                        ..._recentEvents.map((event) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _eventKindChip(event.kind),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '#${event.index}',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          event.timestamp,
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'payload ${event.payloadSize} bytes  •  signer ${event.signer}',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    if (event.details.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: event.details
                                            .map((detail) => _detailChip(detail))
                                            .toList(growable: false),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _infoCard({required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(children: children),
      ),
    );
  }

  Widget _kv(String key, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              key,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _counterChip(String label, int value, Color color) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: color.withValues(alpha: 0.18),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      labelStyle: TextStyle(color: color),
    );
  }

  Widget _eventKindChip(String label) {
    final color = _eventColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _detailChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2733),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF413C50)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }

  Color _eventColor(String kind) {
    switch (kind) {
      case 'CapsuleCreated':
        return Colors.tealAccent.shade200;
      case 'InvitationSent':
      case 'InvitationReceived':
        return Colors.orangeAccent.shade200;
      case 'InvitationAccepted':
        return Colors.greenAccent.shade200;
      case 'InvitationRejected':
      case 'InvitationExpired':
      case 'StarterBurned':
      case 'RelationshipBroken':
        return Colors.redAccent.shade100;
      case 'StarterCreated':
        return Colors.blueAccent.shade100;
      case 'RelationshipEstablished':
        return Colors.purpleAccent.shade100;
      default:
        return Colors.grey.shade300;
    }
  }

  String _encodeCapsulePublicKey(Uint8List bytes) {
    final words = _convertBits(bytes, 8, 5, true);
    return bech32.encode(Bech32('h', words));
  }

  List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxValue = (1 << to) - 1;

    for (final value in data) {
      if (value < 0 || (value >> from) != 0) {
        throw ArgumentError('Invalid key byte for bech32 conversion');
      }
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxValue);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (to - bits)) & maxValue);
      }
    } else if (bits >= from || ((acc << (to - bits)) & maxValue) != 0) {
      throw ArgumentError('Invalid bech32 padding');
    }

    return result;
  }
}

class _LedgerEventRow {
  final int index;
  final String kind;
  final String timestamp;
  final int payloadSize;
  final String signer;
  final List<String> details;

  const _LedgerEventRow({
    required this.index,
    required this.kind,
    required this.timestamp,
    required this.payloadSize,
    required this.signer,
    required this.details,
  });
}

class _PairwiseInviteFact {
  final String invitationId;
  final Set<String> starterIds = <String>{};
  final Set<int> starterKinds = <int>{};
  final Set<String> createdStarterIds = <String>{};
  final Set<int> rejectReasons = <int>{};
  bool accepted = false;
  bool rejected = false;
  bool expired = false;

  _PairwiseInviteFact(this.invitationId);

  String get status {
    if (accepted) return 'accepted';
    if (rejected) return 'rejected';
    if (expired) return 'expired';
    return 'pending';
  }
}

class _PairwiseRelationshipFact {
  final String invitationId;
  final int relationshipKind;
  final List<String> starterPair;

  const _PairwiseRelationshipFact({
    required this.invitationId,
    required this.relationshipKind,
    required this.starterPair,
  });
}

class _PairwiseSnapshotRow {
  final String peerHex;
  final String peerLabel;
  final int invitationCount;
  final int relationshipCount;
  final String hashHex;
  final String canonicalJson;

  const _PairwiseSnapshotRow({
    required this.peerHex,
    required this.peerLabel,
    required this.invitationCount,
    required this.relationshipCount,
    required this.hashHex,
    required this.canonicalJson,
  });
}
