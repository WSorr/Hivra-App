import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  late Directory home;
  late CapsuleFileStore files;
  late String activeRoot;
  late DateTime now;

  setUp(() async {
    activeRoot = _rootA;
    now = DateTime.utc(2026, 7, 26, 12);
    home = await Directory.systemTemp.createTemp('hivra_external_effect_test_');
    files = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      atomicWrites: const AtomicFileWriteService(),
    );
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  ExternalEffectService build(
    ExternalEffectAdapter adapter, {
    String providerId = 'moltbook',
  }) {
    return ExternalEffectService(
      readActiveCapsuleRootHex: () => activeRoot,
      resolveAdapter: (candidate) => candidate == providerId ? adapter : null,
      fileStore: files,
      clock: () {
        now = now.add(const Duration(seconds: 1));
        return now;
      },
    );
  }

  Future<ExternalEffectOperation> prepareApprovedQueued(
    ExternalEffectService service, {
    String operationId = 'post-1',
    String payload = '{"body":"hello"}',
  }) async {
    await service.prepare(
      operationId: operationId,
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'account-1',
      effectKind: 'publish-post',
      canonicalPayloadJson: payload,
    );
    await service.approve(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
      approvalEvidenceHashHex: _approvalHash,
    );
    return service.enqueue(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
    );
  }

  test('persists one successful operation across restart', () async {
    final adapter = _FakeExternalEffectAdapter(
      deliverResults: <Object>[_success('post-1')],
    );
    final service = build(adapter);
    final first = await service.prepare(
      operationId: 'post-1',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'account-1',
      effectKind: 'publish-post',
      canonicalPayloadJson: '{"body":"hello"}',
    );
    final duplicate = await service.prepare(
      operationId: 'post-1',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'account-1',
      effectKind: 'publish-post',
      canonicalPayloadJson: '{"body":"hello"}',
    );
    expect(duplicate.revision, first.revision);

    await service.approve(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
      approvalEvidenceHashHex: _approvalHash,
    );
    await service.enqueue(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    final completed = await service.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );

    expect(
      completed.state,
      ExternalEffectState.succeeded,
      reason:
          'code=${completed.lastErrorCode} message=${completed.lastErrorMessage}',
    );
    expect(completed.attemptCount, 1);
    expect(adapter.deliverCount, 1);

    final restartedAdapter = _FakeExternalEffectAdapter();
    final restarted = build(restartedAdapter);
    final restored = await restarted.list(pluginId: moltbookAmbassadorPluginId);
    expect(restored.single.state, ExternalEffectState.succeeded);
    expect(restartedAdapter.deliverCount, 0);
    expect(restartedAdapter.reconcileCount, 0);
  });

  test(
    'timeout remains unresolved and restart reconciles before retry',
    () async {
      final firstAdapter = _FakeExternalEffectAdapter(
        deliverResults: <Object>[TimeoutException('provider outcome unknown')],
      );
      final firstService = build(firstAdapter);
      await prepareApprovedQueued(firstService);

      final unresolved = await firstService.process(
        pluginId: moltbookAmbassadorPluginId,
        operationId: 'post-1',
      );
      expect(unresolved.state, ExternalEffectState.unresolved);
      expect(unresolved.attemptCount, 1);

      final restartedAdapter = _FakeExternalEffectAdapter(
        reconcileResults: <Object>[_success('post-1')],
      );
      final restarted = build(restartedAdapter);
      final completed = await restarted.process(
        pluginId: moltbookAmbassadorPluginId,
        operationId: 'post-1',
      );

      expect(
        completed.state,
        ExternalEffectState.succeeded,
        reason:
            'code=${completed.lastErrorCode} message=${completed.lastErrorMessage}',
      );
      expect(completed.attemptCount, 1);
      expect(restartedAdapter.reconcileCount, 1);
      expect(restartedAdapter.deliverCount, 0);
    },
  );

  test('not-found reconciliation retries the same semantic operation', () async {
    final firstAdapter = _FakeExternalEffectAdapter(
      deliverResults: const <Object>[
        ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'network_timeout',
          errorMessage: 'Outcome unknown',
        ),
      ],
    );
    final firstService = build(firstAdapter);
    await prepareApprovedQueued(firstService);
    await firstService.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );

    final restartedAdapter = _FakeExternalEffectAdapter(
      reconcileResults: const <Object>[
        ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.notFound,
        ),
      ],
      deliverResults: <Object>[_success('post-1')],
    );
    final restarted = build(restartedAdapter);
    final completed = await restarted.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );

    expect(
      completed.state,
      ExternalEffectState.succeeded,
      reason:
          'code=${completed.lastErrorCode} message=${completed.lastErrorMessage}',
    );
    expect(completed.attemptCount, 2);
    expect(restartedAdapter.reconcileCount, 1);
    expect(restartedAdapter.deliverCount, 1);
    expect(restartedAdapter.deliveredOperationIds, <String>['post-1']);
  });

  test('concurrent process calls execute the adapter only once', () async {
    final deliveryCompleter = Completer<ExternalEffectAdapterResult>();
    final adapter = _FakeExternalEffectAdapter(
      deliverResults: <Object>[deliveryCompleter.future],
    );
    final service = build(adapter);
    await prepareApprovedQueued(service);

    final first = service.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    final second = service.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    await adapter.deliverCalled.future;
    expect(adapter.deliverCount, 1);

    deliveryCompleter.complete(_success('post-1'));
    final results = await Future.wait(<Future<ExternalEffectOperation>>[
      first,
      second,
    ]);
    expect(
      results.every((item) => item.state == ExternalEffectState.succeeded),
      isTrue,
    );
    expect(adapter.deliverCount, 1);
  });

  test('separate service instances share one in-flight operation', () async {
    final deliveryCompleter = Completer<ExternalEffectAdapterResult>();
    final adapter = _FakeExternalEffectAdapter(
      deliverResults: <Object>[deliveryCompleter.future],
    );
    final firstService = build(adapter);
    final secondService = build(adapter);
    await prepareApprovedQueued(firstService);

    final first = firstService.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    final second = secondService.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    await adapter.deliverCalled.future;
    expect(adapter.deliverCount, 1);

    deliveryCompleter.complete(_success('post-1'));
    final results = await Future.wait(<Future<ExternalEffectOperation>>[
      first,
      second,
    ]);
    expect(
      results.every((item) => item.state == ExternalEffectState.succeeded),
      isTrue,
    );
    expect(adapter.deliverCount, 1);
  });

  test(
    'late adapter result cannot downgrade a newer terminal revision',
    () async {
      final deliveryCompleter = Completer<ExternalEffectAdapterResult>();
      final adapter = _FakeExternalEffectAdapter(
        deliverResults: <Object>[deliveryCompleter.future],
      );
      final service = build(adapter);
      await prepareApprovedQueued(service);

      final processing = service.process(
        pluginId: moltbookAmbassadorPluginId,
        operationId: 'post-1',
      );
      await adapter.deliverCalled.future;

      final capsuleDir = await files.capsuleDirForHex(_rootA);
      final raw = await files.readPluginState(
        capsuleDir,
        moltbookAmbassadorPluginId,
        'external_effects.v1.json',
      );
      final journal = Map<String, dynamic>.from(
        jsonDecode(raw!) as Map<dynamic, dynamic>,
      );
      final operations = List<dynamic>.from(journal['operations'] as List);
      final operation = Map<String, dynamic>.from(
        operations.single as Map<dynamic, dynamic>,
      );
      operation['state'] = ExternalEffectState.succeeded.wireName;
      operation['revision'] = (operation['revision'] as int) + 1;
      operation['updated_at_utc'] = '2026-07-26T12:29:00.000Z';
      operation['last_error_code'] = null;
      operation['last_error_message'] = null;
      operation['receipt'] = _success('post-1').receipt!.toJson();
      journal['operations'] = <dynamic>[operation];
      await files.writePluginState(
        capsuleDir,
        moltbookAmbassadorPluginId,
        'external_effects.v1.json',
        jsonEncode(journal),
      );

      deliveryCompleter.complete(
        const ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'late_timeout',
          errorMessage: 'Late result from an obsolete delivery pass',
        ),
      );
      final completed = await processing;
      expect(completed.state, ExternalEffectState.succeeded);

      final persisted = await service.list(
        pluginId: moltbookAmbassadorPluginId,
      );
      expect(persisted.single.state, ExternalEffectState.succeeded);
      expect(persisted.single.lastErrorCode, isNull);
    },
  );

  test('cancelled operation cannot reach the adapter', () async {
    final adapter = _FakeExternalEffectAdapter();
    final service = build(adapter);
    await prepareApprovedQueued(service);
    final cancelled = await service.cancel(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    expect(cancelled.state, ExternalEffectState.cancelled);

    final result = await service.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    expect(result.state, ExternalEffectState.cancelled);
    expect(adapter.deliverCount, 0);
    expect(adapter.reconcileCount, 0);
  });

  test('operation id collision with another payload fails closed', () async {
    final service = build(_FakeExternalEffectAdapter());
    await service.prepare(
      operationId: 'post-1',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'account-1',
      effectKind: 'publish-post',
      canonicalPayloadJson: '{"body":"first"}',
    );

    expect(
      () => service.prepare(
        operationId: 'post-1',
        pluginId: moltbookAmbassadorPluginId,
        providerId: 'moltbook',
        accountBindingId: 'account-1',
        effectKind: 'publish-post',
        canonicalPayloadJson: '{"body":"second"}',
      ),
      throwsStateError,
    );
  });

  test('canonical payload must be a bounded JSON object', () async {
    final service = build(_FakeExternalEffectAdapter());

    expect(
      () => service.prepare(
        operationId: 'post-list',
        pluginId: moltbookAmbassadorPluginId,
        providerId: 'moltbook',
        accountBindingId: 'account-1',
        effectKind: 'publish-post',
        canonicalPayloadJson: '["not-an-object"]',
      ),
      throwsFormatException,
    );
  });

  test('journal load rejects payload tampering', () async {
    final service = build(_FakeExternalEffectAdapter());
    await service.prepare(
      operationId: 'post-1',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'account-1',
      effectKind: 'publish-post',
      canonicalPayloadJson: '{"body":"original"}',
    );

    final capsuleDir = await files.capsuleDirForHex(_rootA);
    final raw = await files.readPluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      'external_effects.v1.json',
    );
    final journal = Map<String, dynamic>.from(
      jsonDecode(raw!) as Map<dynamic, dynamic>,
    );
    final operations = List<dynamic>.from(journal['operations'] as List);
    final operation = Map<String, dynamic>.from(
      operations.single as Map<dynamic, dynamic>,
    );
    operation['canonical_payload_json'] = '{"body":"tampered"}';
    journal['operations'] = <dynamic>[operation];
    await files.writePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      'external_effects.v1.json',
      jsonEncode(journal),
    );

    expect(
      service.list(pluginId: moltbookAmbassadorPluginId),
      throwsFormatException,
    );
  });

  test('completion remains bound to the originating capsule', () async {
    final deliveryCompleter = Completer<ExternalEffectAdapterResult>();
    final adapter = _FakeExternalEffectAdapter(
      deliverResults: <Object>[deliveryCompleter.future],
    );
    final service = build(adapter);
    await prepareApprovedQueued(service);
    final processing = service.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: 'post-1',
    );
    await Future<void>.delayed(Duration.zero);

    activeRoot = _rootB;
    deliveryCompleter.complete(_success('post-1'));
    await processing;
    expect(await service.list(pluginId: moltbookAmbassadorPluginId), isEmpty);

    activeRoot = _rootA;
    final original = await service.list(pluginId: moltbookAmbassadorPluginId);
    expect(original.single.state, ExternalEffectState.succeeded);
  });

  test('plugin state cleanup removes journals from every capsule', () async {
    final service = build(_FakeExternalEffectAdapter());
    await service.prepare(
      operationId: 'post-a',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'account-1',
      effectKind: 'publish-post',
      canonicalPayloadJson: '{"body":"a"}',
    );
    activeRoot = _rootB;
    await service.prepare(
      operationId: 'post-b',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'account-2',
      effectKind: 'publish-post',
      canonicalPayloadJson: '{"body":"b"}',
    );

    await files.deletePluginStateFromAllCapsules(moltbookAmbassadorPluginId);

    expect(await service.list(pluginId: moltbookAmbassadorPluginId), isEmpty);
    activeRoot = _rootA;
    expect(await service.list(pluginId: moltbookAmbassadorPluginId), isEmpty);
  });
}

