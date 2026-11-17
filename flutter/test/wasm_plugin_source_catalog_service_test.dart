import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_source_catalog_service.dart';

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
  late Directory tempDocsDir;
  late _TestUserVisibleDataDirectoryService dataDirs;
  late HttpServer server;
  late WasmPluginRegistryService registry;
  late WasmPluginSourceCatalogService service;
  late SimpleKeyPair catalogSigningKey;
  late String catalogPublicKeyHex;
  late List<int> downloadBytes;
  List<String>? catalogCacheControl;
  List<String>? catalogPragma;

  final packageBytes = _zipBytes(
    files: {
      'plugin/manifest.json': jsonEncode({
        'schema': 'hivra.plugin.manifest',
        'version': 1,
        'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
        'contract': {'kind': 'plugin_workspace_v1'},
        'runtime': {
          'abi': 'hivra_host_abi_v2',
          'entry_export': 'hivra_evaluate_v1',
        },
        'capabilities': ['consensus_guard.read'],
      }),
      'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
    },
  );
  final packageSha256Hex = sha256.convert(packageBytes).toString();
  final mismatchPluginPackageBytes = _zipBytes(
    files: {
      'plugin/manifest.json': jsonEncode({
        'schema': 'hivra.plugin.manifest',
        'version': 1,
        'plugin_id': 'hivra.contract.capsule-chat.v1',
        'contract': {'kind': 'capsule_chat'},
        'runtime': {
          'abi': 'hivra_host_abi_v2',
          'entry_export': 'hivra_evaluate_v1',
        },
        'capabilities': ['workspace.render', 'workspace.continue'],
      }),
      'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
    },
  );

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp('hivra_source_cat_');
    dataDirs = _TestUserVisibleDataDirectoryService(tempDocsDir);
    registry = WasmPluginRegistryService(dataDirs: dataDirs);
    catalogSigningKey = await Ed25519().newKeyPair();
    catalogPublicKeyHex = _hexEncode(
      (await catalogSigningKey.extractPublicKey()).bytes,
    );
    catalogCacheControl = null;
    catalogPragma = null;
    downloadBytes = packageBytes;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final downloadUrl =
        'http://127.0.0.1:${server.port}/packages/demo-plugin.zip';
    final remoteCatalogBody = _catalogJson(
      sourceId: 'wsorr.hivra.plugins',
      sourceName: 'Hivra Plugins',
      entries: [
        {
          'id': 'moltbook-catalog',
          'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
          'display_name': 'Moltbook Ambassador',
          'version': '0.1.0',
          'download_url': downloadUrl,
          'package_kind': 'zip',
          'sha256_hex': packageSha256Hex,
        },
      ],
    );
    service = WasmPluginSourceCatalogService(
      registry: registry,
      dataDirs: dataDirs,
      trustedRemoteCatalogSha256Hexes: {
        sha256.convert(utf8.encode(remoteCatalogBody)).toString(),
      },
    );

    server.listen((request) async {
      if (request.uri.path == '/catalog.json') {
        catalogCacheControl = request.headers[HttpHeaders.cacheControlHeader];
        catalogPragma = request.headers['pragma'];
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(remoteCatalogBody);
        await request.response.close();
        return;
      }
      if (request.uri.path == '/packages/demo-plugin.zip') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..add(downloadBytes);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('fetchCatalog parses valid remote catalog', () async {
    final url = 'http://127.0.0.1:${server.port}/catalog.json';
    final catalog = await service.fetchCatalog(catalogUrl: url);

    expect(catalog.sourceId, 'wsorr.hivra.plugins');
    expect(catalog.sourceName, 'Hivra Plugins');
    expect(catalog.entries.length, 1);
    expect(
      catalog.entries.first.pluginId,
      'hivra.contract.moltbook-ambassador.v1',
    );
    expect(catalogCacheControl, contains('no-cache'));
    expect(catalogPragma, contains('no-cache'));
  });

  test('raw source entries never download or enter installation', () async {
    var downloads = 0;
    var installs = 0;
    final bounded = WasmPluginSourceCatalogService(
      registry: registry,
      dataDirs: dataDirs,
      httpClientFactory: () {
        downloads++;
        throw StateError('Unexpected download');
      },
    );
    for (final url in [
      'https://example.com/module.wasm',
      File('${tempDocsDir.path}/module.wasm').uri.toString(),
    ]) {
      await expectLater(
        bounded.installFromSourceEntry(
          WasmPluginSourceCatalogEntry(
            id: 'raw',
            pluginId: 'hivra.contract.raw.v1',
            displayName: 'Raw',
            version: '0.1.0',
            downloadUrl: url,
            packageKind: 'wasm',
            sha256Hex: null,
          ),
          beforeInstall: (_) async {
            installs++;
          },
        ),
        throwsA(isA<FormatException>()),
      );
    }
    expect(downloads, 0);
    expect(installs, 0);
    expect(await registry.loadPlugins(), isEmpty);
  });

  test('catalog omits raw modules while retaining ZIP packages', () async {
    final path = '${tempDocsDir.path}/mixed-catalog.json';
    await File(path).writeAsString(
      _catalogJson(
        sourceId: 'local.plugins',
        sourceName: 'Local plugins',
        entries: [
          for (final kind in ['zip', 'wasm'])
            {
              'id': kind,
              'plugin_id': 'hivra.contract.$kind.v1',
              'display_name': kind,
              'version': '0.1.0',
              'download_url': 'https://example.com/plugin.$kind',
              'package_kind': kind,
              'sha256_hex': packageSha256Hex,
            },
        ],
      ),
    );
    final catalog = await service.fetchCatalog(catalogUrl: path);
    expect(catalog.entries.map((entry) => entry.packageKind), ['zip']);
  });

  test(
    'fetchCatalog rejects remote catalog when digest is not pinned',
    () async {
      final untrustedService = WasmPluginSourceCatalogService(
        registry: registry,
        dataDirs: dataDirs,
        trustedRemoteCatalogSha256Hexes: const {
          '0000000000000000000000000000000000000000000000000000000000000000',
        },
      );
      final url = 'http://127.0.0.1:${server.port}/catalog.json';

      await expectLater(
        () => untrustedService.fetchCatalog(catalogUrl: url),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'fetchCatalog rejects remote catalog without any trusted digest pin',
    () async {
      final unpinnedService = WasmPluginSourceCatalogService(
        registry: registry,
        dataDirs: dataDirs,
        trustedRemoteCatalogSha256Hexes: const {},
      );
      final url = 'http://127.0.0.1:${server.port}/catalog.json';

      await expectLater(
        () => unpinnedService.fetchCatalog(catalogUrl: url),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'fetchCatalog accepts remote catalog signed by pinned public key',
    () async {
      final downloadUrl =
          'http://127.0.0.1:${server.port}/packages/demo-plugin.zip';
      final unsignedCatalog = _catalogMap(
        sourceId: 'wsorr.hivra.plugins',
        sourceName: 'Hivra Plugins',
        entries: [
          {
            'id': 'moltbook-catalog',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Moltbook Ambassador',
            'version': '0.1.0',
            'download_url': downloadUrl,
            'package_kind': 'zip',
            'sha256_hex': packageSha256Hex,
          },
        ],
      );
      final signedBody = await _signedCatalogJson(
        unsignedCatalog,
        signingKey: catalogSigningKey,
      );
      final signedCatalogPath = '${tempDocsDir.path}/signed_catalog.json';
      File(signedCatalogPath).writeAsStringSync(signedBody, flush: true);
      final signedServerPath = '/signed_catalog.json';

      final signedServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      signedServer.listen((request) async {
        if (request.uri.path == signedServerPath) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(signedBody);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(() => signedServer.close(force: true));

      final signedService = WasmPluginSourceCatalogService(
        registry: registry,
        dataDirs: dataDirs,
        trustedRemoteCatalogSha256Hexes: const {},
        trustedRemoteCatalogPublicKeyHexes: {catalogPublicKeyHex},
      );

      final catalog = await signedService.fetchCatalog(
        catalogUrl: 'http://127.0.0.1:${signedServer.port}$signedServerPath',
      );

      expect(catalog.sourceId, 'wsorr.hivra.plugins');
      expect(catalog.entries.single.id, 'moltbook-catalog');
    },
  );

  test(
    'fetchCatalog rejects signed remote catalog with untrusted public key',
    () async {
      final unsignedCatalog = _catalogMap(
        sourceId: 'wsorr.hivra.plugins',
        sourceName: 'Hivra Plugins',
        entries: [
          {
            'id': 'moltbook-catalog',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Moltbook Ambassador',
            'version': '0.1.0',
            'download_url':
                'http://127.0.0.1:${server.port}/packages/demo-plugin.zip',
            'package_kind': 'zip',
            'sha256_hex': packageSha256Hex,
          },
        ],
      );
      final signedBody = await _signedCatalogJson(
        unsignedCatalog,
        signingKey: catalogSigningKey,
      );
      final signedServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      signedServer.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(signedBody);
        await request.response.close();
      });
      addTearDown(() => signedServer.close(force: true));

      final otherPublicKey = _hexEncode(
        (await (await Ed25519().newKeyPair()).extractPublicKey()).bytes,
      );
      final untrustedService = WasmPluginSourceCatalogService(
        registry: registry,
        dataDirs: dataDirs,
        trustedRemoteCatalogSha256Hexes: const {},
        trustedRemoteCatalogPublicKeyHexes: {otherPublicKey},
      );

      await expectLater(
        () => untrustedService.fetchCatalog(
          catalogUrl: 'http://127.0.0.1:${signedServer.port}/catalog.json',
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'installFromSourceEntry downloads and installs plugin package',
    () async {
      final url = 'http://127.0.0.1:${server.port}/catalog.json';
      final catalog = await service.fetchCatalog(catalogUrl: url);

      final record = await service.installFromSourceEntry(
        catalog.entries.first,
      );

      expect(record.packageKind, 'zip');
      expect(record.pluginId, 'hivra.contract.moltbook-ambassador.v1');
      expect(record.contractKind, 'plugin_workspace_v1');
    },
  );

  test('supports local file catalog and file package URLs', () async {
    final sourceDir = Directory('${tempDocsDir.path}/source')..createSync();
    final packagePath = '${sourceDir.path}/local-plugin.zip';
    File(packagePath).writeAsBytesSync(packageBytes, flush: true);

    final catalogPath = '${tempDocsDir.path}/plugin_catalog.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode({
        'schema': 'hivra.plugin.catalog',
        'version': 1,
        'source_id': 'local.hivra.plugins',
        'source_name': 'Local Hivra Plugins',
        'entries': [
          {
            'id': 'moltbook-local',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Moltbook Local',
            'version': '0.1.0',
            'download_url': File(packagePath).uri.toString(),
            'package_kind': 'zip',
            'sha256_hex': packageSha256Hex,
          },
        ],
      }),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);

    final record = await service.installFromSourceEntry(catalog.entries.first);
    expect(record.pluginId, 'hivra.contract.moltbook-ambassador.v1');
  });

  test(
    'fetchCatalogWithFallback loads local catalog when remote fails',
    () async {
      final sourceDir = Directory('${tempDocsDir.path}/source')..createSync();
      final packagePath = '${sourceDir.path}/local-fallback.zip';
      File(packagePath).writeAsBytesSync(packageBytes, flush: true);

      final localCatalogPath =
          '${tempDocsDir.path}/plugin_catalog_fallback.json';
      File(localCatalogPath).writeAsStringSync(
        jsonEncode({
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'fallback-local',
              'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
              'display_name': 'Moltbook Local Fallback',
              'version': '0.1.0',
              'download_url': File(packagePath).uri.toString(),
              'package_kind': 'zip',
              'sha256_hex': packageSha256Hex,
            },
          ],
        }),
        flush: true,
      );

      final catalog = await service.fetchCatalogWithFallback(
        primaryCatalogUrl: 'http://127.0.0.1:1/not-available.json',
        secondaryCatalogUrl: 'http://127.0.0.1:1/not-available-secondary.json',
        localCatalogPathOverride: localCatalogPath,
      );

      expect(catalog.sourceId, 'local.hivra.plugins');
      expect(catalog.entries.length, 1);
    },
  );

  test(
    'fetchCatalogWithFallback prefers existing local catalog over remote',
    () async {
      final sourceDir = Directory('${tempDocsDir.path}/Plugins/source')
        ..createSync(recursive: true);
      final packagePath = '${sourceDir.path}/local-first.zip';
      File(packagePath).writeAsBytesSync(packageBytes, flush: true);

      final localCatalogPath =
          '${tempDocsDir.path}/Plugins/plugin_catalog.json';
      File(localCatalogPath).writeAsStringSync(
        jsonEncode({
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'local-first',
              'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
              'display_name': 'Moltbook Local First',
              'version': '0.2.2',
              'download_url': File(packagePath).uri.toString(),
              'package_kind': 'zip',
              'sha256_hex': packageSha256Hex,
            },
          ],
        }),
        flush: true,
      );

      final remoteUrl = 'http://127.0.0.1:${server.port}/catalog.json';
      final catalog = await service.fetchCatalogWithFallback(
        primaryCatalogUrl: remoteUrl,
        secondaryCatalogUrl: remoteUrl,
      );

      expect(catalog.sourceId, 'local.hivra.plugins');
      expect(catalog.entries.single.id, 'local-first');
      expect(catalog.entries.single.version, '0.2.2');
    },
  );

  test(
    'missing local catalog does not hide the remote network failure',
    () async {
      var attempts = 0;
      final offline = WasmPluginSourceCatalogService(
        dataDirs: dataDirs,
        httpClientFactory: () {
          attempts++;
          throw const SocketException('Network unavailable');
        },
      );

      await expectLater(
        offline.fetchCatalogWithFallback(),
        throwsA(isA<SocketException>()),
      );
      expect(attempts, 2);
      expect(
        File('${tempDocsDir.path}/Plugins/plugin_catalog.json').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'malformed local catalog does not hide the final remote HTTP error',
    () async {
      final path = '${tempDocsDir.path}/bad_catalog.json';
      File(path).writeAsStringSync('invalid json');
      final secondary = Uri.parse(
        'http://127.0.0.1:${server.port}/missing.json',
      );

      await expectLater(
        service.fetchCatalogWithFallback(
          primaryCatalogUrl:
              'http://127.0.0.1:${server.port}/also-missing.json',
          secondaryCatalogUrl: secondary.toString(),
          localCatalogPathOverride: path,
        ),
        throwsA(
          isA<HttpException>().having((e) => e.uri, 'failed source', secondary),
        ),
      );
      expect(File(path).readAsStringSync(), 'invalid json');
    },
  );

  test('secondary remote catalog is still verified before use', () async {
    final url = 'http://127.0.0.1:${server.port}/catalog.json';
    final catalog = await service.fetchCatalogWithFallback(
      primaryCatalogUrl: 'http://127.0.0.1:${server.port}/missing.json',
      secondaryCatalogUrl: url,
    );
    expect(catalog.sourceId, 'wsorr.hivra.plugins');

    final untrusted = WasmPluginSourceCatalogService(
      dataDirs: dataDirs,
      trustedRemoteCatalogPublicKeyHexes: const {},
      trustedRemoteCatalogSha256Hexes: const {},
    );
    await expectLater(
      untrusted.fetchCatalogWithFallback(
        primaryCatalogUrl: url,
        secondaryCatalogUrl: url,
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'trust failure',
          contains('trusted digest'),
        ),
      ),
    );
  });

  test('installFromSourceEntry fails when sha256 mismatches', () async {
    final sourceDir = Directory('${tempDocsDir.path}/source')..createSync();
    final packagePath = '${sourceDir.path}/bad-hash-plugin.zip';
    File(packagePath).writeAsBytesSync(packageBytes, flush: true);

    final entry = WasmPluginSourceCatalogEntry(
      id: 'bad-hash',
      pluginId: 'hivra.contract.moltbook-ambassador.v1',
      displayName: 'Bad Hash',
      version: '0.1.0',
      downloadUrl: File(packagePath).uri.toString(),
      packageKind: 'zip',
      sha256Hex:
          '0000000000000000000000000000000000000000000000000000000000000000',
    );

    await expectLater(
      () => service.installFromSourceEntry(entry),
      throwsA(isA<FormatException>()),
    );
  });

  for (final tamperTail in [false, true]) {
    test(
      'checksum covers a complete large package (tampered tail: $tamperTail)',
      () async {
        final archive = ZipDecoder().decodeBytes(packageBytes);
        final random = Random(7);
        final payload = List<int>.generate(
          192 * 1024,
          (_) => random.nextInt(256),
        );
        archive.addFile(
          ArchiveFile('plugin/payload.bin', payload.length, payload),
        );
        final candidate = ZipEncoder().encode(archive)!;
        expect(candidate.length, greaterThan(128 * 1024));
        final expected = sha256.convert(candidate).toString();
        final input = List<int>.of(candidate);
        if (tamperTail) input[input.length - 1] ^= 1;
        final source = File('${tempDocsDir.path}/candidate-0.1.0.zip');
        await source.writeAsBytes(input, flush: true);
        final activeFile = File('${tempDocsDir.path}/active.zip');
        await activeFile.writeAsBytes(packageBytes, flush: true);
        final active = await registry.installPluginFromFile(activeFile);
        var retirements = 0;
        final installing = service.installFromSourceEntry(
          WasmPluginSourceCatalogEntry(
            id: 'large',
            pluginId: active.pluginId!,
            displayName: 'Large package',
            version: '0.1.0',
            downloadUrl: source.uri.toString(),
            packageKind: 'zip',
            sha256Hex: expected,
          ),
          beforeInstall: (_) async {
            retirements++;
          },
        );
        if (tamperTail) {
          await expectLater(installing, throwsA(isA<FormatException>()));
          expect(retirements, 0);
          expect((await registry.loadPlugins()).single.id, active.id);
        } else {
          final replacement = await installing;
          expect(retirements, 1);
          expect(replacement.id, isNot(active.id));
          expect(replacement.pluginVersion, '0.1.0');
          final plugins = await registry.pluginsDirectory();
          expect(
            await File(
              '${plugins.path}/${replacement.storedFileName}',
            ).readAsBytes(),
            candidate,
          );
        }
      },
    );
  }

  test('fetchCatalog rejects invalid sha256_hex shape', () async {
    final badCatalogPath = '${tempDocsDir.path}/plugin_catalog_bad_sha.json';
    File(badCatalogPath).writeAsStringSync(
      jsonEncode({
        'schema': 'hivra.plugin.catalog',
        'version': 1,
        'source_id': 'local.hivra.plugins',
        'source_name': 'Local Hivra Plugins',
        'entries': [
          {
            'id': 'bad-sha-shape',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Bad SHA Shape',
            'version': '0.1.0',
            'download_url': 'file:///tmp/any.zip',
            'package_kind': 'zip',
            'sha256_hex': 'not-a-sha',
          },
        ],
      }),
      flush: true,
    );

    await expectLater(
      () => service.fetchCatalog(catalogUrl: badCatalogPath),
      throwsA(isA<FormatException>()),
    );
  });

  test('fetchCatalog version 2 requires sha256_hex', () async {
    final catalogPath = '${tempDocsDir.path}/plugin_catalog_v2_no_sha.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode({
        'schema': 'hivra.plugin.catalog',
        'version': 2,
        'source_id': 'local.hivra.plugins',
        'source_name': 'Local Hivra Plugins',
        'entries': [
          {
            'id': 'missing-sha',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Missing SHA',
            'version': '0.1.0',
            'download_url': 'https://example.com/plugin.zip',
            'package_kind': 'zip',
          },
        ],
      }),
      flush: true,
    );

    await expectLater(
      () => service.fetchCatalog(catalogUrl: catalogPath),
      throwsA(isA<FormatException>()),
    );
  });

  test('fetchCatalog filters unsupported download_url schemes', () async {
    final catalogPath =
        '${tempDocsDir.path}/plugin_catalog_bad_url_scheme.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode({
        'schema': 'hivra.plugin.catalog',
        'version': 1,
        'source_id': 'local.hivra.plugins',
        'source_name': 'Local Hivra Plugins',
        'entries': [
          {
            'id': 'valid-http',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Valid HTTP',
            'version': '0.1.0',
            'download_url': 'https://example.com/plugin.zip',
            'package_kind': 'zip',
          },
          {
            'id': 'bad-ftp',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Bad FTP',
            'version': '0.1.0',
            'download_url': 'ftp://example.com/plugin.zip',
            'package_kind': 'zip',
          },
        ],
      }),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.id, 'valid-http');
  });

  test('fetchCatalog deduplicates entries by id preserving first', () async {
    final catalogPath = '${tempDocsDir.path}/plugin_catalog_dup_id.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode({
        'schema': 'hivra.plugin.catalog',
        'version': 1,
        'source_id': 'local.hivra.plugins',
        'source_name': 'Local Hivra Plugins',
        'entries': [
          {
            'id': 'dup-id',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'First',
            'version': '0.1.0',
            'download_url': 'https://example.com/first.zip',
            'package_kind': 'zip',
          },
          {
            'id': 'dup-id',
            'plugin_id': 'hivra.contract.capsule-chat.v1',
            'display_name': 'Second',
            'version': '0.2.0',
            'download_url': 'https://example.com/second.zip',
            'package_kind': 'zip',
          },
        ],
      }),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.displayName, 'First');
    expect(catalog.entries.first.version, '0.1.0');
  });

  test('fetchCatalog filters entries with invalid plugin_id shape', () async {
    final catalogPath = '${tempDocsDir.path}/plugin_catalog_bad_plugin_id.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode({
        'schema': 'hivra.plugin.catalog',
        'version': 1,
        'source_id': 'local.hivra.plugins',
        'source_name': 'Local Hivra Plugins',
        'entries': [
          {
            'id': 'valid-id-shape',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Valid Plugin Id',
            'version': '0.1.0',
            'download_url': 'https://example.com/valid.zip',
            'package_kind': 'zip',
          },
          {
            'id': 'bad-id-shape',
            'plugin_id': 'moltbook-ambassador',
            'display_name': 'Bad Plugin Id',
            'version': '0.1.0',
            'download_url': 'https://example.com/bad.zip',
            'package_kind': 'zip',
          },
        ],
      }),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.id, 'valid-id-shape');
  });

  test('fetchCatalog filters entries with invalid version shape', () async {
    final catalogPath = '${tempDocsDir.path}/plugin_catalog_bad_version.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode({
        'schema': 'hivra.plugin.catalog',
        'version': 1,
        'source_id': 'local.hivra.plugins',
        'source_name': 'Local Hivra Plugins',
        'entries': [
          {
            'id': 'valid-version-shape',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Valid Version',
            'version': '0.1.0',
            'download_url': 'https://example.com/valid.zip',
            'package_kind': 'zip',
          },
          {
            'id': 'bad-version-shape',
            'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
            'display_name': 'Bad Version',
            'version': 'v0.1',
            'download_url': 'https://example.com/bad.zip',
            'package_kind': 'zip',
          },
        ],
      }),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.id, 'valid-version-shape');
  });

  test(
    'fetchCatalog deduplicates entries by plugin_id + version + package_kind',
    () async {
      final catalogPath =
          '${tempDocsDir.path}/plugin_catalog_dup_plugin_ver.json';
      File(catalogPath).writeAsStringSync(
        jsonEncode({
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'entry-a',
              'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
              'display_name': 'First',
              'version': '0.1.0',
              'download_url': 'https://example.com/first.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'entry-b',
              'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
              'display_name': 'Second same plugin/version',
              'version': '0.1.0',
              'download_url': 'https://example.com/second.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'entry-c',
              'plugin_id': 'hivra.contract.moltbook-ambassador.v1',
              'display_name': 'Different version',
              'version': '0.2.0',
              'download_url': 'https://example.com/third.zip',
              'package_kind': 'zip',
            },
          ],
        }),
        flush: true,
      );

      final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
      expect(catalog.entries.length, 2);
      expect(catalog.entries[0].id, 'entry-a');
      expect(catalog.entries[1].id, 'entry-c');
    },
  );

  for (final remote in [false, true]) {
    for (final fault in [
      'archive',
      'plugin',
      'version',
      if (!remote) 'filename',
    ]) {
      test('rejected source keeps execution untouched ($remote, $fault)', () async {
        final activePackage = File('${tempDocsDir.path}/active.zip');
        await activePackage.writeAsBytes(packageBytes, flush: true);
        final active = await registry.installPluginFromFile(activePackage);
        final pluginsDir = await registry.pluginsDirectory();
        final registryFile = File('${pluginsDir.path}/registry.json');
        final before = await registryFile.readAsString();
        final candidate =
            fault == 'filename'
                ? packageBytes
                : fault == 'plugin'
                ? mismatchPluginPackageBytes
                : _zipBytes(
                  files: {
                    if (fault != 'archive')
                      'plugin/manifest.json': jsonEncode({
                        'schema': 'hivra.plugin.manifest',
                        'version': 1,
                        'release_version': '0.2.0',
                        'plugin_id': active.pluginId,
                        'contract': {'kind': 'plugin_workspace_v1'},
                        'runtime': {
                          'abi': 'hivra_host_abi_v2',
                          'entry_export': 'hivra_evaluate_v1',
                        },
                        'capabilities': [
                          'workspace.render',
                          'workspace.continue',
                        ],
                      }),
                    'plugin/module.wasm': const <int>[
                      0,
                      97,
                      115,
                      109,
                      1,
                      0,
                      0,
                      0,
                    ],
                  },
                );
        downloadBytes = candidate;
        final source = File(
          '${tempDocsDir.path}/candidate${fault == 'filename' ? '-0.2.0' : ''}.zip',
        );
        await source.writeAsBytes(candidate, flush: true);
        var retirements = 0;
        await expectLater(
          service.installFromSourceEntry(
            WasmPluginSourceCatalogEntry(
              id: 'candidate',
              pluginId: active.pluginId!,
              displayName: 'Candidate',
              version: '0.1.0',
              downloadUrl:
                  remote
                      ? 'http://127.0.0.1:${server.port}/packages/demo-plugin.zip'
                      : source.uri.toString(),
              packageKind: 'zip',
              sha256Hex: sha256.convert(candidate).toString(),
            ),
            beforeInstall: (_) async {
              retirements++;
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(retirements, 0);
        expect(await registryFile.readAsString(), before);
        expect((await registry.loadPlugins()).single.id, active.id);
        expect(
          await File(
            '${pluginsDir.path}/${active.storedFileName}',
          ).readAsBytes(),
          packageBytes,
        );
      });
    }
  }

  for (final remote in [false, true]) {
    test(
      'failed retirement preserves the package and permits retry ($remote)',
      () async {
        final source = File('${tempDocsDir.path}/candidate.zip');
        await source.writeAsBytes(packageBytes, flush: true);
        final active = await registry.installPluginFromFile(source);
        final entry = WasmPluginSourceCatalogEntry(
          id: 'candidate',
          pluginId: active.pluginId!,
          displayName: 'Candidate',
          version: '0.1.0',
          downloadUrl:
              remote
                  ? 'http://127.0.0.1:${server.port}/packages/demo-plugin.zip'
                  : source.uri.toString(),
          packageKind: 'zip',
          sha256Hex: packageSha256Hex,
        );
        await expectLater(
          service.installFromSourceEntry(
            entry,
            beforeInstall: (_) async {
              expect((await registry.loadPlugins()).single.id, active.id);
              throw StateError('Previous executor is unavailable');
            },
          ),
          throwsStateError,
        );
        final reopened = WasmPluginRegistryService(dataDirs: dataDirs);
        expect((await reopened.loadPlugins()).single.id, active.id);
        var retirements = 0;
        final replacement = await WasmPluginSourceCatalogService(
          registry: reopened,
          dataDirs: dataDirs,
        ).installFromSourceEntry(
          entry,
          beforeInstall: (pluginId) async {
            expect(pluginId, active.pluginId);
            expect((await reopened.loadPlugins()).single.id, active.id);
            retirements++;
          },
        );
        expect(retirements, 1);
        expect((await reopened.loadPlugins()).single.id, replacement.id);
        expect(replacement.id, isNot(active.id));
      },
    );
  }

  test(
    'source changes during retirement cannot replace the verified candidate',
    () async {
      final source = File('${tempDocsDir.path}/candidate.zip');
      await source.writeAsBytes(packageBytes, flush: true);
      var retirements = 0;
      final installed = await service.installFromSourceEntry(
        WasmPluginSourceCatalogEntry(
          id: 'candidate',
          pluginId: 'hivra.contract.moltbook-ambassador.v1',
          displayName: 'Candidate',
          version: '0.1.0',
          downloadUrl: source.uri.toString(),
          packageKind: 'zip',
          sha256Hex: packageSha256Hex,
        ),
        beforeInstall: (_) async {
          retirements++;
          await source.writeAsBytes(mismatchPluginPackageBytes, flush: true);
        },
      );
      expect(retirements, 1);
      expect(installed.pluginId, 'hivra.contract.moltbook-ambassador.v1');
      final pluginsDir = await registry.pluginsDirectory();
      expect(
        await File(
          '${pluginsDir.path}/${installed.storedFileName}',
        ).readAsBytes(),
        packageBytes,
      );
    },
  );
}

String _catalogJson({
  required String sourceId,
  required String sourceName,
  required List<Map<String, Object?>> entries,
  int version = 1,
}) {
  return jsonEncode(
    _catalogMap(
      sourceId: sourceId,
      sourceName: sourceName,
      entries: entries,
      version: version,
    ),
  );
}

Map<String, Object?> _catalogMap({
  required String sourceId,
  required String sourceName,
  required List<Map<String, Object?>> entries,
  int version = 1,
}) {
  return {
    'schema': 'hivra.plugin.catalog',
    'version': version,
    'source_id': sourceId,
    'source_name': sourceName,
    'entries': entries,
  };
}

Future<String> _signedCatalogJson(
  Map<String, Object?> unsignedCatalog, {
  required SimpleKeyPair signingKey,
}) async {
  final publicKey = await signingKey.extractPublicKey();
  final payload = utf8.encode(_canonicalJson(unsignedCatalog));
  final signature = await Ed25519().sign(payload, keyPair: signingKey);
  final signedCatalog = Map<String, Object?>.from(unsignedCatalog);
  signedCatalog['signatures'] = [
    {
      'algorithm': 'ed25519',
      'key_id': sha256.convert(publicKey.bytes).toString(),
      'signature_hex': _hexEncode(signature.bytes),
    },
  ];
  return jsonEncode(signedCatalog);
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) {
      return '${jsonEncode(key)}:${_canonicalJson(value[key])}';
    }).join(',')}}';
  }
  if (value is List) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}

String _hexEncode(List<int> bytes) {
  const chars = '0123456789abcdef';
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(chars[(byte >> 4) & 0x0f])
      ..write(chars[byte & 0x0f]);
  }
  return buffer.toString();
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
