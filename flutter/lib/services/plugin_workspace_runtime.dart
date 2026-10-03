import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/external_effect_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import '../models/wasm_plugin_models.dart';
import 'bingx_market_data_adapter.dart';
import 'capsule_file_store.dart';
import 'external_effect_service.dart';
import 'plugin_host_api_service.dart';
import 'wasm_plugin_registry_service.dart';

/// The single workspace executor shared by app and headless hosts.
/// Credentials are host ports; package state remains opaque.
class PluginWorkspaceRuntime {
  static final Map<String, Future<void>> _workspaceTails = {};
  static final Map<String, PluginWorkspaceRuntime> _scheduledHosts = {};
  static final Map<String, Timer> _scheduledTimers = {};
  static final Map<String, String> _scheduledBindings = {};
  static final Map<String, Object> _scheduledGenerations = {};
  static final Map<String, Map<String, dynamic>> _cycleObservations = {};
  static final Set<String> _dispatchLeases = {};
  static const _executionFile = 'workspace-execution.v1.json';
  static const _workspaceCandleBatchSize = 12;
  final WasmPluginRegistryService registry;
  final PluginHostApiService pluginHostApi;
  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;
  final Future<String?> Function({
    required String owner,
    required String pluginId,
  })
  _readCredentials;
  final Future<void> Function({
    required String owner,
    required String pluginId,
    required String? value,
  })
  _writeCredentials;
  final BingxMarketDataAdapter _market;
  final bool scheduleTimers;

  PluginWorkspaceRuntime({
    required this.registry,
    required this.pluginHostApi,
    required CapsuleFileStore fileStore,
    required String? Function() readActiveCapsuleRootHex,
    required Future<String?> Function({
      required String owner,
      required String pluginId,
    })
    readCredentials,
    required Future<void> Function({
      required String owner,
      required String pluginId,
      required String? value,
    })
    writeCredentials,
    BingxMarketDataAdapter? market,
    this.scheduleTimers = true,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _readCredentials = readCredentials,
       _writeCredentials = writeCredentials,
       _market = market ?? BingxMarketDataAdapter();

  String? activeCapsuleRootHex() => _readActiveCapsuleRootHex();

  Future<Map<String, dynamic>> runWorkspaceAction({
    required WasmPluginRecord record,
    required String action,
    Map<String, dynamic> settings = const {},
    String? optionsForField,
    Map<String, String>? credentials,
    Map<String, dynamic>? approvedOrder,
    int? executionRevision,
  }) async {
    final owner = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    final pluginId = record.pluginId;
    if (owner == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) ||
        pluginId == null ||
        record.contractKind != pluginWorkspaceContractKind ||
        !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(action) ||
        (optionsForField != null && action != 'open') ||
        (credentials != null && approvedOrder != null) ||
        (executionRevision != null && approvedOrder == null)) {
      throw StateError('Installed workspace and active Capsule are required');
    }
    final key = '$owner::$pluginId';
    return _serialize(
      key,
      () => _runWorkspaceOwned(
        owner,
        record,
        action,
        settings,
        optionsForField,
        credentials,
        approvedOrder,
        executionRevision,
      ),
    );
  }

  static Future<T> _serialize<T>(String key, Future<T> Function() work) async {
    final previous = _workspaceTails[key] ?? Future<void>.value();
    final result = previous.then((_) => work());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _workspaceTails[key] = tail;
    try {
      return await result;
    } finally {
      if (identical(_workspaceTails[key], tail)) _workspaceTails.remove(key);
    }
  }

  Future<Map<String, dynamic>> _runWorkspaceOwned(
    String owner,
    WasmPluginRecord record,
    String action,
    Map<String, dynamic> settings,
    String? optionsForField,
    Map<String, String>? credentials,
    Map<String, dynamic>? approvedOrder,
    int? executionRevision,
  ) async {
    final pluginId = record.pluginId!;
    final directory = await _fileStore.capsuleDirForHex(owner, create: true);
    final execution = await _readExecution(record, owner);
    const stateFile = 'workspace.v1.json';
    final saved = await _fileStore.readPluginState(
      directory,
      pluginId,
      stateFile,
    );
    Map<String, dynamic>? state;
    if (saved != null) {
      if (utf8.encode(saved).length > 32 * 1024) {
        throw StateError('Plugin state exceeds its limit');
      }
      final decoded = jsonDecode(saved);
      if (decoded is! Map) throw StateError('Plugin state is unreadable');
      state = Map<String, dynamic>.from(decoded);
    }
    String? invocationPackageDigest;
    Set<String> grantedCapabilities = {};
    var readingOpenOrders = false;
    var restoringEffects = false;
    Future<Map<String, dynamic>> invoke(
      String nextAction, {
      Map<String, dynamic>? snapshot,
    }) async {
      if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
      // Removal and update must be observed before every continuation.
      final installed = await registry.loadPlugins();
      if (!installed.any((r) => r.id == record.id && r.pluginId == pluginId)) {
        throw StateError('Plugin was removed or updated; reopen its workspace');
      }
      final response = await pluginHostApi.executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: pluginHostApiSchemaVersion,
          pluginId: pluginId,
          method: pluginWorkspaceMethod,
          args: {
            'action': nextAction,
            if (settings.isNotEmpty) 'settings': settings,
            'state': state,
            'observed_at_ms':
                snapshot?['observed_at_ms'] ??
                DateTime.now().toUtc().millisecondsSinceEpoch,
            if (execution != null)
              'execution': {
                'account_id': execution['scope']['account_id'],
                'symbol': execution['scope']['symbol'],
                'allow_new_entries':
                    execution['allow_new_entries'] == true &&
                    DateTime.now().millisecondsSinceEpoch <
                        execution['expires_at_ms'],
              },
            if (snapshot != null) 'snapshot': snapshot,
          },
        ),
      );
      if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
      if (response.executionPackageId != record.id ||
          (invocationPackageDigest != null &&
              invocationPackageDigest != response.executionPackageDigestHex)) {
        throw StateError('Plugin package changed during its action');
      }
      invocationPackageDigest = response.executionPackageDigestHex;
      grantedCapabilities = response.executionCapabilities.toSet();
      if (response.status != PluginHostApiStatus.executed ||
          response.result == null) {
        throw StateError(
          response.errorMessage ?? 'Plugin action could not run',
        );
      }
      final output = response.result!;
      final effectRequests = (output['requests'] as List).where(
        (r) =>
            r['kind'] == 'order.entry.place' ||
            r['kind'] == 'order.entry.cancel' ||
            r['kind'] == 'position.exit.place',
      );
      if (effectRequests.isNotEmpty &&
          (effectRequests.length != 1 ||
              approvedOrder == null ||
              _canonical(effectRequests.single) != _canonical(approvedOrder))) {
        throw StateError('Order request is not the confirmed effect');
      }
      readingOpenOrders |= (output['requests'] as List).any(
        (r) => r['kind'] == 'order.snapshot.read' && r['scope'] == 'open',
      );
      if (!readingOpenOrders) {
        state = Map<String, dynamic>.from(output['state'] as Map);
      }
      if (!readingOpenOrders &&
          !restoringEffects &&
          credentials == null &&
          approvedOrder == null) {
        await _fileStore.writePluginState(
          directory,
          pluginId,
          stateFile,
          jsonEncode(state),
        );
      }
      return output;
    }

