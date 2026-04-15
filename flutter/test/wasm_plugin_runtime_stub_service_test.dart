import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/wasm_plugin_runtime_stub_service.dart';

void main() {
  group('WasmPluginRuntimeStubService', () {
    const service = WasmPluginRuntimeStubService();

    test('returns null for host fallback binding', () async {
      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
          method: 'settle_temperature_tomorrow',
          args: <String, dynamic>{'a': 1},
        ),
        binding: const PluginRuntimeBinding.hostFallback(),
      );

      expect(evidence, isNull);
    });

    test('produces deterministic invoke digest for wasm package', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(),
        flush: true,
      );

      final binding = PluginRuntimeBinding.externalPackage(
        packageId: 'pkg-1',
        packageVersion: '1.0.0',
        packageKind: 'wasm',
        packageFilePath: wasmPath,
        runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
        runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
        contractKind: 'temperature_tomorrow_liechtenstein',
      );
      final requestA = const PluginHostApiRequest(
        schemaVersion: 1,
        pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
        method: 'settle_temperature_tomorrow',
        args: <String, dynamic>{
          'b': 2,
          'a': <String, dynamic>{'y': 2, 'x': 1},
        },
      );
      final requestB = const PluginHostApiRequest(
        schemaVersion: 1,
        pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
        method: 'settle_temperature_tomorrow',
        args: <String, dynamic>{
          'a': <String, dynamic>{'x': 1, 'y': 2},
          'b': 2,
        },
      );

      final first = await service.invoke(request: requestA, binding: binding);
      final second = await service.invoke(request: requestB, binding: binding);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.mode, WasmPluginRuntimeStubService.runtimeMode);
      expect(first.modulePath, 'package/module.wasm');
      expect(first.moduleSelection, 'package_wasm');
      expect(first.moduleDigestHex.length, 64);
      expect(first.invokeDigestHex.length, 64);
      expect(first.invokeDigestHex, second!.invokeDigestHex);
    });

    test('changes invoke digest when request args change', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(),
        flush: true,
      );

      final binding = PluginRuntimeBinding.externalPackage(
        packageId: 'pkg-2',
        packageVersion: '1.0.0',
        packageKind: 'wasm',
        packageFilePath: wasmPath,
        runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
        runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
        contractKind: 'capsule_chat',
      );
      final first = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.capsule-chat.v1',
          method: 'post_capsule_chat_message',
          args: <String, dynamic>{'message_text': 'hello'},
        ),
        binding: binding,
      );
      final second = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.capsule-chat.v1',
          method: 'post_capsule_chat_message',
          args: <String, dynamic>{'message_text': 'world'},
        ),
        binding: binding,
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.invokeDigestHex, isNot(equals(second!.invokeDigestHex)));
    });

    test('rejects external package when package digest mismatches', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-bad-digest',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            packageDigestHex:
                '0000000000000000000000000000000000000000000000000000000000000000',
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Plugin package digest mismatch',
          ),
        ),
      );
    });

    test('rejects external package when package digest shape is invalid',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-bad-shape',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            packageDigestHex: 'not-a-sha',
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Plugin package digest shape is invalid',
          ),
        ),
      );
    });

    test('reads module bytes from zip package', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin/manifest.json',
          2,
          utf8.encode('{}'),
        ))
        ..addFile(ArchiveFile(
          'plugin/alpha.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ))
        ..addFile(ArchiveFile(
          'plugin/module.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ));
      final encoded = ZipEncoder().encode(archive)!;
      final zipPath = '${tempDir.path}/demo.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);
      final selectedModule = _minimalWasmModule();
      final expectedDigest = sha256.convert(selectedModule).toString();

      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.bingx-trading.v1',
          method: 'place_bingx_spot_order_intent',
          args: <String, dynamic>{'symbol': 'BTC-USDT'},
        ),
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-zip',
          packageVersion: '1.0.0',
          packageKind: 'zip',
          packageFilePath: zipPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          runtimeModulePath: 'plugin/module.wasm',
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(evidence, isNotNull);
      expect(evidence!.mode, WasmPluginRuntimeStubService.runtimeMode);
      expect(evidence.modulePath, 'plugin/module.wasm');
      expect(evidence.moduleSelection, 'manifest_module_path');
      expect(evidence.moduleDigestHex.length, 64);
      expect(evidence.moduleDigestHex, expectedDigest);
    });

    test('selects first wasm module path when runtime module_path is absent',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin/manifest.json',
          2,
          utf8.encode('{}'),
        ))
        ..addFile(ArchiveFile(
          'plugin/zeta.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ))
        ..addFile(ArchiveFile(
          'plugin/alpha.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ));
      final encoded = ZipEncoder().encode(archive)!;
      final zipPath = '${tempDir.path}/demo.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);

      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.bingx-trading.v1',
          method: 'place_bingx_spot_order_intent',
          args: <String, dynamic>{'symbol': 'BTC-USDT'},
        ),
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-zip-default',
          packageVersion: '1.0.0',
          packageKind: 'zip',
          packageFilePath: zipPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(evidence, isNotNull);
      expect(evidence!.modulePath, 'plugin/alpha.wasm');
      expect(evidence.moduleSelection, 'lexical_first_wasm');
    });

    test('ignores zip wasm entries with parent traversal segments', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin/manifest.json',
          2,
          utf8.encode('{}'),
        ))
        ..addFile(ArchiveFile(
          '../evil.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ))
        ..addFile(ArchiveFile(
          'plugin/alpha.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ));
      final encoded = ZipEncoder().encode(archive)!;
      final zipPath = '${tempDir.path}/demo.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);

      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.bingx-trading.v1',
          method: 'place_bingx_spot_order_intent',
          args: <String, dynamic>{'symbol': 'BTC-USDT'},
        ),
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-zip-safe-select',
          packageVersion: '1.0.0',
          packageKind: 'zip',
          packageFilePath: zipPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(evidence, isNotNull);
      expect(evidence!.modulePath, 'plugin/alpha.wasm');
      expect(evidence.moduleSelection, 'lexical_first_wasm');
    });

    test('rejects zip package when all wasm entries are unsafe traversal',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin/manifest.json',
          2,
          utf8.encode('{}'),
        ))
        ..addFile(ArchiveFile(
          '../evil.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ));
      final encoded = ZipEncoder().encode(archive)!;
      final zipPath = '${tempDir.path}/demo.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-zip-unsafe',
            packageVersion: '1.0.0',
            packageKind: 'zip',
            packageFilePath: zipPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Plugin package has no safe WASM module paths',
          ),
        ),
      );
    });

    test('changes invoke digest when module path changes for same bytes',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final moduleBytes = _minimalWasmModule();
      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin/manifest.json',
          2,
          utf8.encode('{}'),
        ))
        ..addFile(ArchiveFile(
          'plugin/left.wasm',
          moduleBytes.length,
          moduleBytes,
        ))
        ..addFile(ArchiveFile(
          'plugin/right.wasm',
          moduleBytes.length,
          moduleBytes,
        ));
      final encoded = ZipEncoder().encode(archive)!;
      final zipPath = '${tempDir.path}/demo.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);

      final request = const PluginHostApiRequest(
        schemaVersion: 1,
        pluginId: 'hivra.contract.bingx-trading.v1',
        method: 'place_bingx_spot_order_intent',
        args: <String, dynamic>{'symbol': 'BTC-USDT'},
      );
      final leftEvidence = await service.invoke(
        request: request,
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-zip-left',
          packageVersion: '1.0.0',
          packageKind: 'zip',
          packageFilePath: zipPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          runtimeModulePath: 'plugin/left.wasm',
          contractKind: 'bingx_spot_order_intent',
        ),
      );
      final rightEvidence = await service.invoke(
        request: request,
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-zip-right',
          packageVersion: '1.0.0',
          packageKind: 'zip',
          packageFilePath: zipPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          runtimeModulePath: 'plugin/right.wasm',
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(leftEvidence, isNotNull);
      expect(rightEvidence, isNotNull);
      expect(leftEvidence!.moduleDigestHex, rightEvidence!.moduleDigestHex);
      expect(leftEvidence.modulePath, 'plugin/left.wasm');
      expect(rightEvidence.modulePath, 'plugin/right.wasm');
      expect(leftEvidence.invokeDigestHex,
          isNot(equals(rightEvidence.invokeDigestHex)));
    });

    test('rejects zip package when runtime module_path is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin/manifest.json',
          2,
          utf8.encode('{}'),
        ))
        ..addFile(ArchiveFile(
          'plugin/module.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ));
      final encoded = ZipEncoder().encode(archive)!;
      final zipPath = '${tempDir.path}/demo.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-zip',
            packageVersion: '1.0.0',
            packageKind: 'zip',
            packageFilePath: zipPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            runtimeModulePath: 'plugin/entry.wasm',
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects runtime module_path with parent traversal segments',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin/manifest.json',
          2,
          utf8.encode('{}'),
        ))
        ..addFile(ArchiveFile(
          'plugin/module.wasm',
          _minimalWasmModule().length,
          _minimalWasmModule(),
        ));
      final encoded = ZipEncoder().encode(archive)!;
      final zipPath = '${tempDir.path}/demo.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-zip-path-traversal',
            packageVersion: '1.0.0',
            packageKind: 'zip',
            packageFilePath: zipPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            runtimeModulePath: 'plugin/../module.wasm',
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects external package with wrong runtime ABI', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-bad-abi',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: 'wrong_abi',
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects wasm module when required entry export is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(exportedFunction: 'other_entry'),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-missing-entry',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM entry export symbol not found',
          ),
        ),
      );
    });

    test('rejects wasm module when entry export signature mismatches',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(hasI32Param: true),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-bad-signature',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM entry export signature mismatch',
          ),
        ),
      );
    });

    test('rejects wasm module when imports are declared', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(includeFunctionImport: true),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-with-import',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM imports are not supported in wasm_stub_v1',
          ),
        ),
      );
    });

    test('rejects wasm module when start section is declared', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(includeStartSection: true),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-with-start',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM start section is not supported in wasm_stub_v1',
          ),
        ),
      );
    });

    test('executes supported entry opcodes in wasm_stub_v1', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: const <int>[
            0x41, 0x2a, // i32.const 42
            0x1a, // drop
            0x0b, // end
          ],
        ),
        flush: true,
      );

      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.bingx-trading.v1',
          method: 'place_bingx_spot_order_intent',
          args: <String, dynamic>{'symbol': 'BTC-USDT'},
        ),
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-exec-subset',
          packageVersion: '1.0.0',
          packageKind: 'wasm',
          packageFilePath: wasmPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(evidence, isNotNull);
      expect(evidence!.mode, WasmPluginRuntimeStubService.runtimeMode);
    });

    test('executes i32 arithmetic opcodes in wasm_stub_v1', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: const <int>[
            0x41, 0x02, // i32.const 2
            0x41, 0x03, // i32.const 3
            0x6a, // i32.add
            0x1a, // drop
            0x41, 0x08, // i32.const 8
            0x41, 0x04, // i32.const 4
            0x6b, // i32.sub
            0x1a, // drop
            0x41, 0x07, // i32.const 7
            0x41, 0x06, // i32.const 6
            0x6c, // i32.mul
            0x1a, // drop
            0x0b, // end
          ],
        ),
        flush: true,
      );

      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.bingx-trading.v1',
          method: 'place_bingx_spot_order_intent',
          args: <String, dynamic>{'symbol': 'BTC-USDT'},
        ),
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-i32-arith',
          packageVersion: '1.0.0',
          packageKind: 'wasm',
          packageFilePath: wasmPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(evidence, isNotNull);
      expect(evidence!.mode, WasmPluginRuntimeStubService.runtimeMode);
    });

    test('executes block and br opcodes in wasm_stub_v1', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: const <int>[
            0x02, 0x40, // block void
            0x0c, 0x00, // br 0 (exit block)
            0x41, 0x02, // i32.const 2 (unreachable)
            0x1a, // drop
            0x0b, // end block
            0x0b, // end function
          ],
        ),
        flush: true,
      );

      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.bingx-trading.v1',
          method: 'place_bingx_spot_order_intent',
          args: <String, dynamic>{'symbol': 'BTC-USDT'},
        ),
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-block-branch',
          packageVersion: '1.0.0',
          packageKind: 'wasm',
          packageFilePath: wasmPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(evidence, isNotNull);
      expect(evidence!.mode, WasmPluginRuntimeStubService.runtimeMode);
    });

    test('executes if/else and br_if opcodes in wasm_stub_v1', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: const <int>[
            0x41, 0x00, // if condition = false
            0x04, 0x40, // if void
            0x41, 0x02, // then: i32.const 2
            0x1a, // then: drop
            0x05, // else
            0x41, 0x01, // else: i32.const 1
            0x0d, 0x00, // else: br_if 0 (exit if)
            0x41, 0x03, // else unreachable
            0x1a, // drop
            0x0b, // end if
            0x0b, // end function
          ],
        ),
        flush: true,
      );

      final evidence = await service.invoke(
        request: const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.bingx-trading.v1',
          method: 'place_bingx_spot_order_intent',
          args: <String, dynamic>{'symbol': 'BTC-USDT'},
        ),
        binding: PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-if-else-branch',
          packageVersion: '1.0.0',
          packageKind: 'wasm',
          packageFilePath: wasmPath,
          runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
          runtimeEntryExport: WasmPluginRuntimeStubService.requiredEntryExport,
          contractKind: 'bingx_spot_order_intent',
        ),
      );

      expect(evidence, isNotNull);
      expect(evidence!.mode, WasmPluginRuntimeStubService.runtimeMode);
    });

    test('rejects wasm module when branch depth is out of range', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: const <int>[
            0x02, 0x40, // block
            0x0c, 0x01, // br 1 (out of range for one label)
            0x0b, // end block
            0x0b, // end function
          ],
        ),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-branch-depth-range',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM branch depth out of range',
          ),
        ),
      );
    });

    test('rejects wasm module on i32 arithmetic type mismatch', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: const <int>[
            0x42, 0x01, // i64.const 1
            0x41, 0x02, // i32.const 2
            0x6a, // i32.add (lhs mismatches)
            0x0b, // end
          ],
        ),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-i32-type-mismatch',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM type mismatch on opcode 0x6a',
          ),
        ),
      );
    });

    test('rejects wasm module when entry contains unsupported loop opcode',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: const <int>[
            0x03, 0x40, // loop (unsupported in stub)
            0x0b,
          ],
        ),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-unsupported-opcode',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM loop opcode is not supported in wasm_stub_v1',
          ),
        ),
      );
    });

    test('rejects wasm module when instruction limit is exceeded', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      final instructions = <int>[
        ...List<int>.filled(2050, 0x01), // nop
        0x0b, // end
      ];
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: instructions,
        ),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-op-limit',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM instruction limit exceeded in wasm_stub_v1',
          ),
        ),
      );
    });

    test('rejects wasm module when stack depth limit is exceeded', () async {
      final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_stub_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final wasmPath = '${tempDir.path}/demo.wasm';
      final instructions = <int>[];
      for (var i = 0; i < 513; i++) {
        instructions
          ..add(0x41) // i32.const
          ..add(0x00);
      }
      instructions.add(0x0b); // end
      await File(wasmPath).writeAsBytes(
        _minimalWasmModule(
          functionBodyInstructions: instructions,
        ),
        flush: true,
      );

      await expectLater(
        () => service.invoke(
          request: const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.bingx-trading.v1',
            method: 'place_bingx_spot_order_intent',
            args: <String, dynamic>{'symbol': 'BTC-USDT'},
          ),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-stack-limit',
            packageVersion: '1.0.0',
            packageKind: 'wasm',
            packageFilePath: wasmPath,
            runtimeAbi: WasmPluginRuntimeStubService.requiredRuntimeAbi,
            runtimeEntryExport:
                WasmPluginRuntimeStubService.requiredEntryExport,
            contractKind: 'bingx_spot_order_intent',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'WASM stack depth limit exceeded in wasm_stub_v1',
          ),
        ),
      );
    });
  });
}

