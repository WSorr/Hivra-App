import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../ffi/app_runtime_runtime.dart';
import '../ffi/capsule_chat_runtime.dart';
import '../models/capsule_chat_models.dart';
import '../models/consensus_models.dart';
import '../models/relationship.dart';
import 'bingx_futures_execution_command_service.dart';
import 'capsule_address_service.dart';
import 'capsule_chat_deferred_inbox_store.dart';
import 'manual_consensus_check_service.dart';
import 'ledger_view_support.dart';
import 'transport_health_policy_service.dart';

// Chat send may need two relay publish passes under degraded connectivity.
// Keep timeout above a single slow relay cycle to avoid false -1003 while
// transport still completes on a later relay.
const Duration _chatSendWorkerTimeout = Duration(seconds: 35);
// Quick Nostr receive can spend up to ~20 seconds on cold relay connection
// plus event fetch. A shorter Dart timeout does not cancel the compute worker:
// it can consume and mark events as seen after the caller has discarded them.
const Duration _chatReceiveWorkerTimeout = Duration(seconds: 30);

String tradeSignalInboxRecordId({
  required String fromHex,
  required String signalId,
  required int timestampMs,
  required String payloadJson,
}) {
  final normalizedFrom = fromHex.trim().toLowerCase();
  final normalizedSignalId = signalId.trim();
  if (normalizedSignalId.isNotEmpty) {
    return '$normalizedFrom::$normalizedSignalId';
  }
  final canonical = '$normalizedFrom|$timestampMs|$payloadJson';
  return sha256.convert(utf8.encode(canonical)).toString();
}

typedef ChatWorkerRunner =
    Future<Map<String, Object?>> Function(Map<String, Object?> args);
typedef ChatRelationshipsLoader = List<Relationship> Function();
typedef ChatTrustedCardsLoader = Future<List<CapsuleAddressCard>> Function();
typedef ChatAttestedSignableReader =
    Future<ConsensusSignableResult> Function(String peerRootHex);
typedef ExecutionPolicyResolver = BingxExecutionPolicy Function(String peerHex);
typedef ExecutionKnownIntentLookup = bool Function(String intentHashHex);
typedef UtcNowProvider = DateTime Function();

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
DateTime _defaultNowUtc() => DateTime.now().toUtc();
BingxExecutionPolicy _defaultExecutionPolicyForPeer(String _) =>
    const BingxExecutionPolicy(
      allowedSymbols: <String>{},
      maxLeverage: 1000,
      maxRiskPercent: 100,
    );

class CapsuleTradeSignalInboxStore {
  static final CapsuleTradeSignalInboxStore shared =
      CapsuleTradeSignalInboxStore();

  final Map<String, Map<String, CapsuleTradeSignalInboxMessage>>
  _signalsByCapsule = <String, Map<String, CapsuleTradeSignalInboxMessage>>{};

  CapsuleTradeSignalInboxStore();

  List<CapsuleTradeSignalInboxMessage> load(String capsuleRootHex) {
    final normalized = capsuleRootHex.trim().toLowerCase();
    final signals =
        _signalsByCapsule[normalized]?.values.toList() ??
        <CapsuleTradeSignalInboxMessage>[];
    signals.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return List<CapsuleTradeSignalInboxMessage>.unmodifiable(signals);
  }

  void merge(
    String capsuleRootHex,
    Iterable<CapsuleTradeSignalInboxMessage> signals,
  ) {
    final normalized = capsuleRootHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return;
    final byId = _signalsByCapsule.putIfAbsent(
      normalized,
      () => <String, CapsuleTradeSignalInboxMessage>{},
    );
    for (final signal in signals) {
      byId[signal.id] = signal;
    }
  }

