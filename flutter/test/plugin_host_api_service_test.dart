import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/plugin_contract_handlers.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';

void main() {
  test('complete package choice lists remain bounded without truncation', () {
    final options = List.generate(1400, (index) => 'RESOURCE-$index');
    final view = <String, dynamic>{
      'title': 'Choose resource',
      'message': '',
      'details': '',
      'actions': [],
      'rows': [],
      'columns': [],
      'fields': [],
      'options': options,
    };
    expect(utf8.encode(jsonEncode(view)).length, greaterThan(16 * 1024));
    expect(
      () => PluginWorkspaceContractHandler.validateView(view, capabilities: {}),
      returnsNormally,
    );
    expect(view['options'], same(options));
    expect(
      () => PluginWorkspaceContractHandler.validateView({
        ...view,
        'details': 'x' * (64 * 1024),
      }, capabilities: {}),
      throwsFormatException,
    );
  });

  test(
    'choice loading access uses the same validated permission descriptor',
    () {
      Map<String, dynamic> view(dynamic access) => {
        'title': 'Choose',
        'message': '',
        'details': '',
        'actions': [],
        'rows': [],
        'columns': [],
        'fields': [
          {
            'id': 'item',
            'label': 'Item',
            'type': 'choice',
            'value': 'a',
            'source': {'action': 'load', 'access': access},
          },
        ],
      };
      final access = {
        'version': 2,
        'network': [
          {
            'origin': 'https://catalog.example',
            'methods': ['GET'],
            'credential': null,
          },
        ],
        'credentials': {},
      };
      expect(
        () => PluginWorkspaceContractHandler.validateView(
          view(access),
          capabilities: {},
        ),
        returnsNormally,
      );
      expect(
        () => PluginWorkspaceContractHandler.validateView(
          view({...access, 'network': 'invalid'}),
          capabilities: {},
        ),
        throwsFormatException,
      );
    },
  );
  group('PluginHostApiService', () {
    test(
      'retired workspace operations are refused before invoking WASM',
      () async {
        var calls = 0;
        final host = _service(
          runtimeBinding: const PluginRuntimeBinding.externalPackage(
            packageId: 'old-workspace',
            packageVersion: '0.1.13',
            packageKind: 'zip',
            packageDigestHex:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            runtimeAbi: 'hivra_host_abi_v2',
            runtimeEntryExport: 'hivra_evaluate_v1',
            runtimeModulePath: 'plugin/module.wasm',
            contractKind: pluginWorkspaceContractKind,
            capabilities: [
              'workspace.render',
              'workspace.continue',
              'account.connect',
            ],
          ),
          onRuntimeInvoke: () => calls++,
        );
        final response = await host.executeWithRuntimeHook(
          const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'example.service',
            method: pluginWorkspaceMethod,
            args: {},
          ),
        );
        expect(response.errorCode, 'runtime_capability_mismatch');
        expect(response.errorMessage, contains('compatible plugin update'));
        expect(calls, 0);
      },
    );
    test('raw binding cannot invoke an external package', () async {
      var calls = 0;
      final host = PluginHostApiService(
        handlers: const [],
        resolveRuntimeBinding:
            (_) async => const PluginRuntimeBinding.externalPackage(
              packageId: 'raw',
              packageVersion: '1',
              packageKind: 'wasm',
              contractKind: pluginWorkspaceContractKind,
              capabilities: ['workspace.render', 'workspace.continue'],
            ),
        resolveRuntimeInvoke: (_, _) async {
          calls++;
          return null;
        },
      );
      final response = await host.executeWithRuntimeHook(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'example.package',
          method: pluginWorkspaceMethod,
          args: {},
        ),
      );
      expect(response.errorCode, 'runtime_binding_invalid');
      expect(calls, 0);
    });
    test('rejects unsupported plugin id', () {
      final response = _service().execute(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.unknown.v1',
          method: 'unknown_method',
          args: <String, dynamic>{},
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'unsupported_plugin');
    });

    test('retired Chat package cannot invoke an installed runtime', () async {
      var calls = 0;
      final host = _service(
        runtimeBinding: PluginRuntimeBinding.externalPackage(
          packageId: 'legacy-chat',
          packageVersion: '1',
          packageKind: 'zip',
          packageDigestHex: 'a' * 64,
          contractKind: pluginWorkspaceContractKind,
          capabilities: pluginWorkspaceRequiredCapabilities.toList(),
        ),
        onRuntimeInvoke: () => calls++,
      );
      final response = await host.executeWithRuntimeHook(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: capsuleChatPluginId,
          method: pluginWorkspaceMethod,
          args: {},
        ),
      );
      expect(response.errorCode, 'unsupported_plugin');
      expect(calls, 0);
    });

    for (final change in ['remove', 'replace', 'raw', 'revoke', 'reorder']) {
      test(
        'runtime result respects package authority after await: $change',
        () async {
          var completed = false;
          final host = PluginHostApiService(
            handlers: const [],
            resolveRuntimeBinding: (_) async {
              if (completed && change == 'remove') {
                return const PluginRuntimeBinding.hostFallback();
              }
              return PluginRuntimeBinding.externalPackage(
                packageVersion: '1.0.0',
                packageId:
                    completed && change == 'replace'
                        ? 'new-package'
                        : 'original-package',
                packageKind: completed && change == 'raw' ? 'wasm' : 'zip',
                packageDigestHex: 'a' * 64,
                contractKind: pluginWorkspaceContractKind,
                capabilities:
                    completed && change == 'revoke'
                        ? ['workspace.render', 'workspace.continue']
                        : completed && change == 'reorder'
                        ? [
                          'network.http',
                          'workspace.continue',
                          'workspace.render',
                        ]
                        : [
                          'workspace.render',
                          'workspace.continue',
                          'network.http',
                        ],
              );
            },
            resolveRuntimeInvoke: (_, _) async {
              completed = true;
              return _workspaceRuntimeEvidence();
            },
          );
          final response = await host.executeWithRuntimeHook(
            const PluginHostApiRequest(
              schemaVersion: 1,
              pluginId: 'example.service',
              method: pluginWorkspaceMethod,
              args: {},
            ),
          );
          if (change == 'reorder') {
            expect(response.status, PluginHostApiStatus.executed);
            expect(response.result?['view']['title'], 'Fixture');
          } else {
            expect(response.status, PluginHostApiStatus.rejected);
            expect(response.errorCode, 'runtime_binding_changed');
            expect(response.result, isNull);
          }
        },
      );
    }

    test(
      'retired named service methods have no executable host handler',
      () async {
        var calls = 0;
        final host = PluginHostApiService(
          handlers: [],
          resolveRuntimeBinding:
              (_) async => const PluginRuntimeBinding.externalPackage(
                packageId: 'old-package',
                packageVersion: '0.7.3',
                packageKind: 'zip',
                packageDigestHex:
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                contractKind: 'moltbook_ambassador_draft',
                capabilities: ['content.draft.prepare'],
              ),
          resolveRuntimeInvoke: (_, _) async {
            calls++;
            return null;
          },
        );
        final response = await host.executeWithRuntimeHook(
          const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.moltbook-ambassador.v1',
            method: 'prepare_moltbook_draft',
            args: {},
          ),
        );
        expect(response.status, PluginHostApiStatus.rejected);
        expect(calls, 0);
      },
    );
  });
}

PluginHostApiService _service({
  PluginRuntimeBinding? runtimeBinding,
  void Function()? onRuntimeInvoke,
}) => PluginHostApiService(
  handlers: const [],
  resolveRuntimeBinding:
      (_) async => runtimeBinding ?? const PluginRuntimeBinding.hostFallback(),
  resolveRuntimeInvoke: (_, _) async {
    onRuntimeInvoke?.call();
    return _workspaceRuntimeEvidence();
  },
);

PluginRuntimeInvokeEvidence _workspaceRuntimeEvidence() =>
    PluginRuntimeInvokeEvidence(
      mode: 'wasmi_v1',
      modulePath: 'plugin/module.wasm',
      moduleSelection: 'manifest_module_path',
      moduleDigestHex: 'e' * 64,
      invokeDigestHex: 'f' * 64,
      semanticStatus: PluginHostApiStatus.executed,
      semanticResult: {
        'view': {
          'title': 'Fixture',
          'message': '',
          'details': '',
          'fields': [],
          'actions': [],
          'rows': [],
          'columns': [],
        },
        'requests': [],
      },
      semanticErrorCode: null,
      semanticErrorMessage: null,
    );
