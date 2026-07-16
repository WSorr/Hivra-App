import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:crypto/crypto.dart';

import '../ffi/capsule_address_runtime.dart';
import '../utils/hivra_id_format.dart';
import 'atomic_file_write_service.dart';
import 'user_visible_data_directory_service.dart';

class CapsuleAddressCard {
  static const qrPayloadPrefix = 'hivra:card:v1:';
  static const _maxQrPayloadLength = 4096;
  static const signatureAlgorithm = 'ed25519-sha256-root-v1';
  static const _signatureDomain = 'hivra.contact_card.v2';

  final int version;
  final String rootKey;
  final String rootHex;
  final String nostrNpub;
  final String nostrHex;
  final String? signatureHex;

  const CapsuleAddressCard({
    this.version = 1,
    required this.rootKey,
    required this.rootHex,
    required this.nostrNpub,
    required this.nostrHex,
    this.signatureHex,
  });

  Map<String, dynamic> toJson() {
    final body = _unsignedJson();
    if (version >= 2 && signatureHex != null) {
      body['proof'] = {
        'algorithm': signatureAlgorithm,
        'signatureHex': signatureHex,
      };
    }
    return body;
  }

  Map<String, dynamic> _unsignedJson() => {
        'version': version,
        'rootKey': rootKey,
        'rootHex': rootHex,
        'transports': {
          'nostr': {
            'npub': nostrNpub,
            'hex': nostrHex,
          },
        },
      };

  static CapsuleAddressCard? fromJsonMap(Map<String, dynamic> map) {
    final version = map['version'];
    if (version is! int) return null;
    final rootKey = map['rootKey']?.toString();
    final rootHex = map['rootHex']?.toString();
    final transports = map['transports'];
    if (rootKey == null || rootHex == null || transports is! Map) return null;

    final nostr = transports['nostr'];
    if (nostr is! Map) return null;
    final nostrNpub = nostr['npub']?.toString();
    final nostrHex = nostr['hex']?.toString();
    if (nostrNpub == null || nostrHex == null) return null;

    String? signatureHex;
    if (version >= 2) {
      final proof = map['proof'];
      if (proof is! Map) return null;
      final algorithm = proof['algorithm']?.toString();
      if (algorithm != signatureAlgorithm) return null;
      signatureHex = proof['signatureHex']?.toString().trim().toLowerCase();
      if (signatureHex == null ||
          signatureHex.length != 128 ||
          !RegExp(r'^[0-9a-f]+$').hasMatch(signatureHex)) {
        return null;
      }
    }

    return CapsuleAddressCard(
      version: version,
      rootKey: rootKey,
      rootHex: rootHex,
      nostrNpub: nostrNpub,
      nostrHex: nostrHex,
      signatureHex: signatureHex,
    );
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// A QR envelope carries the same public v1 card as clipboard JSON.
  /// The prefix makes scanner input unambiguous without creating a second card
  /// schema or exposing any private capsule material.
  String toQrPayload() =>
      '$qrPayloadPrefix${base64Url.encode(utf8.encode(jsonEncode(toJson())))}';

  static String decodeQrPayload(String raw) {
    final payload = raw.trim();
    if (!payload.startsWith(qrPayloadPrefix)) {
      throw const FormatException('Unsupported capsule card QR code');
    }
    if (payload.length > _maxQrPayloadLength) {
      throw const FormatException('Capsule card QR code is too large');
    }

    final encoded = payload.substring(qrPayloadPrefix.length);
    if (encoded.isEmpty) {
      throw const FormatException('Capsule card QR code is empty');
    }

    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } on FormatException {
      throw const FormatException('Capsule card QR code is malformed');
    }
  }

  Uint8List signingDigest32() {
    return Uint8List.fromList(
      sha256
          .convert(utf8.encode('$_signatureDomain\n${_canonicalJson(_unsignedJson())}'))
          .bytes,
    );
  }

  static String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      final entries = keys.map((key) {
        return '${jsonEncode(key)}:${_canonicalJson(value[key])}';
      }).join(',');
      return '{$entries}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}

class CapsuleAddressService {
  final UserVisibleDataDirectoryService _dirs;
  final CapsuleAddressRuntime? _runtime;
  final AtomicFileWriteService _atomicWrites;

  const CapsuleAddressService({
    UserVisibleDataDirectoryService? dirs,
    CapsuleAddressRuntime? runtime,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  })  : _dirs = dirs ?? const UserVisibleDataDirectoryService(),
        _runtime = runtime,
        _atomicWrites = atomicWrites;

