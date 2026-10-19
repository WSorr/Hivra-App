import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/screens/main_screen.dart';
import 'package:hivra_app/services/plugin_contract_handlers.dart';

void main() {
  test('installed manifest profiles select the canonical workspace', () {
    final profiles = <(String, String)>[
      (capsuleChatPluginId, capsuleChatContractKind),
      (moltbookAmbassadorPluginId, moltbookAmbassadorContractKind),
    ];

    for (final (pluginId, contractKind) in profiles) {
      final capabilities = switch (contractKind) {
        capsuleChatContractKind => capsuleChatRequiredCapabilities.toList(),
        moltbookAmbassadorContractKind =>
          moltbookAmbassadorRequiredCapabilities.toList(),
        _ => const <String>[],
      };
      expect(
        installedPluginWorkspaceContractKind(
          _record(
            pluginId: pluginId,
            contractKind: contractKind,
            capabilities: capabilities,
          ),
        ),
        contractKind,
      );
    }
  });

  test('every required capability controls readiness and activation', () {
    final profiles = <(String, String, Set<String>)>[
      (
        capsuleChatPluginId,
        capsuleChatContractKind,
        capsuleChatRequiredCapabilities,
      ),
      (
        moltbookAmbassadorPluginId,
        moltbookAmbassadorContractKind,
        moltbookAmbassadorRequiredCapabilities,
      ),
      (
        'hivra.contract.independent.v1',
        pluginWorkspaceContractKind,
        pluginWorkspaceRequiredCapabilities,
      ),
    ];
    for (final (pluginId, contractKind, required) in profiles) {
      for (final missing in required) {
        final capabilities =
            required.where((value) => value != missing).toList();
        final record = _record(
          pluginId: pluginId,
          contractKind: contractKind,
          capabilities: capabilities,
        );
        expect(
          pluginCapabilitiesSatisfyContract(
            pluginId: pluginId,
            contractKind: contractKind,
            capabilities: capabilities,
          ),
          isFalse,
          reason: '$pluginId without $missing',
        );
        expect(
          installedPluginWorkspaceContractKind(record),
          isNull,
          reason: '$pluginId without $missing',
        );
      }
      final capabilities = [...required, 'consensus_guard.read'];
      expect(
        installedPluginWorkspaceContractKind(
          _record(
            pluginId: ' ${pluginId.toUpperCase()} ',
            contractKind: contractKind,
            capabilities: capabilities,
          ),
        ),
        contractKind,
      );
      expect(
        pluginCapabilitiesSatisfyContract(
          pluginId: ' ${pluginId.toUpperCase()} ',
          contractKind: contractKind,
          capabilities: capabilities,
        ),
        isTrue,
      );
    }
  });

  test('workspace requirements cover exactly the host method requirements', () {
    final handlers = [
      const PluginWorkspaceContractHandler(
        pluginId: 'hivra.contract.independent.v1',
      ),
      CapsuleChatPluginContractHandler(
        readSignable:
            (_) =>
                throw StateError(
                  'No consensus read during capability inspection',
                ),
      ),
      const MoltbookAmbassadorPluginContractHandler(),
    ];
    for (final handler in handlers) {
      final requiredByHost = <String>{
        for (final method in handler.methods)
          ...handler.requiredCapabilities(method),
      };
      expect(
        requiredCapabilitiesForPlugin(
          pluginId: handler.pluginId,
          contractKind: handler.contractKind,
        ),
        requiredByHost,
      );
    }
  });

  test('readiness shares the activation capability contract', () {
    expect(
      pluginCapabilitiesSatisfyContract(
        pluginId: moltbookAmbassadorPluginId,
        contractKind: moltbookAmbassadorContractKind,
        capabilities: moltbookAmbassadorRequiredCapabilities.toList(),
      ),
      isTrue,
    );
    expect(
      pluginCapabilitiesSatisfyContract(
        pluginId: moltbookAmbassadorPluginId,
        contractKind: moltbookAmbassadorContractKind,
        capabilities: const [
          'content.draft.prepare',
          'content.engagement.plan',
          'content.feed.plan',
          'content.reply.prepare',
        ],
      ),
      isFalse,
    );
    expect(
      pluginCapabilitiesSatisfyContract(
        pluginId: 'hivra.contract.independent.v1',
        contractKind: 'other_contract',
        capabilities: const [],
      ),
      isTrue,
    );
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

  test(
    'installed workspace does not require a product-specific shell route',
    () {
      final record = _record(
        pluginId: 'hivra.contract.independent-package.v1',
        contractKind: pluginWorkspaceContractKind,
        capabilities: const [
          'workspace.render',
          'workspace.continue',
          'state.plugin.read_write',
        ],
      );
      expect(
        installedPluginWorkspaceContractKind(record),
        pluginWorkspaceContractKind,
      );
      expect(
        installedPluginWorkspaceContractKind(
          _record(
            pluginId: record.pluginId!,
            contractKind: pluginWorkspaceContractKind,
            capabilities: const ['workspace.render'],
          ),
        ),
        isNull,
      );
      expect(
        installedPluginWorkspaceContractKind(
          _record(
            pluginId: record.pluginId!,
            contractKind: pluginWorkspaceContractKind,
            capabilities: const ['workspace.render', 'state.plugin.read_write'],
          ),
        ),
        isNull,
      );
    },
  );
}

WasmPluginRecord _record({
  String pluginId = capsuleChatPluginId,
  String contractKind = capsuleChatContractKind,
  String packageKind = 'zip',
  String runtimeAbi = 'hivra_host_abi_v2',
  String runtimeEntryExport = 'hivra_evaluate_v1',
  String runtimeModulePath = 'plugin/module.wasm',
  List<String> capabilities = const ['consensus_guard.read'],
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
  capabilities: capabilities,
);
