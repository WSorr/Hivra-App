import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cryptography;

import '../models/capsule_chat_models.dart';
import 'capsule_file_store.dart';
import 'capsule_seed_store.dart';

typedef ChatTimelineSeedLoader =
    Future<Uint8List?> Function(String capsuleRootHex);

class CapsuleDeliveryInboxStore {
  static final CapsuleDeliveryInboxStore shared = CapsuleDeliveryInboxStore();

  static const int defaultMaxCapsules = 8;
  static const int defaultMaxRecordsPerCapsule = 256;
  static const String _timelineSchema = 'hivra.chat_timeline';
  static const int _timelineVersion = 1;
  static const String _timelineSuite = 'hkdf-sha256+a256gcm';
  static const String _timelineKeyInfo = 'hivra.chat_timeline.v1';

  final int maxCapsules;
  final int maxRecordsPerCapsule;
  final CapsuleFileStore _fileStore;
  final ChatTimelineSeedLoader _loadTimelineSeed;

  final Map<String, Map<String, CapsuleChatInboxMessage>> _messagesByCapsule =
      <String, Map<String, CapsuleChatInboxMessage>>{};

  final Map<String, Map<String, CapsuleTradeSignalInboxMessage>>
  _signalsByCapsule = <String, Map<String, CapsuleTradeSignalInboxMessage>>{};
  final List<String> _capsuleOrder = <String>[];
  final Set<String> _hydratedCapsules = <String>{};
  final Map<String, Future<void>> _timelineWriteTails =
      <String, Future<void>>{};
  final Map<String, Future<void>> _readStateWriteTails =
      <String, Future<void>>{};

  CapsuleDeliveryInboxStore({
    this.maxCapsules = defaultMaxCapsules,
    this.maxRecordsPerCapsule = defaultMaxRecordsPerCapsule,
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    ChatTimelineSeedLoader? loadTimelineSeed,
  }) : assert(maxCapsules > 0),
       assert(maxRecordsPerCapsule > 0),
       _fileStore = fileStore,
       _loadTimelineSeed = loadTimelineSeed ?? CapsuleSeedStore().loadSeed;

  List<CapsuleChatInboxMessage> loadMessages(String capsuleRootHex) {
    final normalized = capsuleRootHex.trim().toLowerCase();
    final messages =
        _messagesByCapsule[normalized]?.values.toList() ??
        <CapsuleChatInboxMessage>[];
    messages.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return List<CapsuleChatInboxMessage>.unmodifiable(messages);
  }

