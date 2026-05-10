import 'dart:convert';

import 'package:crypto/crypto.dart';

class BingxExecutionPolicy {
  final Set<String> allowedSymbols;
  final double maxLeverage;
  final double maxRiskPercent;

  const BingxExecutionPolicy({
    required this.allowedSymbols,
    required this.maxLeverage,
    required this.maxRiskPercent,
  });
}

enum BingxExecutionDecisionStatus {
  accepted,
  rejected,
}

class BingxExecutionDecision {
  final BingxExecutionDecisionStatus status;
  final String decisionCode;
  final String decisionMessage;
  final String canonicalReceiptJson;
  final String receiptHashHex;

  const BingxExecutionDecision({
    required this.status,
    required this.decisionCode,
    required this.decisionMessage,
    required this.canonicalReceiptJson,
    required this.receiptHashHex,
  });
}

abstract class BingxExecutionCommandReplayStore {
  bool hasProcessed(String commandId);
  void markProcessed(String commandId);
}

class InMemoryBingxExecutionCommandReplayStore
    implements BingxExecutionCommandReplayStore {
  final Set<String> _seen = <String>{};

  @override
  bool hasProcessed(String commandId) => _seen.contains(commandId);

  @override
  void markProcessed(String commandId) {
    _seen.add(commandId);
  }
}

class BingxFuturesExecutionCommandService {
  static const String pluginId = 'hivra.contract.bingx-futures-trading.v1';
  static const String commandKind = 'futures_execution_command_v1';
  static const String receiptKind = 'futures_execution_receipt_v1';

  final BingxExecutionCommandReplayStore _replayStore;

  const BingxFuturesExecutionCommandService({
    required BingxExecutionCommandReplayStore replayStore,
  }) : _replayStore = replayStore;

  String buildCommandEnvelope({
    required String commandId,
    required String intentHashHex,
    required String symbol,
    required String side,
    required String quantityDecimal,
    required String entryPriceDecimal,
    required String stopLossDecimal,
    required String takeProfitDecimal,
    required String leverageDecimal,
    required String riskPercentDecimal,
    required String createdAtUtc,
    required String expiresAtUtc,
    required String targetCapsuleRootHex,
  }) {
    final normalized = _normalizeCommandFields(
      commandId: commandId,
      intentHashHex: intentHashHex,
      symbol: symbol,
      side: side,
      quantityDecimal: quantityDecimal,
      entryPriceDecimal: entryPriceDecimal,
      stopLossDecimal: stopLossDecimal,
      takeProfitDecimal: takeProfitDecimal,
      leverageDecimal: leverageDecimal,
      riskPercentDecimal: riskPercentDecimal,
      createdAtUtc: createdAtUtc,
      expiresAtUtc: expiresAtUtc,
      targetCapsuleRootHex: targetCapsuleRootHex,
    );
    final envelope = <String, dynamic>{
      'schema_version': 1,
      'plugin_id': pluginId,
      'command_kind': commandKind,
      'command_id': normalized.commandId,
      'intent_hash_hex': normalized.intentHashHex,
      'symbol': normalized.symbol,
      'side': normalized.side,
      'quantity_decimal': normalized.quantityDecimal,
      'entry_price_decimal': normalized.entryPriceDecimal,
      'stop_loss_decimal': normalized.stopLossDecimal,
      'take_profit_decimal': normalized.takeProfitDecimal,
      'leverage_decimal': normalized.leverageDecimal,
      'risk_percent_decimal': normalized.riskPercentDecimal,
      'created_at_utc': normalized.createdAtUtc.toIso8601String(),
      'expires_at_utc': normalized.expiresAtUtc.toIso8601String(),
      'target_capsule_root_hex': normalized.targetCapsuleRootHex,
    };
    return jsonEncode(envelope);
  }

