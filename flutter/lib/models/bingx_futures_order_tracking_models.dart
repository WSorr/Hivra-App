import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bingx_futures_exchange_models.dart';

enum BingxLiquidityEventEffectClaimStatus { reserved, confirmed }

enum BingxManagedOrderLifecycleStatus {
  unresolved,
  active,
  filled,
  cancelled,
  rejected,
  expired,
}

enum BingxLiquidityEventEffectReservation {
  acquired,
  alreadyClaimed,
  unavailable,
}

class BingxFuturesTradingMandate {
  static const int schemaVersion = 1;

  final String mandateId;
  final String capsuleRootHex;
  final String accountBindingHashHex;
  final String symbol;
  final bool testOrder;
  final String issuedAtUtc;
  final String expiresAtUtc;
  final String maxOrderNotionalQuoteDecimal;
  final double maxRiskPerTradePercent;
  final double maxDailyLossPercent;
  final int maxConcurrentPositions;
  final int cooldownAfterLossStreak;
  final int cooldownMinutes;
  final int maxEffects;
  final String? revokedAtUtc;

  const BingxFuturesTradingMandate._({
    required this.mandateId,
    required this.capsuleRootHex,
    required this.accountBindingHashHex,
    required this.symbol,
    required this.testOrder,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required this.maxOrderNotionalQuoteDecimal,
    required this.maxRiskPerTradePercent,
    required this.maxDailyLossPercent,
    required this.maxConcurrentPositions,
    required this.cooldownAfterLossStreak,
    required this.cooldownMinutes,
    required this.maxEffects,
    required this.revokedAtUtc,
  });

  factory BingxFuturesTradingMandate.issue({
    required String capsuleRootHex,
    required String accountBindingHashHex,
    required String symbol,
    required bool testOrder,
    required DateTime issuedAtUtc,
    required DateTime expiresAtUtc,
    required String maxOrderNotionalQuoteDecimal,
    required double maxRiskPerTradePercent,
    required double maxDailyLossPercent,
    required int maxConcurrentPositions,
    required int cooldownAfterLossStreak,
    required int cooldownMinutes,
    required int maxEffects,
  }) {
    final fields = _normalizeFields(
      capsuleRootHex: capsuleRootHex,
      accountBindingHashHex: accountBindingHashHex,
      symbol: symbol,
      testOrder: testOrder,
      issuedAtUtc: issuedAtUtc.toUtc().toIso8601String(),
      expiresAtUtc: expiresAtUtc.toUtc().toIso8601String(),
      maxOrderNotionalQuoteDecimal: maxOrderNotionalQuoteDecimal,
      maxRiskPerTradePercent: maxRiskPerTradePercent,
      maxDailyLossPercent: maxDailyLossPercent,
      maxConcurrentPositions: maxConcurrentPositions,
      cooldownAfterLossStreak: cooldownAfterLossStreak,
      cooldownMinutes: cooldownMinutes,
      maxEffects: maxEffects,
    );
    return BingxFuturesTradingMandate._(
      mandateId: _deriveId(fields),
      capsuleRootHex: fields['capsule_root_hex']! as String,
      accountBindingHashHex: fields['account_binding_hash_hex']! as String,
      symbol: fields['symbol']! as String,
      testOrder: fields['test_order']! as bool,
      issuedAtUtc: fields['issued_at_utc']! as String,
      expiresAtUtc: fields['expires_at_utc']! as String,
      maxOrderNotionalQuoteDecimal:
          fields['max_order_notional_quote_decimal']! as String,
      maxRiskPerTradePercent: fields['max_risk_per_trade_percent']! as double,
      maxDailyLossPercent: fields['max_daily_loss_percent']! as double,
      maxConcurrentPositions: fields['max_concurrent_positions']! as int,
      cooldownAfterLossStreak: fields['cooldown_after_loss_streak']! as int,
      cooldownMinutes: fields['cooldown_minutes']! as int,
      maxEffects: fields['max_effects']! as int,
      revokedAtUtc: null,
    );
  }

  bool isActiveAt(DateTime nowUtc) {
    final issued = DateTime.tryParse(issuedAtUtc)?.toUtc();
    final expires = DateTime.tryParse(expiresAtUtc)?.toUtc();
    final now = nowUtc.toUtc();
    return revokedAtUtc == null &&
        issued != null &&
        expires != null &&
        !now.isBefore(issued) &&
        now.isBefore(expires);
  }

