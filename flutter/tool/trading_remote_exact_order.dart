import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

import 'trading_remote_deterministic_order.dart';
import 'trading_remote_shadow_probe.dart'
    show readExchangeCredentialFile, readRunnerSeedBytes;

const String exactOrderMode = 'exact-order';
const String completedSessionEffectsMode = 'completed-session-effects';

Future<void> main(List<String> args) async {
  try {
    final requestedMode = _requestedMode(args);
    if (requestedMode == completedSessionEffectsMode) {
      stdout.writeln(
        await exportCompletedDeterministicSessionEffects(
          options: _parseCompletedSessionEffectsArgs(args),
        ),
      );
      return;
    }
    if (requestedMode == deterministicOrderRecoveryMode) {
      final options = parseDeterministicRecoveryArgs(args);
      final seedBytes = await readRunnerSeedBytes(options);
      stdout.writeln(
        await recoverOneDeterministicOrder(
          options: options,
          runnerSeedBytes: seedBytes,
          reconcileExactOrder: reconcileAuthorizedExactOrder,
        ),
      );
      return;
    }
    if (requestedMode == deterministicOrderMode) {
      final options = parseDeterministicOrderArgs(args);
      final seedBytes = await readRunnerSeedBytes(options);
      stdout.writeln(
        await runOneDeterministicOrder(
          options: options,
          runnerSeedBytes: seedBytes,
          executeExactOrder: runAuthorizedExactOrder,
        ),
      );
      return;
    }
    final options = _parseExactOrderArgs(args);
    final seedBytes = await readRunnerSeedBytes(options);
    stdout.writeln(
      await runMandateBoundExactOrder(
        options: options,
        runnerSeedBytes: seedBytes,
      ),
    );
  } on Object {
    stderr.writeln('trading exact order failed');
    exitCode = 1;
  }
}

