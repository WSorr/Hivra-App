import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/bingx_futures_live_snapshot_builder_service.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_zone_decision_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_risk_input_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_order_sizing_service.dart';
import 'package:hivra_app/services/bingx_futures_remote_order_candidate_service.dart';
import 'package:hivra_app/services/bingx_futures_risk_history_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

import 'trading_remote_shadow_probe.dart' show readExchangeCredentialFile;

const String deterministicOrderMode = 'deterministic-order';
const String deterministicOrderRecoveryMode = 'deterministic-order-recovery';
const int _maxEvidenceBytes = 8192;

typedef AuthorizedExactOrderExecutor =
    Future<String> Function({
      required BingxFuturesRemoteMandateAdmission admission,
      required Map<String, dynamic> exactOrder,
      required String effectOperationId,
      required BingxFuturesApiCredentials credentials,
      required String stateHome,
      BingxHttpRequestSender? requestSender,
      DateTime Function()? nowUtc,
      int Function()? clockMs,
    });

typedef AuthorizedExactOrderReconciler =
    Future<String> Function({
      required BingxFuturesRemoteMandateAdmission admission,
      required String effectOperationId,
      required BingxFuturesApiCredentials credentials,
      required String stateHome,
      BingxHttpRequestSender? requestSender,
      DateTime Function()? nowUtc,
      int Function()? clockMs,
    });

typedef AuthorizedManagedOrderCanceler =
    Future<String> Function({
      required BingxFuturesRemoteMandateAdmission admission,
      required BingxFuturesOpenOrder order,
      required String placementOperationId,
      required String effectOperationId,
      required BingxFuturesApiCredentials credentials,
      required String stateHome,
      BingxHttpRequestSender? requestSender,
      DateTime Function()? nowUtc,
      int Function()? clockMs,
    });

Future<String> recoverOneDeterministicOrder({
  required Map<String, String> options,
  required List<int> runnerSeedBytes,
  required AuthorizedExactOrderReconciler reconcileExactOrder,
  BingxHttpRequestSender? requestSender,
  DateTime Function()? nowUtc,
  int Function()? clockMs,
}) async {
  final admissionBytes = await _readBoundedFile(
    _required(options, 'deterministic-admission-file'),
    BingxFuturesRemoteMandateAdmission.maxWireBytes,
  );
  final admission =
      await BingxFuturesRemoteMandateAdmission.parseAndVerifyAsync(
        untrustedWireBytes: admissionBytes,
        verifySignature:
            ({
              required messageHashHex,
              required participantIdHex,
              required signatureHex,
            }) async => Ed25519().verify(
              _decodeHex(messageHashHex),
              signature: Signature(
                _decodeHex(signatureHex),
                publicKey: SimplePublicKey(
                  _decodeHex(participantIdHex),
                  type: KeyPairType.ed25519,
                ),
              ),
            ),
      );
  if (admission == null || !admission.isDeterministicSession) {
    throw const FormatException('deterministic recovery admission is invalid');
  }
  final cycleIndex = _requiredInt(options, 'session-cycle-index');
  final operationId = admission.deterministicCycleOperationId(cycleIndex);
  if (operationId == null) {
    throw const FormatException('deterministic recovery identity is invalid');
  }
  final signingKey = await Ed25519().newKeyPairFromSeed(runnerSeedBytes);
  final runnerPublicKey = await signingKey.extractPublicKey();
  if (sha256.convert(runnerPublicKey.bytes).toString() !=
      admission.runnerKeyId) {
    throw const FormatException('runner identity mismatch');
  }
  final credentials = await readExchangeCredentialFile(
    _required(options, 'deterministic-credential-file'),
  );
  final stateHome = _required(options, 'deterministic-state-home');
  if (!Directory(stateHome).isAbsolute) {
    throw const FormatException('deterministic state home must be absolute');
  }
  return reconcileExactOrder(
    admission: admission,
    effectOperationId: operationId,
    credentials: credentials,
    stateHome: stateHome,
    requestSender: requestSender,
    nowUtc: nowUtc,
    clockMs: clockMs,
  );
}