  BingxFuturesTradingMandate revoke(DateTime revokedAtUtc) {
    return BingxFuturesTradingMandate._(
      mandateId: mandateId,
      capsuleRootHex: capsuleRootHex,
      accountBindingHashHex: accountBindingHashHex,
      symbol: symbol,
      testOrder: testOrder,
      issuedAtUtc: issuedAtUtc,
      expiresAtUtc: expiresAtUtc,
      maxOrderNotionalQuoteDecimal: maxOrderNotionalQuoteDecimal,
      maxRiskPerTradePercent: maxRiskPerTradePercent,
      maxDailyLossPercent: maxDailyLossPercent,
      maxConcurrentPositions: maxConcurrentPositions,
      cooldownAfterLossStreak: cooldownAfterLossStreak,
      cooldownMinutes: cooldownMinutes,
      maxEffects: maxEffects,
      revokedAtUtc: revokedAtUtc.toUtc().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': schemaVersion,
    'mandate_id': mandateId,
    ..._semanticFields,
    'revoked_at_utc': revokedAtUtc,
  };

  static BingxFuturesTradingMandate? fromJsonMap(Map<String, dynamic> map) {
    const expectedKeys = <String>{
      'version',
      'mandate_id',
      'capsule_root_hex',
      'account_binding_hash_hex',
      'symbol',
      'test_order',
      'issued_at_utc',
      'expires_at_utc',
      'max_order_notional_quote_decimal',
      'max_risk_per_trade_percent',
      'max_daily_loss_percent',
      'max_concurrent_positions',
      'cooldown_after_loss_streak',
      'cooldown_minutes',
      'max_effects',
      'revoked_at_utc',
    };
    if (map.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(map.keys.toSet()).isNotEmpty ||
        map['test_order'] is! bool) {
      return null;
    }
    if (map['version'] != schemaVersion) return null;
    try {
      final maxConcurrentPositions = _readExactInt(
        map['max_concurrent_positions'],
      );
      final cooldownAfterLossStreak = _readExactInt(
        map['cooldown_after_loss_streak'],
      );
      final cooldownMinutes = _readExactInt(map['cooldown_minutes']);
      final maxEffects = _readExactInt(map['max_effects']);
      if (maxConcurrentPositions == null ||
          cooldownAfterLossStreak == null ||
          cooldownMinutes == null ||
          maxEffects == null) {
        return null;
      }
      final fields = _normalizeFields(
        capsuleRootHex: map['capsule_root_hex']?.toString() ?? '',
        accountBindingHashHex:
            map['account_binding_hash_hex']?.toString() ?? '',
        symbol: map['symbol']?.toString() ?? '',
        testOrder: map['test_order'] == true,
        issuedAtUtc: map['issued_at_utc']?.toString() ?? '',
        expiresAtUtc: map['expires_at_utc']?.toString() ?? '',
        maxOrderNotionalQuoteDecimal:
            map['max_order_notional_quote_decimal']?.toString() ?? '',
        maxRiskPerTradePercent:
            (map['max_risk_per_trade_percent'] as num?)?.toDouble() ?? 0,
        maxDailyLossPercent:
            (map['max_daily_loss_percent'] as num?)?.toDouble() ?? 0,
        maxConcurrentPositions: maxConcurrentPositions,
        cooldownAfterLossStreak: cooldownAfterLossStreak,
        cooldownMinutes: cooldownMinutes,
        maxEffects: maxEffects,
      );
      final mandateId =
          map['mandate_id']?.toString().trim().toLowerCase() ?? '';
      if (mandateId != _deriveId(fields)) return null;
      final revokedRaw = map['revoked_at_utc']?.toString().trim() ?? '';
      if (revokedRaw.isNotEmpty &&
          DateTime.tryParse(revokedRaw)?.isUtc != true) {
        return null;
      }
      return BingxFuturesTradingMandate._(
        mandateId: mandateId,
        capsuleRootHex: fields['capsule_root_hex']! as String,
        accountBindingHashHex: fields['account_binding_hash_hex']! as String,
        symbol: fields['symbol']! as String,
        testOrder: fields['test_order']! as bool,
        issuedAtUtc: fields['issued_at_utc']! as String,
        expiresAtUtc: fields['expires_at_utc']! as String,
        maxOrderNotionalQuoteDecimal:
            fields['max_order_notional_quote_decimal']! as String,
        maxRiskPerTradePercent: fields['max_risk_per_trade_percent']! as double,
        maxDailyLossPercent: fields['max_daily_loss_percent']! as double,
        maxConcurrentPositions: fields['max_concurrent_positions']! as int,
        cooldownAfterLossStreak: fields['cooldown_after_loss_streak']! as int,
        cooldownMinutes: fields['cooldown_minutes']! as int,
        maxEffects: fields['max_effects']! as int,
        revokedAtUtc: revokedRaw.isEmpty ? null : revokedRaw,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> get _semanticFields => _normalizeFields(
    capsuleRootHex: capsuleRootHex,
    accountBindingHashHex: accountBindingHashHex,
    symbol: symbol,
    testOrder: testOrder,
    issuedAtUtc: issuedAtUtc,
    expiresAtUtc: expiresAtUtc,
    maxOrderNotionalQuoteDecimal: maxOrderNotionalQuoteDecimal,
    maxRiskPerTradePercent: maxRiskPerTradePercent,
    maxDailyLossPercent: maxDailyLossPercent,
    maxConcurrentPositions: maxConcurrentPositions,
    cooldownAfterLossStreak: cooldownAfterLossStreak,
    cooldownMinutes: cooldownMinutes,
    maxEffects: maxEffects,
  );

  static Map<String, dynamic> _normalizeFields({
    required String capsuleRootHex,
    required String accountBindingHashHex,
    required String symbol,
    required bool testOrder,
    required String issuedAtUtc,
    required String expiresAtUtc,
    required String maxOrderNotionalQuoteDecimal,
    required double maxRiskPerTradePercent,
    required double maxDailyLossPercent,
    required int maxConcurrentPositions,
    required int cooldownAfterLossStreak,
    required int cooldownMinutes,
    required int maxEffects,
  }) {
    final owner = capsuleRootHex.trim().toLowerCase();
    final account = accountBindingHashHex.trim().toLowerCase();
    final normalizedSymbol = symbol.trim().toUpperCase();
    final issued = DateTime.tryParse(issuedAtUtc)?.toUtc();
    final expires = DateTime.tryParse(expiresAtUtc)?.toUtc();
    final maxNotional = double.tryParse(maxOrderNotionalQuoteDecimal.trim());
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(account) ||
        normalizedSymbol.isEmpty ||
        issued == null ||
        expires == null ||
        !expires.isAfter(issued) ||
        expires.difference(issued) > const Duration(hours: 24) ||
        maxNotional == null ||
        !maxNotional.isFinite ||
        maxNotional <= 0 ||
        !maxRiskPerTradePercent.isFinite ||
        maxRiskPerTradePercent <= 0 ||
        !maxDailyLossPercent.isFinite ||
        maxDailyLossPercent <= 0 ||
        maxConcurrentPositions <= 0 ||
        cooldownAfterLossStreak <= 0 ||
        cooldownMinutes < 0 ||
        maxEffects <= 0 ||
        maxEffects > 256) {
      throw const FormatException('Invalid bounded trading mandate');
    }
    return <String, dynamic>{
      'capsule_root_hex': owner,
      'account_binding_hash_hex': account,
      'symbol': normalizedSymbol,
      'test_order': testOrder,
      'issued_at_utc': issued.toIso8601String(),
      'expires_at_utc': expires.toIso8601String(),
      'max_order_notional_quote_decimal': _decimal(maxNotional),
      'max_risk_per_trade_percent': maxRiskPerTradePercent,
      'max_daily_loss_percent': maxDailyLossPercent,
      'max_concurrent_positions': maxConcurrentPositions,
      'cooldown_after_loss_streak': cooldownAfterLossStreak,
      'cooldown_minutes': cooldownMinutes,
      'max_effects': maxEffects,
    };
  }

  static String _deriveId(Map<String, dynamic> fields) =>
      sha256
          .convert(
            utf8.encode(
              'hivra:bingx-futures-trading-mandate:v1\n${jsonEncode(fields)}',
            ),
          )
          .toString();

  static String _decimal(double value) =>
      value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');

  static int? _readExactInt(Object? value) {
    if (value is! num || !value.isFinite || value != value.truncate()) {
      return null;
    }
    return value.toInt();
  }
}

class BingxFuturesRemoteMandateAdmission {
  static const String contractVersion = 'trading-remote-mandate-admission-v2';
  static const String exactOrderContractVersion =
      'trading-remote-mandate-admission-v3';
  static const String deterministicOrderContractVersion =
      'trading-remote-mandate-admission-v4';
  static const String deterministicSessionContractVersion =
      'trading-remote-mandate-admission-v5';
  static const String signatureSuite = 'ed25519-v1';
  static const String operationKind = 'account_read';
  static const String exactOrderOperationKind = 'one_exact_order';
  static const String deterministicOrderOperationKind =
      'one_deterministic_order';
  static const String deterministicSessionOperationKind =
      'bounded_deterministic_session';
  static const String deterministicRunnerBuildId = 'systemd-public-shadow-v1';
  static const String deterministicPluginId = 'hivra.bingx-futures-trading';
  static const String deterministicPluginVersion = '0.2.3';
  static const String deterministicPackageDigestHex =
      '2cb440885a2fa473971364fb26cce304d079d393832b2b5bed6fd95517e61889';
  static const String deterministicHostAbi = 'wasm32-wasi-preview1';
  static const List<String> accountReadScope = <String>[
    'balance',
    'positions',
    'open_orders',
  ];
  static const int maxUses = 1;
  static const int maxSessionCycles = 288;
  static const int maxWireBytes = 8192;

  final String operationId;
  final String commitmentHashHex;
  final String runnerKeyId;
  final BingxFuturesTradingMandate mandate;
  final Map<String, dynamic>? exactOrder;
  final Map<String, dynamic>? strategyPolicy;
  final Map<String, dynamic>? sessionPolicy;
  final String signatureHex;

  const BingxFuturesRemoteMandateAdmission._({
    required this.operationId,
    required this.commitmentHashHex,
    required this.runnerKeyId,
    required this.mandate,
    required this.exactOrder,
    required this.strategyPolicy,
    required this.sessionPolicy,
    required this.signatureHex,
  });

  static BingxFuturesRemoteMandateAdmission? issue({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
    required String? Function(String commitmentHashHex) signCommitment,
  }) {
    if (mandate.revokedAtUtc != null) return null;
    final normalizedRunnerKeyId = runnerKeyId.trim().toLowerCase();
    if (!_isSha256(normalizedRunnerKeyId)) return null;
    final commitmentHashHex = _deriveCommitmentHash(
      mandate: mandate,
      runnerKeyId: normalizedRunnerKeyId,
    );
    final signatureHex =
        signCommitment(commitmentHashHex)?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex)) return null;
    return BingxFuturesRemoteMandateAdmission._(
      operationId: commitmentHashHex,
      commitmentHashHex: commitmentHashHex,
      runnerKeyId: normalizedRunnerKeyId,
      mandate: mandate,
      exactOrder: null,
      strategyPolicy: null,
      sessionPolicy: null,
      signatureHex: signatureHex,
    );
  }

  static BingxFuturesRemoteMandateAdmission? issueExactOrder({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
    required Map<String, dynamic> exactOrder,
    required String? Function(String commitmentHashHex) signCommitment,
  }) {
    if (mandate.revokedAtUtc != null) return null;
    final normalizedRunnerKeyId = runnerKeyId.trim().toLowerCase();
    if (!_isSha256(normalizedRunnerKeyId)) return null;
    final normalizedOrder = _normalizeExactOrder(exactOrder, mandate);
    if (normalizedOrder == null) return null;
    final commitmentHashHex = _deriveExactOrderCommitmentHash(
      mandate: mandate,
      runnerKeyId: normalizedRunnerKeyId,
      exactOrder: normalizedOrder,
    );
    final signatureHex =
        signCommitment(commitmentHashHex)?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex)) return null;
    return BingxFuturesRemoteMandateAdmission._(
      operationId: commitmentHashHex,
      commitmentHashHex: commitmentHashHex,
      runnerKeyId: normalizedRunnerKeyId,
      mandate: mandate,
      exactOrder: normalizedOrder,
      strategyPolicy: null,
      sessionPolicy: null,
      signatureHex: signatureHex,
    );
  }

  static BingxFuturesRemoteMandateAdmission? issueDeterministicOrder({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
    required Map<String, dynamic> strategyPolicy,
    required String? Function(String commitmentHashHex) signCommitment,
  }) {
    if (mandate.revokedAtUtc != null) return null;
    final normalizedRunnerKeyId = runnerKeyId.trim().toLowerCase();
    if (!_isSha256(normalizedRunnerKeyId)) return null;
    final normalizedPolicy = _normalizeStrategyPolicy(strategyPolicy);
    if (normalizedPolicy == null) return null;
    final commitmentHashHex = _deriveDeterministicOrderCommitmentHash(
      mandate: mandate,
      runnerKeyId: normalizedRunnerKeyId,
      strategyPolicy: normalizedPolicy,
    );
    final signatureHex =
        signCommitment(commitmentHashHex)?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex)) return null;
    return BingxFuturesRemoteMandateAdmission._(
      operationId: commitmentHashHex,
      commitmentHashHex: commitmentHashHex,
      runnerKeyId: normalizedRunnerKeyId,
      mandate: mandate,
      exactOrder: null,
      strategyPolicy: normalizedPolicy,
      sessionPolicy: null,
      signatureHex: signatureHex,
    );
  }

  static BingxFuturesRemoteMandateAdmission? issueDeterministicSession({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
    required Map<String, dynamic> strategyPolicy,
    required DateTime startsAtUtc,
    required int intervalSeconds,
    required int maxCycles,
    required String? Function(String commitmentHashHex) signCommitment,
  }) {
    if (mandate.revokedAtUtc != null) return null;
    final normalizedRunnerKeyId = runnerKeyId.trim().toLowerCase();
    if (!_isSha256(normalizedRunnerKeyId)) return null;
    final normalizedStrategy = _normalizeStrategyPolicy(strategyPolicy);
    final normalizedSession = _normalizeSessionPolicy(
      startsAtUtc: startsAtUtc,
      intervalSeconds: intervalSeconds,
      maxCycles: maxCycles,
      mandate: mandate,
    );
    if (normalizedStrategy == null || normalizedSession == null) return null;
    final commitmentHashHex = _deriveDeterministicSessionCommitmentHash(
      mandate: mandate,
      runnerKeyId: normalizedRunnerKeyId,
      strategyPolicy: normalizedStrategy,
      sessionPolicy: normalizedSession,
    );
    final signatureHex =
        signCommitment(commitmentHashHex)?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex)) return null;
    return BingxFuturesRemoteMandateAdmission._(
      operationId: commitmentHashHex,
      commitmentHashHex: commitmentHashHex,
      runnerKeyId: normalizedRunnerKeyId,
      mandate: mandate,
      exactOrder: null,
      strategyPolicy: normalizedStrategy,
      sessionPolicy: normalizedSession,
      signatureHex: signatureHex,
    );
  }

  static Map<String, dynamic> deterministicStrategyPolicy({
    required double stopLossPercent,
    required double minimumRiskReward,
  }) => <String, dynamic>{
    'runner_build_id': deterministicRunnerBuildId,
    'plugin_id': deterministicPluginId,
    'plugin_version': deterministicPluginVersion,
    'package_digest_hex': deterministicPackageDigestHex,
    'host_abi': deterministicHostAbi,
    'stop_loss_percent': stopLossPercent,
    'minimum_risk_reward': minimumRiskReward,
  };

  static BingxFuturesRemoteMandateAdmission? parseAndVerify({
    required List<int> untrustedWireBytes,
    required bool Function({
      required String messageHashHex,
      required String participantIdHex,
      required String signatureHex,
    })
    verifySignature,
  }) {
    if (untrustedWireBytes.isEmpty ||
        untrustedWireBytes.length > maxWireBytes) {
      return null;
    }
    try {
      final raw = utf8.decode(untrustedWireBytes, allowMalformed: false);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['contract_version'];
      final isAccountRead = version == contractVersion;
      final isExactOrder = version == exactOrderContractVersion;
      final isDeterministicOrder = version == deterministicOrderContractVersion;
      final isDeterministicSession =
          version == deterministicSessionContractVersion;
      if (!isAccountRead &&
          !isExactOrder &&
          !isDeterministicOrder &&
          !isDeterministicSession) {
        return null;
      }
      final expectedKeys = <String>{
        'contract_version',
        'operation_id',
        'commitment_hash_hex',
        'runner_key_id',
        'operation_kind',
        if (isAccountRead) 'read_scope',
        if (isExactOrder) 'exact_order',
        if (isDeterministicOrder || isDeterministicSession) 'strategy_policy',
        if (isDeterministicSession) 'session_policy',
        'max_uses',
        'mandate',
        'signature_suite',
        'signature_hex',
      };
      final sessionPolicyWire = decoded['session_policy'];
      final expectedUses =
          isDeterministicSession && sessionPolicyWire is Map<String, dynamic>
              ? sessionPolicyWire['max_cycles']
              : maxUses;
      if (decoded.keys.toSet().difference(expectedKeys).isNotEmpty ||
          expectedKeys.difference(decoded.keys.toSet()).isNotEmpty ||
          decoded['signature_suite'] != signatureSuite ||
          decoded['max_uses'] != expectedUses ||
          decoded['mandate'] is! Map<String, dynamic>) {
        return null;
      }
      final mandate = BingxFuturesTradingMandate.fromJsonMap(
        decoded['mandate']! as Map<String, dynamic>,
      );
      if (mandate == null || mandate.revokedAtUtc != null) return null;
      Map<String, dynamic>? exactOrder;
      Map<String, dynamic>? strategyPolicy;
      Map<String, dynamic>? sessionPolicy;
      if (isAccountRead) {
        final decodedReadScope = decoded['read_scope'];
        if (decoded['operation_kind'] != operationKind ||
            decodedReadScope is! List<dynamic> ||
            decodedReadScope.length != accountReadScope.length ||
            Iterable<int>.generate(accountReadScope.length).any(
              (index) => decodedReadScope[index] != accountReadScope[index],
            )) {
          return null;
        }
      } else if (isExactOrder) {
        if (decoded['operation_kind'] != exactOrderOperationKind ||
            decoded['exact_order'] is! Map<String, dynamic>) {
          return null;
        }
        exactOrder = _normalizeExactOrder(
          decoded['exact_order']! as Map<String, dynamic>,
          mandate,
        );
        if (exactOrder == null) return null;
      } else if (isDeterministicOrder) {
        if (decoded['operation_kind'] != deterministicOrderOperationKind ||
            decoded['strategy_policy'] is! Map<String, dynamic>) {
          return null;
        }
        strategyPolicy = _normalizeStrategyPolicy(
          decoded['strategy_policy']! as Map<String, dynamic>,
        );
        if (strategyPolicy == null) return null;
      } else {
        if (decoded['operation_kind'] != deterministicSessionOperationKind ||
            decoded['strategy_policy'] is! Map<String, dynamic> ||
            decoded['session_policy'] is! Map<String, dynamic>) {
          return null;
        }
        strategyPolicy = _normalizeStrategyPolicy(
          decoded['strategy_policy']! as Map<String, dynamic>,
        );
        sessionPolicy = _normalizeSessionPolicyMap(
          decoded['session_policy']! as Map<String, dynamic>,
          mandate,
        );
        if (strategyPolicy == null || sessionPolicy == null) return null;
      }
      final runnerKeyId = decoded['runner_key_id']?.toString() ?? '';
      final commitmentHashHex =
          decoded['commitment_hash_hex']?.toString() ?? '';
      final operationId = decoded['operation_id']?.toString() ?? '';
      final signatureHex = decoded['signature_hex']?.toString() ?? '';
      if (!_isSha256(runnerKeyId) ||
          !_isSha256(commitmentHashHex) ||
          operationId != commitmentHashHex ||
          !RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex) ||
          commitmentHashHex !=
              (isAccountRead
                  ? _deriveCommitmentHash(
                    mandate: mandate,
                    runnerKeyId: runnerKeyId,
                  )
                  : isExactOrder
                  ? _deriveExactOrderCommitmentHash(
                    mandate: mandate,
                    runnerKeyId: runnerKeyId,
                    exactOrder: exactOrder!,
                  )
                  : isDeterministicOrder
                  ? _deriveDeterministicOrderCommitmentHash(
                    mandate: mandate,
                    runnerKeyId: runnerKeyId,
                    strategyPolicy: strategyPolicy!,
                  )
                  : _deriveDeterministicSessionCommitmentHash(
                    mandate: mandate,
                    runnerKeyId: runnerKeyId,
                    strategyPolicy: strategyPolicy!,
                    sessionPolicy: sessionPolicy!,
                  ))) {
        return null;
      }
      final admission = BingxFuturesRemoteMandateAdmission._(
        operationId: operationId,
        commitmentHashHex: commitmentHashHex,
        runnerKeyId: runnerKeyId,
        mandate: mandate,
        exactOrder: exactOrder,
        strategyPolicy: strategyPolicy,
        sessionPolicy: sessionPolicy,
        signatureHex: signatureHex,
      );
      if (raw != admission.canonicalJson) return null;
      if (!verifySignature(
        messageHashHex: commitmentHashHex,
        participantIdHex: mandate.capsuleRootHex,
        signatureHex: signatureHex,
      )) {
        return null;
      }
      return admission;
    } catch (_) {
      return null;
    }
  }

  static Future<BingxFuturesRemoteMandateAdmission?> parseAndVerifyAsync({
    required List<int> untrustedWireBytes,
    required Future<bool> Function({
      required String messageHashHex,
      required String participantIdHex,
      required String signatureHex,
    })
    verifySignature,
  }) async {
    final admission = parseAndVerify(
      untrustedWireBytes: untrustedWireBytes,
      verifySignature:
          ({
            required messageHashHex,
            required participantIdHex,
            required signatureHex,
          }) => true,
    );
    if (admission == null) return null;
    final valid = await verifySignature(
      messageHashHex: admission.commitmentHashHex,
      participantIdHex: admission.mandate.capsuleRootHex,
      signatureHex: admission.signatureHex,
    );
    return valid ? admission : null;
  }

  bool get isExactOrder => exactOrder != null;
  bool get isDeterministicSession => sessionPolicy != null;
  bool get isDeterministicOrder =>
      strategyPolicy != null && sessionPolicy == null;

  int get authorizedUses =>
      isDeterministicSession ? sessionPolicy!['max_cycles'] as int : maxUses;

  String? deterministicCycleOperationId(int cycleIndex) {
    if (isDeterministicOrder) return cycleIndex == 0 ? operationId : null;
    if (!isDeterministicSession ||
        cycleIndex < 0 ||
        cycleIndex >= authorizedUses) {
      return null;
    }
    return sha256
        .convert(
          utf8.encode(
            'hivra:bingx-futures-remote-session-cycle:v1\n'
            '${jsonEncode(<String, dynamic>{'session_operation_id': operationId, 'cycle_index': cycleIndex})}',
          ),
        )
        .toString();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'contract_version':
        isExactOrder
            ? exactOrderContractVersion
            : isDeterministicSession
            ? deterministicSessionContractVersion
            : isDeterministicOrder
            ? deterministicOrderContractVersion
            : contractVersion,
    'operation_id': operationId,
    'commitment_hash_hex': commitmentHashHex,
    'runner_key_id': runnerKeyId,
    'operation_kind':
        isExactOrder
            ? exactOrderOperationKind
            : isDeterministicSession
            ? deterministicSessionOperationKind
            : isDeterministicOrder
            ? deterministicOrderOperationKind
            : operationKind,
    if (!isExactOrder && !isDeterministicOrder && !isDeterministicSession)
      'read_scope': accountReadScope,
    if (isExactOrder) 'exact_order': exactOrder,
    if (isDeterministicOrder || isDeterministicSession)
      'strategy_policy': strategyPolicy,
    if (isDeterministicSession) 'session_policy': sessionPolicy,
    'max_uses': authorizedUses,
    'mandate': mandate.toJson(),
    'signature_suite': signatureSuite,
    'signature_hex': signatureHex,
  };

  String get canonicalJson => jsonEncode(toJson());

  static String _deriveCommitmentHash({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
  }) =>
      sha256
          .convert(
            utf8.encode(
              'hivra:bingx-futures-remote-mandate-admission:v2\n'
              '${jsonEncode(<String, dynamic>{'contract_version': contractVersion, 'runner_key_id': runnerKeyId, 'operation_kind': operationKind, 'read_scope': accountReadScope, 'max_uses': maxUses, 'mandate': mandate.toJson()})}',
            ),
          )
          .toString();

  static String _deriveExactOrderCommitmentHash({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
    required Map<String, dynamic> exactOrder,
  }) =>
      sha256
          .convert(
            utf8.encode(
              'hivra:bingx-futures-remote-mandate-admission:v3\n'
              '${jsonEncode(<String, dynamic>{'contract_version': exactOrderContractVersion, 'runner_key_id': runnerKeyId, 'operation_kind': exactOrderOperationKind, 'exact_order': exactOrder, 'max_uses': maxUses, 'mandate': mandate.toJson()})}',
            ),
          )
          .toString();

  static String _deriveDeterministicOrderCommitmentHash({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
    required Map<String, dynamic> strategyPolicy,
  }) =>
      sha256
          .convert(
            utf8.encode(
              'hivra:bingx-futures-remote-mandate-admission:v4\n'
              '${jsonEncode(<String, dynamic>{'contract_version': deterministicOrderContractVersion, 'runner_key_id': runnerKeyId, 'operation_kind': deterministicOrderOperationKind, 'strategy_policy': strategyPolicy, 'max_uses': maxUses, 'mandate': mandate.toJson()})}',
            ),
          )
          .toString();

  static String _deriveDeterministicSessionCommitmentHash({
    required BingxFuturesTradingMandate mandate,
    required String runnerKeyId,
    required Map<String, dynamic> strategyPolicy,
    required Map<String, dynamic> sessionPolicy,
  }) =>
      sha256
          .convert(
            utf8.encode(
              'hivra:bingx-futures-remote-mandate-admission:v5\n'
              '${jsonEncode(<String, dynamic>{'contract_version': deterministicSessionContractVersion, 'runner_key_id': runnerKeyId, 'operation_kind': deterministicSessionOperationKind, 'strategy_policy': strategyPolicy, 'session_policy': sessionPolicy, 'max_uses': sessionPolicy['max_cycles'], 'mandate': mandate.toJson()})}',
            ),
          )
          .toString();

  static Map<String, dynamic>? _normalizeSessionPolicy({
    required DateTime startsAtUtc,
    required int intervalSeconds,
    required int maxCycles,
    required BingxFuturesTradingMandate mandate,
  }) {
    final issued = DateTime.tryParse(mandate.issuedAtUtc)?.toUtc();
    final expires = DateTime.tryParse(mandate.expiresAtUtc)?.toUtc();
    final starts = startsAtUtc.toUtc();
    if (issued == null ||
        expires == null ||
        starts.isBefore(issued) ||
        !starts.isBefore(expires) ||
        intervalSeconds < 60 ||
        intervalSeconds > 3600 ||
        maxCycles < 1 ||
        maxCycles > maxSessionCycles ||
        !starts
            .add(Duration(seconds: intervalSeconds * (maxCycles - 1)))
            .isBefore(expires)) {
      return null;
    }
    return <String, dynamic>{
      'starts_at_utc': starts.toIso8601String(),
      'interval_seconds': intervalSeconds,
      'max_cycles': maxCycles,
      'stop_on_failure': true,
    };
  }

  static Map<String, dynamic>? _normalizeSessionPolicyMap(
    Map<String, dynamic> value,
    BingxFuturesTradingMandate mandate,
  ) {
    const keys = <String>{
      'starts_at_utc',
      'interval_seconds',
      'max_cycles',
      'stop_on_failure',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['stop_on_failure'] is! bool ||
        value['stop_on_failure'] != true) {
      return null;
    }
    final interval = _readExactInt(value['interval_seconds']);
    final cycles = _readExactInt(value['max_cycles']);
    final startsAtUtc = DateTime.tryParse(
      value['starts_at_utc']?.toString() ?? '',
    );
    if (interval == null || cycles == null || startsAtUtc == null) return null;
    return _normalizeSessionPolicy(
      startsAtUtc: startsAtUtc,
      intervalSeconds: interval,
      maxCycles: cycles,
      mandate: mandate,
    );
  }

  static Map<String, dynamic>? _normalizeStrategyPolicy(
    Map<String, dynamic> value,
  ) {
    const keys = <String>{
      'runner_build_id',
      'plugin_id',
      'plugin_version',
      'package_digest_hex',
      'host_abi',
      'stop_loss_percent',
      'minimum_risk_reward',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty) {
      return null;
    }
    final buildId = value['runner_build_id']?.toString().trim() ?? '';
    final pluginId = value['plugin_id']?.toString().trim() ?? '';
    final pluginVersion = value['plugin_version']?.toString().trim() ?? '';
    final digest =
        value['package_digest_hex']?.toString().trim().toLowerCase() ?? '';
    final hostAbi = value['host_abi']?.toString().trim() ?? '';
    final stopLoss = (value['stop_loss_percent'] as num?)?.toDouble();
    final minimumRiskReward =
        (value['minimum_risk_reward'] as num?)?.toDouble();
    if (buildId.isEmpty ||
        pluginId.isEmpty ||
        pluginVersion.isEmpty ||
        hostAbi.isEmpty ||
        buildId.length > 128 ||
        pluginId.length > 128 ||
        pluginVersion.length > 128 ||
        hostAbi.length > 128 ||
        !_isSha256(digest) ||
        stopLoss == null ||
        !stopLoss.isFinite ||
        stopLoss <= 0 ||
        minimumRiskReward == null ||
        !minimumRiskReward.isFinite ||
        minimumRiskReward <= 0) {
      return null;
    }
    return <String, dynamic>{
      'runner_build_id': buildId,
      'plugin_id': pluginId,
      'plugin_version': pluginVersion,
      'package_digest_hex': digest,
      'host_abi': hostAbi,
      'stop_loss_percent': stopLoss,
      'minimum_risk_reward': minimumRiskReward,
    };
  }

  static Map<String, dynamic>? _normalizeExactOrder(
    Map<String, dynamic> value,
    BingxFuturesTradingMandate mandate,
  ) {
    const keys = <String>{
      'client_order_id',
      'symbol',
      'side',
      'order_type',
      'quantity_decimal',
      'limit_price_decimal',
      'time_in_force',
      'entry_mode',
      'trigger_price_decimal',
      'stop_loss_decimal',
      'take_profit_decimal',
      'intent_hash_hex',
      'test_order',
    };
    final actualKeys = value.keys.toSet();
    if (actualKeys.difference(keys).isNotEmpty ||
        keys.difference(actualKeys).isNotEmpty ||
        value['test_order'] is! bool) {
      return null;
    }
    try {
      final payload = BingxFuturesIntentPayload.fromPluginResult(value);
      final quantity = double.tryParse(payload.quantityDecimal);
      final price = double.tryParse(payload.limitPriceDecimal ?? '');
      if (!RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(payload.clientOrderId) ||
          payload.symbol != mandate.symbol ||
          payload.orderType != 'limit' ||
          payload.entryMode != 'zone_pending' ||
          (payload.timeInForce ?? '').toUpperCase() != 'GTC' ||
          payload.triggerPriceDecimal == null ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(payload.intentHashHex ?? '') ||
          value['test_order'] != mandate.testOrder ||
          quantity == null ||
          price == null ||
          !quantity.isFinite ||
          !price.isFinite ||
          quantity <= 0 ||
          price <= 0 ||
          quantity * price >
              double.parse(mandate.maxOrderNotionalQuoteDecimal)) {
        return null;
      }
      return payload.toExactOrderJson(testOrder: mandate.testOrder);
    } catch (_) {
      return null;
    }
  }

  static bool _isSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static int? _readExactInt(Object? value) {
    if (value is! num || !value.isFinite || value != value.truncate()) {
      return null;
    }
    return value.toInt();
  }
}

