import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import '../models/wasm_plugin_models.dart';
import 'ai_doctor_credential_store.dart';
import 'app_runtime_service.dart';
import 'capsule_ai_runtime_service.dart';
import 'capsule_file_store.dart';
import 'capsule_scoped_secret_vault.dart';
import 'plugin_workspace_runtime.dart';
import 'plugin_workspace_remote_service.dart';
import 'wasm_plugin_package_preflight_service.dart';
import 'ui_event_log_service.dart';
import 'wasm_plugin_registry_service.dart';
import 'wasm_plugin_source_catalog_service.dart';

class PluginRuntimeModule extends PluginWorkspaceRuntime {
  final WasmPluginSourceCatalogService sourceCatalog;
  final UiEventLogService uiLog;
  final CapsuleFileStore _fileStore;
  final CapsuleScopedSecretVault _secretVault;
  final PluginWorkspaceRemoteService? _providedRemote;
  late final PluginWorkspaceRemoteService _remote =
      _providedRemote ??
      PluginWorkspaceRemoteService(
        files: _fileStore,
        vault: _secretVault,
        registry: registry,
      );

  PluginRuntimeModule({
    required super.registry,
    required this.sourceCatalog,
    required super.pluginHostApi,
    required this.uiLog,
    required super.fileStore,
    required CapsuleScopedSecretVault secretVault,
    required super.readActiveCapsuleRootHex,
    super.capabilities,
    super.infer,
    PluginWorkspaceRemoteService? workspaceRemote,
  }) : _fileStore = fileStore,
       _providedRemote = workspaceRemote,
       _secretVault = secretVault,
       super(resolveCredentialReferences: secretVault.resolveReferences);

  Future<void> removePlugin(
    WasmPluginRecord record, {
    bool deleteSavedData = false,
  }) async {
    return _removePlugin(record, deleteSavedData: deleteSavedData);
  }

  Future<void> _removePlugin(
    WasmPluginRecord record, {
    required bool deleteSavedData,
  }) async {
    final current = (await registry.loadPlugins()).where(
      (r) => r.id == record.id,
    );
    if (current.isEmpty) return;
    if (!current.single.removalPending) {
      await _returnAssignmentsForRemoval(record.pluginId);
    }
    // Stop admission first, then let in-flight continuations fail before
    // deleting state; otherwise a late write can recreate an uninstalled plugin.
    await registry.removePlugin(
      record.id,
      cleanup: () async {
        final pluginId = record.pluginId?.trim();
        if (pluginId != null && pluginId.isNotEmpty) {
          stopWorkspaceScheduling(pluginId: pluginId);
          await drainWorkspaceActions(pluginId);
          await _fileStore.deletePluginStateFromAllCapsules(
            pluginId,
            beforeDelete:
                (owners) =>
                    _secretVault.deletePlugin(pluginId, capsuleHexes: owners),
            preserveFileNames: {
              'external_effects.v1.json',
              'workspace-execution.v1.json',
              if (record.contractKind == pluginWorkspaceContractKind &&
                  !deleteSavedData)
                'workspace.v1.json',
            },
            preserveFilePrefixes:
                record.contractKind == pluginWorkspaceContractKind &&
                        !deleteSavedData
                    ? const {'data-'}
                    : const {},
          );
        }
      },
    );
  }

  Future<WasmPluginRecord> installPluginFromFile(File file) async {
    final inspected = await const WasmPluginPackagePreflightService().inspect(
      file,
    );
    if (inspected.pluginId == capsuleChatPluginId) {
      throw const FormatException(
        'Chat is built into Capsule. Open it from the top bar.',
      );
    }
    return _finishInstallation(
      registry.installPluginFromFile(
        file,
        validateRecord: (record) {
          if (record.pluginId != inspected.pluginId) {
            throw StateError('Installation input changed');
          }
        },
      ),
    );
  }

  Future<WasmPluginRecord> installPluginFromSource(
    WasmPluginSourceCatalogEntry entry,
  ) async {
    if (canonicalPluginId(entry.pluginId) == capsuleChatPluginId) {
      throw const FormatException(
        'Chat is built into Capsule. Open it from the top bar.',
      );
    }
    return _finishInstallation(sourceCatalog.installFromSourceEntry(entry));
  }

