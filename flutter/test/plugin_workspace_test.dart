import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/screens/plugin_workspace_screen.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';
import 'package:hivra_app/services/capsule_contact_label_store.dart';
import 'package:hivra_app/services/capsule_passive_receive_coordinator.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';
import 'package:hivra_app/services/consensus_attestation_exchange_service.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';
import 'package:hivra_app/services/plugin_capability_dispatcher.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_runtime_module_service.dart';
import 'package:hivra_app/services/plugin_workspace_remote_service.dart';
import 'package:hivra_app/services/plugin_workspace_runtime.dart';
import 'package:hivra_app/services/ui_event_log_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_source_catalog_service.dart';

import '../bin/plugin_workspace_runner.dart';

void main() {
  testWidgets(
    'failed first open keeps confirmed return reachable and never starts execution',
    (tester) async {
      var returned = false;
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (action, settings) async {
              actions.add(action);
              if (!returned) throw StateError('Previous installation replaced');
              return presentation();
            },
            useOnline: () async {
              returned = true;
            },
            connectVps: ({
              required host,
              required port,
              required password,
              required trustPeer,
            }) async {
              fail('Cancelling reconnection must not change the VPS');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect VPS'));
      await tester.pumpAndSettle();
      expect(find.text('Connect your VPS'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(actions, ['open']);
      await tester.tap(find.text('Recover local access'));
      await tester.pumpAndSettle();
      expect(returned, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(returned, isFalse);
      await tester.tap(find.text('Recover local access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return to online'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(find.text('Unrelated application'), findsOneWidget);
      expect(actions, ['open', 'open']);
      expect(find.text('Recover local access'), findsNothing);
    },
  );

  test(
    'old device returns only its sealed handoff through the normal module',
    () async {
      final f = await Fixture.create();
      final serverFiles = await Fixture.create();
      try {
        await f.enable();
        final local = f.runtime();
        final checkpoint = await local.releaseWorkspaceToVps(
          f.registry.record,
          executorId: 'e' * 64,
        );
        final directory = await serverFiles.files.capsuleDirForHex(
          f.owner,
          create: true,
        );
        await serverFiles.files.restorePluginCheckpoint(
          directory,
          f.registry.record.pluginId!,
          {
            'workspace-execution.v1.json': jsonEncode(checkpoint['execution']),
            if (checkpoint['workspace'] != null)
              'workspace.v1.json': checkpoint['workspace'] as String,
          },
        );
        final root =
            await UserVisibleDataDirectoryService(
              homeOverride: serverFiles.home.path,
            ).rootDirectory();
        final oldBinding = {
          'owner': f.owner,
          'plugin_id': f.registry.record.pluginId,
          'package_id': 'old-server-package',
          'package_digest': f.registry.digest,
          'executor_id': 'e' * 64,
        };
        final newBinding = {
          ...oldBinding,
          'owner': 'c' * 64,
          'package_id': serverFiles.registry.record.id,
          'executor_id': 'f' * 64,
        };
        serverFiles.owner = newBinding['owner']!;
        await serverFiles.enable();
        final currentDirectory = await serverFiles.files.capsuleDirForHex(
          serverFiles.owner,
        );
        final currentGrant = await serverFiles.files.readPluginState(
          currentDirectory,
          serverFiles.registry.record.pluginId!,
          'workspace-execution.v1.json',
        );
        final runner = WorkspaceRunner(
          root: root,
          registry: serverFiles.registry,
          binding: newBinding,
          runtime: WorkspaceRunner.runtimeFor(
            root,
            newBinding,
            serverFiles.registry,
            scheduleTimers: false,
          ),
        );
        await expectLater(
          runner.dispatch({...oldBinding, 'command': 'status'}),
          throwsStateError,
        );
        final request = {
          ...oldBinding,
          'command': 'return',
          'handoff_id': checkpoint['execution']['handoff_id'],
        };
        // A stale device cannot end an active grant, even with its handoff ID.
        await expectLater(runner.dispatch(request), throwsStateError);
        final prior = WorkspaceRunner.runtimeFor(
          root,
          oldBinding,
          serverFiles.registry,
          scheduleTimers: false,
        );
        await prior.returnWorkspaceToLocal(serverFiles.registry.record);
        final sealed = await serverFiles.files.readPluginState(
          directory,
          f.registry.record.pluginId!,
          'workspace-execution.v1.json',
        );
        await expectLater(
          runner.dispatch({...request, 'handoff_id': '9' * 64}),
          throwsStateError,
        );
        await expectLater(
          runner.dispatch({...request}..remove('handoff_id')),
          throwsFormatException,
        );
        await expectLater(
          runner.dispatch({...request, 'owner': '9' * 64}),
          throwsStateError,
        );
        expect(
          await (await serverFiles.files.capsuleDirForHex('9' * 64)).exists(),
          isFalse,
        );
        final c = {
          ...oldBinding,
          'host': 'server.example',
          'port': 22,
          'fingerprint': 'SHA256:${'A' * 43}',
          'selected': true,
        };
        final dir = await f.files.capsuleDirForHex(f.owner);
        await f.files.writePluginState(
          dir,
          f.registry.record.pluginId!,
          PluginWorkspaceRemoteService.connectionFile,
          jsonEncode(c),
        );
        final calls = <String>[];
        var removeDuringReturn = false;
        final unused = UnusedWorkspacePorts();
        final remote = PluginWorkspaceRemoteService(
          files: f.files,
          vault: unused,
          registry: f.registry,
          requestTransport: (_, command, payload) async {
            expect(command, 'request');
            final input = Map<String, dynamic>.from(
              jsonDecode(utf8.decode(payload)) as Map,
            );
            calls.add(input['command'] as String);
            final result = await runner.dispatch(input);
            if (removeDuringReturn && input['command'] == 'return') {
              f.registry.installed = false;
            }
            return jsonEncode({'ok': true, 'result': result});
          },
        );
        final module = PluginRuntimeModule(
          registry: f.registry,
          sourceCatalog: const WasmPluginSourceCatalogService(),
          manualChecks: unused,
          pluginHostApi: local.pluginHostApi,
          attestationExchange: unused,
          chatDelivery: unused,
          passiveReceive: unused,
          contactLabels: unused,
          uiLog: unused,
          fileStore: f.files,
          secretVault: unused,
          readActiveCapsuleRootHex: () => f.owner,
          workspaceRemote: remote,
        );
        await expectLater(
          module.runWorkspaceAction(record: f.registry.record, action: 'open'),
          throwsStateError,
        );
        removeDuringReturn = true;
        await expectLater(
          module.useWorkspaceOnline(f.registry.record),
          throwsStateError,
        );
        f.registry.installed = true;
        removeDuringReturn = false;
        expect(
          (await local.readWorkspaceExecution(
            f.registry.record,
            enforceHost: false,
          ))!['executor'],
          'vps',
        );
        await module.useWorkspaceOnline(f.registry.record);
        final reopened = await module.runWorkspaceAction(
          record: f.registry.record,
          action: 'open',
        );
        expect(reopened['host_connection']['target'], 'local');
        expect(reopened['execution']['active'], isFalse);
        expect(reopened['execution']['running'], isFalse);
        expect(
          (await remote.connection(
            f.owner,
            f.registry.record.pluginId!,
          ))!['selected'],
          isFalse,
        );
        expect(calls, ['adopt', 'return', 'return']);
        expect(f.sends, 0);
        expect(
          await serverFiles.files.readPluginState(
            directory,
            f.registry.record.pluginId!,
            'workspace-execution.v1.json',
          ),
          sealed,
        );
        expect(
          await serverFiles.files.readPluginState(
            currentDirectory,
            serverFiles.registry.record.pluginId!,
            'workspace-execution.v1.json',
          ),
          currentGrant,
        );
        await module.useWorkspaceOnline(f.registry.record);
        expect(calls, ['adopt', 'return', 'return']);

        // A runtime update may install a new package while this owner's old
        // sealed receipt still names the previous digest. A fresh authorized
        // Start must retain those bytes, not treat the destination as empty.
        serverFiles.registry.digest = 'd' * 64;
        final retained = '{"package_owned":{"unresolved":"keep"}}';
        await serverFiles.files.writePluginState(
          directory,
          f.registry.record.pluginId!,
          'workspace.v1.json',
          retained,
        );
        serverFiles.owner = f.owner;
        final nextRuntime = serverFiles.runtime(
          executionHost: 'vps',
          executionIdentity: oldBinding['executor_id'],
        );
        final nextCheckpoint = {
          ...checkpoint,
          'package_digest': serverFiles.registry.digest,
          'execution': {
            ...checkpoint['execution'] as Map,
            'package_digest': serverFiles.registry.digest,
            'handoff_id': '8' * 64,
            'scope': {
              ...checkpoint['execution']['scope'] as Map,
              'start_action': 'begin_owner_workflow',
            },
          },
          'workspace': '{"new_shape":["stale device copy"]}',
        };
        final starting = Completer<void>(), releaseStart = Completer<void>();
        serverFiles.onInvoke = (action) async {
          if (action == 'begin_owner_workflow') {
            starting.complete();
            await releaseStart.future;
          }
        };
        final firstAdoption = nextRuntime.adoptWorkspaceFromLocal(
          record: serverFiles.registry.record,
          checkpoint: nextCheckpoint,
        );
        await starting.future;
        var replayAcknowledged = false;
        final replay = nextRuntime
            .adoptWorkspaceFromLocal(
              record: serverFiles.registry.record,
              checkpoint: nextCheckpoint,
            )
            .then((_) => replayAcknowledged = true);
        await Future<void>.delayed(Duration.zero);
        expect(replayAcknowledged, isFalse);
        releaseStart.complete();
        await Future.wait([firstAdoption, replay]);
        expect(
          serverFiles.actions.where((a) => a == 'begin_owner_workflow'),
          hasLength(1),
        );
        expect(
          await serverFiles.files.readPluginState(
            directory,
            f.registry.record.pluginId!,
            'workspace.v1.json',
          ),
          retained,
        );
        final adopted = await nextRuntime.readWorkspaceExecution(
          serverFiles.registry.record,
        );
        expect(adopted!['handoff_id'], '8' * 64);
        expect(adopted['package_digest'], serverFiles.registry.digest);
        await nextRuntime.returnWorkspaceToLocal(serverFiles.registry.record);
        serverFiles.onInvoke = (action) async {
          if (action == 'begin_owner_workflow') {
            throw StateError('Start failed');
          }
        };
        final failedCheckpoint = {
          ...nextCheckpoint,
          'execution': {
            ...nextCheckpoint['execution'] as Map,
            'handoff_id': '9' * 64,
          },
        };
        await expectLater(
          nextRuntime.adoptWorkspaceFromLocal(
            record: serverFiles.registry.record,
            checkpoint: failedCheckpoint,
          ),
          throwsStateError,
        );
        final failed = await nextRuntime.readWorkspaceExecution(
          serverFiles.registry.record,
        );
        expect(failed!['revoked'], isTrue);
        expect(failed['enabled'], isFalse);
        await nextRuntime.adoptWorkspaceFromLocal(
          record: serverFiles.registry.record,
          checkpoint: failedCheckpoint,
        );
        expect(
          serverFiles.actions.where((a) => a == 'begin_owner_workflow'),
          hasLength(2),
        );
      } finally {
        await f.close();
        await serverFiles.close();
      }
    },
  );

  test(
    'Start wakes the package immediately; observation never starts a second cycle',
    () async {
      final f = await Fixture.create();
      final runtime = f.runtime(scheduleTimers: true);
      addTearDown(() async {
        runtime.stopWorkspaceScheduling(permanently: true);
        await f.close();
      });
      final permissions =
          {...f.schedule}
            ..remove('action')
            ..remove('interval_seconds');
      await runtime.setWorkspaceExecution(
        record: f.registry.record,
        enabled: true,
        expiresAtMs: null,
        approvedScope: permissions,
        credentialBindings: {
          'default': {'token': 'ref-token'},
        },
      );
      expect(f.sends, 0);
      final finished = Completer<void>();
      f.onInvoke = (action) async {
        if (action == 'finish_custom_operation') finished.complete();
      };
      await runtime.setWorkspaceExecution(
        record: f.registry.record,
        enabled: true,
        expiresAtMs: null,
        expectedRevision: 1,
        approvedScope: {...f.schedule, 'interval_seconds': 1800},
      );
      await finished.future.timeout(const Duration(seconds: 2));
      final observed = await runtime.runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
      );
      expect(observed['execution']['last_result'], 'response');
      expect(f.sends, 1);
      runtime.stopWorkspaceScheduling();
      await runtime.resumeWorkspaceScheduling(f.registry.record);
      await runtime.runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
      );
      // Give a zero-delay wake an opportunity to run: restoration must retain
      // the interval rather than treating process/UI recovery as a new Start.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(f.actions.where((action) => action == 'run'), hasLength(1));
      expect(f.sends, 1);
      expect(
        (await runtime.readWorkspaceExecution(f.registry.record))!['revision'],
        2,
      );
    },
  );

  test(
    'immediate Start still checks revocation and package replacement before dispatch',
    () async {
      for (final replace in [false, true]) {
        final f = await Fixture.create();
        final runtime = f.runtime(scheduleTimers: true);
        final entered = Completer<void>();
        final release = Completer<void>();
        f.onInvoke = (action) async {
          if (action == 'run') {
            entered.complete();
            await release.future;
          }
        };
        try {
          await runtime.setWorkspaceExecution(
            record: f.registry.record,
            enabled: true,
            expiresAtMs: null,
            approvedScope: f.schedule,
            credentialBindings: {
              'default': {'token': 'ref-token'},
            },
          );
          await entered.future.timeout(const Duration(seconds: 2));
          Future<Map<String, dynamic>>? stopped;
          if (replace) {
            f.registry.digest = 'c' * 64;
          } else {
            stopped = runtime.setWorkspaceExecution(
              record: f.registry.record,
              enabled: false,
              revoke: true,
              expiresAtMs: null,
            );
            for (var i = 0; i < 100; i++) {
              if ((await runtime.readWorkspaceExecution(
                    f.registry.record,
                  ))?['revoked'] ==
                  true) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            expect(
              (await runtime.readWorkspaceExecution(
                f.registry.record,
              ))?['revoked'],
              true,
            );
          }
          release.complete();
          await stopped;
          // The serialized read waits for the interrupted first cycle to end.
          await runtime.runWorkspaceAction(
            record: f.registry.record,
            action: 'open',
          );
          expect(f.sends, 0);
        } finally {
          if (!release.isCompleted) release.complete();
          runtime.stopWorkspaceScheduling(permanently: true);
          await f.close();
        }
      }
    },
  );

  test(
    'remote Start uses one setup with the new selection; revoked Start sends no setup',
    () async {
      for (final fault in ['none', 'secret', 'stale']) {
        final revoke = fault != 'none';
        final f = await Fixture.create();
        try {
          final bytes = utf8.encode('synthetic package transport');
          final package = File('${f.home.path}/package.zip');
          await package.writeAsBytes(bytes);
          f.registry.packagePath = package.path;
          f.registry.digest = sha256.convert(bytes).toString();
          await f.enable();
          await f.changeGrant((g) {
            g['executor'] = 'vps';
            g['executor_id'] = 'e' * 64;
            g['handoff_id'] = 'd' * 64;
          });
          final dir = await f.files.capsuleDirForHex(f.owner);
          final connection = {
            'owner': f.owner,
            'plugin_id': f.registry.record.pluginId,
            'executor_id': 'f' * 64,
            'host': 'server.example',
            'port': 22,
            'fingerprint': 'SHA256:${'A' * 43}',
            'selected': true,
            'package_id': 'previous-server-package',
            'package_digest': 'c' * 64,
          };
          await f.files.writePluginState(
            dir,
            f.registry.record.pluginId!,
            PluginWorkspaceRemoteService.connectionFile,
            jsonEncode(connection),
          );
          final calls = <String>[];
          final binding = {...connection}..removeWhere(
            (key, _) =>
                ![
                  'owner',
                  'plugin_id',
                  'executor_id',
                  'package_id',
                  'package_digest',
                ].contains(key),
          );
          binding['package_id'] = 'new-server-package';
          binding['package_digest'] = f.registry.digest;
          final unused = UnusedWorkspacePorts();
          if (fault == 'secret') {
            unused.beforeResolve =
                () => f.changeGrant((g) {
                  g['enabled'] = false;
                  g['revision']++;
                });
          }
          final remote = PluginWorkspaceRemoteService(
            files: f.files,
            vault: unused,
            registry: f.registry,
            requestTransport: (c, command, payload) async {
              final body = jsonDecode(utf8.decode(payload)) as Map;
              calls.add(
                command == 'request' ? body['command'] as String : command,
              );
              if (command == 'setup') {
                expect(body['checkpoint']['execution']['settings'], {
                  'selection': 'new-choice',
                });
                expect(
                  body['checkpoint']['execution']['executor_id'],
                  'f' * 64,
                );
                return jsonEncode(binding);
              }
              return jsonEncode({
                'ok': true,
                'result': {
                  'binding': binding,
                  'runner': {'state': 'running', 'execution_controls': 4},
                  'view': {
                    ...presentation(),
                    'execution': {
                      'mode': 'vps',
                      'active': true,
                      'running': true,
                    },
                  },
                },
              });
            },
          );
          await remote.connect(
            owner: f.owner,
            record: f.registry.record,
            host: 'server.example',
            port: 22,
            password: '',
            trustPeer:
                (_) async => throw StateError('Saved pin must not be replaced'),
            stillOwned: () => true,
          );
          expect(
            calls,
            isEmpty,
            reason: 'Selecting a saved VPS must not control its prior runner',
          );
          final module = PluginRuntimeModule(
            registry: f.registry,
            sourceCatalog: const WasmPluginSourceCatalogService(),
            manualChecks: unused,
            pluginHostApi: f.runtime().pluginHostApi,
            attestationExchange: unused,
            chatDelivery: unused,
            passiveReceive: unused,
            contactLabels: unused,
            uiLog: unused,
            fileStore: f.files,
            secretVault: unused,
            readActiveCapsuleRootHex: () => f.owner,
            workspaceRemote: remote,
          );
          if (fault == 'stale') {
            await f.changeGrant((g) {
              g['enabled'] = false;
              g['revision']++;
            });
          }
          final operation = module.setWorkspaceExecution(
            record: f.registry.record,
            enabled: true,
            expiresAtMs: null,
            expectedRevision: 1,
            approvedScope: {
              ...f.schedule,
              'start_action': 'begin_owner_workflow',
            },
            settings: const {'selection': 'new-choice'},
          );
          if (revoke) {
            await expectLater(operation, throwsStateError);
            expect(calls, isEmpty);
          } else {
            final view = await operation;
            expect(view['host_connection']['target'], 'vps');
            expect(calls.first, 'setup');
            expect(calls, isNot(contains('action')));
            expect(calls, isNot(contains('execution')));
          }
          expect(f.sends, 0);
        } finally {
          await f.close();
        }
      }
    },
  );

  testWidgets(
    'remote Start replaces execution with the selected settings without sending Start to the old runner',
    (tester) async {
      final actions = <String>[];
      Map<String, dynamic>? selected;
      final access = permission('https://one.example');
      final scope = {
        'version': 2,
        'action': 'run',
        'interval_seconds': 60,
        'description': 'Owner workflow',
        'access': access,
      };
      Map<String, dynamic> view() => {
        ...presentation(),
        'fields': [
          {
            'id': 'selection',
            'type': 'text',
            'label': 'Selection',
            'value': 'old-choice',
          },
        ],
        'actions': [
          {'id': 'start', 'label': 'Start', 'host': 'workspace.start'},
        ],
        'schedule': scope,
        'execution': {
          'mode': 'vps',
          'enabled': true,
          'active': true,
          'running': true,
          'revision': 1,
          'expires_at_ms': null,
          'access': access,
          'credentials': {
            'default': {'token': 'ref-token'},
          },
        },
        'host_connection': {
          'target': 'vps',
          'selected': true,
          'host': 'server.example',
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (action, settings) async {
              actions.add(action);
              if (actions.length > 1) {
                throw const SocketException('Old executor unavailable');
              }
              return view();
            },
            configureExecution: ({
              required enabled,
              required expiresAtMs,
              expectedRevision,
              revoke = false,
              approvedScope,
              credentialBindings,
              settings = const {},
            }) async {
              selected = settings;
              return view();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new-choice');
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(actions, ['open', 'open']);
      expect(selected, {'selection': 'new-choice'});
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'scheduled package result remains visible beside fresh observations',
    (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction:
                (_, _) async => {
                  ...presentation(),
                  'message': 'Fresh observation ${++opens}',
                  'execution': {
                    'active': true,
                    'enabled': true,
                    'running': true,
                    'last_checked_at_ms': 1793750978108,
                    'last_result':
                        'Stopped: provider rejected content; nothing sent',
                  },
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Last cycle result'));
      expect(
        find.text('Stopped: provider rejected content; nothing sent'),
        findsOneWidget,
      );
      expect(find.textContaining('Last completed cycle:'), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(opens, greaterThan(1));
      expect(
        find.text('Stopped: provider rejected content; nothing sent'),
        findsOneWidget,
      );
      expect(find.textContaining('Last successful cycle:'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'selected but unacknowledged VPS cannot relabel local execution',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      final directory = await f.files.capsuleDirForHex('a' * 64);
      await f.files.writePluginState(
        directory,
        f.registry.record.pluginId!,
        PluginWorkspaceRemoteService.connectionFile,
        jsonEncode({
          'owner': 'a' * 64,
          'plugin_id': f.registry.record.pluginId,
          'host': 'server.example',
          'port': 22,
          'fingerprint': 'SHA256:${'A' * 43}',
          'executor_id': 'e' * 64,
          'package_id': null,
          'package_digest': null,
          'selected': true,
        }),
      );
      final unused = UnusedWorkspacePorts();
      final module = PluginRuntimeModule(
        registry: f.registry,
        sourceCatalog: const WasmPluginSourceCatalogService(),
        manualChecks: unused,
        pluginHostApi: f.runtime().pluginHostApi,
        attestationExchange: unused,
        chatDelivery: unused,
        passiveReceive: unused,
        contactLabels: unused,
        uiLog: unused,
        fileStore: f.files,
        secretVault: unused,
        readActiveCapsuleRootHex: () => f.owner,
      );
      final view = await module.runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
      );
      expect(view['execution']['mode'], 'local');
      expect(view['execution']['running'], isTrue);
      expect(view['host_connection']['target'], 'local');
      expect(view['host_connection']['selected'], isTrue);
      expect(view['host_connection']['health'], 'setup_unconfirmed');
      expect(f.sends, 0);
    },
  );

  testWidgets(
    'failed VPS connection retains the local workflow without relabelling execution',
    (tester) async {
      var opens = 0, connections = 0;
      final busy = StateError('Synthetic connection failure');
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (action, settings) async {
              opens++;
              return {
                ...presentation(),
                'execution': {'mode': 'local', 'running': true, 'active': true},
                'host_connection': {
                  'target': 'local',
                  'selected': true,
                  'host': 'server.example',
                  'port': 22,
                  'installed': false,
                  'health': 'setup_unconfirmed',
                },
              };
            },
            connectVps: ({
              required host,
              required port,
              required password,
              required trustPeer,
            }) async {
              connections++;
              throw busy;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('On this device · keep the app open'), findsOneWidget);
      expect(find.textContaining('VPS execution ·'), findsNothing);
      expect(find.textContaining('Setup not confirmed'), findsOneWidget);
      final connect = find.text('Connect VPS');
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate((w) => w is TextField && w.obscureText),
        'synthetic-test-password',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect securely'));
      await tester.pumpAndSettle();
      expect(connections, 1);
      expect(
        find.textContaining('VPS connection was not completed'),
        findsOneWidget,
      );
      final observedOpens = opens;
      await tester.pump(const Duration(seconds: 61));
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(
        find.textContaining('VPS connection was not completed'),
        findsOneWidget,
      );
      expect(opens, observedOpens);
      expect(find.textContaining('VPS execution ·'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'scheduled observation preserves owner draft edits until an explicit package action',
    (tester) async {
      final actions = <String>[];
      Map<String, dynamic>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (action, settings) async {
              actions.add(action);
              if (action == 'apply') submitted = settings;
              return {
                ...presentation(),
                'execution': {'active': true, 'enabled': true, 'running': true},
                'fields': [
                  {
                    'id': 'limit',
                    'label': 'Owner limit',
                    'type': 'number',
                    'value': 1,
                  },
                ],
                'actions': [
                  {'id': 'apply', 'label': 'Apply choice'},
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('plugin-field-limit'));
      await tester.enterText(field, '2.5');
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(actions.where((a) => a == 'open').length, greaterThan(1));
      expect(tester.widget<TextField>(field).controller!.text, '2.5');
      expect(submitted, isNull);
      await tester.tap(find.byKey(const ValueKey('plugin-action-apply')));
      await tester.pumpAndSettle();
      expect(submitted?['limit'], 2.5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'workspace keeps status readable and submits edited inputs on narrow and wide screens',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(360, 780), const Size(1280, 900)]) {
        await tester.binding.setSurfaceSize(size);
        var limit = 1.0;
        Map<String, dynamic>? submitted;
        Map<String, dynamic> view() => {
          ...presentation(),
          'summary': 'Owner connection · saved settings',
          'message':
              'Current observation\nThe external result remains unverified.',
          'fields': [
            {
              'id': 'asset',
              'label': 'Instrument',
              'type': 'text',
              'value': 'EXAMPLE',
            },
            {
              'id': 'limit',
              'label': 'Owner limit',
              'type': 'number',
              'value': limit,
            },
            {'id': 'budget', 'label': 'Budget', 'type': 'number', 'value': 20},
          ],
          'actions': [
            {'id': 'refresh', 'label': 'Refresh observation'},
            {'id': 'other', 'label': 'Other action'},
          ],
          'execution': {
            'active': false,
            'enabled': false,
            'running': false,
            'expires_at_ms': null,
          },
        };
        await tester.pumpWidget(
          MaterialApp(
            home: PluginWorkspaceScreen(
              key: ValueKey(size),
              capabilities: const ['workspace.schedule'],
              runWorkspaceAction: (action, settings) async {
                if (action == 'refresh') {
                  submitted = settings;
                  limit = (settings['limit'] as num).toDouble();
                }
                return view();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(find.text('Current status')).dy,
          lessThan(tester.getTopLeft(find.text('Configuration')).dy),
        );
        final field = find.byKey(const ValueKey('plugin-field-limit'));
        await tester.ensureVisible(field);
        await tester.enterText(field, '1.25');
        await tester.pumpAndSettle();
        expect(find.text('Current observation'), findsOneWidget);
        expect(
          find.text(
            'Changes not applied. The observation below uses the previous settings.',
          ),
          findsOneWidget,
        );
        final action = find.byKey(const ValueKey('plugin-action-refresh'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(submitted?['limit'], 1.25);
        expect(find.text('Current observation'), findsOneWidget);
        expect(find.text('Current status'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'inactive or unavailable access never claims authorization until revocation',
    (tester) async {
      for (final active in [false, null, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: PluginWorkspaceScreen(
              key: ValueKey(active),
              capabilities: const ['workspace.schedule'],
              runWorkspaceAction:
                  (_, _) async => {
                    ...presentation(),
                    'execution': {
                      'active': active,
                      'enabled': active,
                      'running': false,
                      'expires_at_ms': null,
                    },
                  },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final text = find.textContaining(
          active == true
              ? 'Permissions active'
              : active == false
              ? 'Permissions inactive'
              : 'Permission status unavailable',
        );
        await tester.ensureVisible(text);
        expect(text, findsOneWidget);
        expect(
          find.textContaining('Until you revoke access.'),
          active == true ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

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
        f.credential = 'default';
        f.auth = {
          'headers': {
            'Authorization': {'field': 'token', 'prefix': 'Bearer '},
          },
        };
        var credentialReads = 0;
        f.onReadSecrets = () async {
          credentialReads++;
        };
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
        expect(credentialReads, 0, reason: fault);
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
        f.extraRequest = {
          'response_json_paths': {
            'value': ['data', 'value'],
          },
        };
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

  test(
    'missing inference permission never opens the provider credential port',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.requestKind = 'ai.infer';
      await f.enable();
      var credentialOpens = 0;
      f.infer = (request, authorize) async {
        credentialOpens++;
        await authorize();
        return {'outcome': 'response', 'text': 'Must not reach inference'};
      };
      await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'run',
      );
      expect(credentialOpens, 0);
      expect(f.received.single['outcome'], 'not_dispatched');
    },
  );
  testWidgets(
    'explicit package results and failures survive polling and app resume until reopening',
    (tester) async {
      for (final (running, fails) in [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
      ]) {
        final actions = <String>[];
        Widget screen() => MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (action, settings) async {
              actions.add(action);
              if (action == 'calculate' && fails) {
                throw StateError('Calculation unavailable');
              }
              return {
                ...presentation(),
                'message':
                    action == 'calculate' ? 'Computed proposal' : 'Ready',
                'execution': {'enabled': true, 'running': running},
                'actions': [
                  {'id': 'calculate', 'label': 'Calculate'},
                ],
              };
            },
          ),
        );
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Calculate'));
        await tester.pumpAndSettle();
        final result = find.textContaining(
          fails ? 'Calculation unavailable' : 'Computed proposal',
        );
        expect(result, findsOneWidget);
        await tester.pump(const Duration(seconds: 16));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(result, findsOneWidget);
        expect(actions, ['open', 'calculate']);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        expect(find.text('Ready'), findsOneWidget);
        expect(actions, ['open', 'calculate', 'open']);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'permission form identifies an incomplete credential without exposing values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final access = permission('https://unrelated.example');
      access['credentials'] = {
        'default': [
          {'id': 'request', 'label': 'Request key'},
          {'id': 'signing', 'label': 'Signing key'},
        ],
      };
      var writes = 0, grants = 0;
      Map<String, dynamic> view() => {
        ...presentation(),
        'access': access,
        'actions': [
          {'id': 'link', 'label': 'Connect', 'host': 'workspace.authorize'},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['credentials.use'],
            listSecrets: () async => [],
            saveSecrets: (secrets) async {
              writes++;
              return [
                for (var i = 0; i < secrets.length; i++)
                  {'id': 'ref-$i', 'label': secrets[i]['label']!},
              ];
            },
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
              expect(credentialBindings, {
                'default': {'request': 'ref-0', 'signing': 'ref-1'},
              });
              return view();
            },
            runWorkspaceAction: (action, settings) async => view(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      final issue = find.byKey(const ValueKey('plugin-permission-issue'));
      final confirm = find.byKey(const ValueKey('plugin-confirm-permissions'));
      for (final id in ['request', 'signing']) {
        final picker = find.byKey(ValueKey('plugin-secret-default-$id'));
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add new secret…').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(ValueKey('plugin-secret-value-default-$id')),
          'test-private-$id',
        );
        await tester.pumpAndSettle();
      }
      // Both values can be present while a separate name is incomplete.
      final name = find.byKey(
        const ValueKey('plugin-secret-name-default-request'),
      );
      await tester.enterText(name, '');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(tester.widget<Text>(issue).data, contains('Request key'));
      expect(tester.widget<Text>(issue).data, isNot(contains('test-private')));
      expect(writes, 0);
      expect(grants, 0);
      await tester.enterText(name, 'Request key');
      await tester.pumpAndSettle();
      expect(issue, findsNothing);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(grants, 1);
    },
  );
  testWidgets(
    'first connection stores only on Allow, passes references, and fails without a grant',
    (tester) async {
      for (final outcome in ['allow', 'cancel', 'fail', 'leave']) {
        var writes = 0, grants = 0;
        final pending = Completer<List<Map<String, String>>>();
        Map<String, Map<String, String>>? connected;
        final access = permission('https://unrelated.example');
        Map<String, dynamic> view() => {
          ...presentation(),
          'access': access,
          'actions': [
            {'id': 'link', 'label': 'Connect', 'host': 'workspace.authorize'},
          ],
        };
        await tester.pumpWidget(
          MaterialApp(
            home: PluginWorkspaceScreen(
              key: ValueKey(outcome),
              capabilities: const ['credentials.use'],
              listSecrets: () async => [],
              saveSecrets: (secrets) async {
                writes++;
                expect(secrets, [
                  {'label': 'My service', 'value': 'test-only-secret'},
                ]);
                if (outcome == 'fail') {
                  throw StateError('Secure storage unavailable');
                }
                if (outcome == 'leave') return pending.future;
                return [
                  {'id': 'new-owner-ref', 'label': 'My service'},
                ];
              },
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
                connected = credentialBindings;
                expect(
                  jsonEncode(settings),
                  isNot(contains('test-only-secret')),
                );
                expect(
                  jsonEncode(approvedScope),
                  isNot(contains('test-only-secret')),
                );
                return view();
              },
              runWorkspaceAction: (action, settings) async {
                expect(
                  jsonEncode(settings),
                  isNot(contains('test-only-secret')),
                );
                return view();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('plugin-confirm-permissions')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(
          find.byKey(const ValueKey('plugin-secret-default-token')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add new secret…').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('plugin-secret-name-default-token')),
          'My service',
        );
        await tester.enterText(
          find.byKey(const ValueKey('plugin-secret-value-default-token')),
          'test-only-secret',
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(
                    const ValueKey('plugin-secret-value-default-token'),
                  ),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isTrue,
        );
        await tester.pumpAndSettle();
        final button = find.text(outcome == 'cancel' ? 'Cancel' : 'Allow');
        await tester.ensureVisible(button);
        await tester.tap(button);
        if (outcome == 'leave') {
          await tester.pump();
          await tester.pumpWidget(const SizedBox());
          pending.complete([
            {'id': 'late-ref', 'label': 'My service'},
          ]);
        }
        await tester.pumpAndSettle();
        expect(writes, outcome == 'cancel' ? 0 : 1);
        expect(grants, outcome == 'allow' ? 1 : 0);
        if (outcome == 'allow') {
          expect(connected, {
            'default': {'token': 'new-owner-ref'},
          });
        }
        if (outcome == 'fail') {
          expect(
            find.textContaining('Secure storage unavailable'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'one owner grant connects Keychain references and Start reuses it',
    (tester) async {
      final access = permission('https://one.example');
      var grants = 0, starts = 0, opens = 0, secretPickers = 0, connections = 0;
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
            listSecrets: () async {
              secretPickers++;
              return [
                {'id': 'ref-token', 'label': 'Service / account / token'},
              ];
            },
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
              if (action == 'link') connections++;
              if (action == 'start') starts++;
              if (action == 'open') opens++;
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
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(connections, 2);
      expect(secretPickers, 1);
      expect(grants, 1);
      expect(find.text('Allow'), findsNothing);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(grants, 2);
      expect(find.text('Allow'), findsNothing);
      final beforePolling = opens;
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(opens, beforePolling + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'choice source requests only its declared access and cancellation never loads choices',
    (tester) async {
      final readAccess = {
        'version': 2,
        'network': [
          {
            'origin': 'https://catalog.example',
            'methods': ['GET'],
            'credential': null,
          },
        ],
        'credentials': <String, dynamic>{},
      };
      var loads = 0;
      var grants = 0;
      Map<String, dynamic>? execution = {
        'enabled': false,
        'active': false,
        'running': false,
        'revoked': true,
        'scope': {
          'version': 2,
          'action': 'cycle',
          'interval_seconds': 60,
          'description': 'Previously authorized workflow',
          'access': readAccess,
        },
      };
      Map<String, dynamic> view() => {
        ...presentation(),
        if (execution != null) 'execution': execution,
        'fields': [
          {
            'id': 'destination',
            'type': 'choice',
            'label': 'Destination',
            'value': 'alpha',
            'source': {'action': 'catalog', 'access': readAccess},
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            listSecrets:
                () async =>
                    throw StateError('Public choices must not open the vault'),
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
              expect(approvedScope!['access'], readAccess);
              expect(approvedScope['action'], isNull);
              expect(credentialBindings, isEmpty);
              execution = {
                'enabled': true,
                'active': true,
                'running': false,
                'access': readAccess,
                'credentials': {},
                'revision': grants,
              };
              return view();
            },
            runWorkspaceAction: (action, settings) async {
              if (action == 'catalog') loads++;
              return {
                ...view(),
                if (action == 'catalog') 'options': ['alpha', 'beta'],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plugin-field-destination')));
      await tester.pumpAndSettle();
      expect(loads, 0);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(grants, 0);
      await tester.tap(find.byKey(const ValueKey('plugin-field-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      await tester.tap(find.widgetWithText(ListTile, 'beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plugin-field-destination')));
      await tester.pumpAndSettle();
      expect(grants, 1);
      expect(loads, 2);
      expect(find.text('Allow'), findsNothing);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a choice asks the package-selected action through the common executor',
    (tester) async {
      final actions = <String>[];
      var destination = 'alpha';
      Map<String, dynamic>? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            runWorkspaceAction: (action, settings) async {
              actions.add(action);
              if (action == 'apply') {
                applied = settings;
                destination = settings['destination'] as String;
              }
              return {
                ...presentation(),
                'fields': [
                  {
                    'id': 'destination',
                    'type': 'choice',
                    'label': 'Destination',
                    'value': destination,
                    'source': {'action': 'list_destinations'},
                  },
                ],
                'actions': [
                  {'id': 'apply', 'label': 'Apply destination'},
                ],
                if (action == 'list_destinations')
                  'options': [
                    'alpha',
                    'beta',
                    for (var i = 0; i < 1100; i++) 'item-$i',
                  ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plugin-field-destination')));
      await tester.pumpAndSettle();
      expect(actions, ['open', 'list_destinations']);
      await tester.enterText(
        find.byKey(const ValueKey('plugin-choice-search')),
        'beta',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'beta'));
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsOneWidget);
      expect(applied, isNull);
      await tester.tap(find.byKey(const ValueKey('plugin-action-apply')));
      await tester.pumpAndSettle();
      expect(applied?['destination'], 'beta');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'HTTP JSON paths select nested arrays without interpreting service success',
    () async {
      for (final paths in [
        null,
        {
          'failure': ['fault'],
          'names': ['items', '*', 'name'],
        },
        {
          'first': ['items', '0', 'value'],
          'absent': ['missing'],
        },
      ]) {
        final dispatcher = PluginCapabilityDispatcher(
          send:
              (m, u, h, b) async => {
                'status': 422,
                'headers': {'Content-Length': '999', 'X-Service': 'fixture'},
                'body': jsonEncode({
                  'fault': 'rejected',
                  'items': [
                    {'name': 'A', 'value': 3, 'unused': 'x' * 70000},
                    {'name': 'B', 'value': 4},
                  ],
                }),
              },
        );
        final result = await dispatcher.http(
          {
            'url': 'https://one.example/list',
            'method': 'GET',
            'max_response_bytes': 128 * 1024,
            if (paths != null) 'response_json_paths': paths,
          },
          access: permission('https://one.example'),
          readCredentials: () async => {},
          authorize: () async {},
        );
        expect(result['outcome'], 'response');
        expect(result['status'], 422);
        if (paths == null) {
          expect((result['body'] as String).length, greaterThan(70000));
        } else {
          expect(
            result['json'],
            paths.containsKey('names')
                ? {
                  'failure': 'rejected',
                  'names': ['A', 'B'],
                }
                : {'first': 3, 'absent': null},
          );
          expect(result['headers'], {'X-Service': 'fixture'});
        }
      }
    },
  );
  test(
    'HTTP JSON paths reject invalid bounds before dispatch and malformed replies remain uncertain',
    () async {
      for (final paths in [
        [],
        {},
        {
          'x': [1],
        },
        {'x': List.filled(17, 'field')},
        {
          'x': ['x' * 65],
        },
        {
          'name': ['name'],
        },
      ]) {
        var calls = 0;
        final dispatcher = PluginCapabilityDispatcher(
          send: (m, u, h, b) async {
            calls++;
            return {'status': 200, 'body': '{broken'};
          },
        );
        final result = await dispatcher.http(
          {
            'url': 'https://one.example/list',
            'method': 'GET',
            'response_json_paths': paths,
          },
          access: permission('https://one.example'),
          readCredentials: () async => {},
          authorize: () async {},
        );
        expect(calls, paths is Map && paths.containsKey('name') ? 1 : 0);
        expect(result['outcome'], calls == 0 ? 'not_dispatched' : 'unknown');
      }
    },
  );
  test(
    'JSON selection cannot hide echoed secrets or expand the response bound',
    () async {
      final dispatcher = PluginCapabilityDispatcher(
        send:
            (m, u, h, b) async => {
              'status': 200,
              'body': '{"hidden":"synthetic-secret","value":"safe"}',
            },
      );
      final result = await dispatcher.http(
        {
          'url': 'https://one.example/list',
          'method': 'GET',
          'credential': 'default',
          'auth': {
            'headers': {
              'Authorization': {'field': 'token'},
            },
          },
          'response_json_paths': {
            'value': ['value'],
          },
        },
        access: permission('https://one.example'),
        readCredentials: () async => {'token': 'synthetic-secret'},
        authorize: () async {},
      );
      expect(result, {'outcome': 'unknown', 'error': 'protected_response'});
      final large = PluginCapabilityDispatcher(
        send:
            (m, u, h, b) async => {
              'status': 200,
              'body': jsonEncode({'v': 'x' * 4000}),
            },
      );
      final overflow = await large.http(
        {
          'url': 'https://one.example/list',
          'method': 'GET',
          'response_json_paths': {for (var i = 0; i < 8; i++) '$i': []},
        },
        access: permission('https://one.example'),
        readCredentials: () async => {},
        authorize: () async {},
      );
      expect(overflow['outcome'], 'unknown');
    },
  );
  test(
    'projected catalog reads bound source and returned data separately without truncation',
    () async {
      final rows = List.generate(
        1400,
        (i) => {'name': 'ITEM-$i', 'unused': 'x' * 450},
      );
      var calls = 0;
      final dispatcher = PluginCapabilityDispatcher(
        send: (m, u, h, b) async {
          calls++;
          return {
            'status': 200,
            'body': jsonEncode({'items': rows}),
          };
        },
      );
      Future<Map<String, dynamic>> read(
        int bound,
        Map<String, List<String>> paths,
      ) => dispatcher.http(
        {
          'url': 'https://one.example/catalog',
          'method': 'GET',
          'max_response_bytes': bound,
          'response_json_paths': paths,
        },
        access: permission('https://one.example'),
        readCredentials: () async => {},
        authorize: () async {},
      );
      final complete = await read(1024 * 1024, {
        'names': ['items', '*', 'name'],
      });
      expect(complete['outcome'], 'response');
      expect(
        (complete['json'] as Map)['names'],
        List.generate(1400, (i) => 'ITEM-$i'),
      );
      expect(
        (await read(256 * 1024, {
          'names': ['items', '*', 'name'],
        }))['outcome'],
        'unknown',
      );
      expect((await read(1024 * 1024, {'full': []}))['outcome'], 'unknown');
      expect(
        (await read(1024 * 1024 + 1, {
          'names': ['items', '*', 'name'],
        }))['outcome'],
        'not_dispatched',
      );
      expect(calls, 3);
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

class UnusedWorkspacePorts
    implements
        ManualConsensusCheckService,
        ConsensusAttestationExchangeService,
        CapsuleChatDeliveryService,
        CapsulePassiveReceivePort,
        CapsuleContactLabelStore,
        CapsuleScopedSecretVault,
        UiEventLogService {
  Future<void> Function()? beforeResolve;
  @override
  Future<Map<String, String>> resolveReferences(
    String owner,
    Map<String, String> references,
  ) async {
    await beforeResolve?.call();
    return references.map((key, _) => MapEntry(key, 'synthetic-$key'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unrelated port invoked: ${invocation.memberName}');
}

class Registry extends WasmPluginRegistryService {
  bool installed = true;
  bool network = true;
  bool persistent = true, scheduled = true;
  String digest = 'b' * 64;
  String? packagePath;
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
            packageFilePath: packagePath,
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
  PluginWorkspaceRuntime runtime({
    bool scheduleTimers = false,
    String executionHost = 'local',
    String? executionIdentity,
  }) => PluginWorkspaceRuntime(
    registry: registry,
    infer: infer,
    fileStore: files,
    readActiveCapsuleRootHex: () => owner,
    scheduleTimers: scheduleTimers,
    executionHost: executionHost,
    executionIdentity: executionIdentity,
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
