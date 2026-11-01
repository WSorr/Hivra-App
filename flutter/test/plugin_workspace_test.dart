import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/screens/plugin_workspace_screen.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/plugin_capability_dispatcher.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_workspace_runtime.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';

void main() {
  test(
    'catalog is common and an unrelated package selects its continuation',
    () async {
      for (final origin in ['https://one.example', 'https://two.example']) {
        final f = await Fixture.create(origin: origin);
        addTearDown(f.close);
        await f.enable();
        final view = await f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        );
        expect(f.sends, 1);
        expect(view['message'], 'response');
        expect(f.actions, contains('finish_custom_operation'));
        expect(
          PluginCapabilityDispatcher.catalog.keys,
          containsAll([
            'http.request',
            'storage.read',
            'storage.write',
            'api.describe',
          ]),
        );
        expect(f.received.single['body'], 'arbitrary service bytes');
      }
    },
  );
  test(
    'owner permission controls destination, method, credential, expiry and revocation',
    () async {
      for (final fault in [
        'absent',
        'origin',
        'method',
        'credential',
        'expired',
        'revoked',
        'disabled',
      ]) {
        final f = await Fixture.create();
        addTearDown(f.close);
        if (fault != 'absent') await f.enable();
        if (fault == 'origin') f.url = 'https://elsewhere.example/action';
        if (fault == 'method') f.method = 'DELETE';
        if (fault == 'credential') f.credential = 'different';
        if (['expired', 'revoked', 'disabled'].contains(fault)) {
          await f.changeGrant((g) {
            if (fault == 'expired') g['expires_at_ms'] = 1;
            if (fault == 'revoked') {
              g['revoked'] = true;
              g['enabled'] = false;
            }
            if (fault == 'disabled') g['enabled'] = false;
          });
        }
        await f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        );
        expect(f.sends, 0, reason: fault);
        expect(f.received.single['outcome'], 'not_dispatched', reason: fault);
      }
    },
  );
  test(
    'a legacy risk grant stays custody evidence and never grants network effects',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      await f.changeGrant((g) {
        g['version'] = 1;
        g.remove('enabled');
        g['allow_new_entries'] = true;
        g['scope'] = {
          'action': 'cycle',
          'interval_seconds': 60,
          'account_id': 'a' * 64,
          'symbol': 'BTC-USDT',
          'max_margin': 1.0,
          'max_stop_percent': 20.0,
        };
      });
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(f.sends, 0);
      expect(f.received.single['outcome'], 'not_dispatched');
      final grant = await f.runtime().readWorkspaceExecution(f.registry.record);
      expect(grant!['version'], 1);
    },
  );
  test(
    'revocation, removal, package and Capsule changes during secret read refuse dispatch',
    () async {
      for (final fault in [
        'revoke',
        'remove',
        'replace',
        'capsule',
        'capability',
      ]) {
        final f = await Fixture.create();
        addTearDown(f.close);
        await f.enable();
        f.credential = 'default';
        f.auth = {
          'headers': {
            'Authorization': {'field': 'token', 'prefix': 'Bearer '},
          },
        };
        f.onReadSecrets = () async {
          if (fault == 'revoke') {
            await f.changeGrant((g) {
              g['enabled'] = false;
              g['revision'] = (g['revision'] as int) + 1;
            });
          }
          if (fault == 'remove') f.registry.installed = false;
          if (fault == 'replace') f.registry.digest = 'c' * 64;
          if (fault == 'capsule') f.owner = 'd' * 64;
          if (fault == 'capability') f.registry.network = false;
        };
        try {
          await f.runtime().runWorkspaceAction(
            record: f.registry.record,
            action: 'run',
          );
        } catch (_) {}
        expect(f.sends, 0, reason: fault);
      }
    },
  );
  test(
    'uncertain transport persists package intent before dispatch and never retries',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      f.onSend = () async {
        final state = await f.state();
        expect(state['private_schema']['pending'], true);
        throw TimeoutException('signed URL and secret must not escape');
      };
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(f.sends, 1);
      expect(f.received.single, containsPair('outcome', 'unknown'));
      expect(jsonEncode(f.received), isNot(contains('signed URL')));
      final retained = await f.state();
      expect(retained['private_schema']['pending'], true);
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
      );
      expect(f.sends, 1);
      expect(await f.state(), retained);
    },
  );
  test(
    'replacement changes private schema without a host migration or inherited grant',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      f.registry.digest = 'c' * 64;
      f.newSchema = true;
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
      );
      expect((await f.state())['entirely_different_shape'], isList);
      expect(
        await f.runtime().readWorkspaceExecution(f.registry.record),
        isNull,
      );
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(f.sends, 1);
      expect(f.received.last['outcome'], 'not_dispatched');
    },
  );
  test(
    'owner can stop while a network read is in flight; next request is refused',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      f.onSend = () async {
        await f.changeGrant((g) {
          g['enabled'] = false;
          g['revision'] = (g['revision'] as int) + 1;
        });
      };
      f.chain = true;
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(f.sends, 1);
      expect(f.received.last['outcome'], 'not_dispatched');
    },
  );
  test(
    'old service request shapes are rejected rather than routed by the host',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.requestKind = 'order.entry.place';
      await expectLater(
        f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        ),
        throwsStateError,
      );
      expect(f.sends, 0);
    },
  );
  test(
    'protected authentication applies only at its granted destination',
    () async {
      for (final signature in [false, true]) {
        var calls = 0;
        final transport = PluginCapabilityDispatcher(
          send: (method, uri, headers, body) async {
            calls++;
            expect(headers['X-Key'], 'test-token');
            if (signature) {
              expect(
                uri.queryParameters['signature'],
                matches(r'^[0-9a-f]{64}$'),
              );
            }
            return {'status': 201, 'body': 'created'};
          },
        );
        final request = {
          'kind': 'http.request',
          'url': 'https://one.example/action?timestamp=1',
          'method': 'POST',
          'credential': 'default',
          'auth': {
            'headers': {
              'X-Key': {'field': 'token'},
            },
            if (signature)
              'hmac_query': {'parameter': 'signature', 'field': 'secret'},
          },
        };
        final access = permission('https://one.example');
        final result = await transport.http(
          request,
          access: access,
          readCredentials:
              () async => {'token': 'test-token', 'secret': 'test-secret'},
          authorize: () async {},
        );
        expect(result['outcome'], 'response');
        expect(calls, 1);
        request['url'] = 'https://foreign.example/action';
        expect(
          (await transport.http(
            request,
            access: access,
            readCredentials: () async => fail('Secret read outside scope'),
            authorize: () async {},
          ))['outcome'],
          'not_dispatched',
        );
        expect(calls, 1);
      }
    },
  );
  test(
    'response limits, invalid headers and echoed credentials cannot escape into WASM',
    () async {
      for (final fault in ['limit', 'echo', 'header']) {
        var calls = 0;
        final transport = PluginCapabilityDispatcher(
          send: (m, u, h, b) async {
            calls++;
            return {
              'status': 200,
              'body': fault == 'limit' ? 'x' * (24 * 1024 + 1) : 'test-token',
            };
          },
        );
        final request = {
          'url': 'https://one.example/action',
          'method': 'POST',
          'credential': 'default',
          'auth': {
            'headers': {
              'X-Key': {'field': 'token'},
            },
          },
          if (fault == 'header') 'headers': {'Host': 'foreign.example'},
        };
        final result = await transport.http(
          request,
          access: permission('https://one.example'),
          readCredentials: () async => {'token': 'test-token'},
          authorize: () async {},
        );
        expect(
          result['outcome'],
          fault == 'header' ? 'not_dispatched' : 'unknown',
        );
        expect(jsonEncode(result), isNot(contains('test-token')));
        expect(calls, fault == 'header' ? 0 : 1);
      }
    },
  );
  test(
    'owner connects references once; only the host resolves selected secrets',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      f.credential = 'default';
      f.auth = {
        'headers': {
          'Authorization': {'field': 'token', 'prefix': 'Bearer '},
        },
      };
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(f.sends, 1);
      expect(jsonEncode(await f.state()), isNot(contains('test-token')));
      expect(f.actions, isNot(contains('credentials.accept')));
    },
  );
  test(
    'remote provisioning cannot expose a field excluded from the current owner connection',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      f.secrets = jsonEncode({
        'version': 3,
        'connections': {
          'default': {'token': 'test-token', 'other': 'unselected-secret'},
        },
      });
      f.credential = 'default';
      f.auth = {
        'headers': {
          'Authorization': {'field': 'other'},
        },
      };
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(f.sends, 0);
      expect(f.received.single['outcome'], 'not_dispatched');
    },
  );
  test(
    'package timing uses a bounded generic wait without service requests',
    () async {
      for (final delay in [-1, 0]) {
        final f = await Fixture.create();
        addTearDown(f.close);
        f.requestKind = 'runtime.wait';
        f.extraRequest = {'milliseconds': delay};
        final run = f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        );
        if (delay < 0) {
          await expectLater(run, throwsStateError);
        } else {
          await run;
          expect(f.actions, contains('finish_custom_operation'));
        }
        expect(f.sends, 0);
      }
    },
  );
  test(
    'a stateless package reacquires service observations after restart without a checkpoint',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.registry.persistent = false;
      f.registry.scheduled = false;
      await f.enable();
      for (var i = 0; i < 2; i++) {
        await f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        );
        expect(
          await f.files.readPluginState(
            await f.files.capsuleDirForHex(f.owner),
            f.registry.record.pluginId!,
            'workspace.v1.json',
          ),
          isNull,
        );
      }
      expect(f.sends, 2);
      expect(
        (await f.runtime().readWorkspaceExecution(
          f.registry.record,
        ))!['enabled'],
        true,
      );
    },
  );
  test(
    'partial Stop is a package action; host revocation ends all further dispatch',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      await f.runtime().setWorkspaceExecution(
        record: f.registry.record,
        enabled: false,
        expiresAtMs: null,
        revoke: true,
      );
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(f.sends, 0);
      expect(
        (await f.runtime().readWorkspaceExecution(
          f.registry.record,
        ))!['revoked'],
        true,
      );
    },
  );
  test('queued owner access cannot be widened by its caller', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    final entered = Completer<void>(), release = Completer<void>();
    f.onInvoke = (action) async {
      if (action == 'open' && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final first = f.runtime().runWorkspaceAction(
      record: f.registry.record,
      action: 'open',
    );
    await entered.future;
    final access = permission(f.origin);
    f.url = 'https://foreign.example/action';
    final second = f.runtime().runWorkspaceAction(
      record: f.registry.record,
      action: 'run',
    );
    (access['network'] as List).add({
      'origin': 'https://foreign.example',
      'methods': ['POST'],
      'credential': null,
    });
    release.complete();
    await first;
    await second;
    expect(f.sends, 0);
    expect(f.received.single['outcome'], 'not_dispatched');
  });
  test(
    'opaque data cannot overwrite permissions or legacy delivery evidence',
    () async {
      for (final key in [
        'workspace-execution.v1.json',
        'external_effects.v1.json',
        '../grant',
      ]) {
        final f = await Fixture.create();
        addTearDown(f.close);
        await f.enable();
        f.requestKind = 'storage.write';
        f.extraRequest = {'key': key, 'value': 'overwrite'};
        await expectLater(
          f.runtime().runWorkspaceAction(
            record: f.registry.record,
            action: 'run',
          ),
          throwsStateError,
        );
        expect(
          (await f.runtime().readWorkspaceExecution(
            f.registry.record,
          ))!['enabled'],
          true,
        );
      }
    },
  );
  test('inference rechecks owner access before adapter dispatch', () async {
    for (final revoke in [false, true]) {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.requestKind = 'ai.infer';
      f.inferenceAllowed = true;
      await f.enable();
      var calls = 0;
      f.infer = (request, authorize) async {
        if (revoke) {
          await f.changeGrant((g) {
            g['enabled'] = false;
            g['revision']++;
          });
        }
        await authorize();
        calls++;
        return {'outcome': 'response', 'text': 'bounded answer'};
      };
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(calls, revoke ? 0 : 1);
      expect(
        f.received.single['outcome'],
        revoke ? 'not_dispatched' : 'response',
      );
    }
  });
  testWidgets(
    'one owner grant connects Keychain references and Start reuses it',
    (tester) async {
      final access = permission('https://one.example');
      var grants = 0, starts = 0;
      Map<String, dynamic>? execution;
      Map<String, Map<String, String>>? selected;
      Map<String, dynamic> view() => {
        ...presentation(),
        'access': access,
        'schedule': {
          'version': 2,
          'action': 'tick',
          'interval_seconds': 60,
          'description': 'Complete workflow',
          'access': access,
        },
        if (execution != null) 'execution': execution,
        'actions': [
          {'id': 'link', 'label': 'Connect', 'host': 'workspace.authorize'},
          {'id': 'start', 'label': 'Start', 'host': 'workspace.start'},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule', 'credentials.use'],
            listSecrets:
                () async => [
                  {'id': 'ref-token', 'label': 'Service / account / token'},
                ],
            configureExecution: ({
              required enabled,
              required expiresAtMs,
              expectedRevision,
              revoke = false,
              approvedScope,
              credentialBindings,
              settings = const {},
            }) async {
              grants++;
              selected = credentialBindings ?? selected;
              execution = {
                'enabled': true,
                'active': true,
                'running': approvedScope?['action'] != null,
                'access': approvedScope!['access'],
                'credentials': selected,
                'revision': grants,
                'expires_at_ms': expiresAtMs,
              };
              return view();
            },
            runWorkspaceAction: (action, settings) async {
              if (action == 'start') starts++;
              return view();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Plugin permissions'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('plugin-credential-token')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('plugin-secret-default-token')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Service / account / token').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(selected, {
        'default': {'token': 'ref-token'},
      });
      expect(grants, 1);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(grants, 2);
      expect(find.text('Allow'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a choice asks the package-selected action through the common executor',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            runWorkspaceAction: (action, settings) async {
              actions.add(action);
              return {
                ...presentation(),
                'fields': [
                  {
                    'id': 'destination',
                    'type': 'choice',
                    'label': 'Destination',
                    'value': 'alpha',
                    'source': {'action': 'list_destinations'},
                  },
                ],
                if (action == 'list_destinations') 'options': ['alpha', 'beta'],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plugin-field-destination')));
      await tester.pumpAndSettle();
      expect(actions, ['open', 'list_destinations']);
      await tester.tap(find.text('beta'));
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'HTTP response budget is opt-in and bounded independently of request size',
    () async {
      for (final selected in [null, 128 * 1024, 300 * 1024]) {
        var calls = 0;
        final dispatcher = PluginCapabilityDispatcher(
          send: (m, u, h, b) async {
            calls++;
            return {'status': 200, 'body': 'x' * (80 * 1024)};
          },
        );
        final result = await dispatcher.http(
          {
            'kind': 'http.request',
            'url': 'https://one.example/history',
            'method': 'GET',
            if (selected != null) 'max_response_bytes': selected,
          },
          access: permission('https://one.example'),
          readCredentials: () async => {},
          authorize: () async {},
        );
        expect(
          result['outcome'],
          selected == null
              ? 'unknown'
              : selected <= 256 * 1024
              ? 'response'
              : 'not_dispatched',
        );
        expect(calls, selected == 300 * 1024 ? 0 : 1);
      }
    },
  );
  test(
    'stateless restart receives owner settings from the existing permission record',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.registry.persistent = false;
      f.registry.scheduled = false;
      await f.runtime().setWorkspaceExecution(
        record: f.registry.record,
        enabled: true,
        expiresAtMs: null,
        approvedScope: f.schedule,
        credentialBindings: {
          'default': {'token': 'ref-token'},
        },
        settings: {'repository': 'owner/new-source'},
      );
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
      );
      expect(f.settingsSeen.last, {'repository': 'owner/new-source'});
      expect(
        await f.files.readPluginState(
          await f.files.capsuleDirForHex(f.owner),
          f.registry.record.pluginId!,
          'workspace.v1.json',
        ),
        isNull,
      );
    },
  );
}

Map<String, dynamic> permission(String origin) => {
  'version': 2,
  'credentials': {
    'default': [
      {'id': 'token', 'label': 'Connection token'},
    ],
  },
  'network': [
    {
      'origin': origin,
      'methods': ['GET', 'POST'],
      'credential': null,
    },
    {
      'origin': origin,
      'methods': ['GET', 'POST'],
      'credential': 'default',
    },
  ],
};
Map<String, dynamic> presentation() => {
  'title': 'Unrelated application',
  'message': 'Ready',
  'details': '',
  'fields': [],
  'actions': [],
  'columns': [],
  'rows': [],
  'confirmation': null,
};

class Registry extends WasmPluginRegistryService {
  bool installed = true;
  bool network = true;
  bool persistent = true, scheduled = true;
  String digest = 'b' * 64;
  final record = const WasmPluginRecord(
    id: 'package',
    displayName: 'Unrelated application',
    originalFileName: 'app.zip',
    storedFileName: 'app.zip',
    sizeBytes: 100,
    installedAtIso: '2026-11-01T00:00:00Z',
    packageKind: 'zip',
    pluginId: 'example.unrelated',
    pluginVersion: '1.0.0',
    contractKind: pluginWorkspaceContractKind,
    runtimeAbi: 'hivra_host_abi_v2',
    runtimeEntryExport: 'hivra_evaluate_v1',
    runtimeModulePath: 'plugin/module.wasm',
    capabilities: [
      'workspace.render',
      'workspace.continue',
      'workspace.schedule',
      'state.plugin.read_write',
      'network.http',
      'credentials.use',
      'inference.request',
    ],
  );
  @override
  Future<List<WasmPluginRecord>> loadPlugins() async =>
      installed ? [record] : [];
  @override
  Future<PluginRuntimeBinding> resolveRuntimeBinding(String id) async =>
      installed
          ? PluginRuntimeBinding.externalPackage(
            packageId: record.id,
            packageVersion: '1.0.0',
            packageKind: 'zip',
            packageDigestHex: digest,
            contractKind: pluginWorkspaceContractKind,
            capabilities:
                record.capabilities
                    .where(
                      (c) =>
                          (network || c != 'network.http') &&
                          (persistent || c != 'state.plugin.read_write') &&
                          (scheduled || c != 'workspace.schedule'),
                    )
                    .toList(),
          )
          : throw StateError('Package removed');
}

class Fixture {
  final Directory home;
  final CapsuleFileStore files;
  final String origin;
  final registry = Registry();
  String owner = 'a' * 64;
  String? secrets;
  int sends = 0;
  bool newSchema = false, chain = false;
  String requestKind = 'http.request', method = 'POST', url;
  String? credential;
  Map<String, dynamic>? auth;
  Map<String, dynamic> extraRequest = {};
  bool inferenceAllowed = false;
  Future<void> Function(String)? onInvoke;
  Future<Map<String, dynamic>> Function(
    Map<String, dynamic>,
    Future<void> Function(),
  )?
  infer;
  Future<void> Function()? onReadSecrets, onSend;
  final actions = <String>[];
  final settingsSeen = <Map<String, dynamic>>[];
  final received = <Map<String, dynamic>>[];
  Fixture(this.home, this.files, this.origin) : url = '$origin/action';
  static Future<Fixture> create({String origin = 'https://one.example'}) async {
    final home = await Directory.systemTemp.createTemp('hivra_common_api_');
    final f = Fixture(
      home,
      CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      ),
      origin,
    );
    f.secrets = jsonEncode({
      'version': 3,
      'connections': {
        'default': {'token': 'test-token'},
      },
    });
    return f;
  }

  Map<String, dynamic> get schedule => {
    'version': 2,
    if (registry.scheduled) 'action': 'run',
    if (registry.scheduled) 'interval_seconds': 60,
    'description': 'Owner-configured application workflow',
    'access': {...permission(origin), if (inferenceAllowed) 'inference': true},
  };
  Map<String, dynamic> request() => {
    'kind': requestKind,
    'id': 'semantic-effect',
    'continuation': 'finish_custom_operation',
    'url': url,
    'method': method,
    if (credential != null) 'credential': credential,
    if (auth != null) 'auth': auth,
    ...extraRequest,
  };
  PluginWorkspaceRuntime runtime() => PluginWorkspaceRuntime(
    registry: registry,
    infer: infer,
    fileStore: files,
    readActiveCapsuleRootHex: () => owner,
    scheduleTimers: false,
    readCredentials: ({required owner, required pluginId}) async {
      await onReadSecrets?.call();
      return secrets;
    },

    capabilities: PluginCapabilityDispatcher(
      send: (m, u, h, b) async {
        sends++;
        await onSend?.call();
        return {'status': 200, 'body': 'arbitrary service bytes'};
      },
    ),
    pluginHostApi: PluginHostApiService(
      handlers: [],
      resolveRuntimeBinding: registry.resolveRuntimeBinding,
      resolveRuntimeInvoke: (request, binding) async {
        final action = request.args['action'] as String;
        settingsSeen.add(
          Map<String, dynamic>.from(
            request.args['settings'] as Map? ?? const {},
          ),
        );
        actions.add(action);
        await onInvoke?.call(action);
        final state = Map<String, dynamic>.from(
          request.args['state'] as Map? ?? {},
        );
        var requests = <Map<String, dynamic>>[];
        if (action == 'run') {
          state['private_schema'] = {'pending': true};
          requests = [this.request()];
        }
        if (action == 'finish_custom_operation') {
          received.add(
            Map<String, dynamic>.from(request.args['result'] as Map),
          );
          if (chain && received.length == 1) requests = [this.request()];
        }
        if (newSchema && action == 'open') {
          state['entirely_different_shape'] = [state.remove('private_schema')];
        }
        return PluginRuntimeInvokeEvidence(
          mode: 'wasmi_v1',
          modulePath: 'plugin/module.wasm',
          moduleSelection: 'manifest_module_path',
          moduleDigestHex: 'e' * 64,
          invokeDigestHex: 'f' * 64,
          semanticStatus: PluginHostApiStatus.executed,
          semanticErrorCode: null,
          semanticErrorMessage: null,
          semanticResult: {
            'state': registry.persistent ? state : null,
            'context': {'package_selected': 'opaque'},
            'view': {
              ...presentation(),
              'message':
                  received.isEmpty
                      ? 'Ready'
                      : received.last['outcome'] ?? 'accepted',
              if (registry.scheduled) 'schedule': schedule,
            },
            'requests': requests,
          },
        );
      },
    ),
  );
  Future<void> enable() async {
    await runtime().setWorkspaceExecution(
      record: registry.record,
      enabled: true,
      expiresAtMs: DateTime.now().millisecondsSinceEpoch + 3600000,
      approvedScope: schedule,
      credentialBindings: {
        'default': {'token': 'ref-token'},
      },
    );
  }

  Future<Map<String, dynamic>> state() async => Map<String, dynamic>.from(
    jsonDecode(
          (await files.readPluginState(
            await files.capsuleDirForHex('a' * 64),
            registry.record.pluginId!,
            'workspace.v1.json',
          ))!,
        )
        as Map,
  );
  Future<void> changeGrant(void Function(Map<String, dynamic>) edit) async {
    final dir = await files.capsuleDirForHex('a' * 64);
    final g = Map<String, dynamic>.from(
      jsonDecode(
            (await files.readPluginState(
              dir,
              registry.record.pluginId!,
              'workspace-execution.v1.json',
            ))!,
          )
          as Map,
    );
    edit(g);
    await files.writePluginState(
      dir,
      registry.record.pluginId!,
      'workspace-execution.v1.json',
      jsonEncode(g),
    );
  }

  Future<void> close() => home.delete(recursive: true);
}
