import 'dart:convert';

import 'package:crypto/crypto.dart';

enum CapsuleHistorySubjectKind { relationship, starter, invitation }

typedef HistoryViewProjector =
    String? Function(String ledgerJson, String requestJson);

class CapsuleHistorySubject {
  final CapsuleHistorySubjectKind kind;
  final String primaryId;
  final String? secondaryId;
  final String displayLabel;

  const CapsuleHistorySubject._({
    required this.kind,
    required this.primaryId,
    required this.displayLabel,
    this.secondaryId,
  });

  const CapsuleHistorySubject.relationship({
    required String peerTransportKey,
    String? peerRootKey,
    required String displayLabel,
  }) : this._(
         kind: CapsuleHistorySubjectKind.relationship,
         primaryId: peerTransportKey,
         secondaryId: peerRootKey,
         displayLabel: displayLabel,
       );

  const CapsuleHistorySubject.starter({
    required String starterId,
    required String displayLabel,
  }) : this._(
         kind: CapsuleHistorySubjectKind.starter,
         primaryId: starterId,
         displayLabel: displayLabel,
       );

  const CapsuleHistorySubject.invitation({
    required String invitationId,
    required String displayLabel,
  }) : this._(
         kind: CapsuleHistorySubjectKind.invitation,
         primaryId: invitationId,
         displayLabel: displayLabel,
       );

  Map<String, dynamic> toCanonicalJson() => <String, dynamic>{
    'kind': kind.name,
    'primary_id': primaryId,
    if (secondaryId != null) 'secondary_id': secondaryId,
  };
}

class CapsuleHistoryEntry {
  final int ledgerIndex;
  final String eventKind;
  final int? timestamp;
  final String timeLabel;
  final String summary;

  const CapsuleHistoryEntry({
    required this.ledgerIndex,
    required this.eventKind,
    required this.timestamp,
    required this.timeLabel,
    required this.summary,
  });

  Map<String, dynamic> toAdvisoryJson() => <String, dynamic>{
    'ledger_index': ledgerIndex,
    'event_kind': eventKind,
    if (timestamp != null) 'timestamp': timestamp,
    'time_label': timeLabel,
    'summary': summary,
  };
}

class CapsuleHistoryProjection {
  final int schemaVersion;
  final CapsuleHistorySubject subject;
  final List<CapsuleHistoryEntry> entries;
  final String projectionHashHex;

  const CapsuleHistoryProjection({
    required this.schemaVersion,
    required this.subject,
    required this.entries,
    required this.projectionHashHex,
  });

  Map<String, dynamic> toAdvisoryJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'subject': <String, dynamic>{
      'kind': subject.kind.name,
      'label': subject.displayLabel,
    },
    'projection_hash_hex': projectionHashHex,
    'events': entries.map((entry) => entry.toAdvisoryJson()).toList(),
    'source': 'local_capsule_ledger_projection',
  };
}

class CapsuleHistoryProjectionService {
  final String? Function() _exportLedger;
  final HistoryViewProjector _projectHistoryView;

  const CapsuleHistoryProjectionService({
    required String? Function() exportLedger,
    required HistoryViewProjector projectHistoryView,
  }) : _exportLedger = exportLedger,
       _projectHistoryView = projectHistoryView;

  CapsuleHistoryProjection project(CapsuleHistorySubject subject) {
    final entries = <CapsuleHistoryEntry>[];
    final ledgerJson = _exportLedger();
    final primaryId = _decode32(subject.primaryId);
    final secondaryId = _decode32(subject.secondaryId);
    if (ledgerJson != null && primaryId != null) {
      final requestJson = jsonEncode(<String, dynamic>{
        'schema': 'hivra.history_view.request',
        'version': 1,
        'subject': <String, dynamic>{
          'kind': subject.kind.name,
          'primary_id': primaryId,
          'secondary_id': secondaryId,
        },
      });
      final projected = _projectHistoryView(ledgerJson, requestJson);
      final rawEntries = _decodeEntries(projected, subject);
      for (final event in rawEntries) {
        final timestamp = _timestampValue(event['timestamp']);
        final ledgerIndex = _nonNegativeInt(event['ledger_index']);
        final eventKind = event['event_kind'];
        final summaryCode = event['summary_code'];
        if (ledgerIndex == null ||
            eventKind is! String ||
            summaryCode is! String) {
          continue;
        }
        entries.add(
          CapsuleHistoryEntry(
            ledgerIndex: ledgerIndex,
            eventKind: eventKind,
            timestamp: timestamp,
            timeLabel: _timeLabel(timestamp),
            summary: _summary(summaryCode, event),
          ),
        );
      }
    }

    final canonical = <String, dynamic>{
      'schema_version': 1,
      'subject': subject.toCanonicalJson(),
      'events': entries.map((entry) => entry.toAdvisoryJson()).toList(),
    };
    return CapsuleHistoryProjection(
      schemaVersion: 1,
      subject: subject,
      entries: List<CapsuleHistoryEntry>.unmodifiable(entries),
      projectionHashHex:
          sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
    );
  }