class BingxFuturesRemoteSessionRevocation {
  static const String contractVersion = 'trading-remote-session-revocation-v1';
  static const String signatureSuite = 'ed25519-v1';
  static const int maxWireBytes = 2048;

  final String revocationId;
  final String targetSessionOperationId;
  final String runnerKeyId;
  final String capsuleRootHex;
  final String revokedAtUtc;
  final String signatureHex;

  const BingxFuturesRemoteSessionRevocation._({
    required this.revocationId,
    required this.targetSessionOperationId,
    required this.runnerKeyId,
    required this.capsuleRootHex,
    required this.revokedAtUtc,
    required this.signatureHex,
  });

  static BingxFuturesRemoteSessionRevocation? issue({
    required BingxFuturesRemoteMandateAdmission session,
    required DateTime revokedAtUtc,
    required String? Function(String commitmentHashHex) signCommitment,
  }) {
    if (!session.isDeterministicSession) return null;
    final semantic = _normalizeSemantic(
      targetSessionOperationId: session.operationId,
      runnerKeyId: session.runnerKeyId,
      capsuleRootHex: session.mandate.capsuleRootHex,
      revokedAtUtc: revokedAtUtc.toUtc().toIso8601String(),
    );
    if (semantic == null) return null;
    final revocationId = _deriveCommitmentHash(semantic);
    final signatureHex =
        signCommitment(revocationId)?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex)) return null;
    return BingxFuturesRemoteSessionRevocation._(
      revocationId: revocationId,
      targetSessionOperationId:
          semantic['target_session_operation_id']! as String,
      runnerKeyId: semantic['runner_key_id']! as String,
      capsuleRootHex: semantic['capsule_root_hex']! as String,
      revokedAtUtc: semantic['revoked_at_utc']! as String,
      signatureHex: signatureHex,
    );
  }

  static BingxFuturesRemoteSessionRevocation? parseAndVerify({
    required List<int> untrustedWireBytes,
    required bool Function({
      required String messageHashHex,
      required String participantIdHex,
      required String signatureHex,
    })
    verifySignature,
  }) {
    if (untrustedWireBytes.isEmpty ||
        untrustedWireBytes.length > maxWireBytes) {
      return null;
    }
    try {
      final raw = utf8.decode(untrustedWireBytes, allowMalformed: false);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      const keys = <String>{
        'contract_version',
        'revocation_id',
        'target_session_operation_id',
        'runner_key_id',
        'capsule_root_hex',
        'revoked_at_utc',
        'signature_suite',
        'signature_hex',
      };
      if (decoded.keys.toSet().difference(keys).isNotEmpty ||
          keys.difference(decoded.keys.toSet()).isNotEmpty ||
          decoded['contract_version'] != contractVersion ||
          decoded['signature_suite'] != signatureSuite) {
        return null;
      }
      final semantic = _normalizeSemantic(
        targetSessionOperationId:
            decoded['target_session_operation_id']?.toString() ?? '',
        runnerKeyId: decoded['runner_key_id']?.toString() ?? '',
        capsuleRootHex: decoded['capsule_root_hex']?.toString() ?? '',
        revokedAtUtc: decoded['revoked_at_utc']?.toString() ?? '',
      );
      if (semantic == null) return null;
      final revocationId = decoded['revocation_id']?.toString() ?? '';
      final signatureHex = decoded['signature_hex']?.toString() ?? '';
      if (revocationId != _deriveCommitmentHash(semantic) ||
          !RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex)) {
        return null;
      }
      final result = BingxFuturesRemoteSessionRevocation._(
        revocationId: revocationId,
        targetSessionOperationId:
            semantic['target_session_operation_id']! as String,
        runnerKeyId: semantic['runner_key_id']! as String,
        capsuleRootHex: semantic['capsule_root_hex']! as String,
        revokedAtUtc: semantic['revoked_at_utc']! as String,
        signatureHex: signatureHex,
      );
      if (raw != result.canonicalJson ||
          !verifySignature(
            messageHashHex: result.revocationId,
            participantIdHex: result.capsuleRootHex,
            signatureHex: result.signatureHex,
          )) {
        return null;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'contract_version': contractVersion,
    'revocation_id': revocationId,
    'target_session_operation_id': targetSessionOperationId,
    'runner_key_id': runnerKeyId,
    'capsule_root_hex': capsuleRootHex,
    'revoked_at_utc': revokedAtUtc,
    'signature_suite': signatureSuite,
    'signature_hex': signatureHex,
  };

  String get canonicalJson => jsonEncode(toJson());

  static Map<String, dynamic>? _normalizeSemantic({
    required String targetSessionOperationId,
    required String runnerKeyId,
    required String capsuleRootHex,
    required String revokedAtUtc,
  }) {
    final target = targetSessionOperationId.trim().toLowerCase();
    final runner = runnerKeyId.trim().toLowerCase();
    final capsule = capsuleRootHex.trim().toLowerCase();
    final revoked = DateTime.tryParse(revokedAtUtc)?.toUtc();
    final hex64 = RegExp(r'^[0-9a-f]{64}$');
    if (!hex64.hasMatch(target) ||
        !hex64.hasMatch(runner) ||
        !hex64.hasMatch(capsule) ||
        revoked == null ||
        !revokedAtUtc.endsWith('Z')) {
      return null;
    }
    return <String, dynamic>{
      'contract_version': contractVersion,
      'target_session_operation_id': target,
      'runner_key_id': runner,
      'capsule_root_hex': capsule,
      'revoked_at_utc': revoked.toIso8601String(),
    };
  }

  static String _deriveCommitmentHash(Map<String, dynamic> semantic) =>
      sha256
          .convert(
            utf8.encode(
              'hivra:bingx-futures-remote-session-revocation:v1\n'
              '${jsonEncode(semantic)}',
            ),
          )
          .toString();
}