Future<String> exportCompletedDeterministicSessionEffects({
  required Map<String, String> options,
}) async {
  final expectedRunnerKeyId = _requiredHex64(options, 'expected-runner-key-id');
  final admissionFile = File(
    _required(options, 'deterministic-admission-file'),
  );
  if (!admissionFile.isAbsolute ||
      FileSystemEntity.typeSync(admissionFile.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await admissionFile.length() >
          BingxFuturesRemoteMandateAdmission.maxWireBytes) {
    throw const FormatException('completed session admission file is invalid');
  }
  final admission =
      await BingxFuturesRemoteMandateAdmission.parseAndVerifyAsync(
        untrustedWireBytes: await admissionFile.readAsBytes(),
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
  if (admission == null ||
      !admission.isDeterministicSession ||
      admission.runnerKeyId != expectedRunnerKeyId) {
    throw const FormatException('completed session authority is invalid');
  }
  if (admission.mandate.testOrder) return '[]';
  final stateHome = _required(options, 'deterministic-state-home');
  if (!Directory(stateHome).isAbsolute) {
    throw const FormatException(
      'completed session state home must be absolute',
    );
  }
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
  final completed = <ExternalEffectOperation>[];
  for (final operation in await effects.list(
    pluginId: bingxFuturesTradingPluginId,
  )) {
    final related =
        cycleOperationIds.contains(operation.operationId) ||
        operation.approvalEvidenceHashHex == admission.operationId;
    if (!related) continue;
    _validateCompletedSessionOperation(
      operation: operation,
      admission: admission,
      cycleOperationIds: cycleOperationIds,
    );
    if (operation.state == ExternalEffectState.succeeded) {
      completed.add(operation);
    }
  }
  if (completed.length > admission.mandate.maxEffects) {
    throw const FormatException(
      'completed session effect count exceeds authority',
    );
  }
  completed.sort(
    (left, right) => left.operationId.compareTo(right.operationId),
  );
  return jsonEncode(
    completed.map((operation) => operation.toJson()).toList(growable: false),
  );
}

void _validateCompletedSessionOperation({
  required ExternalEffectOperation operation,
  required BingxFuturesRemoteMandateAdmission admission,
  required Set<String> cycleOperationIds,
}) {
  if (!cycleOperationIds.contains(operation.operationId) ||
      operation.ownerCapsuleHex != admission.mandate.capsuleRootHex ||
      operation.pluginId != bingxFuturesTradingPluginId ||
      operation.providerId != BingxFuturesExternalEffectAdapter.providerId ||
      operation.accountBindingId != admission.mandate.accountBindingHashHex ||
      operation.effectKind !=
          BingxFuturesExternalEffectAdapter.exactOrderEffectKind ||
      operation.approvalEvidenceHashHex != admission.operationId) {
    throw const FormatException('completed session effect binding is invalid');
  }
  final decoded = jsonDecode(operation.canonicalPayloadJson);
  if (decoded is! Map<String, dynamic> ||
      decoded['test_order'] is! bool ||
      decoded['test_order'] != admission.mandate.testOrder) {
    throw const FormatException('completed session effect payload is invalid');
  }
  final payload = BingxFuturesIntentPayload.fromPluginResult(decoded);
  if (payload.symbol != admission.mandate.symbol ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(payload.intentHashHex ?? '') ||
      jsonEncode(
            payload.toExactOrderJson(testOrder: admission.mandate.testOrder),
          ) !=
          operation.canonicalPayloadJson) {
    throw const FormatException('completed session effect payload is invalid');
  }
  if (operation.state == ExternalEffectState.succeeded &&
      (operation.receipt == null ||
          (operation.providerReferenceId != null &&
              operation.providerReferenceId !=
                  operation.receipt!.providerReceiptId))) {
    throw const FormatException('completed session receipt binding is invalid');
  }
}

String? _requestedMode(List<String> args) {
  for (var index = 0; index + 1 < args.length; index++) {
    if (args[index] == '--mode') return args[index + 1];
  }
  return null;
}

Future<String> runMandateBoundExactOrder({
  required Map<String, String> options,
  required List<int> runnerSeedBytes,
  BingxHttpRequestSender? requestSender,
  DateTime Function()? nowUtc,
  int Function()? clockMs,
}) async {
  final expectedRunnerKeyId = _requiredHex64(options, 'expected-runner-key-id');
  final admissionFile = File(_required(options, 'exact-order-admission-file'));
  if (!admissionFile.isAbsolute ||
      FileSystemEntity.typeSync(admissionFile.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await admissionFile.length() >
          BingxFuturesRemoteMandateAdmission.maxWireBytes) {
    throw const FormatException('exact order admission file is invalid');
  }
  final admission =
      await BingxFuturesRemoteMandateAdmission.parseAndVerifyAsync(
        untrustedWireBytes: await admissionFile.readAsBytes(),
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
  if (admission == null || !admission.isExactOrder) {
    throw const FormatException('exact order admission is invalid');
  }

  final signingKey = await Ed25519().newKeyPairFromSeed(runnerSeedBytes);
  final publicKey = await signingKey.extractPublicKey();
  if (sha256.convert(publicKey.bytes).toString() != expectedRunnerKeyId ||
      admission.runnerKeyId != expectedRunnerKeyId) {
    throw const FormatException('runner identity mismatch');
  }
  final credentials = await readExchangeCredentialFile(
    _required(options, 'exact-order-credential-file'),
  );
  final accountBinding =
      sha256.convert(utf8.encode(credentials.apiKey)).toString();
  if (accountBinding != admission.mandate.accountBindingHashHex) {
    throw const FormatException('exchange account binding mismatch');
  }

  final stateHome = _required(options, 'exact-order-state-home');
  if (!Directory(stateHome).isAbsolute) {
    throw const FormatException('exact order state home must be absolute');
  }
  final effectOperationId =
      admission.exactOrder!['intent_hash_hex']
          ?.toString()
          .trim()
          .toLowerCase() ??
      '';
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(effectOperationId)) {
    throw const FormatException('exact order intent identity is invalid');
  }
  return runAuthorizedExactOrder(
    admission: admission,
    exactOrder: admission.exactOrder!,
    effectOperationId: effectOperationId,
    credentials: credentials,
    stateHome: stateHome,
    requestSender: requestSender,
    nowUtc: nowUtc,
    clockMs: clockMs,
  );
}

Future<String> runAuthorizedExactOrder({
  required BingxFuturesRemoteMandateAdmission admission,
  required Map<String, dynamic> exactOrder,
  required String effectOperationId,
  required BingxFuturesApiCredentials credentials,
  required String stateHome,
  BingxHttpRequestSender? requestSender,
  DateTime Function()? nowUtc,
  int Function()? clockMs,
}) async {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(effectOperationId) ||
      !Directory(stateHome).isAbsolute) {
    throw const FormatException('authorized exact order state is invalid');
  }
  final normalizedOrder =
      BingxFuturesRemoteMandateAdmission.issueExactOrder(
        mandate: admission.mandate,
        runnerKeyId: admission.runnerKeyId,
        exactOrder: exactOrder,
        signCommitment: (_) => '0' * 128,
      )?.exactOrder;
  if (normalizedOrder == null) {
    throw const FormatException('authorized exact order is invalid');
  }
  final now = nowUtc ?? () => DateTime.now().toUtc();
  final context = _authorizedEffectContext(
    admission: admission,
    credentials: credentials,
    stateHome: stateHome,
    requestSender: requestSender,
    now: now,
    clockMs: clockMs,
  );
  final accountBinding = context.accountBinding;
  final effects = context.effects;
  ExternalEffectOperation? existing;
  for (final operation in await effects.list(
    pluginId: bingxFuturesTradingPluginId,
  )) {
    if (operation.operationId == effectOperationId) {
      existing = operation;
      break;
    }
  }
  if (existing == null && !admission.mandate.isActiveAt(now().toUtc())) {
    throw const FormatException('exact order authority is not active');
  }
  var operation = await effects.prepare(
    operationId: effectOperationId,
    pluginId: bingxFuturesTradingPluginId,
    providerId: BingxFuturesExternalEffectAdapter.providerId,
    accountBindingId: accountBinding,
    effectKind: BingxFuturesExternalEffectAdapter.exactOrderEffectKind,
    canonicalPayloadJson: jsonEncode(normalizedOrder),
  );
  if (operation.state == ExternalEffectState.prepared) {
    if (!admission.mandate.isActiveAt(now().toUtc())) {
      throw const FormatException('exact order authority expired before queue');
    }
    operation = await effects.approve(
      pluginId: bingxFuturesTradingPluginId,
      operationId: effectOperationId,
      approvalEvidenceHashHex: admission.commitmentHashHex,
    );
  }
  if (operation.state == ExternalEffectState.approved) {
    if (!admission.mandate.isActiveAt(now().toUtc())) {
      throw const FormatException('exact order authority expired before queue');
    }
    operation = await effects.enqueue(
      pluginId: bingxFuturesTradingPluginId,
      operationId: effectOperationId,
    );
  }
  if (operation.state == ExternalEffectState.queued &&
      !admission.mandate.isActiveAt(now().toUtc())) {
    throw const FormatException(
      'exact order authority expired before delivery',
    );
  }
  operation = await effects.process(
    pluginId: bingxFuturesTradingPluginId,
    operationId: effectOperationId,
  );
  return _exactOrderEvidence(operation, admission.mandate.testOrder);
}

Future<String> reconcileAuthorizedExactOrder({
  required BingxFuturesRemoteMandateAdmission admission,
  required String effectOperationId,
  required BingxFuturesApiCredentials credentials,
  required String stateHome,
  BingxHttpRequestSender? requestSender,
  DateTime Function()? nowUtc,
  int Function()? clockMs,
}) async {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(effectOperationId) ||
      !Directory(stateHome).isAbsolute) {
    throw const FormatException('authorized exact order recovery is invalid');
  }
  final now = nowUtc ?? () => DateTime.now().toUtc();
  final context = _authorizedEffectContext(
    admission: admission,
    credentials: credentials,
    stateHome: stateHome,
    requestSender: requestSender,
    now: now,
    clockMs: clockMs,
  );
  ExternalEffectOperation? operation;
  for (final candidate in await context.effects.list(
    pluginId: bingxFuturesTradingPluginId,
  )) {
    if (candidate.operationId == effectOperationId) {
      operation = candidate;
      break;
    }
  }
  if (operation == null) {
    return _noEffectRecoveryEvidence(effectOperationId, 'absent');
  }
  if (operation.state == ExternalEffectState.delivering ||
      operation.state == ExternalEffectState.unresolved ||
      operation.state == ExternalEffectState.terminalFailure) {
    operation = await context.effects.reconcileOnly(
      pluginId: bingxFuturesTradingPluginId,
      operationId: effectOperationId,
    );
  }
  if (operation.attemptCount == 0) {
    return _noEffectRecoveryEvidence(effectOperationId, 'not_delivered');
  }
  return _exactOrderEvidence(operation, admission.mandate.testOrder);
}

String _noEffectRecoveryEvidence(String operationId, String state) =>
    jsonEncode(<String, dynamic>{
      'contract_version': 'hivra-trading-exact-order-recovery-v1',
      'operation_id': operationId,
      'state': state,
      'effect': false,
    });

({ExternalEffectService effects, String accountBinding})
_authorizedEffectContext({
  required BingxFuturesRemoteMandateAdmission admission,
  required BingxFuturesApiCredentials credentials,
  required String stateHome,
  required DateTime Function() now,
  BingxHttpRequestSender? requestSender,
  int Function()? clockMs,
}) {
  final accountBinding =
      sha256.convert(utf8.encode(credentials.apiKey)).toString();
  if (accountBinding != admission.mandate.accountBindingHashHex) {
    throw const FormatException('exchange account binding mismatch');
  }
  final adapter = BingxFuturesExternalEffectAdapter(
    exchange: BingxFuturesExchangeService(
      requestSender: requestSender,
      clockMs: clockMs,
    ),
    credentials: credentials,
    accountBindingId: accountBinding,
    clock: now,
  );
  return (
    effects: ExternalEffectService(
      readActiveCapsuleRootHex: () => admission.mandate.capsuleRootHex,
      resolveAdapter:
          (providerId) =>
              providerId == BingxFuturesExternalEffectAdapter.providerId
                  ? adapter
                  : null,
      fileStore: CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: stateHome),
      ),
      clock: now,
    ),
    accountBinding: accountBinding,
  );
}

