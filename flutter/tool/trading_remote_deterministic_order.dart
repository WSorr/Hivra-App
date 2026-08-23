import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_risk_input_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_order_sizing_service.dart';
import 'package:hivra_app/services/bingx_futures_remote_order_candidate_service.dart';
import 'package:hivra_app/services/bingx_futures_risk_history_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

import 'trading_remote_shadow_probe.dart' show readExchangeCredentialFile;

const String deterministicOrderMode = 'deterministic-order';
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

Future<String> runOneDeterministicOrder({
  required Map<String, String> options,
  required List<int> runnerSeedBytes,
  required AuthorizedExactOrderExecutor executeExactOrder,
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
    throw const FormatException('deterministic order admission is invalid');
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
  final risk = await const BingxFuturesExchangeRiskInputService().read(
    exchangeService: exchange,
    riskHistoryService: riskHistory,
    credentials: credentials,
    nowUtc: riskObservedAt,
  );
  final rulesResult = await exchange.getPerpetualContractRules(
    symbol: admission.mandate.symbol,
  );
  if (!rulesResult.isSuccess || rulesResult.rules == null) {
    return _blocked(admission.operationId, 'contract_rules_unavailable');
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
  if (candidate.status != BingxFuturesRemoteOrderCandidateStatus.ready) {
    return _blocked(admission.operationId, candidate.reasonCode);
  }
  final intent = candidate.toExactOrderIntent(nowUtc: now);
  if (intent == null) {
    return _blocked(admission.operationId, 'order_candidate_invalid');
  }
  return executeExactOrder(
    admission: admission,
    exactOrder: intent.toExactOrderJson(testOrder: admission.mandate.testOrder),
    effectOperationId: admission.operationId,
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
    'deterministic-credential-file',
    'deterministic-state-home',
    'last-accepted-sequence',
    'last-accepted-evidence-hash',
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
  if (parsed['mode'] != deterministicOrderMode ||
      allowed.any((key) => (parsed[key]?.trim() ?? '').isEmpty)) {
    throw const FormatException('deterministic order options are incomplete');
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
