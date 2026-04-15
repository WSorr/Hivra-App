import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/wasm_plugin_package_preflight_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const service = WasmPluginPackagePreflightService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'hivra_wasm_plugin_preflight_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('accepts valid wasm binary package', () async {
    final file = File('${tempDir.path}/valid.wasm');
    await file.writeAsBytes(
      const <int>[0, 97, 115, 109, 1, 0, 0, 0],
      flush: true,
    );

    final preflight = await service.inspect(file);

    expect(preflight.packageKind, 'wasm');
    expect(preflight.pluginId, isNull);
    expect(preflight.capabilities, isEmpty);
  });

  test('rejects wasm package with invalid header', () async {
    final file = File('${tempDir.path}/invalid.wasm');
    await file.writeAsBytes(
      const <int>[0, 97, 115, 109, 0, 0, 0, 0],
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts valid zip package with manifest and wasm module', () async {
    final file = File('${tempDir.path}/valid.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'release_version': '0.1.0',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'contract': {'kind': 'temperature_tomorrow_liechtenstein'},
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
                'module_path': 'plugin/module.wasm',
              },
              'capabilities': [
                'oracle.read.mock_weather',
                'consensus_guard.read'
              ],
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    final preflight = await service.inspect(file);

    expect(preflight.packageKind, 'zip');
    expect(preflight.pluginId, 'hivra.contract.temperature-li.tomorrow.v1');
    expect(preflight.pluginVersion, '0.1.0');
    expect(preflight.contractKind, 'temperature_tomorrow_liechtenstein');
    expect(preflight.runtimeAbi, 'hivra_host_abi_v1');
    expect(preflight.runtimeEntryExport, 'hivra_entry_v1');
    expect(preflight.runtimeModulePath, 'plugin/module.wasm');
    expect(
      preflight.capabilities,
      ['consensus_guard.read', 'oracle.read.mock_weather'],
    );
  });

  test('rejects zip package when runtime module_path is missing', () async {
    final file = File('${tempDir.path}/missing_module_path_target.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
                'module_path': 'plugin/entry.wasm',
              },
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts runtime module_path containing dots inside segment', () async {
    final file = File('${tempDir.path}/module_path_with_dots.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
                'module_path': 'plugin/v1..2/module.wasm',
              },
            },
          ),
          'plugin/v1..2/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    final preflight = await service.inspect(file);
    expect(preflight.runtimeModulePath, 'plugin/v1..2/module.wasm');
  });

  test('rejects runtime module_path with parent traversal segment', () async {
    final file = File('${tempDir.path}/module_path_parent_traversal.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
                'module_path': 'plugin/../module.wasm',
              },
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip package when all wasm entries use parent traversal',
      () async {
    final file = File('${tempDir.path}/only_traversal_wasm.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
              },
            },
          ),
          '../evil.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts zip package when at least one safe wasm entry exists',
      () async {
    final file = File('${tempDir.path}/mixed_wasm_paths.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
                'module_path': 'plugin/module.wasm',
              },
            },
          ),
          '../evil.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    final preflight = await service.inspect(file);
    expect(preflight.packageKind, 'zip');
    expect(preflight.runtimeModulePath, 'plugin/module.wasm');
  });

  test('rejects non-list capabilities field in manifest', () async {
    final file = File('${tempDir.path}/bad_capabilities.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
              },
              'capabilities': 'not-a-list',
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unknown capability in manifest', () async {
    final file = File('${tempDir.path}/unknown_capability.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
              },
              'capabilities': ['oracle.read.untrusted_source'],
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip package without manifest', () async {
    final file = File('${tempDir.path}/missing_manifest.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip package without wasm module', () async {
    final file = File('${tempDir.path}/missing_wasm.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'hivra_host_abi_v1',
                'entry_export': 'hivra_entry_v1',
              },
            },
          ),
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip package without runtime section', () async {
    final file = File('${tempDir.path}/missing_runtime.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip package with unsupported runtime ABI', () async {
    final file = File('${tempDir.path}/bad_runtime_abi.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'runtime': {
                'abi': 'wrong_abi',
                'entry_export': 'hivra_entry_v1',
              },
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });
}

List<int> _zipBytes({required Map<String, Object> files}) {
  final archive = Archive();
  for (final entry in files.entries) {
    final content = entry.value;
    final bytes = switch (content) {
      List<int> _ => content,
      String _ => utf8.encode(content),
      _ => throw ArgumentError('Unsupported zip content type for ${entry.key}'),
    };
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('Failed to encode zip test archive');
  }
  return encoded;
}