  Future<WasmPluginRecord> _finishInstallation(
    Future<WasmPluginRecord> installation,
  ) async {
    final record = await installation;
    if (record.contractKind == pluginWorkspaceContractKind &&
        record.pluginId != null) {
      stopWorkspaceScheduling(pluginId: record.pluginId);
    }
    return record;
  }

  Future<void> _returnAssignmentsForRemoval(String? pluginId) async {
    final records = (await registry.loadPlugins()).where(
      (r) =>
          r.pluginId == pluginId &&
          r.contractKind == pluginWorkspaceContractKind,
    );
    if (records.isEmpty) return;
    final record = records.single;
    final root = await _fileStore.capsulesRoot();
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      final owner = entity.path.split(Platform.pathSeparator).last;
      if (entity is! Directory || !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) {
        continue;
      }
      final grant = await super.readWorkspaceExecution(
        record,
        enforceHost: false,
        ownerCapsuleHex: owner,
        allowRemoteRecoveryBinding: true,
      );
      if (grant?['executor'] == 'vps') {
        final c = await _remote.connection(owner, record.pluginId!);
        if (c == null || c['executor_id'] != grant!['executor_id']) {
          throw StateError(
            'Reconnect the assigned VPS before removing this package',
          );
        }
        final result = await _remote.request(c, 'return', {
          'handoff_id': grant['handoff_id'],
        });
        await restoreWorkspaceFromVps(
          record: record,
          executorId: c['executor_id'] as String,
          checkpoint: Map<String, dynamic>.from(result['checkpoint'] as Map),
          ownerCapsuleHex: owner,
        );
        await _remote.uninstall(c);
      }
    }
    stopWorkspaceScheduling(pluginId: record.pluginId);
  }

  Future<void> connectWorkspaceVps({
    required WasmPluginRecord record,
    required String host,
    required int port,
    required String password,
    required Future<bool> Function(String) trustPeer,
    bool reinstall = false,
  }) async {
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
      allowRemoteRecoveryBinding: true,
    );
    final binding = await registry.resolveRuntimeBinding(record.pluginId!);
    if (binding.packageId != record.id) throw StateError('Package changed');
    await _remote.connect(
      owner: owner,
      record: record,
      host: host,
      port: port,
      password: password,
      trustPeer: trustPeer,
      reinstall: reinstall,
      assignedExecutorId:
          grant?['executor'] == 'vps' ? grant!['executor_id'] as String : null,
      stillOwned: () => activeCapsuleRootHex() == owner,
      saveAuthorized:
          (save) => withWorkspaceAuthority(owner, record, () async {
            final installed = await registry.resolveRuntimeBinding(
              record.pluginId!,
            );
            final current = await super.readWorkspaceExecution(
              record,
              ownerCapsuleHex: owner,
              enforceHost: false,
              allowRemoteRecoveryBinding: true,
            );
            if (activeCapsuleRootHex() != owner ||
                installed.packageId != binding.packageId ||
                installed.packageDigestHex != binding.packageDigestHex ||
                current?['revision'] != grant?['revision']) {
              throw StateError('Workspace changed while connecting to the VPS');
            }
            await save();
          }),
    );
  }

  Future<void> useWorkspaceOnline(WasmPluginRecord record) async {
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
      allowRemoteRecoveryBinding: true,
    );
    if (grant?['executor'] == 'vps') {
      final c = await _remote.connection(owner, record.pluginId!);
      if (c == null || c['executor_id'] != grant!['executor_id']) {
        throw StateError('Assigned VPS connection is unavailable');
      }
      final result = await _remote.request(c, 'return', {
        'handoff_id': grant['handoff_id'],
      });
      await restoreWorkspaceFromVps(
        record: record,
        executorId: c['executor_id'] as String,
        checkpoint: Map<String, dynamic>.from(result['checkpoint'] as Map),
      );
    }
    await withWorkspaceAuthority(owner, record, () async {
      if (activeCapsuleRootHex() != owner) throw StateError('Capsule changed');
      await _remote.selectOnline(owner, record.pluginId!);
    });
  }

  Future<List<Map<String, String>>> listWorkspaceSecretReferences(
    WasmPluginRecord record,
  ) => _workspaceSecretReferences(
    record,
    (owner, _) =>
        _secretVault.listReferences(owner, pluginId: record.pluginId!),
  );

  Future<List<Map<String, String>>> saveWorkspaceSecretReferences(
    WasmPluginRecord record,
    List<Map<String, String>> secrets,
  ) => _workspaceSecretReferences(
    record,
    (owner, authorize) => _secretVault.addReferences(
      capsuleHex: owner,
      pluginId: record.pluginId!,
      secrets: secrets,
      authorize: authorize,
    ),
  );

  Future<List<Map<String, String>>> _workspaceSecretReferences(
    WasmPluginRecord record,
    Future<List<Map<String, String>>> Function(
      String owner,
      Future<void> Function() authorize,
    )
    operation,
  ) async {
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final binding = await registry.resolveRuntimeBinding(record.pluginId!);
    if (binding.packageId != record.id) throw StateError('Package changed');
    Future<void> authorize() async {
      final current = await registry.resolveRuntimeBinding(record.pluginId!);
      if (activeCapsuleRootHex() != owner ||
          current.packageId != binding.packageId ||
          current.packageDigestHex != binding.packageDigestHex) {
        throw StateError('Capsule or package changed');
      }
    }

    final references = await operation(owner, authorize);
    await authorize();
    return references;
  }

  // Package installation does not change the existing VPS grant.
  bool _isPreviousPackageAssignment(
    WasmPluginRecord record,
    Map<String, dynamic>? grant,
  ) => grant?['executor'] == 'vps' && grant?['package_id'] != record.id;

  static const _updatedPackageStart =
      'Confirm a new Start on the assigned VPS to use the updated package';

  @override
  Future<Map<String, dynamic>> runWorkspaceAction({
    required WasmPluginRecord record,
    required String action,
    Map<String, dynamic> settings = const {},
    bool readOnly = false,
    Map<String, dynamic>? choiceAccess,
    bool choiceAccessApproved = false,
  }) async {
    if (choiceAccess != null) {
      return super.runWorkspaceAction(
        record: record,
        action: action,
        choiceAccess: choiceAccess,
        choiceAccessApproved: choiceAccessApproved,
      );
    }
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
      allowRemoteRecoveryBinding: true,
    );
    final c = await _remote.connection(owner, record.pluginId!);
    if (grant?['executor'] == 'vps') {
      final previousPackage = _isPreviousPackageAssignment(record, grant);
      final connection = c?['executor_id'] == grant!['executor_id'] ? c : null;
      Map<String, dynamic>? result;
      String? unavailable;
      if (previousPackage) {
        if (action != 'open') throw StateError(_updatedPackageStart);
        unavailable = 'package_updated';
      } else {
        if (connection == null) {
          throw StateError('Assigned VPS is unavailable; no local fallback');
        }
        try {
          if (action == 'open' &&
              (connection['package_id'] == null ||
                  connection['package_digest'] != grant['package_digest'])) {
            result = await _recoverWorkspaceBinding(record, grant, connection);
          } else {
            result = await _runAssignedWorkspace(
              record,
              grant,
              connection,
              action,
              settings,
            );
            final controls = result['runner']?['execution_controls'];
            if (action == 'open' &&
                result['runner']?['state'] == 'replaced' &&
                grant['handoff_id'] is String &&
                controls is int &&
                controls >= 5) {
              result = await _recoverWorkspaceBinding(
                record,
                grant,
                connection,
              );
            }
          }
          final state = result['runner']?['state'];
          if (state == 'replaced' || state == 'not_started') {
            if (action != 'open') {
              throw StateError(
                'The VPS no longer runs this assignment; use Start',
              );
            }
            unavailable = state as String;
          } else if (result['view'] is! Map) {
            throw StateError(
              'VPS observation unavailable; its lifecycle is not verified',
            );
          }
        } catch (_) {
          if (action != 'open') rethrow;
          unavailable = 'unavailable';
        }
      }
      final Map<String, dynamic> view;
      if (unavailable != null) {
        // This is this Capsule's own retained view, not the other executor's
        // account state. The common read-only path cannot dispatch or schedule.
        view = await super.runWorkspaceAction(
          record: record,
          action: 'open',
          readOnly: true,
        );
      } else {
        view = Map<String, dynamic>.from(result!['view'] as Map);
      }
      if (activeCapsuleRootHex() != owner ||
          (await registry.resolveRuntimeBinding(record.pluginId!)).packageId !=
              record.id) {
        throw StateError('Capsule or package changed');
      }
      return {
        ...view,
        if (previousPackage) ...{
          'actions': [
            if (connection?['selected'] == true)
              for (final action in view['actions'] as List)
                if (action['host'] == 'workspace.start') action,
          ],
          'execution': {
            'active': false,
            'enabled': false,
            'running': false,
            'revision': grant['revision'],
          },
        },
        'host_connection': {
          'target': 'vps',
          'host': connection?['host'],
          'port': connection?['port'],
          'saved': connection != null,
          'health': unavailable ?? result!['runner']['state'],
          'observation_error': result?['observation_error'],
        },
      };
    }

    final view = await super.runWorkspaceAction(
      record: record,
      action: action,
      settings: settings,
      readOnly: readOnly,
    );
    return {
      ...view,
      'host_connection': {
        'target': 'local',
        'selected': c?['selected'] == true,
        'host': c?['host'],
        'port': c?['port'],
        'saved': c != null,
        'health':
            c?['package_id'] == null ? 'setup_unconfirmed' : 'not_started',
      },
    };
  }

  Future<Map<String, dynamic>> _runAssignedWorkspace(
    WasmPluginRecord record,
    Map<String, dynamic> grant,
    Map<String, dynamic> connection,
    String action,
    Map<String, dynamic> settings,
  ) async {
    if (action != 'open' ||
        grant['revoked'] == true ||
        grant['expires_at_ms'] == null) {
      final status = await _requireExecutionControls(connection);
      if (status['runner']?['state'] == 'not_started') return status;
    }
    if (activeCapsuleRootHex() != grant['owner']) {
      throw StateError('Capsule changed');
    }
    // A replay also carries any revocation recorded while the VPS was unreachable.
    final adoption = await _remote.request(connection, 'adopt', {
      'checkpoint': await releaseWorkspaceToVps(
        record,
        executorId: connection['executor_id'] as String,
      ),
    });
    if (const {
      'replaced',
      'not_started',
    }.contains(adoption['runner']?['state'])) {
      return adoption;
    }
    return _remote.request(
      connection,
      action == 'open' ? 'status' : 'action',
      action == 'open' ? const {} : {'action': action, 'settings': settings},
    );
  }

  Future<Map<String, dynamic>> _recoverWorkspaceBinding(
    WasmPluginRecord record,
    Map<String, dynamic> grant,
    Map<String, dynamic> connection,
  ) async {
    final handoff = grant['handoff_id'];
    if (handoff is! String) {
      throw StateError('The VPS assignment is unconfirmed');
    }
    final digest = grant['package_digest'] as String;
    final observed = await _remote.request(
      {...connection, 'package_id': record.id, 'package_digest': digest},
      'status',
      {'handoff_id': handoff},
    );
    if (observed['runner']?['state'] != 'running') return observed;
    final confirmed = await confirmWorkspaceHandoff(
      record,
      grant,
      () => _remote.rememberBinding(
        connection,
        Map<String, dynamic>.from(observed['binding'] as Map),
        digest: digest,
      ),
    );
    return _runAssignedWorkspace(record, grant, confirmed, 'open', const {});
  }

  @override
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
    String? expectedHandoffId,
    Future<void> Function()? authorizeRelease,
  }) async {
    if (enabled && revoke) throw StateError('Start cannot revoke authority');
    final owner = activeCapsuleRootHex();
    if (owner == null) throw StateError('Open a Capsule first');
    final grant = await super.readWorkspaceExecution(
      record,
      enforceHost: false,
      allowRemoteRecoveryBinding: true,
    );
    var c = await _remote.connection(owner, record.pluginId!);
    if (activeCapsuleRootHex() != owner) throw StateError('Capsule changed');
    final startsOnVps =
        approvedScope?['start_action'] is String && c?['selected'] == true;
    final previousPackage = _isPreviousPackageAssignment(record, grant);
    if (enabled && previousPackage) {
      if (!startsOnVps ||
          c?['executor_id'] != grant?['executor_id'] ||
          credentialBindings == null ||
          expectedRevision != grant?['revision']) {
        throw StateError(_updatedPackageStart);
      }
      // Check the assigned target before changing the retained grant.
      await _requireExecutionControls({
        ...c!,
        'package_id': c['package_id'] ?? grant!['package_id'],
        'package_digest': c['package_digest'] ?? grant!['package_digest'],
      }, requireReplacement: true);
      if (activeCapsuleRootHex() != owner) throw StateError('Capsule changed');
    }
    if (enabled && startsOnVps) {
      if (credentialBindings == null &&
          expectedRevision != null &&
          expectedRevision != grant?['revision']) {
        throw StateError(
          'Start authority changed; reopen the current permissions',
        );
      }
      final selected = c!;
      Future<void> confirmDestination() async {
        if (!mapEquals(
          selected,
          await _remote.connection(owner, record.pluginId!),
        )) {
          throw StateError('VPS selection changed during Start');
        }
      }

      // Start belongs to the current owner and selection, not the device that
      // happened to install the previous server process. No old runner action.
      await super.setWorkspaceExecution(
        record: record,
        enabled: true,
        expiresAtMs: expiresAtMs,
        expectedRevision: grant?['revision'] as int?,
        approvedScope: approvedScope,
        credentialBindings:
            credentialBindings ??
            (grant?['credentials'] as Map?)?.map(
              (k, v) =>
                  MapEntry(k as String, Map<String, String>.from(v as Map)),
            ),
        settings: settings,
        releaseToExecutorId: selected['executor_id'] as String,
        authorizeRelease: confirmDestination,
      );
      final checkpoint = await releaseWorkspaceToVps(
        record,
        executorId: selected['executor_id'] as String,
      );
      final acknowledged = await _remote.ensurePackage(
        selected,
        record,
        credentialBindings: credentialBindings,
        checkpoint: checkpoint,
        authorize: () async {
          await confirmDestination();
          final current = await super.readWorkspaceExecution(
            record,
            enforceHost: false,
          );
          final installed = await registry.resolveRuntimeBinding(
            record.pluginId!,
          );
          if (activeCapsuleRootHex() != owner ||
              current?['revision'] != checkpoint['execution']['revision'] ||
              current?['enabled'] != true ||
              current?['revoked'] == true ||
              installed.packageId != record.id ||
              installed.packageDigestHex != checkpoint['package_digest']) {
            throw StateError(
              'Start authority changed before server replacement',
            );
          }
        },
      );
      c = await confirmWorkspaceHandoff(
        record,
        Map<String, dynamic>.from(checkpoint['execution'] as Map),
        () => _remote.rememberBinding(
          selected,
          acknowledged,
          digest: checkpoint['package_digest'] as String,
        ),
      );
      await _requireExecutionControls(c, requireReplacement: true);
      return runWorkspaceAction(record: record, action: 'open');
    }
    if (grant?['executor'] == 'vps') {
      if (credentialBindings != null) {
        throw StateError(
          'Start a new assignment to use different connections on the VPS, or return execution to this Capsule first',
        );
      }
      final stoppedRevision =
          enabled
              ? null
              : await setReleasedWorkspaceEntries(
                record,
                executorId: grant!['executor_id'] as String,
                enabled: false,
                revoke: revoke,
                expectedRevision: grant['revision'] as int,
              );
      var detached = false;
      try {
        if (c == null || c['executor_id'] != grant!['executor_id']) {
          throw StateError(
            'Reconnect the assigned VPS; remote stop is unconfirmed',
          );
        }
        final handoff =
            !enabled && revoke ? grant['handoff_id'] as String? : null;
        if (handoff != null &&
            (c['package_id'] == null ||
                c['package_digest'] != grant['package_digest'])) {
          c = {
            ...c,
            'package_id': grant['package_id'],
            'package_digest': grant['package_digest'],
          };
        }
        String? scopedHandoff;
        if (enabled ||
            revoke ||
            grant['revoked'] == true ||
            grant['expires_at_ms'] == null) {
          final status = await _requireExecutionControls(c);
          final controls = status['runner']['execution_controls'] as int;
          if (controls >= workspaceHandoffRevocationControls) {
            scopedHandoff = handoff;
          }
        }
        if (activeCapsuleRootHex() != owner ||
            (await registry.resolveRuntimeBinding(
                  record.pluginId!,
                )).packageId !=
                record.id) {
          throw StateError('Capsule or package changed during authorization');
        }
        final response = await _remote.request(c, 'execution', {
          'enabled': enabled,
          'settings': settings,
          'scope': approvedScope,
          if (enabled || revoke) ...{
            'expires_at_ms': expiresAtMs,
            'expected_revision': expectedRevision,
            'revoke': revoke,
          },
          if (scopedHandoff != null) 'handoff_id': scopedHandoff,
        });
        if (scopedHandoff != null &&
            response['runner']?['state'] == 'not_started') {
          final controls = response['runner']?['execution_controls'];
          if (response['handoff_id'] != scopedHandoff ||
              controls is! int ||
              controls < workspaceHandoffRevocationControls) {
            throw StateError(
              'The VPS did not acknowledge this revoked handoff',
            );
          }
          await setReleasedWorkspaceEntries(
            record,
            executorId: grant['executor_id'] as String,
            enabled: false,
            revoke: true,
            expectedRevision: stoppedRevision,
            absentHandoffId: scopedHandoff,
          );
          detached = true;
        }
      } catch (_) {
        if (!enabled && revoke) {
          throw StateError(
            'Permissions revoked on this device. Remote stop is unconfirmed; '
            'restore VPS access or update its runtime before retrying. '
            'Already accepted external actions are not undone.',
          );
        }
        rethrow;
      }
      if (enabled) {
        await setReleasedWorkspaceEntries(
          record,
          executorId: c['executor_id'] as String,
          enabled: true,
          expectedRevision: grant['revision'] as int,
        );
      }
      return runWorkspaceAction(
        record: record,
        action: 'open',
        readOnly: detached,
      );
    }
    return super.setWorkspaceExecution(
      record: record,
      enabled: enabled,
      expiresAtMs: expiresAtMs,
      expectedRevision: expectedRevision,
      revoke: revoke,
      approvedScope: approvedScope,
      credentialBindings: credentialBindings,
      settings: settings,
      releaseToExecutorId: releaseToExecutorId,
      expectedHandoffId: expectedHandoffId,
      authorizeRelease: authorizeRelease,
    );
  }

  Future<Map<String, dynamic>> _requireExecutionControls(
    Map<String, dynamic> connection, {
    bool requireReplacement = false,
  }) async {
    final status = await _remote.request(connection, 'status');
    final controls = status['runner']?['execution_controls'];
    if (controls is! int || controls < (requireReplacement ? 4 : 3)) {
      throw StateError(
        'Update the VPS runtime before changing permission terms',
      );
    }
    return status;
  }
}