  BingxExecutionDecision evaluateIncomingCommand({
    required String commandEnvelopeJson,
    required String localCapsuleRootHex,
    required String fromPeerHex,
    required bool isPeerSignable,
    required DateTime nowUtc,
    required BingxExecutionPolicy policy,
    bool Function(String intentHashHex)? hasKnownIntentHash,
  }) {
    if (!isPeerSignable) {
      return _decision(
        status: BingxExecutionDecisionStatus.rejected,
        decisionCode: 'pending_consensus',
        decisionMessage: 'Consensus guard blocked sender peer',
        commandId: '-',
        intentHashHex: '-',
        localCapsuleRootHex: localCapsuleRootHex,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }

    final parsed = _parseCommand(commandEnvelopeJson);
    if (parsed.errorCode != null) {
      return _decision(
        status: BingxExecutionDecisionStatus.rejected,
        decisionCode: parsed.errorCode!,
        decisionMessage: parsed.errorMessage!,
        commandId: parsed.commandId ?? '-',
        intentHashHex: parsed.intentHashHex ?? '-',
        localCapsuleRootHex: localCapsuleRootHex,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }

    final command = parsed.command!;
    final localRoot = _normalizeHex64(localCapsuleRootHex);
    if (localRoot == null) {
      return _decision(
        status: BingxExecutionDecisionStatus.rejected,
        decisionCode: 'local_capsule_identity_invalid',
        decisionMessage: 'Local capsule root identity is invalid',
        commandId: command.commandId,
        intentHashHex: command.intentHashHex,
        localCapsuleRootHex: localCapsuleRootHex,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }
    if (command.targetCapsuleRootHex != localRoot) {
      return _decision(
        status: BingxExecutionDecisionStatus.rejected,
        decisionCode: 'target_capsule_mismatch',
        decisionMessage: 'Command target capsule does not match local capsule',
        commandId: command.commandId,
        intentHashHex: command.intentHashHex,
        localCapsuleRootHex: localRoot,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }

    if (nowUtc.toUtc().isAfter(command.expiresAtUtc)) {
      return _decision(
        status: BingxExecutionDecisionStatus.rejected,
        decisionCode: 'command_expired',
        decisionMessage: 'Command TTL expired',
        commandId: command.commandId,
        intentHashHex: command.intentHashHex,
        localCapsuleRootHex: localRoot,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }

    if (_replayStore.hasProcessed(command.commandId)) {
      return _decision(
        status: BingxExecutionDecisionStatus.rejected,
        decisionCode: 'command_duplicate',
        decisionMessage: 'Command already processed',
        commandId: command.commandId,
        intentHashHex: command.intentHashHex,
        localCapsuleRootHex: localRoot,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }

    if (policy.allowedSymbols.isNotEmpty &&
        !policy.allowedSymbols.contains(command.symbol)) {
      return _markAndReject(
        decisionCode: 'policy_symbol_blocked',
        decisionMessage: 'Symbol is not allowed by local policy',
        command: command,
        localRoot: localRoot,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }
    if (command.leverage > policy.maxLeverage) {
      return _markAndReject(
        decisionCode: 'policy_leverage_exceeded',
        decisionMessage: 'Leverage exceeds local policy limit',
        command: command,
        localRoot: localRoot,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }
    if (command.riskPercent > policy.maxRiskPercent) {
      return _markAndReject(
        decisionCode: 'policy_risk_exceeded',
        decisionMessage: 'Risk percent exceeds local policy limit',
        command: command,
        localRoot: localRoot,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }
    if (hasKnownIntentHash != null &&
        !hasKnownIntentHash(command.intentHashHex)) {
      return _markAndReject(
        decisionCode: 'intent_hash_unknown',
        decisionMessage: 'Intent hash is unknown in local plugin state',
        command: command,
        localRoot: localRoot,
        fromPeerHex: fromPeerHex,
        nowUtc: nowUtc,
      );
    }

    _replayStore.markProcessed(command.commandId);
    return _decision(
      status: BingxExecutionDecisionStatus.accepted,
      decisionCode: 'accepted_for_execution',
      decisionMessage: 'Command accepted by local execution gate',
      commandId: command.commandId,
      intentHashHex: command.intentHashHex,
      localCapsuleRootHex: localRoot,
      fromPeerHex: fromPeerHex,
      nowUtc: nowUtc,
    );
  }

  BingxExecutionDecision _markAndReject({
    required String decisionCode,
    required String decisionMessage,
    required _Command command,
    required String localRoot,
    required String fromPeerHex,
    required DateTime nowUtc,
  }) {
    _replayStore.markProcessed(command.commandId);
    return _decision(
      status: BingxExecutionDecisionStatus.rejected,
      decisionCode: decisionCode,
      decisionMessage: decisionMessage,
      commandId: command.commandId,
      intentHashHex: command.intentHashHex,
      localCapsuleRootHex: localRoot,
      fromPeerHex: fromPeerHex,
      nowUtc: nowUtc,
    );
  }

  BingxExecutionDecision _decision({
    required BingxExecutionDecisionStatus status,
    required String decisionCode,
    required String decisionMessage,
    required String commandId,
    required String intentHashHex,
    required String localCapsuleRootHex,
    required String fromPeerHex,
    required DateTime nowUtc,
  }) {
    final normalizedPeer = _normalizeHex64(fromPeerHex) ?? '-';
    final normalizedRoot = _normalizeHex64(localCapsuleRootHex) ?? '-';
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'receipt_kind': receiptKind,
      'command_id': commandId,
      'intent_hash_hex': intentHashHex,
      'decision': status == BingxExecutionDecisionStatus.accepted
          ? 'accepted'
          : 'rejected',
      'decision_code': decisionCode,
      'decision_message': decisionMessage,
      'target_capsule_root_hex': normalizedRoot,
      'peer_hex': normalizedPeer,
      'receipt_created_at_utc': nowUtc.toUtc().toIso8601String(),
    });
    final digest = sha256.convert(utf8.encode(canonical)).toString();
    return BingxExecutionDecision(
      status: status,
      decisionCode: decisionCode,
      decisionMessage: decisionMessage,
      canonicalReceiptJson: canonical,
      receiptHashHex: digest,
    );
  }

  _ParsedCommand _parseCommand(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return const _ParsedCommand.error(
          errorCode: 'invalid_shape',
          errorMessage: 'Command envelope must be a JSON object',
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['schema_version'] != 1) {
        return const _ParsedCommand.error(
          errorCode: 'invalid_schema_version',
          errorMessage: 'schema_version must be 1',
        );
      }
      if (map['plugin_id']?.toString() != pluginId) {
        return const _ParsedCommand.error(
          errorCode: 'plugin_id_mismatch',
          errorMessage: 'plugin_id does not match futures execution channel',
        );
      }
      if (map['command_kind']?.toString() != commandKind) {
        return const _ParsedCommand.error(
          errorCode: 'command_kind_mismatch',
          errorMessage: 'command_kind is invalid',
        );
      }
      final normalized = _normalizeCommandFields(
        commandId: map['command_id']?.toString() ?? '',
        intentHashHex: map['intent_hash_hex']?.toString() ?? '',
        symbol: map['symbol']?.toString() ?? '',
        side: map['side']?.toString() ?? '',
        quantityDecimal: map['quantity_decimal']?.toString() ?? '',
        entryPriceDecimal: map['entry_price_decimal']?.toString() ?? '',
        stopLossDecimal: map['stop_loss_decimal']?.toString() ?? '',
        takeProfitDecimal: map['take_profit_decimal']?.toString() ?? '',
        leverageDecimal: map['leverage_decimal']?.toString() ?? '',
        riskPercentDecimal: map['risk_percent_decimal']?.toString() ?? '',
        createdAtUtc: map['created_at_utc']?.toString() ?? '',
        expiresAtUtc: map['expires_at_utc']?.toString() ?? '',
        targetCapsuleRootHex: map['target_capsule_root_hex']?.toString() ?? '',
      );
      if (normalized.expiresAtUtc.isBefore(normalized.createdAtUtc)) {
        return _ParsedCommand.error(
          errorCode: 'ttl_invalid',
          errorMessage: 'expires_at_utc must be after created_at_utc',
          commandId: normalized.commandId,
          intentHashHex: normalized.intentHashHex,
        );
      }

      return _ParsedCommand.ok(
        command: _Command(
          commandId: normalized.commandId,
          intentHashHex: normalized.intentHashHex,
          symbol: normalized.symbol,
          side: normalized.side,
          quantity: double.parse(normalized.quantityDecimal),
          entryPrice: double.parse(normalized.entryPriceDecimal),
          stopLoss: double.parse(normalized.stopLossDecimal),
          takeProfit: double.parse(normalized.takeProfitDecimal),
          leverage: double.parse(normalized.leverageDecimal),
          riskPercent: double.parse(normalized.riskPercentDecimal),
          createdAtUtc: normalized.createdAtUtc,
          expiresAtUtc: normalized.expiresAtUtc,
          targetCapsuleRootHex: normalized.targetCapsuleRootHex,
        ),
      );
    } on FormatException catch (error) {
      return _ParsedCommand.error(
        errorCode: 'invalid_args',
        errorMessage: error.message,
      );
    } catch (_) {
      return const _ParsedCommand.error(
        errorCode: 'invalid_json',
        errorMessage: 'Command envelope is not valid JSON',
      );
    }
  }

  _NormalizedFields _normalizeCommandFields({
    required String commandId,
    required String intentHashHex,
    required String symbol,
    required String side,
    required String quantityDecimal,
    required String entryPriceDecimal,
    required String stopLossDecimal,
    required String takeProfitDecimal,
    required String leverageDecimal,
    required String riskPercentDecimal,
    required String createdAtUtc,
    required String expiresAtUtc,
    required String targetCapsuleRootHex,
  }) {
    final normalizedCommandId = commandId.trim();
    if (normalizedCommandId.isEmpty || normalizedCommandId.length > 128) {
      throw const FormatException(
        'command_id must be non-empty and <= 128 chars',
      );
    }
    final normalizedIntentHash = _normalizeHex64(intentHashHex);
    if (normalizedIntentHash == null) {
      throw const FormatException('intent_hash_hex must be 64-char hex');
    }
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,20}([-_/][A-Z0-9]{2,20})?$')
        .hasMatch(normalizedSymbol)) {
      throw const FormatException('symbol format is invalid');
    }
    final normalizedSide = side.trim().toLowerCase();
    if (normalizedSide != 'buy' && normalizedSide != 'sell') {
      throw const FormatException('side must be buy or sell');
    }
    final quantity = _normalizeDecimal(quantityDecimal, scale: 8);
    final entry = _normalizeDecimal(entryPriceDecimal, scale: 8);
    final stop = _normalizeDecimal(stopLossDecimal, scale: 8);
    final take = _normalizeDecimal(takeProfitDecimal, scale: 8);
    final leverage = _normalizeDecimal(leverageDecimal, scale: 8);
    final risk = _normalizeDecimal(riskPercentDecimal, scale: 8);
    final created = _parseUtcInstant(createdAtUtc, field: 'created_at_utc');
    final expires = _parseUtcInstant(expiresAtUtc, field: 'expires_at_utc');
    final normalizedTargetRoot = _normalizeHex64(targetCapsuleRootHex);
    if (normalizedTargetRoot == null) {
      throw const FormatException(
        'target_capsule_root_hex must be 64-char hex',
      );
    }
    return _NormalizedFields(
      commandId: normalizedCommandId,
      intentHashHex: normalizedIntentHash,
      symbol: normalizedSymbol,
      side: normalizedSide,
      quantityDecimal: quantity,
      entryPriceDecimal: entry,
      stopLossDecimal: stop,
      takeProfitDecimal: take,
      leverageDecimal: leverage,
      riskPercentDecimal: risk,
      createdAtUtc: created,
      expiresAtUtc: expires,
      targetCapsuleRootHex: normalizedTargetRoot,
    );
  }

  DateTime _parseUtcInstant(String value, {required String field}) {
    final trimmed = value.trim();
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null || !parsed.isUtc) {
      throw FormatException('$field must be ISO-8601 UTC instant');
    }
    return parsed.toUtc();
  }

  String _normalizeDecimal(String value, {required int scale}) {
    final raw = value.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(raw)) {
      throw const FormatException('decimal field must be a positive decimal');
    }
    final parts = raw.split('.');
    final whole = parts[0].replaceFirst(RegExp(r'^0+'), '');
    final normalizedWhole = whole.isEmpty ? '0' : whole;
    var frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > scale) {
      frac = frac.substring(0, scale);
    }
    frac = frac.padRight(scale, '0');
    final normalized = '$normalizedWhole.$frac';
    if (normalized == '0.${'0' * scale}') {
      throw const FormatException('decimal field must be > 0');
    }
    return normalized;
  }

  String? _normalizeHex64(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) return null;
    return normalized;
  }
}

