import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/screens/plugin_workspace_screen.dart';
import 'package:hivra_app/screens/wasm_plugins_screen.dart';
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
  for (final error in [
    const FormatException('PRIVATE_REGISTRY_CONTENT'),
    const FileSystemException('PRIVATE_REGISTRY_PATH'),
  ]) {
    for (final width in [360.0, 1200.0]) {
      testWidgets(
        'plugin inventory failure can retry without admission or data cleanup (${error.runtimeType}, width $width)',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final f = (await tester.runAsync(Fixture.create))!;
          addTearDown(() => tester.runAsync(f.close));
          f.registry.loadError = error;
          final ports =
              UnusedWorkspacePorts()
                ..catalog = const WasmPluginSourceCatalog(
                  sourceId: 'source',
                  sourceName: 'Public source',
                  fetchedAtIso: '2026-11-11T00:00:00Z',
                  entries: [
                    WasmPluginSourceCatalogEntry(
                      id: 'other',
                      pluginId: 'other.application',
                      displayName: 'Another application',
                      version: '1.0.0',
                      downloadUrl: 'https://source.example/app.zip',
                      packageKind: 'zip',
                      sha256Hex: null,
                    ),
                  ],
                );
          var opened = 0;
          final module = PluginRuntimeModule(
            registry: f.registry,
            sourceCatalog: ports,
            manualChecks: ports,
            pluginHostApi: f.runtime().pluginHostApi,
            attestationExchange: ports,
            chatDelivery: ports,
            passiveReceive: ports,
            contactLabels: ports,
            uiLog: ports,
            fileStore: f.files,
            secretVault: ports,
            readActiveCapsuleRootHex: () => f.owner,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: WasmPluginsScreen(
                module: module,
                onOpenWorkspacePressed:
                    (_) => () {
                      opened++;
                    },
              ),
            ),
          );
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 1),
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('0 installed'), findsNothing);
          expect(find.text('No plugin packages installed yet.'), findsNothing);
          expect(find.textContaining('PRIVATE_REGISTRY'), findsNothing);
          expect(ports.logs.join(), isNot(contains('PRIVATE_REGISTRY')));
          for (final name in ['Add package', 'Install']) {
            final button = find.widgetWithText(FilledButton, name);
            expect(tester.widget<FilledButton>(button).onPressed, isNull);
          }
          final retry = find.widgetWithText(
            OutlinedButton,
            'Retry loading plugins',
          );
          expect(retry, findsOneWidget);
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(retry, findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          f.registry.loadError = null;
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(find.text('1 installed'), findsOneWidget);
          expect(find.text(f.registry.record.displayName), findsOneWidget);
          expect(retry, findsNothing);
          final open = find.widgetWithText(FilledButton, 'Open');
          await tester.ensureVisible(open);
          await tester.pumpAndSettle();
          await tester.tap(open);
          expect(opened, 1);
          expect(f.actions, isEmpty);
          expect(f.sends, 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final authority in ['local', 'vps', 'corrupt']) {
    test(
      'package removal uses execution authority rather than a saved VPS ($authority)',
      () async {
        final f = await Fixture.create();
        addTearDown(f.close);
        await f.enable();
        await f.changeGrant((grant) {
          grant['package_id'] = 'previous-package';
          grant['package_digest'] = 'c' * 64;
          grant['expires_at_ms'] = DateTime.now().millisecondsSinceEpoch - 1;
          if (authority == 'vps') {
            grant['executor'] = 'vps';
            grant['executor_id'] = 'e' * 64;
            grant['handoff_id'] = 'd' * 64;
          }
        });
        final registry = WasmPluginRegistryService(
          dataDirs: UserVisibleDataDirectoryService(homeOverride: f.home.path),
        );
        final plugins = await registry.pluginsDirectory(create: true);
        await File(
          '${plugins.path}/${f.registry.record.storedFileName}',
        ).writeAsString('inactive fixture package');
        await File(
          '${plugins.path}/registry.json',
        ).writeAsString(jsonEncode([f.registry.record.toJson()]));
        final dir = await f.files.capsuleDirForHex(f.owner);
        final plugin = f.registry.record.pluginId!;
        if (authority == 'corrupt') {
          await f.files.writePluginState(
            dir,
            plugin,
            'workspace-execution.v1.json',
            '{',
          );
        }
        final retained = await f.files.readPluginState(
          dir,
          plugin,
          'workspace-execution.v1.json',
        );
        const pending = '{"private_shape":["unresolved-delivery"]}';
        await f.files.writePluginState(
          dir,
          plugin,
          'workspace.v1.json',
          pending,
        );
        await f.files.writePluginState(
          dir,
          plugin,
          PluginWorkspaceRemoteService.connectionFile,
          jsonEncode({
            'owner': f.owner,
            'plugin_id': plugin,
            'executor_id': 'e' * 64,
            'host': 'offline.example',
            'port': 22,
            'fingerprint': 'SHA256:${'A' * 43}',
            'selected': true,
            'package_id': 'old-server-package',
            'package_digest': 'c' * 64,
          }),
        );
        final calls = <String>[];
        var secretCleanup = false;
        final ports =
            UnusedWorkspacePorts()
              ..onDeletePlugin = (id, owners) async {
                expect(id, plugin);
                expect(owners, {f.owner});
                secretCleanup = true;
              };
        final module = PluginRuntimeModule(
          registry: registry,
          sourceCatalog: const WasmPluginSourceCatalogService(),
          manualChecks: ports,
          pluginHostApi: f.runtime().pluginHostApi,
          attestationExchange: ports,
          chatDelivery: ports,
          passiveReceive: ports,
          contactLabels: ports,
          uiLog: ports,
          fileStore: f.files,
          secretVault: ports,
          readActiveCapsuleRootHex: () => f.owner,
          workspaceRemote: PluginWorkspaceRemoteService(
            files: f.files,
            vault: ports,
            registry: registry,
            requestTransport: (_, command, _) async {
              calls.add(command);
              throw StateError('VPS unavailable');
            },
          ),
        );
        if (authority == 'local') {
          await module.removePlugin(f.registry.record);
          expect(await registry.loadPlugins(), isEmpty);
          expect(secretCleanup, isTrue);
          expect(calls, isEmpty);
        } else {
          await expectLater(
            module.removePlugin(f.registry.record),
            throwsA(anything),
          );
          expect((await registry.loadPlugins()).single.removalPending, isFalse);
          expect(secretCleanup, isFalse);
          expect(calls, authority == 'vps' ? ['request'] : isEmpty);
        }
        expect(
          await f.files.readPluginState(dir, plugin, 'workspace.v1.json'),
          pending,
        );
        expect(
          await f.files.readPluginState(
            dir,
            plugin,
            'workspace-execution.v1.json',
          ),
          retained,
        );
        expect(f.sends, 0);
      },
    );
  }

  for (final deleteSavedData in [false, true]) {
    test(
      'failed secret cleanup preserves private data across retry (delete saved data: $deleteSavedData)',
      () async {
        final f = await Fixture.create();
        addTearDown(f.close);
        final dirs = UserVisibleDataDirectoryService(homeOverride: f.home.path);
        var registry = WasmPluginRegistryService(dataDirs: dirs);
        final plugins = await registry.pluginsDirectory(create: true);
        await File(
          '${plugins.path}/${f.registry.record.storedFileName}',
        ).writeAsString('inactive fixture package');
        await File(
          '${plugins.path}/registry.json',
        ).writeAsString(jsonEncode([f.registry.record.toJson()]));
        final ownerDir = await f.files.capsuleDirForHex(f.owner, create: true);
        final otherOwner = 'c' * 64;
        await f.files.capsuleDirForHex(otherOwner, create: true);
        final plugin = f.registry.record.pluginId!;
        const pending = '{"private_shape":["unresolved-request"]}';
        await f.files.writePluginState(
          ownerDir,
          plugin,
          'workspace.v1.json',
          pending,
        );
        await f.files.writePluginState(
          ownerDir,
          plugin,
          'cache.json',
          'keep on failure',
        );
        final ports = UnusedWorkspacePorts();
        var failCleanup = true;
        var cleanupCalls = 0;
        ports.onDeletePlugin = (id, owners) async {
          cleanupCalls++;
          expect(id, plugin);
          expect(owners, {f.owner, otherOwner});
          expect(
            await f.files.readPluginState(
              ownerDir,
              plugin,
              'workspace.v1.json',
            ),
            pending,
          );
          expect(
            await f.files.readPluginState(ownerDir, plugin, 'cache.json'),
            'keep on failure',
          );
          expect((await registry.loadPlugins()).single.removalPending, isTrue);
          expect(
            (await registry.resolveRuntimeBinding(plugin)).source,
            'host_fallback',
          );
          if (failCleanup) throw StateError('Native secret cleanup denied');
        };
        PluginRuntimeModule module() => PluginRuntimeModule(
          registry: registry,
          sourceCatalog: const WasmPluginSourceCatalogService(),
          manualChecks: ports,
          pluginHostApi: f.runtime().pluginHostApi,
          attestationExchange: ports,
          chatDelivery: ports,
          passiveReceive: ports,
          contactLabels: ports,
          uiLog: ports,
          fileStore: f.files,
          secretVault: ports,
          readActiveCapsuleRootHex: () => f.owner,
        );
        await expectLater(
          module().removePlugin(
            f.registry.record,
            deleteSavedData: deleteSavedData,
          ),
          throwsStateError,
        );
        expect((await registry.loadPlugins()).single.removalPending, isTrue);
        expect(
          await f.files.readPluginState(ownerDir, plugin, 'cache.json'),
          'keep on failure',
        );
        failCleanup = false;
        registry = WasmPluginRegistryService(dataDirs: dirs);
        await module().removePlugin(
          (await registry.loadPlugins()).single,
          deleteSavedData: deleteSavedData,
        );
        expect(cleanupCalls, 2);
        expect(await registry.loadPlugins(), isEmpty);
        expect(
          await f.files.readPluginState(ownerDir, plugin, 'cache.json'),
          isNull,
        );
        expect(
          await f.files.readPluginState(ownerDir, plugin, 'workspace.v1.json'),
          deleteSavedData ? isNull : pending,
        );
        expect(f.sends, 0);
      },
    );
  }

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
              bool reinstall = false,
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
      await tester.tap(find.text('Return to this device'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(find.text('Unrelated application'), findsOneWidget);
      expect(actions, ['open', 'open']);
      expect(find.text('Recover local access'), findsNothing);
    },
  );

  testWidgets(
    'a saved VPS view keeps return confirmation and describes unavailable revocation',
    (tester) async {
      var returns = 0;
      final saved = {
        ...presentation(),
        'execution': {'mode': 'local', 'running': false},
        'host_connection': {
          'target': 'vps',
          'health': 'unavailable',
          'saved': true,
          'host': 'server.example',
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (_, _) async => saved,
            connectVps:
                ({
                  required host,
                  required port,
                  required password,
                  required trustPeer,
                  bool reinstall = false,
                }) async => fail('No VPS connection expected'),
            useOnline: () async {
              returns++;
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
              expect(enabled, isFalse);
              expect(revoke, isTrue);
              return saved;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return from VPS'));
      await tester.pumpAndSettle();
      expect(returns, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(returns, 0);
      await tester.tap(find.text('Revoke plugin permissions'));
      await tester.pumpAndSettle();
      expect(find.text('Saved workspace'), findsOneWidget);
      expect(find.text('Retry connection'), findsOneWidget);
      await tester.tap(find.text('Return from VPS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return to this device'));
      await tester.pumpAndSettle();
      expect(returns, 1);
    },
  );

  testWidgets(
    'failed first open keeps one revocation control and recovery reachable',
    (tester) async {
      final actions = <String>[];
      var revocations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (action, settings) async {
              actions.add(action);
              throw const SocketException('VPS unavailable');
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
              expect(enabled, isFalse);
              expect(revoke, isTrue);
              revocations++;
              throw StateError('Remote stop unavailable');
            },
            connectVps:
                ({
                  required host,
                  required port,
                  required password,
                  required trustPeer,
                  bool reinstall = false,
                }) async => fail('Revocation must not install a server'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final revoke = find.text('Revoke plugin permissions');
      expect(revoke, findsOneWidget);
      await tester.tap(revoke);
      await tester.pumpAndSettle();
      expect(revocations, 1);
      expect(actions, ['open']);
      expect(revoke, findsOneWidget);
      expect(find.text('Connect VPS'), findsOneWidget);
      await tester.tap(find.text('Retry opening plugin'));
      await tester.pumpAndSettle();
      expect(actions, ['open', 'open']);
      expect(revocations, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'missing VPS, failed transport or package replacement cannot prevent local revocation',
    () async {
      for (final fault in ['missing', 'unavailable', 'replacement']) {
        final connected = fault != 'missing';
        final f = await Fixture.create();
        try {
          await f.enable();
          final local = f.runtime();
          await local.runWorkspaceAction(
            record: f.registry.record,
            action: 'open',
          );
          final checkpoint = await local.releaseWorkspaceToVps(
            f.registry.record,
            executorId: 'e' * 64,
          );
          if (fault == 'replacement') f.registry.digest = 'c' * 64;
          final directory = await f.files.capsuleDirForHex(f.owner);
          if (connected) {
            await f.files.writePluginState(
              directory,
              f.registry.record.pluginId!,
              PluginWorkspaceRemoteService.connectionFile,
              jsonEncode({
                'owner': f.owner,
                'plugin_id': f.registry.record.pluginId,
                'executor_id': 'e' * 64,
                'host': 'server.example',
                'port': 22,
                'fingerprint': 'SHA256:${'A' * 43}',
                'selected': true,
                'package_id': f.registry.record.id,
                'package_digest': checkpoint['package_digest'],
              }),
            );
          }
          final ports = UnusedWorkspacePorts();
          final commands = <String>[];
          final module = PluginRuntimeModule(
            registry: f.registry,
            sourceCatalog: const WasmPluginSourceCatalogService(),
            manualChecks: ports,
            pluginHostApi: local.pluginHostApi,
            attestationExchange: ports,
            chatDelivery: ports,
            passiveReceive: ports,
            contactLabels: ports,
            uiLog: ports,
            fileStore: f.files,
            secretVault: ports,
            readActiveCapsuleRootHex: () => f.owner,
            workspaceRemote: PluginWorkspaceRemoteService(
              files: f.files,
              vault: ports,
              registry: f.registry,
              requestTransport: (c, command, input) async {
                commands.add(
                  (jsonDecode(utf8.decode(input)) as Map)['command'] as String,
                );
                throw const SocketException('VPS unavailable');
              },
            ),
          );
          await expectLater(
            module.setWorkspaceExecution(
              record: f.registry.record,
              enabled: false,
              expiresAtMs: null,
              revoke: true,
            ),
            throwsStateError,
          );
          // Reopen the custody owner: recovery must carry the revoked grant,
          // not the old active permission, while preserving opaque evidence.
          final recovered = await f.runtime().releaseWorkspaceToVps(
            f.registry.record,
            executorId: 'e' * 64,
          );
          expect(recovered['execution']['enabled'], isFalse);
          expect(recovered['execution']['revoked'], isTrue);
          expect(
            recovered['execution']['revision'],
            checkpoint['execution']['revision'] + 1,
          );
          expect(recovered['workspace'], checkpoint['workspace']);
          expect(recovered['effects'], checkpoint['effects']);
          expect(recovered['package_digest'], checkpoint['package_digest']);
          expect(
            recovered['execution']['handoff_id'],
            checkpoint['execution']['handoff_id'],
          );
          if (fault == 'replacement') {
            await expectLater(
              f.runtime().setReleasedWorkspaceEntries(
                f.registry.record,
                executorId: 'e' * 64,
                enabled: true,
                expectedRevision: recovered['execution']['revision'] as int,
              ),
              throwsStateError,
            );
          }
          expect(commands, connected ? ['status'] : isEmpty);
          expect(f.sends, 0);
          expect(f.actions, everyElement('open'));
        } finally {
          await f.close();
        }
      }
    },
  );

  test(
    'replaced and unavailable workspaces retain only their own checkpoint and recovery',
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
        final displaced = await runner.dispatch({
          ...oldBinding,
          'command': 'status',
        });
        expect(displaced['binding'], oldBinding);
        expect(displaced['runner']['state'], 'replaced');
        expect(displaced['view'], isNull);
        expect(jsonEncode(displaced), isNot(contains(newBinding['owner'])));
        await expectLater(
          runner.dispatch({
            ...oldBinding,
            'command': 'action',
            'action': 'run',
            'settings': const {},
          }),
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
        var observation = 'replaced-on-adopt';
        const observationError = 'Test observation unavailable';
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
            final operation = input['command'] as String;
            calls.add(operation);
            if (observation == 'legacy' && operation == 'adopt') {
              throw StateError(
                'VPS operation failed; no remote success acknowledged',
              );
            }
            final response = switch ((observation, operation)) {
              ('replaced-on-status' || 'unobserved' || 'ready', 'adopt') => {
                'binding': oldBinding,
                'runner': {'state': 'running', 'execution_controls': 4},
                'view': null,
              },
              ('unobserved' || 'ready', 'status') => {
                'binding': oldBinding,
                'runner': {'state': 'running', 'execution_controls': 4},
                'view':
                    observation == 'ready'
                        ? {...presentation(), 'title': 'Fresh VPS view'}
                        : null,
                if (observation == 'unobserved')
                  'observation_error': observationError,
              },
              _ => await runner.dispatch(input),
            };
            if (removeDuringReturn && operation == 'return') {
              f.registry.installed = false;
            }
            return jsonEncode({'ok': true, 'result': response});
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
        final retainedWorkspace = await f.state();
        f.newSchema = true;
        f.requestOnOpen = true;
        for (final (scenario, health, commands) in const [
          ('replaced-on-adopt', 'replaced', ['adopt']),
          ('legacy', 'unavailable', ['adopt']),
          ('replaced-on-status', 'replaced', ['adopt', 'status']),
          ('unobserved', 'unavailable', ['adopt', 'status']),
          ('ready', 'running', ['adopt', 'status']),
        ]) {
          observation = scenario;
          calls.clear();
          final view = await module.runWorkspaceAction(
            record: f.registry.record,
            action: 'open',
          );
          expect(
            view['host_connection'],
            containsPair('health', health),
            reason: scenario,
          );
          expect(view['host_connection']['target'], 'vps');
          expect(view['host_connection']['saved'], isTrue);
          expect(
            view['host_connection']['observation_error'],
            scenario == 'unobserved' ? observationError : null,
          );
          expect(
            view['title'],
            scenario == 'ready' ? 'Fresh VPS view' : presentation()['title'],
          );
          if (scenario != 'ready') {
            expect(view['execution']['running'], isFalse);
          }
          expect(calls, commands);
          expect(await f.state(), retainedWorkspace);
          expect(
            await serverFiles.files.readPluginState(
              currentDirectory,
              serverFiles.registry.record.pluginId!,
              'workspace-execution.v1.json',
            ),
            currentGrant,
          );
        }
        expect(f.sends, 0);
        f.newSchema = false;
        f.requestOnOpen = false;
        observation = 'replaced-on-adopt';
        calls.clear();
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
        expect(calls, ['return', 'return']);
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
        final afterReturn = [...calls];
        await module.useWorkspaceOnline(f.registry.record);
        expect(calls, afterReturn);

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
        try {
          await nextRuntime
              .adoptWorkspaceFromLocal(
                record: serverFiles.registry.record,
                checkpoint: nextCheckpoint,
              )
              .timeout(const Duration(seconds: 2));
        } finally {
          releaseStart.complete();
          await firstAdoption;
        }
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
    'remote status and adoption replay remain readable during a blocked cycle',
    () async {
      final source = await Fixture.create();
      final server = await Fixture.create();
      final entered = Completer<void>(), release = Completer<void>();
      Future<Map<String, dynamic>>? cycle;
      PluginWorkspaceRuntime? runtime;
      try {
        final local = source.runtime();
        await source.enable();
        await local.runWorkspaceAction(
          record: source.registry.record,
          action: 'open',
        );
        final checkpoint = await local.releaseWorkspaceToVps(
          source.registry.record,
          executorId: 'e' * 64,
        );
        runtime = server.runtime(
          executionHost: 'vps',
          executionIdentity: 'e' * 64,
        );
        await runtime.adoptWorkspaceFromLocal(
          record: server.registry.record,
          checkpoint: checkpoint,
        );
        final binding = {
          'owner': server.owner,
          'plugin_id': server.registry.record.pluginId,
          'package_id': server.registry.record.id,
          'package_digest': server.registry.digest,
          'executor_id': 'e' * 64,
        };
        final root =
            await UserVisibleDataDirectoryService(
              homeOverride: server.home.path,
            ).rootDirectory();
        WorkspaceRunner runner(PluginWorkspaceRuntime host) => WorkspaceRunner(
          root: root,
          registry: server.registry,
          binding: binding,
          runtime: host,
        );
        final directory = await server.files.capsuleDirForHex(server.owner);
        Future<List<String?>> retainedBytes() => Future.wait([
          for (final file in [
            'workspace.v1.json',
            'external_effects.v1.json',
            'workspace-execution.v1.json',
          ])
            server.files.readPluginState(
              directory,
              server.registry.record.pluginId!,
              file,
            ),
        ]);
        server.onSend = () async {
          entered.complete();
          await release.future;
        };
        cycle = runtime.runScheduledWorkspaceCycle(server.registry.record);
        await entered.future.timeout(const Duration(seconds: 2));
        final retained = await retainedBytes();
        // A replacement schema and requests proposed by open are presentation
        // output only; neither may overwrite or advance the in-flight workflow.
        server.newSchema = server.requestOnOpen = true;
        final status = await runner(runtime)
            .dispatch({...binding, 'command': 'status'})
            .timeout(const Duration(seconds: 2));
        expect(status['view']['message'], 'Ready');
        expect(status['view']['execution']['running'], isTrue);
        expect(status['observation_error'], isNull);
        expect(await retainedBytes(), retained);
        expect(server.sends, 1);
        expect(server.received, isEmpty);
        await runner(runtime)
            .dispatch({
              ...binding,
              'command': 'adopt',
              'checkpoint': checkpoint,
            })
            .timeout(const Duration(seconds: 2));
        expect(await retainedBytes(), retained);
        await expectLater(
          runner(runtime).dispatch({
            ...binding,
            'command': 'adopt',
            'checkpoint': {...checkpoint, 'workspace': '{"different":true}'},
          }),
          throwsStateError,
        );
        expect(await retainedBytes(), retained);

        // A lost Stop acknowledgement still travels with the frozen checkpoint
        // without waiting for the network response or renewing authority.
        server.chain = true;
        await runner(runtime)
            .dispatch({
              ...binding,
              'command': 'adopt',
              'checkpoint': {
                ...checkpoint,
                'execution': {
                  ...checkpoint['execution'] as Map,
                  'enabled': false,
                  'revoked': true,
                },
              },
            })
            .timeout(const Duration(seconds: 2));
        final stopped = await runner(
          runtime,
        ).dispatch({...binding, 'command': 'status'});
        expect(stopped['view']['execution']['running'], isFalse);
        expect(stopped['view']['execution']['revoked'], isTrue);
        expect((await retainedBytes()).take(2), retained.take(2));
        release.complete();
        await cycle;
        expect(server.sends, 1);
        expect(server.received.last['outcome'], 'not_dispatched');

        final completed = await retainedBytes();
        final restarted = server.runtime(
          executionHost: 'vps',
          executionIdentity: 'e' * 64,
        );
        final reopened = await runner(
          restarted,
        ).dispatch({...binding, 'command': 'status'});
        expect(reopened['view']['execution']['revoked'], isTrue);
        expect(await retainedBytes(), completed);
        expect(server.sends, 1);
      } finally {
        if (!release.isCompleted) release.complete();
        await cycle;
        await runtime?.drainWorkspaceActions(server.registry.record.pluginId!);
        await source.close();
        await server.close();
      }
    },
  );

  for (final change in ['replace', 'remove', 'owner', 'revoke']) {
    test('read-only presentation rechecks $change during rendering', () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      final runtime = f.runtime();
      await f.enable();
      await runtime.runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
      );
      final retained = await f.state();
      f.newSchema = f.requestOnOpen = true;
      f.onInvoke = (_) async {
        switch (change) {
          case 'replace':
            f.registry.digest = 'c' * 64;
          case 'remove':
            f.registry.installed = false;
          case 'owner':
            f.owner = 'c' * 64;
          case 'revoke':
            await f.changeGrant((grant) {
              grant['revoked'] = true;
              grant['enabled'] = false;
              grant['revision'] = (grant['revision'] as int) + 1;
            });
        }
      };
      final observation = runtime.runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
        readOnly: true,
      );
      if (change == 'revoke') {
        final view = await observation;
        expect(view['execution']['revoked'], isTrue);
        expect(view['execution']['running'], isFalse);
      } else {
        await expectLater(observation, throwsStateError);
      }
      expect(await f.state(), retained);
      expect(f.sends, 0);
    });
  }

  for (final operation in ['connect', 'bootstrap', 'update']) {
    test(
      'VPS $operation changes only its authorized installation scope',
      () async {
        final home = await Directory.systemTemp.createTemp('hivra_connect_');
        addTearDown(() => home.delete(recursive: true));
        final base = '${home.path}/runtime';
        final data = '${home.path}/data';
        final ssh = '${home.path}/ssh';
        final commands = Directory('${home.path}/commands');
        await commands.create();
        await Directory(data).create();
        await Directory(ssh).create();
        final calls = File('${home.path}/service-calls');
        await calls.writeAsString('');
        final archive =
            Archive()
              ..addFile(
                ArchiveFile.string(
                  'bin/hivra-workspace-runner',
                  'candidate runtime',
                ),
              )
              ..addFile(
                ArchiveFile.string('bin/libhivra_ffi.so', 'candidate library'),
              )
              ..addFile(
                ArchiveFile.string(
                  'hivra-workspace-runner.service',
                  'candidate unit',
                ),
              );
        final bytes = GZipEncoder().encode(TarEncoder().encode(archive))!;
        final protected = <File, List<int>>{};
        if (operation != 'bootstrap') {
          await Directory('$base/current/bin').create(recursive: true);
          for (final path in [
            '$base/current/bin/hivra-workspace-runner',
            '$base/control',
            '$data/runner.json',
            '$data/credentials.json',
          ]) {
            final f = File(path);
            await f.writeAsString('retained ${f.uri.pathSegments.last}');
            protected[f] = await f.readAsBytes();
          }
          await Process.run('chmod', [
            '755',
            '$base/current/bin/hivra-workspace-runner',
          ]);
        }
        final keys = File('$ssh/authorized_keys');
        await keys.writeAsString('retained owner key\n');
        for (final entry
            in <String, String>{
              'id': 'if [ "\$1" = -u ]; then printf 0; fi',
              'uname':
                  'if [ "\$1" = -s ]; then printf Linux; else printf x86_64; fi',
              'flock': 'exit 0',
              'systemctl': 'printf "%s\\n" "\$*" >> "\$HIVRA_TEST_CONTROL_LOG"',
              'useradd': 'exit 91',
              'runuser': 'exit 92',
              'sha256sum':
                  Platform.isMacOS
                      ? 'exec /usr/bin/shasum -a 256 "\$@"'
                      : 'exec /usr/bin/sha256sum "\$@"',
              'install':
                  'if [ "\$1" = -d ]; then for last do :; done; exec /usr/bin/install -d -m 700 "\$last"; fi\nexec /usr/bin/install "\$@"',
            }.entries) {
          final f = File('${commands.path}/${entry.key}');
          await f.writeAsString('#!/bin/sh\n${entry.value}\n');
          await Process.run('chmod', ['755', f.path]);
        }
        final script = PluginWorkspaceRemoteService.installationScript(
              bytes,
              sha256.convert(bytes).toString(),
              'ssh-ed25519 AAAA hivra-workspace-${'f' * 64}',
              'f' * 64,
              reinstall: operation == 'update',
            )
            .replaceAll('/opt/hivra-workspace', base)
            .replaceAll('/var/lib/hivra-workspace', data)
            .replaceAll('/root/.ssh', ssh)
            .replaceAll(
              '/etc/systemd/system/hivra-workspace-runner.service',
              '${home.path}/service',
            );
        final result = await Process.run(
          '/bin/sh',
          ['-c', script],
          environment: {
            'PATH': '${commands.path}:${Platform.environment['PATH']}',
            'HIVRA_TEST_CONTROL_LOG': calls.path,
          },
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(jsonDecode(result.stdout as String), {'connected': true});
        expect(await keys.readAsString(), contains('retained owner key'));
        expect(
          await keys.readAsString(),
          contains('hivra-workspace-${'f' * 64}'),
        );
        final serviceCalls = await calls.readAsString();
        if (operation == 'connect') {
          expect(serviceCalls, isEmpty);
          for (final f in protected.entries) {
            expect(await f.key.readAsBytes(), f.value);
          }
        } else {
          expect(
            await File(
              '$base/current/bin/hivra-workspace-runner',
            ).readAsString(),
            'candidate runtime',
          );
          if (operation == 'bootstrap') {
            expect(serviceCalls, isNot(contains('start ')));
            expect(serviceCalls, isNot(contains('stop ')));
            expect(File('$data/runner.json').existsSync(), isFalse);
            expect(File('$data/credentials.json').existsSync(), isFalse);
          } else {
            expect(
              serviceCalls,
              contains('stop hivra-workspace-runner.service'),
            );
            expect(
              serviceCalls,
              contains('start hivra-workspace-runner.service'),
            );
            for (final f in protected.entries.where(
              (e) => e.key.path.startsWith(data),
            )) {
              expect(await f.key.readAsBytes(), f.value);
            }
          }
        }
      },
    );
  }

  test('status before adoption does not initialize a workspace', () async {
    final f = await Fixture.create();
    addTearDown(f.close);
    final root =
        await UserVisibleDataDirectoryService(
          homeOverride: f.home.path,
        ).rootDirectory();
    final binding = {
      'owner': f.owner,
      'plugin_id': f.registry.record.pluginId,
      'package_id': f.registry.record.id,
      'package_digest': f.registry.digest,
      'executor_id': 'e' * 64,
    };
    final runner = WorkspaceRunner(
      root: root,
      registry: f.registry,
      binding: binding,
      runtime: f.runtime(executionHost: 'vps', executionIdentity: 'e' * 64),
    );
    final status = await runner.dispatch({...binding, 'command': 'status'});
    expect(status['view'], isNull);
    expect(f.actions, isEmpty);
    expect(f.sends, 0);
    expect((await f.files.capsuleDirForHex(f.owner)).existsSync(), isFalse);
  });

  test(
    'read-only local presentation retains delegated state without execution',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      await f.runtime().releaseWorkspaceToVps(
        f.registry.record,
        executorId: 'e' * 64,
      );
      final before = await f.state();
      final grant = await f.runtime().readWorkspaceExecution(
        f.registry.record,
        enforceHost: false,
      );
      f.requestOnOpen = true;
      f.onReadSecrets =
          () async => fail('Observation must not open credentials');
      final view = await f.runtime().runWorkspaceAction(
        record: f.registry.record,
        action: 'open',
        readOnly: true,
      );
      expect(view['title'], f.registry.record.displayName);
      expect(view['execution']['running'], isFalse);
      expect(f.executionSeen.last['running'], isFalse);
      expect(f.executionSeen.last['enabled'], isFalse);
      expect(await f.state(), before);
      expect(
        await f.runtime().readWorkspaceExecution(
          f.registry.record,
          enforceHost: false,
        ),
        grant,
      );
      expect(f.sends, 0);
      await expectLater(
        f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'delegated choices read locally without state, secrets or changes to execution',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      final runtime = f.runtime();
      await runtime.releaseWorkspaceToVps(
        f.registry.record,
        executorId: 'e' * 64,
      );
      final before = await f.state();
      final grant = await runtime.readWorkspaceExecution(
        f.registry.record,
        enforceHost: false,
      );
      f.onReadSecrets = () async => fail('Choices must not open credentials');
      final readAccess = {
        'version': 2,
        'network': [
          {
            'origin': f.origin,
            'methods': ['GET'],
          },
        ],
      };
      Future<Map<String, dynamic>> load({bool approved = false}) =>
          runtime.runWorkspaceAction(
            record: f.registry.record,
            action: 'run',
            choiceAccess: readAccess,
            choiceAccessApproved: approved,
          );

      f.method = 'GET';
      await load();
      expect(f.sends, 1);
      expect(f.executionSeen.last, {
        'running': false,
        'enabled': false,
        'scope': null,
      });
      expect(await f.state(), before);
      expect(
        await runtime.readWorkspaceExecution(
          f.registry.record,
          enforceHost: false,
        ),
        grant,
      );

      f.method = 'POST';
      await expectLater(load(approved: true), throwsStateError);
      f.method = 'GET';
      f.credential = 'default';
      await expectLater(load(approved: true), throwsStateError);
      f.credential = null;
      expect(f.sends, 1);

      final expiredAt = DateTime.now().millisecondsSinceEpoch - 1000;
      await f.changeGrant((grant) => grant['expires_at_ms'] = expiredAt);
      await load();
      expect(f.sends, 1);
      expect(f.received.last['outcome'], 'not_dispatched');
      await load(approved: true);
      expect(f.sends, 2);
      expect(await f.state(), before);
      expect(
        await runtime.readWorkspaceExecution(
          f.registry.record,
          enforceHost: false,
        ),
        {...grant!, 'expires_at_ms': expiredAt},
      );

      f.onInvoke = (_) async {
        f.registry.digest = 'd' * 64;
      };
      await expectLater(load(approved: true), throwsStateError);
      expect(f.sends, 2);
    },
  );

  test(
    'authorized local Start applies prepared settings once before the new cycle',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      await f.enable();
      final runtime = f.runtime();
      final prior = (await runtime.readWorkspaceExecution(f.registry.record))!;
      final before = await f.state();
      final selection = {'symbol': 'NEW', 'interval': 120};
      Future<Map<String, dynamic>> start(String action) =>
          runtime.setWorkspaceExecution(
            record: f.registry.record,
            enabled: true,
            expiresAtMs: null,
            expectedRevision: prior['revision'] as int,
            approvedScope: {...f.schedule, 'start_action': action},
            settings: selection,
          );

      await expectLater(start('run'), throwsStateError);
      expect(f.sends, 0);
      expect(await f.state(), before);
      expect(await runtime.readWorkspaceExecution(f.registry.record), prior);

      f.actions.clear();
      await start('start');
      expect(f.actions, ['start', 'open']);
      expect((await f.state())['prepared_settings'], selection);
      final grant = (await runtime.readWorkspaceExecution(f.registry.record))!;
      expect(grant['scope']['interval_seconds'], 120);
      expect(grant['scope']['start_action'], isNull);
      expect(grant['settings'], selection);
      await expectLater(
        runtime.runScheduledWorkspaceCycle(
          f.registry.record,
          expectedRevision: prior['revision'] as int,
        ),
        throwsStateError,
      );
      expect(f.sends, 0);
      await runtime.runScheduledWorkspaceCycle(
        f.registry.record,
        expectedRevision: grant['revision'] as int,
      );
      expect(f.sends, 1);
      expect(f.actions.where((a) => a == 'start'), hasLength(1));
      expect(f.settingsSeen.last, selection);
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
          if (!revoke) {
            await expectLater(
              module.setWorkspaceExecution(
                record: f.registry.record,
                enabled: true,
                expiresAtMs: null,
                expectedRevision: 1,
                approvedScope: f.schedule,
                credentialBindings: {
                  'default': {'token': 'ref-token'},
                },
              ),
              throwsStateError,
            );
            expect(
              calls,
              isEmpty,
              reason: 'A permissions edit must not replace the runner',
            );
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

  for (final scenario in ['running', 'replaced', 'unavailable', 'expired']) {
    testWidgets(
      'VPS next Start settings are editable without stopping or reconnecting ($scenario)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final expired = scenario == 'expired';
        final health = expired ? 'replaced' : scenario;
        final access = permission('https://one.example');
        final readAccess = {
          'version': 2,
          'network': [
            {
              'origin': 'https://one.example',
              'methods': ['GET'],
            },
          ],
        };
        final deadline =
            DateTime.now().millisecondsSinceEpoch +
            (expired ? -3600000 : 3600000);
        var started = false;
        final configuration = <Map<String, dynamic>>[];
        final actions = <String>[];
        final choices = <String>[];
        Map<String, dynamic> view() => {
          ...presentation(),
          'fields': [
            {
              'id': 'selection',
              'label': 'Owner selection',
              'type': 'choice',
              'value': 'retained-choice',
              'source': {'action': 'select_item', 'access': readAccess},
            },
            {
              'id': 'period',
              'label': 'Period',
              'type': 'choice',
              'value': 'all',
              'source': {'action': 'select_period'},
            },
          ],
          'actions': [
            {
              'id': 'begin_owner_workflow',
              'label': 'Start application',
              'host': 'workspace.start',
            },
            if (health == 'running' && !started)
              {'id': 'stop', 'label': 'Stop new entries', 'settings': false},
          ],
          'schedule': {
            'version': 2,
            'action': 'run',
            'interval_seconds': 60,
            'description': 'Owner workflow',
            'access': access,
          },
          'execution': {
            'active': !expired,
            'enabled': !expired,
            'running': started || health == 'running',
            'revision': 1,
            'expires_at_ms': deadline,
            'access': access,
            'credentials': {
              'default': {'token': 'saved-reference'},
            },
          },
          'host_connection': {
            'target': 'vps',
            'host': 'server.example',
            'port': 22,
            'saved': true,
            'health': started ? 'running' : health,
          },
        };
        await tester.pumpWidget(
          MaterialApp(
            home: PluginWorkspaceScreen(
              capabilities: const ['workspace.schedule'],
              runWorkspaceAction: (action, settings) async {
                actions.add(action);
                return view();
              },
              loadLocalChoices: (action, access, approved) async {
                choices.add(action);
                expect(approved, expired && action == 'select_item');
                return {
                  if (action == 'select_period')
                    'message': 'All uses six frames; 1m is separate.',
                  'options': action == 'select_item' ? ['new-choice'] : ['1m'],
                };
              },
              listSecrets:
                  () async =>
                      throw StateError('Matching access must be reused'),
              connectVps:
                  ({
                    required host,
                    required port,
                    required password,
                    required trustPeer,
                    bool reinstall = false,
                  }) async => fail('Start must not reconnect'),
              configureExecution: ({
                required enabled,
                required expiresAtMs,
                expectedRevision,
                revoke = false,
                approvedScope,
                credentialBindings,
                settings = const {},
              }) async {
                expect(enabled, isTrue);
                expect(expiresAtMs, deadline);
                expect(expectedRevision, 1);
                expect(approvedScope?['start_action'], 'begin_owner_workflow');
                expect(credentialBindings, isNull);
                configuration.add(Map<String, dynamic>.from(settings));
                started = true;
                return view();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(switch (health) {
            'replaced' => 'Previous assignment replaced',
            'unavailable' => 'Previous assignment unavailable',
            _ => 'VPS process is running',
          }),
          findsOneWidget,
        );
        expect(
          find.textContaining('Execution location: This device'),
          findsNothing,
        );
        expect(find.text('Retry opening plugin'), findsNothing);
        final selection = find.byKey(const ValueKey('plugin-field-selection'));
        await tester.scrollUntilVisible(
          selection,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(selection);
        await tester.pumpAndSettle();
        await tester.tap(selection);
        await tester.pumpAndSettle();
        if (expired) {
          expect(choices, isEmpty);
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          expect(choices, isEmpty);
          await tester.tap(selection);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.widgetWithText(ListTile, 'new-choice'));
        await tester.pumpAndSettle();
        final period = find.byKey(const ValueKey('plugin-field-period'));
        await tester.ensureVisible(period);
        await tester.pumpAndSettle();
        await tester.tap(period);
        await tester.pumpAndSettle();
        expect(
          find.text('All uses six frames; 1m is separate.'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(ListTile, '1m'));
        await tester.pumpAndSettle();
        expect(choices, ['select_item', 'select_period']);
        if (expired) {
          expect(configuration, isEmpty);
          expect(actions, ['open']);
          return;
        }
        final start = find.byKey(
          const ValueKey('plugin-action-begin_owner_workflow'),
        );
        await tester.scrollUntilVisible(
          start,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(start);
        await tester.pumpAndSettle();
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(configuration, [
          {'selection': 'new-choice', 'period': '1m'},
        ]);
        expect(find.text('Plugin permissions'), findsNothing);
        expect(find.text('VPS process is running'), findsOneWidget);
        expect(actions, ['open']);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Stop keeps the draft even with a missing numeric input', (
    tester,
  ) async {
    final stop = find.byKey(const ValueKey('plugin-action-stop'));
    var stopped = false;
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PluginWorkspaceScreen(
          runWorkspaceAction: (action, settings) async {
            if (action == 'stop') {
              submitted.add(settings);
              stopped = true;
            }
            return {
              ...presentation(),
              'fields': [
                {
                  'id': 'symbol',
                  'label': 'Instrument',
                  'type': 'text',
                  'value': 'MNT-USDT',
                },
                {
                  'id': 'period',
                  'label': 'Timeframe',
                  'type': 'text',
                  'value': 'all',
                },
                {
                  'id': 'margin',
                  'label': 'Margin',
                  'type': 'number',
                  'value': 1.0,
                },
              ],
              'actions': [
                if (!stopped)
                  {
                    'id': 'stop',
                    'label': 'Stop new entries',
                    'settings': false,
                  },
              ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final symbol = find.byKey(const ValueKey('plugin-field-symbol'));
    final period = find.byKey(const ValueKey('plugin-field-period'));
    final margin = find.byKey(const ValueKey('plugin-field-margin'));
    await tester.enterText(symbol, 'ACH-USDT');
    await tester.enterText(period, '1m');
    await tester.enterText(margin, '');
    await tester.ensureVisible(stop);
    await tester.pumpAndSettle();
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(submitted, [<String, dynamic>{}]);
    expect(tester.widget<TextField>(symbol).controller!.text, 'ACH-USDT');
    expect(tester.widget<TextField>(period).controller!.text, '1m');
    expect(tester.widget<TextField>(margin).controller!.text, isEmpty);
    expect(stop, findsNothing);
  });

  for (final target in ['local', 'selected', 'vps']) {
    testWidgets('execution destination is visible before Start ($target)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction: (action, _) async {
              actions.add(action);
              return {
                ...presentation(),
                'fields': [
                  {
                    'id': 'selection',
                    'label': 'Selection',
                    'type': 'text',
                    'value': 'unchanged',
                  },
                ],
                'actions': [
                  {
                    'id': 'start',
                    'label': 'Begin workflow',
                    'host': 'workspace.start',
                  },
                ],
                'host_connection': {
                  'target': target == 'vps' ? 'vps' : 'local',
                  'selected': target != 'local',
                  'saved': target != 'local',
                  if (target != 'local') 'host': 'server.example',
                  'health': target == 'vps' ? 'running' : 'not_started',
                },
                'execution': {
                  'mode': target == 'vps' ? 'vps' : 'local',
                  'active': false,
                  'running': false,
                },
              };
            },
            connectVps: ({
              required host,
              required port,
              required password,
              required trustPeer,
              bool reinstall = false,
            }) async {
              fail('Rendering must not connect a server');
            },
            useOnline: () async => fail('Rendering must not change execution'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = find.byKey(const ValueKey('plugin-action-start'));
      final expected = target == 'local' ? 'this device' : 'VPS server.example';
      expect(
        find.descendant(of: start, matching: find.textContaining(expected)),
        findsOneWidget,
      );
      final location = find.text(
        'Execution location: ${target == 'vps' ? 'VPS server.example' : 'This device'}',
      );
      expect(location, findsOneWidget);
      final choose = find.byKey(const ValueKey('workspace-target-vps'));
      expect(
        tester.getTopLeft(choose).dy,
        lessThan(tester.getTopLeft(start).dy),
      );
      expect(tester.getBottomRight(start).dy, lessThan(780));
      expect(actions, ['open']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('running server does not hide expired workflow permission', (
    tester,
  ) async {
    final expired = DateTime(2020, 2, 3, 4, 5).millisecondsSinceEpoch;
    await tester.pumpWidget(
      MaterialApp(
        home: PluginWorkspaceScreen(
          capabilities: const ['workspace.schedule'],
          runWorkspaceAction:
              (_, _) async => {
                ...presentation(),
                'host_connection': {
                  'target': 'vps',
                  'host': 'server.example',
                  'health': 'running',
                },
                'execution': {
                  'mode': 'vps',
                  'active': false,
                  'running': false,
                  'revoked': false,
                  'expires_at_ms': expired,
                },
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Permissions expired'), findsOneWidget);
    expect(find.textContaining('04:05'), findsOneWidget);
    expect(find.textContaining('Automatic cycle off.'), findsOneWidget);
    expect(find.textContaining('VPS process is running'), findsOneWidget);
    expect(find.textContaining('Permissions active'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final remote in [false, true]) {
    testWidgets(
      'Start permission names its destination and Cancel does not start ($remote)',
      (tester) async {
        final access = permission('https://one.example');
        final scope = {
          'version': 2,
          'action': 'run',
          'interval_seconds': 60,
          'description': 'Owner workflow',
          'access': access,
        };
        final observed = <String>[];
        Map<String, dynamic> nextView() => {
          ...presentation(),
          'actions': [
            {
              'id': 'start',
              'label': 'Begin workflow',
              'host': 'workspace.start',
            },
          ],
          'schedule': scope,
          'access': access,
          'execution': {'active': false, 'running': false},
          'host_connection': {
            'target': 'local',
            'selected': remote,
            if (remote) 'host': 'server.example',
          },
        };
        await tester.pumpWidget(
          MaterialApp(
            home: PluginWorkspaceScreen(
              capabilities: const ['workspace.schedule'],
              runWorkspaceAction: (action, _) async {
                observed.add(action);
                return nextView();
              },
              listSecrets:
                  () async => [
                    {'id': 'ref-token', 'label': 'Saved connection'},
                  ],
              configureExecution:
                  ({
                    required enabled,
                    required expiresAtMs,
                    expectedRevision,
                    revoke = false,
                    approvedScope,
                    credentialBindings,
                    settings = const {},
                  }) async => fail('Cancel must not grant or start execution'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('plugin-action-start')));
        await tester.pumpAndSettle();
        expect(observed, ['open']);
        expect(
          find.text(
            'Start on ${remote ? 'VPS server.example' : 'this device'}',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(observed, ['open']);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

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
      await tester.ensureVisible(
        find.byKey(const ValueKey('plugin-action-start')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plugin-action-start')));
      await tester.pumpAndSettle();
      expect(actions, ['open', 'open']);
      expect(selected, {'selection': 'new-choice'});
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'scheduled package result remains visible beside fresh observations',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction:
                (_, _) async => {
                  ...presentation(),
                  'message': 'Fresh observation ${++opens}',
                  'actions': [
                    {
                      'id': 'start',
                      'label': 'Run cycle now',
                      'host': 'workspace.start',
                    },
                    {
                      'id': 'stop',
                      'label': 'Stop and revoke access',
                      'host': 'workspace.stop',
                    },
                  ],
                  'fields': [
                    {
                      'id': 'repository',
                      'label': 'Repository',
                      'type': 'text',
                      'value': 'owner/project',
                    },
                  ],
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
      final start = find.byKey(const ValueKey('plugin-action-start'));
      final stop = find.byKey(const ValueKey('plugin-action-stop'));
      final result = find.text('Last cycle result');
      final configuration = find.text('Configuration');
      expect(tester.getBottomRight(stop).dy, lessThan(780));
      expect(
        tester.getTopLeft(start).dy,
        lessThan(tester.getTopLeft(result).dy),
      );
      expect(
        tester.getTopLeft(result).dy,
        lessThan(tester.getTopLeft(configuration).dy),
      );
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

  testWidgets(
    'long cycle receipt stays expandable above settings and does not replace a preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const receipt =
          'Service confirmed publication\nExact content ID: result-123\nPrepared content and provider evidence';
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            capabilities: const ['workspace.schedule'],
            runWorkspaceAction:
                (action, _) async => {
                  ...presentation(),
                  'message':
                      action == 'preview'
                          ? 'Prepared without sending'
                          : 'Fresh observation',
                  'actions': [
                    {'id': 'preview', 'label': 'Preview'},
                  ],
                  'fields': [
                    {
                      'id': 'repository',
                      'label': 'Repository',
                      'type': 'text',
                      'value': 'owner/project',
                    },
                  ],
                  'execution': {
                    'active': true,
                    'enabled': true,
                    'running': true,
                    'last_result': receipt,
                  },
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Service confirmed publication'), findsOneWidget);
      expect(find.text(receipt), findsNothing);
      await tester.tap(find.text('Service confirmed publication'));
      await tester.pumpAndSettle();
      expect(find.text(receipt), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plugin-action-preview')));
      await tester.pumpAndSettle();
      expect(find.text('Prepared without sending'), findsOneWidget);
      expect(find.text('Last cycle result'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
                  'saved': false,
                  'health': 'setup_unconfirmed',
                },
              };
            },
            connectVps: ({
              required host,
              required port,
              required password,
              required trustPeer,
              bool reinstall = false,
            }) async {
              connections++;
              throw busy;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Execution location: This device'), findsOneWidget);
      expect(find.textContaining('Execution location: VPS'), findsNothing);
      expect(
        find.textContaining('No assignment started from this Capsule'),
        findsOneWidget,
      );
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
      expect(find.textContaining('Execution location: VPS'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final trust in [false, true]) {
    testWidgets(
      'VPS connection confirms the presented identity before continuing (trust: $trust)',
      (tester) async {
        final actions = <String>[];
        bool? trusted;
        final fingerprint = 'SHA256:${'B' * 43}';
        await tester.pumpWidget(
          MaterialApp(
            home: PluginWorkspaceScreen(
              capabilities: const ['workspace.schedule'],
              runWorkspaceAction: (action, settings) async {
                actions.add(action);
                return {
                  ...presentation(),
                  'host_connection': {
                    'host': 'server.example',
                    'port': 22,
                    'saved': false,
                  },
                };
              },
              connectVps: ({
                required host,
                required port,
                required password,
                required trustPeer,
                bool reinstall = false,
              }) async {
                expect(host, 'server.example');
                expect(port, 22);
                expect(password, 'synthetic-test-password');
                trusted = await trustPeer(fingerprint);
                if (!trusted!) throw StateError('Server identity declined');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connect VPS'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byWidgetPredicate((w) => w is TextField && w.obscureText),
          'synthetic-test-password',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connect securely'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(trusted, isNull);
        expect(
          find.textContaining(
            'server.example:22\n$fingerprint',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(actions, ['open']);
        await tester.tap(find.text(trust ? 'Trust this server' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(trusted, trust);
        expect(actions, trust ? ['open', 'open'] : ['open']);
        expect(
          find.textContaining('VPS connection was not completed'),
          trust ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

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
        await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(submitted?['limit'], 1.25);
        expect(find.text('Current observation'), findsOneWidget);
        expect(find.text('Last action result'), findsOneWidget);
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
  for (final entry in {'empty': '', 'whitespace': ' \n\t'}.entries) {
    test(
      'opaque storage retains ${entry.key} values across runtime and package replacement',
      () async {
        final f = await Fixture.create();
        addTearDown(f.close);
        await f.enable();
        f.requestKind = 'storage.write';
        f.extraRequest = {'key': 'data-owner-value', 'value': entry.value};
        await f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        );
        expect(f.received.single, containsPair('written', true));

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
        await f.enable();
        f.requestKind = 'storage.read';
        f.extraRequest = {'key': 'data-owner-value'};
        f.received.clear();
        await f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'run',
        );
        expect(f.received.single, containsPair('value', entry.value));
        expect(f.sends, 0);
      },
    );

    test(
      'a retained ${entry.key} workspace cannot be reset before retry',
      () async {
        final f = await Fixture.create();
        addTearDown(f.close);
        await f.enable();
        final dir = await f.files.capsuleDirForHex(f.owner);
        final plugin = f.registry.record.pluginId!;
        await f.files.writePluginState(
          dir,
          plugin,
          'workspace.v1.json',
          entry.value,
        );
        await f.files.writePluginState(
          dir,
          plugin,
          'data-pending',
          'opaque pending request',
        );
        final grant = await f.files.readPluginState(
          dir,
          plugin,
          'workspace-execution.v1.json',
        );
        f.actions.clear();
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(
            f.runtime().runWorkspaceAction(
              record: f.registry.record,
              action: 'run',
            ),
            throwsA(isA<FormatException>()),
          );
          expect(f.actions, isEmpty);
          expect(f.sends, 0);
          expect(
            await f.files.readPluginState(dir, plugin, 'workspace.v1.json'),
            entry.value,
          );
          expect(
            await f.files.readPluginState(dir, plugin, 'data-pending'),
            'opaque pending request',
          );
          expect(
            await f.files.readPluginState(
              dir,
              plugin,
              'workspace-execution.v1.json',
            ),
            grant,
          );
        }
        final retained = {
          'different_private_shape': ['pending-request'],
        };
        await f.files.writePluginState(
          dir,
          plugin,
          'workspace.v1.json',
          jsonEncode(retained),
        );
        await f.runtime().runWorkspaceAction(
          record: f.registry.record,
          action: 'open',
        );
        expect(f.actions, ['open']);
        expect(f.sends, 0);
        expect(await f.state(), retained);
      },
    );
  }

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
      Map<String, dynamic>? execution = {
        'enabled': false,
        'active': false,
        'running': false,
        'revoked': true,
        'revision': 7,
        'scope': {
          'version': 2,
          'action': 'old_cycle',
          'interval_seconds': 60,
          'description': 'Previous workflow',
          'access': access,
        },
      };
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
              if (approvedScope?['start_action'] == 'start') starts++;
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
              if (action == 'start') {
                fail('The host must apply Start under its grant');
              }
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
      expect(execution!['running'], isFalse);
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
        UiEventLogService,
        WasmPluginSourceCatalogService {
  WasmPluginSourceCatalog? catalog;
  final logs = <String>[];
  @override
  Future<void> log(String source, String message) async {
    logs.add('$source $message');
  }

  @override
  Future<WasmPluginSourceCatalog> fetchCatalogWithFallback({
    String primaryCatalogUrl = WasmPluginSourceCatalogService.defaultCatalogUrl,
    String secondaryCatalogUrl =
        WasmPluginSourceCatalogService.fallbackCatalogUrl,
    String? localCatalogPathOverride,
  }) async => catalog ?? (throw StateError('Unexpected catalog read'));
  Future<void> Function()? beforeResolve;
  Future<void> Function(String, Set<String>)? onDeletePlugin;

  @override
  Future<void> deletePlugin(
    String pluginId, {
    required Set<String> capsuleHexes,
  }) async {
    final cleanup = onDeletePlugin;
    if (cleanup == null) throw StateError('Unexpected secret deletion');
    await cleanup(pluginId, capsuleHexes);
  }

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
  Object? loadError;
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
  Future<List<WasmPluginRecord>> loadPlugins() async {
    if (loadError != null) throw loadError!;
    return installed ? [record] : [];
  }

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
  bool newSchema = false, chain = false, requestOnOpen = false;
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
  final executionSeen = <Map<String, dynamic>>[];
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
        executionSeen.add(
          Map<String, dynamic>.from(request.args['execution'] as Map),
        );
        actions.add(action);
        await onInvoke?.call(action);
        final state = Map<String, dynamic>.from(
          request.args['state'] as Map? ?? {},
        );
        var requests = <Map<String, dynamic>>[];
        if (action == 'start') state['prepared_settings'] = settingsSeen.last;
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
        if (requestOnOpen && action == 'open') requests = [this.request()];
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
              if (registry.scheduled)
                'schedule': {
                  ...schedule,
                  if (action == 'start' &&
                      settingsSeen.last['interval'] != null)
                    'interval_seconds': settingsSeen.last['interval'],
                },
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
