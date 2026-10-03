import 'dart:convert';
import 'dart:io';

import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/ffi/hivra_bindings.dart';
import 'package:hivra_app/services/bingx_market_data_adapter.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_workspace_runtime.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_runtime_service.dart';
import 'package:crypto/crypto.dart';

import '../../bin/plugin_workspace_runner.dart';

// Run with Dart as well as Flutter: the executor must not depend on dart:ui,
// mobile vaults, Chat or Moltbook, even when using an unrelated package shape.
Future<void> main(List<String> args) async {
  if (args.length == 2 || args.length == 3) {
    await _checkInstalledWasm(
      File(args[0]).absolute,
      Directory(args[1]).absolute,
      args.length == 3 ? File(args[2]).absolute : null,
    );
    return;
  }
  final home = await Directory.systemTemp.createTemp('hivra_headless_');
  try {
    final files = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
    );
    final registry = _Registry();
    const owner =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    var digest = 'b' * 64;
    var credentialCalls = 0;
    var rewriteDigest = false;
    final seen = <Map<String, dynamic>?>[];
    final host = PluginHostApiService(
      handlers: [],
      resolveRuntimeBinding:
          (_) async => PluginRuntimeBinding.externalPackage(
            packageId: registry.record.id,
            packageVersion: registry.record.pluginVersion,
            packageKind: 'zip',
            packageDigestHex: digest,
            contractKind: pluginWorkspaceContractKind,
            capabilities: const [
              'workspace.render',
              'workspace.continue',
              'state.plugin.read_write',
            ],
          ),
      resolveRuntimeInvoke: (request, _) async {
        final previous = request.args['state'] as Map<String, dynamic>?;
        seen.add(previous);
        if (rewriteDigest) digest = 'c' * 64;
        final next = {
          'unrelated': [previous?['unrelated'] ?? 'first', 'package-owned'],
        };
        return PluginRuntimeInvokeEvidence(
          mode: 'wasmi_v1',
          modulePath: 'plugin/module.wasm',
          moduleSelection: 'zip_manifest',
          moduleDigestHex: 'd' * 64,
          invokeDigestHex: 'e' * 64,
          semanticStatus: PluginHostApiStatus.executed,
          semanticErrorCode: null,
          semanticErrorMessage: null,
          semanticResult: {
            'state': next,
            'requests': <Object>[],
            'view': {
              'title': 'Independent package',
              'message': 'Ready',
              'details': '',
              'fields': <Object>[],
              'actions': <Object>[],
              'columns': <Object>[],
              'rows': <Object>[],
            },
          },
        );
      },
    );
    PluginWorkspaceRuntime runtime() => PluginWorkspaceRuntime(
      registry: registry,
      pluginHostApi: host,
      fileStore: files,
      readActiveCapsuleRootHex: () => owner,
      readCredentials: ({required owner, required pluginId}) async {
        credentialCalls++;
        throw StateError('This package has no credential grant');
      },
      writeCredentials: ({
        required owner,
        required pluginId,
        required value,
      }) async {
        credentialCalls++;
        throw StateError('This package has no credential grant');
      },
    );
    await runtime().runWorkspaceAction(
      record: registry.record,
      action: 'observe',
    );
    final directory = await files.capsuleDirForHex(owner);
    final saved = await files.readPluginState(
      directory,
      registry.record.pluginId!,
      'workspace.v1.json',
    );
    await runtime().runWorkspaceAction(
      record: registry.record,
      action: 'continue_observation',
    );
    if (jsonEncode(seen.last) != saved) {
      throw StateError('Opaque state changed');
    }
    if (credentialCalls != 0) throw StateError('Unexpected credential access');
    registry.installed = false;
    var removedRejected = false;
    try {
      await runtime().runWorkspaceAction(
        record: registry.record,
        action: 'observe',
      );
    } on StateError {
      removedRejected = true;
    }
    if (!removedRejected) throw StateError('Removed package executed');
    registry.installed = true;
    // A changed binding is admitted only as a fresh action, never as a
    // continuation of the prior digest. No private-state migration in host.
    rewriteDigest = true;
    await runtime().runWorkspaceAction(
      record: registry.record,
      action: 'observe',
    );
    if (credentialCalls != 0) throw StateError('Unexpected credential access');
    stdout.writeln('headless workspace PASS');
  } finally {
    await home.delete(recursive: true);
  }
}