class BingxLiquidityEventEffectClaim {
  final String liquidityEventId;
  final String clientOrderId;
  final String symbol;
  final String side;
  final String? intentHashHex;
  final String? canonicalIntentJson;
  final bool testOrder;
  final BingxLiquidityEventEffectClaimStatus status;
  final String? orderId;
  final String? accountBindingHashHex;
  final String? mandateId;
  final BingxManagedOrderLifecycleStatus lifecycleStatus;
  final String? lifecycleEvidenceAtUtc;
  final String? lifecycleDiagnostic;
  final String recordedAtUtc;

  const BingxLiquidityEventEffectClaim({
    required this.liquidityEventId,
    required this.clientOrderId,
    required this.symbol,
    required this.side,
    this.intentHashHex,
    this.canonicalIntentJson,
    required this.testOrder,
    required this.status,
    required this.orderId,
    this.accountBindingHashHex,
    this.mandateId,
    this.lifecycleStatus = BingxManagedOrderLifecycleStatus.unresolved,
    this.lifecycleEvidenceAtUtc,
    this.lifecycleDiagnostic,
    required this.recordedAtUtc,
  });

  String get storageKey => '${testOrder ? "test" : "live"}|$liquidityEventId';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'liquidity_event_id': liquidityEventId,
    'client_order_id': clientOrderId,
    'symbol': symbol,
    'side': side,
    'intent_hash_hex': intentHashHex,
    'canonical_intent_json': canonicalIntentJson,
    'test_order': testOrder,
    'status': status.name,
    'order_id': orderId,
    'account_binding_hash_hex': accountBindingHashHex,
    'mandate_id': mandateId,
    'lifecycle_status': lifecycleStatus.name,
    'lifecycle_evidence_at_utc': lifecycleEvidenceAtUtc,
    'lifecycle_diagnostic': lifecycleDiagnostic,
    'recorded_at_utc': recordedAtUtc,
  };

  static BingxLiquidityEventEffectClaim? fromJsonMap(Map<String, dynamic> map) {
    String read(String key) => map[key]?.toString().trim() ?? '';
    final eventId = read('liquidity_event_id').toLowerCase();
    final clientOrderId = read('client_order_id');
    final symbol = read('symbol').toUpperCase();
    final side = read('side').toLowerCase();
    final status = switch (read('status')) {
      'reserved' => BingxLiquidityEventEffectClaimStatus.reserved,
      'confirmed' => BingxLiquidityEventEffectClaimStatus.confirmed,
      _ => null,
    };
    final recordedAtUtc = read('recorded_at_utc');
    final accountBindingHashHex =
        read('account_binding_hash_hex').toLowerCase();
    final lifecycleStatus = _readLifecycleStatus(read('lifecycle_status'));
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(eventId) ||
        clientOrderId.isEmpty ||
        symbol.isEmpty ||
        (side != 'buy' && side != 'sell') ||
        status == null ||
        recordedAtUtc.isEmpty) {
      return null;
    }
    final orderId = read('order_id');
    return BingxLiquidityEventEffectClaim(
      liquidityEventId: eventId,
      clientOrderId: clientOrderId,
      symbol: symbol,
      side: side,
      intentHashHex: _readOptionalString(map['intent_hash_hex']),
      canonicalIntentJson: _readOptionalString(map['canonical_intent_json']),
      testOrder: map['test_order'] == true,
      status: status,
      orderId: orderId.isEmpty ? null : orderId,
      accountBindingHashHex:
          RegExp(r'^[0-9a-f]{64}$').hasMatch(accountBindingHashHex)
              ? accountBindingHashHex
              : null,
      mandateId: _readOptionalSha256(map['mandate_id']),
      lifecycleStatus: lifecycleStatus,
      lifecycleEvidenceAtUtc: _readOptionalString(
        map['lifecycle_evidence_at_utc'],
      ),
      lifecycleDiagnostic: _readOptionalString(map['lifecycle_diagnostic']),
      recordedAtUtc: recordedAtUtc,
    );
  }

  BingxLiquidityEventEffectClaim withLifecycle({
    required BingxManagedOrderLifecycleStatus lifecycleStatus,
    required String evidenceAtUtc,
    String? diagnostic,
    String? confirmedOrderId,
  }) {
    final nextOrderId = confirmedOrderId?.trim() ?? orderId;
    return BingxLiquidityEventEffectClaim(
      liquidityEventId: liquidityEventId,
      clientOrderId: clientOrderId,
      symbol: symbol,
      side: side,
      intentHashHex: intentHashHex,
      canonicalIntentJson: canonicalIntentJson,
      testOrder: testOrder,
      status:
          nextOrderId == null || nextOrderId.isEmpty
              ? status
              : BingxLiquidityEventEffectClaimStatus.confirmed,
      orderId: nextOrderId,
      accountBindingHashHex: accountBindingHashHex,
      mandateId: mandateId,
      lifecycleStatus: lifecycleStatus,
      lifecycleEvidenceAtUtc: evidenceAtUtc,
      lifecycleDiagnostic: diagnostic,
      recordedAtUtc: recordedAtUtc,
    );
  }
}

