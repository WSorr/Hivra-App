import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../ffi/app_runtime_runtime.dart';
import '../ffi/capsule_chat_runtime.dart';
import '../models/relationship.dart';
import 'capsule_address_service.dart';
import 'manual_consensus_check_service.dart';

// Chat send may need two relay publish passes under degraded connectivity.
// Keep timeout above a single slow relay cycle to avoid false -1003 while
// transport still completes on a later relay.
const Duration _chatSendWorkerTimeout = Duration(seconds: 35);
const Duration _chatReceiveWorkerTimeout = Duration(seconds: 12);

typedef ChatWorkerRunner = Future<Map<String, Object?>> Function(
  Map<String, Object?> args,
);
typedef ChatRelationshipsLoader = List<Relationship> Function();
typedef ChatTrustedCardsLoader = Future<List<CapsuleAddressCard>> Function();

Future<Map<String, Object?>> _defaultSendWorkerRunner(
  Map<String, Object?> args,
) {
  return compute<Map<String, Object?>, Map<String, Object?>>(
    sendCapsuleChatInWorker,
    args,
  );
}

Future<Map<String, Object?>> _defaultReceiveWorkerRunner(
  Map<String, Object?> args,
) {
  return compute<Map<String, Object?>, Map<String, Object?>>(
    receiveCapsuleChatInWorker,
    args,
  );
}

List<Relationship> _emptyRelationships() => const <Relationship>[];
Future<List<CapsuleAddressCard>> _emptyTrustedCards() async =>
    const <CapsuleAddressCard>[];

class CapsuleChatDeliverySendResult {
  final bool isSuccess;
  final bool blockedByConsensus;
  final int code;
  final String? errorMessage;
  final String? deliveryPeerHex;

  const CapsuleChatDeliverySendResult({
    required this.isSuccess,
    required this.blockedByConsensus,
    required this.code,
    required this.errorMessage,
    required this.deliveryPeerHex,
  });
}

class CapsuleChatInboxMessage {
  final String id;
  final String fromHex;
  final String messageText;
  final String createdAtUtc;
  final String envelopeHashHex;
  final int timestampMs;

  const CapsuleChatInboxMessage({
    required this.id,
    required this.fromHex,
    required this.messageText,
    required this.createdAtUtc,
    required this.envelopeHashHex,
    required this.timestampMs,
  });
}

class CapsuleTradeSignalInboxMessage {
  final String id;
  final String signalId;
  final String fromHex;
  final String symbol;
  final String side;
  final String orderType;
  final String quantityDecimal;
  final String entryMode;
  final String intentHashHex;
  final String createdAtUtc;
  final String? strategyTag;
  final String canonicalIntentJson;
  final int timestampMs;

  const CapsuleTradeSignalInboxMessage({
    required this.id,
    required this.signalId,
    required this.fromHex,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantityDecimal,
    required this.entryMode,
    required this.intentHashHex,
    required this.createdAtUtc,
    required this.strategyTag,
    required this.canonicalIntentJson,
    required this.timestampMs,
  });
}

class CapsuleChatDeliveryReceiveResult {
  final int code;
  final String? errorMessage;
  final int droppedByConsensus;
  final List<CapsuleChatInboxMessage> messages;
  final List<CapsuleTradeSignalInboxMessage> tradeSignals;

  const CapsuleChatDeliveryReceiveResult({
    required this.code,
    required this.errorMessage,
    required this.droppedByConsensus,
    required this.messages,
    required this.tradeSignals,
  });
}

class CapsuleChatDeliveryService {
  final AppRuntimeRuntime _runtime;
  final ManualConsensusCheckService _manualChecks;
  final ChatRelationshipsLoader _loadRelationships;
  final ChatTrustedCardsLoader _listTrustedCards;
  final ChatWorkerRunner _sendWorkerRunner;
  final ChatWorkerRunner _receiveWorkerRunner;

  CapsuleChatDeliveryService({
    required AppRuntimeRuntime runtime,
    required ManualConsensusCheckService manualChecks,
    ChatRelationshipsLoader? loadRelationships,
    ChatTrustedCardsLoader? listTrustedCards,
    ChatWorkerRunner sendWorkerRunner = _defaultSendWorkerRunner,
    ChatWorkerRunner receiveWorkerRunner = _defaultReceiveWorkerRunner,
  })  : _runtime = runtime,
        _manualChecks = manualChecks,
        _loadRelationships = loadRelationships ?? _emptyRelationships,
        _listTrustedCards = listTrustedCards ?? _emptyTrustedCards,
        _sendWorkerRunner = sendWorkerRunner,
        _receiveWorkerRunner = receiveWorkerRunner;