String _exactOrderEvidence(ExternalEffectOperation operation, bool testOrder) =>
    jsonEncode(<String, dynamic>{
      'contract_version': 'hivra-trading-exact-order-evidence-v1',
      'operation_id': operation.operationId,
      'state': operation.state.wireName,
      'attempt_count': operation.attemptCount,
      'provider_reference_id':
          operation.providerReferenceId ?? operation.receipt?.providerReceiptId,
      'receipt_evidence_hash_hex': operation.receipt?.evidenceHashHex,
      'test_order': testOrder,
    });

Map<String, String> _parseExactOrderArgs(List<String> args) {
  const allowed = <String>{
    'mode',
    'runner-seed-file',
    'expected-runner-key-id',
    'exact-order-admission-file',
    'exact-order-credential-file',
    'exact-order-state-home',
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
  if (parsed['mode'] != exactOrderMode ||
      allowed.any((key) => (parsed[key]?.trim() ?? '').isEmpty)) {
    throw const FormatException('exact order options are incomplete');
  }
  return parsed;
}

Map<String, String> _parseCompletedSessionEffectsArgs(List<String> args) {
  const allowed = <String>{
    'mode',
    'expected-runner-key-id',
    'deterministic-admission-file',
    'deterministic-state-home',
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
  if (parsed['mode'] != completedSessionEffectsMode ||
      allowed.any((key) => (parsed[key]?.trim() ?? '').isEmpty)) {
    throw const FormatException(
      'completed session effect options are incomplete',
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