    Future<Map<String, String>> savedCredentials() async {
      final raw = await _readCredentials(owner: owner, pluginId: pluginId);
      if (raw == null) throw StateError('Reconnect your BingX account');
      return _decodeCredentials(raw);
    }

    final adapter = _market.scopedEffects(
      credentials: (request) async {
        if (!_isStillOwnedBy(owner) ||
            request.ownerCapsuleHex != owner ||
            request.pluginId != pluginId) {
          throw StateError('Effect scope changed');
        }
        await invoke('open');
        if (!grantedCapabilities.contains('order.snapshot.read')) {
          throw StateError('Account/order read scope changed');
        }
        return savedCredentials();
      },
      authorize: (plan) async {
        final cancelling = approvedOrder?['kind'] == 'order.entry.cancel';
        final exiting = approvedOrder?['kind'] == 'position.exit.place';
        bool allowed() =>
            approvedOrder != null &&
            _canonical(plan) == _canonical(approvedOrder['plan']) &&
            grantedCapabilities.contains(
              exiting
                  ? 'position.exit.place'
                  : cancelling
                  ? 'order.entry.cancel'
                  : 'order.entry.place',
            ) &&
            grantedCapabilities.contains('order.snapshot.read') &&
            grantedCapabilities.contains('market.candles.read');
        final admission = await invoke(
          exiting
              ? 'validate_exit'
              : cancelling
              ? 'validate_cancel'
              : 'validate_entry',
        );
        if (!allowed()) throw StateError('Entry authority is unavailable');
        if (executionRevision != null) {
          await _authorizeScheduledEntry(
            record,
            owner,
            plan,
            executionRevision,
            exiting: exiting,
          );
        }
        if (cancelling || exiting) {
          if (admission['resume_action'] != null ||
              (admission['requests'] as List).isNotEmpty ||
              !grantedCapabilities.contains('position.snapshot.read')) {
            throw StateError(
              'Cancellation validation changed authority or requested effects',
            );
          }
          return;
        }
        final reads = List<Map<String, dynamic>>.from(
          (admission['requests'] as List).map(
            (r) => Map<String, dynamic>.from(r as Map),
          ),
        );
        if (admission['resume_action'] != null ||
            reads.isEmpty ||
            reads.length > 7 ||
            reads.any(
              (r) =>
                  r['kind'] != 'market.candles.read' ||
                  r['provider'] != 'bingx' ||
                  r['symbol'] != plan['symbol'],
            )) {
          throw StateError('Plugin must request bounded entry evidence');
        }
        for (final read in reads) {
          final quote = await _market.readCandles(read);
          final candles = quote['candles'] as List;
          for (
            var offset = 0;
            offset < candles.length;
            offset += _workspaceCandleBatchSize
          ) {
            final end = (offset + _workspaceCandleBatchSize).clamp(
              0,
              candles.length,
            );
            final checked = await invoke(
              'validate_entry',
              snapshot: {
                ...quote,
                'candles': candles.sublist(offset, end),
                'history_start_ms': (candles.first as List).first,
                'history_end_ms': (candles.last as List).first,
                'batch_complete': end == candles.length,
              },
            );
            if (!allowed() ||
                checked['resume_action'] != null ||
                (checked['requests'] as List).isNotEmpty) {
              throw StateError(
                'Entry validation changed authority or requested effects',
              );
            }
          }
        }
        if (!allowed()) throw StateError('Entry authority is unavailable');
        if (executionRevision != null) {
          await _authorizeScheduledEntry(
            record,
            owner,
            plan,
            executionRevision,
          );
        }
      },
    );
    final effects = ExternalEffectService(
      readActiveCapsuleRootHex: _readActiveCapsuleRootHex,
      fileStore: _fileStore,
      resolveAdapter: (provider) => provider == 'bingx' ? adapter : null,
    );