class BingxManagedOrderProvenance {
  final String orderId;
  final String symbol;
  final String side;
  final bool testOrder;
  final String intentHashHex;
  final String canonicalIntentJson;
  final String? clientOrderId;
  final String? accountBindingHashHex;
  final String? externalEffectOperationId;
  final BingxManagedOrderLifecycleStatus lifecycleStatus;
  final String? lifecycleEvidenceAtUtc;
  final String? lifecycleDiagnostic;
  final String? marketSnapshotHashHex;
  final String? featureHashHex;
  final String? tvhDecisionHashHex;
  final String? liveDecisionHashHex;
  final String recordedAtUtc;

  const BingxManagedOrderProvenance({
    required this.orderId,
    required this.symbol,
    required this.side,
    required this.testOrder,
    required this.intentHashHex,
    required this.canonicalIntentJson,
    this.clientOrderId,
    this.accountBindingHashHex,
    this.externalEffectOperationId,
    this.lifecycleStatus = BingxManagedOrderLifecycleStatus.unresolved,
    this.lifecycleEvidenceAtUtc,
    this.lifecycleDiagnostic,
    required this.marketSnapshotHashHex,
    required this.featureHashHex,
    required this.tvhDecisionHashHex,
    required this.liveDecisionHashHex,
    required this.recordedAtUtc,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'order_id': orderId.trim(),
      'symbol': symbol.trim().toUpperCase(),
      'side': side.trim().toLowerCase(),
      'test_order': testOrder,
      'intent_hash_hex': intentHashHex.trim().toLowerCase(),
      'canonical_intent_json': canonicalIntentJson,
      'client_order_id': clientOrderId,
      'account_binding_hash_hex': accountBindingHashHex,
      'external_effect_operation_id': externalEffectOperationId,
      'lifecycle_status': lifecycleStatus.name,
      'lifecycle_evidence_at_utc': lifecycleEvidenceAtUtc,
      'lifecycle_diagnostic': lifecycleDiagnostic,
      'market_snapshot_hash_hex': marketSnapshotHashHex?.trim().toLowerCase(),
      'feature_hash_hex': featureHashHex?.trim().toLowerCase(),
      'tvh_decision_hash_hex': tvhDecisionHashHex?.trim().toLowerCase(),
      'live_decision_hash_hex': liveDecisionHashHex?.trim().toLowerCase(),
      'recorded_at_utc': recordedAtUtc.trim(),
    };
  }

