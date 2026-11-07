import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:crypto/crypto.dart';

import '../ffi/capsule_address_runtime.dart';
import '../models/invitation.dart';
import '../models/relationship.dart';
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
      'nostr': {'npub': nostrNpub, 'hex': nostrHex},
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
          .convert(
            utf8.encode(
              '$_signatureDomain\n${_canonicalJson(_unsignedJson())}',
            ),
          )
          .bytes,
    );
  }

  static String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      final entries = keys
          .map((key) {
            return '${jsonEncode(key)}:${_canonicalJson(value[key])}';
          })
          .join(',');
      return '{$entries}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}

class CapsuleAddressService {
  static final Map<String, Future<void>> _cardOperations = {};
  final UserVisibleDataDirectoryService _dirs;
  final CapsuleAddressRuntime? _runtime;
  final AtomicFileWriteService _atomicWrites;

  const CapsuleAddressService({
    UserVisibleDataDirectoryService? dirs,
    CapsuleAddressRuntime? runtime,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _dirs = dirs ?? const UserVisibleDataDirectoryService(),
       _runtime = runtime,
       _atomicWrites = atomicWrites;

  /// One transient routing projection for Chat and pair attestations.
  /// Explicit trusted cards take precedence over relationship and invitation
  /// observations. Fallback evidence is never persisted as a trusted card.
  PeerIdentityIndex peerIdentityIndex({
    required Iterable<Relationship> relationships,
    required Iterable<Invitation> invitations,
    required Iterable<CapsuleAddressCard> cards,
  }) {
    final transportPeers = <String>{};
    final transportToRoot = <String, String>{};
    final rootToTransport = <String, String>{};
    String? hexKey(String value) {
      final bytes = _decodeHex32(value.trim().toLowerCase());
      return bytes == null ? null : _toHex(bytes);
    }

    String? base64Key(String value) {
      try {
        final bytes = base64.decode(value);
        return bytes.length == 32 ? _toHex(Uint8List.fromList(bytes)) : null;
      } catch (_) {
        return null;
      }
    }

    void remember(String? root, String? transport) {
      if (root == null || transport == null || root == transport) return;
      transportPeers.add(transport);
      transportToRoot.putIfAbsent(transport, () => root);
      rootToTransport.putIfAbsent(root, () => transport);
    }

    for (final card in cards) {
      remember(hexKey(card.rootHex), hexKey(card.nostrHex));
    }
    for (final relationship in relationships) {
      if (!relationship.isActive || relationship.hasPendingRemoteBreak) {
        continue;
      }
      final transport = base64Key(relationship.peerPubkey);
      final root = relationship.peerRootPubkey;
      if (root == null || root.isEmpty) {
        if (transport != null) transportPeers.add(transport);
      } else {
        remember(base64Key(root), transport);
      }
    }
    for (final invitation in invitations) {
      if (invitation.isIncoming) {
        remember(
          base64Key(invitation.fromRootPubkey ?? ''),
          base64Key(invitation.fromPubkey),
        );
      }
    }
    return PeerIdentityIndex(
      transportPeers: transportPeers,
      transportToRoot: transportToRoot,
      rootToTransport: rootToTransport,
    );
  }

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
    final signature = _runtime?.signRootDigest32(
      unsignedCard.signingDigest32(),
    );
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

  Future<List<CapsuleAddressCard>> listInvitationRecipients() async {
    final cards = await listTrustedCards();
    final ownRoot = _runtime?.capsuleRootPublicKey();
    if (ownRoot == null || ownRoot.length != 32) return cards;

    final ownRootHex = _toHex(ownRoot);
    return cards
        .where((card) => card.rootHex.toLowerCase() != ownRootHex)
        .toList(growable: false);
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
    if (_sameBytes(rootBytes, nostrBytes)) {
      throw const FormatException(
        'Contact card uses the capsule root as its delivery endpoint. Export and import a fresh card.',
      );
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

    await _withCards((cards) {
      cards[card.rootHex] = card.toJson();
    }, write: true);
  }

  /// Imports either the legacy shareable JSON card or the canonical QR
  /// envelope. Both paths converge on the same v1 JSON validator and store.
  Future<void> importCardPayload(String raw) {
    final payload = raw.trim();
    final json =
        payload.startsWith(CapsuleAddressCard.qrPayloadPrefix)
            ? CapsuleAddressCard.decodeQrPayload(payload)
            : payload;
    return importCardJson(json);
  }

  /// Imports a shareable card and returns the validated identity that callers
  /// should use. Invitation flows can therefore accept the card itself without
  /// asking the user to copy its root key separately.
  Future<CapsuleAddressCard> importAndReadCardPayload(String raw) async {
    final payload = raw.trim();
    final json =
        payload.startsWith(CapsuleAddressCard.qrPayloadPrefix)
            ? CapsuleAddressCard.decodeQrPayload(payload)
            : payload;
    await importCardJson(json);

    final decoded = _parseJsonMap(json);
    final card =
        decoded == null ? null : CapsuleAddressCard.fromJsonMap(decoded);
    if (card == null) {
      throw const FormatException('Invalid contact card');
    }
    return card;
  }

  Future<bool> upsertTrustedCardFromKeys({
    required Uint8List rootPubkey,
    required Uint8List nostrPubkey,
    String? signatureHex,
  }) async {
    if (rootPubkey.length != 32 || nostrPubkey.length != 32) {
      return false;
    }
    if (_sameBytes(rootPubkey, nostrPubkey)) {
      return false;
    }
    final rootBytes = Uint8List.fromList(rootPubkey);
    final nostrBytes = Uint8List.fromList(nostrPubkey);
    final normalizedSignature = signatureHex?.trim().toLowerCase();
    final signed =
        normalizedSignature != null && normalizedSignature.isNotEmpty;
    if (signed &&
        (normalizedSignature.length != 128 ||
            !RegExp(r'^[0-9a-f]+$').hasMatch(normalizedSignature))) {
      return false;
    }
    final unsignedCard = CapsuleAddressCard(
      version: signed ? 2 : 1,
      rootKey: HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      rootHex: _toHex(rootBytes),
      nostrNpub: _encodeBech32('npub', nostrBytes),
      nostrHex: _toHex(nostrBytes),
    );
    if (signed) {
      final signature = _decodeHex64(normalizedSignature);
      final verifier = _runtime;
      if (signature == null ||
          verifier == null ||
          !verifier.verifyRootDigest32(
            message32: unsignedCard.signingDigest32(),
            pubkey32: rootBytes,
            signature64: signature,
          )) {
        return false;
      }
    }
    final card = CapsuleAddressCard(
      version: unsignedCard.version,
      rootKey: unsignedCard.rootKey,
      rootHex: unsignedCard.rootHex,
      nostrNpub: unsignedCard.nostrNpub,
      nostrHex: unsignedCard.nostrHex,
      signatureHex: normalizedSignature,
    );

    return _withCards((cards) {
      final existing = _coerceJsonMap(cards[card.rootHex]);
      final previous =
          existing == null ? null : CapsuleAddressCard.fromJsonMap(existing);
      // Synchronizing the same local or accepted-invitation keys must not
      // discard an existing proof.
      if (!signed &&
          previous?.version == 2 &&
          previous?.nostrHex == card.nostrHex) {
        return true;
      }
      cards[card.rootHex] = card.toJson();
      return true;
    }, write: true);
  }

  Future<bool> removeTrustedCard(String rootKey) async {
    final rootBytes = decodeRootKey(rootKey);
    if (rootBytes == null) return false;
    return _withCards(
      (cards) => cards.remove(_toHex(rootBytes)) != null,
      write: true,
    );
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
    final endpoint = _decodeHex32(card.nostrHex);
    if (endpoint == null || _sameBytes(rootBytes, endpoint)) return null;
    return endpoint;
  }

  Future<bool> hasKnownNostrEndpoint(String rootKey) async {
    return await resolveNostrRecipient(rootKey) != null;
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

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Uint8List? _decodeHex32(String input) {
    try {
      final clean = input
          .replaceAll(':', '')
          .replaceAll(' ', '')
          .replaceAll('-', '');
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
      final clean = input
          .replaceAll(':', '')
          .replaceAll(' ', '')
          .replaceAll('-', '');
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

  static List<int>? _convertBits(
    List<int> data,
    int fromBits,
    int toBits,
    bool pad,
  ) {
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
    return File('${root.path}/capsule_contact_cards.json');
  }

  Future<Map<String, dynamic>> _readCards() => _withCards((cards) => cards);

  /// Every read/modify/write uses this queue, shared by instances for the same
  /// file in this isolate. Atomic replacement alone does not protect a stale
  /// read from a concurrent import or Capsule cleanup.
  Future<T> _withCards<T>(
    T Function(Map<String, dynamic> cards) action, {
    bool write = false,
  }) async {
    final file = await _cardsFile();
    final path = file.absolute.path;
    final previous = _cardOperations[path] ?? Future<void>.value();
    final operation = previous.then((_) async {
      final cards =
          await file.exists()
              ? _parseJsonMap(await file.readAsString()) ?? <String, dynamic>{}
              : <String, dynamic>{};
      final before = write ? jsonEncode(cards) : null;
      final result = action(cards);
      if (write && before != jsonEncode(cards)) {
        await _atomicWrites.writeString(
          file,
          const JsonEncoder.withIndent('  ').convert(cards),
        );
      }
      return result;
    });
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _cardOperations[path] = tail;
    return operation.whenComplete(() {
      if (identical(_cardOperations[path], tail)) _cardOperations.remove(path);
    });
  }

  Future<void> removeCapsuleReferences(String capsuleHex) {
    return _withCards((cards) {
      cards.removeWhere(
        (key, value) => shouldRemoveCapsuleContactCardEntry(
          entryKey: key,
          entryValue: value,
          deleteKeyHex: capsuleHex,
        ),
      );
    }, write: true);
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

class PeerIdentityIndex {
  final Set<String> _transportPeers;
  final Map<String, String> _transportToRoot;
  final Map<String, String> _rootToTransport;

  const PeerIdentityIndex({
    required Set<String> transportPeers,
    required Map<String, String> transportToRoot,
    required Map<String, String> rootToTransport,
  }) : _transportPeers = transportPeers,
       _transportToRoot = transportToRoot,
       _rootToTransport = rootToTransport;

  String? resolveTransportForSend(String peerHex) {
    final normalized = peerHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return null;
    final mappedTransport = _rootToTransport[normalized];
    if (mappedTransport != null) return mappedTransport;
    if (_transportPeers.contains(normalized)) return normalized;
    return null;
  }

  String resolveConsensusForIncoming(String transportPeerHex) {
    final normalized = transportPeerHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return normalized;
    return _transportToRoot[normalized] ?? normalized;
  }

  static bool _isHex64(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

bool shouldRemoveCapsuleContactCardEntry({
  required String entryKey,
  required Object? entryValue,
  required String deleteKeyHex,
}) {
  final normalizedDeleteKey = _normalizeHex32ForCleanup(deleteKeyHex);
  if (normalizedDeleteKey == null) return false;

  final normalizedEntryKey = _normalizeHex32ForCleanup(entryKey);
  if (normalizedEntryKey == normalizedDeleteKey) return true;
  final entryRootKeyHex = _decodeBech32Hex32ForCleanup(
    entryKey,
    expectedHrp: 'h',
  );
  if (entryRootKeyHex == normalizedDeleteKey) return true;
  final entryNpubHex = _decodeBech32Hex32ForCleanup(
    entryKey,
    expectedHrp: 'npub',
  );
  if (entryNpubHex == normalizedDeleteKey) return true;

  if (entryValue is! Map) return false;
  final map = Map<String, dynamic>.from(entryValue);

  final rootHex = _normalizeHex32ForCleanup(map['rootHex']?.toString());
  if (rootHex == normalizedDeleteKey) return true;
  final rootKeyHex = _decodeBech32Hex32ForCleanup(
    map['rootKey']?.toString(),
    expectedHrp: 'h',
  );
  if (rootKeyHex == normalizedDeleteKey) return true;

  final transports = map['transports'];
  if (transports is! Map) return false;
  final nostr = transports['nostr'];
  if (nostr is! Map) return false;
  final nostrMap = Map<String, dynamic>.from(nostr);
  final nostrHex = _normalizeHex32ForCleanup(nostrMap['hex']?.toString());
  if (nostrHex == normalizedDeleteKey) return true;
  final nostrNpubHex = _decodeBech32Hex32ForCleanup(
    nostrMap['npub']?.toString(),
    expectedHrp: 'npub',
  );
  if (nostrNpubHex == normalizedDeleteKey) return true;
  return false;
}

String? _decodeBech32Hex32ForCleanup(
  String? value, {
  required String expectedHrp,
}) {
  if (value == null) return null;
  final input = value.trim();
  if (input.isEmpty) return null;
  try {
    final decoded = bech32.decode(input);
    if (decoded.hrp != expectedHrp) return null;
    final bytes = CapsuleAddressService._convertBits(decoded.data, 5, 8, false);
    if (bytes == null || bytes.length != 32) return null;
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  } catch (_) {
    return null;
  }
}

String? _normalizeHex32ForCleanup(String? value) {
  if (value == null) return null;
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(':', '')
      .replaceAll('-', '')
      .replaceAll(' ', '');
  final hex32 = RegExp(r'^[0-9a-f]{64}$');
  if (!hex32.hasMatch(normalized)) return null;
  return normalized;
}