    var output = await invoke(action);
    Future<void> restoreEntry(
      Map<String, dynamic> request, {
      String? verifiedAccountId,
    }) async {
      bool allowed() =>
          grantedCapabilities.contains('order.snapshot.read') &&
          request['kind'] == 'order.snapshot.read' &&
          request['scope'] == 'durable' &&
          request['provider'] == 'bingx' &&
          request['account_id'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(request['account_id'] as String);
      if (!allowed()) throw StateError('Durable order read is unavailable');
      final accountId = request['account_id'] as String;
      if (verifiedAccountId == null) {
        await _market.verifyAccountBinding(accountId, await savedCredentials());
      } else if (verifiedAccountId != accountId) {
        throw StateError('Durable order read belongs to another account');
      }
      await invoke('open');
      if (!allowed()) throw StateError('Durable order read authority changed');
      final entries =
          (await effects.list(pluginId: pluginId))
              .where(
                (o) =>
                    o.providerId == 'bingx' && o.accountBindingId == accountId,
              )
              .toList();
      // Stream the journal unchanged; only the package selects what to recover.
      // Commit strategy state once the entire recovery read has succeeded.
      restoringEffects = true;
      try {
        const batchSize = 1;
        var offset = 0;
        do {
          final end = (offset + batchSize).clamp(0, entries.length);
          output = await invoke(
            'restore_entry',
            snapshot: {
              'account_id': accountId,
              'operations':
                  entries.sublist(offset, end).map((o) => o.toJson()).toList(),
              'batch_complete': end == entries.length,
            },
          );
          if (!allowed() ||
              output['resume_action'] != null ||
              (output['requests'] as List).isNotEmpty) {
            throw StateError(
              'Durable recovery changed authority or requested effects',
            );
          }
          offset = end;
        } while (offset < entries.length);
        await _fileStore.writePluginState(
          directory,
          pluginId,
          stateFile,
          jsonEncode(state),
        );
      } finally {
        restoringEffects = false;
      }
    }

    Future<void> restoreRequestedEntries({
      required String verifiedAccountId,
    }) async {
      final pending = output['requests'] as List;
      if (output['resume_action'] != null) {
        throw StateError('Nested workspace continuations are not supported');
      }
      if (pending.isEmpty) return;
      if (pending.length != 1 ||
          (pending.single as Map)['scope'] != 'durable') {
        throw StateError('Nested provider requests are not supported');
      }
      await restoreEntry(
        Map<String, dynamic>.from(pending.single as Map),
        verifiedAccountId: verifiedAccountId,
      );
    }

    if (optionsForField != null) {
      final fields = (output['view'] as Map)['fields'] as List;
      final matches = fields.where(
        (f) => (f as Map)['id'] == optionsForField && f['type'] == 'choice',
      );
      if (matches.length != 1 ||
          !grantedCapabilities.contains('market.instruments.read')) {
        throw StateError('Plugin requested an unavailable choice capability');
      }
      final source = Map<String, dynamic>.from(
        (matches.single as Map)['source'] as Map,
      );
      final options = await _market.readInstruments(source);
      // Use the same serialized invocation boundary after the asynchronous read;
      // a changed Capsule, removed package or replaced digest cannot continue.
      await invoke('open');
      if (!grantedCapabilities.contains('market.instruments.read')) {
        throw StateError('Instrument capability is no longer available');
      }
      return {'options': options};
    }
    final requests = List<Map<String, dynamic>>.from(
      (output['requests'] as List).map(
        (r) => Map<String, dynamic>.from(r as Map),
      ),
    );
    final resumeAction = output['resume_action'] as String?;
    if (credentials != null &&
        (requests.length != 1 ||
            requests.single['kind'] != 'account.connect')) {
      throw StateError('Plugin did not request an account connection');
    }
    if (approvedOrder != null &&
        (requests.length != 1 ||
            _canonical(requests.single) != _canonical(approvedOrder))) {
      throw StateError('Plugin did not request the exact confirmed effect');
    }
    for (final request in requests) {
      if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
      final kind = request['kind'];
      if (kind == 'order.snapshot.read' && request['scope'] == 'durable') {
        await restoreEntry(request);
        continue;
      }
      if (kind == 'order.snapshot.read' && request['scope'] == 'open') {
        bool allowed() =>
            grantedCapabilities.contains('order.snapshot.read') &&
            request['provider'] == 'bingx' &&
            request['account_id'] != null;
        if (!allowed()) throw StateError('Open-order read scope changed');
        final credentials = await savedCredentials();
        await invoke('open');
        if (!allowed()) throw StateError('Open-order read scope changed');
        final snapshot = await _market.readOpenOrders(request, credentials);
        await invoke('open');
        if (!allowed()) throw StateError('Open-order read scope changed');
        output = await invoke('open_orders', snapshot: snapshot);
        if (resumeAction != null ||
            output['resume_action'] != null ||
            (output['requests'] as List).isNotEmpty) {
          throw StateError('Nested provider requests are not supported');
        }
        continue;
      }
      if (kind == 'order.entry.place' ||
          kind == 'order.entry.cancel' ||
          kind == 'position.exit.place' ||
          kind == 'order.snapshot.read') {
        final cancelling = kind == 'order.entry.cancel';
        final exiting = kind == 'position.exit.place';
        final writing = kind != 'order.snapshot.read';
        if (!grantedCapabilities.contains(kind) ||
            !grantedCapabilities.contains('order.snapshot.read') ||
            (request['scope'] != null &&
                (kind != 'order.snapshot.read' ||
                    request['scope'] != 'lifecycle')) ||
            ((request['scope'] == 'lifecycle' || cancelling || exiting) &&
                !grantedCapabilities.contains('position.snapshot.read')) ||
            request['provider'] != 'bingx' ||
            request['plan'] is! Map ||
            (writing &&
                (approvedOrder == null ||
                    _canonical(request) != _canonical(approvedOrder)))) {
          throw StateError(
            'Order request is not authorized or changed after confirmation',
          );
        }
        final plan = Map<String, dynamic>.from(request['plan'] as Map);
        final entryPlan =
            exiting
                ? Map<String, dynamic>.from(plan['entry_plan'] as Map)
                : plan;
        final entryId = BingxMarketDataAdapter.entryOperationId(entryPlan);
        ExternalEffectOperation? originalEntry;
        if (cancelling || exiting) {
          final id = request['order_id'];
          if (cancelling &&
              (id is! String || !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(id))) {
            throw StateError('An exact cancellation order ID is required');
          }
          final originals =
              (await effects.list(pluginId: pluginId))
                  .where(
                    (o) =>
                        o.operationId == entryId &&
                        o.effectKind == 'order.entry.place' &&
                        o.canonicalPayloadJson == _canonical(entryPlan),
                  )
                  .toList();
          if (originals.length != 1) {
            throw StateError('Cancellation is not bound to a journaled entry');
          }
          originalEntry = originals.single;
        }
        final operationId =
            cancelling
                ? BingxMarketDataAdapter.cancelOperationId(
                  plan,
                  request['order_id'],
                )
                : exiting
                ? BingxMarketDataAdapter.exitOperationId(plan)
                : entryId;
        ExternalEffectOperation operation;
        if (writing) {
          operation = await _withEntryDispatchLease(owner, entryPlan, () async {
            if (exiting) {
              // Losing opaque package state must not authorize a second exit
              // for the same fill. Recovery must use the existing operation.
              final conflicting = (await effects.list(pluginId: pluginId)).any((
                o,
              ) {
                if (o.effectKind != 'position.exit.place' ||
                    o.operationId == operationId ||
                    (o.state == ExternalEffectState.terminalFailure &&
                        [
                          'exit_not_sent',
                          'provider_rejected',
                        ].contains(o.lastErrorCode))) {
                  return false;
                }
                final payload = jsonDecode(o.canonicalPayloadJson) as Map;
                return _canonical(payload['entry_plan']) ==
                    _canonical(entryPlan);
              });
              if (conflicting) {
                throw StateError(
                  'A journaled exit already exists for this entry',
                );
              }
            }
            final prepared = await effects.prepare(
              operationId: operationId,
              pluginId: pluginId,
              providerId: 'bingx',
              accountBindingId: entryPlan['account_id'] as String,
              effectKind: kind,
              canonicalPayloadJson: _canonical(
                cancelling
                    ? {'plan': plan, 'order_id': request['order_id']}
                    : plan,
              ),
            );
            if (prepared.state == ExternalEffectState.terminalFailure &&
                prepared.lastErrorCode ==
                    (cancelling ? 'cancel_not_sent' : 'entry_not_sent')) {
              await effects.reauthorizeRejectedDelivery(
                pluginId: pluginId,
                operationId: operationId,
                approvalEvidenceHashHex: prepared.payloadHashHex,
              );
            } else {
              await effects.approve(
                pluginId: pluginId,
                operationId: operationId,
                approvalEvidenceHashHex: prepared.payloadHashHex,
              );
              await effects.enqueue(
                pluginId: pluginId,
                operationId: operationId,
              );
            }
            await _fileStore.writePluginState(
              directory,
              pluginId,
              stateFile,
              jsonEncode(state),
            );
            return await effects.process(
              pluginId: pluginId,
              operationId: operationId,
            );
          });
        } else {
          final matches =
              (await effects.list(
                pluginId: pluginId,
              )).where((o) => o.operationId == operationId).toList();
          if (matches.length != 1 ||
              matches.single.canonicalPayloadJson != _canonical(plan)) {
            throw StateError('Exact entry is not in the durable journal');
          }
          operation = matches.single;
        }
        final observedOperation =
            exiting ? operation : originalEntry ?? operation;
        final bound = ExternalEffectAdapterRequest(
          ownerCapsuleHex: owner,
          operationId: exiting ? operationId : entryId,
          pluginId: pluginId,
          providerId: 'bingx',
          accountBindingId: observedOperation.accountBindingId,
          effectKind: observedOperation.effectKind,
          canonicalPayloadJson: observedOperation.canonicalPayloadJson,
          payloadHashHex: observedOperation.payloadHashHex,
          providerReferenceId:
              cancelling
                  ? request['order_id']
                  : operation.receipt?.providerReceiptId ??
                      operation.providerReferenceId,
        );
        final Map<String, dynamic> evidence;
        var evidenceAction =
            exiting
                ? 'exit'
                : request['scope'] == 'lifecycle' || cancelling
                ? 'lifecycle'
                : 'order';
        if (!cancelling &&
            operation.state == ExternalEffectState.terminalFailure &&
            [
              'entry_not_sent',
              'provider_rejected',
              'exit_not_sent',
            ].contains(operation.lastErrorCode)) {
          evidence = {
            'account_id': entryPlan['account_id'],
            'symbol': entryPlan['symbol'],
            'client_order_id': operationId.substring(0, 40),
            'order_id': null,
            'status':
                [
                      'entry_not_sent',
                      'exit_not_sent',
                    ].contains(operation.lastErrorCode)
                    ? 'not_sent'
                    : 'rejected',
            'filled_quantity': 0.0,
            'average_price': 0.0,
            'observed_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
            'error_message': operation.lastErrorMessage,
          };
          evidenceAction = exiting ? 'exit' : 'order';
        } else {
          try {
            ExternalEffectAdapterRequest? exit;
            if (request['exit_plan'] is Map) {
              if (request['scope'] != 'lifecycle') {
                throw StateError('Exit evidence requires lifecycle scope');
              }
              final exitPlan = Map<String, dynamic>.from(
                request['exit_plan'] as Map,
              );
              if (_canonical(exitPlan['entry_plan']) != _canonical(plan)) {
                throw StateError('Exit belongs to another entry');
              }
              final exitId = BingxMarketDataAdapter.exitOperationId(exitPlan);
              final matches =
                  (await effects.list(pluginId: pluginId))
                      .where(
                        (o) =>
                            o.operationId == exitId &&
                            o.effectKind == 'position.exit.place' &&
                            o.canonicalPayloadJson == _canonical(exitPlan),
                      )
                      .toList();
              if (matches.length != 1) {
                throw StateError('Exact exit is not in the durable journal');
              }
              final o = matches.single;
              exit = ExternalEffectAdapterRequest(
                ownerCapsuleHex: owner,
                operationId: exitId,
                pluginId: pluginId,
                providerId: 'bingx',
                accountBindingId: o.accountBindingId,
                effectKind: o.effectKind,
                canonicalPayloadJson: o.canonicalPayloadJson,
                payloadHashHex: o.payloadHashHex,
                providerReferenceId:
                    o.receipt?.providerReceiptId ?? o.providerReferenceId,
              );
              if (o.state == ExternalEffectState.unresolved ||
                  o.state == ExternalEffectState.delivering) {
                await effects.reconcileOnly(
                  pluginId: pluginId,
                  operationId: exitId,
                );
              }
            }
            evidence =
                exiting
                    ? await adapter.readExit(bound)
                    : request['scope'] == 'lifecycle' || cancelling
                    ? await adapter.readLifecycle(bound, exit: exit)
                    : await adapter.readEntry(bound);
          } catch (_) {
            throw StateError(
              'Exact order read unavailable; no new observation or resubmission',
            );
          }
        }
        await invoke('open');
        if (!grantedCapabilities.contains('order.snapshot.read') ||
            ((request['scope'] == 'lifecycle' || cancelling || exiting) &&
                !grantedCapabilities.contains('position.snapshot.read'))) {
          throw StateError('Order read authority changed');
        }
        output = await invoke(evidenceAction, snapshot: evidence);
        if (output['resume_action'] != null ||
            (output['requests'] as List).isNotEmpty) {
          throw StateError('Nested provider requests are not supported');
        }
        if (!cancelling && evidenceAction == 'lifecycle') {
          final orderId = (evidence['entry'] as Map)['order_id'];
          if (orderId is String) {
            final cancelId = BingxMarketDataAdapter.cancelOperationId(
              plan,
              orderId,
            );
            final pendingCancel = (await effects.list(pluginId: pluginId)).any(
              (o) =>
                  o.operationId == cancelId &&
                  o.effectKind == 'order.entry.cancel' &&
                  (o.state == ExternalEffectState.unresolved ||
                      o.state == ExternalEffectState.delivering),
            );
            // A racing fill may stop the package proposing cancellation.
            // Finish its durable request through read-only reconciliation.
            if (pendingCancel) {
              await effects.reconcileOnly(
                pluginId: pluginId,
                operationId: cancelId,
              );
            }
          }
        }
        if (cancelling &&
            operation.state == ExternalEffectState.terminalFailure) {
          // The current order evidence is already saved. Surface non-dispatch
          // without rewriting the package view or treating the entry as closed.
          throw StateError(
            operation.lastErrorMessage ?? 'No cancellation sent',
          );
        }
        continue;
      }
      if (kind == 'account.connect' || kind == 'account.snapshot.read') {
        if (!grantedCapabilities.contains(kind) ||
            request['provider'] != 'bingx' ||
            (kind == 'account.connect' &&
                (credentials == null || requests.length != 1))) {
          throw StateError(
            'Plugin requested an unavailable account capability',
          );
        }
        final previous = await _readCredentials(
          owner: owner,
          pluginId: pluginId,
        );
        final pair =
            kind == 'account.connect'
                ? credentials!
                : previous == null
                ? null
                : _decodeCredentials(previous);
        if (pair == null) throw StateError('Reconnect your BingX account');
        final snapshot = await _market.readAccount(request, pair);
        // Revalidate the package and grants after the network read, before
        // admitting the account evidence or changing its secure binding.
        await invoke('open');
        if (!grantedCapabilities.contains(kind)) {
          throw StateError('Account capability is no longer available');
        }
        if (kind == 'account.connect') {
          output = await invoke('account', snapshot: snapshot);
          var savedCredentials = false;
          try {
            await _writeCredentials(
              owner: owner,
              pluginId: pluginId,
              value: jsonEncode(pair),
            );
            savedCredentials = true;
            await invoke('open');
            if (!grantedCapabilities.contains(kind)) {
              throw StateError('Account capability is no longer available');
            }
            await restoreRequestedEntries(
              verifiedAccountId: snapshot['account_id'] as String,
            );
            await _fileStore.writePluginState(
              directory,
              pluginId,
              stateFile,
              jsonEncode(state),
            );
          } catch (_) {
            if (savedCredentials) {
              if (previous == null) {
                await _writeCredentials(
                  owner: owner,
                  pluginId: pluginId,
                  value: null,
                );
              } else {
                await _writeCredentials(
                  owner: owner,
                  pluginId: pluginId,
                  value: previous,
                );
              }
            }
            rethrow;
          }
        } else {
          output = await invoke('account', snapshot: snapshot);
          await restoreRequestedEntries(
            verifiedAccountId: snapshot['account_id'] as String,
          );
        }
        continue;
      }
      if (request['kind'] != 'market.candles.read' ||
          !grantedCapabilities.contains('market.candles.read')) {
        throw StateError('Plugin requested an unavailable capability');
      }
      final snapshot = await _market.readCandles(request);
      final candles = snapshot['candles'] as List;
      final historyEnd = (candles.last as List).first;
      // Streaming bounds one WASM invocation without interpreting its data.
      for (
        var offset = 0;
        offset < candles.length;
        offset += _workspaceCandleBatchSize
      ) {
        final end = (offset + _workspaceCandleBatchSize).clamp(
          0,
          candles.length,
        );
        output = await invoke(
          'market',
          snapshot: {
            ...snapshot,
            'candles': candles.sublist(offset, end),
            'history_end_ms': historyEnd,
            'batch_complete': end == candles.length,
          },
        );
        if (output['resume_action'] != null ||
            (output['requests'] as List).isNotEmpty) {
          throw StateError('Nested provider requests are not supported');
        }
      }
    }
    if (requests.any(
      (r) => r['kind'] == 'order.snapshot.read' && r['scope'] == 'open',
    )) {
      return Map<String, dynamic>.from(output['view'] as Map);
    }
    if (resumeAction != null) {
      if (!grantedCapabilities.contains('workspace.continue')) {
        throw StateError('Workspace continuation authority changed');
      }
      output = await invoke(resumeAction);
      if (output['resume_action'] != null ||
          (output['requests'] as List).isNotEmpty) {
        throw StateError('Workspace continuation must finish without requests');
      }
    }
    if (approvedOrder != null) {
      await _fileStore.writePluginState(
        directory,
        pluginId,
        stateFile,
        jsonEncode(state),
      );
    }
    final view = Map<String, dynamic>.from(output['view'] as Map);
    final currentExecution = await _readExecution(record, owner);
    if (currentExecution != null) {
      view['execution'] = _executionPresentation(
        currentExecution,
        _cycleObservations['$owner::$pluginId'],
      );
      _armScheduledExecution(record, owner, currentExecution);
    }
    return view;
  }

