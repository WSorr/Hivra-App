import 'dart:convert';

import 'package:crypto/crypto.dart';

enum BingxFuturesRiskDecisionStatus {
  allowed,
  blocked,
}

class BingxFuturesRiskPolicy {
  final double maxRiskPerTradePercent;
  final double maxDailyLossPercent;
  final int maxConcurrentPositions;
  final int cooldownAfterLossStreak;
  final int cooldownMinutes;
  final Set<String> symbolAllowlist;
  final Set<String> symbolDenylist;

  const BingxFuturesRiskPolicy({
    required this.maxRiskPerTradePercent,
    required this.maxDailyLossPercent,
    required this.maxConcurrentPositions,
    required this.cooldownAfterLossStreak,
    required this.cooldownMinutes,
    this.symbolAllowlist = const <String>{},
    this.symbolDenylist = const <String>{},
  });
}

class BingxFuturesRiskGovernorInput {
  final String symbol;
  final String quantityDecimal;
  final String entryPriceDecimal;
  final String stopLossDecimal;
  final String accountEquityQuoteDecimal;
  final String realizedDailyPnlQuoteDecimal;
  final int concurrentPositions;
  final int lossStreakCount;
  final String? lastLossAtUtc;
  final String nowUtc;
  final String? exchangeMinimumQuantityDecimal;
  final String? exchangeMinimumNotionalQuoteDecimal;
  final String? exchangeReferencePriceDecimal;

  const BingxFuturesRiskGovernorInput({
    required this.symbol,
    required this.quantityDecimal,
    required this.entryPriceDecimal,
    required this.stopLossDecimal,
    required this.accountEquityQuoteDecimal,
    required this.realizedDailyPnlQuoteDecimal,
    required this.concurrentPositions,
    required this.lossStreakCount,
    required this.lastLossAtUtc,
    required this.nowUtc,
    this.exchangeMinimumQuantityDecimal,
    this.exchangeMinimumNotionalQuoteDecimal,
    this.exchangeReferencePriceDecimal,
  });
}

class BingxFuturesRiskDecision {
  final BingxFuturesRiskDecisionStatus status;
  final String reasonCode;
  final String reasonMessage;
  final String canonicalJson;
  final String decisionHashHex;
  final String maxAllowedQuantityDecimal;
  final String tradeRiskQuoteDecimal;
  final String tradeRiskLimitQuoteDecimal;
  final String dailyLossQuoteDecimal;
  final String dailyLossLimitQuoteDecimal;

  const BingxFuturesRiskDecision({
    required this.status,
    required this.reasonCode,
    required this.reasonMessage,
    required this.canonicalJson,
    required this.decisionHashHex,
    required this.maxAllowedQuantityDecimal,
    required this.tradeRiskQuoteDecimal,
    required this.tradeRiskLimitQuoteDecimal,
    required this.dailyLossQuoteDecimal,
    required this.dailyLossLimitQuoteDecimal,
  });
}

class BingxFuturesRiskGovernorService {
  const BingxFuturesRiskGovernorService();

