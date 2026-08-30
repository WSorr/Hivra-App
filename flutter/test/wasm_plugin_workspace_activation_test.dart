import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/screens/wasm_plugins_screen.dart';

void main() {
  test('installed manifest profiles select the canonical workspace', () {
    final profiles = <(String, String)>[
      (capsuleChatPluginId, capsuleChatContractKind),
      (moltbookAmbassadorPluginId, moltbookAmbassadorContractKind),
      (bingxFuturesTradingPluginId, bingxFuturesContractKind),
    ];

    for (final (pluginId, contractKind) in profiles) {
      expect(
        installedPluginWorkspaceContractKind(
          _record(pluginId: pluginId, contractKind: contractKind),
        ),
        contractKind,
      );
    }
  });

  test('mutated or incomplete manifest profiles expose no workspace', () {
    final invalidProfiles = <WasmPluginRecord>[
      _record(pluginId: 'hivra.contract.other-chat.v1'),
      _record(contractKind: 'other_chat'),
      _record(runtimeAbi: 'unsupported_abi'),
      _record(runtimeEntryExport: 'unsupported_entry'),
      _record(runtimeModulePath: ''),
      _record(packageKind: 'wasm'),
    ];

    for (final record in invalidProfiles) {
      expect(installedPluginWorkspaceContractKind(record), isNull);
    }
  });
}

WasmPluginRecord _record({
  String pluginId = capsuleChatPluginId,
  String contractKind = capsuleChatContractKind,
  String packageKind = 'zip',
  String runtimeAbi = 'hivra_host_abi_v2',
  String runtimeEntryExport = 'hivra_evaluate_v1',
  String runtimeModulePath = 'plugin/module.wasm',
}) => WasmPluginRecord(
  id: 'package-id',
  displayName: 'Plugin',
  originalFileName: 'plugin.zip',
  storedFileName: 'plugin.zip',
  sizeBytes: 100,
  installedAtIso: '2026-08-30T00:00:00Z',
  packageKind: packageKind,
  pluginId: pluginId,
  pluginVersion: '1.0.0',
  contractKind: contractKind,
  runtimeAbi: runtimeAbi,
  runtimeEntryExport: runtimeEntryExport,
  runtimeModulePath: runtimeModulePath,
  capabilities: const <String>['consensus_guard.read'],
);
