import 'dart:async';
import 'dart:convert';

import '../models/moltbook_provider_models.dart';
import '../models/external_effect_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_file_store.dart';

class MoltbookFeedCheckpointStore {
  static const String _fileName = 'feed_checkpoint.v1.json';

  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;
  Future<void> _writeTail = Future<void>.value();

  MoltbookFeedCheckpointStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    required String? Function() readActiveCapsuleRootHex,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  Future<MoltbookFeedCheckpoint> load() async {
    final ownerHex = _requireOwnerHex();
    return _loadForOwner(ownerHex);
  }

  Future<MoltbookFeedCheckpoint> save(MoltbookFeedCheckpoint checkpoint) {
    return _serialized(() async {
      final ownerHex = _requireOwnerHex();
      checkpoint.validate();
      final stored = await _readStore(ownerHex);
      await _writeStore(ownerHex, {...stored, ...checkpoint.toJson()});
      return checkpoint;
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeTail = _writeTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<MoltbookFeedCheckpoint> _loadForOwner(String ownerHex) async =>
      MoltbookFeedCheckpoint.fromJson(await _readStore(ownerHex));

  // These are safety budgets, never publication history or UI statistics.
  Future<({int writesToday, int? minutesSinceLastWrite})> writeUsage(
    String accountId,
    String effectKind,
    DateTime nowUtc,
  ) => _serialized(() async {
    final stored = await _readStore(_requireOwnerHex());
    final usage = _usage(stored, accountId, effectKind);
    final now = nowUtc.toUtc();
    final day = now.toIso8601String().substring(0, 10);
    final last = DateTime.tryParse(
      usage['last_write_at_utc']?.toString() ?? '',
    );
    return (
      writesToday: usage['day'] == day ? usage['count'] as int : 0,
      minutesSinceLastWrite:
          last == null
              ? null
              : now.difference(last).inMinutes.clamp(0, 1000000),
    );
  });

  Future<void> recordProcessedWrite(ExternalEffectOperation operation) =>
      _serialized(() async {
        final owner = _requireOwnerHex();
        if (operation.ownerCapsuleHex != owner || !operation.state.isTerminal) {
          throw StateError(
            'Only a completed effect in the active Capsule can settle',
          );
        }
        final stored = await _readStore(owner);
        // The marker exists only between accounting and deleting the effect.
        // A crash in that interval cannot charge the same write twice.
        if (stored['settling_operation_id'] == operation.operationId) return;
        final usage = _usage(
          stored,
          operation.accountBindingId,
          operation.effectKind,
        );
        final committed =
            operation.state == ExternalEffectState.succeeded ||
            (operation.state == ExternalEffectState.terminalFailure &&
                operation.providerReferenceId != null);
        if (committed) {
          final time =
              DateTime.parse(
                operation.approvedAtUtc ?? operation.updatedAtUtc,
              ).toUtc();
          final day = time.toIso8601String().substring(0, 10);
          final oldDay = usage['day'] as String?;
          if (oldDay == null || day.compareTo(oldDay) >= 0) {
            usage['count'] = (oldDay == day ? usage['count'] as int : 0) + 1;
            usage['day'] = day;
          }
          final last = DateTime.tryParse(
            usage['last_write_at_utc']?.toString() ?? '',
          );
          if (last == null || time.isAfter(last)) {
            usage['last_write_at_utc'] = time.toIso8601String();
          }
        }
        final budgets = Map<String, dynamic>.from(
          stored['write_usage'] as Map? ?? {},
        );
        budgets['${operation.accountBindingId}::${operation.effectKind}'] =
            usage;
        stored['write_usage'] = budgets;
        stored['settling_operation_id'] = operation.operationId;
        await _writeStore(owner, stored);
      });

  Future<void> finishProcessedWrite(String operationId) =>
      _serialized(() async {
        final owner = _requireOwnerHex();
        final stored = await _readStore(owner);
        if (stored['settling_operation_id'] == operationId) {
          stored.remove('settling_operation_id');
          await _writeStore(owner, stored);
        }
      });

  Map<String, dynamic> _usage(
    Map<String, dynamic> stored,
    String account,
    String kind,
  ) {
    final budgets = stored['write_usage'];
    if (budgets != null && (budgets is! Map || budgets.length > 128)) {
      throw const FormatException('Invalid Moltbook write budgets');
    }
    final raw = budgets is Map ? budgets['$account::$kind'] : null;
    if (raw == null) return <String, dynamic>{'count': 0};
    if (raw is! Map ||
        raw['count'] is! int ||
        (raw['count'] as int) < 0 ||
        (raw['day'] != null &&
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw['day'].toString())) ||
        (raw['last_write_at_utc'] != null &&
            DateTime.tryParse(raw['last_write_at_utc'].toString()) == null)) {
      throw const FormatException('Invalid Moltbook write budget');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> _readStore(String ownerHex) async {
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    final raw = await _fileStore.readPluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _fileName,
    );
    _ensureOwner(ownerHex);
    if (raw == null) {
      return {
        ...const MoltbookFeedCheckpoint.empty().toJson(),
        'plugin_id': moltbookAmbassadorPluginId,
      };
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['plugin_id'] != moltbookAmbassadorPluginId) {
      throw const FormatException('Invalid Moltbook feed checkpoint store');
    }
    final stored = Map<String, dynamic>.from(decoded);
    MoltbookFeedCheckpoint.fromJson(stored);
    return stored;
  }

  Future<void> _writeStore(String ownerHex, Map<String, dynamic> stored) async {
    _ensureOwner(ownerHex);
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    await _fileStore.writePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _fileName,
      const JsonEncoder.withIndent(
        '  ',
      ).convert({...stored, 'plugin_id': moltbookAmbassadorPluginId}),
    );
    _ensureOwner(ownerHex);
  }

  String _requireOwnerHex() {
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) {
      throw StateError('Active capsule identity is unavailable');
    }
    return ownerHex;
  }

  void _ensureOwner(String expectedOwnerHex) {
    if (_activeOwnerHex() != expectedOwnerHex) {
      throw StateError(
        'Active capsule changed during Moltbook checkpoint persistence',
      );
    }
  }

  String? _activeOwnerHex() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }
}