class _FakeExternalEffectAdapter implements ExternalEffectAdapter {
  final List<Object> deliverResults;
  final List<Object> reconcileResults;
  final List<String> deliveredOperationIds = <String>[];
  final Completer<void> deliverCalled = Completer<void>();
  int deliverCount = 0;
  int reconcileCount = 0;

  _FakeExternalEffectAdapter({
    List<Object>? deliverResults,
    List<Object>? reconcileResults,
  }) : deliverResults = List<Object>.of(deliverResults ?? const <Object>[]),
       reconcileResults = List<Object>.of(reconcileResults ?? const <Object>[]);

  @override
  Future<ExternalEffectAdapterResult> deliver(
    ExternalEffectAdapterRequest request,
  ) async {
    deliverCount += 1;
    deliveredOperationIds.add(request.operationId);
    if (!deliverCalled.isCompleted) deliverCalled.complete();
    return _take(deliverResults, 'deliver');
  }

  @override
  Future<ExternalEffectAdapterResult> reconcile(
    ExternalEffectAdapterRequest request,
  ) async {
    reconcileCount += 1;
    return _take(reconcileResults, 'reconcile');
  }

  Future<ExternalEffectAdapterResult> _take(
    List<Object> values,
    String method,
  ) async {
    if (values.isEmpty) {
      throw StateError('No fake $method result configured');
    }
    final value = values.removeAt(0);
    if (value is TimeoutException) throw value;
    if (value is Future<ExternalEffectAdapterResult>) return value;
    return value as ExternalEffectAdapterResult;
  }
}

ExternalEffectAdapterResult _success(String operationId) {
  return ExternalEffectAdapterResult(
    status: ExternalEffectAdapterStatus.succeeded,
    receipt: ExternalEffectReceipt(
      operationId: operationId,
      providerId: 'moltbook',
      providerReceiptId: 'receipt-$operationId',
      evidenceHashHex: _receiptHash,
      receivedAtUtc: '2026-07-26T12:30:00.000Z',
    ),
  );
}

const String _approvalHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _receiptHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _rootA =
    '1111111111111111111111111111111111111111111111111111111111111111';
const String _rootB =
    '2222222222222222222222222222222222222222222222222222222222222222';