Future<String> runOneDeterministicOrder({
  required Map<String, String> options,
  required List<int> runnerSeedBytes,
  required AuthorizedExactOrderExecutor executeExactOrder,
  AuthorizedManagedOrderCanceler? cancelManagedOrder,
  BingxHttpRequestSender? requestSender,
  DateTime Function()? nowUtc,
  int Function()? clockMs,
}) async {
  final admissionBytes = await _readBoundedFile(
    _required(options, 'deterministic-admission-file'),
    BingxFuturesRemoteMandateAdmission.maxWireBytes,
  );
  final admission =
      await BingxFuturesRemoteMandateAdmission.parseAndVerifyAsync(
        untrustedWireBytes: admissionBytes,
        verifySignature:
            ({
              required messageHashHex,
              required participantIdHex,
              required signatureHex,
            }) async => Ed25519().verify(
              _decodeHex(messageHashHex),
              signature: Signature(
                _decodeHex(signatureHex),
                publicKey: SimplePublicKey(
                  _decodeHex(participantIdHex),
                  type: KeyPairType.ed25519,
                ),
              ),
            ),
      );
  if (admission == null || !admission.isDeterministicOrder) {
    if (admission == null || !admission.isDeterministicSession) {
      throw const FormatException('deterministic order admission is invalid');
    }
  }
  final cycleIndex =
      admission.isDeterministicSession
          ? _requiredInt(options, 'session-cycle-index')
          : 0;
  final cycleOperationId = admission.deterministicCycleOperationId(cycleIndex);
  if (cycleOperationId == null) {
    throw const FormatException('deterministic cycle identity is invalid');
  }

  final signingKey = await Ed25519().newKeyPairFromSeed(runnerSeedBytes);
  final runnerPublicKey = await signingKey.extractPublicKey();
  if (sha256.convert(runnerPublicKey.bytes).toString() !=
      admission.runnerKeyId) {
    throw const FormatException('runner identity mismatch');
  }
  final credentials = await readExchangeCredentialFile(
    _required(options, 'deterministic-credential-file'),
  );
  final accountBinding =
      sha256.convert(utf8.encode(credentials.apiKey)).toString();
  if (accountBinding != admission.mandate.accountBindingHashHex) {
    throw const FormatException('exchange account binding mismatch');
  }
  final stateHome = _required(options, 'deterministic-state-home');
  if (!Directory(stateHome).isAbsolute) {
    throw const FormatException('deterministic state home must be absolute');
  }
  final now = (nowUtc ?? () => DateTime.now().toUtc())().toUtc();
  if (!admission.mandate.isActiveAt(now)) {
    throw const FormatException('deterministic authority is not active');
  }

  final exchange = BingxFuturesExchangeService(
    requestSender: requestSender,
    clockMs: clockMs,
  );
  final fileStore = CapsuleFileStore(
    dirs: UserVisibleDataDirectoryService(homeOverride: stateHome),
  );
  final riskHistory = BingxFuturesRiskHistoryService(
    readActiveCapsuleRootHex: () => admission.mandate.capsuleRootHex,
    fileStore: fileStore,
  );
  final riskObservedAt = now;
  if (admission.isLegacyDeterministicSession) {
    return _blocked(cycleOperationId, 'session_contract_upgrade_required');
  }
  if (admission.strategyPolicy?['strategy_version'] !=
      bingxLiquidityStrategyVersion) {
    return _blocked(
      cycleOperationId,
      'strategy_authorization_upgrade_required',
    );
  }
  final requiredExposureScope =
      admission.isDeterministicSession
          ? BingxFuturesRemoteMandateAdmission.exposureReadScope
          : BingxFuturesRemoteMandateAdmission.legacyExposureReadScope;
  if (jsonEncode(admission.strategyPolicy?['account_read_scope']) !=
      jsonEncode(requiredExposureScope)) {
    return _blocked(cycleOperationId, 'exposure_read_authority_missing');
  }
  var activeOrders = const <BingxFuturesOpenOrder>[];
  if (admission.isDeterministicSession) {
    final openOrders = await exchange.getOpenOrders(
      credentials: credentials,
      symbol: admission.mandate.symbol,
    );
    if (!openOrders.isSuccess) {
      return _blocked(cycleOperationId, 'open_orders_unavailable');
    }
    activeOrders = openOrders.orders
        .where(
          (order) => order.symbol.toUpperCase() == admission.mandate.symbol,
        )
        .toList(growable: false);
  }
  final risk = await const BingxFuturesExchangeRiskInputService().read(
    exposureSymbol: admission.mandate.symbol,
    exchangeService: exchange,
    riskHistoryService: riskHistory,
    credentials: credentials,
    nowUtc: riskObservedAt,
  );
  final rulesResult = await exchange.getPerpetualContractRules(
    symbol: admission.mandate.symbol,
  );
  if (!rulesResult.isSuccess || rulesResult.rules == null) {
    return _blocked(cycleOperationId, 'contract_rules_unavailable');
  }
  final policy = admission.strategyPolicy!;
  final evidenceBytes = await _readBoundedFile(
    _required(options, 'market-evidence-file'),
    _maxEvidenceBytes,
  );
  final candidate = await BingxFuturesRemoteOrderCandidateService(
    sizing: BingxFuturesOrderSizingService(exchange: exchange),
  ).compose(
    untrustedMarketEvidenceBytes: evidenceBytes,
    trustedRunnerKey: runnerPublicKey,
    lastAcceptedSequence: _requiredInt(options, 'last-accepted-sequence'),
    lastAcceptedEvidenceHashHex: _requiredHex64(
      options,
      'last-accepted-evidence-hash',
    ),
    expectedRunnerBuildId: policy['runner_build_id'] as String,
    expectedPluginId: policy['plugin_id'] as String,
    expectedPluginVersion: policy['plugin_version'] as String,
    expectedPackageDigestHex: policy['package_digest_hex'] as String,
    expectedHostAbi: policy['host_abi'] as String,
    mandate: admission.mandate,
    accountRisk: risk,
    accountRiskObservedAtUtc: riskObservedAt,
    contractRules: rulesResult.rules!,
    nowUtc: now,
    stopLossPercent: policy['stop_loss_percent'] as double,
    minimumRiskReward: policy['minimum_risk_reward'] as double,
  );
  if (activeOrders.isNotEmpty) {
    final ownership = await _managedActiveOrder(
      admission: admission,
      activeOrders: activeOrders,
      stateHome: stateHome,
    );
    if (ownership.order == null || ownership.placementOperationId == null) {
      return _blocked(cycleOperationId, ownership.reasonCode);
    }
    final anchor = await _revalidateManagedAnchor(
      options: options,
      admission: admission,
      runnerKey: runnerPublicKey,
      order: ownership.order!,
      placementOperationId: ownership.placementOperationId!,
      exchange: exchange,
      now: now,
    );
    if (!const {
      'anchor_valid',
      'anchor_consumed',
      'anchor_expired',
    }.contains(anchor)) {
      return _blocked(
        cycleOperationId,
        'managed_order_revalidation_unavailable',
      );
    }
    if (anchor == 'anchor_valid') {
      return _blocked(cycleOperationId, 'managed_order_active');
    }
    if (cancelManagedOrder == null) {
      return _blocked(
        cycleOperationId,
        'managed_order_cancellation_unavailable',
      );
    }
    return cancelManagedOrder(
      admission: admission,
      order: ownership.order!,
      placementOperationId: ownership.placementOperationId!,
      effectOperationId: cycleOperationId,
      credentials: credentials,
      stateHome: stateHome,
      requestSender: requestSender,
      nowUtc: () => now,
      clockMs: clockMs,
    );
  }
  if (candidate.status != BingxFuturesRemoteOrderCandidateStatus.ready) {
    return _blocked(cycleOperationId, candidate.reasonCode);
  }
  final intent = candidate.toExactOrderIntent(nowUtc: now);
  if (intent == null) {
    return _blocked(cycleOperationId, 'order_candidate_invalid');
  }
  return executeExactOrder(
    admission: admission,
    exactOrder: intent.toExactOrderJson(testOrder: admission.mandate.testOrder),
    effectOperationId: cycleOperationId,
    credentials: credentials,
    stateHome: stateHome,
    requestSender: requestSender,
    nowUtc: () => now,
    clockMs: clockMs,
  );
}

