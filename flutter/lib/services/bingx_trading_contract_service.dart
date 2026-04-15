import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'consensus_processor.dart';

typedef BingxConsensusSignableReader = ConsensusSignableResult Function(
  String peerHex,
);

enum BingxOrderSide {
  buy,
  sell,
}

enum BingxOrderType {
  market,
  limit,
}

enum BingxEntryMode {
  direct,
  zonePending,
}

enum BingxZoneSide {
  buyside,
  sellside,
}

enum BingxZonePriceRule {
  zoneLow,
  zoneMid,
  zoneHigh,
  manual,
}

class BingxSpotOrderIntent {
  final String pluginId;
  final String peerHex;
  final String clientOrderId;
  final String symbol;
  final BingxOrderSide side;
  final BingxOrderType orderType;
  final String quantityDecimal;
  final String? limitPriceDecimal;
  final String? timeInForce;
  final BingxEntryMode entryMode;
  final BingxZoneSide? zoneSide;
  final String? zoneLowDecimal;
  final String? zoneHighDecimal;
  final BingxZonePriceRule? zonePriceRule;
  final String? triggerPriceDecimal;
  final String? stopLossDecimal;
  final String? takeProfitDecimal;
  final String createdAtUtc;
  final String? strategyTag;
  final String canonicalJson;
  final String intentHashHex;

  const BingxSpotOrderIntent({
    required this.pluginId,
    required this.peerHex,
    required this.clientOrderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantityDecimal,
    required this.limitPriceDecimal,
    required this.timeInForce,
    required this.entryMode,
    required this.zoneSide,
    required this.zoneLowDecimal,
    required this.zoneHighDecimal,
    required this.zonePriceRule,
    required this.triggerPriceDecimal,
    required this.stopLossDecimal,
    required this.takeProfitDecimal,
    required this.createdAtUtc,
    required this.strategyTag,
    required this.canonicalJson,
    required this.intentHashHex,
  });
}

class BingxTradingExecutionResult {
  final BingxSpotOrderIntent? intent;
  final List<ConsensusBlockingFact> blockingFacts;

  const BingxTradingExecutionResult({
    required this.intent,
    required this.blockingFacts,
  });

  bool get isExecutable => intent != null && blockingFacts.isEmpty;
}

class BingxTradingContractService {
  static const String pluginId = 'hivra.contract.bingx-trading.v1';
  static const String contractKind = 'bingx_spot_order_intent';

  final BingxConsensusSignableReader _readSignable;

  const BingxTradingContractService({
    required BingxConsensusSignableReader readSignable,
  }) : _readSignable = readSignable;

  BingxTradingExecutionResult execute({
    required String peerHex,
    required String clientOrderId,
    required String symbol,
    required String side,
    required String orderType,
    required String quantityDecimal,
    required String? limitPriceDecimal,
    required String? timeInForce,
    required String? entryMode,
    required String? zoneSide,
    required String? zoneLowDecimal,
    required String? zoneHighDecimal,
    required String? zonePriceRule,
    required String? manualEntryPriceDecimal,
    required String? triggerPriceDecimal,
    required String? stopLossDecimal,
    required String? takeProfitDecimal,
    required String createdAtUtc,
    required String? strategyTag,
  }) {
    final signable = _readSignable(peerHex);
    if (!signable.isSignable) {
      return BingxTradingExecutionResult(
        intent: null,
        blockingFacts: signable.blockingFacts,
      );
    }

    final intent = evaluateDeterministic(
      peerHex: peerHex,
      clientOrderId: clientOrderId,
      symbol: symbol,
      side: side,
      orderType: orderType,
      quantityDecimal: quantityDecimal,
      limitPriceDecimal: limitPriceDecimal,
      timeInForce: timeInForce,
      entryMode: entryMode,
      zoneSide: zoneSide,
      zoneLowDecimal: zoneLowDecimal,
      zoneHighDecimal: zoneHighDecimal,
      zonePriceRule: zonePriceRule,
      manualEntryPriceDecimal: manualEntryPriceDecimal,
      triggerPriceDecimal: triggerPriceDecimal,
      stopLossDecimal: stopLossDecimal,
      takeProfitDecimal: takeProfitDecimal,
      createdAtUtc: createdAtUtc,
      strategyTag: strategyTag,
    );
    return BingxTradingExecutionResult(
      intent: intent,
      blockingFacts: const <ConsensusBlockingFact>[],
    );
  }