  List<Map<String, dynamic>> _decodeEntries(
    String? projectionJson,
    CapsuleHistorySubject subject,
  ) {
    if (projectionJson == null) return const <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(projectionJson);
      if (decoded is! Map) return const <Map<String, dynamic>>[];
      final root = Map<String, dynamic>.from(decoded);
      if (root['schema'] != 'hivra.history_view' || root['version'] != 1) {
        return const <Map<String, dynamic>>[];
      }
      final projectedSubject = root['subject'];
      if (projectedSubject is! Map ||
          projectedSubject['kind'] != subject.kind.name ||
          !_bytesEqual(
            projectedSubject['primary_id'],
            _decode32(subject.primaryId),
          ) ||
          !_bytesEqual(
            projectedSubject['secondary_id'],
            _decode32(subject.secondaryId),
          )) {
        return const <Map<String, dynamic>>[];
      }
      final rawEntries = root['entries'];
      if (rawEntries is! List) return const <Map<String, dynamic>>[];
      return rawEntries
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  String _summary(String code, Map<String, dynamic> event) {
    final ids = event['summary_ids'];
    String id(int index) {
      if (ids is! List || index >= ids.length) return 'unknown';
      final value = _bytes32(ids[index]);
      return value == null ? 'unknown' : _short(base64.encode(value));
    }

    final starterKind = _starterKind(_nonNegativeInt(event['starter_kind']));
    final reason = _nonNegativeInt(event['reason']);
    return switch (code) {
      'invitation_sent' => 'Invitation ${id(0)} sent with starter ${id(1)}.',
      'invitation_received' =>
        'Invitation ${id(0)} received with starter ${id(1)}.',
      'invitation_accepted' =>
        'Invitation ${id(0)} accepted; starter ${id(1)} recorded.',
      'invitation_rejected' =>
        'Invitation ${id(0)} rejected (${reason == 0 ? 'empty slot' : 'declined'}).',
      'invitation_expired' => 'Invitation ${id(0)} expired.',
      'starter_created' => 'Starter ${id(0)} created ($starterKind).',
      'starter_burned' =>
        'Starter ${id(0)} burned (${reason == 0 ? 'invitation rejected' : 'recorded reason'}).',
      'relationship_established' =>
        'Relationship established with ${id(0)} using $starterKind.',
      'relationship_broken' => 'Relationship with ${id(0)} broken.',
      _ => 'Ledger event recorded.',
    };
  }

  List<int>? _decode32(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    try {
      final bytes = base64.decode(normalized);
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  List<int>? _bytes32(dynamic value) {
    if (value is! List || value.length != 32) return null;
    final bytes = <int>[];
    for (final raw in value) {
      if (raw is! num || raw.toInt() < 0 || raw.toInt() > 255) return null;
      bytes.add(raw.toInt());
    }
    return bytes;
  }

  bool _bytesEqual(dynamic raw, List<int>? expected) {
    if (raw == null || expected == null) return raw == null && expected == null;
    final actual = _bytes32(raw);
    if (actual == null) return false;
    for (var index = 0; index < 32; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  int? _nonNegativeInt(dynamic raw) {
    if (raw is! num || raw.toInt() < 0) return null;
    return raw.toInt();
  }

  int? _timestampValue(dynamic raw) {
    if (raw is! num || raw.toInt() <= 0) return null;
    return raw.toInt();
  }

  String _timeLabel(int? raw) {
    if (raw == null) return 'Unknown time';
    int epochMs;
    if (raw >= 1000000000000000000) {
      epochMs = raw ~/ 1000000;
    } else if (raw >= 1000000000000000) {
      epochMs = raw ~/ 1000;
    } else if (raw >= 1000000000000) {
      epochMs = raw;
    } else if (raw >= 1000000000) {
      epochMs = raw * 1000;
    } else {
      return 'Ledger step $raw';
    }
    final value = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
    if (value.year < 2020 || value.year > 2100) return 'Ledger step $raw';
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')} UTC';
  }

  String _starterKind(int? value) {
    return switch (value) {
      0 => 'Juice',
      1 => 'Spark',
      2 => 'Seed',
      3 => 'Pulse',
      4 => 'Kick',
      _ => 'unknown kind',
    };
  }

  String _short(String value) {
    if (value.length <= 15) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 5)}';
  }
}