String _blocked(String operationId, String reasonCode) =>
    jsonEncode(<String, dynamic>{
      'contract_version': 'hivra-trading-deterministic-cycle-evidence-v1',
      'operation_id': operationId,
      'state': 'blocked',
      'reason_code': reasonCode,
      'effect': false,
    });

Future<String> _revalidateManagedAnchor({
  required Map<String, String> options,
  required BingxFuturesRemoteMandateAdmission admission,
  required SimplePublicKey runnerKey,
  required BingxFuturesOpenOrder order,
  required String placementOperationId,
  required BingxFuturesExchangeService exchange,
  required DateTime now,
}) async {
  try {
    if (options['original-market-operation-id'] != placementOperationId ||
        num.tryParse(order.executedQuantityDecimal ?? '') != 0) {
      return 'anchor_unavailable';
    }
    const harness = BingxFuturesDeterministicReplayHarnessService();
    final original = harness.parseShadowEvidence(
      await _readBoundedFile(
        _required(options, 'original-market-evidence-file'),
        _maxEvidenceBytes,
      ),
    );
    final policy = admission.strategyPolicy!;
    if (!await harness.authenticateShadowEvidence(
          evidence: original,
          trustedRunnerKey: runnerKey,
        ) ||
        original.runnerKeyId != admission.runnerKeyId ||
        original.marketSymbol != admission.mandate.symbol ||
        original.marketProposalStatus != 'READY' ||
        original.policyHashHex != harness.publicStrategyPolicyHashHex() ||
        original.observedAtEpochMs > now.millisecondsSinceEpoch ||
        original.runnerBuildId != policy['runner_build_id'] ||
        original.packageDigestHex != policy['package_digest_hex'] ||
        original.pluginId != policy['plugin_id'] ||
        original.pluginVersion != policy['plugin_version'] ||
        original.hostAbi != policy['host_abi']) {
      return 'anchor_unavailable';
    }
    final proposal =
        jsonDecode(original.marketProposalJson!) as Map<String, dynamic>;
    final zone = proposal['zone'] as Map<String, dynamic>;
    final eventId = zone['liquidity_event_id'] as String;
    final side = proposal['side'] as String;
    if (order.clientOrderId != 'hivra-${eventId.substring(0, 32)}' ||
        order.side.toLowerCase() != side) {
      return 'anchor_unavailable';
    }
    final bars = await const BingxFuturesLiveSnapshotBuilderService()
        .loadMicroHistory(
          exchange: exchange,
          symbol: admission.mandate.symbol,
          fromUtc: DateTime.parse(
            (zone['parent'] as Map<String, dynamic>?)?['confirmed_at_utc']
                    as String? ??
                zone['liquidity_event_at_utc'] as String,
          ),
          observedAtUtc: now,
        );
    return const BingxFuturesZoneDecisionService().revalidateAnchor(
      parentZone: zone['parent'] as Map<String, dynamic>?,
      side: side,
      source: zone['anchor_source'] as String,
      zoneLow: num.parse(zone['low_decimal'] as String),
      zoneHigh: num.parse(zone['high_decimal'] as String),
      eventAtUtc: DateTime.parse(zone['liquidity_event_at_utc'] as String),
      nowUtc: now,
      candles: bars,
    );
  } on Object {
    return 'anchor_unavailable';
  }
}