  Future<bool> hydrateCapsule(String capsuleRootHex) async {
    final normalized = capsuleRootHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return false;
    if (_hydratedCapsules.contains(normalized)) return true;
    try {
      final capsuleDir = await _fileStore.capsuleDirForHex(normalized);
      final raw = await _fileStore.readChatTimeline(capsuleDir);
      if (raw == null) {
        _hydratedCapsules.add(normalized);
        return true;
      }
      final cleartext = await _openTimeline(normalized, raw);
      if (cleartext == null) return false;
      final decoded = jsonDecode(cleartext);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['capsule_root_hex'] != normalized ||
          decoded['messages'] is! List) {
        return false;
      }
      final loaded = <String, CapsuleChatInboxMessage>{};
      for (final item in decoded['messages'] as List) {
        final message = _decodeTimelineMessage(item, normalized);
        if (message == null) return false;
        loaded[message.id] = message;
      }
      _hydratedCapsules.add(normalized);
      final existing = _messagesByCapsule[normalized];
      if (existing != null) loaded.addAll(existing);
      if (loaded.isEmpty) return true;
      _messagesByCapsule[normalized] = loaded;
      _touchCapsule(normalized);
      _retainNewestMessages(loaded);
      _retainNewestCapsules();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> mergeDurably(
    String capsuleRootHex, {
    required Iterable<CapsuleChatInboxMessage> messages,
    required Iterable<CapsuleTradeSignalInboxMessage> tradeSignals,
  }) async {
    final normalized = capsuleRootHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return;
    final incomingMessages = messages.toList(growable: false);
    if (incomingMessages.isEmpty) {
      merge(normalized, messages: incomingMessages, tradeSignals: tradeSignals);
      return;
    }
    if (!await hydrateCapsule(normalized)) {
      throw StateError('Existing Chat timeline is unavailable or invalid');
    }
    merge(normalized, messages: incomingMessages, tradeSignals: tradeSignals);
    if (incomingMessages.isNotEmpty) await _persistTimeline(normalized);
  }

  Future<void> upsertMessageDurably(
    String capsuleRootHex,
    CapsuleChatInboxMessage message,
  ) async {
    final normalized = capsuleRootHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return;
    if (!await hydrateCapsule(normalized)) {
      throw StateError('Existing Chat timeline is unavailable or invalid');
    }
    merge(
      normalized,
      messages: <CapsuleChatInboxMessage>[message],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );
    await _persistTimeline(normalized);
  }

  List<CapsuleTradeSignalInboxMessage> loadTradeSignals(String capsuleRootHex) {
    final normalized = capsuleRootHex.trim().toLowerCase();
    final signals =
        _signalsByCapsule[normalized]?.values.toList() ??
        <CapsuleTradeSignalInboxMessage>[];
    signals.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return List<CapsuleTradeSignalInboxMessage>.unmodifiable(signals);
  }

  void merge(
    String capsuleRootHex, {
    required Iterable<CapsuleChatInboxMessage> messages,
    required Iterable<CapsuleTradeSignalInboxMessage> tradeSignals,
  }) {
    final normalized = capsuleRootHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return;
    final incomingMessages = messages.toList(growable: false);
    final incomingSignals = tradeSignals.toList(growable: false);
    if (incomingMessages.isEmpty && incomingSignals.isEmpty) return;

    _touchCapsule(normalized);
    if (incomingMessages.isNotEmpty) {
      final messagesById = _messagesByCapsule.putIfAbsent(
        normalized,
        () => <String, CapsuleChatInboxMessage>{},
      );
      for (final message in incomingMessages) {
        final existing = messagesById[message.id];
        if (existing == null || _sameMessageSemantics(existing, message)) {
          messagesById[message.id] = message;
        }
      }
      _retainNewestMessages(messagesById);
    }
    if (incomingSignals.isNotEmpty) {
      final signalsById = _signalsByCapsule.putIfAbsent(
        normalized,
        () => <String, CapsuleTradeSignalInboxMessage>{},
      );
      for (final signal in incomingSignals) {
        signalsById[signal.id] = signal;
      }
      _retainNewestSignals(signalsById);
    }
    _retainNewestCapsules();
  }

  void clearCapsule(String capsuleRootHex) {
    final normalized = capsuleRootHex.trim().toLowerCase();
    _messagesByCapsule.remove(normalized);
    _signalsByCapsule.remove(normalized);
    _capsuleOrder.remove(normalized);
    _hydratedCapsules.remove(normalized);
    _timelineWriteTails.remove(normalized);
    _readStateWriteTails.remove(normalized);
  }

  Future<int> unreadMessageCount(String capsuleRootHex) async {
    final normalized = capsuleRootHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return 0;
    await hydrateCapsule(normalized);
    final retainedIds = loadMessages(normalized)
        .where(
          (message) =>
              message.direction == CapsuleChatMessageDirection.incoming,
        )
        .map((message) => message.id);
    final readIds = await _loadReadMessageIds(normalized);
    return retainedIds.where((id) => !readIds.contains(id)).length;
  }

  Future<void> markMessagesRead(
    String capsuleRootHex,
    Iterable<String> messageIds,
  ) async {
    final normalized = capsuleRootHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return;
    await hydrateCapsule(normalized);
    final ids = messageIds.toList(growable: false);
    final previous = _readStateWriteTails[normalized] ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => _markMessagesReadNow(normalized, ids));
    _readStateWriteTails[normalized] = next;
    try {
      await next;
    } finally {
      if (identical(_readStateWriteTails[normalized], next)) {
        _readStateWriteTails.remove(normalized);
      }
    }
  }

  Future<void> _markMessagesReadNow(
    String capsuleRootHex,
    Iterable<String> messageIds,
  ) async {
    final retainedIds = loadMessages(capsuleRootHex)
        .where(
          (message) =>
              message.direction == CapsuleChatMessageDirection.incoming,
        )
        .map((message) => message.id);
    final retainedSet = retainedIds.toSet();
    final nextReadIds = await _loadReadMessageIds(capsuleRootHex);
    nextReadIds.addAll(
      messageIds.map((id) => id.trim()).where(retainedSet.contains),
    );
    nextReadIds.removeWhere((id) => !retainedSet.contains(id));
    final bounded = nextReadIds.toList()..sort();
    if (bounded.length > maxRecordsPerCapsule) {
      bounded.removeRange(0, bounded.length - maxRecordsPerCapsule);
    }
    final capsuleDir = await _fileStore.capsuleDirForHex(
      capsuleRootHex,
      create: true,
    );
    await _fileStore.writeChatReadState(
      capsuleDir,
      jsonEncode(<String, Object?>{
        'version': 1,
        'capsule_root_hex': capsuleRootHex,
        'read_message_ids': bounded,
      }),
    );
  }

