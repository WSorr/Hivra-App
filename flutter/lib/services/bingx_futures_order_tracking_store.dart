import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/bingx_futures_order_tracking_models.dart';
import 'atomic_file_write_service.dart';
import 'capsule_file_store.dart';

class BingxFuturesOrderTrackingStore {
  static const String _stateFileName = 'bingx_futures_order_tracking.v1.json';
  static const int _maxLiquidityEventClaims = 256;

  final String? Function() _readActiveCapsuleRootHex;
  final CapsuleFileStore _fileStore;
  final AtomicFileWriteService _atomicWrites;
  Future<void> _mutationTail = Future<void>.value();

  BingxFuturesOrderTrackingStore({
    required String? Function() readActiveCapsuleRootHex,
    CapsuleFileStore? fileStore,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _fileStore = fileStore ?? const CapsuleFileStore(),
       _atomicWrites = atomicWrites;

  Future<void> save(BingxFuturesOrderTrackingState state) async {
    final capsuleRootHex = activeCapsuleRootHex;
    if (capsuleRootHex == null) return;
    return _serialized(
      () =>
          _saveForCapsule(capsuleRootHex, state, preserveExistingClaims: true),
    );
  }

  Future<void> saveReconciledForCapsule(
    String capsuleRootHex,
    BingxFuturesOrderTrackingState state,
  ) {
    return _serialized(
      () =>
          _saveForCapsule(capsuleRootHex, state, preserveExistingClaims: false),
    );
  }

  Future<void> _saveForCapsule(
    String capsuleRootHex,
    BingxFuturesOrderTrackingState state, {
    required bool preserveExistingClaims,
  }) async {
    final file = await _stateFileForCapsule(capsuleRootHex, createDir: true);
    if (file == null) return;
    final existing = await _readState(file);
    final mergedState = BingxFuturesOrderTrackingState(
      trackedSymbol: state.trackedSymbol,
      trackedOrderId: state.trackedOrderId,
      managedOrderIds: state.managedOrderIds,
      managedOrderSymbols: state.managedOrderSymbols,
      managedOrderProvenance: state.managedOrderProvenance,
      liquidityEventEffectClaims:
          preserveExistingClaims
              ? existing?.liquidityEventEffectClaims ??
                  state.liquidityEventEffectClaims
              : state.liquidityEventEffectClaims,
      stopLossPercent: state.stopLossPercent,
      takeProfitRiskReward: state.takeProfitRiskReward,
    );
    if (mergedState.isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await _atomicWrites.writeString(file, jsonEncode(mergedState.toJson()));
  }

  Future<BingxFuturesOrderTrackingState?> load() async {
    final capsuleRootHex = activeCapsuleRootHex;
    if (capsuleRootHex == null) return null;
    return loadForCapsule(capsuleRootHex);
  }

  Future<BingxFuturesOrderTrackingState?> loadForCapsule(
    String capsuleRootHex,
  ) async {
    await _mutationTail;
    final file = await _stateFileForCapsule(capsuleRootHex, createDir: false);
    if (file == null || !await file.exists()) return null;
    return _readState(file);
  }

  String? get activeCapsuleRootHex =>
      _normalizeCapsuleHex(_readActiveCapsuleRootHex());

  Future<BingxLiquidityEventEffectReservation> reserveLiquidityEventEffect({
    required String liquidityEventId,
    required String clientOrderId,
    required String symbol,
    required String side,
    String? intentHashHex,
    String? canonicalIntentJson,
    required bool testOrder,
    required String recordedAtUtc,
    String? accountBindingHashHex,
  }) {
    final capsuleRootHex = activeCapsuleRootHex;
    if (capsuleRootHex == null) {
      return Future<BingxLiquidityEventEffectReservation>.value(
        BingxLiquidityEventEffectReservation.unavailable,
      );
    }
    return reserveLiquidityEventEffectForCapsule(
      capsuleRootHex: capsuleRootHex,
      liquidityEventId: liquidityEventId,
      clientOrderId: clientOrderId,
      symbol: symbol,
      side: side,
      intentHashHex: intentHashHex,
      canonicalIntentJson: canonicalIntentJson,
      testOrder: testOrder,
      recordedAtUtc: recordedAtUtc,
      accountBindingHashHex: accountBindingHashHex,
    );
  }

  Future<BingxLiquidityEventEffectReservation>
  reserveLiquidityEventEffectForCapsule({
    required String capsuleRootHex,
    required String liquidityEventId,
    required String clientOrderId,
    required String symbol,
    required String side,
    String? intentHashHex,
    String? canonicalIntentJson,
    required bool testOrder,
    required String recordedAtUtc,
    String? accountBindingHashHex,
  }) {
    return _serialized(
      () => _reserveLiquidityEventEffect(
        capsuleRootHex: capsuleRootHex,
        liquidityEventId: liquidityEventId,
        clientOrderId: clientOrderId,
        symbol: symbol,
        side: side,
        intentHashHex: intentHashHex,
        canonicalIntentJson: canonicalIntentJson,
        testOrder: testOrder,
        recordedAtUtc: recordedAtUtc,
        accountBindingHashHex: accountBindingHashHex,
      ),
    );
  }

  Future<BingxLiquidityEventEffectReservation> _reserveLiquidityEventEffect({
    required String capsuleRootHex,
    required String liquidityEventId,
    required String clientOrderId,
    required String symbol,
    required String side,
    String? intentHashHex,
    String? canonicalIntentJson,
    required bool testOrder,
    required String recordedAtUtc,
    String? accountBindingHashHex,
  }) async {
    final file = await _stateFileForCapsule(capsuleRootHex, createDir: true);
    if (file == null) return BingxLiquidityEventEffectReservation.unavailable;
    final current = await _readState(file) ?? _emptyState;
    final claim = BingxLiquidityEventEffectClaim(
      liquidityEventId: liquidityEventId.trim().toLowerCase(),
      clientOrderId: clientOrderId.trim(),
      symbol: symbol.trim().toUpperCase(),
      side: side.trim().toLowerCase(),
      intentHashHex: intentHashHex?.trim().toLowerCase(),
      canonicalIntentJson: canonicalIntentJson,
      testOrder: testOrder,
      status: BingxLiquidityEventEffectClaimStatus.reserved,
      orderId: null,
      accountBindingHashHex: accountBindingHashHex?.trim().toLowerCase(),
      recordedAtUtc: recordedAtUtc,
    );
    if (BingxLiquidityEventEffectClaim.fromJsonMap(claim.toJson()) == null) {
      return BingxLiquidityEventEffectReservation.unavailable;
    }
    if (current.liquidityEventEffectClaims.containsKey(claim.storageKey)) {
      return BingxLiquidityEventEffectReservation.alreadyClaimed;
    }
    if (current.liquidityEventEffectClaims.length >= _maxLiquidityEventClaims) {
      return BingxLiquidityEventEffectReservation.unavailable;
    }
    final claims = <String, BingxLiquidityEventEffectClaim>{
      ...current.liquidityEventEffectClaims,
      claim.storageKey: claim,
    };
    await _writeState(file, _copyWithClaims(current, claims));
    return BingxLiquidityEventEffectReservation.acquired;
  }

  Future<void> confirmLiquidityEventEffect({
    required String liquidityEventId,
    required bool testOrder,
    required String orderId,
  }) {
    final capsuleRootHex = activeCapsuleRootHex;
    if (capsuleRootHex == null) return Future<void>.value();
    return confirmLiquidityEventEffectForCapsule(
      capsuleRootHex: capsuleRootHex,
      liquidityEventId: liquidityEventId,
      testOrder: testOrder,
      orderId: orderId,
    );
  }

  Future<void> confirmLiquidityEventEffectForCapsule({
    required String capsuleRootHex,
    required String liquidityEventId,
    required bool testOrder,
    required String orderId,
  }) {
    return _serialized(
      () => _confirmLiquidityEventEffect(
        capsuleRootHex: capsuleRootHex,
        liquidityEventId: liquidityEventId,
        testOrder: testOrder,
        orderId: orderId,
      ),
    );
  }

  Future<void> _confirmLiquidityEventEffect({
    required String capsuleRootHex,
    required String liquidityEventId,
    required bool testOrder,
    required String orderId,
  }) async {
    final file = await _stateFileForCapsule(capsuleRootHex, createDir: false);
    if (file == null || !await file.exists()) return;
    final current = await _readState(file);
    if (current == null) return;
    final key =
        '${testOrder ? "test" : "live"}|${liquidityEventId.trim().toLowerCase()}';
    final existing = current.liquidityEventEffectClaims[key];
    if (existing == null) return;
    final claims = <String, BingxLiquidityEventEffectClaim>{
      ...current.liquidityEventEffectClaims,
      key: BingxLiquidityEventEffectClaim(
        liquidityEventId: existing.liquidityEventId,
        clientOrderId: existing.clientOrderId,
        symbol: existing.symbol,
        side: existing.side,
        intentHashHex: existing.intentHashHex,
        canonicalIntentJson: existing.canonicalIntentJson,
        testOrder: existing.testOrder,
        status: BingxLiquidityEventEffectClaimStatus.confirmed,
        orderId: orderId.trim().isEmpty ? null : orderId.trim(),
        accountBindingHashHex: existing.accountBindingHashHex,
        lifecycleStatus: existing.lifecycleStatus,
        lifecycleEvidenceAtUtc: existing.lifecycleEvidenceAtUtc,
        lifecycleDiagnostic: existing.lifecycleDiagnostic,
        recordedAtUtc: existing.recordedAtUtc,
      ),
    };
    await _writeState(file, _copyWithClaims(current, claims));
  }

  Future<void> clear() async {
    return _serialized(_clear);
  }

  Future<void> _clear() async {
    final file = await _stateFileForActiveCapsule(createDir: false);
    if (file == null || !await file.exists()) return;
    await file.delete();
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) => operation());
    _mutationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<BingxFuturesOrderTrackingState?> _readState(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return BingxFuturesOrderTrackingState.fromJsonMap(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _writeState(File file, BingxFuturesOrderTrackingState state) {
    return _atomicWrites.writeString(file, jsonEncode(state.toJson()));
  }

  BingxFuturesOrderTrackingState _copyWithClaims(
    BingxFuturesOrderTrackingState state,
    Map<String, BingxLiquidityEventEffectClaim> claims,
  ) {
    return BingxFuturesOrderTrackingState(
      trackedSymbol: state.trackedSymbol,
      trackedOrderId: state.trackedOrderId,
      managedOrderIds: state.managedOrderIds,
      managedOrderSymbols: state.managedOrderSymbols,
      managedOrderProvenance: state.managedOrderProvenance,
      liquidityEventEffectClaims:
          Map<String, BingxLiquidityEventEffectClaim>.unmodifiable(claims),
      stopLossPercent: state.stopLossPercent,
      takeProfitRiskReward: state.takeProfitRiskReward,
    );
  }

  static const BingxFuturesOrderTrackingState _emptyState =
      BingxFuturesOrderTrackingState(
        trackedSymbol: null,
        trackedOrderId: null,
        managedOrderIds: <String>[],
        managedOrderSymbols: <String, String>{},
        stopLossPercent: null,
        takeProfitRiskReward: null,
      );

  Future<File?> _stateFileForActiveCapsule({required bool createDir}) async {
    final capsuleHex = activeCapsuleRootHex;
    if (capsuleHex == null) return null;
    return _stateFileForCapsule(capsuleHex, createDir: createDir);
  }

  Future<File?> _stateFileForCapsule(
    String capsuleRootHex, {
    required bool createDir,
  }) async {
    final capsuleHex = _normalizeCapsuleHex(capsuleRootHex);
    if (capsuleHex == null) return null;
    final capsuleDir = await _fileStore.capsuleDirForHex(
      capsuleHex,
      create: createDir,
    );
    return File('${capsuleDir.path}/$_stateFileName');
  }

  String? _normalizeCapsuleHex(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.length != 64) return null;
    const hex = '0123456789abcdef';
    for (var i = 0; i < normalized.length; i++) {
      if (!hex.contains(normalized[i])) return null;
    }
    return normalized;
  }
}
