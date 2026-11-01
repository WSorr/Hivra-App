import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/ffi/hivra_bindings.dart';
import 'package:hivra_app/services/plugin_capability_dispatcher.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
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
  if ((args.length == 2 || args.length == 4) &&
      args.first == '--runner-shutdown') {
    await _checkShutdownProcess(
      File(args[1]).absolute,
      memoryProbe: args.length == 4 ? File(args[2]).absolute : null,
      service: args.length == 4 ? File(args[3]).absolute : null,
    );
    return;
  }
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
            packageDigestHex: registry.digest,
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
        if (rewriteDigest) registry.digest = 'c' * 64;
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
    final beforeReplacement = await files.readPluginState(
      directory,
      registry.record.pluginId!,
      'workspace.v1.json',
    );
    rewriteDigest = true;
    var replacementRejected = false;
    try {
      await runtime().runWorkspaceAction(
        record: registry.record,
        action: 'observe',
      );
    } on StateError {
      replacementRejected = true;
    }
    if (!replacementRejected ||
        await files.readPluginState(
              directory,
              registry.record.pluginId!,
              'workspace.v1.json',
            ) !=
            beforeReplacement) {
      throw StateError('Replaced package committed stale state');
    }
    rewriteDigest = false;
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

Future<void> _checkShutdownProcess(
  File executable, {
  File? memoryProbe,
  File? service,
}) async {
  final root = await Directory('/tmp').createTemp('hivra_shutdown_fixture_');
  final previousDirectory = Directory.current;
  Directory.current = executable.parent;
  try {
    const pluginId = 'hivra.contract.shutdown-test.v1';
    final scope = {
      'version': 2,
      'description': 'Provider-free shutdown fixture',
      'access': {'version': 2, 'network': []},
      'action': 'open',
      'interval_seconds': 30,
    };
    final response = jsonEncode({
      'schema_version': 1,
      'status': 'executed',
      'result': {
        'state': {
          'unrelated_private_shape': [7, 'retained'],
        },
        'requests': <Object>[],
        'view': {
          'title': 'Shutdown test',
          'message': 'No provider requests or trading capabilities',
          'details': '',
          'fields': <Object>[],
          'actions': <Object>[],
          'columns': <Object>[],
          'rows': <Object>[],
          'schedule': scope,
        },
      },
    });
    final source = File('${root.path}/fixture.rs');
    await source.writeAsString('''#![no_std]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }
static OUTPUT: &[u8] = br###"$response"###;
static mut INPUT: [u8; 65536] = [0; 65536];
#[no_mangle]
pub extern "C" fn hivra_alloc_v1(len: u32) -> u32 {
    if len > 65536 { return 0; }
    core::ptr::addr_of_mut!(INPUT) as u32
}
#[no_mangle]
pub extern "C" fn hivra_dealloc_v1(_: u32, _: u32) {}
#[no_mangle]
pub extern "C" fn hivra_evaluate_v1(_: u32, _: u32) -> u64 {
    ((OUTPUT.as_ptr() as u64) << 32) | OUTPUT.len() as u64
}
''');
    final module = File('${root.path}/fixture.wasm');
    final compiled = await Process.run('rustc', [
      '--edition=2021',
      '--crate-type=cdylib',
      '--target=wasm32-unknown-unknown',
      '-C',
      'opt-level=s',
      '-C',
      'panic=abort',
      source.path,
      '-o',
      module.path,
    ]);
    if (compiled.exitCode != 0) {
      throw StateError('Cannot build test WASM: ${compiled.stderr}');
    }
    final manifest = utf8.encode(
      jsonEncode({
        'schema': 'hivra.plugin.manifest',
        'version': 1,
        'release_version': '1.0.0',
        'plugin_id': pluginId,
        'contract': {'kind': pluginWorkspaceContractKind},
        'runtime': {
          'abi': 'hivra_host_abi_v2',
          'entry_export': 'hivra_evaluate_v1',
          'module_path': 'plugin/module.wasm',
        },
        'capabilities': [
          ...pluginWorkspaceRequiredCapabilities,
          'workspace.schedule',
        ],
      }),
    );
    final bytes = await module.readAsBytes();
    final package = File('${root.path}/fixture.zip');
    await package.writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile('plugin/manifest.json', manifest.length, manifest),
          )
          ..addFile(ArchiveFile('plugin/module.wasm', bytes.length, bytes)),
      )!,
    );
    final dirs = UserVisibleDataDirectoryService(
      runtimeRootOverride: '${root.path}/source',
    );
    final registry = WasmPluginRegistryService(dataDirs: dirs);
    final files = CapsuleFileStore(dirs: dirs);
    final record = await registry.installPluginFromFile(package);
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
      fileStore: files,
      readActiveCapsuleRootHex: () => 'a' * 64,
      scheduleTimers: false,
      readCredentials:
          ({required owner, required pluginId}) async =>
              throw StateError('No test credentials'),
    );
    await runtime.setWorkspaceExecution(
      record: record,
      enabled: true,
      expiresAtMs: null,
      approvedScope: scope,
    );
    await _checkProductionProcess(
      executable,
      registry,
      files,
      record,
      'a' * 64,
      memoryProbe: memoryProbe,
      service: service,
    );
  } finally {
    Directory.current = previousDirectory;
    await root.delete(recursive: true);
  }
}