  /// A host-owned grant, never a field inside private package state.
  Future<Map<String, dynamic>> setWorkspaceExecution({
    required WasmPluginRecord record,
    required bool enabled,
    Map<String, dynamic>? approvedScope,
    Map<String, dynamic> settings = const {},
  }) async {
    final owner = activeCapsuleRootHex()?.trim().toLowerCase();
    if (owner == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) {
      throw StateError('An active Capsule is required');
    }
    final previous = await _readExecution(record, owner);
    final Map<String, dynamic> control;
    if (enabled) {
      final view = await runWorkspaceAction(record: record, action: 'open');
      final scope = Map<String, dynamic>.from(view['schedule'] as Map);
      _validateSchedule(scope);
      if (approvedScope == null ||
          _canonical(scope) != _canonical(approvedScope)) {
        throw StateError('Execution scope changed; confirm Start again');
      }
      if (settings.length > 8 ||
          utf8.encode(jsonEncode(settings)).length > 2048 ||
          settings.values.any((v) => v is! String && v is! num)) {
        throw StateError('Execution settings are invalid');
      }
      final binding = await registry.resolveRuntimeBinding(record.pluginId!);
      if (binding.packageId != record.id ||
          binding.packageDigestHex == null ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(binding.packageDigestHex!) ||
          !binding.capabilities.contains('workspace.schedule')) {
        throw StateError('Scheduled execution is not granted to this package');
      }
      control = {
        'version': 1,
        'owner': owner,
        'plugin_id': record.pluginId,
        'package_id': record.id,
        'package_digest': binding.packageDigestHex,
        'scope': scope,
        'settings': settings,
        'expires_at_ms':
            DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000,
        'allow_new_entries': true,
        'revision': (previous?['revision'] as int? ?? 0) + 1,
      };
    } else {
      if (previous == null) throw StateError('No scheduled execution to stop');
      // Persist revocation immediately, outside the action queue. An in-flight
      // read cannot defer Stop until after its provider write.
      control = {
        ...previous,
        'allow_new_entries': false,
        'revision': (previous['revision'] as int) + 1,
      };
    }
    if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
    await _serialize('$owner::${record.pluginId}::execution', () async {
      final current = await _readExecution(record, owner);
      if (current?['revision'] != previous?['revision']) {
        throw StateError('Execution authority changed during confirmation');
      }
      final binding = await registry.resolveRuntimeBinding(record.pluginId!);
      if (binding.packageId != control['package_id'] ||
          binding.packageDigestHex != control['package_digest'] ||
          !binding.capabilities.contains('workspace.schedule')) {
        throw StateError('Execution package changed during confirmation');
      }
      if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
      final directory = await _fileStore.capsuleDirForHex(owner, create: true);
      await _fileStore.writePluginState(
        directory,
        record.pluginId!,
        _executionFile,
        jsonEncode(control),
      );
    });
    _armScheduledExecution(record, owner, control);
    return runWorkspaceAction(record: record, action: 'open');
  }

