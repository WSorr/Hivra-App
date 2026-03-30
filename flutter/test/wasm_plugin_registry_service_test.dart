import 'dart:convert';
import 'dart:io';

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
    await sourceFile.writeAsBytes(const <int>[0, 97, 115, 109], flush: true);

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
}
