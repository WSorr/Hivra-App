import 'dart:convert';
import 'dart:typed_data';

import '../models/starter.dart';

class LedgerViewSupport {
  const LedgerViewSupport();

  Map<String, dynamic>? exportLedgerRoot(String? json) {
    if (json == null || json.isEmpty) return null;
    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  List<dynamic> events(Map<String, dynamic> root) {
    final events = root['events'];
    return events is List ? events : const <dynamic>[];
  }

  bool? inferGenesisFromLedgerRoot(Map<String, dynamic>? root) {
    if (root == null) return null;
    for (final eventRaw in events(root)) {
      if (eventRaw is! Map) continue;
      final event = Map<String, dynamic>.from(eventRaw);
      if (kindCode(event['kind']) != 0) continue;

      final payload = payloadBytes(event['payload']);
      if (payload.length < 2) return null;

      final capsuleType = payload[1];
      if (capsuleType == 1) return true;
      if (capsuleType == 0) return false;
    }
    return null;
  }

  int kindCode(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      switch (value) {
        case 'CapsuleCreated':
          return 0;
        case 'InvitationSent':
          return 1;
        case 'InvitationReceived':
          return 9;
        case 'InvitationAccepted':
          return 2;
        case 'InvitationRejected':
          return 3;
        case 'InvitationExpired':
          return 4;
        case 'StarterCreated':
          return 5;
        case 'StarterBurned':
          return 6;
        case 'RelationshipEstablished':
          return 7;
        case 'RelationshipBroken':
          return 8;
      }
    }
    return -1;
  }

  String kindLabel(dynamic kind) {
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
        default:
          return 'Kind($kind)';
      }
    }
    return 'Unknown';
  }

  DateTime eventTime(dynamic ts) {
    if (ts is! num) return DateTime.now();

    final raw = ts.toInt();
    if (raw <= 0) return DateTime.now();

    final millis = raw < 100000000000 ? raw * 1000 : raw;

    try {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return DateTime.now();
    }
  }

  Uint8List payloadBytes(dynamic payload) {
    if (payload is List) {
      final out = <int>[];
      for (final item in payload) {
        if (item is! num) return Uint8List(0);
        final value = item.toInt();
        if (value < 0 || value > 255) return Uint8List(0);
        out.add(value);
      }
      return Uint8List.fromList(out);
    }
    if (payload is String) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty) return Uint8List(0);
      final isHex = RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed);
      if (isHex && trimmed.length.isEven) {
        final out = <int>[];
        for (int i = 0; i < trimmed.length; i += 2) {
          out.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
        }
        return Uint8List.fromList(out);
      }
      try {
        return Uint8List.fromList(base64.decode(trimmed));
      } catch (_) {
        return Uint8List(0);
      }
    }
    return Uint8List(0);
  }

  Uint8List bytes32(dynamic value) {
    if (value is List && value.length == 32) {
      return Uint8List.fromList(
        value.whereType<num>().map((v) => v.toInt()).toList(),
      );
    }
    final bytes = payloadBytes(value);
    return bytes.length == 32 ? bytes : Uint8List(32);
  }

  bool eq32(Uint8List a, Uint8List b) {
    if (a.length != 32 || b.length != 32) return false;
    for (var i = 0; i < 32; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int? slotForStarterId(Uint8List starterId, Map<int, Uint8List> slotToId) {
    for (final entry in slotToId.entries) {
      if (eq32(starterId, entry.value)) return entry.key;
    }
    return null;
  }

  StarterKind starterKindFromByte(int value) {
    switch (value) {
      case 0:
        return StarterKind.juice;
      case 1:
        return StarterKind.spark;
      case 2:
        return StarterKind.seed;
      case 3:
        return StarterKind.pulse;
      case 4:
        return StarterKind.kick;
      default:
        return StarterKind.juice;
    }
  }

  String? relationshipKeyFromEstablishedPayload(
    Uint8List payload, {
    String Function(Uint8List bytes)? encode32,
  }) {
    if (payload.length != 97 && payload.length != 194) return null;
    final encode = encode32 ?? (Uint8List bytes) => base64.encode(bytes);
    final peer = encode(Uint8List.fromList(payload.sublist(0, 32)));
    final ownStarter = encode(Uint8List.fromList(payload.sublist(32, 64)));
    return '$peer:$ownStarter';
  }

  String? relationshipPeerFromEstablishedPayload(
    Uint8List payload, {
    String Function(Uint8List bytes)? encode32,
  }) {
    if (payload.length != 97 && payload.length != 194) return null;
    final encode = encode32 ?? (Uint8List bytes) => base64.encode(bytes);
    return encode(Uint8List.fromList(payload.sublist(0, 32)));
  }

  String? relationshipKeyFromBrokenPayload(
    Uint8List payload, {
    String Function(Uint8List bytes)? encode32,
  }) {
    if (payload.length < 64) return null;
    final encode = encode32 ?? (Uint8List bytes) => base64.encode(bytes);
    final peer = encode(Uint8List.fromList(payload.sublist(0, 32)));
    final ownStarter = encode(Uint8List.fromList(payload.sublist(32, 64)));
    return '$peer:$ownStarter';
  }
}
