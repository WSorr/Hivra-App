import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/wasm_plugin_runtime_service.dart';

void main() {
  group('WasmPluginRuntimeService', () {
    test('returns null for host fallback binding', () async {
      final service = WasmPluginRuntimeService(
        invokeJson: _executedInvoker,
      );
      final evidence = await service.invoke(
        request: _request(),
        binding: const PluginRuntimeBinding.hostFallback(),
      );
      expect(evidence, isNull);
    });

    test('invokes manifest-selected module and returns semantic result',
        () async {
      final package = await _writePackage();
      addTearDown(package.dispose);
      final service = WasmPluginRuntimeService(
        invokeJson: ({
          required Uint8List moduleBytes,
          required String entryExport,
          required Uint8List inputJsonBytes,
        }) {
          expect(entryExport, WasmPluginRuntimeService.requiredEntryExport);
          expect(moduleBytes.take(4), <int>[0, 0x61, 0x73, 0x6d]);
          final input = jsonDecode(utf8.decode(inputJsonBytes));
          expect(input['plugin_id'], _pluginId);
          expect(input['symbol'], 'BTC-USDT');
          return _executedOutput;
        },
      );

      final evidence = await service.invoke(
        request: _request(),
        binding: package.binding,
      );

      expect(evidence, isNotNull);
      expect(evidence!.mode, WasmPluginRuntimeService.runtimeMode);
      expect(evidence.modulePath, 'plugin/module.wasm');
      expect(evidence.semanticStatus, PluginHostApiStatus.executed);
      expect(evidence.semanticResult?['intent_hash_hex'], _hex('a'));
      expect(evidence.moduleDigestHex.length, 64);
      expect(evidence.invokeDigestHex.length, 64);
    });

    test('preserves deterministic invoke digest', () async {
      final package = await _writePackage();
      addTearDown(package.dispose);
      final service = WasmPluginRuntimeService(
        invokeJson: _executedInvoker,
      );

      final first = await service.invoke(
        request: _request(),
        binding: package.binding,
      );
      final second = await service.invoke(
        request: _request(),
        binding: package.binding,
      );

      expect(first!.invokeDigestHex, second!.invokeDigestHex);
    });

    test('rejects malformed semantic envelope', () async {
      final package = await _writePackage();
      addTearDown(package.dispose);
      final service = WasmPluginRuntimeService(
        invokeJson: ({
          required Uint8List moduleBytes,
          required String entryExport,
          required Uint8List inputJsonBytes,
        }) =>
            '{"schema_version":1,"status":"executed","result":null}',
      );

      await expectLater(
        () => service.invoke(
          request: _request(),
          binding: package.binding,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires ABI v2 and package digest', () async {
      final package = await _writePackage();
      addTearDown(package.dispose);
      final service = WasmPluginRuntimeService(
        invokeJson: _executedInvoker,
      );

      await expectLater(
        () => service.invoke(
          request: _request(),
          binding: PluginRuntimeBinding.externalPackage(
            packageId: 'pkg',
            packageVersion: '1',
            packageKind: 'zip',
            packageFilePath: package.path,
            packageDigestHex: package.binding.packageDigestHex,
            runtimeAbi: 'hivra_host_abi_v1',
            runtimeEntryExport: WasmPluginRuntimeService.requiredEntryExport,
            runtimeModulePath: 'plugin/module.wasm',
            contractKind: 'bingx_futures_order_intent',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

String? _executedInvoker({
  required Uint8List moduleBytes,
  required String entryExport,
  required Uint8List inputJsonBytes,
}) =>
    _executedOutput;

PluginHostApiRequest _request() => const PluginHostApiRequest(
      schemaVersion: 1,
      pluginId: _pluginId,
      method: 'place_bingx_futures_order_intent',
      args: <String, dynamic>{'symbol': 'BTC-USDT'},
    );

Future<_TestPackage> _writePackage() async {
  final tempDir = await Directory.systemTemp.createTemp('hivra_wasm_runtime_');
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'plugin/module.wasm',
        _wasmHeader.length,
        _wasmHeader,
      ),
    );
  final bytes = ZipEncoder().encode(archive)!;
  final path = '${tempDir.path}/plugin.zip';
  await File(path).writeAsBytes(bytes, flush: true);
  return _TestPackage(
    path: path,
    tempDir: tempDir,
    binding: PluginRuntimeBinding.externalPackage(
      packageId: 'pkg',
      packageVersion: '0.2.0',
      packageKind: 'zip',
      packageFilePath: path,
      packageDigestHex: sha256.convert(bytes).toString(),
      runtimeAbi: WasmPluginRuntimeService.requiredRuntimeAbi,
      runtimeEntryExport: WasmPluginRuntimeService.requiredEntryExport,
      runtimeModulePath: 'plugin/module.wasm',
      contractKind: 'bingx_futures_order_intent',
    ),
  );
}

class _TestPackage {
  final String path;
  final Directory tempDir;
  final PluginRuntimeBinding binding;

  const _TestPackage({
    required this.path,
    required this.tempDir,
    required this.binding,
  });

  Future<void> dispose() => tempDir.delete(recursive: true);
}

const String _pluginId = 'hivra.contract.bingx-futures-trading.v1';
const List<int> _wasmHeader = <int>[
  0x00,
  0x61,
  0x73,
  0x6d,
  0x01,
  0x00,
  0x00,
  0x00,
];
const String _executedOutput =
    '{"schema_version":1,"status":"executed","result":'
    '{"canonical_json":"{\\"plugin_id\\":\\"hivra.contract.bingx-futures-trading.v1\\"}",'
    '"intent_hash_hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},'
    '"error_code":null,"error_message":null}';

String _hex(String character) => List<String>.filled(64, character).join();
