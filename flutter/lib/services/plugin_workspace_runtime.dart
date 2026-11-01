import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/plugin_host_api_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/wasm_plugin_models.dart';
import 'plugin_capability_dispatcher.dart';
import 'capsule_file_store.dart';
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
  static const _executionFile = 'workspace-execution.v1.json';
  final WasmPluginRegistryService registry;
  final PluginHostApiService pluginHostApi;
  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;
  final Future<String?> Function({
    required String owner,
    required String pluginId,
  })?
  _readCredentials;
  final PluginCapabilityDispatcher _capabilities;
  final Future<Map<String, dynamic>> Function(
    Map<String, dynamic> request,
    Future<void> Function() authorize,
  )?
  infer;
  final Future<Map<String, String>> Function(
    String owner,
    Map<String, String> references,
  )?
  resolveCredentialReferences;
  final bool scheduleTimers;
  bool _schedulingClosed = false;
  final String executionHost;
  final String? executionIdentity;

  PluginWorkspaceRuntime({
    required this.registry,
    required this.pluginHostApi,
    required CapsuleFileStore fileStore,
    required String? Function() readActiveCapsuleRootHex,
    Future<String?> Function({required String owner, required String pluginId})?
    readCredentials,
    PluginCapabilityDispatcher? capabilities,
    this.infer,
    this.resolveCredentialReferences,
    this.scheduleTimers = true,
    this.executionHost = 'local',
    this.executionIdentity,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _readCredentials = readCredentials,
       _capabilities = capabilities ?? const PluginCapabilityDispatcher() {
    if (!{'local', 'vps'}.contains(executionHost)) {
      throw ArgumentError('Unsupported execution host');
    }
    if (executionHost == 'vps' &&
        (executionIdentity == null ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(executionIdentity!))) {
      throw ArgumentError(
        'VPS identity must be established by its host transport',
      );
    }
  }

  String? activeCapsuleRootHex() => _readActiveCapsuleRootHex();

  Future<Map<String, dynamic>?> readWorkspaceExecution(
    WasmPluginRecord record, {
    bool enforceHost = true,
    String? ownerCapsuleHex,
    bool allowRemoteRecoveryBinding = false,
  }) async {
    final owner =
        ownerCapsuleHex ?? activeCapsuleRootHex()?.trim().toLowerCase();
    if (owner == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) {
      throw StateError('An active Capsule is required');
    }
    return _readExecution(
      record,
      owner,
      enforceHost: enforceHost,
      allowRemoteRecoveryBinding: allowRemoteRecoveryBinding,
    );
  }

  /// Restore only host authority/timing. Provider availability must not be a
  /// prerequisite for bringing up the process that will retry observation.
  Future<void> resumeWorkspaceScheduling(WasmPluginRecord record) async {
    final owner = activeCapsuleRootHex()?.trim().toLowerCase();
    if (owner == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) {
      throw StateError('An active Capsule is required');
    }
    final control = await _readExecution(record, owner, enforceHost: false);
    if (control != null && (control['executor'] ?? 'local') != executionHost) {
      return;
    }
    if (control != null &&
        control['version'] == 2 &&
        workspaceExecutionIsActive(control)) {
      _armScheduledExecution(record, owner, control);
    }
  }

  Future<Map<String, dynamic>> runWorkspaceAction({
    required WasmPluginRecord record,
    required String action,
    Map<String, dynamic> settings = const {},
  }) async {
    final owner = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    final pluginId = record.pluginId;
    if (owner == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) ||
        pluginId == null ||
        record.contractKind != pluginWorkspaceContractKind ||
        !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(action)) {
      throw StateError('Installed workspace and active Capsule are required');
    }
    // Freeze owner input before waiting for another action's executor lease.
    final ownedSettings = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(settings)) as Map,
    );
    final key = '$owner::$pluginId';
    return _serialize(
      key,
      () => _withWorkspaceLease(
        owner,
        record,
        () => _runWorkspaceOwned(owner, record, action, ownedSettings),
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
  ) async {
    final pluginId = record.pluginId!;
    final directory = await _fileStore.capsuleDirForHex(owner, create: true);
    final initial = await registry.resolveRuntimeBinding(pluginId);
    final digest = initial.packageDigestHex;
    if (digest == null || initial.packageId != record.id) {
      throw StateError('Package binding unavailable');
    }
    final persistent = initial.capabilities.contains('state.plugin.read_write');
    final saved =
        persistent
            ? await _fileStore.readPluginState(
              directory,
              pluginId,
              'workspace.v1.json',
            )
            : null;
    Map<String, dynamic>? state =
        saved == null
            ? null
            : Map<String, dynamic>.from(jsonDecode(saved) as Map);
    final control = await _readExecution(record, owner);
    final invocationRevision = control?['revision'];
    final effectiveSettings =
        settings.isNotEmpty
            ? settings
            : Map<String, dynamic>.from(
              control?['settings'] as Map? ?? const {},
            );
    Map<String, dynamic>? currentView;
    dynamic continuationContext;

    Future<void> bound(String capability) async {
      if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
      final binding = await registry.resolveRuntimeBinding(pluginId);
      if (binding.packageId != record.id ||
          binding.packageDigestHex != digest ||
          !binding.capabilities.contains(capability) ||
          !_isStillOwnedBy(owner)) {
        throw StateError('Package or capability changed during the action');
      }
    }

    Future<Map<String, dynamic>> invoke(
      String next, {
      Map<String, dynamic>? result,
    }) async {
      await bound('workspace.continue');
      final current = await _readExecution(record, owner);
      final response = await pluginHostApi.executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: pluginHostApiSchemaVersion,
          pluginId: pluginId,
          method: pluginWorkspaceMethod,
          args: {
            'api_version': PluginCapabilityDispatcher.version,
            'action': next,
            'context': continuationContext,
            'state': state,
            if (effectiveSettings.isNotEmpty) 'settings': effectiveSettings,
            'observed_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
            'execution': {
              'enabled':
                  current?['version'] == 2 &&
                  (current != null && workspaceExecutionEnabled(current)) &&
                  workspaceExecutionIsActive(current),
              'scope': current?['version'] == 2 ? current!['scope'] : null,
              'running':
                  current?['scope']?['action'] != null &&
                  current?['version'] == 2 &&
                  workspaceExecutionEnabled(current!) &&
                  workspaceExecutionIsActive(current),
            },
            if (result != null) 'result': result,
          },
        ),
      );
      await bound('workspace.continue');
      if (response.executionPackageId != record.id ||
          response.executionPackageDigestHex != digest ||
          response.status != PluginHostApiStatus.executed ||
          response.result == null) {
        throw StateError(
          response.errorMessage ?? 'Package invocation unavailable',
        );
      }
      final output = response.result!;
      continuationContext = output['context'];
      state =
          output['state'] == null
              ? null
              : Map<String, dynamic>.from(output['state'] as Map);
      if (persistent && state != null) {
        await _fileStore.writePluginState(
          directory,
          pluginId,
          'workspace.v1.json',
          jsonEncode(state),
        );
      }
      currentView = Map<String, dynamic>.from(output['view'] as Map);
      return output;
    }

    Future<Map<String, dynamic>> accessFor(Map<String, dynamic> request) async {
      final current = await _readExecution(
        record,
        owner,
        requiredCapabilities: {
          if (request['kind'] == 'ai.infer')
            'inference.request'
          else
            'network.http',
          if (request['credential'] != null) 'credentials.use',
        },
      );
      // Legacy risk-scoped grants never become network permissions.
      if (!_isStillOwnedBy(owner) ||
          current == null ||
          current['version'] != 2 ||
          !workspaceExecutionEnabled(current) ||
          current['revision'] != invocationRevision ||
          !workspaceExecutionIsActive(current) ||
          !PluginCapabilityDispatcher.allows(
            current['scope']['access'] as Map,
            request,
          )) {
        throw StateError('Owner access is absent, revoked, expired or changed');
      }
      return Map<String, dynamic>.from(current['scope']['access'] as Map);
    }

    Future<Map<String, String>> secrets(Map<String, dynamic> request) async {
      final alias = request['credential'] as String;
      final fields = (control?['credentials'] as Map?)?[alias];
      if (fields is! Map) {
        throw StateError('Connect this credential in plugin permissions');
      }
      final references = Map<String, String>.from(fields);
      if (resolveCredentialReferences != null) {
        return resolveCredentialReferences!(owner, references);
      }
      // A remote executor receives only the connections explicitly transferred
      // by the owner; it has no access to the local Keychain.
      final raw = await _readCredentials?.call(
        owner: owner,
        pluginId: pluginId,
      );
      final stored = raw == null ? null : jsonDecode(raw);
      if (stored is! Map ||
          stored['version'] != 3 ||
          stored['connections'] is! Map) {
        throw StateError('Connected credentials unavailable');
      }
      final values = _decodeCredentials(
        jsonEncode(stored['connections'][alias]),
      );
      return {
        for (final field in references.keys)
          field:
              values[field] ??
              (throw StateError('Connected credential field unavailable')),
      };
    }

    var output = await invoke(action);
    for (var steps = 0; steps < 512; steps++) {
      final requests = output['requests'] as List;
      if (requests.isEmpty) {
        final view = currentView!;
        final current = await _readExecution(record, owner);
        if (current != null) {
          view['execution'] = _executionPresentation(
            current,
            _cycleObservations['$owner::$pluginId'],
          );
          _armScheduledExecution(record, owner, current);
        }
        return view;
      }
      final request = Map<String, dynamic>.from(requests.single as Map);
      final kind = request['kind'] as String;
      final continuation = request['continuation'] as String;
      Map<String, dynamic> result;
      switch (kind) {
        case 'runtime.yield':
          result = {};
        case 'runtime.wait':
          final delay = request['milliseconds'];
          if (delay is! int || delay < 0 || delay > 60000) {
            throw StateError('Wait exceeds runtime bound');
          }
          await Future<void>.delayed(Duration(milliseconds: delay));
          result = {};
        case 'api.describe':
          result = {
            'catalog': {
              for (final entry in PluginCapabilityDispatcher.catalog.entries)
                entry.key: {
                  ...entry.value,
                  'available': entry.key != 'ai.infer' || infer != null,
                },
            },
          };
        case 'ai.infer':
          if (infer == null) {
            result = {
              'outcome': 'not_dispatched',
              'error': 'capability_unavailable',
            };
          } else {
            var admitted = false;
            try {
              result = await infer!(
                {...request, 'plugin_id': pluginId},
                () async {
                  await accessFor(request);
                  admitted = true;
                },
              );
              if (utf8.encode(jsonEncode(result)).length >
                  PluginCapabilityDispatcher.maxBodyBytes) {
                result = {
                  'outcome': 'unknown',
                  'error': 'result_exceeds_bound',
                };
              }
            } catch (_) {
              result = {
                'outcome': admitted ? 'unknown' : 'not_dispatched',
                'error': 'inference_unavailable',
              };
            }
          }
        case 'http.request':
          final access =
              control?['version'] == 2
                  ? Map<String, dynamic>.from(
                    control!['scope']['access'] as Map,
                  )
                  : <String, dynamic>{'version': 2, 'network': []};
          result = await _capabilities.http(
            request,
            access: access,
            readCredentials: () => secrets(request),
            authorize: () async {
              await accessFor(request);
            },
          );
        case 'storage.read':
        case 'storage.write':
          await bound('state.plugin.read_write');
          final key = request['key'];
          if (!PluginCapabilityDispatcher.safeId(key) ||
              !(key as String).startsWith('data-')) {
            throw StateError('Storage key is outside package data');
          }
          if (kind == 'storage.write') {
            final value = request['value'];
            if (value is! String ||
                utf8.encode(value).length >
                    PluginCapabilityDispatcher.maxBodyBytes) {
              throw StateError('Storage value exceeds bound');
            }
            await _fileStore.writePluginState(directory, pluginId, key, value);
            result = {'written': true};
          } else {
            final value = await _fileStore.readPluginState(
              directory,
              pluginId,
              key,
            );
            if (value != null &&
                utf8.encode(value).length >
                    PluginCapabilityDispatcher.maxBodyBytes) {
              result = {'error': 'value_exceeds_bound'};
            } else {
              result = {'value': value};
            }
          }
        default:
          throw StateError('Unsupported capability operation');
      }
      output = await invoke(
        continuation,
        result: {'id': request['id'], ...result},
      );
    }
    throw StateError('Capability continuation budget exhausted');
  }

  /// A host-owned grant, never a field inside private package state.
  Future<Map<String, dynamic>> setWorkspaceExecution({
    required WasmPluginRecord record,
    required bool enabled,
    required int? expiresAtMs,
    int? expectedRevision,
    bool revoke = false,
    Map<String, dynamic>? approvedScope,
    Map<String, Map<String, String>>? credentialBindings,
    Map<String, dynamic> settings = const {},
    String? releaseToExecutorId,
  }) async {
    approvedScope =
        approvedScope == null
            ? null
            : Map<String, dynamic>.from(
              jsonDecode(jsonEncode(approvedScope)) as Map,
            );
    credentialBindings = credentialBindings?.map(
      (k, v) => MapEntry(k, Map<String, String>.from(v)),
    );
    settings = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(settings)) as Map,
    );
    if (enabled &&
        (revoke ||
            (expiresAtMs != null &&
                (expiresAtMs <= DateTime.now().millisecondsSinceEpoch ||
                    expiresAtMs > 8640000000000000)))) {
      throw StateError(
        'Choose a future deadline or authorize until revocation',
      );
    }
    final owner = activeCapsuleRootHex()?.trim().toLowerCase();
    if (owner == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) {
      throw StateError('An active Capsule is required');
    }
    if (releaseToExecutorId != null &&
        (!enabled ||
            executionHost != 'local' ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(releaseToExecutorId))) {
      throw StateError('Invalid VPS execution target');
    }
    final previous = await _readExecution(record, owner);
    if (settings.isEmpty && previous?['settings'] is Map) {
      settings = Map<String, dynamic>.from(previous!['settings'] as Map);
    }
    if (enabled && previous?['revision'] != expectedRevision) {
      throw StateError('Execution authority changed; review Start again');
    }
    final Map<String, dynamic> control;
    if (enabled) {
      if (approvedScope == null) {
        throw StateError('Owner permission scope is required');
      }
      final scope = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(approvedScope)) as Map,
      );
      validateWorkspaceExecutionSchedule(scope);
      if (scope['version'] != 2) {
        throw StateError('A common permission scope is required');
      }
      PluginCapabilityDispatcher.validateAccess(scope['access']);
      final credentials =
          credentialBindings ??
          (previous?['credentials'] is Map
              ? (previous!['credentials'] as Map).map(
                (k, v) =>
                    MapEntry(k as String, Map<String, String>.from(v as Map)),
              )
              : <String, Map<String, String>>{});
      final fields = scope['access']['credentials'] as Map? ?? const {};
      if (fields.entries.any(
        (e) => (e.value as List).any(
          (f) => credentials[e.key]?[f['id']]?.isNotEmpty != true,
        ),
      )) {
        throw StateError('Choose the Keychain secrets for this permission');
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
          (scope['action'] != null &&
              !binding.capabilities.contains('workspace.schedule'))) {
        throw StateError('Execution capability is not available');
      }
      control = {
        'version': 2,
        'owner': owner,
        'plugin_id': record.pluginId,
        'package_id': record.id,
        'package_digest': binding.packageDigestHex,
        'executor': releaseToExecutorId != null ? 'vps' : executionHost,
        if (releaseToExecutorId != null) ...{
          'executor_id': releaseToExecutorId,
          'handoff_id': sha256.convert(_handoffNonce()).toString(),
        },
        if (executionHost == 'vps') 'executor_id': executionIdentity,
        if (releaseToExecutorId == null && previous?['handoff_id'] != null)
          'handoff_id': previous!['handoff_id'],
        if (releaseToExecutorId == null && previous?['handoff_digest'] != null)
          'handoff_digest': previous!['handoff_digest'],
        'scope': scope,
        'credentials': {
          for (final e in fields.entries)
            e.key: {
              for (final field in e.value as List)
                field['id']: credentials[e.key]![field['id']]!,
            },
        },
        'settings': settings,
        'expires_at_ms': expiresAtMs,
        'revoked': false,
        'enabled': true,
        'revision': (previous?['revision'] as int? ?? 0) + 1,
      };
    } else {
      if (previous == null) throw StateError('No scheduled execution to stop');
      // Persist revocation immediately, outside the action queue. An in-flight
      // read cannot defer Stop until after its provider write.
      control = {
        ...previous,
        workspaceExecutionFlag(previous): false,
        if (revoke) 'revoked': true,
        'revision': (previous['revision'] as int) + 1,
      };
    }
    if (utf8.encode(jsonEncode(control)).length > 8192) {
      throw StateError('Permission metadata exceeds bound');
    }
    if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
    await _serialize(
      '$owner::${record.pluginId}::execution',
      () => _withWorkspaceLease(owner, record, () async {
        final current = await _readExecution(record, owner);
        if (current?['revision'] != previous?['revision']) {
          throw StateError('Execution authority changed during confirmation');
        }
        if (enabled &&
            expiresAtMs != null &&
            expiresAtMs <= DateTime.now().millisecondsSinceEpoch) {
          throw StateError(
            'Authorization deadline elapsed during confirmation',
          );
        }
        final binding = await registry.resolveRuntimeBinding(record.pluginId!);
        if (binding.packageId != control['package_id'] ||
            binding.packageDigestHex != control['package_digest'] ||
            (control['scope']['action'] != null &&
                !binding.capabilities.contains('workspace.schedule'))) {
          throw StateError('Execution package changed during confirmation');
        }
        if (!_isStillOwnedBy(owner)) throw StateError('Active Capsule changed');
        final directory = await _fileStore.capsuleDirForHex(
          owner,
          create: true,
        );
        await _fileStore.writePluginState(
          directory,
          record.pluginId!,
          _executionFile,
          jsonEncode(control),
        );
      }, authorityOnly: true),
    );
    _armScheduledExecution(record, owner, control);
    if (releaseToExecutorId != null) {
      stopWorkspaceScheduling(pluginId: record.pluginId);
      // The target has not acknowledged adoption yet. A source-side snapshot
      // is neither a running-local status nor evidence of a running VPS.
      return {'execution': _executionPresentation(control, null)};
    }
    return runWorkspaceAction(record: record, action: 'open');
  }

  static List<int> _handoffNonce() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
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
    String owner, {
    bool enforceHost = true,
    bool allowRemoteRecoveryBinding = false,
    Set<String> requiredCapabilities = const {},
  }) async {
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
    validateWorkspaceExecutionControl(control, owner, record.pluginId!);
    if (enforceHost &&
        ((control['executor'] ?? 'local') != executionHost ||
            (executionHost == 'vps' &&
                control['executor_id'] != executionIdentity))) {
      throw StateError(
        'Workspace execution belongs to VPS; connect to its current state',
      );
    }
    final packageMatches =
        control['package_id'] == record.id &&
        binding.packageId == record.id &&
        control['package_digest'] == binding.packageDigestHex;
    final remoteAuthority =
        control['executor'] == 'vps' ||
        (executionHost == 'vps' &&
            control['executor'] == 'local' &&
            control['expires_at_ms'] == 0 &&
            !workspaceExecutionEnabled(control));
    if ((!packageMatches &&
            !(allowRemoteRecoveryBinding && !enforceHost && remoteAuthority)) ||
        !binding.capabilities.toSet().containsAll(requiredCapabilities) ||
        (control['scope']['action'] != null &&
            !binding.capabilities.contains('workspace.schedule'))) {
      // A replaced package may not execute a stale local grant. A VPS grant
      // and its sealed return receipt remain readable only for authenticated
      // retirement. The original digest and opaque state are not rewritten;
      // ordinary execution still requires the current package binding.
      return null;
    }
    return Map<String, dynamic>.from(control);
  }

  /// Installation may rebind only a completely ended host grant.
  static void validateInactiveWorkspaceGrant(
    dynamic control,
    String owner,
    String pluginId,
  ) {
    validateWorkspaceExecutionControl(control, owner, pluginId);
    if (control['executor'] != 'local' ||
        control['expires_at_ms'] != 0 ||
        workspaceExecutionEnabled(control)) {
      throw StateError('Return remote authority before package replacement');
    }
  }

  /// Called by the host transport, never by WASM. The source stays detached
  /// even if upload or acknowledgement is lost; there is no local fallback.
  Future<Map<String, dynamic>> releaseWorkspaceToVps(
    WasmPluginRecord record, {
    required String executorId,
  }) async {
    final owner = activeCapsuleRootHex()?.trim().toLowerCase();
    if (executionHost != 'local' ||
        owner == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(executorId)) {
      throw StateError('A local workspace is required for handoff');
    }
    final key = '$owner::${record.pluginId}';
    return _serialize(
      key,
      () => _withWorkspaceLease(
        owner,
        record,
        () => _serialize(
          '$key::execution',
          () => _withWorkspaceLease(owner, record, () async {
            final control = await _readExecution(
              record,
              owner,
              enforceHost: false,
              allowRemoteRecoveryBinding: true,
            );
            if (control == null) {
              throw StateError('Authorize execution before handoff');
            }
            if (control['executor'] == 'vps' && control['handoff_id'] == null) {
              throw StateError('Workspace is already assigned elsewhere');
            }
            if (control['executor'] == 'vps' &&
                control['executor_id'] != executorId) {
              throw StateError('Execution was released to another VPS');
            }
            final directory = await _fileStore.capsuleDirForHex(owner);
            final state = await _fileStore.readPluginState(
              directory,
              record.pluginId!,
              'workspace.v1.json',
            );
            final effects = await _fileStore.readPluginState(
              directory,
              record.pluginId!,
              'external_effects.v1.json',
            );
            final released =
                control['executor'] == 'vps'
                    ? control
                    : {
                      ...control,
                      'executor': 'vps',
                      'executor_id': executorId,
                      'handoff_id': sha256.convert(_handoffNonce()).toString(),
                      'revision': (control['revision'] as int) + 1,
                    };
            final checkpoint = {
              'owner': owner,
              'plugin_id': record.pluginId,
              'package_digest': control['package_digest'],
              'execution': released,
              'workspace': state,
              'effects': effects,
            };
            _validateCheckpoint(checkpoint, owner, record.pluginId!);
            final binding = await registry.resolveRuntimeBinding(
              record.pluginId!,
            );
            if (!_isStillOwnedBy(owner) ||
                binding.packageId != record.id ||
                !binding.capabilities.contains('workspace.schedule') ||
                (control['executor'] != 'vps' &&
                    binding.packageDigestHex != control['package_digest'])) {
              throw StateError('Handoff package or Capsule changed');
            }
            await _fileStore.writePluginState(
              directory,
              record.pluginId!,
              _executionFile,
              jsonEncode(released),
            );
            stopWorkspaceScheduling(pluginId: record.pluginId);
            return checkpoint;
          }, authorityOnly: true),
        ),
      ),
    );
  }

  /// Adopt opaque state and the canonical effect journal without renewing
  /// authority. An exact replay acknowledges, never restores old files.
  Future<void> adoptWorkspaceFromLocal({
    required WasmPluginRecord record,
    required Map<String, dynamic> checkpoint,
  }) async {
    final owner = activeCapsuleRootHex()?.trim().toLowerCase();
    if (executionHost != 'vps' || owner == null) {
      throw StateError('A VPS executor is required for adoption');
    }
    _validateCheckpoint(checkpoint, owner, record.pluginId!);
    // Keep one immutable input across asynchronous registry/storage checks.
    checkpoint = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(checkpoint)) as Map,
    );
    // The immutable custody checkpoint never changes. Entry revocation can
    // travel with its source grant, but cannot restore state or renew authority.
    final digest = _handoffDigest(checkpoint);
    final incoming = Map<String, dynamic>.from(checkpoint['execution'] as Map);
    if (incoming['executor_id'] != executionIdentity) {
      throw StateError('Checkpoint belongs to another VPS');
    }
    final key = '$owner::${record.pluginId}';
    await _serialize(
      key,
      () => _withWorkspaceLease(
        owner,
        record,
        () => _serialize(
          '$key::execution',
          () => _withWorkspaceLease(owner, record, () async {
            final binding = await registry.resolveRuntimeBinding(
              record.pluginId!,
            );
            if (binding.packageId != record.id ||
                binding.packageDigestHex != checkpoint['package_digest'] ||
                !binding.capabilities.contains('workspace.schedule') ||
                !_isStillOwnedBy(owner)) {
              throw StateError('Handoff package or Capsule changed');
            }
            final previous = await _readExecution(
              record,
              owner,
              enforceHost: false,
            );
            if (previous != null) {
              if (previous['handoff_id'] == incoming['handoff_id'] &&
                  previous['handoff_digest'] == digest &&
                  previous['executor'] == 'vps') {
                if ((!workspaceExecutionEnabled(incoming) &&
                        workspaceExecutionEnabled(previous)) ||
                    (incoming['revoked'] == true &&
                        previous['revoked'] != true)) {
                  final directory = await _fileStore.capsuleDirForHex(owner);
                  await _fileStore.writePluginState(
                    directory,
                    record.pluginId!,
                    _executionFile,
                    jsonEncode({
                      ...previous,
                      workspaceExecutionFlag(previous): false,
                      if (incoming['revoked'] == true) 'revoked': true,
                      'revision': (previous['revision'] as int) + 1,
                    }),
                  );
                }
                return;
              }
              if (previous['executor'] != 'local' ||
                  workspaceExecutionIsActive(previous) ||
                  workspaceExecutionEnabled(previous) ||
                  previous['handoff_id'] == incoming['handoff_id']) {
                throw StateError(
                  'VPS already owns another workspace checkpoint',
                );
              }
            }
            final directory = await _fileStore.capsuleDirForHex(
              owner,
              create: true,
            );
            await _fileStore.restorePluginCheckpoint(
              directory,
              record.pluginId!,
              {
                if (checkpoint['workspace'] != null)
                  'workspace.v1.json': checkpoint['workspace'] as String,
                if (checkpoint['effects'] != null)
                  'external_effects.v1.json': checkpoint['effects'] as String,
                _executionFile: jsonEncode({
                  ...incoming,
                  'package_id': record.id,
                  'handoff_digest': digest,
                }),
              },
              replaceSealed: previous != null,
            );
          }, authorityOnly: true),
        ),
      ),
    );
    await resumeWorkspaceScheduling(record);
  }

  /// Record Stop even if the peer is unavailable or adoption was not delivered.
  /// Acknowledging a later explicit Start may clear it only at the same source
  /// revision; a concurrent Stop wins. This grant never runs locally.
  Future<void> setReleasedWorkspaceEntries(
    WasmPluginRecord record, {
    required String executorId,
    required bool enabled,
    bool revoke = false,
    int? expectedRevision,
  }) async {
    if (enabled && revoke) throw StateError('Start cannot revoke authority');
    final owner = activeCapsuleRootHex();
    if (executionHost != 'local' || owner == null) {
      throw StateError('Local custody is required');
    }
    await _serialize(
      '$owner::${record.pluginId}::execution',
      () => _withWorkspaceLease(owner, record, () async {
        final control = await _readExecution(record, owner, enforceHost: false);
        if (control == null ||
            control['executor'] != 'vps' ||
            control['executor_id'] != executorId ||
            (expectedRevision != null &&
                expectedRevision != control['revision']) ||
            !_isStillOwnedBy(owner)) {
          throw StateError('Remote authority changed');
        }
        final directory = await _fileStore.capsuleDirForHex(owner);
        await _fileStore.writePluginState(
          directory,
          record.pluginId!,
          _executionFile,
          jsonEncode({
            ...control,
            workspaceExecutionFlag(control): enabled,
            if (revoke || enabled) 'revoked': revoke,
            'revision': (control['revision'] as int) + 1,
          }),
        );
      }, authorityOnly: true),
    );
  }

  /// End all remote authority before returning opaque state. Unlike Stop,
  /// this also ends reducing exits and is durable before draining actions.
  Future<Map<String, dynamic>> returnWorkspaceToLocal(
    WasmPluginRecord record,
  ) async {
    final owner = activeCapsuleRootHex()?.trim().toLowerCase();
    if (executionHost != 'vps' || owner == null) {
      throw StateError('A VPS executor is required');
    }
    final key = '$owner::${record.pluginId}';
    await _serialize(
      '$key::execution',
      () => _withWorkspaceLease(owner, record, () async {
        final control = await _readExecution(
          record,
          owner,
          enforceHost: false,
          allowRemoteRecoveryBinding: true,
        );
        if (control == null) throw StateError('No workspace to return');
        if (control['executor'] == 'vps' &&
            control['executor_id'] != executionIdentity) {
          throw StateError('Workspace belongs to another executor');
        }
        if (control['executor'] == 'vps') {
          final directory = await _fileStore.capsuleDirForHex(owner);
          final sealed = {
            ...control,
            'executor': 'local',
            'expires_at_ms': 0,
            workspaceExecutionFlag(control): false,
            'revision': (control['revision'] as int) + 1,
          }..remove('executor_id');
          await _fileStore.writePluginState(
            directory,
            record.pluginId!,
            _executionFile,
            jsonEncode(sealed),
          );
        }
        stopWorkspaceScheduling(pluginId: record.pluginId);
      }, authorityOnly: true),
    );
    return _serialize(
      key,
      () => _withWorkspaceLease(owner, record, () async {
        final control = await _readExecution(
          record,
          owner,
          enforceHost: false,
          allowRemoteRecoveryBinding: true,
        );
        if (control == null ||
            control['executor'] != 'local' ||
            control['expires_at_ms'] != 0 ||
            workspaceExecutionEnabled(control)) {
          throw StateError('Remote authority has not been ended');
        }
        final directory = await _fileStore.capsuleDirForHex(owner);
        return {
          'owner': owner,
          'plugin_id': record.pluginId,
          'package_digest': control['package_digest'],
          'execution': control,
          'workspace': await _fileStore.readPluginState(
            directory,
            record.pluginId!,
            'workspace.v1.json',
          ),
          'effects': await _fileStore.readPluginState(
            directory,
            record.pluginId!,
            'external_effects.v1.json',
          ),
        };
      }),
    );
  }

  /// Transport has authenticated the returning peer; neither package state nor
  /// a network failure may choose the execution host or renew its grant.
  Future<void> restoreWorkspaceFromVps({
    required WasmPluginRecord record,
    required String executorId,
    required Map<String, dynamic> checkpoint,
    String? ownerCapsuleHex,
  }) async {
    final owner =
        ownerCapsuleHex ?? activeCapsuleRootHex()?.trim().toLowerCase();
    if (executionHost != 'local' ||
        owner == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) ||
        checkpoint.length != 6 ||
        checkpoint['owner'] != owner ||
        checkpoint['plugin_id'] != record.pluginId ||
        checkpoint['execution'] is! Map ||
        utf8.encode(jsonEncode(checkpoint)).length > 8 * 1024 * 1024 ||
        [
          'workspace',
          'effects',
        ].any((k) => checkpoint[k] != null && checkpoint[k] is! String) ||
        (checkpoint['workspace'] is String &&
            utf8.encode(checkpoint['workspace']).length > 32 * 1024)) {
      throw StateError('Invalid returned workspace');
    }
    checkpoint = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(checkpoint)) as Map,
    );
    final incoming = Map<String, dynamic>.from(checkpoint['execution'] as Map);
    validateWorkspaceExecutionControl(incoming, owner, record.pluginId!);
    if (incoming['executor'] != 'local' ||
        incoming['expires_at_ms'] != 0 ||
        workspaceExecutionEnabled(incoming) ||
        incoming['package_digest'] != checkpoint['package_digest']) {
      throw StateError('Remote authority remains active');
    }
    await _serialize(
      '$owner::${record.pluginId}',
      () => _withWorkspaceLease(owner, record, () async {
        final control = await _readExecution(
          record,
          owner,
          enforceHost: false,
          allowRemoteRecoveryBinding: true,
        );
        if (control == null ||
            control['executor'] != 'vps' ||
            control['executor_id'] != executorId ||
            control['handoff_id'] == null ||
            control['handoff_id'] != incoming['handoff_id']) {
          throw StateError('Return does not match the assigned workspace');
        }
        final directory = await _fileStore.capsuleDirForHex(owner);
        if (control['package_digest'] != checkpoint['package_digest'] &&
            incoming['handoff_digest'] !=
                _handoffDigest({
                  'owner': owner,
                  'plugin_id': record.pluginId,
                  'package_digest': control['package_digest'],
                  'execution': control,
                  'workspace': await _fileStore.readPluginState(
                    directory,
                    record.pluginId!,
                    'workspace.v1.json',
                  ),
                  'effects': await _fileStore.readPluginState(
                    directory,
                    record.pluginId!,
                    'external_effects.v1.json',
                  ),
                })) {
          throw StateError('Return does not prove the original handoff');
        }
        final binding = await registry.resolveRuntimeBinding(record.pluginId!);
        if (binding.packageId != record.id ||
            binding.packageDigestHex == null ||
            !binding.capabilities.contains('workspace.schedule')) {
          throw StateError('Installed workspace changed during return');
        }
        final restored =
            {
                ...incoming,
                'package_id': record.id,
                'package_digest': binding.packageDigestHex,
              }
              ..remove('handoff_id')
              ..remove('handoff_digest');
        if (ownerCapsuleHex == null && !_isStillOwnedBy(owner)) {
          throw StateError('Active Capsule changed during return');
        }
        for (final pair
            in {
              'workspace': 'workspace.v1.json',
              'effects': 'external_effects.v1.json',
            }.entries) {
          if (checkpoint[pair.key] == null &&
              await _fileStore.readPluginState(
                    directory,
                    record.pluginId!,
                    pair.value,
                  ) !=
                  null) {
            throw StateError(
              'Returned checkpoint lost retained state or effect evidence',
            );
          }
        }
        await _fileStore.restorePluginCheckpoint(directory, record.pluginId!, {
          if (checkpoint['workspace'] != null)
            'workspace.v1.json': checkpoint['workspace'] as String,
          if (checkpoint['effects'] != null)
            'external_effects.v1.json': checkpoint['effects'] as String,
          _executionFile: jsonEncode(restored),
        }, replaceSealed: true);
      }),
    );
  }

  static String _handoffDigest(Map<String, dynamic> checkpoint) {
    final immutable = {
      ...checkpoint,
      'execution':
          {...checkpoint['execution'] as Map}
            ..remove(workspaceExecutionFlag(checkpoint['execution'] as Map))
            ..remove('revoked')
            ..remove('revision'),
    };
    return sha256.convert(utf8.encode(_canonical(immutable))).toString();
  }

  static void _validateCheckpoint(
    Map<String, dynamic> checkpoint,
    String owner,
    String pluginId,
  ) {
    if (checkpoint.length != 6 ||
        !checkpoint.keys.toSet().containsAll(const {
          'owner',
          'plugin_id',
          'package_digest',
          'execution',
          'workspace',
          'effects',
        }) ||
        checkpoint['owner'] != owner ||
        checkpoint['plugin_id'] != pluginId ||
        checkpoint['package_digest'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checkpoint['package_digest']) ||
        checkpoint['execution'] is! Map ||
        utf8.encode(jsonEncode(checkpoint)).length > 8 * 1024 * 1024 ||
        [
          'workspace',
          'effects',
        ].any((key) => checkpoint[key] != null && checkpoint[key] is! String)) {
      throw StateError('Invalid workspace checkpoint');
    }
    final control = checkpoint['execution'];
    validateWorkspaceExecutionControl(control, owner, pluginId);
    if (control['executor'] != 'vps' ||
        control['handoff_id'] == null ||
        control['handoff_digest'] != null ||
        control['package_digest'] != checkpoint['package_digest'] ||
        utf8.encode(jsonEncode(control)).length > 8192 ||
        (checkpoint['workspace'] != null &&
            utf8.encode(checkpoint['workspace']).length > 32 * 1024)) {
      throw StateError(
        'Checkpoint does not carry released execution authority',
      );
    }
  }

  Map<String, dynamic> _executionPresentation(
    Map<String, dynamic> control,
    Map<String, dynamic>? observation,
  ) => {
    'mode': executionHost,
    'enabled':
        workspaceExecutionEnabled(control) &&
        workspaceExecutionIsActive(control),
    'active': workspaceExecutionIsActive(control),
    'running':
        workspaceExecutionEnabled(control) &&
        workspaceExecutionIsActive(control) &&
        control['scope']['action'] != null,
    'access': control['version'] == 2 ? control['scope']['access'] : null,
    'scope': control['version'] == 2 ? control['scope'] : null,
    'credentials': control['credentials'] ?? const {},
    'revoked': control['revoked'] == true,
    'revision': control['revision'],
    'expires_at_ms': control['expires_at_ms'],
    'last_checked_at_ms': observation?['last_checked_at_ms'],
    'last_error': observation?['last_error'],
  };

  void _armScheduledExecution(
    WasmPluginRecord record,
    String owner,
    Map<String, dynamic> control,
  ) {
    if (_schedulingClosed ||
        !scheduleTimers ||
        (control['executor'] ?? 'local') != executionHost) {
      return;
    }
    final key = '$owner::${record.pluginId}';
    final binding =
        '${record.id}::${control['package_digest']}::${control['revision']}';
    if (control['version'] != 2 ||
        control['scope']['action'] == null ||
        !workspaceExecutionIsActive(control) ||
        !workspaceExecutionEnabled(control)) {
      _clearSchedule(key);
      return;
    }
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
            if (current == null || !workspaceExecutionIsActive(current)) {
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

  void stopWorkspaceScheduling({String? pluginId, bool permanently = false}) {
    // Process shutdown must also seal rearming by actions already in flight.
    // Normal Stop/switch calls remain reversible through the existing grant.
    if (permanently) _schedulingClosed = true;
    for (final key in _scheduledHosts.keys.toList()) {
      if (pluginId == null
          ? identical(_scheduledHosts[key], this)
          : key.endsWith('::$pluginId')) {
        _clearSchedule(key);
      }
    }
  }

  Future<T> _withWorkspaceLease<T>(
    String owner,
    WasmPluginRecord record,
    Future<T> Function() work, {
    bool authorityOnly = false,
  }) async {
    final directory = await _fileStore.capsuleDirForHex(owner, create: true);
    // Use the storage owner's validation, not an unchecked package path.
    await _fileStore.pluginStateDirectory(directory, record.pluginId!);
    final lock = await File(
      '${directory.path}/workspace-${authorityOnly ? 'authority' : 'state'}-${record.pluginId}.lock',
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      return await work();
    } finally {
      await lock.close();
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
      if (utf8.encode(raw).length > 8192) throw const FormatException();
      final values = jsonDecode(raw);
      if (values is! Map ||
          values.isEmpty ||
          values.length > 8 ||
          values.entries.any(
            (e) =>
                !PluginCapabilityDispatcher.safeId(e.key) ||
                e.value is! String ||
                (e.value as String).isEmpty ||
                (e.value as String).length > 4096,
          )) {
        throw const FormatException();
      }
      return Map<String, String>.from(values);
    } catch (_) {
      throw StateError(
        'Saved credentials are unreadable; configure access again',
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