  /// Both the foreground timer and a headless host enter this same path.
  Future<Map<String, dynamic>> runScheduledWorkspaceCycle(
    WasmPluginRecord record,
  ) async {
    final owner = activeCapsuleRootHex()?.trim().toLowerCase();
    if (owner == null) throw StateError('An active Capsule is required');
    final control = await _readExecution(record, owner);
    if (control == null) throw StateError('Start has not been authorized');
    final scope = Map<String, dynamic>.from(control['scope'] as Map);
    var view = await runWorkspaceAction(
      record: record,
      action: scope['action'] as String,
      settings: Map<String, dynamic>.from(control['settings'] as Map),
    );
    if (DateTime.now().millisecondsSinceEpoch < control['expires_at_ms'] &&
        view['confirmation'] is Map) {
      final request = Map<String, dynamic>.from(view['confirmation'] as Map);
      final exiting = request['kind'] == 'position.exit.place';
      if (!exiting && control['allow_new_entries'] != true) return view;
      final actions = (view['actions'] as List).where(
        (a) => a['host'] == 'bingx.order.submit',
      );
      if (actions.length != 1) {
        throw StateError('Package did not expose one entry action');
      }
      await _authorizeScheduledEntry(
        record,
        owner,
        Map<String, dynamic>.from(request['plan'] as Map),
        control['revision'] as int,
        exiting: exiting,
      );
      view = await runWorkspaceAction(
        record: record,
        action: actions.single['id'] as String,
        settings: Map<String, dynamic>.from(control['settings'] as Map),
        approvedOrder: request,
        executionRevision: control['revision'] as int,
      );
    }
    final latest = await _readExecution(record, owner);
    if (latest != null) {
      final observed = {
        'last_checked_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      _cycleObservations['$owner::${record.pluginId}'] = observed;
      view['execution'] = _executionPresentation(latest, observed);
    }
    return view;
  }

  Future<Map<String, dynamic>?> _readExecution(
    WasmPluginRecord record,
    String owner,
  ) async {
    final directory = await _fileStore.capsuleDirForHex(owner, create: false);
    var raw = await _fileStore.readPluginState(
      directory,
      record.pluginId!,
      _executionFile,
    );
    if (raw == null) return null;
    final binding = await registry.resolveRuntimeBinding(record.pluginId!);
    // Resolve only when a grant exists, then reread authority: Stop must not
    // be hidden behind an earlier snapshot during asynchronous package checks.
    raw = await _fileStore.readPluginState(
      directory,
      record.pluginId!,
      _executionFile,
    );
    if (raw == null) return null;
    if (utf8.encode(raw).length > 8192) {
      throw StateError('Execution grant exceeds the storage bound');
    }
    final control = jsonDecode(raw);
    if (control is! Map ||
        control['version'] != 1 ||
        control['owner'] != owner ||
        control['plugin_id'] != record.pluginId ||
        control['revision'] is! int ||
        control['revision'] <= 0 ||
        control['allow_new_entries'] is! bool ||
        control['expires_at_ms'] is! int ||
        control['settings'] is! Map ||
        control['scope'] is! Map) {
      throw StateError(
        'Execution grant is unreadable; no cycle or effect admitted',
      );
    }
    final settings = control['settings'] as Map;
    if (settings.length > 8 ||
        utf8.encode(jsonEncode(settings)).length > 2048 ||
        settings.values.any((v) => v is! String && v is! num)) {
      throw StateError('Execution settings are invalid');
    }
    _validateSchedule(Map<String, dynamic>.from(control['scope'] as Map));
    if (control['package_id'] != record.id ||
        binding.packageId != record.id ||
        control['package_digest'] != binding.packageDigestHex ||
        !binding.capabilities.contains('workspace.schedule')) {
      // Replaced/revoked code can still open its workspace for a new explicit
      // Start, but never inherits the previous package's execution authority.
      return null;
    }
    return Map<String, dynamic>.from(control);
  }

  static void _validateSchedule(Map<String, dynamic> scope) {
    if (scope.length != 6 ||
        scope['account_id'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(scope['account_id']) ||
        scope['symbol'] is! String ||
        (scope['symbol'] as String).length > 64 ||
        !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(scope['symbol']) ||
        scope['action'] is! String ||
        !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(scope['action']) ||
        scope['interval_seconds'] is! int ||
        scope['interval_seconds'] < 30 ||
        scope['interval_seconds'] > 3600 ||
        scope['max_margin'] is! num ||
        !scope['max_margin'].isFinite ||
        scope['max_margin'] <= 0 ||
        scope['max_stop_percent'] is! num ||
        !scope['max_stop_percent'].isFinite ||
        scope['max_stop_percent'] <= 0 ||
        scope['max_stop_percent'] > 100) {
      throw StateError('Invalid bounded execution scope');
    }
  }

  Future<void> _authorizeScheduledEntry(
    WasmPluginRecord record,
    String owner,
    Map<String, dynamic> plan,
    int revision, {
    bool exiting = false,
  }) async {
    final control = await _readExecution(record, owner);
    if (!_isStillOwnedBy(owner) ||
        control == null ||
        control['revision'] != revision ||
        (!exiting && control['allow_new_entries'] != true) ||
        DateTime.now().millisecondsSinceEpoch >= control['expires_at_ms']) {
      throw StateError('Start authority was stopped, expired or replaced');
    }
    final scope = control['scope'] as Map;
    if (exiting) {
      final entry = plan['entry_plan'];
      if (entry is! Map ||
          entry['account_id'] != scope['account_id'] ||
          entry['symbol'] != scope['symbol'] ||
          entry['margin'] is! num ||
          entry['margin'] > scope['max_margin']) {
        throw StateError('Exit exceeds the authorized account and instrument');
      }
      return;
    }
    final numbers = ['price', 'quantity', 'margin', 'stop_price', 'leverage'];
    if (plan['account_id'] != scope['account_id'] ||
        plan['symbol'] != scope['symbol'] ||
        numbers.any(
          (key) => plan[key] is! num || !plan[key].isFinite || plan[key] <= 0,
        ) ||
        plan['margin'] > scope['max_margin'] ||
        plan['quantity'] * plan['price'] / plan['leverage'] >
            scope['max_margin'] + 1e-9 ||
        (plan['price'] - plan['stop_price']).abs() * plan['quantity'] >
            plan['margin'] * scope['max_stop_percent'] / 100 + 1e-9) {
      throw StateError(
        'Entry exceeds the account, instrument, margin or stop authority',
      );
    }
  }

  static Map<String, dynamic> _executionPresentation(
    Map<String, dynamic> control,
    Map<String, dynamic>? observation,
  ) => {
    'mode': 'local',
    'allow_new_entries':
        control['allow_new_entries'] == true &&
        DateTime.now().millisecondsSinceEpoch < control['expires_at_ms'],
    'expires_at_ms': control['expires_at_ms'],
    'last_checked_at_ms': observation?['last_checked_at_ms'],
    'last_error': observation?['last_error'],
  };

  void _armScheduledExecution(
    WasmPluginRecord record,
    String owner,
    Map<String, dynamic> control,
  ) {
    if (!scheduleTimers) return;
    final key = '$owner::${record.pluginId}';
    final binding =
        '${record.id}::${control['package_digest']}::${control['revision']}';
    if (_scheduledHosts.containsKey(key) &&
        _scheduledBindings[key] == binding) {
      return;
    }
    _scheduledTimers.remove(key)?.cancel();
    _cycleObservations.remove(key);
    final generation = Object();
    _scheduledBindings[key] = binding;
    _scheduledGenerations[key] = generation;
    _scheduledHosts[key] = this;
    void arm() {
      _scheduledTimers[key] = Timer(
        Duration(seconds: control['scope']['interval_seconds']),
        () async {
          if (!identical(_scheduledGenerations[key], generation)) return;
          if (!_isStillOwnedBy(owner)) {
            _clearSchedule(key);
            return;
          }
          try {
            final current = await _readExecution(record, owner);
            if (!identical(_scheduledGenerations[key], generation)) return;
            if (current == null ||
                DateTime.now().millisecondsSinceEpoch >=
                    current['expires_at_ms']) {
              _clearSchedule(key);
              return;
            }
            await runScheduledWorkspaceCycle(record);
          } catch (_) {
            if (!identical(_scheduledGenerations[key], generation)) return;
            // Do not render network URLs, credentials or arbitrary provider text.
            try {
              final latest = await _readExecution(record, owner);
              if (!identical(_scheduledGenerations[key], generation)) return;
              if (latest != null) {
                _cycleObservations[key] = {
                  ...?_cycleObservations[key],
                  'last_error': 'Cycle unavailable; no unverified retry',
                };
              } else {
                _clearSchedule(key);
              }
            } catch (_) {
              if (identical(_scheduledGenerations[key], generation)) {
                _clearSchedule(key);
              }
            }
          }
          if (identical(_scheduledGenerations[key], generation) &&
              identical(_scheduledHosts[key], this)) {
            arm();
          }
        },
      );
    }

    arm();
  }

  static void _clearSchedule(String key) {
    _scheduledHosts.remove(key);
    _scheduledBindings.remove(key);
    _scheduledGenerations.remove(key);
    _scheduledTimers.remove(key)?.cancel();
    _cycleObservations.remove(key);
  }

  void stopWorkspaceScheduling({String? pluginId}) {
    for (final key in _scheduledHosts.keys.toList()) {
      if (pluginId == null
          ? identical(_scheduledHosts[key], this)
          : key.endsWith('::$pluginId')) {
        _clearSchedule(key);
      }
    }
  }

  Future<T> _withEntryDispatchLease<T>(
    String owner,
    Map<String, dynamic> plan,
    Future<T> Function() dispatch,
  ) async {
    if (plan['account_id'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(plan['account_id']) ||
        plan['symbol'] is! String ||
        (plan['symbol'] as String).length > 64 ||
        !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(plan['symbol'])) {
      throw StateError('Invalid entry dispatch scope');
    }
    final key = '$owner::${plan['account_id']}::${plan['symbol']}';
    if (!_dispatchLeases.add(key)) {
      throw StateError(
        'This account/instrument already has an entry dispatch in progress',
      );
    }
    RandomAccessFile? lock;
    try {
      final directory = await _fileStore.capsuleDirForHex(owner, create: true);
      lock = await File(
        '${directory.path}/workspace-entry-${plan['account_id']}-${plan['symbol']}.lock',
      ).open(mode: FileMode.append);
      // Nonblocking: a second process must not queue a financial write behind
      // another executor and later act on an already stale preflight.
      await lock.lock(FileLock.exclusive);
      return await dispatch();
    } finally {
      try {
        await lock?.close();
      } finally {
        _dispatchLeases.remove(key);
      }
    }
  }

  static String _canonical(dynamic value) {
    dynamic sorted(dynamic v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: sorted(v[k])};
      }
      if (v is List) return v.map(sorted).toList();
      return v;
    }

    return jsonEncode(sorted(value));
  }

  static Map<String, String> _decodeCredentials(String raw) {
    try {
      if (raw.length > 2048) throw const FormatException();
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded.length != 2 ||
          !['api_key', 'secret_key'].every(
            (key) =>
                decoded[key] is String &&
                RegExp(
                  r'^[A-Za-z0-9_-]{1,512}$',
                ).hasMatch(decoded[key] as String),
          )) {
        throw const FormatException();
      }
      return Map<String, String>.from(decoded);
    } catch (_) {
      // JSON parse errors can include their source: never render a vault value.
      throw StateError(
        'Saved BingX credentials are unreadable; reconnect your account',
      );
    }
  }

  Future<void> drainWorkspaceActions(String pluginId) => Future.wait(
    _workspaceTails.entries
        .where((entry) => entry.key.split('::')[1] == pluginId)
        .map((entry) => entry.value),
  );

  bool _isStillOwnedBy(String owner) =>
      _readActiveCapsuleRootHex()?.trim().toLowerCase() == owner;
}
