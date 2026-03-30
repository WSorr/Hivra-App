import 'dart:convert';

import 'ledger_view_support.dart';

class CapsuleBackupCodec {
  static const String schema = 'hivra.capsule_backup';
  static const int version = 1;
  static const LedgerViewSupport _support = LedgerViewSupport();

  static String encodeBackupEnvelope({
    required String ledgerJson,
    bool? isGenesis,
    bool? isNeste,
  }) {
    final ledger = _support.exportLedgerRoot(ledgerJson);
    if (ledger == null) {
      throw const FormatException('Ledger JSON must be an object');
    }

    final envelope = <String, dynamic>{
      'schema': schema,
      'version': version,
      'exported_at_utc': DateTime.now().toUtc().toIso8601String(),
      'ledger': ledger,
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

    final obj = _decodeJsonMap(trimmed);
    if (obj == null) return null;

    // v1 envelope
    if (obj['schema'] == schema && obj['version'] == version) {
      final normalized = _coerceJsonMap(obj['ledger']);
      if (normalized == null) return null;
      if (!_isLedgerShape(normalized)) {
        return null;
      }
      return jsonEncode(normalized);
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
    final ownerBytes = _support.payloadBytes(raw);
    if (ownerBytes.length != 32) return null;
    return ownerBytes;
  }

  static Map<String, dynamic>? _decodeJsonMap(String rawJson) {
    final decoded = jsonDecode(rawJson);
    return _coerceJsonMap(decoded);
  }

  static Map<String, dynamic>? _coerceJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