  Future<CapsuleAddressCard?> buildOwnCard() async {
    final root = _runtime?.capsuleRootPublicKey();
    final nostr = _runtime?.capsuleNostrPublicKey();
    if (root == null ||
        root.length != 32 ||
        nostr == null ||
        nostr.length != 32) {
      return null;
    }

    final rootBytes = Uint8List.fromList(root);
    final nostrBytes = Uint8List.fromList(nostr);
    final unsignedCard = CapsuleAddressCard(
      version: 2,
      rootKey: HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      rootHex: _toHex(rootBytes),
      nostrNpub: _encodeBech32('npub', nostrBytes),
      nostrHex: _toHex(nostrBytes),
    );
    final signature = _runtime?.signRootDigest32(unsignedCard.signingDigest32());
    if (signature == null || signature.length != 64) {
      return CapsuleAddressCard(
        rootKey: unsignedCard.rootKey,
        rootHex: unsignedCard.rootHex,
        nostrNpub: unsignedCard.nostrNpub,
        nostrHex: unsignedCard.nostrHex,
      );
    }
    return CapsuleAddressCard(
      version: 2,
      rootKey: unsignedCard.rootKey,
      rootHex: unsignedCard.rootHex,
      nostrNpub: unsignedCard.nostrNpub,
      nostrHex: unsignedCard.nostrHex,
      signatureHex: _toHex(signature),
    );
  }

  Future<String?> exportOwnCardJson() async {
    final card = await buildOwnCard();
    return card?.toPrettyJson();
  }

  Future<int> contactCount() async {
    final cards = await _readCards();
    return cards.length;
  }

  Future<List<CapsuleAddressCard>> listTrustedCards() async {
    final cards = await _readCards();
    final result = <CapsuleAddressCard>[];
    for (final entry in cards.values) {
      final entryMap = _coerceJsonMap(entry);
      if (entryMap == null) continue;
      final card = CapsuleAddressCard.fromJsonMap(entryMap);
      if (card != null) {
        result.add(card);
      }
    }
    result.sort((a, b) => a.rootKey.compareTo(b.rootKey));
    return result;
  }

  Future<void> importCardJson(String raw) async {
    final decoded = _parseJsonMap(raw);
    if (decoded == null) {
      throw const FormatException('Contact card must be a JSON object');
    }
    final version = decoded['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported contact card version');
    }
    final card = CapsuleAddressCard.fromJsonMap(decoded);
    if (card == null) {
      throw const FormatException('Invalid contact card');
    }
    final rootBytes = decodeRootKey(card.rootKey);
    final rootHexBytes = _decodeHex32(card.rootHex);
    if (rootBytes == null || rootHexBytes == null) {
      throw const FormatException('Invalid root capsule key');
    }
    if (_toHex(rootBytes) != _toHex(rootHexBytes)) {
      throw const FormatException('Contact card root key mismatch');
    }

    final nostrBytes = decodeDirectNostrRecipient(card.nostrNpub);
    final nostrHexBytes = _decodeHex32(card.nostrHex);
    if (nostrBytes == null || nostrHexBytes == null) {
      throw const FormatException('Invalid Nostr transport endpoint');
    }
    if (_toHex(nostrBytes) != _toHex(nostrHexBytes)) {
      throw const FormatException('Contact card Nostr endpoint mismatch');
    }
    if (card.version >= 2) {
      final signatureBytes = _decodeHex64(card.signatureHex ?? '');
      if (signatureBytes == null) {
        throw const FormatException('Invalid contact card signature');
      }
      final verifier = _runtime;
      if (verifier == null ||
          !verifier.verifyRootDigest32(
            message32: card.signingDigest32(),
            pubkey32: rootBytes,
            signature64: signatureBytes,
          )) {
        throw const FormatException('Contact card signature mismatch');
      }
    }

    final cards = await _readCards();
    cards[card.rootHex] = card.toJson();
    await _writeCards(cards);
  }

  /// Imports either the legacy shareable JSON card or the canonical QR
  /// envelope. Both paths converge on the same v1 JSON validator and store.
  Future<void> importCardPayload(String raw) {
    final payload = raw.trim();
    final json = payload.startsWith(CapsuleAddressCard.qrPayloadPrefix)
        ? CapsuleAddressCard.decodeQrPayload(payload)
        : payload;
    return importCardJson(json);
  }

  Future<bool> upsertTrustedCardFromKeys({
    required Uint8List rootPubkey,
    required Uint8List nostrPubkey,
  }) async {
    if (rootPubkey.length != 32 || nostrPubkey.length != 32) {
      return false;
    }
    final rootBytes = Uint8List.fromList(rootPubkey);
    final nostrBytes = Uint8List.fromList(nostrPubkey);
    final card = CapsuleAddressCard(
      rootKey: HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      rootHex: _toHex(rootBytes),
      nostrNpub: _encodeBech32('npub', nostrBytes),
      nostrHex: _toHex(nostrBytes),
    );

    final cards = await _readCards();
    cards[card.rootHex] = card.toJson();
    await _writeCards(cards);
    return true;
  }

