import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/screens/plugin_workspace_screen.dart';
import 'package:hivra_app/services/bingx_market_data_adapter.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/services/plugin_runtime_module_service.dart';
import 'package:hivra_app/services/plugin_workspace_runtime.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_source_catalog_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';
import 'package:hivra_app/services/consensus_attestation_exchange_service.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';
import 'package:hivra_app/services/capsule_passive_receive_coordinator.dart';
import 'package:hivra_app/services/capsule_contact_label_store.dart';
import 'package:hivra_app/services/ui_event_log_service.dart';
import 'package:hivra_app/services/moltbook_runtime_module.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

import '../bin/plugin_workspace_runner.dart';

void main() {
  test(
    'runner socket restores authority, rejects duplicates and binds commands',
    () async {
      final root = await Directory('/tmp').createTemp('hivra_runner_');
      addTearDown(() => root.delete(recursive: true));
      expect((await Process.run('chmod', ['700', root.path])).exitCode, 0);
      final files = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(runtimeRootOverride: root.path),
      );
      final registry = _Registry();
      const owner =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      var digest = 'b' * 64;
      final scope = {
        'account_id': 'c' * 64,
        'symbol': 'DASH-USDT',
        'action': 'independent_cycle',
        'interval_seconds': 30,
        'max_margin': 1.0,
        'max_stop_percent': 20.0,
      };
      registry.executionBinding =
          () => PluginRuntimeBinding.externalPackage(
            packageId: registry.record.id,
            packageVersion: registry.record.pluginVersion,
            packageKind: 'zip',
            packageDigestHex: digest,
            contractKind: pluginWorkspaceContractKind,
            capabilities: const [
              'workspace.render',
              'workspace.continue',
              'state.plugin.read_write',
              'workspace.schedule',
            ],
          );
      var observed = 0;
      var providerDown = false;
      final host = PluginHostApiService(
        handlers: [],
        resolveRuntimeBinding: registry.resolveRuntimeBinding,
        resolveRuntimeInvoke: (request, _) async {
          if (providerDown) throw StateError('secret-key provider URL');
          observed++;
          return PluginRuntimeInvokeEvidence(
            mode: 'wasmi_v1',
            modulePath: 'plugin/module.wasm',
            moduleSelection: 'zip_manifest',
            moduleDigestHex: 'd' * 64,
            invokeDigestHex: 'e' * 64,
            semanticStatus: PluginHostApiStatus.executed,
            semanticErrorCode: null,
            semanticErrorMessage: null,
            semanticResult: {
              'state':
                  request.args['state'] ??
                  {
                    'unrelated_private_shape': ['not', 'Jack', 'fields'],
                  },
              'requests': <Object>[],
              'view': {...view(), 'schedule': scope},
            },
          );
        },
      );
      PluginWorkspaceRuntime runtime() => PluginWorkspaceRuntime(
        registry: registry,
        pluginHostApi: host,
        fileStore: files,
        readActiveCapsuleRootHex: () => owner,
        readCredentials:
            ({required owner, required pluginId}) async =>
                throw StateError('No credentials for this package'),
        writeCredentials:
            ({required owner, required pluginId, required value}) async =>
                throw StateError('No credential writes'),
      );
      final binding = {
        'owner': owner,
        'plugin_id': registry.record.pluginId,
        'package_id': registry.record.id,
        'package_digest': digest,
      };
      WorkspaceRunner runner() => WorkspaceRunner(
        root: root,
        runtime: runtime(),
        registry: registry,
        binding: binding,
      );
      final first = runner();
      addTearDown(first.close);
      await first.start();
      expect(
        observed,
        0,
        reason: 'Process startup must not require the provider',
      );
      Future<Map<String, dynamic>> command(
        String command, [
        Map<String, dynamic> fields = const {},
      ]) => WorkspaceRunner.request(root, {
        ...binding,
        'command': command,
        ...fields,
      });
      final initial = await command('status');
      expect(initial['ok'], true);
      expect(initial['result']['runner']['state'], 'running');
      expect(initial['result']['view']['execution'], isNull);
      providerDown = true;
      final unavailable = await command('status');
      expect(unavailable['ok'], true);
      expect(unavailable['result']['runner']['state'], 'running');
      expect(unavailable['result']['view'], isNull);
      expect(
        unavailable['result']['observation_error'],
        contains('unavailable'),
      );
      expect(jsonEncode(unavailable), isNot(contains('secret-key')));
      providerDown = false;
      await expectLater(runner().start(), throwsStateError);
      expect((await command('status'))['ok'], true);
      final mismatched = await command('status', {'owner': 'f' * 64});
      expect(mismatched['ok'], false);
      final before = observed;
      expect((await command('status', {'approvedOrder': {}}))['ok'], false);
      expect(observed, before, reason: 'Extra authority cannot reach WASM');
      final started = await command('execution', {
        'enabled': true,
        'scope': scope,
        'settings': <String, dynamic>{},
      });
      expect(started['ok'], true);
      expect(started['result']['view']['execution']['mode'], 'vps');
      expect(started['result']['view']['execution']['allow_new_entries'], true);
      final capsule = await files.capsuleDirForHex(owner);
      final grant = await files.readPluginState(
        capsule,
        registry.record.pluginId!,
        'workspace-execution.v1.json',
      );
      final state = await files.readPluginState(
        capsule,
        registry.record.pluginId!,
        'workspace.v1.json',
      );
      await first.close();
      final restarted = runner();
      addTearDown(restarted.close);
      await restarted.start();
      expect(
        (await command(
          'status',
        ))['result']['view']['execution']['allow_new_entries'],
        true,
      );
      expect(
        await files.readPluginState(
          capsule,
          registry.record.pluginId!,
          'workspace-execution.v1.json',
        ),
        grant,
        reason: 'Restart must not renew or replace authority',
      );
      expect(
        await files.readPluginState(
          capsule,
          registry.record.pluginId!,
          'workspace.v1.json',
        ),
        state,
        reason: 'Runner must not migrate private state',
      );
      final stopped = await command('execution', {
        'enabled': false,
        'scope': null,
        'settings': <String, dynamic>{},
      });
      expect(
        stopped['result']['view']['execution']['allow_new_entries'],
        false,
      );
      digest = 'f' * 64;
      expect((await command('status'))['ok'], false);
      await restarted.close();
      await expectLater(runner().start(), throwsStateError);
    },
  );
  test(
    'exact cancellation reconciles uncertainty and fill races without another DELETE',
    () async {
      for (final mode in [
        'cancelled',
        'unknown',
        'fill',
        'partial',
        'position',
        'foreign',
        'wrong_id',
        'revoked',
      ]) {
        final home = await Directory.systemTemp.createTemp('hivra_cancel_');
        addTearDown(() => home.delete(recursive: true));
        final files = CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
        );
        final provider =
            _EntryProvider()
              ..deleteTimeout = mode == 'unknown'
              ..deleteStaysOpen = mode == 'unknown'
              ..deleteFillRace = mode == 'fill';
        if (mode == 'partial') {
          provider.status = 'PARTIALLY_FILLED';
          provider.filled = '0.1';
        }
        if (mode == 'position') {
          provider.positionData = [
            {
              'symbol': 'BTC-USDT',
              'positionId': '42',
              'positionSide': 'LONG',
              'positionAmt': '0.1',
              'avgPrice': '96.4',
            },
          ];
        }
        if (mode == 'foreign') provider.clientIdOverride = 'f' * 40;
        if (mode == 'revoked') {
          provider.afterOrderRead = () async {
            provider.authorized = false;
          };
        }
        final plan = entryPlan();
        final orderId = mode == 'wrong_id' ? '999' : '2103610529511862272';
        final payload = jsonEncode({'order_id': orderId, 'plan': plan});
        final id = BingxMarketDataAdapter.cancelOperationId(plan, orderId);
        ExternalEffectService effects() => ExternalEffectService(
          readActiveCapsuleRootHex: () => 'a' * 64,
          fileStore: files,
          resolveAdapter: (_) => provider.adapter(),
        );
        final service = effects();
        final prepared = await service.prepare(
          operationId: id,
          pluginId: 'hivra.contract.jack-ventura.v1',
          providerId: 'bingx',
          accountBindingId: plan['account_id'],
          effectKind: 'order.entry.cancel',
          canonicalPayloadJson: payload,
        );
        await service.approve(
          pluginId: prepared.pluginId,
          operationId: id,
          approvalEvidenceHashHex: prepared.payloadHashHex,
        );
        await service.enqueue(pluginId: prepared.pluginId, operationId: id);
        final result = await service.process(
          pluginId: prepared.pluginId,
          operationId: id,
        );
        expect(provider.posts, 0);
        expect(
          provider.deletes,
          ['cancelled', 'unknown', 'fill'].contains(mode) ? 1 : 0,
          reason: mode,
        );
        expect(
          result.state,
          ['unknown', 'fill'].contains(mode)
              ? ExternalEffectState.unresolved
              : mode == 'cancelled'
              ? ExternalEffectState.succeeded
              : ExternalEffectState.terminalFailure,
          reason: mode,
        );
        if (result.state != ExternalEffectState.terminalFailure) {
          await effects().process(pluginId: prepared.pluginId, operationId: id);
          expect(
            provider.deletes,
            1,
            reason: 'Restart must not repeat DELETE: $mode',
          );
        } else {
          expect(result.lastErrorCode, 'cancel_not_sent');
        }
        if (mode == 'fill') {
          final observed = await provider.adapter().readEntry(
            entryEffect(plan),
          );
          expect(observed['status'], 'partial');
          expect(observed['filled_quantity'], 0.1);
        }
        expect(
          provider.deleteParams?['orderId'],
          provider.deletes == 0 ? null : '2103610529511862272',
        );
      }
    },
  );

  testWidgets('Start requires consent and Stop stays available during reads', (
    tester,
  ) async {
    var enabled = false;
    var grants = 0;
    final reading = Completer<void>();
    Map<String, dynamic> shown() => {
      ...view(),
      'fields': <dynamic>[],
      'schedule': {
        'action': 'package_cycle',
        'interval_seconds': 60,
        'account_id': 'a' * 64,
        'symbol': 'BTC-USDT',
        'max_margin': 1,
        'max_stop_percent': 10,
      },
      if (grants > 0)
        'execution': {'allow_new_entries': enabled, 'expires_at_ms': 200000000},
      'actions': [
        {
          'id': enabled ? 'stop' : 'start',
          'label': enabled ? 'Stop new entries' : 'Start cycles',
          'host': enabled ? 'workspace.stop' : 'workspace.start',
        },
        {'id': 'read', 'label': 'Read observations'},
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: PluginWorkspaceScreen(
          runWorkspaceAction: (
            action,
            settings, {
            credentials,
            approvedOrder,
          }) async {
            expect(credentials, isNull);
            expect(approvedOrder, isNull);
            if (action == 'read') await reading.future;
            return shown();
          },
          configureExecution: ({
            required enabled,
            approvedScope,
            settings = const {},
          }) async {
            if (enabled) {
              expect(approvedScope, shown()['schedule']);
              grants++;
            }
            // Keep the test's host state separate from the parameter.
            final data = shown();
            data['execution'] = {
              'allow_new_entries': enabled,
              'expires_at_ms': 200000000,
            };
            data['actions'] = [
              {
                'id': enabled ? 'stop' : 'start',
                'label': enabled ? 'Stop new entries' : 'Start cycles',
                'host': enabled ? 'workspace.stop' : 'workspace.start',
              },
              {'id': 'read', 'label': 'Read observations'},
            ];
            return data;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start cycles'));
    await tester.pumpAndSettle();
    expect(find.text('Start local LIVE cycles for 24 hours?'), findsOneWidget);
    expect(grants, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(grants, 0);
    await tester.tap(find.text('Start cycles'));
    await tester.pumpAndSettle();
    enabled = true;
    await tester.tap(find.byKey(const ValueKey('plugin-confirm-start')));
    await tester.pumpAndSettle();
    expect(grants, 1);
    expect(
      find.textContaining('No cycle observed in this process'),
      findsOneWidget,
    );
    await tester.tap(find.text('Read observations'));
    await tester.pump();
    enabled = false;
    await tester.tap(find.text('Stop new entries'));
    await tester.pump();
    expect(
      find.textContaining('New entries stopped or expired'),
      findsOneWidget,
    );
    reading.complete();
    await tester.pumpAndSettle();
    expect(grants, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test(
    'scheduled entries use host grants, opaque state and the existing journal',
    () async {
      for (final fault in [
        'none',
        'stop',
        'expire',
        'account',
        'margin',
        'loss',
        'replace',
        'during_read',
        'cancel',
        'cancel_unknown',
        'cancel_fill',
        'cancel_unjournaled',
        'cancel_during_read',
        'cancel_revoked',
        'cancel_replaced',
        'exit',
        'exit_stop',
        'exit_unknown',
        'exit_unjournaled',
        'exit_replaced',
        'exit_revoked',
        'exit_position',
        'exit_oneway',
        'exit_removed',
        'exit_unsafe_evidence',
      ]) {
        final home = await Directory.systemTemp.createTemp('hivra_scheduled_');
        addTearDown(() => home.delete(recursive: true));
        final files = CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
        );
        final registry = _Registry();
        final fixture = _EntryProvider();
        final cancelling = fault.startsWith('cancel');
        final exiting = fault.startsWith('exit');
        if (exiting) {
          fixture.exitMode = true;
          fixture.status = 'FILLED';
          fixture.filled = '0.518';
          fixture.positionData = [
            {
              'symbol': 'BTC-USDT',
              'positionId': '42',
              'positionSide': 'LONG',
              'positionAmt': fault == 'exit_position' ? '0.1' : '0.518',
              'avgPrice': '96.4',
            },
          ];
          fixture.postTimeout = fault == 'exit_unknown';
          fixture.exitQueryUnavailable = fault == 'exit_unknown';
          if (['exit_oneway', 'exit_unsafe_evidence'].contains(fault)) {
            fixture.modeData = {'dualSidePosition': false};
            fixture.positionSide = 'BOTH';
          }
          fixture.unsafeExit = fault == 'exit_unsafe_evidence';
        }
        if (cancelling) {
          fixture.deleteTimeout = fault == 'cancel_unknown';
          fixture.deleteStaysOpen = fault == 'cancel_unknown';
          fixture.deleteFillRace = fault == 'cancel_fill';
        }
        final plan = entryPlan();
        final exitPlan = {
          'entry_plan': plan,
          'position_id': '42',
          'quantity': 0.518,
          'average_price': 96.4,
          'price': 105.0,
          'prepared_at_ms': fixture.now,
          'expires_at_ms': fixture.now + 60000,
        };
        final effectRequest = {
          'kind':
              exiting
                  ? 'position.exit.place'
                  : cancelling
                  ? 'order.entry.cancel'
                  : 'order.entry.place',
          'provider': 'bingx',
          'plan': exiting ? exitPlan : plan,
          if (cancelling) 'order_id': '2103610529511862272',
        };
        final owner = 'a' * 64;
        var digest = 'b' * 64;
        final scope = {
          'action': 'package_cycle',
          'interval_seconds': 60,
          'account_id': plan['account_id'],
          'symbol': 'BTC-USDT',
          'max_margin': 1.0,
          'max_stop_percent': 20.0,
        };
        registry.executionBinding =
            () => PluginRuntimeBinding.externalPackage(
              packageId: registry.record.id,
              packageVersion: '0.1.0',
              packageKind: 'zip',
              packageDigestHex: digest,
              contractKind: pluginWorkspaceContractKind,
              capabilities: [
                'workspace.render',
                'workspace.continue',
                'workspace.schedule',
                'state.plugin.read_write',
                'order.entry.place',
                if (fault != 'cancel_revoked') 'order.entry.cancel',
                'order.snapshot.read',
                'position.snapshot.read',
                if (fault != 'exit_revoked') 'position.exit.place',
                'market.candles.read',
              ],
            );
        final host = PluginHostApiService(
          handlers: [],
          resolveRuntimeBinding:
              (_) => registry.resolveRuntimeBinding(registry.record.pluginId!),
          resolveRuntimeInvoke: (request, _) async {
            final action = request.args['action'];
            final previous = request.args['state'] as Map?;
            var sent = previous?['unrelated_bundle'] == true;
            final requests = <Map<String, dynamic>>[];
            if (action == 'package_send') {
              sent = !cancelling;
              requests.add(effectRequest);
            }
            if (cancelling && action == 'lifecycle') {
              // An unrelated package shape decides from normalized evidence,
              // not a host inspection of its private state.
              sent =
                  (request.args['snapshot'] as Map)['entry']['status'] !=
                  'open';
            }
            if (cancelling && action == 'package_cycle' && sent) {
              requests.add({
                'kind': 'order.snapshot.read',
                'scope': 'lifecycle',
                'provider': 'bingx',
                'plan': plan,
              });
            }
            if (action == 'validate_entry' &&
                request.args['snapshot'] == null) {
              requests.add({
                'kind': 'market.candles.read',
                'provider': 'bingx',
                'symbol': 'BTC-USDT',
                'timeframe': '5m',
                'limit': 600,
              });
            }
            final presentation = {
              ...view(),
              'schedule': scope,
              'confirmation':
                  action == 'package_cycle' && !sent ? effectRequest : null,
              'actions': [
                {
                  'id': 'package_send',
                  'label': 'Entry',
                  'host': 'bingx.order.submit',
                },
              ],
            };
            expect(jsonEncode(request.args), isNot(contains('test-secret')));
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
                'state': {'unrelated_bundle': sent},
                'view': presentation,
                'requests': requests,
              },
            );
          },
        );
        PluginWorkspaceRuntime runtime() => PluginWorkspaceRuntime(
          registry: registry,
          pluginHostApi: host,
          fileStore: files,
          market: fixture.adapter(),
          scheduleTimers: false,
          readActiveCapsuleRootHex: () => owner,
          readCredentials:
              ({required owner, required pluginId}) async => jsonEncode({
                'api_key': 'test-key',
                'secret_key': 'test-secret',
              }),
          writeCredentials:
              ({required owner, required pluginId, required value}) async =>
                  fail('No credential write'),
        );
        final executor = runtime();
        await expectLater(
          executor.runScheduledWorkspaceCycle(registry.record),
          throwsStateError,
        );
        await executor.setWorkspaceExecution(
          record: registry.record,
          enabled: true,
          approvedScope: scope,
        );
        final directory = await files.capsuleDirForHex(owner);
        if ((cancelling || exiting) &&
            !['cancel_unjournaled', 'exit_unjournaled'].contains(fault)) {
          final keys = plan.keys.toList()..sort();
          await ExternalEffectService(
            readActiveCapsuleRootHex: () => owner,
            fileStore: files,
            resolveAdapter: (_) => null,
          ).prepare(
            operationId: BingxMarketDataAdapter.entryOperationId(plan),
            pluginId: registry.record.pluginId!,
            providerId: 'bingx',
            accountBindingId: plan['account_id'],
            effectKind: 'order.entry.place',
            canonicalPayloadJson: jsonEncode({
              for (final k in keys) k: plan[k],
            }),
          );
        }
        Future<void> revoke() async {
          final saved =
              jsonDecode(
                    (await files.readPluginState(
                      directory,
                      registry.record.pluginId!,
                      'workspace-execution.v1.json',
                    ))!,
                  )
                  as Map;
          await files.writePluginState(
            directory,
            registry.record.pluginId!,
            'workspace-execution.v1.json',
            jsonEncode({
              ...saved,
              'allow_new_entries': false,
              'revision': (saved['revision'] as int) + 1,
            }),
          );
        }

        if (fault == 'stop' || fault == 'exit_stop') {
          await executor.setWorkspaceExecution(
            record: registry.record,
            enabled: false,
          );
        }
        if (fault == 'expire') {
          final saved =
              jsonDecode(
                    (await files.readPluginState(
                      directory,
                      registry.record.pluginId!,
                      'workspace-execution.v1.json',
                    ))!,
                  )
                  as Map;
          await files.writePluginState(
            directory,
            registry.record.pluginId!,
            'workspace-execution.v1.json',
            jsonEncode({...saved, 'expires_at_ms': 1}),
          );
        }
        if (fault == 'account') plan['account_id'] = 'd' * 64;
        if (fault == 'margin') plan['margin'] = 2.0;
        if (fault == 'loss') plan['stop_price'] = 90.0;
        if (fault == 'replace') digest = 'c' * 64;
        if (fault == 'during_read') fixture.beforeMarketRead = revoke;
        if (fault == 'cancel_during_read') fixture.afterOrderRead = revoke;
        if (fault == 'cancel_replaced') {
          fixture.afterOrderRead = () async {
            digest = 'c' * 64;
          };
        }
        if (fault == 'exit_replaced') {
          fixture.afterModeRead = () => digest = 'c' * 64;
        }
        if (fault == 'exit_removed') {
          fixture.afterModeRead = () => registry.installed = false;
        }
        if ([
          'account',
          'margin',
          'loss',
          'replace',
          'cancel_unjournaled',
          'cancel_revoked',
          'cancel_during_read',
          'cancel_replaced',
          'exit_unjournaled',
          'exit_revoked',
          'exit_replaced',
          'exit_unknown',
          'exit_removed',
          'exit_unsafe_evidence',
        ].contains(fault)) {
          await expectLater(
            executor.runScheduledWorkspaceCycle(registry.record),
            throwsStateError,
            reason: fault,
          );
        } else {
          await executor.runScheduledWorkspaceCycle(registry.record);
        }
        expect(
          fixture.posts,
          [
                'none',
                'exit',
                'exit_stop',
                'exit_unknown',
                'exit_oneway',
                'exit_unsafe_evidence',
              ].contains(fault)
              ? 1
              : 0,
          reason: fault,
        );
        if ([
          'exit',
          'exit_stop',
          'exit_unknown',
          'exit_oneway',
          'exit_unsafe_evidence',
        ].contains(fault)) {
          expect(fixture.postParams!['side'], 'SELL');
          final oneWay = [
            'exit_oneway',
            'exit_unsafe_evidence',
          ].contains(fault);
          expect(fixture.postParams!['positionSide'], oneWay ? 'BOTH' : 'LONG');
          expect(fixture.postParams!['reduceOnly'], oneWay ? 'true' : null);
          expect(fixture.postParams!.containsKey('closePosition'), false);
          expect(fixture.postParams!['positionId'], '42');
          final journal = ExternalEffectService(
            readActiveCapsuleRootHex: () => owner,
            fileStore: files,
            resolveAdapter: (_) => fixture.adapter(),
          );
          final operation = (await journal.list(
            pluginId: registry.record.pluginId!,
          )).singleWhere((o) => o.effectKind == 'position.exit.place');
          expect(
            operation.state,
            ['exit_unknown', 'exit_unsafe_evidence'].contains(fault)
                ? ExternalEffectState.unresolved
                : ExternalEffectState.succeeded,
          );
          fixture.exitQueryUnavailable = false;
          fixture.unsafeExit = false;
          await journal.process(
            pluginId: operation.pluginId,
            operationId: operation.operationId,
          );
          expect(
            fixture.posts,
            1,
            reason: 'Restart reconciles the same exit without another POST',
          );
        }
        expect(
          fixture.deletes,
          ['cancel', 'cancel_unknown', 'cancel_fill'].contains(fault) ? 1 : 0,
          reason: fault,
        );
        if (['cancel', 'cancel_unknown', 'cancel_fill'].contains(fault)) {
          await runtime().runScheduledWorkspaceCycle(registry.record);
          expect(
            fixture.deletes,
            1,
            reason: 'Reopen must reconcile, not repeat cancellation',
          );
          expect(fixture.posts, 0);
          final operations = await ExternalEffectService(
            readActiveCapsuleRootHex: () => owner,
            fileStore: files,
            resolveAdapter: (_) => null,
          ).list(pluginId: registry.record.pluginId!);
          expect(
            operations
                .where((o) => o.effectKind == 'order.entry.cancel')
                .single
                .state,
            fault == 'cancel'
                ? ExternalEffectState.succeeded
                : ExternalEffectState.unresolved,
          );
          if (fault == 'cancel_fill') {
            fixture.status = 'FILLED';
            fixture.filled = '0.518';
            await runtime().runScheduledWorkspaceCycle(registry.record);
            final resolved = await ExternalEffectService(
              readActiveCapsuleRootHex: () => owner,
              fileStore: files,
              resolveAdapter: (_) => null,
            ).list(pluginId: registry.record.pluginId!);
            expect(
              resolved
                  .where((o) => o.effectKind == 'order.entry.cancel')
                  .single
                  .state,
              ExternalEffectState.succeeded,
            );
            expect(fixture.deletes, 1);
            expect(fixture.posts, 0);
          }
        }
        if (fault == 'none') {
          await runtime().runScheduledWorkspaceCycle(registry.record);
          expect(
            fixture.posts,
            1,
            reason: 'Restart must not duplicate an entry',
          );
          final journal = ExternalEffectService(
            readActiveCapsuleRootHex: () => owner,
            fileStore: files,
            resolveAdapter: (_) => null,
          );
          expect(
            (await journal.list(pluginId: registry.record.pluginId!)).length,
            1,
          );
          expect(
            await files.readPluginState(
              directory,
              registry.record.pluginId!,
              'workspace.v1.json',
            ),
            '{"unrelated_bundle":true}',
          );
          await executor.setWorkspaceExecution(
            record: registry.record,
            enabled: false,
          );
          final saved = await files.readPluginState(
            directory,
            registry.record.pluginId!,
            'workspace-execution.v1.json',
          );
          expect(jsonDecode(saved!)['allow_new_entries'], false);
          expect(saved, isNot(contains('test-secret')));
        }
      }
    },
  );
  test(
    'lifecycle evidence uses explicit grants and revalidates ownership after reads',
    () async {
      for (final fault in [
        'none',
        'denied',
        'revoked',
        'replaced',
        'capsule',
      ]) {
        final home = await Directory.systemTemp.createTemp(
          'hivra_lifecycle_scope_',
        );
        addTearDown(() => home.delete(recursive: true));
        final files = CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
        );
        final registry = _Registry();
        var owner = 'a' * 64;
        var digest = 'b' * 64;
        var positionGrant = fault != 'denied';
        final fixture = _EntryProvider();
        final plan = entryPlan();
        final keys = plan.keys.toList()..sort();
        final operationId = BingxMarketDataAdapter.entryOperationId(plan);
        final effects = ExternalEffectService(
          readActiveCapsuleRootHex: () => owner,
          fileStore: files,
          resolveAdapter: (_) => fixture.adapter(),
        );
        final operation = await effects.prepare(
          operationId: operationId,
          pluginId: registry.record.pluginId!,
          providerId: 'bingx',
          accountBindingId: plan['account_id'] as String,
          effectKind: 'order.entry.place',
          canonicalPayloadJson: jsonEncode({
            for (final key in keys) key: plan[key],
          }),
        );
        await effects.approve(
          pluginId: registry.record.pluginId!,
          operationId: operationId,
          approvalEvidenceHashHex: operation.payloadHashHex,
        );
        await effects.enqueue(
          pluginId: registry.record.pluginId!,
          operationId: operationId,
        );
        await effects.process(
          pluginId: registry.record.pluginId!,
          operationId: operationId,
        );
        fixture.posts = 0;
        fixture.afterOpenOrdersRead = () {
          if (fault == 'revoked') positionGrant = false;
          if (fault == 'replaced') digest = 'c' * 64;
          if (fault == 'capsule') owner = 'd' * 64;
        };
        Map<String, dynamic>? admitted;
        final host = PluginHostApiService(
          handlers: [],
          resolveRuntimeBinding:
              (_) async => PluginRuntimeBinding.externalPackage(
                packageId: registry.record.id,
                packageVersion: '1.0.0',
                packageKind: 'zip',
                packageDigestHex: digest,
                contractKind: pluginWorkspaceContractKind,
                capabilities: [
                  'workspace.render',
                  'workspace.continue',
                  'state.plugin.read_write',
                  'order.snapshot.read',
                  if (positionGrant) 'position.snapshot.read',
                ],
              ),
          resolveRuntimeInvoke: (request, binding) async {
            if (request.args['action'] == 'lifecycle') {
              admitted = Map<String, dynamic>.from(
                request.args['snapshot'] as Map,
              );
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
                'state': {
                  'opaque': [1, 2, 3],
                },
                'view': view(),
                'requests':
                    request.args['action'] == 'observe_position'
                        ? [
                          {
                            'kind': 'order.snapshot.read',
                            'scope': 'lifecycle',
                            'provider': 'bingx',
                            'plan': plan,
                          },
                        ]
                        : [],
              },
            );
          },
        );
        final runtime = PluginWorkspaceRuntime(
          registry: registry,
          pluginHostApi: host,
          fileStore: files,
          market: fixture.adapter(),
          readActiveCapsuleRootHex: () => owner,
          readCredentials:
              ({required owner, required pluginId}) async => jsonEncode({
                'api_key': 'test-key',
                'secret_key': 'test-secret',
              }),
          writeCredentials:
              ({required owner, required pluginId, required value}) async =>
                  fail('No credential writes are authorized'),
        );
        final observation = runtime.runWorkspaceAction(
          record: registry.record,
          action: 'observe_position',
        );
        if (fault == 'none') {
          await observation;
          expect(admitted?['account_id'], plan['account_id']);
          expect(admitted?['positions'], isEmpty);
          expect(
            (admitted?['entry'] as Map)['order_id'],
            '2103610529511862272',
          );
          expect(jsonEncode(admitted), isNot(contains('test-secret')));
        } else {
          await expectLater(observation, throwsStateError);
          expect(admitted, isNull, reason: fault);
        }
        expect(fixture.posts, 0, reason: fault);
      }
    },
  );
  test(
    'workspace executor compiles and runs without Flutter or a platform vault',
    () async {
      final output = await Directory.systemTemp.createTemp(
        'hivra_headless_binary_',
      );
      addTearDown(() => output.delete(recursive: true));
      final executable = '${output.path}/workspace-probe';
      final compiled = await Process.run('dart', [
        'compile',
        'exe',
        'test/fixtures/plugin_workspace_headless_probe.dart',
        '-o',
        executable,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      final checked = await Process.run(executable, []);
      expect(
        checked.exitCode,
        0,
        reason: '${checked.stdout}\n${checked.stderr}',
      );
      expect(checked.stdout, contains('headless workspace PASS'));
    },
  );
  test(
    'lifecycle observation is exact, bounded and read-only; failure is not flat',
    () async {
      final fixture =
          _EntryProvider()
            ..status = 'FILLED'
            ..filled = '0.518'
            ..positionData = [
              {
                'symbol': 'BTC-USDT',
                'positionId': '123',
                'positionSide': 'LONG',
                'positionAmt': '0.518',
                'avgPrice': '96.4',
              },
            ];
      final effect = entryEffect(entryPlan());
      final observed = await fixture.adapter().readLifecycle(effect);
      expect((observed['entry'] as Map)['status'], 'filled');
      expect(observed['positions'], [
        {
          'position_id': '123',
          'side': 'long',
          'quantity': 0.518,
          'average_price': 96.4,
        },
      ]);
      expect(observed['orders'], isEmpty);
      for (final malformed in [
        null,
        {},
        [
          {'symbol': 'ETH-USDT', 'positionAmt': '0'},
        ],
        [
          {'symbol': 'BTC-USDT', 'positionAmt': 'NaN'},
        ],
        [
          {'symbol': 'BTC-USDT', 'positionAmt': '1'},
        ],
        List.generate(65, (_) => {'symbol': 'BTC-USDT', 'positionAmt': '0'}),
        [fixture.positionData.single, fixture.positionData.single],
      ]) {
        fixture.positionData = malformed;
        await expectLater(
          fixture.adapter().readLifecycle(effect),
          throwsFormatException,
        );
      }
      fixture.positionData = [];
      expect(
        (await fixture.adapter().readLifecycle(effect))['positions'],
        isEmpty,
      );
      fixture.positionData = [
        {
          'symbol': 'BTC-USDT',
          'positionId': '124',
          'positionSide': 'BOTH',
          'positionAmt': '-0.1',
          'avgPrice': '100',
        },
      ];
      expect((await fixture.adapter().readLifecycle(effect))['positions'], [
        {
          'position_id': '124',
          'side': 'short',
          'quantity': 0.1,
          'average_price': 100,
        },
      ]);
      fixture.afterOpenOrdersRead = () => fixture.now += 60001;
      await expectLater(
        fixture.adapter().readLifecycle(effect),
        throwsStateError,
      );
      expect(fixture.posts, 0);
    },
  );
  test('entry identity binds the complete plan, independent of map order', () {
    final plan = entryPlan();
    final id = BingxMarketDataAdapter.entryOperationId(plan);
    expect(
      BingxMarketDataAdapter.entryOperationId(
        Map.fromEntries(plan.entries.toList().reversed),
      ),
      id,
    );
    for (final field in [
      'price',
      'quantity',
      'stop_price',
      'margin',
      'leverage',
      'prepared_at_ms',
      'expires_at_ms',
    ]) {
      final changed = {...plan, field: (plan[field] as num) + 1};
      expect(BingxMarketDataAdapter.entryOperationId(changed), isNot(id));
    }
  });

  test(
    'workspace effect approval, package pinning and reinstall use one durable operation',
    () async {
      const placementAction = 'confirm_package_entry';
      const preparationAction = 'update_plan';
      const completionAction = 'finish_selected_plan';
      for (final mode in [
        'normal',
        'normal_15m',
        'denied',
        'replaced',
        'not_sent',
        'missing_evidence',
        'foreign_evidence',
        'nested_evidence',
        'market_denied',
        'evidence_replaced',
      ]) {
        final home = await Directory.systemTemp.createTemp(
          'hivra_workspace_entry_',
        );
        addTearDown(() => home.delete(recursive: true));
        final files = CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
        );
        final registry = _Registry();
        final vault = _Vault();
        var owner = 'a' * 64;
        final plan = entryPlan();
        final request = {
          'kind': 'order.entry.place',
          'provider': 'bingx',
          'plan': plan,
        };
        var packageDigest = 'c' * 64;
        var orderReadGrant = true;
        var listRequest = openOrdersRequest();
        var listAdmissions = 0;
        String? recoveryFault;
        var recoveryAdmissions = 0;
        final recoverySnapshots = <Map>[];
        final validationSnapshots = <Map>[];
        final fixture = _EntryProvider();
        if (mode == 'normal_15m') {
          fixture.evidenceTimeframe = '15m';
          fixture.evidenceLimit = 49;
        }
        if (mode == 'not_sent') fixture.existingOrder = true;
        if (mode == 'replaced') {
          fixture.afterModeRead = () => packageDigest = 'f' * 64;
        }
        if (mode == 'evidence_replaced') {
          fixture.afterMarketRead = () => packageDigest = 'f' * 64;
        }
        final host = PluginHostApiService(
          handlers: [],
          resolveRuntimeBinding:
              (_) async => PluginRuntimeBinding.externalPackage(
                packageId: registry.record.id,
                packageVersion: '0.1.0',
                packageKind: 'zip',
                packageDigestHex: packageDigest,
                contractKind: pluginWorkspaceContractKind,
                capabilities: [
                  'workspace.render',
                  'workspace.continue',
                  'state.plugin.read_write',
                  if (orderReadGrant) 'order.snapshot.read',
                  if (mode != 'denied') 'order.entry.place',
                  if (mode != 'market_denied') 'market.candles.read',
                ],
              ),
          resolveRuntimeInvoke: (call, _) async {
            final state = Map<String, dynamic>.from(
              (call.args['state'] as Map?)?['package_state'] as Map? ??
                  {
                    'account': {'account_id': plan['account_id']},
                    'settings': {'symbol': 'BTC-USDT'},
                  },
            );
            final action = call.args['action'];
            final requests = <Map<String, dynamic>>[];
            if (action == 'open' &&
                (state['entry'] as Map?)?['attempted'] != true) {
              requests.add({
                'kind': 'order.snapshot.read',
                'scope': 'durable',
                'provider': 'bingx',
                'account_id': plan['account_id'],
              });
            }
            if (action == placementAction) {
              state['entry'] = {'plan': plan, 'attempted': true};
              requests.add(request);
            }
            if (action == 'validate_entry') {
              if (call.args['snapshot'] == null) {
                if (mode != 'missing_evidence') {
                  requests.add({
                    'kind':
                        mode == 'nested_evidence'
                            ? 'order.entry.place'
                            : 'market.candles.read',
                    'provider': 'bingx',
                    'symbol':
                        mode == 'foreign_evidence'
                            ? 'ETH-USDT'
                            : plan['symbol'],
                    'timeframe': fixture.evidenceTimeframe,
                    'limit': fixture.evidenceLimit,
                  });
                }
              } else {
                validationSnapshots.add(call.args['snapshot'] as Map);
              }
            }
            if (action == preparationAction) {
              state['entry'] = null;
              requests.add(marketRequest());
            }
            if (action == completionAction) {
              state['entry'] = {'plan': plan, 'attempted': false};
            }
            if (action == 'refresh_order') {
              requests.add({...request, 'kind': 'order.snapshot.read'});
            }
            if (action == 'list_orders') {
              requests.add(listRequest);
              // Rendering may reorder JSON; an observation must not rewrite state.
              final fields = state.entries.toList().reversed.toList();
              state
                ..clear()
                ..addEntries(fields);
            }
            if (action == 'open_orders') listAdmissions++;
            if (action == 'order') {
              (state['entry'] as Map)['evidence'] = call.args['snapshot'];
            }
            if (action == 'restore_entry') {
              recoveryAdmissions++;
              recoverySnapshots.add(call.args['snapshot'] as Map);
              if (recoveryFault == 'reject' && recoveryAdmissions == 2) {
                throw StateError('Package rejected the remaining history');
              }
              for (final operation
                  in (call.args['snapshot'] as Map)['operations'] as List) {
                if (operation['state'] == 'terminal_failure' &&
                    [
                      'entry_not_sent',
                      'provider_rejected',
                    ].contains(operation['last_error_code']) &&
                    operation['receipt'] == null) {
                  continue;
                }
                state['entry'] = {
                  'plan': jsonDecode(
                    operation['canonical_payload_json'] as String,
                  ),
                  'attempted': true,
                };
              }
              if (recoveryAdmissions == 1) {
                if (recoveryFault == 'replace') packageDigest = 'f' * 64;
                if (recoveryFault == 'capsule') owner = 'b' * 64;
                if (recoveryFault == 'remove') registry.installed = false;
                if (recoveryFault == 'revoke') orderReadGrant = false;
                if (recoveryFault == 'nested') requests.add(request);
              }
            }
            expect(jsonEncode(call.args), isNot(contains('test-secret')));
            return PluginRuntimeInvokeEvidence(
              mode: 'wasmi_v1',
              modulePath: 'plugin/module.wasm',
              moduleSelection: 'manifest_module_path',
              moduleDigestHex: 'd' * 64,
              invokeDigestHex: 'e' * 64,
              semanticStatus: PluginHostApiStatus.executed,
              semanticErrorCode: null,
              semanticErrorMessage: null,
              semanticResult: {
                'state': {'package_state': state},
                'view':
                    action == 'open_orders'
                        ? {
                          ...view(),
                          'details_title': 'Open orders',
                          'columns': ['Order ID'],
                          'rows': [
                            for (final order
                                in (call.args['snapshot'] as Map)['orders']
                                    as List)
                              [order['order_id']],
                          ],
                        }
                        : view(),
                'requests': requests,
                if (action == preparationAction)
                  'resume_action': completionAction,
              },
            );
          },
        );
        PluginRuntimeModule module() => PluginRuntimeModule(
          registry: registry,
          sourceCatalog: const WasmPluginSourceCatalogService(),
          manualChecks: _Manual(),
          pluginHostApi: host,
          attestationExchange: _Attestations(),
          chatDelivery: _Delivery(),
          passiveReceive: _Passive(),
          contactLabels: _Labels(),
          uiLog: const UiEventLogService(),
          moltbook: _Moltbook(),
          fileStore: files,
          secretVault: vault,
          readActiveCapsuleRootHex: () => owner,
          market: fixture.adapter(),
        );
        await vault.saveSecret(
          capsuleHex: owner,
          pluginId: registry.record.pluginId!,
          providerId: 'bingx',
          accountId: 'primary',
          secretName: 'credentials',
          secretValue: jsonEncode({
            'api_key': 'test-key',
            'secret_key': 'test-secret',
          }),
        );
        await expectLater(
          module().runWorkspaceAction(
            record: registry.record,
            action: placementAction,
          ),
          throwsStateError,
        );
        expect(fixture.posts, 0);
        final initialDirectory = await files.capsuleDirForHex(owner);
        expect(
          await files.readPluginState(
            initialDirectory,
            registry.record.pluginId!,
            'workspace.v1.json',
          ),
          isNull,
        );
        await expectLater(
          module().runWorkspaceAction(
            record: registry.record,
            action: placementAction,
            approvedOrder: {
              ...request,
              'plan': {...plan, 'price': 1},
            },
          ),
          throwsStateError,
        );
        expect(
          await files.readPluginState(
            initialDirectory,
            registry.record.pluginId!,
            'workspace.v1.json',
          ),
          isNull,
        );
        expect(fixture.posts, 0);
        if (mode == 'denied' ||
            mode == 'replaced' ||
            mode == 'evidence_replaced') {
          await expectLater(
            module().runWorkspaceAction(
              record: registry.record,
              action: placementAction,
              approvedOrder: request,
            ),
            throwsStateError,
          );
          expect(fixture.posts, 0);
          if (mode == 'evidence_replaced') {
            final failed = await ExternalEffectService(
              readActiveCapsuleRootHex: () => owner,
              fileStore: files,
              resolveAdapter: (_) => fixture.adapter(),
            ).list(pluginId: registry.record.pluginId!);
            expect(failed.single.lastErrorCode, 'entry_not_sent');
          }
          continue;
        }
        await module().runWorkspaceAction(
          record: registry.record,
          action: placementAction,
          approvedOrder: request,
        );
        if ([
          'missing_evidence',
          'foreign_evidence',
          'nested_evidence',
          'market_denied',
          'evidence_replaced',
        ].contains(mode)) {
          expect(fixture.posts, 0, reason: mode);
          final failed = await ExternalEffectService(
            readActiveCapsuleRootHex: () => owner,
            fileStore: files,
            resolveAdapter: (_) => fixture.adapter(),
          ).list(pluginId: registry.record.pluginId!);
          expect(failed.single.lastErrorCode, 'entry_not_sent', reason: mode);
          continue;
        }
        if (mode == 'not_sent') {
          expect(fixture.posts, 0);
          final effects = ExternalEffectService(
            readActiveCapsuleRootHex: () => owner,
            fileStore: files,
            resolveAdapter: (_) => fixture.adapter(),
          );
          final old =
              (await effects.list(pluginId: registry.record.pluginId!)).single;
          expect(old.lastErrorCode, 'entry_not_sent');
          fixture.existingOrder = false;
          plan['prepared_at_ms'] += 1;
          plan['expires_at_ms'] += 1;
          fixture.now += 1;
          await module().runWorkspaceAction(
            record: registry.record,
            action: preparationAction,
          );
          await module().runWorkspaceAction(
            record: registry.record,
            action: 'open',
          );
          final fresh = jsonDecode(
            (await files.readPluginState(
              await files.capsuleDirForHex(owner),
              registry.record.pluginId!,
              'workspace.v1.json',
            ))!,
          );
          expect(fresh['package_state']['entry']['attempted'], false);
          expect(fresh['package_state']['entry']['plan'], plan);
          expect(fixture.posts, 0);
          expect(
            (await effects.list(
              pluginId: registry.record.pluginId!,
            )).single.canonicalPayloadJson,
            old.canonicalPayloadJson,
          );
          await module().runWorkspaceAction(
            record: registry.record,
            action: placementAction,
            approvedOrder: request,
          );
          final history = await effects.list(
            pluginId: registry.record.pluginId!,
          );
          expect(history.length, 2);
          expect(history.first.operationId, old.operationId);
          expect(history.last.operationId, isNot(old.operationId));
        }
        expect(fixture.posts, 1);
        expect(validationSnapshots, isNotEmpty);
        expect(
          validationSnapshots.every(
            (s) => s['timeframe'] == fixture.evidenceTimeframe,
          ),
          true,
        );
        final validationCandles =
            validationSnapshots.expand((s) => s['candles'] as List).toList();
        final span = fixture.evidenceTimeframe == '15m' ? 900000 : 300000;
        final expectedCount =
            (fixture.now ~/ span + 1).clamp(2, fixture.evidenceLimit) - 1;
        expect(validationCandles.length, expectedCount);
        expect(
          validationSnapshots.every((s) => (s['candles'] as List).length <= 12),
          true,
        );
        expect(validationSnapshots.last['batch_complete'], true);
        for (var i = 1; i < validationCandles.length; i++) {
          expect(validationCandles[i][0] - validationCandles[i - 1][0], span);
        }
        await module().runWorkspaceAction(
          record: registry.record,
          action: 'open',
        );
        fixture.status = 'PARTIALLY_FILLED';
        fixture.filled = '0.1';
        await module().runWorkspaceAction(
          record: registry.record,
          action: 'refresh_order',
        );
        final capsule = await files.capsuleDirForHex(owner);
        final raw = await files.readPluginState(
          capsule,
          registry.record.pluginId!,
          'workspace.v1.json',
        );
        expect(
          jsonDecode(raw!)['package_state']['entry']['evidence']['status'],
          'partial',
        );
        expect(raw, isNot(contains('test-secret')));
        await module().removePlugin(registry.record);
        expect(
          await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'workspace.v1.json',
          ),
          isNull,
        );
        expect(
          await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'external_effects.v1.json',
          ),
          isNotNull,
        );
        registry.installed = true;
        await vault.saveSecret(
          capsuleHex: owner,
          pluginId: registry.record.pluginId!,
          providerId: 'bingx',
          accountId: 'primary',
          secretName: 'credentials',
          secretValue: jsonEncode({
            'api_key': 'test-key',
            'secret_key': 'test-secret',
          }),
        );
        await module().runWorkspaceAction(
          record: registry.record,
          action: 'open',
        );
        await module().runWorkspaceAction(
          record: registry.record,
          action: 'refresh_order',
        );
        expect(fixture.posts, 1);
        final recovered = jsonDecode(
          (await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'workspace.v1.json',
          ))!,
        );
        expect(
          recovered['package_state']['entry']['evidence']['order_id'],
          '2103610529511862272',
        );
        expect(
          recovered['package_state']['entry']['evidence']['filled_quantity'],
          0.1,
        );
        final retainedState = await files.readPluginState(
          capsule,
          registry.record.pluginId!,
          'workspace.v1.json',
        );
        final retainedJournal = await files.readPluginState(
          capsule,
          registry.record.pluginId!,
          'external_effects.v1.json',
        );
        fixture.queryUnavailable = true;
        await expectLater(
          module().runWorkspaceAction(
            record: registry.record,
            action: 'refresh_order',
          ),
          throwsStateError,
        );
        expect(
          await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'workspace.v1.json',
          ),
          retainedState,
        );
        expect(
          await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'external_effects.v1.json',
          ),
          retainedJournal,
        );
        expect(fixture.posts, 1);
        fixture.queryUnavailable = false;
        if (mode == 'normal') {
          final beforeState = await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'workspace.v1.json',
          );
          final beforeJournal = await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'external_effects.v1.json',
          );
          fixture.existingOrder = true;
          final listed = await module().runWorkspaceAction(
            record: registry.record,
            action: 'list_orders',
          );
          expect(listed['rows'], [
            ['2103610529511862272'],
          ]);
          expect(listAdmissions, 1);
          expect(
            await files.readPluginState(
              capsule,
              registry.record.pluginId!,
              'workspace.v1.json',
            ),
            beforeState,
          );
          expect(
            await files.readPluginState(
              capsule,
              registry.record.pluginId!,
              'external_effects.v1.json',
            ),
            beforeJournal,
          );
          for (final fault in [
            'grant',
            'account',
            'symbol',
            'revoke',
            'replace',
            'capsule',
            'remove',
          ]) {
            orderReadGrant = fault != 'grant';
            listRequest = {
              ...openOrdersRequest(),
              if (fault == 'account') 'account_id': 'b' * 64,
              if (fault == 'symbol') 'symbol': 'VET-USDT',
            };
            fixture.afterOpenOrdersRead = () {
              if (fault == 'revoke') orderReadGrant = false;
              if (fault == 'replace') packageDigest = 'f' * 64;
              if (fault == 'capsule') owner = 'b' * 64;
              if (fault == 'remove') registry.installed = false;
            };
            await expectLater(
              module().runWorkspaceAction(
                record: registry.record,
                action: 'list_orders',
              ),
              fault == 'symbol' ? throwsFormatException : throwsStateError,
              reason: fault,
            );
            expect(listAdmissions, 1, reason: fault);
            expect(fixture.posts, 1, reason: fault);
            owner = 'a' * 64;
            packageDigest = 'c' * 64;
            registry.installed = true;
          }
          fixture.afterOpenOrdersRead = null;
          orderReadGrant = true;
          final effects = ExternalEffectService(
            readActiveCapsuleRootHex: () => owner,
            fileStore: files,
            resolveAdapter: (_) => fixture.adapter(),
          );
          for (var i = 0; i < 8; i++) {
            final historicPlan = {
              ...plan,
              'prepared_at_ms': (plan['prepared_at_ms'] as int) + i + 1,
            };
            await effects.prepare(
              operationId: BingxMarketDataAdapter.entryOperationId(
                historicPlan,
              ),
              pluginId: registry.record.pluginId!,
              providerId: 'bingx',
              accountBindingId: plan['account_id'] as String,
              effectKind: 'order.entry.place',
              canonicalPayloadJson: jsonEncode(historicPlan),
            );
          }
          final journal = await files.readPluginState(
            capsule,
            registry.record.pluginId!,
            'external_effects.v1.json',
          );
          final empty = jsonDecode(beforeState!) as Map;
          empty['package_state']['entry'] = null;
          final baseline = jsonEncode(empty);
          for (final fault in [
            'replace',
            'capsule',
            'remove',
            'revoke',
            'nested',
            'reject',
            'normal',
          ]) {
            await files.writePluginState(
              capsule,
              registry.record.pluginId!,
              'workspace.v1.json',
              baseline,
            );
            recoveryFault = fault;
            recoveryAdmissions = 0;
            recoverySnapshots.clear();
            final run = module().runWorkspaceAction(
              record: registry.record,
              action: 'open',
            );
            if (fault == 'normal') {
              await run;
              expect(recoveryAdmissions, 9);
              expect(recoverySnapshots.last['batch_complete'], true);
              expect(
                recoverySnapshots.expand((s) => s['operations'] as List).length,
                9,
              );
              final restored = jsonDecode(
                (await files.readPluginState(
                  capsule,
                  registry.record.pluginId!,
                  'workspace.v1.json',
                ))!,
              );
              final operations = await effects.list(
                pluginId: registry.record.pluginId!,
              );
              expect(
                restored['package_state']['entry']['plan'],
                jsonDecode(operations.last.canonicalPayloadJson),
              );
            } else {
              await expectLater(run, throwsStateError, reason: fault);
              expect(recoveryAdmissions, greaterThanOrEqualTo(1));
              expect(
                await files.readPluginState(
                  capsule,
                  registry.record.pluginId!,
                  'workspace.v1.json',
                ),
                baseline,
                reason: fault,
              );
            }
            expect(fixture.posts, 1, reason: fault);
            expect(
              await files.readPluginState(
                capsule,
                registry.record.pluginId!,
                'external_effects.v1.json',
              ),
              journal,
              reason: fault,
            );
            owner = 'a' * 64;
            packageDigest = 'c' * 64;
            registry.installed = true;
            orderReadGrant = true;
          }
        }
      }
    },
  );
  test(
    'one signed entry has an attached stop and exact string-ID reconciliation',
    () async {
      final fixture = _EntryProvider();
      final adapter = fixture.adapter();
      final request = entryEffect(entryPlan());
      final result = await adapter.deliver(request);
      expect(result.status, ExternalEffectAdapterStatus.succeeded);
      expect(result.receipt!.providerReceiptId, '2103610529511862272');
      expect(fixture.posts, 1);
      expect(
        fixture.postParams!['clientOrderId'],
        request.operationId.substring(0, 40),
      );
      expect(fixture.postParams!['timeInForce'], 'PostOnly');
      expect(fixture.postParams!['positionSide'], 'LONG');
      expect(jsonDecode(fixture.postParams!['stopLoss']!), {
        'type': 'STOP_MARKET',
        'stopPrice': 96.12,
        'workingType': 'CONTRACT_PRICE',
      });
      fixture.status = 'PARTIALLY_FILLED';
      fixture.filled = '0.1';
      final read = await adapter.readEntry(request);
      expect(read['status'], 'partial');
      expect(read['filled_quantity'], 0.1);
      fixture.status = 'CANCELED';
      expect((await adapter.readEntry(request))['status'], 'cancelled');
      expect(fixture.posts, 1);
      fixture.positionSide = 'SHORT';
      await expectLater(adapter.readEntry(request), throwsFormatException);
      fixture.positionSide = 'BOTH';
      expect((await adapter.readEntry(request))['status'], 'cancelled');
      fixture.positionSide = 'LONG';
      fixture.clientIdOverride = 'foreign';
      await expectLater(adapter.readEntry(request), throwsFormatException);
      fixture.clientIdOverride = null;
      fixture.uid = '999999';
      await expectLater(adapter.readEntry(request), throwsStateError);
      expect((await adapter.deliver(request)).errorCode, 'entry_not_sent');
      expect(fixture.posts, 1);
    },
  );

  test('position mode accepts exact BingX values without guessing', () async {
    for (final value in [true, 'true', false, 'false']) {
      final fixture = _EntryProvider()..modeData = {'dualSidePosition': value};
      final result = await fixture.adapter().deliver(entryEffect(entryPlan()));
      expect(result.status, ExternalEffectAdapterStatus.succeeded);
      expect(fixture.posts, 1);
      expect(
        fixture.postParams!['positionSide'],
        value == true || value == 'true' ? 'LONG' : 'BOTH',
      );
    }
    for (final data in [
      null,
      [],
      {},
      {'dualSidePosition': null},
      {'dualSidePosition': 1},
      {'dualSidePosition': 'TRUE'},
      {'dualSidePosition': 'false '},
    ]) {
      final fixture = _EntryProvider()..modeData = data;
      final result = await fixture.adapter().deliver(entryEffect(entryPlan()));
      expect(result.status, ExternalEffectAdapterStatus.terminalFailure);
      expect(result.errorCode, 'entry_not_sent');
      expect(result.errorMessage, contains('position mode is unreadable'));
      expect(fixture.posts, 0);
    }
  });

  test(
    'delayed confirmation retains the exact plan and requests full final history',
    () async {
      final plan = entryPlan();
      plan['expires_at_ms'] = plan['prepared_at_ms'] + 48 * 60 * 60 * 1000;
      final fixture = _EntryProvider()..now = 100900000;
      final request = entryEffect(plan);
      final result = await fixture.adapter().deliver(request);
      expect(result.status, ExternalEffectAdapterStatus.succeeded);
      expect(fixture.posts, 1);
      expect(fixture.postParams!['price'], plan['price'].toString());
      expect(fixture.postParams!['quantity'], plan['quantity'].toString());
      expect(
        fixture.postParams!['clientOrderId'],
        request.operationId.substring(0, 40),
      );
    },
  );

  test(
    'non-dispatch survives restart and only explicit approval retries the same journal operation',
    () async {
      final home = await Directory.systemTemp.createTemp('hivra_not_sent_');
      addTearDown(() => home.delete(recursive: true));
      final files = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      );
      final fixture = _EntryProvider()..existingOrder = true;
      final request = entryEffect(entryPlan());
      ExternalEffectService service() => ExternalEffectService(
        readActiveCapsuleRootHex: () => 'a' * 64,
        fileStore: files,
        resolveAdapter: (_) => fixture.adapter(),
      );
      await service().prepare(
        operationId: request.operationId,
        pluginId: request.pluginId,
        providerId: request.providerId,
        accountBindingId: request.accountBindingId,
        effectKind: request.effectKind,
        canonicalPayloadJson: request.canonicalPayloadJson,
      );
      await service().approve(
        pluginId: request.pluginId,
        operationId: request.operationId,
        approvalEvidenceHashHex: request.payloadHashHex,
      );
      await service().enqueue(
        pluginId: request.pluginId,
        operationId: request.operationId,
      );
      final failure = await service().process(
        pluginId: request.pluginId,
        operationId: request.operationId,
      );
      expect(failure.state, ExternalEffectState.terminalFailure);
      expect(failure.lastErrorCode, 'entry_not_sent');
      fixture.existingOrder = false;
      expect(
        (await service().process(
          pluginId: request.pluginId,
          operationId: request.operationId,
        )).state,
        ExternalEffectState.terminalFailure,
      );
      expect(fixture.posts, 0);
      await service().reauthorizeRejectedDelivery(
        pluginId: request.pluginId,
        operationId: request.operationId,
        approvalEvidenceHashHex: request.payloadHashHex,
      );
      final delivered = await service().process(
        pluginId: request.pluginId,
        operationId: request.operationId,
      );
      expect(delivered.state, ExternalEffectState.succeeded);
      expect(delivered.operationId, failure.operationId);
      expect(delivered.canonicalPayloadJson, failure.canonicalPayloadJson);
      expect(fixture.posts, 1);
    },
  );

  test(
    'timeout, not-found and restart never permit a second POST; durable evidence survives uninstall',
    () async {
      final home = await Directory.systemTemp.createTemp('hivra_entry_effect_');
      addTearDown(() => home.delete(recursive: true));
      final files = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      );
      final fixture =
          _EntryProvider()
            ..postTimeout = true
            ..queryUnavailable = true;
      final request = entryEffect(entryPlan());
      ExternalEffectService service() => ExternalEffectService(
        readActiveCapsuleRootHex: () => 'a' * 64,
        fileStore: files,
        resolveAdapter:
            (provider) => provider == 'bingx' ? fixture.adapter() : null,
      );
      await service().prepare(
        operationId: request.operationId,
        pluginId: request.pluginId,
        providerId: 'bingx',
        accountBindingId: request.accountBindingId,
        effectKind: request.effectKind,
        canonicalPayloadJson: request.canonicalPayloadJson,
      );
      await service().approve(
        pluginId: request.pluginId,
        operationId: request.operationId,
        approvalEvidenceHashHex: request.payloadHashHex,
      );
      await service().enqueue(
        pluginId: request.pluginId,
        operationId: request.operationId,
      );
      expect(
        (await service().process(
          pluginId: request.pluginId,
          operationId: request.operationId,
        )).state,
        ExternalEffectState.unresolved,
      );
      expect(fixture.posts, 1);
      expect(
        (await service().process(
          pluginId: request.pluginId,
          operationId: request.operationId,
        )).state,
        ExternalEffectState.unresolved,
      );
      expect(fixture.posts, 1);
      final capsule = await files.capsuleDirForHex('a' * 64);
      await files.writePluginState(
        capsule,
        request.pluginId,
        'workspace.v1.json',
        '{}',
      );
      await files.deletePluginStateFromAllCapsules(
        request.pluginId,
        preserveFileNames: const {'external_effects.v1.json'},
      );
      expect(
        await files.readPluginState(
          capsule,
          request.pluginId,
          'workspace.v1.json',
        ),
        isNull,
      );
      expect(
        (await service().list(pluginId: request.pluginId)).single.attemptCount,
        1,
      );
      fixture.queryUnavailable = false;
      final recovered = await service().reconcileOnly(
        pluginId: request.pluginId,
        operationId: request.operationId,
      );
      expect(recovered.state, ExternalEffectState.succeeded);
      expect(recovered.receipt!.providerReceiptId, '2103610529511862272');
      expect(fixture.posts, 1);
    },
  );

  test(
    'BingX order envelope is normalized without treating malformed evidence as empty',
    () async {
      final wrapped = _EntryProvider()..wrappedOrders = true;
      expect(
        (await wrapped.adapter().deliver(entryEffect(entryPlan()))).status,
        ExternalEffectAdapterStatus.succeeded,
      );
      expect(wrapped.posts, 1);
      for (final data in <dynamic>[
        {},
        {'orders': null},
        {'orders': 'invalid'},
      ]) {
        final invalid = _EntryProvider()..openDataOverride = data;
        final failure = await invalid.adapter().deliver(
          entryEffect(entryPlan()),
        );
        expect(failure.status, ExternalEffectAdapterStatus.terminalFailure);
        expect(failure.errorCode, 'entry_not_sent');
        expect(invalid.posts, 0);
      }
      final conflict =
          _EntryProvider()
            ..wrappedOrders = true
            ..existingOrder = true;
      expect(
        (await conflict.adapter().deliver(entryEffect(entryPlan()))).errorCode,
        'entry_not_sent',
      );
      expect(conflict.posts, 0);
    },
  );

  test(
    'open-order conflicts require exact instrument and provider identity',
    () async {
      for (final data in <dynamic>[
        [null],
        [{}],
        [
          {'symbol': 'BTC-USDT'},
        ],
        [
          {'symbol': 'BTC-USDT', 'orderId': 'invalid'},
        ],
        [
          {'symbol': 'BTC-USDT', 'orderId': 1.5},
        ],
        [
          {'orderId': '2103610529511862272'},
        ],
      ]) {
        final fixture = _EntryProvider()..openDataOverride = {'orders': data};
        final result = await fixture.adapter().deliver(
          entryEffect(entryPlan()),
        );
        expect(result.errorCode, 'entry_not_sent');
        expect(result.errorMessage, contains('evidence is unreadable'));
        expect(fixture.posts, 0);
      }
      final foreign =
          _EntryProvider()
            ..openDataOverride = {
              'orders': [
                {'symbol': 'VET-USDT', 'orderId': '2103610529511862272'},
              ],
            };
      final mismatch = await foreign.adapter().deliver(
        entryEffect(entryPlan()),
      );
      expect(mismatch.errorCode, 'entry_not_sent');
      expect(
        mismatch.errorMessage,
        contains('outside the requested instrument'),
      );
      expect(mismatch.errorMessage, isNot(contains('Open BTC-USDT order')));
      expect(foreign.posts, 0);
      for (final key in ['orderId', 'orderID']) {
        final exact =
            _EntryProvider()
              ..openDataOverride = {
                'orders': [
                  {...openOrder(), key: '2103610529511862272'},
                ],
              };
        final result = await exact.adapter().deliver(entryEffect(entryPlan()));
        expect(result.errorCode, 'entry_not_sent');
        expect(result.errorMessage, contains('BTC-USDT'));
        expect(result.errorMessage, contains('2103610529511862272'));
        expect(exact.posts, 0);
      }
    },
  );

  test(
    'scope changes, existing orders, leverage drift, expired plans and crossed lines stop before POST',
    () async {
      for (final mode in [
        'revoked',
        'open',
        'leverage',
        'invalid_leverage',
        'expired',
        'crossed',
      ]) {
        final fixture = _EntryProvider();
        if (mode == 'revoked') fixture.authorized = false;
        if (mode == 'open') fixture.existingOrder = true;
        if (mode == 'leverage') fixture.longLeverage = '20';
        if (mode == 'invalid_leverage') fixture.longLeverage = 'NaN';
        if (mode == 'expired') fixture.now = 100060001;
        if (mode == 'crossed') fixture.currentPrice = 95;
        final failure = await fixture.adapter().deliver(
          entryEffect(entryPlan()),
        );
        expect(
          failure.status,
          ExternalEffectAdapterStatus.terminalFailure,
          reason: mode,
        );
        expect(failure.errorCode, 'entry_not_sent', reason: mode);
        expect(fixture.posts, 0, reason: mode);
      }
      final fixture = _EntryProvider()..queryUnavailable = true;
      final result = await fixture.adapter().deliver(entryEffect(entryPlan()));
      expect(result.status, ExternalEffectAdapterStatus.unresolved);
      expect(result.receipt, isNull);
      expect(fixture.posts, 1);
    },
  );

  test(
    'open-order listing is a bound GET observation, not an entry effect',
    () async {
      final fixture = _EntryProvider()..existingOrder = true;
      final request = openOrdersRequest();
      final snapshot = await fixture.adapter().readOpenOrders(request, {
        'api_key': 'test-key',
        'secret_key': 'test-secret',
      });
      expect(snapshot['account_id'], request['account_id']);
      expect(snapshot['symbol'], 'BTC-USDT');
      expect(snapshot['orders'], [
        {
          'order_id': '2103610529511862272',
          'side': 'BUY',
          'position_side': 'LONG',
          'type': 'LIMIT',
          'status': 'NEW',
          'price': '96.5',
          'stop_price': '0',
          'quantity': '0.518',
          'filled_quantity': '0.1',
        },
      ]);
      expect(jsonEncode(snapshot), isNot(contains('test-secret')));
      fixture.existingOrder = false;
      expect(
        (await fixture.adapter().readOpenOrders(request, {
          'api_key': 'test-key',
          'secret_key': 'test-secret',
        }))['orders'],
        isEmpty,
      );
      fixture.uid = '999999';
      await expectLater(
        fixture.adapter().readOpenOrders(request, {
          'api_key': 'test-key',
          'secret_key': 'test-secret',
        }),
        throwsStateError,
      );
      expect(fixture.posts, 0);
    },
  );

  test(
    'open-order listing rejects partial, duplicate or mismatched evidence',
    () async {
      for (final rows in <dynamic>[
        [openOrder(), openOrder()],
        [
          {...openOrder(), 'symbol': 'VET-USDT'},
        ],
        [
          {...openOrder(), 'price': 'NaN'},
        ],
        [
          {...openOrder(), 'origQty': '0.01'},
        ],
        [
          {...openOrder(), 'orderID': '2103610529511862273'},
        ],
        [
          {...openOrder(), 'status': 'untrusted prose'},
        ],
        [
          {...openOrder(), 'positionSide': 'INVALID'},
        ],
        List.generate(65, (i) => {...openOrder(), 'orderId': '${i + 1}'}),
      ]) {
        final fixture = _EntryProvider()..openDataOverride = {'orders': rows};
        await expectLater(
          fixture.adapter().readOpenOrders(openOrdersRequest(), {
            'api_key': 'test-key',
            'secret_key': 'test-secret',
          }),
          throwsFormatException,
        );
        expect(fixture.posts, 0);
      }
      final unavailable =
          _EntryProvider()
            ..afterOpenOrdersRead = () => throw TimeoutException('test-secret');
      await expectLater(
        unavailable.adapter().readOpenOrders(openOrdersRequest(), {
          'api_key': 'test-key',
          'secret_key': 'test-secret',
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'sanitized read error',
            allOf(contains('read unavailable'), isNot(contains('test-secret'))),
          ),
        ),
      );
      expect(unavailable.posts, 0);
    },
  );

  testWidgets(
    'financial confirmation cancellation does not invoke the effect',
    (tester) async {
      for (final cancelling in [false, true]) {
        var submitted = 0;
        var approved = <String, dynamic>{};
        final request = {
          'kind': cancelling ? 'order.entry.cancel' : 'order.entry.place',
          'provider': 'bingx',
          'plan': entryPlan(),
          if (cancelling) 'order_id': '2103610529511862272',
        };
        final data = {
          ...view(),
          'summary': 'BingX LIVE / account ending 6789',
          'confirmation': request,
          'actions': [
            {
              'id': 'place_entry',
              'label': 'Place this entry',
              'host': 'bingx.order.submit',
            },
          ],
        };
        await tester.pumpWidget(
          MaterialApp(
            home: PluginWorkspaceScreen(
              runWorkspaceAction: (
                action,
                settings, {
                credentials,
                approvedOrder,
              }) async {
                if (action == 'place_entry') {
                  submitted++;
                  approved = approvedOrder!;
                }
                return data;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Place this entry'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            cancelling
                ? 'Cancel this exact LIVE entry?'
                : 'Place one LIVE limit order?',
          ),
          findsOneWidget,
        );
        if (cancelling) {
          expect(find.textContaining('2103610529511862272'), findsOneWidget);
        }
        expect(submitted, 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(submitted, 0);
        await tester.tap(find.text('Place this entry'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('plugin-confirm-entry')));
        await tester.pumpAndSettle();
        expect(submitted, 1);
        expect(approved, request);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'package order list uses existing table and hides stale data on failed refresh',
    (tester) async {
      var fail = false;
      var reads = 0;
      final reading = Completer<void>();
      final base = {
        ...view(),
        'actions': [
          {'id': 'list_orders', 'label': 'Refresh open orders'},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            runWorkspaceAction: (
              action,
              settings, {
              credentials,
              approvedOrder,
            }) async {
              expect(credentials, isNull);
              expect(approvedOrder, isNull);
              if (action != 'list_orders') return base;
              reads++;
              if (fail) throw StateError('Order read unavailable');
              await reading.future;
              return {
                ...base,
                'details_title': 'Open orders',
                'columns': ['Order ID', 'Status'],
                'rows': [
                  ['2103610529511862272', 'PARTIALLY_FILLED'],
                ],
                'message': 'Exchange observations; not adopted',
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh open orders'));
      await tester.pump();
      expect(
        find.textContaining('Complete any system permission prompt'),
        findsOneWidget,
      );
      expect(find.textContaining('Settings or inputs changed'), findsNothing);
      reading.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open orders'));
      await tester.pumpAndSettle();
      expect(find.text('2103610529511862272'), findsOneWidget);
      expect(find.text('PARTIALLY_FILLED'), findsOneWidget);
      fail = true;
      await tester.tap(find.text('Refresh open orders'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.textContaining('Order read unavailable'), findsOneWidget);
      expect(find.text('2103610529511862272'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'private account reads sign fixed GET endpoints and expose only bounded evidence',
    () async {
      final calls = <Uri>[];
      final adapter = BingxMarketDataAdapter(
        clock:
            () => DateTime.fromMillisecondsSinceEpoch(100000000, isUtc: true),
        readAuthenticated: (uri, headers) async {
          calls.add(uri);
          expect(uri.host, 'open-api.bingx.com');
          expect(headers['X-BX-APIKEY'], 'test-key');
          final params = Map<String, String>.from(uri.queryParameters)
            ..remove('signature');
          final canonical = params.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('&');
          expect(
            uri.queryParameters['signature'],
            Hmac(
              sha256,
              utf8.encode('test-secret'),
            ).convert(utf8.encode(canonical)).toString(),
          );
          final data =
              uri.path.endsWith('/uid')
                  ? {'uid': '123456789'}
                  : uri.path.endsWith('/balance')
                  ? [
                    {
                      'asset': 'USDT',
                      'availableMargin': '30',
                      'userId': '****6789',
                    },
                  ]
                  : {'longLeverage': 50, 'shortLeverage': '20'};
          return jsonEncode({'code': 0, 'data': data});
        },
        read:
            (_) async => jsonEncode({
              'code': 0,
              'data': [accountContract()],
            }),
      );
      final snapshot = await adapter.readAccount(accountRequest(), {
        'api_key': 'test-key',
        'secret_key': 'test-secret',
      });
      expect(calls.map((u) => u.path), [
        '/openApi/account/v1/uid',
        '/openApi/swap/v3/user/balance',
        '/openApi/swap/v2/trade/leverage',
      ]);
      expect(
        snapshot['account_id'],
        sha256.convert(utf8.encode('bingx:LIVE:123456789')).toString(),
      );
      expect(snapshot['long_leverage'], 50);
      expect(snapshot['short_leverage'], 20);
      expect(snapshot['available_margin'], 30);
      expect(jsonEncode(snapshot), isNot(contains('test-key')));
      expect(jsonEncode(snapshot), isNot(contains('test-secret')));
      expect(jsonEncode(snapshot), isNot(contains('****')));
      await expectLater(
        adapter.readAccount(
          {...accountRequest(), 'provider': 'http://attacker.invalid'},
          {'api_key': 'test-key', 'secret_key': 'test-secret'},
        ),
        throwsFormatException,
      );
      expect(calls.length, 3);
    },
  );

  test(
    'private errors do not echo credentials, URLs or provider messages',
    () async {
      for (final mode in ['provider', 'network', 'masked']) {
        final adapter = BingxMarketDataAdapter(
          readAuthenticated: (uri, _) async {
            if (mode == 'network') throw StateError('$uri secret-key');
            return jsonEncode(
              mode == 'provider'
                  ? {'code': 100001, 'msg': 'secret-key $uri'}
                  : {
                    'code': 0,
                    'data': {'uid': '***1234'},
                  },
            );
          },
        );
        try {
          await adapter.readAccount(accountRequest(), {
            'api_key': 'api-key',
            'secret_key': 'secret-key',
          });
          fail('Expected rejection');
        } catch (error) {
          expect(error.toString(), isNot(contains('secret-key')));
          expect(error.toString(), isNot(contains('signature=')));
          expect(error.toString(), isNot(contains('***1234')));
        }
      }
    },
  );

  testWidgets(
    'advanced fields are optional and account credentials use a host-only dialog',
    (tester) async {
      Map<String, String>? sentCredentials;
      Map<String, dynamic>? sentSettings;
      final shown = {
        ...view(),
        'summary': 'BingX LIVE / account not connected',
        'fields': [
          ...view()['fields'] as List,
          {
            'id': 'detection_length',
            'label': 'Detection length',
            'type': 'integer',
            'value': 7,
            'advanced': true,
          },
        ],
        'actions': [
          {
            'id': 'connect',
            'label': 'Connect account',
            'host': 'bingx.account.connect',
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            runWorkspaceAction: (
              action,
              settings, {
              credentials,
              approvedOrder,
            }) async {
              if (action != 'open') {
                sentCredentials = credentials;
                sentSettings = settings;
              }
              return shown;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Detection length'), findsNothing);
      expect(find.text('BingX LIVE / account not connected'), findsOneWidget);
      await tester.tap(find.text('Advanced settings'));
      await tester.pumpAndSettle();
      expect(find.text('Detection length'), findsOneWidget);
      await tester.tap(find.text('Connect account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('plugin-account-api-key')),
        'test-key',
      );
      await tester.enterText(
        find.byKey(const ValueKey('plugin-account-secret-key')),
        'test-secret',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect and save'));
      await tester.pumpAndSettle();
      expect(sentCredentials, {
        'api_key': 'test-key',
        'secret_key': 'test-secret',
      });
      expect(sentSettings, {'symbol': 'BTC-USDT', 'detection_length': 7});
      expect(find.text('test-key'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'workspace persists only plugin state and recovers it after reopening',
    () async {
      final registry = _Registry();
      var owner = 'a' * 64;
      var requests = 0;
      var receivedState = <String, dynamic>{};
      bool marketGrant = true;
      bool instrumentGrant = true;
      bool accountGrant = true;
      bool continuationGrant = true;
      bool revokeContinuationDuringRead = false;
      String? continuationFault;
      var continuations = 0;
      var privateReads = 0;
      var uid = '123456789';
      var revokeAccountDuringRead = false;
      var candleCount = 1;
      var clockMs = 950000;
      final streamed = <Map<String, dynamic>>[];
      final vault = _Vault();
      String packageDigest = 'c' * 64;
      final host = PluginHostApiService(
        handlers: [],
        resolveRuntimeBinding:
            (_) async => PluginRuntimeBinding.externalPackage(
              packageId: registry.record.id,
              packageVersion: '0.1.0',
              packageKind: 'zip',
              packageDigestHex: packageDigest,
              contractKind: pluginWorkspaceContractKind,
              capabilities: [
                'workspace.render',
                if (continuationGrant) 'workspace.continue',
                'state.plugin.read_write',
                if (marketGrant) 'market.candles.read',
                if (instrumentGrant) 'market.instruments.read',
                if (accountGrant) 'account.connect',
                if (accountGrant) 'account.snapshot.read',
              ],
            ),
        resolveRuntimeInvoke: (request, _) async {
          expect(jsonEncode(request.args), isNot(contains('test-secret')));
          expect(jsonEncode(request.args), isNot(contains('test-key')));
          if (request.args['action'] == 'market') {
            streamed.add(
              Map<String, dynamic>.from(request.args['snapshot'] as Map),
            );
          }
          receivedState = Map<String, dynamic>.from(
            request.args['state'] as Map? ?? {},
          );
          if (request.args['action'] == 'open') {
            expect(request.args.containsKey('settings'), isFalse);
          }
          final counter = (receivedState['counter'] as int? ?? 0) + 1;
          if (request.args['action'] == 'finish_observation') {
            continuations++;
            expect(streamed.last['batch_complete'], true);
            expect(
              streamed.expand((s) => s['candles'] as List).length,
              candleCount,
            );
          }
          return PluginRuntimeInvokeEvidence(
            mode: 'wasmi_v1',
            modulePath: 'plugin/module.wasm',
            moduleSelection: 'manifest_module_path',
            moduleDigestHex: 'd' * 64,
            invokeDigestHex: 'e' * 64,
            semanticStatus: PluginHostApiStatus.executed,
            semanticErrorCode: null,
            semanticErrorMessage: null,
            semanticResult: {
              'state': {
                'counter': counter,
                if (receivedState['account'] != null)
                  'account': receivedState['account'],
                if (request.args['action'] == 'account')
                  'account': request.args['snapshot'],
              },
              'view': choiceView(),
              'requests':
                  request.args['action'] == 'link_account'
                      ? [accountRequest()]
                      : request.args['action'] == 'update_observation' ||
                          (request.args['action'] == 'market' &&
                              const [
                                'nested',
                                'nested_resume',
                              ].contains(continuationFault)) ||
                          (request.args['action'] == 'finish_observation' &&
                              continuationFault == 'chained')
                      ? [marketRequest()]
                      : request.args['action'] == 'inspect'
                      ? [
                        marketRequest(),
                        if (receivedState['account'] != null)
                          {
                            ...accountRequest(),
                            'kind': 'account.snapshot.read',
                            'account_id':
                                (receivedState['account'] as Map)['account_id'],
                          },
                      ]
                      : [],
              if (request.args['action'] == 'update_observation' ||
                  (request.args['action'] == 'market' &&
                      continuationFault == 'nested_resume') ||
                  (request.args['action'] == 'finish_observation' &&
                      continuationFault == 'chained'))
                'resume_action': 'finish_observation',
            },
          );
        },
      );
      bool switchCapsule = false;
      Completer<void>? readPause;
      Completer<void>? readStarted;
      bool replaceDuringRead = false;
      final market = BingxMarketDataAdapter(
        clock: () => DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
        readAuthenticated: (uri, headers) async {
          privateReads++;
          expect(headers['X-BX-APIKEY'], 'test-key');
          if (revokeAccountDuringRead) accountGrant = false;
          return jsonEncode({
            'code': 0,
            'data':
                uri.path.endsWith('/uid')
                    ? {'uid': uid}
                    : uri.path.endsWith('/balance')
                    ? [
                      {'asset': 'USDT', 'availableMargin': '30'},
                    ]
                    : {'longLeverage': 50, 'shortLeverage': 20},
          });
        },
        read: (uri) async {
          requests++;
          if (switchCapsule) owner = 'b' * 64;
          if (replaceDuringRead) packageDigest = 'f' * 64;
          if (revokeContinuationDuringRead) continuationGrant = false;
          readStarted?.complete();
          if (readPause != null) await readPause.future;
          if (uri.path.endsWith('/contracts')) {
            return jsonEncode({
              'code': 0,
              'data': [accountContract()],
            });
          }
          return jsonEncode({
            'code': 0,
            'data': List.generate(
              candleCount,
              (i) => [600000 + i * 300000, 100, 102, 99, 101],
            ),
          });
        },
      );
      PluginRuntimeModule module() => PluginRuntimeModule(
        registry: registry,
        sourceCatalog: const WasmPluginSourceCatalogService(),
        manualChecks: _Manual(),
        pluginHostApi: host,
        attestationExchange: _Attestations(),
        chatDelivery: _Delivery(),
        passiveReceive: _Passive(),
        contactLabels: _Labels(),
        uiLog: const UiEventLogService(),
        moltbook: _Moltbook(),
        fileStore: const CapsuleFileStore(),
        secretVault: vault,
        readActiveCapsuleRootHex: () => owner,
        market: market,
      );
      await module().runWorkspaceAction(
        record: registry.record,
        action: 'open',
      );
      await module().runWorkspaceAction(
        record: registry.record,
        action: 'open',
      );
      expect(receivedState, {'counter': 1});
      await module().runWorkspaceAction(
        record: registry.record,
        action: 'inspect',
      );
      expect(requests, 1);
      expect(receivedState, {'counter': 3});
      marketGrant = false;
      await expectLater(
        module().runWorkspaceAction(record: registry.record, action: 'inspect'),
        throwsStateError,
      );
      expect(requests, 1);
      marketGrant = true;
      switchCapsule = true;
      await expectLater(
        module().runWorkspaceAction(record: registry.record, action: 'inspect'),
        throwsStateError,
      );
      expect(receivedState, {'counter': 5});
      expect(
        await const CapsuleFileStore().readPluginState(
          await const CapsuleFileStore().capsuleDirForHex(owner),
          registry.record.pluginId!,
          'workspace.v1.json',
        ),
        isNull,
      );
      owner = 'a' * 64;
      registry.installed = false;
      await expectLater(
        module().runWorkspaceAction(record: registry.record, action: 'open'),
        throwsStateError,
      );
      registry.installed = true;
      switchCapsule = false;
      readPause = Completer<void>();
      readStarted = Completer<void>();
      final interrupted = expectLater(
        module().runWorkspaceAction(record: registry.record, action: 'inspect'),
        throwsStateError,
      );
      await readStarted.future;
      final removed = module().removePlugin(registry.record);
      await Future<void>.delayed(Duration.zero);
      expect(registry.installed, isFalse);
      readPause.complete();
      await interrupted;
      await removed;
      expect(
        await const CapsuleFileStore().readPluginState(
          await const CapsuleFileStore().capsuleDirForHex(owner),
          registry.record.pluginId!,
          'workspace.v1.json',
        ),
        isNull,
      );
      registry.installed = true;
      readPause = null;
      readStarted = null;
      instrumentGrant = false;
      final beforeCatalog = requests;
      await expectLater(
        module().runWorkspaceAction(
          record: registry.record,
          action: 'open',
          optionsForField: 'symbol',
        ),
        throwsStateError,
      );
      expect(requests, beforeCatalog);
      instrumentGrant = true;
      final options = await module().runWorkspaceAction(
        record: registry.record,
        action: 'open',
        optionsForField: 'symbol',
      );
      expect(options, {
        'options': ['XRP-USDT'],
      });
      final saved = await const CapsuleFileStore().readPluginState(
        await const CapsuleFileStore().capsuleDirForHex(owner),
        registry.record.pluginId!,
        'workspace.v1.json',
      );
      expect(jsonDecode(saved!).keys, ['counter']);
      await expectLater(
        module().runWorkspaceAction(
          record: registry.record,
          action: 'open',
          optionsForField: 'unknown',
        ),
        throwsStateError,
      );
      expect(requests, beforeCatalog + 1);
      replaceDuringRead = true;
      await expectLater(
        module().runWorkspaceAction(
          record: registry.record,
          action: 'open',
          optionsForField: 'symbol',
        ),
        throwsStateError,
      );
      replaceDuringRead = false;
      switchCapsule = true;
      await expectLater(
        module().runWorkspaceAction(
          record: registry.record,
          action: 'open',
          optionsForField: 'symbol',
        ),
        throwsStateError,
      );
      switchCapsule = false;
      owner = 'a' * 64;
      streamed.clear();
      candleCount = 49;
      clockMs = 15350000;
      await module().runWorkspaceAction(
        record: registry.record,
        action: 'inspect',
      );
      expect(streamed.map((s) => (s['candles'] as List).length), [
        12,
        12,
        12,
        12,
        1,
      ]);
      expect(
        streamed.expand((s) => s['candles'] as List).map((bar) => bar[0]),
        List.generate(candleCount, (i) => 600000 + i * 300000),
      );
      expect(streamed.map((s) => s['history_end_ms']).toSet(), {15000000});
      expect(streamed.map((s) => s['batch_complete']), [
        false,
        false,
        false,
        false,
        true,
      ]);
      candleCount = 1;
      clockMs = 950000;
      for (final fault in [
        'normal',
        'nested',
        'nested_resume',
        'chained',
        'revoke',
        'replace',
        'capsule',
      ]) {
        streamed.clear();
        continuations = 0;
        continuationFault = fault;
        revokeContinuationDuringRead = fault == 'revoke';
        replaceDuringRead = fault == 'replace';
        switchCapsule = fault == 'capsule';
        final run = module().runWorkspaceAction(
          record: registry.record,
          action: 'update_observation',
        );
        if (fault == 'normal') {
          await run;
          expect(continuations, 1);
        } else {
          await expectLater(run, throwsStateError, reason: fault);
          expect(continuations, fault == 'chained' ? 1 : 0, reason: fault);
        }
        owner = 'a' * 64;
        packageDigest = 'c' * 64;
        continuationGrant = true;
        revokeContinuationDuringRead = false;
        replaceDuringRead = false;
        switchCapsule = false;
      }
      continuationFault = null;
      accountGrant = false;
      final pair = {'api_key': 'test-key', 'secret_key': 'test-secret'};
      await expectLater(
        module().runWorkspaceAction(
          record: registry.record,
          action: 'link_account',
          credentials: pair,
        ),
        throwsStateError,
      );
      expect(privateReads, 0);
      expect(vault.values, isEmpty);
      accountGrant = true;
      await module().runWorkspaceAction(
        record: registry.record,
        action: 'link_account',
        credentials: pair,
      );
      expect(privateReads, 3);
      expect(vault.values.length, 1);
      final connected = await const CapsuleFileStore().readPluginState(
        await const CapsuleFileStore().capsuleDirForHex(owner),
        registry.record.pluginId!,
        'workspace.v1.json',
      );
      expect(connected, isNot(contains('test-secret')));
      expect(
        jsonDecode(connected!)['account']['account_id'],
        sha256.convert(utf8.encode('bingx:LIVE:$uid')).toString(),
      );
      await module().runWorkspaceAction(
        record: registry.record,
        action: 'inspect',
      );
      expect(
        privateReads,
        6,
      ); // Reopening the runtime reuses the secure binding.
      final retained = Map<String, String>.from(vault.values);
      uid = '987654321';
      await expectLater(
        module().runWorkspaceAction(record: registry.record, action: 'inspect'),
        throwsStateError,
      );
      expect(vault.values, retained);
      revokeAccountDuringRead = true;
      await expectLater(
        module().runWorkspaceAction(
          record: registry.record,
          action: 'link_account',
          credentials: pair,
        ),
        throwsStateError,
      );
      expect(vault.values, retained);
      revokeAccountDuringRead = false;
      accountGrant = true;
      await module().removePlugin(registry.record);
      expect(vault.values, isEmpty);
    },
  );
  test('package workspace requires grants and actual WASM evidence', () async {
    var invocations = 0;
    PluginHostApiService host({
      bool grant = true,
      bool continuationGrant = true,
      bool evidence = true,
      bool invalidTable = false,
      bool invalidSource = false,
      Object? resume,
      List<Map<String, dynamic>> requests = const [],
    }) => PluginHostApiService(
      handlers: [],
      resolveRuntimeBinding:
          (_) async => PluginRuntimeBinding.externalPackage(
            packageId: 'package',
            packageVersion: '0.1.0',
            packageKind: 'zip',
            contractKind: pluginWorkspaceContractKind,
            capabilities: [
              'workspace.render',
              if (continuationGrant) 'workspace.continue',
              if (grant) 'state.plugin.read_write',
            ],
          ),
      resolveRuntimeInvoke: (_, _) async {
        invocations++;
        return evidence
            ? PluginRuntimeInvokeEvidence(
              mode: 'wasmi_v1',
              modulePath: 'plugin/module.wasm',
              moduleSelection: 'manifest_module_path',
              moduleDigestHex: 'a' * 64,
              invokeDigestHex: 'b' * 64,
              semanticStatus: PluginHostApiStatus.executed,
              semanticResult: {
                'state': {},
                'view':
                    invalidTable
                        ? {
                          ...view(),
                          'columns': [],
                          'rows': [[]],
                        }
                        : invalidSource
                        ? {
                          ...choiceView(),
                          'fields': [
                            {
                              ...(choiceView()['fields'] as List).single as Map,
                              'source': {
                                'kind': 'market.instruments.read',
                                'provider': 'https://attacker.invalid',
                              },
                            },
                          ],
                        }
                        : view(),
                'requests': requests,
                if (resume != null) 'resume_action': resume,
              },
              semanticErrorCode: null,
              semanticErrorMessage: null,
            )
            : null;
      },
    );
    const request = PluginHostApiRequest(
      schemaVersion: 1,
      pluginId: 'hivra.contract.independent-workspace.v1',
      method: 'workspace',
      args: {},
    );
    expect(
      (await host(grant: false).executeWithRuntimeHook(request)).errorCode,
      'runtime_capability_mismatch',
    );
    expect(invocations, 0);
    expect(
      (await host(
        continuationGrant: false,
      ).executeWithRuntimeHook(request)).errorCode,
      'runtime_capability_mismatch',
    );
    expect(invocations, 0);
    expect(
      (await host(evidence: false).executeWithRuntimeHook(request)).errorCode,
      'runtime_invoke_unavailable',
    );
    expect(
      (await host().executeWithRuntimeHook(request)).result?['view'],
      view(),
    );
    expect(host().execute(request).errorCode, 'unsupported_plugin');
    final resumed = await host(
      resume: 'package_finish',
      requests: [marketRequest()],
    ).executeWithRuntimeHook(request);
    expect(resumed.result?['resume_action'], 'package_finish');
    for (final resume in [
      '',
      'A',
      'a' * 65,
      3,
      ['package_finish'],
    ]) {
      expect(
        (await host(
          resume: resume,
          requests: [marketRequest()],
        ).executeWithRuntimeHook(request)).errorCode,
        'invalid_workspace',
      );
    }
    for (final requests in <List<Map<String, dynamic>>>[
      [],
      [accountRequest()],
      [openOrdersRequest()],
      [
        {'kind': 'order.entry.place', 'provider': 'bingx', 'plan': entryPlan()},
      ],
    ]) {
      expect(
        (await host(
          resume: 'package_finish',
          requests: requests,
        ).executeWithRuntimeHook(request)).errorCode,
        'invalid_workspace',
      );
    }
    expect(
      (await host(
        invalidTable: true,
      ).executeWithRuntimeHook(request)).errorCode,
      'invalid_workspace',
    );
    expect(
      (await host(
        invalidSource: true,
      ).executeWithRuntimeHook(request)).errorCode,
      'invalid_workspace',
    );
  });

  test('instrument catalog is provider-owned, bounded and retryable', () async {
    var reads = 0;
    var data = <dynamic>[
      {'symbol': 'XRP-USDT', 'status': 1, 'apiStateOpen': 'true'},
      {'symbol': 'BTC-USDT', 'status': 1, 'apiStateOpen': true},
      {
        'symbol': 'NCSIRUSSELL20002USD-USDT',
        'status': 1,
        'apiStateOpen': 'true',
      },
      {'symbol': 'XRP-USDT', 'status': 1, 'apiStateOpen': 'true'},
      {'symbol': 'OLD-USDT', 'status': 0, 'apiStateOpen': 'true'},
      {'symbol': 'CLOSED-USDT', 'status': 1, 'apiStateOpen': 'false'},
    ];
    final adapter = BingxMarketDataAdapter(
      read: (uri) async {
        reads++;
        expect(uri.host, 'open-api.bingx.com');
        expect(uri.path, '/openApi/swap/v2/quote/contracts');
        expect(uri.queryParameters.keys, ['timestamp']);
        return jsonEncode({'code': 0, 'data': data});
      },
    );
    const source = {'kind': 'market.instruments.read', 'provider': 'bingx'};
    expect(await adapter.readInstruments(source), [
      'BTC-USDT',
      'NCSIRUSSELL20002USD-USDT',
      'XRP-USDT',
    ]);
    await expectLater(
      adapter.readInstruments({...source, 'provider': 'arbitrary'}),
      throwsFormatException,
    );
    expect(reads, 1);
    for (final bad in <List<dynamic>>[
      [],
      [null],
      [
        {'symbol': '../secret', 'status': 1, 'apiStateOpen': true},
      ],
      List.filled(4097, {}),
      [
        {'symbol': '${'A' * 61}-USDT', 'status': 1, 'apiStateOpen': true},
      ],
    ]) {
      data = bad;
      await expectLater(adapter.readInstruments(source), throwsFormatException);
    }
    data = [
      {'symbol': 'BTC-USDT', 'status': 1, 'apiStateOpen': 'true'},
    ];
    expect(await adapter.readInstruments(source), ['BTC-USDT']);
  });

  test(
    'provider normalizes both candle shapes and excludes live candle',
    () async {
      final now = DateTime.fromMillisecondsSinceEpoch(950000, isUtc: true);
      for (final objects in [false, true]) {
        final adapter = BingxMarketDataAdapter(
          clock: () => now,
          read: (uri) async {
            expect(uri.host, 'open-api.bingx.com');
            expect(uri.queryParameters['symbol'], 'XRP-USDT');
            final rows = [
              [900000, '100', '102', '99', '101'],
              [600000, '100', '102', '99', '101'],
              [300000, '100', '102', '99', '101'],
            ];
            return jsonEncode({
              'code': 0,
              'data':
                  objects
                      ? rows
                          .map(
                            (r) => {
                              'time': r[0],
                              'open': r[1],
                              'high': r[2],
                              'low': r[3],
                              'close': r[4],
                            },
                          )
                          .toList()
                      : rows,
            });
          },
        );
        final snapshot = await adapter.readCandles(marketRequest());
        expect(snapshot['candles'], [
          [300000, 100, 102, 99, 101],
          [600000, 100, 102, 99, 101],
        ]);
        expect(snapshot['current_price'], 101);
        expect(snapshot['symbol'], 'XRP-USDT');
      }
    },
  );

  test(
    'provider rejects arbitrary URLs, non-market requests, gaps and bad OHLC',
    () async {
      var reads = 0;
      String response = jsonEncode({
        'code': 0,
        'data': [
          [600000, 100, 102, 99, 101],
        ],
      });
      final adapter = BingxMarketDataAdapter(
        clock: () => DateTime.fromMillisecondsSinceEpoch(950000, isUtc: true),
        read: (_) async {
          reads++;
          return response;
        },
      );
      for (final mutation in [
        {'provider': 'http://localhost'},
        {'kind': 'order.submit'},
        {'symbol': '../secret'},
        {'symbol': '${'A' * 61}-USDT'},
        {'limit': 601},
        {'timeframe': 'unsupported'},
      ]) {
        await expectLater(
          adapter.readCandles({...marketRequest(), ...mutation}),
          throwsFormatException,
        );
      }
      expect(reads, 0);
      for (final data in [
        [
          [300000, 100, 102, 99, 101],
          [900000, 100, 102, 99, 101],
        ],
        [
          [600000, 100, 98, 99, 101],
        ],
        [
          [600000, 100, 102, 99, 101],
          [600000, 100, 102, 99, 101],
        ],
        [
          [0, 100, 102, 99, 101],
        ],
      ]) {
        response = jsonEncode({'code': 0, 'data': data});
        await expectLater(
          adapter.readCandles(marketRequest()),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets(
    'package defines its form; edited or failed actions hide previous results',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      String? sentAction;
      Map<String, dynamic>? sentSettings;
      await tester.pumpWidget(
        MaterialApp(
          home: PluginWorkspaceScreen(
            runWorkspaceAction: (
              action,
              settings, {
              credentials,
              approvedOrder,
            }) async {
              if (action == 'open') return view();
              sentAction = action;
              sentSettings = settings;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Observed levels'), findsOneWidget);
      expect(find.text('105.5'), findsNothing);
      expect(find.text('Provider evidence'), findsNothing);
      await tester.tap(find.text('Calculation details'));
      await tester.pumpAndSettle();
      expect(find.text('105.5'), findsOneWidget);
      expect(find.text('Provider evidence'), findsOneWidget);
      await tester.tap(find.text('Calculation details'));
      await tester.pumpAndSettle();
      expect(find.text('105.5'), findsNothing);
      expect(find.text('Observed levels'), findsOneWidget);
      await tester.tap(find.text('Calculation details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('plugin-field-symbol')),
        'XRP-USDT',
      );
      await tester.pump();
      expect(find.text('105.5'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('plugin-action-inspect')));
      await tester.pump();
      expect(sentAction, 'inspect');
      expect(sentSettings, {'symbol': 'XRP-USDT'});
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('plugin-action-inspect')),
            )
            .onPressed,
        isNull,
      );
      pending.completeError(StateError('Market unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Market unavailable'), findsOneWidget);
      expect(find.text('105.5'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search chooses one instrument; cancel and retry do not invent a selection',
    (tester) async {
      var selected = 'BTC-USDT';
      var reads = 0;
      var fail = true;
      Map<String, dynamic> shown() => {
        ...choiceView(),
        'fields': [
          {
            ...(choiceView()['fields'] as List).single as Map,
            'value': selected,
          },
        ],
      };
      Widget screen() => MaterialApp(
        home: PluginWorkspaceScreen(
          runWorkspaceAction: (
            action,
            settings, {
            credentials,
            approvedOrder,
          }) async {
            if (action == 'inspect') selected = settings['symbol'] as String;
            return shown();
          },
          readFieldOptions: (id) async {
            expect(id, 'symbol');
            reads++;
            if (fail) throw StateError('Network unavailable');
            return ['BTC-USDT', 'XRP-USDT', 'VET-USDT'];
          },
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('plugin-field-symbol')),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('plugin-field-symbol')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Network unavailable'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      await tester.enterText(
        find.byKey(const ValueKey('plugin-choice-search')),
        'xrp',
      );
      await tester.pumpAndSettle();
      expect(find.text('XRP-USDT'), findsOneWidget);
      expect(find.text('VET-USDT'), findsNothing);
      await tester.tap(find.text('XRP-USDT'));
      await tester.pumpAndSettle();
      expect(find.text('105.5'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('plugin-action-inspect')));
      await tester.pumpAndSettle();
      expect(selected, 'XRP-USDT');
      expect(find.text('105.5'), findsNothing);
      await tester.tap(find.text('Calculation details'));
      await tester.pumpAndSettle();
      expect(find.text('105.5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plugin-field-symbol')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('plugin-choice-search')),
        'not-a-symbol',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching instruments'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(selected, 'XRP-USDT');
      expect(find.text('105.5'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('XRP-USDT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Map<String, dynamic> choiceView() => {
  ...view(),
  'fields': [
    {
      'id': 'symbol',
      'label': 'Instrument',
      'type': 'choice',
      'value': 'BTC-USDT',
      'source': {'kind': 'market.instruments.read', 'provider': 'bingx'},
    },
  ],
};

Map<String, dynamic> marketRequest() => {
  'kind': 'market.candles.read',
  'provider': 'bingx',
  'symbol': 'XRP-USDT',
  'timeframe': '5m',
  'limit': 600,
};

Map<String, dynamic> accountRequest() => {
  'kind': 'account.connect',
  'provider': 'bingx',
  'symbol': 'XRP-USDT',
};

Map<String, dynamic> entryPlan() => {
  'account_id': sha256.convert(utf8.encode('bingx:LIVE:123456789')).toString(),
  'symbol': 'BTC-USDT',
  'side': 'long',
  'timeframe': '5m',
  'origin': 10,
  'first_known': 20,
  'line_price': 96.5,
  'price': 96.5,
  'quantity': 0.518,
  'stop_price': 96.12,
  'margin': 0.999740,
  'leverage': 50,
  'prepared_at_ms': 100000000,
  'expires_at_ms': 100060000,
};

ExternalEffectAdapterRequest entryEffect(Map<String, dynamic> plan) {
  final payload = jsonEncode(plan);
  return ExternalEffectAdapterRequest(
    ownerCapsuleHex: 'a' * 64,
    operationId: BingxMarketDataAdapter.entryOperationId(plan),
    pluginId: 'hivra.contract.jack-ventura.v1',
    providerId: 'bingx',
    accountBindingId: plan['account_id'] as String,
    effectKind: 'order.entry.place',
    canonicalPayloadJson: payload,
    payloadHashHex: sha256.convert(utf8.encode(payload)).toString(),
  );
}

Map<String, dynamic> openOrdersRequest() => {
  'kind': 'order.snapshot.read',
  'scope': 'open',
  'provider': 'bingx',
  'account_id': entryPlan()['account_id'],
  'symbol': 'BTC-USDT',
};

class _EntryProvider {
  int posts = 0;
  int deletes = 0;
  bool deleteTimeout = false;
  bool deleteStaysOpen = false;
  bool deleteFillRace = false;
  Map<String, String>? deleteParams;
  Future<void> Function()? afterOrderRead;
  int now = 100000000;
  String uid = '123456789';
  String status = 'NEW';
  String filled = '0';
  String longLeverage = '50';
  String positionSide = 'LONG';
  String? clientIdOverride;
  bool postTimeout = false;
  bool queryUnavailable = false;
  bool exitMode = false;
  bool exitQueryUnavailable = false;
  bool unsafeExit = false;
  bool existingOrder = false;
  bool wrappedOrders = false;
  dynamic openDataOverride;
  dynamic positionData = [];
  dynamic modeData = {'dualSidePosition': 'true'};
  bool authorized = true;
  double currentPrice = 100;
  String evidenceTimeframe = '5m';
  int evidenceLimit = 600;
  Map<String, String>? postParams;
  void Function()? afterModeRead;
  void Function()? afterOpenOrdersRead;
  void Function()? afterMarketRead;
  Future<void> Function()? beforeMarketRead;

  BingxMarketDataAdapter adapter() => BingxMarketDataAdapter(
    clock: () => DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    credentials:
        (_) async => {'api_key': 'test-key', 'secret_key': 'test-secret'},
    authorize: (plan) async {
      if (!authorized) throw StateError('Revoked');
      if (!plan.containsKey('entry_plan') && currentPrice <= plan['price']) {
        throw StateError('Passed entry');
      }
    },
    read: (uri) async {
      await beforeMarketRead?.call();
      expect(uri.queryParameters['limit'], '$evidenceLimit');
      expect(uri.queryParameters['interval'], evidenceTimeframe);
      final span = evidenceTimeframe == '15m' ? 900000 : 300000;
      final currentOpen = now ~/ span * span;
      final count = (currentOpen ~/ span + 1).clamp(2, evidenceLimit);
      afterMarketRead?.call();
      return jsonEncode({
        'code': 0,
        'data': List.generate(
          count,
          (i) => [
            currentOpen - (count - 1 - i) * span,
            100,
            101,
            currentPrice < 99 ? currentPrice : 99,
            currentPrice,
          ],
        ),
      });
    },
    sendAuthenticated: (method, uri, headers) async {
      expect(uri.host, 'open-api.bingx.com');
      expect(headers['X-BX-APIKEY'], 'test-key');
      final params = Map<String, String>.from(uri.queryParameters)
        ..remove('signature');
      final names = params.keys.toList()..sort();
      expect(uri.queryParameters.keys.toList(), [...names, 'signature']);
      expect(
        uri.queryParameters['signature'],
        Hmac(sha256, utf8.encode('test-secret'))
            .convert(utf8.encode(names.map((k) => '$k=${params[k]}').join('&')))
            .toString(),
      );
      dynamic data;
      if (method == 'POST') {
        expect(uri.path, '/openApi/swap/v2/trade/order');
        posts++;
        postParams = params;
        if (postTimeout) throw TimeoutException('secret-key $uri');
        data = {'orderId': '2103610529511862272'};
      } else if (method == 'DELETE') {
        expect(uri.path, '/openApi/swap/v2/trade/order');
        expect(params['orderId'], '2103610529511862272');
        expect(params['symbol'], 'BTC-USDT');
        expect(params.containsKey('clientOrderId'), isFalse);
        deletes++;
        deleteParams = params;
        if (deleteFillRace) {
          status = 'PARTIALLY_FILLED';
          filled = '0.1';
        } else if (!deleteStaysOpen) {
          status = 'CANCELED';
          existingOrder = false;
          openDataOverride = null;
        }
        if (deleteTimeout) throw TimeoutException('secret-key $uri');
        data = {};
      } else if (uri.path.endsWith('/uid')) {
        data = {'uid': uid};
      } else if (uri.path.endsWith('/openOrders')) {
        data = existingOrder ? [openOrder()] : [];
        if (wrappedOrders) data = {'orders': data};
        if (openDataOverride != null) data = openDataOverride;
        afterOpenOrdersRead?.call();
      } else if (uri.path.endsWith('/positions')) {
        data = positionData;
      } else if (uri.path.endsWith('/dual')) {
        data = modeData;
        afterModeRead?.call();
      } else if (uri.path.endsWith('/leverage')) {
        expect(params['symbol'], 'BTC-USDT');
        data = {'longLeverage': longLeverage, 'shortLeverage': '20'};
      } else {
        expect(uri.path, '/openApi/swap/v2/trade/order');
        final isExit =
            exitMode &&
            params['clientOrderId'] !=
                BingxMarketDataAdapter.entryOperationId(
                  entryPlan(),
                ).substring(0, 40);
        if (isExit) {
          if (exitQueryUnavailable) throw TimeoutException('Unavailable');
          return jsonEncode({
            'code': 0,
            'data': {
              'orderID': '2103610529511862273',
              'symbol': 'BTC-USDT',
              'clientOrderId': params['clientOrderId'],
              'side': 'SELL',
              'positionSide': positionSide,
              'reduceOnly': !unsafeExit,
              'type': 'LIMIT',
              'origQty': '0.518',
              'price': '105.0',
              'executedQty': '0',
              'avgPrice': '0',
              'status': 'NEW',
            },
          });
        }
        if (queryUnavailable) {
          return jsonEncode({'code': 100001, 'msg': 'secret-key $uri'});
        }
        data = {
          'orderID': '2103610529511862272',
          'symbol': 'BTC-USDT',
          'clientOrderId': clientIdOverride ?? params['clientOrderId'],
          'side': 'BUY',
          'positionSide': positionSide,
          'type': 'LIMIT',
          'origQty': '0.518',
          'price': '96.5',
          'executedQty': filled,
          'avgPrice': filled == '0' ? '0' : '96.4',
          'status': status,
        };
        await afterOrderRead?.call();
      }
      return jsonEncode({'code': 0, 'data': data});
    },
  );
}

Map<String, dynamic> openOrder() => {
  'symbol': 'BTC-USDT',
  'orderId': '2103610529511862272',
  'side': 'BUY',
  'positionSide': 'LONG',
  'type': 'LIMIT',
  'status': 'NEW',
  'price': '96.5',
  'stopPrice': '',
  'origQty': '0.518',
  'executedQty': '0.1',
};

Map<String, dynamic> accountContract() => {
  'symbol': 'XRP-USDT',
  'status': 1,
  'apiStateOpen': 'true',
  'pricePrecision': 4,
  'quantityPrecision': 1,
  'tradeMinQuantity': '1',
  'tradeMinUSDT': '5',
};

Map<String, dynamic> view() => {
  'title': 'Independent package',
  'message': 'Observed levels',
  'details': 'Provider evidence',
  'fields': [
    {
      'id': 'symbol',
      'label': 'Instrument',
      'type': 'text',
      'value': 'BTC-USDT',
    },
  ],
  'actions': [
    {'id': 'inspect', 'label': 'Inspect'},
  ],
  'columns': ['Price'],
  'rows': [
    ['105.5'],
  ],
};

class _Registry extends WasmPluginRegistryService {
  PluginRuntimeBinding Function()? executionBinding;
  bool installed = true;
  final record = const WasmPluginRecord(
    id: 'workspace-package',
    displayName: 'Workspace',
    originalFileName: 'workspace.zip',
    storedFileName: 'workspace.zip',
    sizeBytes: 100,
    installedAtIso: '2026-09-30T00:00:00Z',
    packageKind: 'zip',
    pluginId: 'hivra.contract.workspace-test.v1',
    pluginVersion: '0.1.0',
    contractKind: pluginWorkspaceContractKind,
    runtimeAbi: 'hivra_host_abi_v2',
    runtimeEntryExport: 'hivra_evaluate_v1',
    runtimeModulePath: 'plugin/module.wasm',
    // An apparent UI grant must not override the resolved package grants.
    capabilities: [
      'workspace.render',
      'workspace.continue',
      'state.plugin.read_write',
      'market.candles.read',
      'market.instruments.read',
    ],
  );
  @override
  Future<List<WasmPluginRecord>> loadPlugins() async =>
      installed ? [record] : [];
  @override
  Future<PluginRuntimeBinding> resolveRuntimeBinding(String pluginId) async =>
      executionBinding != null && installed
          ? executionBinding!()
          : super.resolveRuntimeBinding(pluginId);
  @override
  Future<void> removePlugin(String id) async => installed = false;
}

class _Vault extends Fake implements CapsuleScopedSecretVault {
  final values = <String, String>{};
  String scope(
    String capsule,
    String plugin,
    String provider,
    String account,
    String name,
  ) => '$capsule/$plugin/$provider/$account/$name';
  @override
  Future<String?> loadSecret({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    required String accountId,
    required String secretName,
  }) async =>
      values[scope(capsuleHex, pluginId, providerId, accountId, secretName)];
  @override
  Future<void> saveSecret({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    required String accountId,
    required String secretName,
    required String secretValue,
  }) async {
    values[scope(capsuleHex, pluginId, providerId, accountId, secretName)] =
        secretValue;
  }

  @override
  Future<void> deleteAccount({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    required String accountId,
  }) async {
    values.removeWhere(
      (k, v) => k.startsWith('$capsuleHex/$pluginId/$providerId/$accountId/'),
    );
  }

  @override
  Future<void> deletePlugin(String pluginId) async =>
      values.removeWhere((k, v) => k.split('/')[1] == pluginId);
}

class _Manual extends Fake implements ManualConsensusCheckService {}

class _Attestations extends Fake
    implements ConsensusAttestationExchangeService {}

class _Delivery extends Fake implements CapsuleChatDeliveryService {}

class _Passive extends Fake implements CapsulePassiveReceivePort {}

class _Labels extends Fake implements CapsuleContactLabelStore {}

class _Moltbook extends Fake implements MoltbookRuntimeModule {}