Future<void> _checkInstalledWasm(
  File package,
  Directory libraryDirectory,
  File? runnerExecutable,
) async {
  final home = await Directory('/tmp').createTemp('hivra_real_wasm_');
  final previousDirectory = Directory.current;
  Directory.current = libraryDirectory;
  try {
    final dirs = UserVisibleDataDirectoryService(homeOverride: home.path);
    final files = CapsuleFileStore(dirs: dirs);
    final registry = WasmPluginRegistryService(dataDirs: dirs);
    final record = await registry.installPluginFromFile(package);
    final wasm = WasmPluginRuntimeService(
      invokeJson: HivraBindings.invokeInstalledWasmJson,
    );
    final host = PluginHostApiService(
      handlers: [],
      resolveRuntimeBinding: registry.resolveRuntimeBinding,
      resolveRuntimeInvoke:
          (request, binding) => wasm.invoke(request: request, binding: binding),
    );
    final owner = 'a' * 64;
    final account = sha256.convert(utf8.encode('bingx:LIVE:123')).toString();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final plan = {
      'account_id': account,
      'symbol': 'BTC-USDT',
      'side': 'long',
      'timeframe': '5m',
      'origin': 10,
      'first_known': 20,
      'line_price': 96.5,
      'price': 96.5,
      'quantity': 0.518,
      'stop_price': 96.12,
      'margin': 0.99974,
      'leverage': 50,
      'prepared_at_ms': now - 1000,
      'expires_at_ms': now + 3600000,
    };
    var operationId = BingxMarketDataAdapter.entryOperationId(plan);
    final payloadKeys = plan.keys.toList()..sort();
    final payload = jsonEncode({for (final key in payloadKeys) key: plan[key]});
    var positionOpen = true;
    var posts = 0;
    var cancellations = 0;
    var orderId = '123';
    var orderStatus = 'FILLED';
    final market = BingxMarketDataAdapter(
      read: (uri) async {
        if (uri.path.endsWith('/contracts')) {
          return jsonEncode({
            'code': 0,
            'data': [
              {
                'symbol': 'BTC-USDT',
                'status': 1,
                'apiStateOpen': true,
                'pricePrecision': 2,
                'quantityPrecision': 3,
                'tradeMinQuantity': '0.001',
                'tradeMinUSDT': '5',
              },
            ],
          });
        }
        final spans = {
          '1d': 86400000,
          '4h': 14400000,
          '1h': 3600000,
          '30m': 1800000,
          '15m': 900000,
          '5m': 300000,
        };
        final span = spans[uri.queryParameters['interval']]!;
        final time = DateTime.now().toUtc().millisecondsSinceEpoch;
        final current = time ~/ span * span;
        return jsonEncode({
          'code': 0,
          'data': List.generate(
            600,
            (i) => [current - (599 - i) * span, 100, 101, 99, 100],
          ),
        });
      },
      sendAuthenticated: (method, uri, headers) async {
        dynamic data;
        if (method == 'DELETE' && orderId == '124') {
          if (uri.path != '/openApi/swap/v2/trade/order' ||
              uri.queryParameters['orderId'] != orderId ||
              uri.queryParameters['symbol'] != 'BTC-USDT') {
            throw StateError('Cancellation lost exact provider scope');
          }
          cancellations++;
          orderStatus = 'CANCELED';
          return jsonEncode({'code': 0, 'data': {}});
        }
        if (method != 'GET') {
          posts++;
          throw StateError('Probe forbids provider writes');
        }
        if (uri.path.endsWith('/uid')) {
          data = {'uid': '123'};
        } else if (uri.path.endsWith('/balance')) {
          data = [
            {'asset': 'USDT', 'availableMargin': '30'},
          ];
        } else if (uri.path.endsWith('/leverage')) {
          data = {'longLeverage': 50, 'shortLeverage': 20};
        } else if (uri.path.endsWith('/positions')) {
          data =
              positionOpen
                  ? [
                    {
                      'symbol': 'BTC-USDT',
                      'positionId': '456',
                      'positionSide': 'LONG',
                      'positionAmt': '0.518',
                      'avgPrice': '96.5',
                    },
                  ]
                  : [];
        } else if (uri.path.endsWith('/openOrders')) {
          data = [];
        } else if (uri.path.endsWith('/order')) {
          data = {
            'symbol': 'BTC-USDT',
            'clientOrderId': operationId.substring(0, 40),
            'orderID': orderId,
            'side': 'BUY',
            'positionSide': 'LONG',
            'type': 'LIMIT',
            'origQty': '0.518',
            'executedQty': orderStatus == 'FILLED' ? '0.518' : '0',
            'avgPrice': orderStatus == 'FILLED' ? '96.5' : '0',
            'price': '96.5',
            'status': orderStatus,
          };
        } else {
          throw StateError('Unexpected provider read');
        }
        return jsonEncode({'code': 0, 'data': data});
      },
    );
    final effects = ExternalEffectService(
      readActiveCapsuleRootHex: () => owner,
      fileStore: files,
      resolveAdapter: (_) => null,
    );
    await effects.prepare(
      operationId: operationId,
      pluginId: record.pluginId!,
      providerId: 'bingx',
      accountBindingId: account,
      effectKind: 'order.entry.place',
      canonicalPayloadJson: payload,
    );
    final directory = await files.capsuleDirForHex(owner, create: true);
    await files.writePluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
      jsonEncode({
        'version': 1,
        'settings': {
          'symbol': 'BTC-USDT',
          'detection_length': 3,
          'margin': 6.9,
          'entry_margin': 1.0,
          'stop_percent': 20.0,
        },
        'frames': [],
        'current_price': 100.0,
        'observed_at': now,
        'complete': false,
        'account': {
          'symbol': 'BTC-USDT',
          'endpoint': 'LIVE',
          'account_id': account,
          'account_label': 'Test account',
          'available_margin': 30.0,
          'long_leverage': 50,
          'short_leverage': 20,
          'price_precision': 2,
          'quantity_precision': 3,
          'min_quantity': 0.001,
          'min_notional': 5.0,
          'observed_at_ms': now,
        },
        'entry': {'plan': plan, 'attempted': true, 'evidence': null},
      }),
    );
    await _checkBoundedPresentation(
      host,
      record.pluginId!,
      jsonDecode(
            (await files.readPluginState(
              directory,
              record.pluginId!,
              'workspace.v1.json',
            ))!,
          )
          as Map<String, dynamic>,
      now,
    );
    PluginWorkspaceRuntime runtime() => PluginWorkspaceRuntime(
      registry: registry,
      pluginHostApi: host,
      fileStore: files,
      market: market,
      scheduleTimers: false,
      readActiveCapsuleRootHex: () => owner,
      readCredentials:
          ({required owner, required pluginId}) async => jsonEncode({
            'api_key': 'fixture-key',
            'secret_key': 'fixture-secret',
          }),
      writeCredentials:
          ({required owner, required pluginId, required value}) async =>
              throw StateError('No credential changes in probe'),
    );
    final initialView = await runtime().runWorkspaceAction(
      record: record,
      action: 'open',
    );
    await runtime().setWorkspaceExecution(
      record: record,
      enabled: true,
      approvedScope: Map<String, dynamic>.from(initialView['schedule'] as Map),
    );
    await runtime().runScheduledWorkspaceCycle(record);
    final opened = jsonDecode(
      (await files.readPluginState(
        directory,
        record.pluginId!,
        'workspace.v1.json',
      ))!,
    );
    if (opened['entry']['observed_position_id'] != '456') {
      throw StateError('Position observation lost');
    }
    positionOpen = false;
    // Recreate the executor to exercise saved state, not its in-memory reducer.
    await runtime().runScheduledWorkspaceCycle(record);
    final retired = await files.readPluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
    );
    if (jsonDecode(retired!)['entry'] != null) {
      throw StateError('Closed entry was not retired');
    }
    await runtime().runWorkspaceAction(record: record, action: 'open');
    final reopened = await files.readPluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
    );
    if (_canonicalJson(jsonDecode(reopened!)) !=
        _canonicalJson(jsonDecode(retired))) {
      throw StateError('Durable recovery resurrected a retired entry');
    }
    if (posts != 0) throw StateError('Unexpected provider write');
    final next = await runtime().runScheduledWorkspaceCycle(record);
    if (next['confirmation'] != null) {
      throw StateError('No line must mean waiting, not a fabricated entry');
    }
    // A second synthetic managed entry has no original line in the refreshed
    // market. Exercise real WASM cancellation through the same headless host.
    final newTime = DateTime.now().toUtc().millisecondsSinceEpoch;
    plan['prepared_at_ms'] = newTime;
    plan['expires_at_ms'] = newTime + 3600000;
    operationId = BingxMarketDataAdapter.entryOperationId(plan);
    orderId = '124';
    orderStatus = 'NEW';
    await effects.prepare(
      operationId: operationId,
      pluginId: record.pluginId!,
      providerId: 'bingx',
      accountBindingId: account,
      effectKind: 'order.entry.place',
      canonicalPayloadJson: jsonEncode({
        for (final key in payloadKeys) key: plan[key],
      }),
    );
    final pending =
        jsonDecode(
              (await files.readPluginState(
                directory,
                record.pluginId!,
                'workspace.v1.json',
              ))!,
            )
            as Map;
    pending['entry'] = {'plan': plan, 'attempted': true, 'evidence': null};
    await files.writePluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
      jsonEncode(pending),
    );
    await runtime().runScheduledWorkspaceCycle(record);
    final cancelled = jsonDecode(
      (await files.readPluginState(
        directory,
        record.pluginId!,
        'workspace.v1.json',
      ))!,
    );
    if (cancellations != 1 || posts != 0 || cancelled['entry'] != null) {
      throw StateError(
        'Invalidated unfilled entry did not retire after exact cancellation',
      );
    }
    await runtime().runScheduledWorkspaceCycle(record);
    if (cancellations != 1 || posts != 0) {
      throw StateError('Reopen duplicated cancellation or fabricated an entry');
    }
    await runtime().setWorkspaceExecution(record: record, enabled: false);
    final stopped = await runtime().runScheduledWorkspaceCycle(record);
    if (stopped['execution']['allow_new_entries'] != false || posts != 0) {
      throw StateError('Stop did not prevent new entries');
    }
    stdout.writeln(
      'installed WASM headless lifecycle/cancellation PASS; synthetic DELETE=1, POST=0; no network',
    );
    if (runnerExecutable != null) {
      await _checkProductionProcess(
        runnerExecutable,
        registry,
        files,
        record,
        owner,
      );
    }
  } finally {
    Directory.current = previousDirectory;
    await home.delete(recursive: true);
  }
}

