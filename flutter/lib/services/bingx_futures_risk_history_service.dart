import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_risk_models.dart';
import 'atomic_file_write_service.dart';
import 'bingx_futures_exchange_service.dart';
import 'capsule_file_store.dart';

class BingxFuturesRiskHistoryProjection {
  final bool isComplete;
  final String realizedDailyPnlQuoteDecimal;
  final int lossStreakCount;
  final String? lastLossAtUtc;
  final int recordCount;
  final String? unavailableCode;
  final String? unavailableMessage;

  const BingxFuturesRiskHistoryProjection({
    required this.isComplete,
    required this.realizedDailyPnlQuoteDecimal,
    required this.lossStreakCount,
    required this.lastLossAtUtc,
    required this.recordCount,
    this.unavailableCode,
    this.unavailableMessage,
  });
}

class BingxFuturesRiskHistoryService {
  static const String _stateFileName = 'bingx_futures_risk_history.v1.json';
  static const int _incomeLimit = 1000;
  static const Duration _retention = Duration(days: 90);

  final String? Function() _readActiveCapsuleRootHex;
  final CapsuleFileStore _fileStore;
  final AtomicFileWriteService _atomicWrites;

  const BingxFuturesRiskHistoryService({
    required String? Function() readActiveCapsuleRootHex,
    CapsuleFileStore? fileStore,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _fileStore = fileStore ?? const CapsuleFileStore(),
       _atomicWrites = atomicWrites;

  Future<BingxFuturesRiskHistoryProjection> refresh({
    required BingxFuturesExchangeService exchangeService,
    required BingxFuturesApiCredentials credentials,
    required DateTime nowUtc,
  }) async {
    final normalizedNow = nowUtc.toUtc();
    final start = normalizedNow.subtract(_retention);
    final response = await exchangeService.getUserIncome(
      credentials: credentials,
      startTimeMs: start.millisecondsSinceEpoch,
      endTimeMs: normalizedNow.millisecondsSinceEpoch,
      incomeType: 'REALIZED_PNL',
      limit: _incomeLimit,
    );
    if (!response.isSuccess) {
      return BingxFuturesRiskHistoryProjection(
        isComplete: false,
        realizedDailyPnlQuoteDecimal: '0.00000000',
        lossStreakCount: 0,
        lastLossAtUtc: null,
        recordCount: 0,
        unavailableCode: response.exchangeCode,
        unavailableMessage: response.exchangeMessage,
      );
    }
    if (!response.sourceRecordsShapeValid ||
        response.records.length != response.sourceRecordCount) {
      return BingxFuturesRiskHistoryProjection(
        isComplete: false,
        realizedDailyPnlQuoteDecimal: '0.00000000',
        lossStreakCount: 0,
        lastLossAtUtc: null,
        recordCount: response.records.length,
        unavailableCode: 'income_history_invalid',
        unavailableMessage: 'BingX realized PnL response was not fully parsed',
      );
    }

    late final List<BingxFuturesRealizedPnlRecord> normalized;
    try {
      normalized = _normalize(
        response.records,
        startTimeMs: start.millisecondsSinceEpoch,
        endTimeMs: normalizedNow.millisecondsSinceEpoch,
      );
    } on FormatException catch (error) {
      return BingxFuturesRiskHistoryProjection(
        isComplete: false,
        realizedDailyPnlQuoteDecimal: '0.00000000',
        lossStreakCount: 0,
        lastLossAtUtc: null,
        recordCount: 0,
        unavailableCode: 'income_history_invalid',
        unavailableMessage: error.message,
      );
    }
    final snapshot = BingxFuturesRiskHistorySnapshot(
      records: normalized,
      refreshedAtUtc: normalizedNow.toIso8601String(),
    );
    final projection = project(snapshot: snapshot, nowUtc: normalizedNow);
    if (response.sourceRecordCount >= _incomeLimit) {
      return BingxFuturesRiskHistoryProjection(
        isComplete: false,
        realizedDailyPnlQuoteDecimal: projection.realizedDailyPnlQuoteDecimal,
        lossStreakCount: projection.lossStreakCount,
        lastLossAtUtc: projection.lastLossAtUtc,
        recordCount: projection.recordCount,
        unavailableCode: 'income_history_truncated',
        unavailableMessage:
            'BingX returned the maximum $_incomeLimit realized PnL records',
      );
    }
    try {
      await _save(snapshot);
    } catch (error) {
      return BingxFuturesRiskHistoryProjection(
        isComplete: false,
        realizedDailyPnlQuoteDecimal: '0.00000000',
        lossStreakCount: 0,
        lastLossAtUtc: null,
        recordCount: normalized.length,
        unavailableCode: 'risk_history_persist_failed',
        unavailableMessage: error.toString(),
      );
    }
    return projection;
  }

  BingxFuturesRiskHistoryProjection project({
    required BingxFuturesRiskHistorySnapshot snapshot,
    required DateTime nowUtc,
  }) {
    final normalizedNow = nowUtc.toUtc();
    final dayStart = DateTime.utc(
      normalizedNow.year,
      normalizedNow.month,
      normalizedNow.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    var dailyPnl = 0.0;
    for (final record in snapshot.records) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        record.timestampMs,
        isUtc: true,
      );
      if (!timestamp.isBefore(dayStart) && timestamp.isBefore(dayEnd)) {
        dailyPnl += double.parse(record.incomeQuoteDecimal);
      }
    }

    String? lastLossAtUtc;
    for (final record in snapshot.records.reversed) {
      final pnl = double.parse(record.incomeQuoteDecimal);
      if (pnl < 0) {
        lastLossAtUtc =
            DateTime.fromMillisecondsSinceEpoch(
              record.timestampMs,
              isUtc: true,
            ).toIso8601String();
        break;
      }
    }
    var streak = 0;
    for (final record in snapshot.records.reversed) {
      final pnl = double.parse(record.incomeQuoteDecimal);
      if (pnl == 0) continue;
      if (pnl < 0) {
        streak += 1;
      } else {
        break;
      }
    }
    return BingxFuturesRiskHistoryProjection(
      isComplete: true,
      realizedDailyPnlQuoteDecimal: dailyPnl.toStringAsFixed(8),
      lossStreakCount: streak,
      lastLossAtUtc: lastLossAtUtc,
      recordCount: snapshot.records.length,
    );
  }

  Future<BingxFuturesRiskHistorySnapshot?> load() async {
    final file = await _stateFile(createDir: false);
    if (file == null || !await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return BingxFuturesRiskHistorySnapshot.fromJsonMap(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  List<BingxFuturesRealizedPnlRecord> _normalize(
    List<BingxFuturesIncomeRecord> records, {
    required int startTimeMs,
    required int endTimeMs,
  }) {
    final byId = <String, BingxFuturesRealizedPnlRecord>{};
    for (final record in records) {
      if (record.incomeType != 'REALIZED_PNL') {
        throw const FormatException('Unexpected income type in PnL history');
      }
      if (record.asset != 'USDT') {
        throw const FormatException('Non-USDT realized PnL is unsupported');
      }
      if (record.timestampMs < startTimeMs || record.timestampMs > endTimeMs) {
        continue;
      }
      final pnl = double.tryParse(record.incomeQuoteDecimal);
      if (pnl == null || !pnl.isFinite) {
        throw const FormatException('Realized PnL amount is invalid');
      }
      final transactionId = record.transactionId.trim();
      final tradeId = record.tradeId.trim();
      if (transactionId.isEmpty && tradeId.isEmpty) {
        throw const FormatException('Realized PnL record has no stable id');
      }
      final identity =
          transactionId.isNotEmpty ? 'tran:$transactionId' : 'trade:$tradeId';
      final recordId = sha256.convert(utf8.encode(identity)).toString();
      final normalized = BingxFuturesRealizedPnlRecord(
        recordId: recordId,
        symbol: record.symbol.trim().toUpperCase(),
        incomeQuoteDecimal: pnl.toStringAsFixed(8),
        timestampMs: record.timestampMs,
        transactionId: transactionId,
        tradeId: tradeId,
      );
      final existing = byId[recordId];
      if (existing != null &&
          (existing.symbol != normalized.symbol ||
              existing.incomeQuoteDecimal != normalized.incomeQuoteDecimal ||
              existing.timestampMs != normalized.timestampMs ||
              existing.tradeId != normalized.tradeId)) {
        throw const FormatException('Conflicting realized PnL record id');
      }
      byId[recordId] = normalized;
    }
    final out =
        byId.values.toList()..sort((a, b) {
          final byTime = a.timestampMs.compareTo(b.timestampMs);
          return byTime != 0 ? byTime : a.recordId.compareTo(b.recordId);
        });
    return List.unmodifiable(out);
  }

  Future<void> _save(BingxFuturesRiskHistorySnapshot snapshot) async {
    final file = await _stateFile(createDir: true);
    if (file == null) {
      throw StateError('Active capsule is required for risk history');
    }
    await _atomicWrites.writeString(file, jsonEncode(snapshot.toJson()));
  }

  Future<File?> _stateFile({required bool createDir}) async {
    final capsuleHex = _normalizeCapsuleHex(_readActiveCapsuleRootHex());
    if (capsuleHex == null) return null;
    final dir = await _fileStore.capsuleDirForHex(
      capsuleHex,
      create: createDir,
    );
    return File('${dir.path}/$_stateFileName');
  }

  String? _normalizeCapsuleHex(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) return null;
    return normalized;
  }
}