  Future<Set<String>> _loadReadMessageIds(String capsuleRootHex) async {
    try {
      final capsuleDir = await _fileStore.capsuleDirForHex(capsuleRootHex);
      final raw = await _fileStore.readChatReadState(capsuleDir);
      if (raw == null) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['capsule_root_hex'] != capsuleRootHex ||
          decoded['read_message_ids'] is! List) {
        return <String>{};
      }
      final ids = decoded['read_message_ids'] as List;
      if (ids.any((id) => id is! String || id.trim().isEmpty)) {
        return <String>{};
      }
      return ids.cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _persistTimeline(String capsuleRootHex) async {
    final previous =
        _timelineWriteTails[capsuleRootHex] ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => _persistTimelineNow(capsuleRootHex));
    _timelineWriteTails[capsuleRootHex] = next;
    try {
      await next;
    } finally {
      if (identical(_timelineWriteTails[capsuleRootHex], next)) {
        _timelineWriteTails.remove(capsuleRootHex);
      }
    }
  }

  Future<void> _persistTimelineNow(String capsuleRootHex) async {
    final messages = loadMessages(capsuleRootHex);
    final capsuleDir = await _fileStore.capsuleDirForHex(
      capsuleRootHex,
      create: true,
    );
    final cleartext = jsonEncode(<String, Object?>{
      'version': 1,
      'capsule_root_hex': capsuleRootHex,
      'messages': messages
          .map(
            (message) => <String, Object?>{
              'id': message.id,
              'from_hex': message.fromHex,
              if (message.toHex != null) 'to_hex': message.toHex,
              'message_text': message.messageText,
              'created_at_utc': message.createdAtUtc,
              'envelope_hash_hex': message.envelopeHashHex,
              'timestamp_ms': message.timestampMs,
              'direction': message.direction.name,
              'delivery_state': message.deliveryState.name,
            },
          )
          .toList(growable: false),
    });
    await _fileStore.writeChatTimeline(
      capsuleDir,
      await _sealTimeline(capsuleRootHex, cleartext),
    );
  }

