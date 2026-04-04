import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'consensus_processor.dart';

typedef ChatConsensusSignableReader = ConsensusSignableResult Function(
  String peerHex,
);

class CapsuleChatEnvelope {
  final String pluginId;
  final String peerHex;
  final String clientMessageId;
  final String messageText;
  final String createdAtUtc;
  final String canonicalJson;
  final String envelopeHashHex;

  const CapsuleChatEnvelope({
    required this.pluginId,
    required this.peerHex,
    required this.clientMessageId,
    required this.messageText,
    required this.createdAtUtc,
    required this.canonicalJson,
    required this.envelopeHashHex,
  });
}

class CapsuleChatExecutionResult {
  final CapsuleChatEnvelope? envelope;
  final List<ConsensusBlockingFact> blockingFacts;

  const CapsuleChatExecutionResult({
    required this.envelope,
    required this.blockingFacts,
  });

  bool get isExecutable => envelope != null && blockingFacts.isEmpty;
}

class CapsuleChatContractService {
  static const String pluginId = 'hivra.contract.capsule-chat.v1';
  final ChatConsensusSignableReader _readSignable;

  const CapsuleChatContractService({
    required ChatConsensusSignableReader readSignable,
  }) : _readSignable = readSignable;

  CapsuleChatExecutionResult execute({
    required String peerHex,
    required String clientMessageId,
    required String messageText,
    required String createdAtUtc,
  }) {
    final signable = _readSignable(peerHex);
    if (!signable.isSignable) {
      return CapsuleChatExecutionResult(
        envelope: null,
        blockingFacts: signable.blockingFacts,
      );
    }

    final envelope = evaluateDeterministic(
      peerHex: peerHex,
      clientMessageId: clientMessageId,
      messageText: messageText,
      createdAtUtc: createdAtUtc,
    );
    return CapsuleChatExecutionResult(
      envelope: envelope,
      blockingFacts: <ConsensusBlockingFact>[],
    );
  }

  CapsuleChatEnvelope evaluateDeterministic({
    required String peerHex,
    required String clientMessageId,
    required String messageText,
    required String createdAtUtc,
  }) {
    final normalizedPeer = peerHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedPeer)) {
      throw const FormatException('peer_hex must be a 64-char lowercase hex');
    }

    final messageId = clientMessageId.trim();
    if (messageId.isEmpty) {
      throw const FormatException('client_message_id is required');
    }
    if (messageId.length > 128) {
      throw const FormatException('client_message_id must be <= 128 chars');
    }

    final text = messageText.trim();
    if (text.isEmpty) {
      throw const FormatException('message_text is required');
    }
    if (utf8.encode(text).length > 1024) {
      throw const FormatException('message_text must be <= 1024 UTF-8 bytes');
    }

    final created = createdAtUtc.trim();
    if (!_isIsoUtc(created)) {
      throw const FormatException(
          'created_at_utc must be ISO-8601 UTC instant');
    }

    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plugin_id': pluginId,
      'contract_kind': 'capsule_chat_direct',
      'peer_hex': normalizedPeer,
      'client_message_id': messageId,
      'message_text': text,
      'created_at_utc': created,
    });
    final hashHex = sha256.convert(utf8.encode(canonical)).toString();

    return CapsuleChatEnvelope(
      pluginId: pluginId,
      peerHex: normalizedPeer,
      clientMessageId: messageId,
      messageText: text,
      createdAtUtc: created,
      canonicalJson: canonical,
      envelopeHashHex: hashHex,
    );
  }

  bool _isIsoUtc(String value) {
    try {
      return DateTime.parse(value).isUtc;
    } catch (_) {
      return false;
    }
  }
}