  static bool _isHex64(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

class CapsuleChatDeliveryService {
  final AppRuntimeRuntime _runtime;
  final ManualConsensusCheckService _manualChecks;
  final ChatAttestedSignableReader? _readAttestedSignable;
  final ChatRelationshipsLoader _loadRelationships;
  final ChatTrustedCardsLoader _listTrustedCards;
  final ChatWorkerRunner _sendWorkerRunner;
  final ChatWorkerRunner _receiveWorkerRunner;
  final CapsuleChatDeferredInboxStore _deferredInboxStore;
  final CapsuleTradeSignalInboxStore _tradeSignalInboxStore;
  final BingxFuturesExecutionCommandService _executionCommandService;
  final ExecutionPolicyResolver _executionPolicyForPeer;
  final ExecutionKnownIntentLookup? _hasKnownIntentHash;
  final UtcNowProvider _nowUtc;
  final TransportHealthPolicyService _transportHealth;
  final LedgerViewSupport _ledgerSupport = const LedgerViewSupport();

  CapsuleChatDeliveryService({
    required AppRuntimeRuntime runtime,
    required ManualConsensusCheckService manualChecks,
    ChatAttestedSignableReader? readAttestedSignable,
    ChatRelationshipsLoader? loadRelationships,
    ChatTrustedCardsLoader? listTrustedCards,
    ChatWorkerRunner sendWorkerRunner = _defaultSendWorkerRunner,
    ChatWorkerRunner receiveWorkerRunner = _defaultReceiveWorkerRunner,
    CapsuleChatDeferredInboxStore? deferredInboxStore,
    CapsuleTradeSignalInboxStore? tradeSignalInboxStore,
    BingxFuturesExecutionCommandService? executionCommandService,
    ExecutionPolicyResolver? executionPolicyForPeer,
    ExecutionKnownIntentLookup? hasKnownIntentHash,
    UtcNowProvider nowUtc = _defaultNowUtc,
    TransportHealthPolicyService? transportHealth,
  }) : _runtime = runtime,
       _manualChecks = manualChecks,
       _readAttestedSignable = readAttestedSignable,
       _loadRelationships = loadRelationships ?? _emptyRelationships,
       _listTrustedCards = listTrustedCards ?? _emptyTrustedCards,
       _sendWorkerRunner = sendWorkerRunner,
       _receiveWorkerRunner = receiveWorkerRunner,
       _deferredInboxStore =
           deferredInboxStore ?? const CapsuleChatDeferredInboxStore(),
       _tradeSignalInboxStore =
           tradeSignalInboxStore ?? CapsuleTradeSignalInboxStore.shared,
       _executionCommandService =
           executionCommandService ??
           BingxFuturesExecutionCommandService(
             replayStore: InMemoryBingxExecutionCommandReplayStore(),
           ),
       _executionPolicyForPeer =
           executionPolicyForPeer ?? _defaultExecutionPolicyForPeer,
       _hasKnownIntentHash = hasKnownIntentHash,
       _nowUtc = nowUtc,
       _transportHealth =
           transportHealth ?? TransportHealthPolicyService.shared;

  List<CapsuleTradeSignalInboxMessage> loadCachedTradeSignals() {
    final root = _runtime.capsuleRootPublicKey();
    if (root == null || root.length != 32) {
      return const <CapsuleTradeSignalInboxMessage>[];
    }
    return _tradeSignalInboxStore.load(_hex(root));
  }

  Future<CapsuleChatDeliverySendResult> sendCanonicalEnvelope({
    required String peerHex,
    required String canonicalEnvelopeJson,
    String? expectedCapsuleRootHex,
  }) async {
    final expectedOwner = expectedCapsuleRootHex?.trim().toLowerCase();
    if (expectedOwner != null && _localCapsuleRootHex() != expectedOwner) {
      return const CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: false,
        code: -2004,
        errorMessage: 'Active capsule changed before chat delivery',
        deliveryPeerHex: null,
      );
    }
    if (!await _isPeerAttestedSignable(peerHex)) {
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
    final bootstrapOwner =
        bootstrap['activeCapsuleHex']?.toString().trim().toLowerCase();
    if (expectedOwner != null && bootstrapOwner != expectedOwner) {
      return const CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: false,
        code: -2004,
        errorMessage: 'Active capsule changed before chat delivery',
        deliveryPeerHex: null,
      );
    }

    Future<Map<String, Object?>> runWorker() {
      return _sendWorkerRunner(<String, Object?>{
        ...bootstrap,
        'toPubkey': peerBytes,
        'payloadJson': canonicalEnvelopeJson,
      }).timeout(
        _chatSendWorkerTimeout,
        onTimeout:
            () => <String, Object?>{
              'result': -1003,
              'lastError':
                  'Chat send timed out locally; relay delivery may still complete',
            },
      );
    }

    final workerResult = await runWorker();
    final code = (workerResult['result'] as int?) ?? -1003;
    final lastError = workerResult['lastError'] as String?;
    final deliveryReceiptsJson =
        workerResult['deliveryReceiptsJson'] as String?;
    _transportHealth.recordResult(
      capsuleHex: _localCapsuleRootHex(),
      code: code,
    );
    if (code != 0) {
      return CapsuleChatDeliverySendResult(
        isSuccess: false,
        blockedByConsensus: false,
        code: code,
        errorMessage: lastError ?? 'Chat delivery failed',
        deliveryPeerHex: deliveryPeerHex,
        deliveryReceiptsJson: deliveryReceiptsJson,
      );
    }

    return CapsuleChatDeliverySendResult(
      isSuccess: true,
      blockedByConsensus: false,
      code: 0,
      errorMessage: null,
      deliveryPeerHex: deliveryPeerHex,
      deliveryReceiptsJson: deliveryReceiptsJson,
    );
  }

  Future<CapsuleChatDeliveryReceiveResult> receiveAndFilter() async {
    final localRootHex = _localCapsuleRootHex();
    final health = _transportHealth.canRun(capsuleHex: localRootHex);
    if (!health.isAllowed) {
      return CapsuleChatDeliveryReceiveResult(
        code: health.code,
        errorMessage: health.message,
        droppedByConsensus: 0,
        deferredByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }
    final bootstrap = await _runtime.loadWorkerBootstrapArgs();
    if (bootstrap == null) {
      return CapsuleChatDeliveryReceiveResult(
        code: -1004,
        errorMessage: 'Chat worker bootstrap unavailable',
        droppedByConsensus: 0,
        deferredByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }

    final transport = await _receiveWorkerRunner(bootstrap).timeout(
      _chatReceiveWorkerTimeout,
      onTimeout:
          () => <String, Object?>{
            'result': -1003,
            'json': null,
            'lastError': 'Chat fetch timed out',
          },
    );
    final code = (transport['result'] as int?) ?? -1003;
    _transportHealth.recordResult(capsuleHex: localRootHex, code: code);
    final rawJson = transport['json'] as String?;
    final transportError = transport['lastError'] as String?;
    if (code < 0) {
      return CapsuleChatDeliveryReceiveResult(
        code: code,
        errorMessage: transportError,
        droppedByConsensus: 0,
        deferredByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }

    final List<dynamic> decoded;
    if (rawJson == null || rawJson.trim().isEmpty) {
      decoded = const <dynamic>[];
    } else {
      final dynamic parsed;
      try {
        parsed = jsonDecode(rawJson);
      } catch (_) {
        return CapsuleChatDeliveryReceiveResult(
          code: -2002,
          errorMessage: 'Chat receive payload is not valid JSON',
          droppedByConsensus: 0,
          deferredByConsensus: 0,
          messages: const <CapsuleChatInboxMessage>[],
          tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
        );
      }
      if (parsed is! List) {
        return CapsuleChatDeliveryReceiveResult(
          code: -2002,
          errorMessage: 'Chat receive payload has invalid shape',
          droppedByConsensus: 0,
          deferredByConsensus: 0,
          messages: const <CapsuleChatInboxMessage>[],
          tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
        );
      }
      decoded = List<dynamic>.from(parsed);
    }

    final identityIndex = await _loadPeerIdentityIndex();
    final signableCache = <String, ConsensusSignableResult>{};

    Future<ConsensusSignableResult> readSignable(String peerHex) async {
      final normalized = peerHex.trim().toLowerCase();
      final cached = signableCache[normalized];
      if (cached != null) return cached;
      final result = await _readPeerAttestedSignable(normalized);
      signableCache[normalized] = result;
      return result;
    }

    final byId = <String, CapsuleChatInboxMessage>{};
    final byTradeSignalId = <String, CapsuleTradeSignalInboxMessage>{};
    final byExecutionDecisionId =
        <String, CapsuleExecutionCommandDecisionMessage>{};
    final byExecutionReceiptId =
        <String, CapsuleExecutionReceiptInboxMessage>{};
    var droppedByConsensus = 0;
    var deferredByConsensus = 0;
    final remainingDeferred = <CapsuleChatDeferredInboxItem>[];
    final nextDeferred = <CapsuleChatDeferredInboxItem>[];
    final now = _nowUtc();
    final activeCapsuleHex = bootstrap['activeCapsuleHex']?.toString() ?? '';
    final deferredItems = await _deferredInboxStore.load(localRootHex ?? '');
    final incomingItems = <_ChatTransportItem>[
      for (final item in deferredItems)
        _ChatTransportItem(
          fromHex: item.fromHex,
          payloadJson: item.payloadJson,
          timestampMs: item.timestampMs,
          deferredItem: item,
        ),
    ];

    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final fromHex = (map['from_hex']?.toString().trim().toLowerCase() ?? '');
      final payloadJson = map['payload_json']?.toString() ?? '';
      final timestampMs = _toInt(map['timestamp_ms']) ?? 0;
      if (!_isLowerHex64(fromHex) || payloadJson.isEmpty) {
        continue;
      }
      incomingItems.add(
        _ChatTransportItem(
          fromHex: fromHex,
          payloadJson: payloadJson,
          timestampMs: timestampMs,
        ),
      );
    }

    for (final item in incomingItems) {
      final fromHex = item.fromHex;
      final payloadJson = item.payloadJson;
      final timestampMs = item.timestampMs;
      final consensusPeerHex = identityIndex.resolveConsensusForIncoming(
        fromHex,
      );
      var signable = await readSignable(consensusPeerHex);
      if (!signable.isSignable && consensusPeerHex != fromHex) {
        signable = await readSignable(fromHex);
      }
      final isSignablePeer = signable.isSignable;
      if (!isSignablePeer) {
        if (_shouldDeferForConsensus(signable) && localRootHex != null) {
          deferredByConsensus += 1;
          final deferredItem = item.deferredItem;
          if (deferredItem == null) {
            nextDeferred.add(
              _deferredInboxStore.create(
                capsuleHex: localRootHex,
                fromHex: fromHex,
                payloadJson: payloadJson,
                timestampMs: timestampMs,
                now: now,
              ),
            );
          } else {
            remainingDeferred.add(
              deferredItem.copyWith(
                lastSeenAt: now,
                attempts: deferredItem.attempts + 1,
              ),
            );
          }
        } else {
          droppedByConsensus += 1;
        }
        continue;
      }

      final envelope = _parseEnvelope(payloadJson);
      if (envelope != null) {
        final id =
            envelope['envelope_hash_hex']!.isEmpty
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

      final executionDecision = await _processExecutionCommandEnvelope(
        payloadJson: payloadJson,
        consensusPeerHex: consensusPeerHex,
        isSignablePeer: isSignablePeer,
        timestampMs: timestampMs,
      );
      if (executionDecision != null) {
        byExecutionDecisionId[executionDecision.id] = executionDecision;
        continue;
      }

      final executionReceipt = _parseExecutionReceiptEnvelope(payloadJson);
      if (executionReceipt != null) {
        final id = _stableMessageId(consensusPeerHex, timestampMs, payloadJson);
        byExecutionReceiptId[id] = CapsuleExecutionReceiptInboxMessage(
          id: id,
          fromHex: consensusPeerHex,
          commandId: executionReceipt['command_id']!,
          decision: executionReceipt['decision']!,
          decisionCode: executionReceipt['decision_code']!,
          decisionMessage: executionReceipt['decision_message']!,
          targetCapsuleRootHex: executionReceipt['target_capsule_root_hex']!,
          peerHex: executionReceipt['peer_hex']!,
          receiptCreatedAtUtc: executionReceipt['receipt_created_at_utc']!,
          timestampMs: timestampMs,
        );
        continue;
      }

      final tradeSignal = _parseTradeSignalEnvelope(payloadJson);
      if (tradeSignal == null) continue;
      final signalId = tradeSignal['signal_id']!;
      final id = tradeSignalInboxRecordId(
        fromHex: consensusPeerHex,
        signalId: signalId,
        timestampMs: timestampMs,
        payloadJson: payloadJson,
      );
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

    final messages =
        byId.values.toList()
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final tradeSignals =
        byTradeSignalId.values.toList()
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    _tradeSignalInboxStore.merge(activeCapsuleHex, tradeSignals);
    if (localRootHex != null) {
      final deferredById = <String, CapsuleChatDeferredInboxItem>{
        for (final item in remainingDeferred) item.id: item,
      };
      for (final item in nextDeferred) {
        deferredById[item.id] = item;
      }
      await _deferredInboxStore.replaceAll(
        capsuleHex: localRootHex,
        items: deferredById.values,
        now: now,
      );
    }
    final executionDecisions =
        byExecutionDecisionId.values.toList()
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final executionReceipts =
        byExecutionReceiptId.values.toList()
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    return CapsuleChatDeliveryReceiveResult(
      code: code,
      errorMessage: null,
      droppedByConsensus: droppedByConsensus,
      deferredByConsensus: deferredByConsensus,
      messages: List<CapsuleChatInboxMessage>.unmodifiable(messages),
      tradeSignals: List<CapsuleTradeSignalInboxMessage>.unmodifiable(
        tradeSignals,
      ),
      executionDecisions:
          List<CapsuleExecutionCommandDecisionMessage>.unmodifiable(
            executionDecisions,
          ),
      executionReceipts: List<CapsuleExecutionReceiptInboxMessage>.unmodifiable(
        executionReceipts,
      ),
    );
  }

  Future<CapsuleExecutionCommandDecisionMessage?>
  _processExecutionCommandEnvelope({
    required String payloadJson,
    required String consensusPeerHex,
    required bool isSignablePeer,
    required int timestampMs,
  }) async {
    final decoded = _parseJsonMap(payloadJson);
    if (decoded == null) return null;
    if (decoded['plugin_id']?.toString() !=
            BingxFuturesExecutionCommandService.pluginId ||
        decoded['command_kind']?.toString() !=
            BingxFuturesExecutionCommandService.commandKind) {
      return null;
    }

    final localCapsuleRootHex = _localCapsuleRootHex() ?? '';
    final commandId = decoded['command_id']?.toString().trim() ?? '-';
    final decision = _executionCommandService.evaluateIncomingCommand(
      commandEnvelopeJson: payloadJson,
      localCapsuleRootHex: localCapsuleRootHex,
      fromPeerHex: consensusPeerHex,
      isPeerSignable: isSignablePeer,
      nowUtc: _nowUtc(),
      policy: _executionPolicyForPeer(consensusPeerHex),
      hasKnownIntentHash: _hasKnownIntentHash,
    );

    final receiptSend = await sendCanonicalEnvelope(
      peerHex: consensusPeerHex,
      canonicalEnvelopeJson: decision.canonicalReceiptJson,
    );
    final decisionValue =
        decision.status == BingxExecutionDecisionStatus.accepted
            ? 'accepted'
            : 'rejected';
    final id = _stableMessageId(
      consensusPeerHex,
      timestampMs,
      '${decision.receiptHashHex}|$commandId|$decisionValue',
    );
    return CapsuleExecutionCommandDecisionMessage(
      id: id,
      fromHex: consensusPeerHex,
      commandId: commandId.isEmpty ? '-' : commandId,
      decision: decisionValue,
      decisionCode: decision.decisionCode,
      decisionMessage: decision.decisionMessage,
      receiptHashHex: decision.receiptHashHex,
      receiptDeliveryCode: receiptSend.code,
      receiptDeliveryError: receiptSend.errorMessage,
      timestampMs: timestampMs,
    );
  }

  ManualConsensusCheck? _manualConsensusForPeer(String peerHex) {
    final normalized = peerHex.trim().toLowerCase();
    final checks = _manualChecks.loadChecks();
    for (final check in checks) {
      if (check.peerHex.trim().toLowerCase() == normalized) {
        return check;
      }
    }
    return null;
  }

  Future<bool> _isPeerAttestedSignable(String peerHex) async {
    return (await _readPeerAttestedSignable(peerHex)).isSignable;
  }

  Future<ConsensusSignableResult> _readPeerAttestedSignable(
    String peerHex,
  ) async {
    final readAttestedSignable = _readAttestedSignable;
    if (readAttestedSignable == null) {
      final check = _manualConsensusForPeer(peerHex);
      final isSignable = check?.isSignable ?? false;
      return ConsensusSignableResult(
        preview:
            check == null
                ? null
                : ConsensusPreview(
                  peerHex: check.peerHex,
                  peerLabel: check.peerLabel,
                  invitationCount: check.invitationCount,
                  relationshipCount: check.relationshipCount,
                  hashHex: check.hashHex,
                  canonicalJson: check.canonicalJson,
                  blockingFacts: check.blockingFacts,
                ),
        blockingFacts:
            isSignable
                ? const <ConsensusBlockingFact>[]
                : check?.blockingFacts ??
                    const <ConsensusBlockingFact>[
                      ConsensusBlockingFact(code: 'pair_consensus_missing'),
                    ],
      );
    }
    return readAttestedSignable(peerHex);
  }

  bool _shouldDeferForConsensus(ConsensusSignableResult signable) {
    return signable.blockingFacts.any((fact) {
      final code = fact.code.trim().toLowerCase();
      return code == 'pair_attestation_missing' ||
          code == 'pair_attestation_incomplete' ||
          code == 'pair_consensus_attestation_missing';
    });
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

      final peerRoot = relationship.peerRootPubkey;
      if (peerRoot == null || peerRoot.isEmpty) {
        transportPeers.add(transportHex);
        continue;
      }
      final rootHex = _decodeB64ToHex32(peerRoot);
      if (rootHex == null) continue;
      _rememberPeerTransport(
        transportPeers: transportPeers,
        transportToRoot: transportToRoot,
        rootToTransport: rootToTransport,
        rootHex: rootHex,
        transportHex: transportHex,
      );
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
      _rememberPeerTransport(
        transportPeers: transportPeers,
        transportToRoot: transportToRoot,
        rootToTransport: rootToTransport,
        rootHex: rootHex,
        transportHex: transportHex,
      );
    }

    _mergeInvitationIdentityFacts(
      transportPeers: transportPeers,
      transportToRoot: transportToRoot,
      rootToTransport: rootToTransport,
    );

    return _PeerIdentityIndex(
      transportPeers: transportPeers,
      transportToRoot: transportToRoot,
      rootToTransport: rootToTransport,
    );
  }

  void _mergeInvitationIdentityFacts({
    required Set<String> transportPeers,
    required Map<String, String> transportToRoot,
    required Map<String, String> rootToTransport,
  }) {
    final ledgerRoot = _ledgerSupport.exportLedgerRoot(_runtime.exportLedger());
    if (ledgerRoot == null) return;

    for (final raw in _ledgerSupport.events(ledgerRoot)) {
      if (raw is! Map) continue;
      final event = Map<String, dynamic>.from(raw);
      if (_ledgerSupport.kindCode(event['kind']) != 9) continue;
      final payload = _ledgerSupport.payloadBytes(event['payload']);
      if (payload.length < 161) continue;

      final senderRoot = _hex(Uint8List.fromList(payload.sublist(96, 128)));
      final senderTransport = _hex(
        Uint8List.fromList(payload.sublist(129, 161)),
      );
      _rememberPeerTransport(
        transportPeers: transportPeers,
        transportToRoot: transportToRoot,
        rootToTransport: rootToTransport,
        rootHex: senderRoot,
        transportHex: senderTransport,
      );
    }
  }

  void _rememberPeerTransport({
    required Set<String> transportPeers,
    required Map<String, String> transportToRoot,
    required Map<String, String> rootToTransport,
    required String rootHex,
    required String transportHex,
  }) {
    if (rootHex == transportHex) return;
    transportPeers.add(transportHex);
    transportToRoot[transportHex] = rootHex;
    final current = rootToTransport[rootHex];
    if (current == null || current == rootHex) {
      rootToTransport[rootHex] = transportHex;
    }
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

  Map<String, String>? _parseExecutionReceiptEnvelope(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['receipt_kind']?.toString() !=
          BingxFuturesExecutionCommandService.receiptKind) {
        return null;
      }

      final commandId = map['command_id']?.toString().trim() ?? '';
      final decision = map['decision']?.toString().trim().toLowerCase() ?? '';
      final decisionCode = map['decision_code']?.toString().trim() ?? '';
      final decisionMessage = map['decision_message']?.toString().trim() ?? '';
      final targetCapsuleRootHex =
          map['target_capsule_root_hex']?.toString().trim().toLowerCase() ?? '';
      final peerHex = map['peer_hex']?.toString().trim().toLowerCase() ?? '';
      final receiptCreatedAtUtc =
          map['receipt_created_at_utc']?.toString().trim() ?? '';
      if (commandId.isEmpty ||
          decisionCode.isEmpty ||
          decisionMessage.isEmpty ||
          !const <String>{'accepted', 'rejected'}.contains(decision) ||
          !_isLowerHex64(targetCapsuleRootHex) ||
          !_isLowerHex64(peerHex) ||
          !_isIsoUtc(receiptCreatedAtUtc)) {
        return null;
      }
      return <String, String>{
        'command_id': commandId,
        'decision': decision,
        'decision_code': decisionCode,
        'decision_message': decisionMessage,
        'target_capsule_root_hex': targetCapsuleRootHex,
        'peer_hex': peerHex,
        'receipt_created_at_utc': receiptCreatedAtUtc,
      };
    } catch (_) {
      return null;
    }
  }

  String? _localCapsuleRootHex() {
    final root = _runtime.capsuleRootPublicKey();
    if (root != null && root.length == 32) {
      return _hex(root);
    }
    final nostr = _runtime.capsuleNostrPublicKey();
    if (nostr != null && nostr.length == 32) {
      return _hex(nostr);
    }
    return null;
  }

  Map<String, dynamic>? _parseJsonMap(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  bool _isIsoUtc(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.isUtc;
  }

  String _stableMessageId(String fromHex, int timestampMs, String payloadJson) {
    final canonical = '$fromHex|$timestampMs|$payloadJson';
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

class _ChatTransportItem {
  final String fromHex;
  final String payloadJson;
  final int timestampMs;
  final CapsuleChatDeferredInboxItem? deferredItem;

  const _ChatTransportItem({
    required this.fromHex,
    required this.payloadJson,
    required this.timestampMs,
    this.deferredItem,
  });
}

class _PeerIdentityIndex {
  final Set<String> _transportPeers;
  final Map<String, String> _transportToRoot;
  final Map<String, String> _rootToTransport;

  const _PeerIdentityIndex({
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