Future<
  ({
    String reasonCode,
    BingxFuturesOpenOrder? order,
    String? placementOperationId,
  })
>
_managedActiveOrder({
  required BingxFuturesRemoteMandateAdmission admission,
  required List<BingxFuturesOpenOrder> activeOrders,
  required String stateHome,
}) async {
  if (activeOrders.length != 1) {
    return (
      reasonCode: 'order_ownership_unavailable',
      order: null,
      placementOperationId: null,
    );
  }
  try {
    final effects = ExternalEffectService(
      readActiveCapsuleRootHex: () => admission.mandate.capsuleRootHex,
      resolveAdapter: (_) => null,
      fileStore: CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: stateHome),
      ),
    );
    final cycleOperationIds = <String>{
      for (var index = 0; index < admission.authorizedUses; index += 1)
        admission.deterministicCycleOperationId(index)!,
    };
    final managedOperations = <String, String>{};
    for (final operation in await effects.list(
      pluginId: bingxFuturesTradingPluginId,
    )) {
      if (!cycleOperationIds.contains(operation.operationId) ||
          operation.ownerCapsuleHex != admission.mandate.capsuleRootHex ||
          operation.providerId !=
              BingxFuturesExternalEffectAdapter.providerId ||
          operation.accountBindingId !=
              admission.mandate.accountBindingHashHex ||
          operation.effectKind !=
              BingxFuturesExternalEffectAdapter.exactOrderEffectKind ||
          operation.approvalEvidenceHashHex != admission.commitmentHashHex ||
          operation.state != ExternalEffectState.succeeded ||
          operation.receipt == null) {
        continue;
      }
      final decoded = jsonDecode(operation.canonicalPayloadJson);
      if (decoded is! Map<String, dynamic>) {
        return (
          reasonCode: 'order_ownership_unavailable',
          order: null,
          placementOperationId: null,
        );
      }
      final payload = BingxFuturesIntentPayload.fromPluginResult(decoded);
      final receiptOrderId = operation.receipt!.providerReceiptId.trim();
      if (payload.symbol == admission.mandate.symbol &&
          receiptOrderId.isNotEmpty &&
          (operation.providerReferenceId == null ||
              operation.providerReferenceId == receiptOrderId)) {
        managedOperations['${payload.clientOrderId}|$receiptOrderId'] =
            operation.operationId;
      }
    }
    final order = activeOrders.single;
    final clientOrderId = order.clientOrderId?.trim() ?? '';
    final placementOperationId =
        managedOperations['$clientOrderId|${order.orderId}'];
    if (clientOrderId.isEmpty || placementOperationId == null) {
      return (
        reasonCode: 'external_order_active',
        order: null,
        placementOperationId: null,
      );
    }
    return (
      reasonCode: 'managed_order_active',
      order: order,
      placementOperationId: placementOperationId,
    );
  } on Object {
    return (
      reasonCode: 'order_ownership_unavailable',
      order: null,
      placementOperationId: null,
    );
  }
}