  Future<bool> removeTrustedCard(String rootKey) async {
    final rootBytes = decodeRootKey(rootKey);
    if (rootBytes == null) return false;
    final cards = await _readCards();
    final removed = cards.remove(_toHex(rootBytes)) != null;
    if (removed) {
      await _writeCards(cards);
    }
    return removed;
  }

  Future<Uint8List?> resolveTransportEndpoint(
    String rootOrDirectValue, {
    required String transport,
  }) async {
    switch (transport) {
      case 'nostr':
        return resolveNostrRecipient(rootOrDirectValue);
      default:
        return null;
    }
  }

  Future<Uint8List?> resolveNostrRecipient(String input) async {
    final value = input.trim();
    if (value.isEmpty) return null;

    final direct = decodeDirectNostrRecipient(value);
    if (direct != null) return direct;

    final rootBytes = decodeRootKey(value);
    if (rootBytes == null) return null;
    final cards = await _readCards();
    final cardMap = _coerceJsonMap(cards[_toHex(rootBytes)]);
    if (cardMap == null) return null;
    final card = CapsuleAddressCard.fromJsonMap(cardMap);
    if (card == null) return null;
    return _decodeHex32(card.nostrHex);
  }

  Future<bool> hasKnownNostrEndpoint(String rootKey) async {
    final rootBytes = decodeRootKey(rootKey);
    if (rootBytes == null) return false;
    final cards = await _readCards();
    return cards.containsKey(_toHex(rootBytes));
  }

  Uint8List? decodeDirectNostrRecipient(String input) {
    final value = input.trim();

    if (value.startsWith('npub1')) {
      try {
        final decoded = bech32.decode(value);
        if (decoded.hrp == 'npub') {
          final data = _convertBits(decoded.data, 5, 8, false);
          if (data != null && data.length == 32) {
            return Uint8List.fromList(data);
          }
        }
      } catch (_) {}
    }

    final hex = _decodeHex32(value);
    if (hex != null) return hex;

    try {
      final bytes = base64.decode(value);
      if (bytes.length == 32) {
        return Uint8List.fromList(bytes);
      }
    } catch (_) {}

    return null;
  }

  Uint8List? decodeRootKey(String input) {
    final value = input.trim();
    if (!value.startsWith('h1')) return null;
    try {
      final decoded = bech32.decode(value);
      if (decoded.hrp != 'h') return null;
      final data = _convertBits(decoded.data, 5, 8, false);
      if (data == null || data.length != 32) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeHex32(String input) {
    try {
      final clean =
          input.replaceAll(':', '').replaceAll(' ', '').replaceAll('-', '');
      if (clean.length != 64) return null;
      final bytes = <int>[];
      for (var i = 0; i < clean.length; i += 2) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeHex64(String input) {
    try {
      final clean =
          input.replaceAll(':', '').replaceAll(' ', '').replaceAll('-', '');
      if (clean.length != 128) return null;
      final bytes = <int>[];
      for (var i = 0; i < clean.length; i += 2) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  String _encodeBech32(String hrp, Uint8List bytes) {
    final words = _convertBits(bytes, 8, 5, true);
    if (words == null) {
      throw ArgumentError('Invalid bytes for bech32 encoding');
    }
    return bech32.encode(Bech32(hrp, words));
  }

  String _toHex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  List<int>? _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) return null;
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      return null;
    }

    return result;
  }

  Future<File> _cardsFile() async {
    final root = await _dirs.rootDirectory(create: true);
    final file = File('${root.path}/capsule_contact_cards.json');
    if (!await file.exists()) {
      await _atomicWrites.writeString(file, '{}');
    }
    return file;
  }

  Future<Map<String, dynamic>> _readCards() async {
    final file = await _cardsFile();
    final raw = await file.readAsString();
    return _parseJsonMap(raw) ?? <String, dynamic>{};
  }

  Future<void> _writeCards(Map<String, dynamic> cards) async {
    final file = await _cardsFile();
    await _atomicWrites.writeString(
      file,
      const JsonEncoder.withIndent('  ').convert(cards),
    );
  }

  Map<String, dynamic>? _parseJsonMap(String rawJson) {
    final decoded = jsonDecode(_normalizePastedJson(rawJson));
    return _coerceJsonMap(decoded);
  }

  String _normalizePastedJson(String rawJson) {
    return rawJson
        .replaceAll('\uFEFF', '')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u2007', ' ')
        .replaceAll('\u202F', ' ');
  }

  Map<String, dynamic>? _coerceJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