  Future<CapsuleChatDeliverySendResult> sendCanonicalEnvelope({
    required String peerHex,
    required String canonicalEnvelopeJson,
  }) async {
    if (!_isPeerSignable(peerHex)) {
      return const CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: true,
        code: -2001,
        errorMessage: 'Consensus guard blocked chat delivery for this peer',
        deliveryPeerHex: null,
      );
    }

    final identityIndex = await _loadPeerIdentityIndex();
    final deliveryPeerHex = identityIndex.resolveTransportForSend(peerHex);
    if (deliveryPeerHex == null) {
      return const CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: false,
        code: -2003,
        errorMessage: 'No transport endpoint mapped for this consensus peer',
        deliveryPeerHex: null,
      );
    }

    final peerBytes = _hexToBytes(deliveryPeerHex);
    if (peerBytes == null) {
      return const CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: false,
        code: -1,
        errorMessage: 'peer_hex must be a 64-char lowercase hex',
        deliveryPeerHex: null,
      );
    }

    final bootstrap = await _runtime.loadWorkerBootstrapArgs();
    if (bootstrap == null) {
      return const CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: false,
        code: -1004,
        errorMessage: 'Chat worker bootstrap unavailable',
        deliveryPeerHex: null,
      );
    }

    final workerResult = await _sendWorkerRunner(
      <String, Object?>{
        ...bootstrap,
        'toPubkey': peerBytes,
        'payloadJson': canonicalEnvelopeJson,
      },
    ).timeout(
      _chatSendWorkerTimeout,
      onTimeout: () => <String, Object?>{
        'result': -1003,
        'lastError':
            'Chat send timed out locally; relay delivery may still complete',
      },
    );

    final code = (workerResult['result'] as int?) ?? -1003;
    final lastError = workerResult['lastError'] as String?;
    if (code != 0) {
      return CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: false,
        code: code,
        errorMessage: lastError ?? 'Chat delivery failed',
        deliveryPeerHex: deliveryPeerHex,
      );
    }

    return CapsuleChatDeliverySendResult(
      isSuccess: true,
      blockedByConsensus: false,
      code: 0,
      errorMessage: null,
      deliveryPeerHex: deliveryPeerHex,
    );
  }

  Future<CapsuleChatDeliveryReceiveResult> receiveAndFilter() async {
    final bootstrap = await _runtime.loadWorkerBootstrapArgs();
    if (bootstrap == null) {
      return CapsuleChatDeliveryReceiveResult(
        code: -1004,
        errorMessage: 'Chat worker bootstrap unavailable',
        droppedByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }

    final transport = await _receiveWorkerRunner(bootstrap).timeout(
      _chatReceiveWorkerTimeout,
      onTimeout: () => <String, Object?>{
        'result': -1003,
        'json': null,
        'lastError': 'Chat fetch timed out',
      },
    );
    final code = (transport['result'] as int?) ?? -1003;
    final rawJson = transport['json'] as String?;
    final transportError = transport['lastError'] as String?;
    if (code < 0) {
      return CapsuleChatDeliveryReceiveResult(
        code: code,
        errorMessage: transportError,
        droppedByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }

    if (rawJson == null || rawJson.trim().isEmpty) {
      return CapsuleChatDeliveryReceiveResult(
        code: code,
        errorMessage: null,
        droppedByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (_) {
      return CapsuleChatDeliveryReceiveResult(
        code: -2002,
        errorMessage: 'Chat receive payload is not valid JSON',
        droppedByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }
    if (decoded is! List) {
      return CapsuleChatDeliveryReceiveResult(
        code: -2002,
        errorMessage: 'Chat receive payload has invalid shape',
        droppedByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }

    final checks = _manualChecks.loadChecks();
    final signablePeers = <String>{
      for (final check in checks)
        if (check.isSignable) check.peerHex.trim().toLowerCase(),
    };
    final identityIndex = await _loadPeerIdentityIndex();

    final byId = <String, CapsuleChatInboxMessage>{};
    final byTradeSignalId = <String, CapsuleTradeSignalInboxMessage>{};
    var droppedByConsensus = 0;

    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final fromHex = (map['from_hex']?.toString().trim().toLowerCase() ?? '');
      final payloadJson = map['payload_json']?.toString() ?? '';
      final timestampMs = _toInt(map['timestamp_ms']) ?? 0;
      if (!_isLowerHex64(fromHex) || payloadJson.isEmpty) {
        continue;
      }
      final consensusPeerHex =
          identityIndex.resolveConsensusForIncoming(fromHex);
      final isSignablePeer = signablePeers.contains(consensusPeerHex) ||
          signablePeers.contains(fromHex);
      if (!isSignablePeer) {
        droppedByConsensus += 1;
        continue;
      }

      final envelope = _parseEnvelope(payloadJson);
      if (envelope != null) {
        final id = envelope['envelope_hash_hex']!.isEmpty
            ? _stableMessageId(consensusPeerHex, timestampMs, payloadJson)
            : envelope['envelope_hash_hex']!;

        byId[id] = CapsuleChatInboxMessage(
          id: id,
          fromHex: consensusPeerHex,
          messageText: envelope['message_text']!,
          createdAtUtc: envelope['created_at_utc']!,
          envelopeHashHex: envelope['envelope_hash_hex']!,
          timestampMs: timestampMs,
        );
        continue;
      }

      final tradeSignal = _parseTradeSignalEnvelope(payloadJson);
      if (tradeSignal == null) continue;
      final signalId = tradeSignal['signal_id']!;
      final id = signalId.isEmpty
          ? _stableMessageId(consensusPeerHex, timestampMs, payloadJson)
          : signalId;
      byTradeSignalId[id] = CapsuleTradeSignalInboxMessage(
        id: id,
        signalId: signalId.isEmpty ? id : signalId,
        fromHex: consensusPeerHex,
        symbol: tradeSignal['symbol']!,
        side: tradeSignal['side']!,
        orderType: tradeSignal['order_type']!,
        quantityDecimal: tradeSignal['quantity_decimal']!,
        entryMode: tradeSignal['entry_mode']!,
        intentHashHex: tradeSignal['intent_hash_hex']!,
        createdAtUtc: tradeSignal['created_at_utc']!,
        strategyTag: tradeSignal['strategy_tag'],
        canonicalIntentJson: tradeSignal['canonical_intent_json']!,
        timestampMs: timestampMs,
      );
    }

    final messages = byId.values.toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final tradeSignals = byTradeSignalId.values.toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    return CapsuleChatDeliveryReceiveResult(
      code: code,
      errorMessage: null,
      droppedByConsensus: droppedByConsensus,
      messages: List<CapsuleChatInboxMessage>.unmodifiable(messages),
      tradeSignals:
          List<CapsuleTradeSignalInboxMessage>.unmodifiable(tradeSignals),
    );
  }

  bool _isPeerSignable(String peerHex) {
    final normalized = peerHex.trim().toLowerCase();
    final checks = _manualChecks.loadChecks();
    for (final check in checks) {
      if (check.peerHex.trim().toLowerCase() == normalized) {
        return check.isSignable;
      }
    }
    return false;
  }

  Future<_PeerIdentityIndex> _loadPeerIdentityIndex() async {
    final transportPeers = <String>{};
    final transportToRoot = <String, String>{};
    final rootToTransport = <String, String>{};

    final relationships = _loadRelationships();
    for (final relationship in relationships) {
      if (!relationship.isActive || relationship.hasPendingRemoteBreak) {
        continue;
      }
      final transportHex = _decodeB64ToHex32(relationship.peerPubkey);
      if (transportHex == null) continue;
      transportPeers.add(transportHex);

      final peerRoot = relationship.peerRootPubkey;
      if (peerRoot == null || peerRoot.isEmpty) {
        continue;
      }
      final rootHex = _decodeB64ToHex32(peerRoot);
      if (rootHex == null) continue;
      transportToRoot.putIfAbsent(transportHex, () => rootHex);
      rootToTransport.putIfAbsent(rootHex, () => transportHex);
    }

    List<CapsuleAddressCard> cards;
    try {
      cards = await _listTrustedCards();
    } catch (_) {
      cards = const <CapsuleAddressCard>[];
    }
    for (final card in cards) {
      final rootHex = _normalizeHex32(card.rootHex);
      final transportHex = _normalizeHex32(card.nostrHex);
      if (rootHex == null || transportHex == null) continue;
      transportPeers.add(transportHex);
      transportToRoot.putIfAbsent(transportHex, () => rootHex);
      rootToTransport.putIfAbsent(rootHex, () => transportHex);
    }

    return _PeerIdentityIndex(
      transportPeers: transportPeers,
      transportToRoot: transportToRoot,
      rootToTransport: rootToTransport,
    );
  }

  Uint8List? _hexToBytes(String hex) {
    final normalized = hex.trim().toLowerCase();
    if (!_isLowerHex64(normalized)) return null;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i += 1) {
      final start = i * 2;
      final byte = int.tryParse(
        normalized.substring(start, start + 2),
        radix: 16,
      );
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }

  bool _isLowerHex64(String value) {
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
  }

  int? _toInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }

  String? _decodeB64ToHex32(String value) {
    try {
      final bytes = base64.decode(value);
      if (bytes.length != 32) return null;
      return _hex(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  String? _normalizeHex32(String value) {
    final normalized = value.trim().toLowerCase();
    return _isLowerHex64(normalized) ? normalized : null;
  }

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Map<String, String>? _parseEnvelope(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final messageText = map['message_text']?.toString() ?? '';
      final createdAtUtc = map['created_at_utc']?.toString() ?? '';
      final envelopeHashHex = map['envelope_hash_hex']?.toString() ?? '';
      if (messageText.isEmpty || createdAtUtc.isEmpty) return null;
      return <String, String>{
        'message_text': messageText,
        'created_at_utc': createdAtUtc,
        'envelope_hash_hex': envelopeHashHex.toLowerCase(),
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, String?>? _parseTradeSignalEnvelope(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['contract_kind']?.toString() != 'bingx_trade_signal_v1') {
        return null;
      }

      final signalId = map['signal_id']?.toString() ?? '';
      final symbol = map['symbol']?.toString() ?? '';
      final side = map['side']?.toString() ?? '';
      final orderType = map['order_type']?.toString() ?? '';
      final quantityDecimal = map['quantity_decimal']?.toString() ?? '';
      final entryMode = map['entry_mode']?.toString() ?? 'direct';
      final intentHashHex =
          (map['intent_hash_hex']?.toString() ?? '').toLowerCase();
      final createdAtUtc = map['created_at_utc']?.toString() ?? '';
      final canonicalIntentJson =
          map['canonical_intent_json']?.toString() ?? '';
      final strategyTag = map['strategy_tag']?.toString();

      if (symbol.isEmpty ||
          side.isEmpty ||
          orderType.isEmpty ||
          quantityDecimal.isEmpty ||
          intentHashHex.isEmpty ||
          createdAtUtc.isEmpty ||
          canonicalIntentJson.isEmpty) {
        return null;
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(intentHashHex)) {
        return null;
      }

      return <String, String?>{
        'signal_id': signalId,
        'symbol': symbol,
        'side': side,
        'order_type': orderType,
        'quantity_decimal': quantityDecimal,
        'entry_mode': entryMode,
        'intent_hash_hex': intentHashHex,
        'created_at_utc': createdAtUtc,
        'strategy_tag': strategyTag,
        'canonical_intent_json': canonicalIntentJson,
      };
    } catch (_) {
      return null;
    }
  }

  String _stableMessageId(String fromHex, int timestampMs, String payloadJson) {
    final canonical = '$fromHex|$timestampMs|$payloadJson';
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

class _PeerIdentityIndex {
  final Set<String> _transportPeers;
  final Map<String, String> _transportToRoot;
  final Map<String, String> _rootToTransport;

  const _PeerIdentityIndex({
    required Set<String> transportPeers,
    required Map<String, String> transportToRoot,
    required Map<String, String> rootToTransport,
  })  : _transportPeers = transportPeers,
        _transportToRoot = transportToRoot,
        _rootToTransport = rootToTransport;

  String? resolveTransportForSend(String peerHex) {
    final normalized = peerHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return null;
    if (_transportPeers.contains(normalized)) {
      return normalized;
    }
    return _rootToTransport[normalized];
  }

  String resolveConsensusForIncoming(String transportPeerHex) {
    final normalized = transportPeerHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return normalized;
    return _transportToRoot[normalized] ?? normalized;
  }

  static bool _isHex64(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}
