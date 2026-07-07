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

  static BingxManagedOrderProvenance? fromJsonMap(
    Map<String, dynamic> map,
  ) {
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
      marketSnapshotHashHex: _readOptionalHash(
        map['market_snapshot_hash_hex'],
      ),
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
  final double? stopLossPercent;
  final double? takeProfitRiskReward;

  const BingxFuturesOrderTrackingState({
    required this.trackedSymbol,
    required this.trackedOrderId,
    required this.managedOrderIds,
    required this.managedOrderSymbols,
    this.managedOrderProvenance = const <String, BingxManagedOrderProvenance>{},
    required this.stopLossPercent,
    required this.takeProfitRiskReward,
  });

  bool get isEmpty =>
      (trackedSymbol == null || trackedSymbol!.trim().isEmpty) &&
      (trackedOrderId == null || trackedOrderId!.trim().isEmpty) &&
      managedOrderIds.isEmpty &&
      managedOrderSymbols.isEmpty &&
      managedOrderProvenance.isEmpty &&
      stopLossPercent == null &&
      takeProfitRiskReward == null;

  Map<String, dynamic> toJson() {
    final sortedProvenance = managedOrderProvenance.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      'version': 2,
      'tracked_symbol': trackedSymbol?.trim().toUpperCase(),
      'tracked_order_id': trackedOrderId?.trim(),
      'managed_order_ids': managedOrderIds,
      'managed_order_symbols': managedOrderSymbols,
      'managed_order_provenance': <String, dynamic>{
        for (final entry in sortedProvenance) entry.key: entry.value.toJson(),
      },
      'stop_loss_percent': stopLossPercent,
      'take_profit_risk_reward': takeProfitRiskReward,
    };
  }

  static BingxFuturesOrderTrackingState? fromJsonMap(
    Map<String, dynamic> map,
  ) {
    final trackedSymbol = map['tracked_symbol']?.toString().trim();
    final trackedOrderId = map['tracked_order_id']?.toString().trim();
    final stopLossPercent = _readPositiveDouble(map['stop_loss_percent']);
    final takeProfitRiskReward =
        _readPositiveDouble(map['take_profit_risk_reward']);
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
    return BingxFuturesOrderTrackingState(
      trackedSymbol: trackedSymbol == null || trackedSymbol.isEmpty
          ? null
          : trackedSymbol.toUpperCase(),
      trackedOrderId: trackedOrderId == null || trackedOrderId.isEmpty
          ? null
          : trackedOrderId,
      managedOrderIds: List<String>.unmodifiable(managed.toList()..sort()),
      managedOrderSymbols:
          Map<String, String>.unmodifiable(Map<String, String>.fromEntries(
        managedSymbols.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      )),
      managedOrderProvenance:
          Map<String, BingxManagedOrderProvenance>.unmodifiable(
        Map<String, BingxManagedOrderProvenance>.fromEntries(
          provenance.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        ),
      ),
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