  BingxSpotOrderIntent evaluateDeterministic({
    required String peerHex,
    required String clientOrderId,
    required String symbol,
    required String side,
    required String orderType,
    required String quantityDecimal,
    required String? limitPriceDecimal,
    required String? timeInForce,
    required String? entryMode,
    required String? zoneSide,
    required String? zoneLowDecimal,
    required String? zoneHighDecimal,
    required String? zonePriceRule,
    required String? manualEntryPriceDecimal,
    required String? triggerPriceDecimal,
    required String? stopLossDecimal,
    required String? takeProfitDecimal,
    required String createdAtUtc,
    required String? strategyTag,
  }) {
    final normalizedPeer = peerHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedPeer)) {
      throw const FormatException('peer_hex must be a 64-char lowercase hex');
    }

    final normalizedClientOrderId = clientOrderId.trim();
    if (normalizedClientOrderId.isEmpty) {
      throw const FormatException('client_order_id is required');
    }
    if (normalizedClientOrderId.length > 128) {
      throw const FormatException('client_order_id must be <= 128 chars');
    }

    final normalizedSymbol = symbol.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,20}([-_/][A-Z0-9]{2,20})?$')
        .hasMatch(normalizedSymbol)) {
      throw const FormatException('symbol format is invalid');
    }

    final parsedSide = switch (side.trim().toLowerCase()) {
      'buy' => BingxOrderSide.buy,
      'sell' => BingxOrderSide.sell,
      _ => throw const FormatException('side must be buy or sell'),
    };
    final parsedOrderType = switch (orderType.trim().toLowerCase()) {
      'market' => BingxOrderType.market,
      'limit' => BingxOrderType.limit,
      _ => throw const FormatException('order_type must be market or limit'),
    };
    final parsedEntryMode =
        switch ((entryMode ?? 'direct').trim().toLowerCase()) {
      '' || 'direct' => BingxEntryMode.direct,
      'zone_pending' => BingxEntryMode.zonePending,
      _ => throw const FormatException(
          'entry_mode must be direct or zone_pending'),
    };

    final normalizedQuantity = _normalizeDecimal(
      quantityDecimal,
      field: 'quantity_decimal',
      maxScale: 8,
    );

    String? normalizedLimitPrice;
    String? normalizedTif;
    if (parsedOrderType == BingxOrderType.market) {
      if (limitPriceDecimal != null && limitPriceDecimal.trim().isNotEmpty) {
        throw const FormatException(
            'limit_price_decimal is not allowed for market orders');
      }
      if (timeInForce != null && timeInForce.trim().isNotEmpty) {
        throw const FormatException(
            'time_in_force is not allowed for market orders');
      }
    } else {
      if (parsedEntryMode == BingxEntryMode.direct) {
        if (limitPriceDecimal == null || limitPriceDecimal.trim().isEmpty) {
          throw const FormatException(
              'limit_price_decimal is required for limit orders');
        }
        normalizedLimitPrice = _normalizeDecimal(
          limitPriceDecimal,
          field: 'limit_price_decimal',
          maxScale: 8,
        );
      }
      normalizedTif = (timeInForce?.trim().toUpperCase() ?? 'GTC');
      if (!const <String>{'GTC', 'IOC', 'FOK'}.contains(normalizedTif)) {
        throw const FormatException('time_in_force must be GTC, IOC, or FOK');
      }
    }

    BingxZoneSide? parsedZoneSide;
    String? normalizedZoneLow;
    String? normalizedZoneHigh;
    BingxZonePriceRule? parsedZonePriceRule;
    String? normalizedTriggerPrice;
    String? normalizedStopLoss;
    String? normalizedTakeProfit;

    if (parsedEntryMode == BingxEntryMode.zonePending) {
      if (parsedOrderType != BingxOrderType.limit) {
        throw const FormatException(
            'entry_mode=zone_pending requires order_type=limit');
      }
      parsedZoneSide = switch ((zoneSide ?? '').trim().toLowerCase()) {
        'buyside' => BingxZoneSide.buyside,
        'sellside' => BingxZoneSide.sellside,
        _ => throw const FormatException(
            'zone_side must be buyside or sellside for zone_pending'),
      };
      if (parsedSide == BingxOrderSide.buy &&
          parsedZoneSide != BingxZoneSide.buyside) {
        throw const FormatException(
            'buy orders require zone_side=buyside in zone_pending mode');
      }
      if (parsedSide == BingxOrderSide.sell &&
          parsedZoneSide != BingxZoneSide.sellside) {
        throw const FormatException(
            'sell orders require zone_side=sellside in zone_pending mode');
      }

      normalizedZoneLow = _normalizeDecimal(
        zoneLowDecimal ?? '',
        field: 'zone_low_decimal',
        maxScale: 8,
      );
      normalizedZoneHigh = _normalizeDecimal(
        zoneHighDecimal ?? '',
        field: 'zone_high_decimal',
        maxScale: 8,
      );
      final lowScaled = _toScaledInt(normalizedZoneLow, scale: 8);
      final highScaled = _toScaledInt(normalizedZoneHigh, scale: 8);
      if (lowScaled >= highScaled) {
        throw const FormatException(
            'zone_low_decimal must be less than zone_high_decimal');
      }

      parsedZonePriceRule =
          switch ((zonePriceRule ?? 'zone_mid').trim().toLowerCase()) {
        'zone_low' => BingxZonePriceRule.zoneLow,
        'zone_mid' => BingxZonePriceRule.zoneMid,
        'zone_high' => BingxZonePriceRule.zoneHigh,
        'manual' => BingxZonePriceRule.manual,
        _ => throw const FormatException(
            'zone_price_rule must be zone_low, zone_mid, zone_high, or manual'),
      };

      String derivedEntryPrice;
      switch (parsedZonePriceRule) {
        case BingxZonePriceRule.zoneLow:
          derivedEntryPrice = normalizedZoneLow;
          break;
        case BingxZonePriceRule.zoneHigh:
          derivedEntryPrice = normalizedZoneHigh;
          break;
        case BingxZonePriceRule.zoneMid:
          final midScaled = (lowScaled + highScaled) ~/ BigInt.from(2);
          derivedEntryPrice = _fromScaledInt(midScaled, scale: 8);
          break;
        case BingxZonePriceRule.manual:
          final normalizedManual = _normalizeDecimal(
            manualEntryPriceDecimal ?? '',
            field: 'manual_entry_price_decimal',
            maxScale: 8,
          );
          final manualScaled = _toScaledInt(normalizedManual, scale: 8);
          if (manualScaled < lowScaled || manualScaled > highScaled) {
            throw const FormatException(
                'manual_entry_price_decimal must stay inside [zone_low_decimal, zone_high_decimal]');
          }
          derivedEntryPrice = normalizedManual;
          break;
      }

      normalizedLimitPrice = derivedEntryPrice;
      normalizedTif = (timeInForce?.trim().toUpperCase() ?? 'GTC');
      if (!const <String>{'GTC', 'IOC', 'FOK'}.contains(normalizedTif)) {
        throw const FormatException('time_in_force must be GTC, IOC, or FOK');
      }

      if (_isProvided(limitPriceDecimal)) {
        final providedLimitPrice = _normalizeDecimal(
          limitPriceDecimal!,
          field: 'limit_price_decimal',
          maxScale: 8,
        );
        if (providedLimitPrice != normalizedLimitPrice) {
          throw const FormatException(
              'limit_price_decimal must match derived zone entry price');
        }
      }

      normalizedTriggerPrice = _normalizeOptionalDecimal(
        triggerPriceDecimal,
        field: 'trigger_price_decimal',
      );
      normalizedStopLoss = _normalizeOptionalDecimal(
        stopLossDecimal,
        field: 'stop_loss_decimal',
      );
      normalizedTakeProfit = _normalizeOptionalDecimal(
        takeProfitDecimal,
        field: 'take_profit_decimal',
      );

      final entryScaled = _toScaledInt(normalizedLimitPrice, scale: 8);
      if (parsedSide == BingxOrderSide.buy) {
        if (normalizedStopLoss != null &&
            _toScaledInt(normalizedStopLoss, scale: 8) >= entryScaled) {
          throw const FormatException(
              'stop_loss_decimal must be below entry price for buy side');
        }
        if (normalizedTakeProfit != null &&
            _toScaledInt(normalizedTakeProfit, scale: 8) <= entryScaled) {
          throw const FormatException(
              'take_profit_decimal must be above entry price for buy side');
        }
      } else {
        if (normalizedStopLoss != null &&
            _toScaledInt(normalizedStopLoss, scale: 8) <= entryScaled) {
          throw const FormatException(
              'stop_loss_decimal must be above entry price for sell side');
        }
        if (normalizedTakeProfit != null &&
            _toScaledInt(normalizedTakeProfit, scale: 8) >= entryScaled) {
          throw const FormatException(
              'take_profit_decimal must be below entry price for sell side');
        }
      }
    } else {
      if (_isProvided(zoneSide) ||
          _isProvided(zoneLowDecimal) ||
          _isProvided(zoneHighDecimal) ||
          _isProvided(zonePriceRule) ||
          _isProvided(manualEntryPriceDecimal) ||
          _isProvided(triggerPriceDecimal) ||
          _isProvided(stopLossDecimal) ||
          _isProvided(takeProfitDecimal)) {
        throw const FormatException(
            'zone_* parameters require entry_mode=zone_pending');
      }
    }

    final normalizedCreatedAtUtc = createdAtUtc.trim();
    if (!_isIsoUtc(normalizedCreatedAtUtc)) {
      throw const FormatException(
          'created_at_utc must be ISO-8601 UTC instant');
    }

    final normalizedStrategyTag = strategyTag?.trim();
    if (normalizedStrategyTag != null && normalizedStrategyTag.length > 64) {
      throw const FormatException('strategy_tag must be <= 64 chars');
    }

    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plugin_id': pluginId,
      'contract_kind': contractKind,
      'peer_hex': normalizedPeer,
      'client_order_id': normalizedClientOrderId,
      'symbol': normalizedSymbol,
      'side': parsedSide.name,
      'order_type': parsedOrderType.name,
      'quantity_decimal': normalizedQuantity,
      'limit_price_decimal': normalizedLimitPrice,
      'time_in_force': normalizedTif,
      'entry_mode': parsedEntryMode == BingxEntryMode.zonePending
          ? 'zone_pending'
          : 'direct',
      'zone_side': parsedZoneSide?.name,
      'zone_low_decimal': normalizedZoneLow,
      'zone_high_decimal': normalizedZoneHigh,
      'zone_price_rule': switch (parsedZonePriceRule) {
        BingxZonePriceRule.zoneLow => 'zone_low',
        BingxZonePriceRule.zoneMid => 'zone_mid',
        BingxZonePriceRule.zoneHigh => 'zone_high',
        BingxZonePriceRule.manual => 'manual',
        null => null,
      },
      'trigger_price_decimal': normalizedTriggerPrice,
      'stop_loss_decimal': normalizedStopLoss,
      'take_profit_decimal': normalizedTakeProfit,
      'created_at_utc': normalizedCreatedAtUtc,
      'strategy_tag':
          normalizedStrategyTag == null || normalizedStrategyTag.isEmpty
              ? null
              : normalizedStrategyTag,
    });
    final intentHashHex = sha256.convert(utf8.encode(canonical)).toString();

    return BingxSpotOrderIntent(
      pluginId: pluginId,
      peerHex: normalizedPeer,
      clientOrderId: normalizedClientOrderId,
      symbol: normalizedSymbol,
      side: parsedSide,
      orderType: parsedOrderType,
      quantityDecimal: normalizedQuantity,
      limitPriceDecimal: normalizedLimitPrice,
      timeInForce: normalizedTif,
      entryMode: parsedEntryMode,
      zoneSide: parsedZoneSide,
      zoneLowDecimal: normalizedZoneLow,
      zoneHighDecimal: normalizedZoneHigh,
      zonePriceRule: parsedZonePriceRule,
      triggerPriceDecimal: normalizedTriggerPrice,
      stopLossDecimal: normalizedStopLoss,
      takeProfitDecimal: normalizedTakeProfit,
      createdAtUtc: normalizedCreatedAtUtc,
      strategyTag:
          normalizedStrategyTag == null || normalizedStrategyTag.isEmpty
              ? null
              : normalizedStrategyTag,
      canonicalJson: canonical,
      intentHashHex: intentHashHex,
    );
  }

  String _normalizeDecimal(
    String value, {
    required String field,
    required int maxScale,
  }) {
    final raw = value.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(raw)) {
      throw FormatException('$field must be a positive decimal');
    }
    final parts = raw.split('.');
    final whole = parts[0].replaceFirst(RegExp(r'^0+'), '');
    final normalizedWhole = whole.isEmpty ? '0' : whole;
    var frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > maxScale) {
      throw FormatException('$field precision must be <= $maxScale');
    }
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    final normalized =
        frac.isEmpty ? normalizedWhole : '$normalizedWhole.$frac';
    if (normalized == '0') {
      throw FormatException('$field must be > 0');
    }
    return normalized;
  }

  bool _isIsoUtc(String value) {
    try {
      return DateTime.parse(value).isUtc;
    } catch (_) {
      return false;
    }
  }

  bool _isProvided(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  String? _normalizeOptionalDecimal(
    String? value, {
    required String field,
  }) {
    if (!_isProvided(value)) return null;
    return _normalizeDecimal(
      value!,
      field: field,
      maxScale: 8,
    );
  }

  BigInt _toScaledInt(String normalized, {required int scale}) {
    final parts = normalized.split('.');
    final whole = BigInt.parse(parts[0]);
    final fracRaw = parts.length == 2 ? parts[1] : '';
    final fracPadded = fracRaw.padRight(scale, '0');
    return whole * BigInt.from(10).pow(scale) + BigInt.parse(fracPadded);
  }

  String _fromScaledInt(BigInt value, {required int scale}) {
    final base = BigInt.from(10).pow(scale);
    final whole = value ~/ base;
    var frac = (value % base).toString().padLeft(scale, '0');
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    if (frac.isEmpty) return whole.toString();
    return '${whole.toString()}.$frac';
  }
}