class _ParsedCommand {
  final _Command? command;
  final String? errorCode;
  final String? errorMessage;
  final String? commandId;
  final String? intentHashHex;

  const _ParsedCommand.ok({required this.command})
      : errorCode = null,
        errorMessage = null,
        commandId = null,
        intentHashHex = null;

  const _ParsedCommand.error({
    required this.errorCode,
    required this.errorMessage,
    this.commandId,
    this.intentHashHex,
  }) : command = null;
}

class _Command {
  final String commandId;
  final String intentHashHex;
  final String symbol;
  final String side;
  final double quantity;
  final double entryPrice;
  final double stopLoss;
  final double takeProfit;
  final double leverage;
  final double riskPercent;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final String targetCapsuleRootHex;

  const _Command({
    required this.commandId,
    required this.intentHashHex,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.entryPrice,
    required this.stopLoss,
    required this.takeProfit,
    required this.leverage,
    required this.riskPercent,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    required this.targetCapsuleRootHex,
  });
}

class _NormalizedFields {
  final String commandId;
  final String intentHashHex;
  final String symbol;
  final String side;
  final String quantityDecimal;
  final String entryPriceDecimal;
  final String stopLossDecimal;
  final String takeProfitDecimal;
  final String leverageDecimal;
  final String riskPercentDecimal;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final String targetCapsuleRootHex;

  const _NormalizedFields({
    required this.commandId,
    required this.intentHashHex,
    required this.symbol,
    required this.side,
    required this.quantityDecimal,
    required this.entryPriceDecimal,
    required this.stopLossDecimal,
    required this.takeProfitDecimal,
    required this.leverageDecimal,
    required this.riskPercentDecimal,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    required this.targetCapsuleRootHex,
  });
}
