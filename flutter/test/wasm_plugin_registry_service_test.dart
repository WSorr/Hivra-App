import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';

class _TestUserVisibleDataDirectoryService
    extends UserVisibleDataDirectoryService {
  final Directory _root;

  const _TestUserVisibleDataDirectoryService(this._root);

  @override
  Future<Directory> rootDirectory({bool create = false}) async {
    if (create && !await _root.exists()) {
      await _root.create(recursive: true);
    }
    return _root;
  }

  @override
  Future<Directory> pluginsDirectory({bool create = false}) async {
    final dir = Directory('${_root.path}/Plugins');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDocsDir;
  late WasmPluginRegistryService service;

  setUp(() async {
    tempDocsDir =
        await Directory.systemTemp.createTemp('hivra_wasm_registry_test_');
    service = WasmPluginRegistryService(
      dataDirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('loadPlugins returns empty when registry is missing', () async {
    final records = await service.loadPlugins();
    expect(records, isEmpty);
  });

  test('loadPlugins ignores malformed entries and sorts by installedAt desc',
      () async {
    final pluginsDir = await service.pluginsDirectory(create: true);
    await File('${pluginsDir.path}/old.wasm').writeAsString('old', flush: true);
    await File('${pluginsDir.path}/new.wasm').writeAsString('new', flush: true);
    final registry = File('${pluginsDir.path}/registry.json');
    await registry.writeAsString(
      jsonEncode([
        {
          'id': 'old',
          'displayName': 'Old',
          'originalFileName': 'old.wasm',
          'storedFileName': 'old.wasm',
          'sizeBytes': 1,
          'installedAtIso': '2026-03-29T10:00:00Z',
        },
        'bad-entry',
        {
          'id': 'new',
          'displayName': 'New',
          'originalFileName': 'new.wasm',
          'storedFileName': 'new.wasm',
          'sizeBytes': 2,
          'installedAtIso': '2026-03-29T12:00:00Z',
        },
      ]),
      flush: true,
    );

    final records = await service.loadPlugins();

    expect(records.map((r) => r.id).toList(), ['new', 'old']);
  });

  test('install and remove plugin keeps registry and files in sync', () async {
    final sourceFile = File('${tempDocsDir.path}/demo_plugin.wasm');
    await sourceFile.writeAsBytes(
      const <int>[0, 97, 115, 109, 1, 0, 0, 0],
      flush: true,
    );

    final installed = await service.installPluginFromFile(sourceFile);
    expect(installed.originalFileName, 'demo_plugin.wasm');

    final pluginsDir = await service.pluginsDirectory();
    final storedFile = File('${pluginsDir.path}/${installed.storedFileName}');
    expect(await storedFile.exists(), isTrue);

    final loaded = await service.loadPlugins();
    expect(loaded.any((record) => record.id == installed.id), isTrue);

    await service.removePlugin(installed.id);
    expect(await storedFile.exists(), isFalse);
    expect(
      (await service.loadPlugins()).any((record) => record.id == installed.id),
      isFalse,
    );
  });

  test('stores manifest metadata for zip package install', () async {
    final sourceFile = File('${tempDocsDir.path}/demo_contract.zip');
    await sourceFile.writeAsBytes(
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
                'consensus_guard.read',
                'oracle.read.mock_weather'
              ],
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    final installed = await service.installPluginFromFile(sourceFile);

    expect(installed.packageKind, 'zip');
    expect(installed.pluginId, 'hivra.contract.temperature-li.tomorrow.v1');
    expect(installed.pluginVersion, '0.1.0');
    expect(installed.contractKind, 'temperature_tomorrow_liechtenstein');
    expect(installed.runtimeAbi, 'hivra_host_abi_v1');
    expect(installed.runtimeEntryExport, 'hivra_entry_v1');
    expect(installed.runtimeModulePath, 'plugin/module.wasm');
    expect(
      installed.capabilities,
      ['consensus_guard.read', 'oracle.read.mock_weather'],
    );

    final loaded = await service.loadPlugins();
    expect(loaded, isNotEmpty);
    expect(loaded.first.packageKind, 'zip');
    expect(loaded.first.pluginId, 'hivra.contract.temperature-li.tomorrow.v1');
  });

  test('reinstalls same plugin_id + version without creating duplicates',
      () async {
    Future<File> createPackage(String name) async {
      final sourceFile = File('${tempDocsDir.path}/$name');
      await sourceFile.writeAsBytes(
        _zipBytes(
          files: {
            'plugin/manifest.json': jsonEncode(
              {
                'schema': 'hivra.plugin.manifest',
                'version': 1,
                'release_version': '0.1.0',
                'plugin_id': 'hivra.contract.bingx-trading.v1',
                'contract': {'kind': 'bingx_spot_order_intent'},
                'runtime': {
                  'abi': 'hivra_host_abi_v1',
                  'entry_export': 'hivra_entry_v1',
                },
                'capabilities': [
                  'exchange.read.bingx.market',
                  'exchange.trade.bingx.spot'
                ],
              },
            ),
            'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
          },
        ),
        flush: true,
      );
      return sourceFile;
    }

    final first = await service.installPluginFromFile(
      await createPackage('bingx-a-0.1.0.zip'),
    );
    final pluginsDir = await service.pluginsDirectory();
    final firstStored = File('${pluginsDir.path}/${first.storedFileName}');
    expect(await firstStored.exists(), isTrue);

    final second = await service.installPluginFromFile(
      await createPackage('bingx-b-0.1.0.zip'),
    );
    final secondStored = File('${pluginsDir.path}/${second.storedFileName}');
    expect(await secondStored.exists(), isTrue);
    expect(await firstStored.exists(), isFalse);

    final records = await service.loadPlugins();
    final samePlugin = records
        .where((r) =>
            r.pluginId == 'hivra.contract.bingx-trading.v1' &&
            r.pluginVersion == '0.1.0')
        .toList();
    expect(samePlugin.length, 1);
    expect(samePlugin.first.id, second.id);
  });

  test('loadPlugins self-heals duplicate plugin_id + version records',
      () async {
    final pluginsDir = await service.pluginsDirectory(create: true);
    final staleFile = File('${pluginsDir.path}/stale.zip');
    final freshFile = File('${pluginsDir.path}/fresh.zip');
    await staleFile.writeAsString('stale', flush: true);
    await freshFile.writeAsString('fresh', flush: true);

    final registry = File('${pluginsDir.path}/registry.json');
    await registry.writeAsString(
      jsonEncode([
        {
          'id': 'fresh-id',
          'displayName': 'BingX',
          'originalFileName': 'bingx_spot_test_plugin-0.1.0.zip',
          'storedFileName': 'fresh.zip',
          'sizeBytes': 10,
          'installedAtIso': '2026-04-09T12:00:00Z',
          'packageKind': 'zip',
          'pluginId': 'hivra.contract.bingx-trading.v1',
          'pluginVersion': '0.1.0',
        },
        {
          'id': 'stale-id',
          'displayName': 'BingX',
          'originalFileName': 'bingx_spot_test_plugin-0.1.0.zip',
          'storedFileName': 'stale.zip',
          'sizeBytes': 11,
          'installedAtIso': '2026-04-09T11:00:00Z',
          'packageKind': 'zip',
          'pluginId': 'hivra.contract.bingx-trading.v1',
          'pluginVersion': '0.1.0',
        },
      ]),
      flush: true,
    );

    final records = await service.loadPlugins();
    expect(records.length, 1);
    expect(records.first.id, 'fresh-id');
    expect(await staleFile.exists(), isFalse);
    expect(await freshFile.exists(), isTrue);
  });

  test('loadPlugins prunes records with missing stored package files',
      () async {
    final pluginsDir = await service.pluginsDirectory(create: true);
    final presentFile = File('${pluginsDir.path}/present.zip');
    await presentFile.writeAsString('present', flush: true);

    final registry = File('${pluginsDir.path}/registry.json');
    await registry.writeAsString(
      jsonEncode([
        {
          'id': 'present-id',
          'displayName': 'Present',
          'originalFileName': 'present.zip',
          'storedFileName': 'present.zip',
          'sizeBytes': 10,
          'installedAtIso': '2026-04-10T12:00:00Z',
          'packageKind': 'zip',
          'pluginId': 'hivra.contract.temperature-li.tomorrow.v1',
          'pluginVersion': '0.1.0',
        },
        {
          'id': 'missing-id',
          'displayName': 'Missing',
          'originalFileName': 'missing.zip',
          'storedFileName': 'missing.zip',
          'sizeBytes': 10,
          'installedAtIso': '2026-04-10T11:00:00Z',
          'packageKind': 'zip',
          'pluginId': 'hivra.contract.capsule-chat.v1',
          'pluginVersion': '0.1.0',
        },
      ]),
      flush: true,
    );

    final loaded = await service.loadPlugins();
    expect(loaded.length, 1);
    expect(loaded.first.id, 'present-id');

    final repairedRegistry =
        jsonDecode(await registry.readAsString()) as List<dynamic>;
    expect(repairedRegistry.length, 1);
    expect(
      (repairedRegistry.first as Map<String, dynamic>)['id'],
      'present-id',
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