List<int> _minimalWasmModule({
  String exportedFunction = 'hivra_entry_v1',
  bool hasI32Param = false,
  bool includeFunctionImport = false,
  bool includeStartSection = false,
  List<int>? functionBodyInstructions,
}) {
  final nameBytes = utf8.encode(exportedFunction);
  if (nameBytes.length > 0x7f) {
    throw ArgumentError('exportedFunction must be <= 127 bytes');
  }
  final typeSectionPayload = hasI32Param
      ? <int>[0x01, 0x60, 0x01, 0x7f, 0x00]
      : <int>[0x01, 0x60, 0x00, 0x00];
  final importSectionPayload = includeFunctionImport
      ? <int>[
          ..._encodeU32Leb128(1),
          ..._encodeName('env'),
          ..._encodeName('host'),
          0x00, // function import
          ..._encodeU32Leb128(0), // type index
        ]
      : <int>[];
  final functionSectionPayload = <int>[
    ..._encodeU32Leb128(1),
    ..._encodeU32Leb128(0), // function type index
  ];
  final exportSectionPayload = <int>[
    ..._encodeU32Leb128(1),
    ..._encodeName(exportedFunction),
    0x00, // function export
    ..._encodeU32Leb128(includeFunctionImport ? 1 : 0),
  ];
  final startSectionPayload = includeStartSection
      ? <int>[
          ..._encodeU32Leb128(includeFunctionImport ? 1 : 0),
        ]
      : <int>[];
  final bodyInstructions = functionBodyInstructions ?? const <int>[0x0b];
  if (bodyInstructions.isEmpty || bodyInstructions.last != 0x0b) {
    throw ArgumentError(
      'functionBodyInstructions must end with opcode 0x0b (end)',
    );
  }
  final bodyPayload = <int>[
    0x00, // local decl count
    ...bodyInstructions,
  ];
  final codeSectionPayload = <int>[
    ..._encodeU32Leb128(1), // one function body
    ..._encodeU32Leb128(bodyPayload.length),
    ...bodyPayload,
  ];
  final sections = <int>[
    ..._encodeSection(1, typeSectionPayload),
    if (importSectionPayload.isNotEmpty)
      ..._encodeSection(2, importSectionPayload),
    ..._encodeSection(3, functionSectionPayload),
    ..._encodeSection(7, exportSectionPayload),
    if (startSectionPayload.isNotEmpty)
      ..._encodeSection(8, startSectionPayload),
    ..._encodeSection(10, codeSectionPayload),
  ];

  return <int>[
    0x00,
    0x61,
    0x73,
    0x6d,
    0x01,
    0x00,
    0x00,
    0x00,
    ...sections,
  ];
}

List<int> _encodeSection(int sectionId, List<int> payload) {
  return <int>[
    sectionId,
    ..._encodeU32Leb128(payload.length),
    ...payload,
  ];
}

List<int> _encodeName(String value) {
  final bytes = utf8.encode(value);
  return <int>[
    ..._encodeU32Leb128(bytes.length),
    ...bytes,
  ];
}

List<int> _encodeU32Leb128(int value) {
  if (value < 0) {
    throw ArgumentError('value must be >= 0');
  }
  var remaining = value;
  final encoded = <int>[];
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) {
      byte |= 0x80;
    }
    encoded.add(byte);
  } while (remaining != 0);
  return encoded;
}
