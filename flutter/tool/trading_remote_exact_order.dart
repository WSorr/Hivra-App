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

Future<void> main(List<String> args) async {
  try {
    if (_requestedMode(args) == deterministicOrderMode) {
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
  final accountBinding =
      sha256.convert(utf8.encode(credentials.apiKey)).toString();
  if (accountBinding != admission.mandate.accountBindingHashHex) {
    throw const FormatException('exchange account binding mismatch');
  }
  final now = nowUtc ?? () => DateTime.now().toUtc();
  final adapter = BingxFuturesExternalEffectAdapter(
    exchange: BingxFuturesExchangeService(
      requestSender: requestSender,
      clockMs: clockMs,
    ),
    credentials: credentials,
    accountBindingId: accountBinding,
    clock: now,
  );
  final effects = ExternalEffectService(
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
  );
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
  return jsonEncode(<String, dynamic>{
    'contract_version': 'hivra-trading-exact-order-evidence-v1',
    'operation_id': operation.operationId,
    'state': operation.state.wireName,
    'attempt_count': operation.attemptCount,
    'provider_reference_id':
        operation.providerReferenceId ?? operation.receipt?.providerReceiptId,
    'receipt_evidence_hash_hex': operation.receipt?.evidenceHashHex,
    'test_order': admission.mandate.testOrder,
  });
}

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