class PluginRuntimeModuleService {
  final AppRuntimeService runtime;
  final CapsuleFileStore fileStore;

  const PluginRuntimeModuleService({
    required this.runtime,
    this.fileStore = const CapsuleFileStore(),
  });

  PluginRuntimeModule build() {
    final activeCapsuleRootHex = runtime.activeCapsuleRootHex;
    final secretVault = CapsuleScopedSecretVault();
    final aiRuntime = CapsuleAiRuntimeService(
      credentialStore: AiDoctorCredentialStore.shared,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
    final uiLog = const UiEventLogService();
    final pluginHostApi = runtime.buildPluginHostApiService();
    return PluginRuntimeModule(
      infer: (request, authorize) async {
        final maxOutput = request['max_output_bytes'] ?? 16 * 1024;
        if (maxOutput is! int || maxOutput < 1 || maxOutput > 16 * 1024) {
          throw const FormatException('Invalid inference output bound');
        }
        final result = await aiRuntime.inferAuthorized(
          CapsuleInferenceRequestV1.create(
            capsuleRootHex: activeCapsuleRootHex()!,
            capabilityId: 'plugin:${request['plugin_id']}',
            disclosureSchemaVersion: 1,
            disclosedSectionIds: const ['package_input'],
            proposalSchemaId: 'plugin.inference.text',
            proposalSchemaVersion: 1,
            cancellationScope: 'workspace:${request['plugin_id']}',
            instructions: request['instructions'] as String,
            input: request['input'] as Object,
            maxInputBytes: 24 * 1024,
            maxOutputBytes: maxOutput,
          ),
          authorize: authorize,
        );
        return {
          'outcome': 'response',
          'text': result.proposalText,
          'provider_id': result.providerId,
          'provider_label': result.providerLabel,
          'model': result.model,
        };
      },
      registry: const WasmPluginRegistryService(),
      sourceCatalog: const WasmPluginSourceCatalogService(),
      pluginHostApi: pluginHostApi,
      uiLog: uiLog,
      secretVault: secretVault,
      fileStore: fileStore,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
  }
}
