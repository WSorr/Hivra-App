import 'dart:convert';

class CapsuleBackupCodec {
  static const String schema = 'hivra.capsule_backup';
  static const int version = 1;

  static String encodeBackupEnvelope({
    required String ledgerJson,
    bool? isGenesis,
    bool? isNeste,
  }) {
    final decoded = jsonDecode(ledgerJson);
    if (decoded is! Map) {
      throw const FormatException('Ledger JSON must be an object');
    }

    final envelope = <String, dynamic>{
      'schema': schema,
      'version': version,
      'exported_at_utc': DateTime.now().toUtc().toIso8601String(),
      'ledger': Map<String, dynamic>.from(decoded),
      'meta': <String, dynamic>{
        if (isGenesis != null) 'is_genesis': isGenesis,
        if (isNeste != null) 'is_neste': isNeste,
      },
    };

    return jsonEncode(envelope);
  }

  static String? tryExtractLedgerJson(String inputJson) {
    final trimmed = inputJson.trim();
    if (trimmed.isEmpty) return null;

    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;

    final obj = Map<String, dynamic>.from(decoded);

    // v1 envelope
    if (obj['schema'] == schema && obj['version'] == version) {
      final ledger = obj['ledger'];
      if (ledger is Map) {
        final normalized = Map<String, dynamic>.from(ledger);
        if (!_isLedgerShape(normalized)) {
          return null;
        }
        return jsonEncode(normalized);
      }
      return null;
    }

    // Legacy raw ledger JSON
    if (_isLedgerShape(obj)) {
      return jsonEncode(obj);
    }

    return null;
  }

  static bool _isLedgerShape(Map<String, dynamic> ledger) {
    final owner = _parseOwnerBytes(ledger['owner']);
    if (owner == null || owner.length != 32) return false;
    final events = ledger['events'];
    if (events is! List) return false;
    return true;
  }

  static List<int>? _parseOwnerBytes(dynamic raw) {
    if (raw is List) {
      if (raw.length != 32) return null;
      final out = <int>[];
      for (final item in raw) {
        if (item is! num) return null;
        final value = item.toInt();
        if (value < 0 || value > 255) return null;
        out.add(value);
      }
      return out;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed)) {
        final out = <int>[];
        for (var i = 0; i < trimmed.length; i += 2) {
          out.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
        }
        return out;
      }
      try {
        final decoded = base64Decode(trimmed);
        return decoded.length == 32 ? decoded : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