Future<void> _checkProductionProcess(
  File executable,
  WasmPluginRegistryService fixtureRegistry,
  CapsuleFileStore fixtureFiles,
  WasmPluginRecord fixtureRecord,
  String owner,
) async {
  final root = await Directory('/tmp').createTemp('hivra_runner_process_');
  final dirs = UserVisibleDataDirectoryService(runtimeRootOverride: root.path);
  final registry = WasmPluginRegistryService(dataDirs: dirs);
  final files = CapsuleFileStore(dirs: dirs);
  final fixtureBinding = await fixtureRegistry.resolveRuntimeBinding(
    fixtureRecord.pluginId!,
  );
  final record = await registry.installPluginFromFile(
    File(fixtureBinding.packageFilePath!),
  );
  final binding = await registry.resolveRuntimeBinding(record.pluginId!);
  final config = {
    'owner': owner,
    'plugin_id': record.pluginId,
    'package_id': record.id,
    'package_digest': binding.packageDigestHex,
  };
  final configFile = File('${root.path}/runner.json');
  await configFile.writeAsString(jsonEncode(config), flush: true);
  if ((await Process.run('chmod', ['700', root.path])).exitCode != 0 ||
      (await Process.run('chmod', ['600', configFile.path])).exitCode != 0) {
    throw StateError('Cannot prepare private runner fixture');
  }
  final capsule = await files.capsuleDirForHex(owner);
  final rawGrant =
      (await fixtureFiles.readPluginState(
        await fixtureFiles.capsuleDirForHex(owner),
        fixtureRecord.pluginId!,
        'workspace-execution.v1.json',
      ))!;
  final grant = Map<String, dynamic>.from(jsonDecode(rawGrant) as Map);
  grant['package_id'] = record.id;
  grant['package_digest'] = binding.packageDigestHex;
  // This synthetic grant exercises timer recovery with read-only open;
  // it cannot submit a provider request or require live credentials.
  grant['scope']['action'] = 'open';
  grant['scope']['interval_seconds'] = 30;
  grant['allow_new_entries'] = false;
  await files.writePluginState(
    capsule,
    record.pluginId!,
    'workspace-execution.v1.json',
    jsonEncode(grant),
  );
  final effectsBefore = await files.readPluginState(
    capsule,
    record.pluginId!,
    'external_effects.v1.json',
  );
  Future<Process> start() async {
    final process = await Process.start(executable.path, ['serve', root.path]);
    final errors = process.stderr.transform(utf8.decoder).join();
    final ready = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .take(1)
        .toList()
        .then((lines) => lines.firstOrNull)
        .timeout(const Duration(seconds: 10));
    if (ready != 'Workspace runner ready') {
      process.kill();
      await process.exitCode;
      throw StateError(
        'Production process did not become ready: ${await errors}',
      );
    }
    return process;
  }

  Future<Map<String, dynamic>> status() async {
    final response = await WorkspaceRunner.request(root, {
      ...config,
      'command': 'status',
    });
    if (response['ok'] != true) throw StateError('Runner status failed');
    return Map<String, dynamic>.from(response['result'] as Map);
  }

  Process? process;
  try {
    process = await start();
    final duplicate = await Process.run(executable.path, ['serve', root.path]);
    if (duplicate.exitCode != 1 ||
        !duplicate.stderr.toString().contains('Workspace runner unavailable')) {
      throw StateError('Second production process was not refused');
    }
    final first = await status();
    if (first['runner']['state'] != 'running' ||
        first['view']['execution']['mode'] != 'vps' ||
        first['view']['execution']['allow_new_entries'] != false) {
      throw StateError('Production runner misrepresented its authority');
    }
    await Future<void>.delayed(const Duration(seconds: 31));
    final cycled = await status();
    if (cycled['view']['execution']['last_checked_at_ms'] is! int) {
      throw StateError('Production timer did not resume its persisted grant');
    }
    final stateBefore = await files.readPluginState(
      capsule,
      record.pluginId!,
      'workspace.v1.json',
    );
    process.kill(ProcessSignal.sigterm);
    if (await process.exitCode.timeout(const Duration(seconds: 10)) != 0) {
      throw StateError('Production shutdown failed');
    }
    process = await start();
    await status();
    if (await files.readPluginState(
          capsule,
          record.pluginId!,
          'workspace-execution.v1.json',
        ) !=
        jsonEncode(grant)) {
      throw StateError('Restart changed authority');
    }
    if (await files.readPluginState(
          capsule,
          record.pluginId!,
          'workspace.v1.json',
        ) !=
        stateBefore) {
      throw StateError('Restart changed opaque state');
    }
    if (await files.readPluginState(
          capsule,
          record.pluginId!,
          'external_effects.v1.json',
        ) !=
        effectsBefore) {
      throw StateError('Restart changed effect journal');
    }
    stdout.writeln(
      'production runner process/timer/restart/singleton PASS; real installed WASM; no network',
    );
  } finally {
    process?.kill(ProcessSignal.sigterm);
    if (process != null) await process.exitCode;
    await root.delete(recursive: true);
  }
}