  static BingxManagedOrderProvenance? fromJsonMap(Map<String, dynamic> map) {
    String read(String key) => map[key]?.toString().trim() ?? '';

    final orderId = read('order_id');
    final symbol = read('symbol').toUpperCase();
    final side = read('side').toLowerCase();
    final intentHashHex = read('intent_hash_hex').toLowerCase();
    final canonicalIntentJson = map['canonical_intent_json']?.toString() ?? '';
    final recordedAtUtc = read('recorded_at_utc');
    final accountBindingHashHex =
        read('account_binding_hash_hex').toLowerCase();
    final externalEffectOperationId =
        read('external_effect_operation_id').toLowerCase();
    if (orderId.isEmpty ||
        symbol.isEmpty ||
        (side != 'buy' && side != 'sell') ||
        intentHashHex.isEmpty ||
        canonicalIntentJson.trim().isEmpty ||
        (externalEffectOperationId.isNotEmpty &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(externalEffectOperationId)) ||
        recordedAtUtc.isEmpty) {
      return null;
    }
    return BingxManagedOrderProvenance(
      orderId: orderId,
      symbol: symbol,
      side: side,
      testOrder: map['test_order'] == true,
      intentHashHex: intentHashHex,
      canonicalIntentJson: canonicalIntentJson,
      clientOrderId: _readOptionalString(map['client_order_id']),
      accountBindingHashHex:
          RegExp(r'^[0-9a-f]{64}$').hasMatch(accountBindingHashHex)
              ? accountBindingHashHex
              : null,
      externalEffectOperationId:
          RegExp(r'^[0-9a-f]{64}$').hasMatch(externalEffectOperationId)
              ? externalEffectOperationId
              : null,
      lifecycleStatus: _readLifecycleStatus(read('lifecycle_status')),
      lifecycleEvidenceAtUtc: _readOptionalString(
        map['lifecycle_evidence_at_utc'],
      ),
      lifecycleDiagnostic: _readOptionalString(map['lifecycle_diagnostic']),
      marketSnapshotHashHex: _readOptionalHash(map['market_snapshot_hash_hex']),
      featureHashHex: _readOptionalHash(map['feature_hash_hex']),
      tvhDecisionHashHex: _readOptionalHash(map['tvh_decision_hash_hex']),
      liveDecisionHashHex: _readOptionalHash(map['live_decision_hash_hex']),
      recordedAtUtc: recordedAtUtc,
    );
  }

