import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'ledger_view_support.dart';

enum CapsuleHistorySubjectKind { relationship, starter, invitation }

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
  final LedgerViewSupport _support;

  const CapsuleHistoryProjectionService({
    required String? Function() exportLedger,
    LedgerViewSupport support = const LedgerViewSupport(),
  }) : _exportLedger = exportLedger,
       _support = support;

  CapsuleHistoryProjection project(CapsuleHistorySubject subject) {
    final root = _support.exportLedgerRoot(_exportLedger());
    final entries = <CapsuleHistoryEntry>[];
    if (root != null) {
      final events = _support.events(root);
      for (var index = 0; index < events.length; index++) {
        final raw = events[index];
        if (raw is! Map) continue;
        final event = Map<String, dynamic>.from(raw);
        final payload = _support.payloadBytes(event['payload']);
        final kindCode = _support.kindCode(event['kind']);
        if (!_matches(subject, kindCode, payload)) continue;
        final timestamp = _timestampValue(event['timestamp']);
        entries.add(
          CapsuleHistoryEntry(
            ledgerIndex: index,
            eventKind: _support.kindLabel(event['kind']),
            timestamp: timestamp,
            timeLabel: _timeLabel(timestamp),
            summary: _summary(kindCode, payload),
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

  bool _matches(CapsuleHistorySubject subject, int kind, Uint8List payload) {
    final primary = _decode32(subject.primaryId);
    final secondary = _decode32(subject.secondaryId);
    if (primary == null) return false;

    bool at(int start, Uint8List expected) {
      if (payload.length < start + 32) return false;
      for (var i = 0; i < 32; i++) {
        if (payload[start + i] != expected[i]) return false;
      }
      return true;
    }

    bool eitherAt(int start) =>
        at(start, primary) || (secondary != null && at(start, secondary));

    return switch (subject.kind) {
      CapsuleHistorySubjectKind.invitation => switch (kind) {
        1 || 9 || 2 || 3 || 4 => at(0, primary),
        7 => at(97, primary),
        _ => false,
      },
      CapsuleHistorySubjectKind.starter => switch (kind) {
        5 || 6 => at(0, primary),
        1 || 9 => at(32, primary),
        2 => at(64, primary),
        7 => at(32, primary) || at(64, primary) || at(162, primary),
        8 => at(32, primary),
        _ => false,
      },
      CapsuleHistorySubjectKind.relationship => switch (kind) {
        1 || 9 => eitherAt(64) || eitherAt(96),
        2 => eitherAt(32) || eitherAt(96),
        7 => eitherAt(0) || eitherAt(129) || eitherAt(194) || eitherAt(226),
        8 => eitherAt(0) || eitherAt(64),
        _ => false,
      },
    };
  }

  String _summary(int kind, Uint8List payload) {
    String id(int start) {
      if (payload.length < start + 32) return 'unknown';
      return _short(base64.encode(payload.sublist(start, start + 32)));
    }

    return switch (kind) {
      0 => 'Capsule created.',
      1 => 'Invitation ${id(0)} sent with starter ${id(32)}.',
      9 => 'Invitation ${id(0)} received with starter ${id(32)}.',
      2 => 'Invitation ${id(0)} accepted; starter ${id(64)} recorded.',
      3 => 'Invitation ${id(0)} rejected (${_rejectReason(payload)}).',
      4 => 'Invitation ${id(0)} expired.',
      5 => 'Starter ${id(0)} created (${_starterKind(payload, 64)}).',
      6 => 'Starter ${id(0)} burned (${_burnReason(payload)}).',
      7 =>
        'Relationship established with ${id(0)} using '
            '${_starterKind(payload, 96)}.',
      8 => 'Relationship with ${id(0)} broken.',
      _ => 'Ledger event recorded.',
    };
  }

  Uint8List? _decode32(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    try {
      final bytes = base64.decode(normalized);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
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

  String _starterKind(Uint8List payload, int offset) {
    if (payload.length <= offset) return 'unknown kind';
    return switch (payload[offset]) {
      0 => 'Juice',
      1 => 'Spark',
      2 => 'Seed',
      3 => 'Pulse',
      4 => 'Kick',
      _ => 'unknown kind',
    };
  }

  String _rejectReason(Uint8List payload) {
    if (payload.length < 33) return 'unknown reason';
    return payload[32] == 0 ? 'empty slot' : 'declined';
  }

  String _burnReason(Uint8List payload) {
    if (payload.length < 33) return 'unknown reason';
    return payload[32] == 0 ? 'invitation rejected' : 'recorded reason';
  }

  String _short(String value) {
    if (value.length <= 15) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 5)}';
  }
}