Future<void> _checkBoundedPresentation(
  PluginHostApiService host,
  String pluginId,
  Map<String, dynamic> state,
  int now,
) async {
  final spans = {
    '1d': 86400000,
    '4h': 14400000,
    '1h': 3600000,
    '30m': 1800000,
    '15m': 900000,
    '5m': 300000,
  };
  state['settings']['detection_length'] = 7;
  List<dynamic> bar(int time, int span) {
    final price = 100.00000123456789 + (time ~/ span % 97) * 0.00000123456789;
    return [time, price, price + 1, price - 1, price];
  }

  state['frames'] = [
    for (final tf in spans.entries)
      {
        'timeframe': tf.key,
        'checked_at_ms': tf.key == '5m' ? null : now,
        'last_open':
            now ~/ tf.value * tf.value - tf.value * (tf.key == '5m' ? 2 : 1),
        'formation_start': now - 500 * tf.value,
        'atr': 2.00000123456789,
        'seed_sum': 20.0000123456789,
        'seed_count': 10,
        'bars': List.generate(
          8,
          (i) => bar(
            now ~/ tf.value * tf.value -
                tf.value * (8 - i + (tf.key == '5m' ? 1 : 0)),
            tf.value,
          ),
        ),
        'swings': List.generate(
          50,
          (i) => {
            'direction': i.isEven ? 1 : -1,
            'time': now - (i + 10) * tf.value,
            'price': 100.00000123456789 + i * 0.00000123456789,
          },
        ),
        for (final side in ['buy', 'sell'])
          side: List.generate(
            3,
            (i) => {
              'origin': now - (i + 12) * tf.value,
              'first_known': now - (i + 10) * tf.value,
              'price': 100.00000123456789 + i * 0.00000123456789,
              'top': 101.00000123456789,
              'bottom': 99.00000123456789,
              'touched': false,
              'consumed': false,
            },
          ),
      },
  ];
  state['complete'] = false;
  final plan = Map<String, dynamic>.from(state['entry']['plan'] as Map);
  final span = spans['5m']!;
  final current = now ~/ span * span;
  for (final action in ['market', 'present']) {
    final response = await host.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: pluginId,
        method: pluginWorkspaceMethod,
        args: {
          'action': action,
          'state': state,
          'observed_at_ms': now,
          if (action == 'market')
            'snapshot': {
              'symbol': 'BTC-USDT',
              'timeframe': '5m',
              'candles': List.generate(
                12,
                (i) => bar(current - (12 - i) * span, span),
              ),
              'history_end_ms': current - span,
              'batch_complete': true,
              'current_price': bar(current, span)[4],
              'current_candle': bar(current, span),
            },
        },
      ),
    );
    if (response.status != PluginHostApiStatus.executed) {
      throw StateError(
        'Dense six-frame $action failed: ${response.errorMessage}',
      );
    }
    final output = response.result!;
    state = Map<String, dynamic>.from(output['state'] as Map);
    final rows = output['view']['rows'] as List;
    final retainedPlan = state['entry']['plan'] as Map;
    if (retainedPlan.length != plan.length ||
        plan.entries.any((e) => retainedPlan[e.key] != e.value) ||
        (output['requests'] as List).isNotEmpty ||
        (action == 'market' ? rows.isNotEmpty : rows.length != 36)) {
      throw StateError('Presentation changed the plan or lost retained lines');
    }
  }
  stdout.writeln(
    'dense six-frame streaming/presentation PASS under unchanged WASM limits',
  );
  state['frames'][0]['buy'][0].addAll({
    'price': 110.0,
    'top': 111.0,
    'bottom': 109.0,
    'touched': false,
  });
  final filled = (plan['quantity'] as num) / 2;
  final position = {
    'position_id': '456',
    'side': 'long',
    'quantity': filled,
    'average_price': 96.4,
  };
  final evidence = {
    'account_id': plan['account_id'],
    'symbol': plan['symbol'],
    'client_order_id': BingxMarketDataAdapter.entryOperationId(
      plan,
    ).substring(0, 40),
    'order_id': '123',
    'status': 'partial',
    'filled_quantity': filled,
    'average_price': 96.4,
    'observed_at_ms': now,
  };
  for (final action in ['lifecycle', 'present']) {
    final saved = _canonicalJson(state);
    final response = await host.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: pluginId,
        method: pluginWorkspaceMethod,
        args: {
          'action': action,
          'state': state,
          'observed_at_ms': now,
          if (action == 'lifecycle')
            'snapshot': {
              'account_id': plan['account_id'],
              'symbol': plan['symbol'],
              'entry': evidence,
              'positions': [position],
              'orders': <Object>[],
              'observed_at_ms': now,
            },
        },
      ),
    );
    if (response.status != PluginHostApiStatus.executed) {
      throw StateError(
        'Dense filled-position $action failed: ${response.errorMessage}',
      );
    }
    final output = response.result!;
    state = Map<String, dynamic>.from(output['state'] as Map);
    final view = output['view'] as Map;
    final message = view['message'] as String;
    if (_canonicalJson(state['entry']['position']) !=
            _canonicalJson(position) ||
        _canonicalJson(state['entry']['plan']) != _canonicalJson(plan) ||
        (output['requests'] as List).isNotEmpty ||
        view['confirmation'] != null ||
        !message.contains('Fill-based stop estimate: 96.03') ||
        !message.contains('not confirmation of exchange-side protection') ||
        !message.contains('110 on 1D') ||
        (action == 'present' &&
            (saved != _canonicalJson(state) ||
                (view['rows'] as List).length != 36))) {
      throw StateError(
        'Fill management changed identity, invented an effect or lost its projection',
      );
    }
  }
  stdout.writeln(
    'dense actual-WASM partial-fill management/reopen PASS; no effects',
  );
  Map<String, dynamic>? exitRequest;
  for (final action in [
    'exit_ready',
    'place_exit',
    'validate_exit',
    'exit',
    'present',
  ]) {
    final saved = _canonicalJson(state);
    final response = await host.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: pluginId,
        method: pluginWorkspaceMethod,
        args: {
          'action': action,
          'state': state,
          'observed_at_ms': now,
          if (action == 'exit')
            'snapshot': {
              'account_id': plan['account_id'],
              'symbol': plan['symbol'],
              'client_order_id': BingxMarketDataAdapter.exitOperationId(
                Map<String, dynamic>.from(exitRequest!['plan'] as Map),
              ).substring(0, 40),
              'order_id': '987',
              'status': 'open',
              'filled_quantity': 0.0,
              'average_price': 0.0,
              'observed_at_ms': now,
            },
        },
      ),
    );
    if (response.status != PluginHostApiStatus.executed) {
      throw StateError('Actual-WASM $action failed: ${response.errorMessage}');
    }
    final output = response.result!;
    state = Map<String, dynamic>.from(output['state'] as Map);
    if (action == 'exit_ready') {
      exitRequest = Map<String, dynamic>.from(
        output['view']['confirmation'] as Map,
      );
      if (exitRequest['kind'] != 'position.exit.place' ||
          exitRequest['plan']['quantity'] != filled) {
        throw StateError('Exit is not sized to the actual partial fill');
      }
    }
    if (action == 'place_exit' &&
        _canonicalJson((output['requests'] as List).single) !=
            _canonicalJson(exitRequest)) {
      throw StateError('Confirmed exit plan changed');
    }
    if (action != 'place_exit' && (output['requests'] as List).isNotEmpty) {
      throw StateError('Exit read/validation dispatched an effect');
    }
    if (action == 'present' && saved != _canonicalJson(state)) {
      throw StateError('Reopen changed the fixed exit');
    }
  }
  stdout.writeln(
    'dense actual-WASM exit preparation, admission and fixed-order reopen PASS; synthetic evidence only',
  );
}

String _canonicalJson(Object? value) {
  Object? ordered(Object? v) {
    if (v is List) return v.map(ordered).toList();
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(v[key])};
    }
    return v;
  }

  return jsonEncode(ordered(value));
}

class _Registry extends WasmPluginRegistryService {
  bool installed = true;
  final record = const WasmPluginRecord(
    id: 'headless-test-package',
    displayName: 'Independent package',
    originalFileName: 'independent.zip',
    storedFileName: 'independent.zip',
    sizeBytes: 1,
    installedAtIso: '2026-10-02T00:00:00Z',
    packageKind: 'zip',
    pluginId: 'hivra.contract.headless-test.v1',
    pluginVersion: '1.0.0',
    contractKind: pluginWorkspaceContractKind,
    runtimeAbi: 'hivra_host_abi_v2',
    runtimeEntryExport: 'hivra_evaluate_v1',
    runtimeModulePath: 'plugin/module.wasm',
    capabilities: [
      'workspace.render',
      'workspace.continue',
      'state.plugin.read_write',
    ],
  );
  @override
  Future<List<WasmPluginRecord>> loadPlugins() async =>
      installed ? [record] : [];
}