  BingxFuturesRiskDecision evaluate({
    required BingxFuturesRiskGovernorInput input,
    required BingxFuturesRiskPolicy policy,
  }) {
    final symbol = input.symbol.trim().toUpperCase();
    if (symbol.isEmpty) {
      throw const FormatException('symbol is required');
    }
    final deny =
        policy.symbolDenylist.map((item) => item.toUpperCase()).toSet();
    final allow =
        policy.symbolAllowlist.map((item) => item.toUpperCase()).toSet();
    if (deny.contains(symbol)) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'risk_symbol_denied',
        reasonMessage: 'Symbol is denied by local risk policy',
      );
    }
    if (allow.isNotEmpty && !allow.contains(symbol)) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'risk_symbol_not_allowed',
        reasonMessage: 'Symbol is outside local allowlist',
      );
    }

    if (input.concurrentPositions >= policy.maxConcurrentPositions) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'risk_max_concurrent_positions',
        reasonMessage: 'Maximum concurrent positions reached',
      );
    }

    final now = _parseUtc(input.nowUtc, field: 'now_utc');
    if (input.lossStreakCount >= policy.cooldownAfterLossStreak &&
        policy.cooldownMinutes > 0 &&
        input.lastLossAtUtc != null &&
        input.lastLossAtUtc!.trim().isNotEmpty) {
      final lastLossAt = _parseUtc(input.lastLossAtUtc!, field: 'last_loss_at');
      final cooldownEnds =
          lastLossAt.add(Duration(minutes: policy.cooldownMinutes));
      if (now.isBefore(cooldownEnds)) {
        return _decision(
          input: input,
          policy: policy,
          status: BingxFuturesRiskDecisionStatus.blocked,
          reasonCode: 'risk_loss_streak_cooldown',
          reasonMessage: 'Loss streak cooldown is active',
        );
      }
    }

    final equity = _parsePositiveDecimal(
      input.accountEquityQuoteDecimal,
      field: 'account_equity_quote_decimal',
    );
    final dailyPnl = _parseDecimal(
      input.realizedDailyPnlQuoteDecimal,
      field: 'realized_daily_pnl_quote_decimal',
    );
    final dailyLoss = dailyPnl < 0 ? -dailyPnl : 0.0;
    final dailyLossLimit =
        equity * (policy.maxDailyLossPercent / 100.0).clamp(0.0, 1000000.0);
    if (dailyLoss > dailyLossLimit) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'risk_daily_loss_limit',
        reasonMessage: 'Daily loss limit exceeded',
        dailyLoss: dailyLoss,
        dailyLossLimit: dailyLossLimit,
      );
    }

    final quantity = _parsePositiveDecimal(
      input.quantityDecimal,
      field: 'quantity_decimal',
    );
    final entryPrice = _parsePositiveDecimal(
      input.entryPriceDecimal,
      field: 'entry_price_decimal',
    );
    final referencePrice = input.exchangeReferencePriceDecimal == null
        ? entryPrice
        : _parsePositiveDecimal(
            input.exchangeReferencePriceDecimal!,
            field: 'exchange_reference_price_decimal',
          );
    final minimumQuantity = _parseOptionalNonNegativeDecimal(
      input.exchangeMinimumQuantityDecimal,
      field: 'exchange_minimum_quantity_decimal',
    );
    final minimumNotional = _parseOptionalNonNegativeDecimal(
      input.exchangeMinimumNotionalQuoteDecimal,
      field: 'exchange_minimum_notional_quote_decimal',
    );
    final effectiveMinimumNotional = [
      minimumNotional,
      minimumQuantity * referencePrice,
    ].reduce((left, right) => left > right ? left : right);
    if (minimumQuantity > 0 && quantity < minimumQuantity) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'exchange_min_quantity',
        reasonMessage:
            'Order quantity ${_fmtDecimal(quantity, scale: 8)} is below '
            'BingX minimum ${_fmtDecimal(minimumQuantity, scale: 8)} '
            '(about ${_fmtDecimal(effectiveMinimumNotional, scale: 8)} USDT)',
      );
    }
    final orderNotional = quantity * referencePrice;
    if (minimumNotional > 0 && orderNotional < minimumNotional) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'exchange_min_notional',
        reasonMessage:
            'Order notional ${_fmtDecimal(orderNotional, scale: 8)} USDT is '
            'below BingX minimum ${_fmtDecimal(minimumNotional, scale: 8)} USDT',
      );
    }
    final stopLoss = _parsePositiveDecimal(
      input.stopLossDecimal,
      field: 'stop_loss_decimal',
    );
    final priceDistance = (entryPrice - stopLoss).abs();
    if (priceDistance <= 0) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'risk_stop_loss_invalid',
        reasonMessage: 'Stop-loss distance must be positive',
      );
    }

    final maxRiskQuote =
        equity * (policy.maxRiskPerTradePercent / 100.0).clamp(0.0, 1000000.0);
    final tradeRiskQuote = quantity * priceDistance;
    final maxAllowedQuantity = maxRiskQuote / priceDistance;
    if (tradeRiskQuote > maxRiskQuote) {
      return _decision(
        input: input,
        policy: policy,
        status: BingxFuturesRiskDecisionStatus.blocked,
        reasonCode: 'risk_per_trade_exceeded',
        reasonMessage: 'Per-trade risk exceeds configured limit',
        maxAllowedQuantity: maxAllowedQuantity,
        tradeRiskQuote: tradeRiskQuote,
        tradeRiskLimit: maxRiskQuote,
        dailyLoss: dailyLoss,
        dailyLossLimit: dailyLossLimit,
      );
    }

    return _decision(
      input: input,
      policy: policy,
      status: BingxFuturesRiskDecisionStatus.allowed,
      reasonCode: 'risk_allowed',
      reasonMessage: 'Risk gates passed',
      maxAllowedQuantity: maxAllowedQuantity,
      tradeRiskQuote: tradeRiskQuote,
      tradeRiskLimit: maxRiskQuote,
      dailyLoss: dailyLoss,
      dailyLossLimit: dailyLossLimit,
    );
  }

  BingxFuturesRiskDecision _decision({
    required BingxFuturesRiskGovernorInput input,
    required BingxFuturesRiskPolicy policy,
    required BingxFuturesRiskDecisionStatus status,
    required String reasonCode,
    required String reasonMessage,
    double maxAllowedQuantity = 0,
    double tradeRiskQuote = 0,
    double tradeRiskLimit = 0,
    double dailyLoss = 0,
    double dailyLossLimit = 0,
  }) {
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'risk_model': 'bingx_futures_risk_governor_v1',
      'symbol': input.symbol.trim().toUpperCase(),
      'status': status.name,
      'reason_code': reasonCode,
      'policy': <String, dynamic>{
        'max_risk_per_trade_percent':
            _fmtDecimal(policy.maxRiskPerTradePercent, scale: 8),
        'max_daily_loss_percent':
            _fmtDecimal(policy.maxDailyLossPercent, scale: 8),
        'max_concurrent_positions': policy.maxConcurrentPositions,
        'cooldown_after_loss_streak': policy.cooldownAfterLossStreak,
        'cooldown_minutes': policy.cooldownMinutes,
      },
      'metrics': <String, dynamic>{
        'exchange_minimum_quantity_decimal':
            input.exchangeMinimumQuantityDecimal?.trim() ?? '',
        'exchange_minimum_notional_quote_decimal':
            input.exchangeMinimumNotionalQuoteDecimal?.trim() ?? '',
        'exchange_reference_price_decimal':
            input.exchangeReferencePriceDecimal?.trim() ?? '',
        'max_allowed_quantity_decimal':
            _fmtDecimal(maxAllowedQuantity, scale: 8),
        'trade_risk_quote_decimal': _fmtDecimal(tradeRiskQuote, scale: 8),
        'trade_risk_limit_quote_decimal': _fmtDecimal(tradeRiskLimit, scale: 8),
        'daily_loss_quote_decimal': _fmtDecimal(dailyLoss, scale: 8),
        'daily_loss_limit_quote_decimal': _fmtDecimal(dailyLossLimit, scale: 8),
      },
    });
    final digest = sha256.convert(utf8.encode(canonical)).toString();
    return BingxFuturesRiskDecision(
      status: status,
      reasonCode: reasonCode,
      reasonMessage: reasonMessage,
      canonicalJson: canonical,
      decisionHashHex: digest,
      maxAllowedQuantityDecimal: _fmtDecimal(maxAllowedQuantity, scale: 8),
      tradeRiskQuoteDecimal: _fmtDecimal(tradeRiskQuote, scale: 8),
      tradeRiskLimitQuoteDecimal: _fmtDecimal(tradeRiskLimit, scale: 8),
      dailyLossQuoteDecimal: _fmtDecimal(dailyLoss, scale: 8),
      dailyLossLimitQuoteDecimal: _fmtDecimal(dailyLossLimit, scale: 8),
    );
  }

  DateTime _parseUtc(String raw, {required String field}) {
    final value = DateTime.tryParse(raw.trim())?.toUtc();
    if (value == null) {
      throw FormatException('$field must be valid UTC timestamp');
    }
    return value;
  }

  double _parsePositiveDecimal(String raw, {required String field}) {
    final value = _parseDecimal(raw, field: field);
    if (value <= 0) {
      throw FormatException('$field must be > 0');
    }
    return value;
  }

  double _parseOptionalNonNegativeDecimal(
    String? raw, {
    required String field,
  }) {
    if (raw == null || raw.trim().isEmpty) return 0;
    final value = _parseDecimal(raw, field: field);
    if (value < 0) {
      throw FormatException('$field must be >= 0');
    }
    return value;
  }

  double _parseDecimal(String raw, {required String field}) {
    final value = double.tryParse(raw.trim());
    if (value == null) {
      throw FormatException('$field must be decimal');
    }
    return value;
  }

  String _fmtDecimal(double value, {required int scale}) {
    return value.toStringAsFixed(scale).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
