import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'ledger_view_support.dart';

class CapsuleBackupContents {
  final String ledgerJson;
  final bool? isGenesis;
  final bool? isNeste;

  const CapsuleBackupContents({
    required this.ledgerJson,
    this.isGenesis,
    this.isNeste,
  });
}

class CapsuleBackupCodec {
  static const String schema = 'hivra.capsule_backup';
  static const int version = 1;
  static const int encryptedVersion = 2;
  static const String encryptedSuite = 'hkdf-sha256+a256gcm';
  static const String _keyInfo = 'hivra.capsule_backup.v2';
  static const LedgerViewSupport _support = LedgerViewSupport();

  static bool isEncryptedEnvelope(String inputJson) {
    final envelope = _decodeJsonMap(inputJson.trim());
    return envelope?['schema'] == schema &&
        envelope?['version'] == encryptedVersion;
  }

  static Future<String> encodeEncryptedBackupEnvelope({
    required String ledgerJson,
    required Uint8List seed,
    bool? isGenesis,
    bool? isNeste,
    List<int>? salt,
    List<int>? nonce,
  }) async {
    if (seed.isEmpty) {
      throw const FormatException('Backup encryption seed is empty');
    }
    final resolvedSalt = salt ?? _randomBytes(32);
    final cipher = AesGcm.with256bits();
    final resolvedNonce = nonce ?? cipher.newNonce();
    if (resolvedSalt.length != 32 || resolvedNonce.length != 12) {
      throw const FormatException('Invalid backup encryption parameters');
    }
    final secretKey = await _deriveKey(seed, resolvedSalt);
    final cleartext = utf8.encode(
      encodeBackupEnvelope(
        ledgerJson: ledgerJson,
        isGenesis: isGenesis,
        isNeste: isNeste,
      ),
    );
    final secretBox = await cipher.encrypt(
      cleartext,
      secretKey: secretKey,
      nonce: resolvedNonce,
      aad: _associatedData,
    );
    return jsonEncode(<String, dynamic>{
      'schema': schema,
      'version': encryptedVersion,
      'suite': encryptedSuite,
      'kdf': <String, dynamic>{
        'name': 'hkdf-sha256',
        'salt': base64Encode(resolvedSalt),
      },
      'cipher': <String, dynamic>{
        'name': 'aes-256-gcm',
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'tag': base64Encode(secretBox.mac.bytes),
      },
    });
  }

  static Future<String?> tryDecryptLedgerJson(
    String inputJson,
    Uint8List seed,
  ) async {
    return (await tryDecodeBackup(inputJson, seed))?.ledgerJson;
  }

  static Future<CapsuleBackupContents?> tryDecodeBackup(
    String inputJson,
    Uint8List seed,
  ) async {
    final envelope = _decodeJsonMap(inputJson.trim());
    if (envelope == null ||
        envelope['schema'] != schema ||
        envelope['version'] != encryptedVersion) {
      return _legacyContents(inputJson);
    }
    if (envelope['suite'] != encryptedSuite) return null;
    final kdf = _coerceJsonMap(envelope['kdf']);
    final cipherFields = _coerceJsonMap(envelope['cipher']);
    if (kdf?['name'] != 'hkdf-sha256' ||
        cipherFields?['name'] != 'aes-256-gcm') {
      return null;
    }
    try {
      final salt = base64Decode(kdf!['salt'] as String);
      final nonce = base64Decode(cipherFields!['nonce'] as String);
      final ciphertext = base64Decode(cipherFields['ciphertext'] as String);
      final tag = base64Decode(cipherFields['tag'] as String);
      if (salt.length != 32 || nonce.length != 12 || tag.length != 16) {
        return null;
      }
      final cleartext = await AesGcm.with256bits().decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: await _deriveKey(seed, salt),
        aad: _associatedData,
      );
      final decoded = utf8.decode(cleartext);
      final inner = _decodeJsonMap(decoded);
      if (inner?['schema'] != schema || inner?['version'] != version) {
        return null;
      }
      return _legacyContents(decoded);
    } on Object {
      return null;
    }
  }

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

  static List<int> get _associatedData =>
      utf8.encode('$schema|$encryptedVersion|$encryptedSuite');

  static Future<SecretKey> _deriveKey(Uint8List seed, List<int> salt) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(seed),
      nonce: salt,
      info: utf8.encode(_keyInfo),
    );
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static CapsuleBackupContents? _legacyContents(String inputJson) {
    final ledgerJson = tryExtractLedgerJson(inputJson);
    if (ledgerJson == null) return null;
    final envelope = _decodeJsonMap(inputJson.trim());
    final meta = _coerceJsonMap(envelope?['meta']);
    return CapsuleBackupContents(
      ledgerJson: ledgerJson,
      isGenesis:
          meta?['is_genesis'] is bool ? meta!['is_genesis'] as bool : null,
      isNeste: meta?['is_neste'] is bool ? meta!['is_neste'] as bool : null,
    );
  }
}
