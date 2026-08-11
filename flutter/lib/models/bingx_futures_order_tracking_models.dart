enum BingxLiquidityEventEffectClaimStatus { reserved, confirmed }

enum BingxLiquidityEventEffectReservation {
  acquired,
  alreadyClaimed,
  unavailable,
}

class BingxLiquidityEventEffectClaim {
  final String liquidityEventId;
  final String clientOrderId;
  final String symbol;
  final String side;
  final bool testOrder;
  final BingxLiquidityEventEffectClaimStatus status;
  final String? orderId;
  final String recordedAtUtc;

  const BingxLiquidityEventEffectClaim({
    required this.liquidityEventId,
    required this.clientOrderId,
    required this.symbol,
    required this.side,
    required this.testOrder,
    required this.status,
    required this.orderId,
    required this.recordedAtUtc,
  });

  String get storageKey => '${testOrder ? "test" : "live"}|$liquidityEventId';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'liquidity_event_id': liquidityEventId,
    'client_order_id': clientOrderId,
    'symbol': symbol,
    'side': side,
    'test_order': testOrder,
    'status': status.name,
    'order_id': orderId,
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
      testOrder: map['test_order'] == true,
      status: status,
      orderId: orderId.isEmpty ? null : orderId,
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
    if (orderId.isEmpty ||
        symbol.isEmpty ||
        (side != 'buy' && side != 'sell') ||
        intentHashHex.isEmpty ||
        canonicalIntentJson.trim().isEmpty ||
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
      marketSnapshotHashHex: _readOptionalHash(map['market_snapshot_hash_hex']),
      featureHashHex: _readOptionalHash(map['feature_hash_hex']),
      tvhDecisionHashHex: _readOptionalHash(map['tvh_decision_hash_hex']),
      liveDecisionHashHex: _readOptionalHash(map['live_decision_hash_hex']),
      recordedAtUtc: recordedAtUtc,
    );
  }

  static String? _readOptionalHash(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

class BingxFuturesOrderTrackingState {
  final String? trackedSymbol;
  final String? trackedOrderId;
  final List<String> managedOrderIds;
  final Map<String, String> managedOrderSymbols;
  final Map<String, BingxManagedOrderProvenance> managedOrderProvenance;
  final Map<String, BingxLiquidityEventEffectClaim> liquidityEventEffectClaims;
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
      stopLossPercent == null &&
      takeProfitRiskReward == null;

  BingxFuturesOrderTrackingState reconcileOpenOrderIds(
    Iterable<String> openOrderIds,
  ) {
    final openIds =
        openOrderIds
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet();
    final retainedIds =
        managedOrderIds
            .map((value) => value.trim())
            .where(openIds.contains)
            .toSet()
            .toList()
          ..sort();
    final retainedIdSet = retainedIds.toSet();
    final retainedSymbols = <String, String>{
      for (final entry in managedOrderSymbols.entries)
        if (retainedIdSet.contains(entry.key)) entry.key: entry.value,
    };
    final retainedProvenance = <String, BingxManagedOrderProvenance>{
      for (final entry in managedOrderProvenance.entries)
        if (retainedIdSet.contains(entry.key)) entry.key: entry.value,
    };
    final currentTrackedOrderId = trackedOrderId?.trim() ?? '';
    final nextTrackedOrderId =
        retainedIdSet.contains(currentTrackedOrderId)
            ? currentTrackedOrderId
            : retainedIds.isEmpty
            ? null
            : retainedIds.first;
    final nextTrackedSymbol =
        nextTrackedOrderId == null
            ? null
            : retainedSymbols[nextTrackedOrderId] ?? trackedSymbol;

    return BingxFuturesOrderTrackingState(
      trackedSymbol: nextTrackedSymbol,
      trackedOrderId: nextTrackedOrderId,
      managedOrderIds: List<String>.unmodifiable(retainedIds),
      managedOrderSymbols: Map<String, String>.unmodifiable(retainedSymbols),
      managedOrderProvenance:
          Map<String, BingxManagedOrderProvenance>.unmodifiable(
            retainedProvenance,
          ),
      liquidityEventEffectClaims: liquidityEventEffectClaims,
      stopLossPercent: stopLossPercent,
      takeProfitRiskReward: takeProfitRiskReward,
    );
  }

  Map<String, dynamic> toJson() {
    final sortedProvenance =
        managedOrderProvenance.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final sortedClaims =
        liquidityEventEffectClaims.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      'version': 3,
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
      'stop_loss_percent': stopLossPercent,
      'take_profit_risk_reward': takeProfitRiskReward,
    };
  }

  static BingxFuturesOrderTrackingState? fromJsonMap(Map<String, dynamic> map) {
    final trackedSymbol = map['tracked_symbol']?.toString().trim();
    final trackedOrderId = map['tracked_order_id']?.toString().trim();
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