  BingxManagedOrderProvenance withLifecycle({
    required BingxManagedOrderLifecycleStatus status,
    required String evidenceAtUtc,
    String? diagnostic,
  }) {
    return BingxManagedOrderProvenance(
      orderId: orderId,
      symbol: symbol,
      side: side,
      testOrder: testOrder,
      intentHashHex: intentHashHex,
      canonicalIntentJson: canonicalIntentJson,
      clientOrderId: clientOrderId,
      accountBindingHashHex: accountBindingHashHex,
      externalEffectOperationId: externalEffectOperationId,
      lifecycleStatus: status,
      lifecycleEvidenceAtUtc: evidenceAtUtc,
      lifecycleDiagnostic: diagnostic,
      marketSnapshotHashHex: marketSnapshotHashHex,
      featureHashHex: featureHashHex,
      tvhDecisionHashHex: tvhDecisionHashHex,
      liveDecisionHashHex: liveDecisionHashHex,
      recordedAtUtc: recordedAtUtc,
    );
  }

  static String? _readOptionalHash(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

BingxManagedOrderLifecycleStatus _readLifecycleStatus(String value) {
  return switch (value) {
    'active' => BingxManagedOrderLifecycleStatus.active,
    'filled' => BingxManagedOrderLifecycleStatus.filled,
    'cancelled' || 'canceled' => BingxManagedOrderLifecycleStatus.cancelled,
    'rejected' => BingxManagedOrderLifecycleStatus.rejected,
    'expired' => BingxManagedOrderLifecycleStatus.expired,
    _ => BingxManagedOrderLifecycleStatus.unresolved,
  };
}

String? _readOptionalString(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String? _readOptionalSha256(Object? value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
}

class BingxFuturesOrderTrackingState {
  final String? trackedSymbol;
  final String? trackedOrderId;
  final List<String> managedOrderIds;
  final Map<String, String> managedOrderSymbols;
  final Map<String, BingxManagedOrderProvenance> managedOrderProvenance;
  final Map<String, BingxLiquidityEventEffectClaim> liquidityEventEffectClaims;
  final bool? droneEnabled;
  final BingxFuturesTradingMandate? tradingMandate;
  final double? stopLossPercent;
  final double? takeProfitRiskReward;

  const BingxFuturesOrderTrackingState({
    required this.trackedSymbol,
    required this.trackedOrderId,
    required this.managedOrderIds,
    required this.managedOrderSymbols,
    this.managedOrderProvenance = const <String, BingxManagedOrderProvenance>{},
    this.liquidityEventEffectClaims =
        const <String, BingxLiquidityEventEffectClaim>{},
    this.droneEnabled,
    this.tradingMandate,
    required this.stopLossPercent,
    required this.takeProfitRiskReward,
  });

  bool get isEmpty =>
      (trackedSymbol == null || trackedSymbol!.trim().isEmpty) &&
      (trackedOrderId == null || trackedOrderId!.trim().isEmpty) &&
      managedOrderIds.isEmpty &&
      managedOrderSymbols.isEmpty &&
      managedOrderProvenance.isEmpty &&
      liquidityEventEffectClaims.isEmpty &&
      droneEnabled == null &&
      tradingMandate == null &&
      stopLossPercent == null &&
      takeProfitRiskReward == null;

  Map<String, dynamic> toJson() {
    final sortedProvenance =
        managedOrderProvenance.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final sortedClaims =
        liquidityEventEffectClaims.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      'version': 6,
      'tracked_symbol': trackedSymbol?.trim().toUpperCase(),
      'tracked_order_id': trackedOrderId?.trim(),
      'managed_order_ids': managedOrderIds,
      'managed_order_symbols': managedOrderSymbols,
      'managed_order_provenance': <String, dynamic>{
        for (final entry in sortedProvenance) entry.key: entry.value.toJson(),
      },
      'liquidity_event_effect_claims': <String, dynamic>{
        for (final entry in sortedClaims) entry.key: entry.value.toJson(),
      },
      'drone_enabled': droneEnabled,
      'trading_mandate': tradingMandate?.toJson(),
      'stop_loss_percent': stopLossPercent,
      'take_profit_risk_reward': takeProfitRiskReward,
    };
  }

  static BingxFuturesOrderTrackingState? fromJsonMap(Map<String, dynamic> map) {
    final trackedSymbol = map['tracked_symbol']?.toString().trim();
    final trackedOrderId = map['tracked_order_id']?.toString().trim();
    final droneEnabled =
        map['drone_enabled'] is bool ? map['drone_enabled'] as bool : null;
    final mandateRaw = map['trading_mandate'];
    final tradingMandate =
        mandateRaw is Map
            ? BingxFuturesTradingMandate.fromJsonMap(
              Map<String, dynamic>.from(mandateRaw),
            )
            : null;
    final stopLossPercent = _readPositiveDouble(map['stop_loss_percent']);
    final takeProfitRiskReward = _readPositiveDouble(
      map['take_profit_risk_reward'],
    );
    final managedRaw = map['managed_order_ids'];
    final managed = <String>{};
    if (managedRaw is List) {
      for (final value in managedRaw) {
        final normalized = value?.toString().trim() ?? '';
        if (normalized.isNotEmpty) {
          managed.add(normalized);
        }
      }
    }
    final managedSymbolsRaw = map['managed_order_symbols'];
    final managedSymbols = <String, String>{};
    if (managedSymbolsRaw is Map) {
      for (final entry in managedSymbolsRaw.entries) {
        final orderId = entry.key.toString().trim();
        final symbol = entry.value?.toString().trim().toUpperCase() ?? '';
        if (orderId.isNotEmpty && symbol.isNotEmpty) {
          managedSymbols[orderId] = symbol;
        }
      }
    }
    final provenanceRaw = map['managed_order_provenance'];
    final provenance = <String, BingxManagedOrderProvenance>{};
    if (provenanceRaw is Map) {
      for (final entry in provenanceRaw.entries) {
        final orderId = entry.key.toString().trim();
        final value = entry.value;
        if (orderId.isEmpty || value is! Map) continue;
        final parsed = BingxManagedOrderProvenance.fromJsonMap(
          Map<String, dynamic>.from(value),
        );
        if (parsed != null && parsed.orderId == orderId) {
          provenance[orderId] = parsed;
        }
      }
    }
    final claimsRaw = map['liquidity_event_effect_claims'];
    final claims = <String, BingxLiquidityEventEffectClaim>{};
    if (claimsRaw is Map) {
      for (final entry in claimsRaw.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value;
        if (key.isEmpty || value is! Map) continue;
        final parsed = BingxLiquidityEventEffectClaim.fromJsonMap(
          Map<String, dynamic>.from(value),
        );
        if (parsed != null && parsed.storageKey == key) {
          claims[key] = parsed;
        }
      }
    }
    return BingxFuturesOrderTrackingState(
      trackedSymbol:
          trackedSymbol == null || trackedSymbol.isEmpty
              ? null
              : trackedSymbol.toUpperCase(),
      trackedOrderId:
          trackedOrderId == null || trackedOrderId.isEmpty
              ? null
              : trackedOrderId,
      managedOrderIds: List<String>.unmodifiable(managed.toList()..sort()),
      managedOrderSymbols: Map<String, String>.unmodifiable(
        Map<String, String>.fromEntries(
          managedSymbols.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)),
        ),
      ),
      managedOrderProvenance:
          Map<String, BingxManagedOrderProvenance>.unmodifiable(
            Map<String, BingxManagedOrderProvenance>.fromEntries(
              provenance.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)),
            ),
          ),
      liquidityEventEffectClaims:
          Map<String, BingxLiquidityEventEffectClaim>.unmodifiable(claims),
      droneEnabled: droneEnabled,
      tradingMandate: tradingMandate,
      stopLossPercent: stopLossPercent,
      takeProfitRiskReward: takeProfitRiskReward,
    );
  }

  static double? _readPositiveDouble(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final parsed = value.toDouble();
      return parsed > 0 ? parsed : null;
    }
    final parsed = double.tryParse(value.toString().trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}
