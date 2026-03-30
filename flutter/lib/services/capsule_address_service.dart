import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';

import '../ffi/hivra_bindings.dart';
import '../utils/hivra_id_format.dart';
import 'user_visible_data_directory_service.dart';

class CapsuleAddressCard {
  final String rootKey;
  final String rootHex;
  final String nostrNpub;
  final String nostrHex;

  const CapsuleAddressCard({
    required this.rootKey,
    required this.rootHex,
    required this.nostrNpub,
    required this.nostrHex,
  });

  Map<String, dynamic> toJson() => {
        'version': 1,
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
    final rootKey = map['rootKey']?.toString();
    final rootHex = map['rootHex']?.toString();
    final transports = map['transports'];
    if (rootKey == null || rootHex == null || transports is! Map) return null;

    final nostr = transports['nostr'];
    if (nostr is! Map) return null;
    final nostrNpub = nostr['npub']?.toString();
    final nostrHex = nostr['hex']?.toString();
    if (nostrNpub == null || nostrHex == null) return null;

    return CapsuleAddressCard(
      rootKey: rootKey,
      rootHex: rootHex,
      nostrNpub: nostrNpub,
      nostrHex: nostrHex,
    );
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class CapsuleAddressService {
  final UserVisibleDataDirectoryService _dirs;

  const CapsuleAddressService({
    UserVisibleDataDirectoryService? dirs,
  }) : _dirs = dirs ?? const UserVisibleDataDirectoryService();

  Future<CapsuleAddressCard?> buildOwnCard(HivraBindings hivra) async {
    final root = hivra.capsuleRootPublicKey();
    final nostr = hivra.capsuleNostrPublicKey();
    if (root == null ||
        root.length != 32 ||
        nostr == null ||
        nostr.length != 32) {
      return null;
    }

    final rootBytes = Uint8List.fromList(root);
    final nostrBytes = Uint8List.fromList(nostr);
    return CapsuleAddressCard(
      rootKey: HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      rootHex: _toHex(rootBytes),
      nostrNpub: _encodeBech32('npub', nostrBytes),
      nostrHex: _toHex(nostrBytes),
    );
  }

  Future<String?> exportOwnCardJson(HivraBindings hivra) async {
    final card = await buildOwnCard(hivra);
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
    if (version != 1) {
      throw const FormatException('Unsupported contact card version');
    }
    final card = CapsuleAddressCard.fromJsonMap(decoded);
    if (card == null) {
      throw const FormatException('Invalid contact card');
    }
    if (decodeRootKey(card.rootKey) == null) {
      throw const FormatException('Invalid root capsule key');
    }
    if (decodeDirectNostrRecipient(card.nostrNpub) == null ||
        _decodeHex32(card.nostrHex) == null) {
      throw const FormatException('Invalid Nostr transport endpoint');
    }

    final cards = await _readCards();
    cards[card.rootHex] = card.toJson();
    await _writeCards(cards);
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
      await file.writeAsString('{}');
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
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(cards));
  }

  Map<String, dynamic>? _parseJsonMap(String rawJson) {
    final decoded = jsonDecode(rawJson);
    return _coerceJsonMap(decoded);
  }

  Map<String, dynamic>? _coerceJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