  Future<String> _sealTimeline(String capsuleRootHex, String cleartext) async {
    final seed = await _loadTimelineSeed(capsuleRootHex);
    if (seed == null || seed.isEmpty) {
      throw StateError('Capsule seed is unavailable for Chat timeline');
    }
    final salt = _randomBytes(32);
    final cipher = cryptography.AesGcm.with256bits();
    final nonce = cipher.newNonce();
    final secretBox = await cipher.encrypt(
      utf8.encode(cleartext),
      secretKey: await _deriveTimelineKey(seed, salt),
      nonce: nonce,
      aad: _timelineAssociatedData(capsuleRootHex),
    );
    return jsonEncode(<String, Object?>{
      'schema': _timelineSchema,
      'version': _timelineVersion,
      'suite': _timelineSuite,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'tag': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<String?> _openTimeline(
    String capsuleRootHex,
    String sealedJson,
  ) async {
    try {
      final decoded = jsonDecode(sealedJson);
      if (decoded is! Map ||
          decoded['schema'] != _timelineSchema ||
          decoded['version'] != _timelineVersion ||
          decoded['suite'] != _timelineSuite) {
        return null;
      }
      final salt = base64Decode(decoded['salt']?.toString() ?? '');
      final nonce = base64Decode(decoded['nonce']?.toString() ?? '');
      final ciphertext = base64Decode(decoded['ciphertext']?.toString() ?? '');
      final tag = base64Decode(decoded['tag']?.toString() ?? '');
      final seed = await _loadTimelineSeed(capsuleRootHex);
      if (seed == null ||
          seed.isEmpty ||
          salt.length != 32 ||
          nonce.length != 12 ||
          tag.length != 16) {
        return null;
      }
      final cleartext = await cryptography.AesGcm.with256bits().decrypt(
        cryptography.SecretBox(
          ciphertext,
          nonce: nonce,
          mac: cryptography.Mac(tag),
        ),
        secretKey: await _deriveTimelineKey(seed, salt),
        aad: _timelineAssociatedData(capsuleRootHex),
      );
      return utf8.decode(cleartext);
    } catch (_) {
      return null;
    }
  }

  Future<cryptography.SecretKey> _deriveTimelineKey(
    Uint8List seed,
    List<int> salt,
  ) {
    return cryptography.Hkdf(
      hmac: cryptography.Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: cryptography.SecretKey(seed),
      nonce: salt,
      info: utf8.encode(_timelineKeyInfo),
    );
  }

  List<int> _timelineAssociatedData(String capsuleRootHex) => utf8.encode(
    '$_timelineSchema|$_timelineVersion|$_timelineSuite|$capsuleRootHex',
  );

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  CapsuleChatInboxMessage? _decodeTimelineMessage(
    Object? raw,
    String capsuleRootHex,
  ) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final id = map['id']?.toString() ?? '';
    final fromHex = map['from_hex']?.toString() ?? '';
    final toHex = map['to_hex']?.toString();
    final messageText = map['message_text']?.toString() ?? '';
    final createdAtUtc = map['created_at_utc']?.toString() ?? '';
    final envelopeHashHex = map['envelope_hash_hex']?.toString() ?? '';
    final timestampMs = map['timestamp_ms'];
    final direction =
        CapsuleChatMessageDirection.values
            .where((value) => value.name == map['direction'])
            .firstOrNull;
    final deliveryState =
        CapsuleChatMessageDeliveryState.values
            .where((value) => value.name == map['delivery_state'])
            .firstOrNull;
    if (id.isEmpty ||
        !_isHex64(fromHex) ||
        (toHex != null && !_isHex64(toHex)) ||
        messageText.isEmpty ||
        createdAtUtc.isEmpty ||
        timestampMs is! int ||
        direction == null ||
        deliveryState == null) {
      return null;
    }
    if (direction == CapsuleChatMessageDirection.incoming &&
        toHex != null &&
        toHex != capsuleRootHex) {
      return null;
    }
    if (direction == CapsuleChatMessageDirection.outgoing &&
        (fromHex != capsuleRootHex || toHex == null)) {
      return null;
    }
    return CapsuleChatInboxMessage(
      id: id,
      fromHex: fromHex,
      toHex: toHex,
      messageText: messageText,
      createdAtUtc: createdAtUtc,
      envelopeHashHex: envelopeHashHex,
      timestampMs: timestampMs,
      direction: direction,
      deliveryState: deliveryState,
    );
  }

  void _touchCapsule(String capsuleRootHex) {
    _capsuleOrder.remove(capsuleRootHex);
    _capsuleOrder.add(capsuleRootHex);
  }

  void _retainNewestCapsules() {
    while (_capsuleOrder.length > maxCapsules) {
      clearCapsule(_capsuleOrder.first);
    }
  }

  void _retainNewestMessages(
    Map<String, CapsuleChatInboxMessage> messagesById,
  ) {
    if (messagesById.length <= maxRecordsPerCapsule) return;
    final oldestFirst =
        messagesById.values.toList()..sort((a, b) {
          final timestampOrder = a.timestampMs.compareTo(b.timestampMs);
          return timestampOrder != 0 ? timestampOrder : a.id.compareTo(b.id);
        });
    for (final message in oldestFirst.take(
      messagesById.length - maxRecordsPerCapsule,
    )) {
      messagesById.remove(message.id);
    }
  }

  void _retainNewestSignals(
    Map<String, CapsuleTradeSignalInboxMessage> signalsById,
  ) {
    if (signalsById.length <= maxRecordsPerCapsule) return;
    final oldestFirst =
        signalsById.values.toList()..sort((a, b) {
          final timestampOrder = a.timestampMs.compareTo(b.timestampMs);
          return timestampOrder != 0 ? timestampOrder : a.id.compareTo(b.id);
        });
    for (final signal in oldestFirst.take(
      signalsById.length - maxRecordsPerCapsule,
    )) {
      signalsById.remove(signal.id);
    }
  }

  bool _sameMessageSemantics(
    CapsuleChatInboxMessage existing,
    CapsuleChatInboxMessage candidate,
  ) {
    return existing.id == candidate.id &&
        existing.fromHex == candidate.fromHex &&
        existing.toHex == candidate.toHex &&
        existing.messageText == candidate.messageText &&
        existing.createdAtUtc == candidate.createdAtUtc &&
        existing.envelopeHashHex == candidate.envelopeHashHex &&
        existing.timestampMs == candidate.timestampMs &&
        existing.direction == candidate.direction;
  }

  static bool _isHex64(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}
