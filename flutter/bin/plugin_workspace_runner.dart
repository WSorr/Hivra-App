import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hivra_app/ffi/hivra_bindings.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_workspace_runtime.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_runtime_service.dart';

// This is host composition, not a second strategy or trading lifecycle.
// SSH transports requests to the private socket; no public listener is opened.
Future<void> main(List<String> args) async {
  if (args.length != 2 || !['serve', 'request'].contains(args[0])) {
    stderr.writeln('Usage: hivra-workspace-runner <serve|request> <data-root>');
    exitCode = 64;
    return;
  }
  var phase = 'configuration';
  try {
    final root = Directory(args[1]);
    if (!root.isAbsolute) throw const FormatException('Absolute root required');
    if (args[0] == 'request') {
      final input = await _readMessage(stdin);
      final result = await WorkspaceRunner.request(root, input);
      stdout.writeln(jsonEncode(result));
      return;
    }
    final config = await _readPrivateJson(File('${root.path}/runner.json'));
    final owner = config['owner'];
    final pluginId = config['plugin_id'];
    if (config.length != 5 ||
        owner is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) ||
        pluginId is! String ||
        !RegExp(r'^[a-z][a-z0-9._-]{0,127}$').hasMatch(pluginId) ||
        config['package_id'] is! String ||
        config['package_digest'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(config['package_digest']) ||
        config['executor_id'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(config['executor_id'])) {
      throw const FormatException('Invalid runner binding');
    }
    final dirs = UserVisibleDataDirectoryService(
      runtimeRootOverride: root.path,
    );
    final registry = WasmPluginRegistryService(dataDirs: dirs);
    phase = 'native_runtime';
    final wasm = WasmPluginRuntimeService(
      invokeJson: HivraBindings.invokeInstalledWasmJson,
    );
    final runtime = PluginWorkspaceRuntime(
      registry: registry,
      pluginHostApi: PluginHostApiService(
        handlers: [],
        resolveRuntimeBinding: registry.resolveRuntimeBinding,
        resolveRuntimeInvoke:
            (request, binding) =>
                wasm.invoke(request: request, binding: binding),
      ),
      fileStore: CapsuleFileStore(dirs: dirs),
      readActiveCapsuleRootHex: () => owner,
      executionHost: 'vps',
      executionIdentity: config['executor_id'] as String,
      readCredentials: ({required owner, required pluginId}) async {
        final stored = await _readPrivateJson(
          File('${root.path}/credentials.json'),
        );
        if (stored['owner'] != owner ||
            stored['plugin_id'] != pluginId ||
            stored['credentials'] is! Map ||
            stored.length != 3) {
          throw StateError('Credentials do not belong to this workspace');
        }
        return jsonEncode(stored['credentials']);
      },
      // Credential provisioning is a separate host operation. A package
      // action cannot replace the server's host-only credential binding.
      writeCredentials:
          ({required owner, required pluginId, required value}) async =>
              throw StateError('Connect the account through Capsule'),
    );
    final runner = WorkspaceRunner(
      root: root,
      runtime: runtime,
      registry: registry,
      binding: config,
    );
    final shutdown = Completer<void>();
    final signals = [
      ProcessSignal.sigterm.watch().listen((_) {
        if (!shutdown.isCompleted) shutdown.complete();
      }),
      ProcessSignal.sigint.watch().listen((_) {
        if (!shutdown.isCompleted) shutdown.complete();
      }),
    ];
    try {
      try {
        await runner.start();
      } catch (_) {
        phase = runner.startupPhase;
        rethrow;
      }
      stdout.writeln('Workspace runner ready');
      await shutdown.future;
    } finally {
      await runner.close();
      for (final signal in signals) {
        await signal.cancel();
      }
    }
  } catch (_) {
    // Provider messages, command payloads and credentials must not reach logs.
    stderr.writeln(
      'Workspace runner unavailable ($phase); no automatic replay',
    );
    exitCode = 1;
  }
}

class WorkspaceRunner {
  static const _socketName = 'runner.sock';
  static final Set<String> _ownedRoots = {};
  final Directory root;
  final PluginWorkspaceRuntime runtime;
  final WasmPluginRegistryService registry;
  final Map<String, dynamic> binding;
  final int _startedAt = DateTime.now().millisecondsSinceEpoch;
  RandomAccessFile? _lease;
  ServerSocket? _server;
  final Set<Socket> _clients = {};
  final Set<Future<void>> _requests = {};
  bool _closing = false;
  String? _ownedRoot;
  String startupPhase = 'private_directory';

  WorkspaceRunner({
    required this.root,
    required this.runtime,
    required this.registry,
    required this.binding,
  });

  Future<WasmPluginRecord> _record() async {
    if (runtime.activeCapsuleRootHex() != binding['owner']) {
      throw StateError('Runner Capsule changed');
    }
    if (runtime.executionHost != 'vps' ||
        runtime.executionIdentity != binding['executor_id']) {
      throw StateError('Runner host identity changed');
    }
    final records = await registry.loadPlugins();
    final matching = records.where(
      (record) =>
          record.id == binding['package_id'] &&
          record.pluginId == binding['plugin_id'] &&
          record.contractKind == pluginWorkspaceContractKind,
    );
    if (matching.length != 1) throw StateError('Runner package replaced');
    final resolved = await registry.resolveRuntimeBinding(
      binding['plugin_id'] as String,
    );
    if (resolved.packageDigestHex != binding['package_digest']) {
      throw StateError('Runner package bytes changed');
    }
    return matching.single;
  }

  Future<void> start() async {
    if (_lease != null || _closing) throw StateError('Runner already started');
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Private runner directory required');
    }
    final stat = await root.stat();
    if (stat.mode & 0x3f != 0) {
      throw StateError('Runner directory must be private (0700)');
    }
    final ownedRoot = await root.resolveSymbolicLinks();
    if (!_ownedRoots.add(ownedRoot)) {
      throw StateError('Runner already owns this data directory');
    }
    // Acquire before removing a stale socket. A second process must neither
    // execute cycles nor disconnect the existing owner.
    RandomAccessFile? lease;
    try {
      lease = await File(
        '${root.path}/runner.lock',
      ).open(mode: FileMode.append);
      await lease.lock(FileLock.exclusive);
    } catch (_) {
      await lease?.close();
      _ownedRoots.remove(ownedRoot);
      rethrow;
    }
    _ownedRoot = ownedRoot;
    _lease = lease;
    try {
      startupPhase = 'package_binding';
      final record = await _record();
      // Restart never manufactures a new grant, plan or order identity, and
      // does not require the exchange to be reachable at process startup.
      startupPhase = 'workspace_restore';
      await runtime.resumeWorkspaceScheduling(record);
      startupPhase = 'control_socket';
      final socketPath = '${root.path}/$_socketName';
      final stale = File(socketPath);
      if (await FileSystemEntity.type(socketPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await stale.delete();
      }
      _server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      _server!.listen((socket) {
        if (_closing || _clients.length >= 16) {
          socket.destroy();
          return;
        }
        _clients.add(socket);
        final request = _handle(socket);
        _requests.add(request);
        unawaited(request.whenComplete(() => _requests.remove(request)));
      });
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _handle(Socket socket) async {
    try {
      final request = await _readMessage(socket);
      final result = await dispatch(request);
      socket.writeln(jsonEncode({'ok': true, 'result': result}));
      await socket.flush();
    } catch (_) {
      try {
        socket.writeln(
          jsonEncode({
            'ok': false,
            'error': 'Workspace command failed; refresh before retrying',
          }),
        );
        await socket.flush();
      } catch (_) {}
    } finally {
      _clients.remove(socket);
      socket.destroy();
    }
  }

  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> request) async {
    if (_closing ||
        request['owner'] != binding['owner'] ||
        request['plugin_id'] != binding['plugin_id'] ||
        request['package_id'] != binding['package_id'] ||
        request['package_digest'] != binding['package_digest'] ||
        request['executor_id'] != binding['executor_id']) {
      throw StateError('Workspace request binding mismatch');
    }
    final record = await _record();
    final command = request['command'];
    Map<String, dynamic>? view;
    String? observationError;
    switch (command) {
      case 'adopt':
        if (request.length != 7 || request['checkpoint'] is! Map) {
          throw const FormatException();
        }
        await runtime.adoptWorkspaceFromLocal(
          record: record,
          checkpoint: Map<String, dynamic>.from(request['checkpoint'] as Map),
        );
      case 'status':
        if (request.length != 6) throw const FormatException();
        try {
          view = await runtime.runWorkspaceAction(
            record: record,
            action: 'open',
          );
        } catch (_) {
          observationError =
              'Exchange/workspace observation unavailable; '
              'runner is running, retained lifecycle is not verified';
        }
      case 'action':
        if (request.length != 8 ||
            request['action'] is! String ||
            request['settings'] is! Map) {
          throw const FormatException();
        }
        view = await runtime.runWorkspaceAction(
          record: record,
          action: request['action'] as String,
          settings: Map<String, dynamic>.from(request['settings'] as Map),
        );
      case 'execution':
        if (request.length != 9 ||
            request['enabled'] is! bool ||
            request['settings'] is! Map ||
            (request['scope'] != null && request['scope'] is! Map)) {
          throw const FormatException();
        }
        view = await runtime.setWorkspaceExecution(
          record: record,
          enabled: request['enabled'] as bool,
          approvedScope:
              request['scope'] == null
                  ? null
                  : Map<String, dynamic>.from(request['scope'] as Map),
          settings: Map<String, dynamic>.from(request['settings'] as Map),
        );
      default:
        throw const FormatException('Unsupported workspace command');
    }
    return {
      'binding': binding,
      'runner': {'state': 'running', 'started_at_ms': _startedAt},
      'view': view,
      if (observationError != null) 'observation_error': observationError,
    };
  }

  Future<void> close() async {
    _closing = true;
    await _server?.close();
    runtime.stopWorkspaceScheduling(pluginId: binding['plugin_id'] as String);
    for (final client in _clients.toList()) {
      client.destroy();
    }
    await Future.wait(_requests.toList());
    await runtime.drainWorkspaceActions(binding['plugin_id'] as String);
    // Do not unlink after releasing the lease: a new owner may already have
    // installed its socket. The stale socket is removed at the next startup.
    await _lease?.close();
    _lease = null;
    if (_ownedRoot != null) _ownedRoots.remove(_ownedRoot);
    _ownedRoot = null;
  }

  static Future<Map<String, dynamic>> request(
    Directory root,
    Map<String, dynamic> input,
  ) async {
    final socket = await Socket.connect(
      InternetAddress(
        '${root.path}/$_socketName',
        type: InternetAddressType.unix,
      ),
      0,
      timeout: const Duration(seconds: 10),
    );
    try {
      socket.writeln(jsonEncode(input));
      await socket.flush();
      return await _readMessage(socket);
    } finally {
      socket.destroy();
    }
  }
}

Future<Map<String, dynamic>> _readMessage(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream.timeout(const Duration(seconds: 90))) {
    final end = chunk.indexOf(10);
    bytes.addAll(end < 0 ? chunk : chunk.sublist(0, end));
    if (bytes.length > 8 * 1024 * 1024) throw const FormatException();
    if (end >= 0) break;
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) throw const FormatException();
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, dynamic>> _readPrivateJson(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('Private regular file required');
  }
  final stat = await file.stat();
  if (stat.mode & 0x3f != 0 || stat.size > 8192) {
    throw StateError('Private file must be bounded and mode 0600');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) throw const FormatException();
  return Map<String, dynamic>.from(decoded);
}
