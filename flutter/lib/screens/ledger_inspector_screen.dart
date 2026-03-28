import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_runtime_service.dart';
import '../services/capsule_state_manager.dart';
import '../services/ledger_view_support.dart';
import '../services/pairwise_snapshot_service.dart';
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
  String _ledgerOwnerKey = 'No key';
  String _rootDisplayKey = 'No key';
  List<_LedgerEventRow> _recentEvents = const <_LedgerEventRow>[];
  List<PairwiseSnapshotRow> _pairwiseSnapshots = const <PairwiseSnapshotRow>[];
  Map<String, int> _eventCounts = const <String, int>{};
  List<String> _integrityHints = const <String>[];
  final PairwiseSnapshotService _pairwiseSnapshotService =
      const PairwiseSnapshotService();
  final LedgerViewSupport _support = const LedgerViewSupport();

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
      final ownerKey = state.publicKey.length == 32
          ? HivraIdFormat.formatCapsuleKeyBytes(state.publicKey)
          : 'No key';
      final rootPubKey = widget.runtime.capsuleRootPublicKey();
      final rootDisplayKey = rootPubKey == null || rootPubKey.isEmpty
          ? ownerKey
          : HivraIdFormat.formatCapsuleKeyBytes(rootPubKey);

      final raw = widget.runtime.exportLedger();
      if (raw == null || raw.trim().isEmpty) {
        setState(() {
          _capsuleState = state;
          _ledgerOwnerKey = ownerKey;
          _rootDisplayKey = rootDisplayKey;
          _rawLedgerJson = '';
          _recentEvents = const <_LedgerEventRow>[];
          _eventCounts = const <String, int>{};
          _integrityHints = const <String>[];
          _error = 'Ledger export returned empty result';
          _isLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        setState(() {
          _capsuleState = state;
          _ledgerOwnerKey = ownerKey;
          _rootDisplayKey = rootDisplayKey;
          _rawLedgerJson = raw;
          _recentEvents = const <_LedgerEventRow>[];
          _eventCounts = const <String, int>{};
          _integrityHints = const <String>[];
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
        final kindLabel = _support.kindLabel(event['kind']);
        counts[kindLabel] = (counts[kindLabel] ?? 0) + 1;
        final payloadBytes = _payloadBytes(event['payload']);

        rows.add(
          _LedgerEventRow(
            index: i,
            kind: kindLabel,
            timestamp: _timestampLabel(event['timestamp']),
            payloadSize: payloadBytes.length,
            signer: _shortSigner(event['signer']),
            details: _decodeEventDetails(kindLabel, event['payload']),
            rawEventJson: const JsonEncoder.withIndent('  ').convert(event),
            rawPayloadBase64:
                payloadBytes.isEmpty ? 'empty' : base64.encode(payloadBytes),
            rawPayloadHex: payloadBytes.isEmpty ? 'empty' : _hex(payloadBytes),
          ),
        );
      }

      final recent = rows.reversed.take(40).toList(growable: false);
      final snapshots = _pairwiseSnapshotService.buildSnapshots(
        events,
        widget.runtime.capsuleNostrPublicKey() ?? Uint8List(0),
      );
      final ledgerOwnerKey = _ownerKeyFromLedger(decoded) ?? ownerKey;
      final integrityHints = _buildIntegrityHints(events, rows);

      setState(() {
        _capsuleState = state;
        _ledgerOwnerKey = ledgerOwnerKey;
        _rootDisplayKey = rootDisplayKey;
        _rawLedgerJson = raw;
        _recentEvents = recent;
        _pairwiseSnapshots = snapshots;
        _eventCounts = counts;
        _integrityHints = integrityHints;
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

  String? _ownerKeyFromLedger(Map<String, dynamic> root) {
    final ownerBytes = _payloadBytes(root['owner']);
    if (ownerBytes.length != 32) return null;
    try {
      return HivraIdFormat.formatCapsuleKeyBytes(ownerBytes);
    } catch (_) {
      return null;
    }
  }

  List<String> _buildIntegrityHints(
    List<Map<String, dynamic>> events,
    List<_LedgerEventRow> rows,
  ) {
    var unknownKinds = 0;
    var malformedPayloads = 0;
    var malformedSigners = 0;

    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final row = rows[i];
      final kind = row.kind;
      if (kind.startsWith('Kind(') || kind == 'Unknown') {
        unknownKinds++;
      }
      final minPayloadBytes = _minPayloadBytes(kind);
      if (minPayloadBytes != null && row.payloadSize < minPayloadBytes) {
        malformedPayloads++;
      }
      final signerBytes = _payloadBytes(event['signer']);
      if (signerBytes.isNotEmpty && signerBytes.length != 32) {
        malformedSigners++;
      }
    }

    final hints = <String>[];
    if (unknownKinds > 0) {
      hints.add('Unknown event kinds: $unknownKinds');
    }
    if (malformedPayloads > 0) {
      hints.add('Malformed known-event payloads: $malformedPayloads');
    }
    if (malformedSigners > 0) {
      hints.add('Non-32-byte signer fields: $malformedSigners');
    }
    if (hints.isEmpty && events.isNotEmpty) {
      hints.add('No obvious integrity issues detected');
    }
    return hints;
  }

  String _shortSigner(dynamic signer) {
    if (signer is List) {
      final bytes =
          signer.whereType<num>().map((v) => v.toInt()).toList(growable: false);
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
    return _support.payloadBytes(payload);
  }

  String _keyLabel(List<int> bytes) => HivraIdFormat.short(
      HivraIdFormat.formatCapsuleKeyBytes(Uint8List.fromList(bytes)));

  String _starterLabel(List<int> bytes) => HivraIdFormat.short(
      HivraIdFormat.formatStarterIdBytes(Uint8List.fromList(bytes)));

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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
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
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
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
                          _kv('Capsule root',
                              _short(_rootDisplayKey, start: 16, end: 10),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 16),
                                onPressed: _rootDisplayKey == 'No key'
                                    ? null
                                    : () => _copyToClipboard(_rootDisplayKey,
                                        'Capsule root identity'),
                              )),
                          _kv('Ledger owner',
                              _short(_ledgerOwnerKey, start: 16, end: 10),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 16),
                                onPressed: _ledgerOwnerKey == 'No key'
                                    ? null
                                    : () => _copyToClipboard(
                                        _ledgerOwnerKey, 'Ledger owner key'),
                              )),
                          _kv('Network', state.isNeste ? 'NESTE' : 'HOOD'),
                          _kv('Ledger version', state.version.toString()),
                          _kv('Ledger hash',
                              _short(state.ledgerHashHex, start: 12, end: 8),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 16),
                                onPressed: state.ledgerHashHex.isEmpty
                                    ? null
                                    : () => _copyToClipboard(
                                        state.ledgerHashHex, 'Ledger hash'),
                              )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('State Counters'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _counterChip(
                              'Starters', state.starterCount, Colors.blue),
                          _counterChip('Relationships', state.relationshipCount,
                              Colors.green),
                          _counterChip('Pending', state.pendingInvitations,
                              Colors.orange),
                          _counterChip(
                              'Events', _recentEvents.length, Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('Event Distribution'),
                      _infoCard(
                        children: distribution
                            .map<Widget>((e) => _kv(e.key, e.value.toString()))
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('Integrity Hints'),
                      _infoCard(
                        children: _integrityHints
                            .map<Widget>((hint) => _kv('Hint', hint))
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
                                      _detailChip(
                                          'invites ${snapshot.invitationCount}'),
                                      _detailChip(
                                          'relationships ${snapshot.relationshipCount}'),
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
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: const Color(0xFF3A3646)),
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
                                            .map(
                                                (detail) => _detailChip(detail))
                                            .toList(growable: false),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      title:
                                          const Text('Raw event (on demand)'),
                                      childrenPadding: EdgeInsets.zero,
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF211E27),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: const Color(0xFF3A3646)),
                                          ),
                                          child: SelectableText(
                                            'payload.base64: ${event.rawPayloadBase64}\n'
                                            'payload.hex: ${event.rawPayloadHex}\n\n'
                                            '${event.rawEventJson}',
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

  int? _minPayloadBytes(String kind) {
    switch (kind) {
      case 'CapsuleCreated':
        return 2;
      case 'InvitationSent':
      case 'InvitationReceived':
      case 'InvitationAccepted':
        return 96;
      case 'InvitationRejected':
        return 33;
      case 'InvitationExpired':
        return 32;
      case 'StarterCreated':
        return 66;
      case 'StarterBurned':
        return 33;
      case 'RelationshipEstablished':
        return 97;
      case 'RelationshipBroken':
        return 64;
      default:
        return null;
    }
  }

  String _hex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

class _LedgerEventRow {
  final int index;
  final String kind;
  final String timestamp;
  final int payloadSize;
  final String signer;
  final List<String> details;
  final String rawEventJson;
  final String rawPayloadBase64;
  final String rawPayloadHex;

  const _LedgerEventRow({
    required this.index,
    required this.kind,
    required this.timestamp,
    required this.payloadSize,
    required this.signer,
    required this.details,
    required this.rawEventJson,
    required this.rawPayloadBase64,
    required this.rawPayloadHex,
  });
}