Future<List<int>> _readBoundedFile(String path, int maxBytes) async {
  final file = File(path);
  if (!file.isAbsolute ||
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > maxBytes) {
    throw const FormatException('bounded input file is invalid');
  }
  return file.readAsBytes();
}

Map<String, String> parseDeterministicOrderArgs(List<String> args) {
  const allowed = <String>{
    'mode',
    'runner-seed-file',
    'deterministic-admission-file',
    'market-evidence-file',
    'original-market-evidence-file',
    'original-market-operation-id',
    'deterministic-credential-file',
    'deterministic-state-home',
    'last-accepted-sequence',
    'last-accepted-evidence-hash',
    'session-cycle-index',
  };
  final parsed = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (!argument.startsWith('--') ||
        index + 1 >= args.length ||
        args[index + 1].startsWith('--')) {
      throw FormatException('invalid argument: $argument');
    }
    final key = argument.substring(2);
    if (!allowed.contains(key) || parsed.containsKey(key)) {
      throw FormatException('unsupported or duplicate argument: $argument');
    }
    parsed[key] = args[++index];
  }
  const required = <String>{
    'mode',
    'runner-seed-file',
    'deterministic-admission-file',
    'market-evidence-file',
    'deterministic-credential-file',
    'deterministic-state-home',
    'last-accepted-sequence',
    'last-accepted-evidence-hash',
  };
  if (parsed['mode'] != deterministicOrderMode ||
      required.any((key) => (parsed[key]?.trim() ?? '').isEmpty) ||
      (parsed.containsKey('session-cycle-index') &&
          parsed['session-cycle-index']!.trim().isEmpty)) {
    throw const FormatException('deterministic order options are incomplete');
  }
  return parsed;
}

Map<String, String> parseDeterministicRecoveryArgs(List<String> args) {
  const allowed = <String>{
    'mode',
    'runner-seed-file',
    'deterministic-admission-file',
    'deterministic-credential-file',
    'deterministic-state-home',
    'session-cycle-index',
  };
  final parsed = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (!argument.startsWith('--') ||
        index + 1 >= args.length ||
        args[index + 1].startsWith('--')) {
      throw FormatException('invalid argument: $argument');
    }
    final key = argument.substring(2);
    if (!allowed.contains(key) || parsed.containsKey(key)) {
      throw FormatException('unsupported or duplicate argument: $argument');
    }
    parsed[key] = args[++index];
  }
  if (parsed['mode'] != deterministicOrderRecoveryMode ||
      allowed.any((key) => (parsed[key]?.trim() ?? '').isEmpty)) {
    throw const FormatException(
      'deterministic recovery options are incomplete',
    );
  }
  return parsed;
}

String _required(Map<String, String> options, String key) {
  final value = options[key]?.trim() ?? '';
  if (value.isEmpty) throw FormatException('missing --$key');
  return value;
}

String _requiredHex64(Map<String, String> options, String key) {
  final value = _required(options, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('--$key must be 64-character lowercase hex');
  }
  return value;
}

int _requiredInt(Map<String, String> options, String key) {
  final value = _required(options, key);
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
    throw FormatException('--$key must be a decimal integer');
  }
  return int.parse(value);
}

List<int> _decodeHex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
    throw const FormatException('invalid lowercase hex');
  }
  return List<int>.generate(
    value.length ~/ 2,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
    growable: false,
  );
}