Future<void> _checkInstalledWasm(
  File package,
  Directory libraries,
  File? executable,
) async {
  final previousDirectory = Directory.current;
  Directory.current = libraries;
  final home = await Directory.systemTemp.createTemp('hivra_common_wasm_');
  try {
    final dirs = UserVisibleDataDirectoryService(homeOverride: home.path);
    final registry = WasmPluginRegistryService(dataDirs: dirs);
    final files = CapsuleFileStore(dirs: dirs);
    final record = await registry.installPluginFromFile(package);
    final wasm = WasmPluginRuntimeService(
      invokeJson: HivraBindings.invokeInstalledWasmJson,
    );
    final owner = 'a' * 64;
    final keys = jsonEncode({
      'version': 3,
      'connections': {
        'default': {'api_key': 'fixture-api', 'secret_key': 'fixture-secret'},
      },
    });
    var phase = 'partial';
    var writes = 0;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final account =
        sha256.convert(utf8.encode('bingx:LIVE:123456789')).toString();
    final plan = {
      'account_id': account,
      'symbol': 'BTC-USDT',
      'side': 'long',
      'timeframe': '1m',
      'origin': now - 3600000,
      'first_known': now - 1800000,
      'line_price': 96.5,
      'price': 96.5,
      'quantity': 1.0,
      'stop_price': 96.4,
      'margin': 1.93,
      'leverage': 50,
      'prepared_at_ms': now - 600000,
      'expires_at_ms': now + 3600000,
    };
    final exitPlan = {
      'entry_plan': plan,
      'position_id': '456',
      'quantity': 1.0,
      'average_price': 96.5,
      'price': 105.0,
      'prepared_at_ms': now - 1000,
      'expires_at_ms': now + 59000,
    };
    final settings = {
      'symbol': 'BTC-USDT',
      'detection_length': 3,
      'margin': 6.9,
      'timeframes': '1m',
      'entry_margin': 1.93,
      'stop_percent': 20.0,
    };
    final seed = {
      'version': 2,
      'new_entries': true,
      'intents': <String, String>{},
      'clients': <String, String>{},
      'engine': {
        'version': 1,
        'settings': settings,
        'frames': [],
        'current_price': 100.0,
        'observed_at': now,
        'complete': false,
        'retired_before_ms': 0,
        'parked': [],
        'account': {
          'symbol': 'BTC-USDT',
          'endpoint': 'LIVE',
          'account_id': account,
          'account_label': 'Fixture account',
          'available_margin': 30.0,
          'long_leverage': 50,
          'short_leverage': 20,
          'price_precision': 2,
          'quantity_precision': 3,
          'min_quantity': 0.001,
          'min_notional': 5.0,
          'observed_at_ms': now,
        },
        'entry': {
          'plan': plan,
          'attempted': true,
          'evidence': {
            'account_id': account,
            'symbol': 'BTC-USDT',
            'client_order_id': 'b' * 40,
            'order_id': '123',
            'status': 'filled',
            'filled_quantity': 1.0,
            'average_price': 96.5,
            'observed_at_ms': now,
          },
          'observed_position_id': '456',
          'lifecycle_observed_at_ms': now,
          'position': {
            'position_id': '456',
            'side': 'long',
            'quantity': 1.0,
            'average_price': 96.5,
          },
          'profit_exit': {
            'plan': exitPlan,
            'attempted': true,
            'evidence': {
              'account_id': account,
              'symbol': 'BTC-USDT',
              'client_order_id': 'c' * 40,
              'order_id': '999',
              'status': 'open',
              'filled_quantity': 0.0,
              'average_price': 0.0,
              'observed_at_ms': now,
            },
          },
        },
      },
    };
    final directory = await files.capsuleDirForHex(owner, create: true);
    await files.writePluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
      jsonEncode(seed),
    );
    final access = {
      'version': 2,
      'credentials': {
        'default': [
          {'id': 'api_key', 'label': 'API key'},
          {'id': 'secret_key', 'label': 'Secret key'},
        ],
      },
      'network': [
        {
          'origin': 'https://open-api.bingx.com',
          'methods': ['GET'],
          'credential': null,
        },
        {
          'origin': 'https://open-api.bingx.com',
          'methods': ['GET'],
          'credential': 'default',
        },
      ],
    };
    PluginWorkspaceRuntime runtime() => PluginWorkspaceRuntime(
      registry: registry,
      pluginHostApi: PluginHostApiService(
        handlers: [],
        resolveRuntimeBinding: registry.resolveRuntimeBinding,
        resolveRuntimeInvoke: (request, binding) async {
          final evidence = await wasm.invoke(
            request: request,
            binding: binding,
          );
          return evidence;
        },
      ),
      fileStore: files,
      readActiveCapsuleRootHex: () => owner,
      scheduleTimers: false,
      readCredentials: ({required owner, required pluginId}) async => keys,

      capabilities: PluginCapabilityDispatcher(
        send: (method, uri, headers, body) async {
          if (method != 'GET') {
            writes++;
            throw StateError('No network mutations in this fixture');
          }
          dynamic data;
          if (uri.path.endsWith('/uid')) {
            data = {'uid': '123456789'};
          } else if (uri.path.endsWith('/order')) {
            final exit = uri.queryParameters['clientOrderId'] == 'c' * 40;
            data = {
              'orderId': exit ? '999' : '123',
              'symbol': 'BTC-USDT',
              'clientOrderId': exit ? 'c' * 40 : 'b' * 40,
              'side': exit ? 'SELL' : 'BUY',
              'positionSide': 'LONG',
              'reduceOnly': exit,
              'type': 'LIMIT',
              'origQty': '1',
              'price': exit ? '105' : '96.5',
              'executedQty': exit ? (phase == 'partial' ? '0.5' : '1') : '1',
              'avgPrice': exit ? '105' : '96.5',
              'status':
                  exit && phase == 'partial' ? 'PARTIALLY_FILLED' : 'FILLED',
            };
          } else if (uri.path.endsWith('/positions')) {
            data =
                phase == 'partial'
                    ? [
                      {
                        'symbol': 'BTC-USDT',
                        'positionId': '456',
                        'positionSide': 'LONG',
                        'positionAmt': '0.5',
                        'avgPrice': '96.5',
                      },
                    ]
                    : [];
          } else if (uri.path.endsWith('/openOrders')) {
            data = [
              {
                'symbol': 'BTC-USDT',
                'orderId': '789',
                'clientOrderId': '',
                'side': 'BUY',
                'positionSide': 'LONG',
                'type': 'TRIGGER_LIMIT',
                'status': 'NEW',
                'price': '90',
                'stopPrice': '91',
                'origQty': '2',
                'executedQty': '0',
              },
              if (phase == 'partial')
                {
                  'symbol': 'BTC-USDT',
                  'orderId': '999',
                  'clientOrderId': 'c' * 40,
                  'side': 'SELL',
                  'positionSide': 'LONG',
                  'type': 'LIMIT',
                  'status': 'PARTIALLY_FILLED',
                  'price': '105',
                  'stopPrice': '0',
                  'origQty': '1',
                  'executedQty': '0.5',
                },
            ];
          } else if (uri.path.endsWith('/klines')) {
            final start = int.tryParse(uri.queryParameters['startTime'] ?? '');
            final end = int.tryParse(uri.queryParameters['endTime'] ?? '');
            final clock = DateTime.now().millisecondsSinceEpoch;
            final span =
                const {
                  '1m': 60000,
                  '5m': 300000,
                  '15m': 900000,
                  '30m': 1800000,
                  '1h': 3600000,
                  '4h': 14400000,
                  '1d': 86400000,
                }[uri.queryParameters['interval']]!;
            final current = clock - clock % span;
            final first = start ?? current - span;
            final last = end ?? current;
            data = [
              for (var t = first; t <= last; t += span)
                [t, '100', '101', '99', '100', '0'],
            ];
          } else {
            throw StateError('Unexpected fixture request ${uri.path}');
          }
          return {
            'status': 200,
            'body': jsonEncode({'code': 0, 'data': data}),
          };
        },
      ),
    );
    await runtime().setWorkspaceExecution(
      record: record,
      enabled: true,
      expiresAtMs: null,
      approvedScope: {
        'version': 2,
        'access': access,
        'description': 'Synthetic read-only observation',
      },
      credentialBindings: {
        'default': {
          'api_key': 'fixture-api-reference',
          'secret_key': 'fixture-secret-reference',
        },
      },
    );
    // A replacement must stay within the existing sandbox budget at the full
    // supported private-state shape, not only with an empty candle cache.
    final original =
        jsonDecode(
              (await files.readPluginState(
                directory,
                record.pluginId!,
                'workspace.v1.json',
              ))!,
            )
            as Map;
    final dense = jsonDecode(jsonEncode(original)) as Map;
    final engine = dense['engine'] as Map;
    final clock = DateTime.now().millisecondsSinceEpoch;
    final spans = {
      '1d': 86400000,
      '4h': 14400000,
      '1h': 3600000,
      '30m': 1800000,
      '15m': 900000,
      '5m': 300000,
    };
    engine['settings']['timeframes'] = 'all';
    engine['settings']['detection_length'] = 7;
    engine['entry']['plan']['timeframe'] = '5m';
    engine['entry']['profit_exit']['plan']['entry_plan']['timeframe'] = '5m';
    engine['complete'] = true;
    engine['observed_at'] = clock;
    engine['frames'] = [
      for (final tf in spans.entries)
        {
          'timeframe': tf.key,
          'checked_at_ms': clock,
          'last_open': clock ~/ tf.value * tf.value - tf.value,
          'formation_start': clock - 500 * tf.value,
          'atr': 2.00000123456789,
          'seed_sum': 20.0000123456789,
          'seed_count': 10,
          'bars': [
            for (var i = 0; i < 8; i++)
              [
                clock ~/ tf.value * tf.value - tf.value * (8 - i),
                100.00000123456789,
                101.00000123456789,
                99.00000123456789,
                100.00000123456789,
              ],
          ],
          'swings': [
            for (var i = 0; i < 50; i++)
              [
                i.isEven ? 1 : -1,
                clock - (i + 10) * tf.value,
                100.00000123456789 + i * 0.00000123456789,
              ],
          ],
          for (final side in ['buy', 'sell'])
            side: [
              for (var i = 0; i < 3; i++)
                {
                  'origin': clock - (i + 12) * tf.value,
                  'first_known': clock - (i + 10) * tf.value,
                  'price': 100.00000123456789 + i * 0.00000123456789,
                  'top': 101.00000123456789,
                  'bottom': 99.00000123456789,
                  'touched': false,
                  'consumed': false,
                },
            ],
        },
    ];
    await files.writePluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
      jsonEncode(dense),
    );
    await runtime().runWorkspaceAction(record: record, action: 'open');
    await runtime().runWorkspaceAction(record: record, action: 'refresh_order');
    await files.writePluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
      jsonEncode(original),
    );
    stdout.writeln(
      'common API actual-WASM dense six-frame streaming/presentation PASS; unchanged sandbox limits',
    );
    await runtime().runWorkspaceAction(record: record, action: 'refresh_order');
    final partial =
        jsonDecode(
              (await files.readPluginState(
                directory,
                record.pluginId!,
                'workspace.v1.json',
              ))!,
            )
            as Map;
    if (partial['engine']['entry']?['position']?['quantity'] != 0.5 ||
        partial['engine']['entry']?['profit_exit']?['evidence']?['status'] !=
            'partial') {
      throw StateError(
        'Actual WASM lost partial exit evidence: ${partial['engine']['entry']}',
      );
    }
    stdout.writeln(
      'common API actual-WASM partial reducing fill retained; manual order unchanged PASS',
    );
    phase = 'filled';
    await runtime().runWorkspaceAction(record: record, action: 'refresh_order');
    final retired = await files.readPluginState(
      directory,
      record.pluginId!,
      'workspace.v1.json',
    );
    if ((jsonDecode(retired!) as Map)['engine']['entry'] != null) {
      throw StateError(
        'Actual WASM did not retire the exact filled reducing exit',
      );
    }
    await runtime().runWorkspaceAction(record: record, action: 'open');
    final reopened = jsonDecode(
      (await files.readPluginState(
        directory,
        record.pluginId!,
        'workspace.v1.json',
      ))!,
    );
    if (reopened['engine']['entry'] != null || writes != 0) {
      throw StateError('Restart restored a completed plan or sent an effect');
    }
    stdout.writeln(
      'common API actual-WASM full reducing closure/reopen PASS; synthetic provider only, no network or writes',
    );
    if (executable != null) {
      await _checkProductionProcess(executable, registry, files, record, owner);
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
  String owner, {
  File? memoryProbe,
  File? service,
}) async {
  final root = await Directory('/tmp').createTemp('hivra_runner_process_');
  final sourceRoot = await Directory('/tmp').createTemp('hivra_runner_source_');
  Process? process;
  try {
    final sourceDirs = UserVisibleDataDirectoryService(
      runtimeRootOverride: sourceRoot.path,
    );
    final sourceRegistry = WasmPluginRegistryService(dataDirs: sourceDirs);
    final sourceFiles = CapsuleFileStore(dirs: sourceDirs);
    final dirs = UserVisibleDataDirectoryService(
      runtimeRootOverride: root.path,
    );
    final registry = WasmPluginRegistryService(dataDirs: dirs);
    final files = CapsuleFileStore(dirs: dirs);
    final fixtureBinding = await fixtureRegistry.resolveRuntimeBinding(
      fixtureRecord.pluginId!,
    );
    if ((await Process.run('chmod', ['700', root.path])).exitCode != 0) {
      throw StateError('Cannot prepare private runner fixture');
    }
    final packageBytes =
        await File(fixtureBinding.packageFilePath!).readAsBytes();
    final installation = {
      'owner': owner,
      'plugin_id': fixtureRecord.pluginId,
      'package_digest': sha256.convert(packageBytes).toString(),
      'executor_id': 'f' * 64,
      'package': base64Encode(packageBytes),
      'credentials': null,
    };
    Future<Map<String, dynamic>> setup(Map<String, dynamic> input) async {
      final installer = await Process.start(executable.path, [
        'setup',
        root.path,
      ]);
      final output = installer.stdout.transform(utf8.decoder).join();
      final errors = installer.stderr.transform(utf8.decoder).join();
      installer.stdin.writeln(jsonEncode(input));
      await installer.stdin.close();
      final code = await installer.exitCode.timeout(
        const Duration(seconds: 30),
      );
      final raw = await output;
      if (code != 0) throw StateError('Runner setup failed: ${await errors}');
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    }

    final config = await setup(installation);
    final record = (await registry.loadPlugins()).single;
    final repeated = await setup(installation);
    if (jsonEncode(config) != jsonEncode(repeated) ||
        await files.readPluginState(
              await files.capsuleDirForHex(owner),
              record.pluginId!,
              'workspace-execution.v1.json',
            ) !=
            null) {
      throw StateError(
        'Repeated setup changed the binding or created authority',
      );
    }
    try {
      await setup({...installation, 'owner': 'e' * 64});
      throw StateError('Foreign installation was accepted');
    } on StateError catch (error) {
      if (!error.message.toString().startsWith('Runner setup failed:')) rethrow;
    }
    final sourceRecord = await sourceRegistry.installPluginFromFile(
      File(fixtureBinding.packageFilePath!),
    );
    final binding = await registry.resolveRuntimeBinding(record.pluginId!);
    final capsule = await files.capsuleDirForHex(owner);
    final sourceCapsule = await sourceFiles.capsuleDirForHex(
      owner,
      create: true,
    );
    final rawGrant =
        (await fixtureFiles.readPluginState(
          await fixtureFiles.capsuleDirForHex(owner),
          fixtureRecord.pluginId!,
          'workspace-execution.v1.json',
        ))!;
    final grant = Map<String, dynamic>.from(jsonDecode(rawGrant) as Map);
    grant['package_id'] = sourceRecord.id;
    grant['package_digest'] = binding.packageDigestHex;
    // This synthetic grant exercises timer recovery with read-only open;
    // it cannot submit a provider request or require live credentials.
    grant['scope']['action'] = 'open';
    grant['scope']['interval_seconds'] = 30;
    grant['enabled'] = true;
    grant['executor'] = 'local';
    await sourceFiles.writePluginState(
      sourceCapsule,
      sourceRecord.pluginId!,
      'workspace-execution.v1.json',
      jsonEncode(grant),
    );
    final sourceWasm = WasmPluginRuntimeService(
      invokeJson: HivraBindings.invokeInstalledWasmJson,
    );
    final sourceRuntime = PluginWorkspaceRuntime(
      registry: sourceRegistry,
      pluginHostApi: PluginHostApiService(
        handlers: [],
        resolveRuntimeBinding: sourceRegistry.resolveRuntimeBinding,
        resolveRuntimeInvoke:
            (request, binding) =>
                sourceWasm.invoke(request: request, binding: binding),
      ),
      fileStore: sourceFiles,
      readActiveCapsuleRootHex: () => owner,
      scheduleTimers: false,
      readCredentials:
          ({required owner, required pluginId}) async =>
              throw StateError('No live credentials in process smoke'),
    );
    await sourceRuntime.runWorkspaceAction(
      record: sourceRecord,
      action: 'open',
    );
    final checkpoint = await sourceRuntime.releaseWorkspaceToVps(
      sourceRecord,
      executorId: config['executor_id'] as String,
    );
    final effectsBefore = await files.readPluginState(
      capsule,
      record.pluginId!,
      'external_effects.v1.json',
    );
    Future<Process> start() async {
      final process = await Process.start(executable.path, [
        'serve',
        root.path,
      ]);
      final errors = process.stderr.transform(utf8.decoder).join();
      try {
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
      } catch (_) {
        process.kill(ProcessSignal.sigterm);
        await process.exitCode;
        await errors;
        rethrow;
      }
    }

    Future<Map<String, dynamic>> status() async {
      final response = await WorkspaceRunner.request(root, {
        ...config,
        'command': 'status',
      });
      if (response['ok'] != true) throw StateError('Runner status failed');
      return Map<String, dynamic>.from(response['result'] as Map);
    }

    process = await start();
    try {
      await setup(installation);
      throw StateError('Setup replaced a live production installation');
    } on StateError catch (error) {
      if (!error.message.toString().startsWith('Runner setup failed:')) rethrow;
    }
    await status();
    final adopted = await WorkspaceRunner.request(root, {
      ...config,
      'command': 'adopt',
      'checkpoint': checkpoint,
    });
    if (adopted['ok'] != true ||
        await files.readPluginState(
              capsule,
              record.pluginId!,
              'workspace.v1.json',
            ) !=
            checkpoint['workspace']) {
      throw StateError('Production runner did not adopt exact source state');
    }
    var sourceRejected = false;
    try {
      await sourceRuntime.runWorkspaceAction(
        record: sourceRecord,
        action: 'open',
      );
    } on StateError {
      sourceRejected = true;
    }
    if (!sourceRejected) throw StateError('Detached source still executes');
    final importedGrant = await files.readPluginState(
      capsule,
      record.pluginId!,
      'workspace-execution.v1.json',
    );
    final duplicate = await Process.run(executable.path, ['serve', root.path]);
    if (duplicate.exitCode != 1 ||
        !duplicate.stderr.toString().contains('Workspace runner unavailable')) {
      throw StateError('Second production process was not refused');
    }
    final first = await status();
    if (first['runner']['state'] != 'running' ||
        first['view']['execution']['mode'] != 'vps' ||
        first['view']['execution']['enabled'] != true) {
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
    final idle = await Socket.connect(
      InternetAddress(
        '${root.path}/runner.sock',
        type: InternetAddressType.unix,
      ),
      0,
    );
    final partial = await Socket.connect(
      InternetAddress(
        '${root.path}/runner.sock',
        type: InternetAddressType.unix,
      ),
      0,
    );
    try {
      partial.write('{"command":');
      await partial.flush();
      await status();
      final elapsed = Stopwatch()..start();
      process.kill(ProcessSignal.sigterm);
      if (await process.exitCode.timeout(const Duration(seconds: 10)) != 0) {
        throw StateError('Production shutdown failed');
      }
      stdout.writeln(
        'SIGTERM clean exit in ${elapsed.elapsedMilliseconds}ms; idle/partial clients disconnected',
      );
    } finally {
      idle.destroy();
      partial.destroy();
    }
    if (jsonEncode(await setup(installation)) != jsonEncode(config) ||
        await files.readPluginState(
              capsule,
              record.pluginId!,
              'workspace.v1.json',
            ) !=
            stateBefore ||
        await files.readPluginState(
              capsule,
              record.pluginId!,
              'workspace-execution.v1.json',
            ) !=
            importedGrant ||
        await files.readPluginState(
              capsule,
              record.pluginId!,
              'external_effects.v1.json',
            ) !=
            effectsBefore) {
      throw StateError(
        'Reinstallation changed the binding, workspace, authority or journal',
      );
    }
    process = await start();
    final replay = await WorkspaceRunner.request(root, {
      ...config,
      'command': 'adopt',
      'checkpoint': checkpoint,
    });
    if (replay['ok'] != true) {
      throw StateError('Restart did not acknowledge exact handoff replay');
    }
    await status();
    if (await files.readPluginState(
          capsule,
          record.pluginId!,
          'workspace-execution.v1.json',
        ) !=
        importedGrant) {
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
    process.kill(ProcessSignal.sigint);
    if (await process.exitCode.timeout(const Duration(seconds: 10)) != 0) {
      throw StateError('Production SIGINT shutdown failed');
    }
    process = null;
    if (memoryProbe != null && service != null) {
      final memory = await Process.run('python3', [
        memoryProbe.path,
        executable.path,
        service.path,
        root.path,
      ]);
      if (memory.exitCode != 0) {
        throw StateError('Memory recovery probe failed: ${memory.stderr}');
      }
      stdout.write(memory.stdout);
    }
    stdout.writeln(
      'production runner setup/reinstall/handoff/timer/restart/replay/singleton PASS; real installed WASM; no network',
    );
  } finally {
    process?.kill(ProcessSignal.sigterm);
    if (process != null) {
      final child = process;
      await child.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          child.kill(ProcessSignal.sigkill);
          return child.exitCode;
        },
      );
    }
    await root.delete(recursive: true);
    await sourceRoot.delete(recursive: true);
  }
}

class _Registry extends WasmPluginRegistryService {
  bool installed = true;
  String digest = 'b' * 64;
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
  Future<PluginRuntimeBinding> resolveRuntimeBinding(String pluginId) async =>
      PluginRuntimeBinding.externalPackage(
        packageId: record.id,
        packageVersion: '1.0.0',
        packageKind: 'zip',
        packageDigestHex: digest,
        contractKind: pluginWorkspaceContractKind,
        capabilities: record.capabilities,
      );
  @override
  Future<List<WasmPluginRecord>> loadPlugins() async =>
      installed ? [record] : [];
}
