import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_doctor_chat_service.dart';
import 'package:hivra_app/services/capsule_ai_runtime_service.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';
import 'package:hivra_app/services/ui_event_log_service.dart';
import 'package:hivra_app/widgets/ai_diagnostics/provider_widgets.dart';

void main() {
  Future<void> showCard(WidgetTester tester, _RecordingRuntime runtime) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiDoctorChatCard(
              snapshot: _snapshot(),
              chatService: AiDoctorChatService(runtime: runtime),
              uiLog: const _NoopUiLog(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> selectProvider(WidgetTester tester, String label) async {
    await tester.tap(
      find.byType(DropdownButtonFormField<InferenceProviderKind>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Analyst accepts delayed storage status without an invented timeout',
    (tester) async {
      final pending = Completer<bool>();
      final runtime = _RecordingRuntime(preferredProviderId: 'gemini')
        ..readPresence = (_) => pending.future;
      await showCard(tester, runtime);
      await tester.pump(const Duration(seconds: 40));
      expect(find.text('Checking secure storage…'), findsOneWidget);
      expect(find.textContaining('not saved.'), findsNothing);
      expect(find.text('Retry secure storage check'), findsNothing);
      await tester.tap(find.text('Ask AI Analyst'));
      expect(runtime.operations, isEmpty);
      expect(runtime.presenceCalls, ['gemini']);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(
        find.text('Gemini API key is saved in secure storage.'),
        findsOneWidget,
      );
      expect(runtime.operations, isEmpty);
    },
  );

  testWidgets(
    'Analyst retries a real status failure without displaying raw secret data',
    (tester) async {
      const secret = 'Bearer private-test-key';
      final runtime = _RecordingRuntime(preferredProviderId: 'gemini')
        ..readPresence = (_) async => throw StateError(secret);
      await showCard(tester, runtime);
      await tester.pumpAndSettle();
      expect(find.textContaining(secret), findsNothing);
      expect(find.text('Retry secure storage check'), findsOneWidget);
      final pending = Completer<bool>();
      runtime.readPresence = (_) => pending.future;
      await tester.tap(find.text('Retry secure storage check'));
      await tester.pump();
      expect(find.text('Checking secure storage…'), findsOneWidget);
      expect(find.text('Retry secure storage check'), findsNothing);
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Gemini API key is not saved.'), findsOneWidget);
      expect(runtime.presenceCalls, ['gemini', 'gemini']);
      expect(runtime.operations, isEmpty);
    },
  );

  testWidgets(
    'provider-preference failure recovers through the same Retry action',
    (tester) async {
      final runtime =
          _RecordingRuntime()
            ..readPreferred =
                () async => throw StateError('private preference failure');
      await showCard(tester, runtime);
      await tester.pumpAndSettle();
      expect(find.text('Checking secure storage…'), findsNothing);
      expect(find.textContaining('private preference failure'), findsNothing);
      expect(find.text('Retry secure storage check'), findsOneWidget);
      runtime.readPreferred = () async => 'gemini';
      await tester.tap(find.text('Retry secure storage check'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gemini API key is saved in secure storage.'),
        findsOneWidget,
      );
      expect(runtime.presenceCalls, ['gemini']);
      expect(runtime.operations, isEmpty);
    },
  );

  testWidgets('switching away and back rejects earlier status completions', (
    tester,
  ) async {
    final first = Completer<bool>();
    final latest = Completer<bool>();
    final other = Completer<bool>();
    var reads = 0;
    final runtime = _RecordingRuntime(preferredProviderId: 'openai')
      ..readPresence = (id) {
        if (id == 'gemini') return other.future;
        return ++reads == 1 ? first.future : latest.future;
      };
    await showCard(tester, runtime);
    await selectProvider(tester, 'Gemini');
    await selectProvider(tester, 'OpenAI');
    latest.complete(false);
    await tester.pumpAndSettle();
    first.complete(true);
    other.completeError(StateError('outdated failure'));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI API key is not saved.'), findsOneWidget);
    expect(
      find.text('OpenAI API key is saved in secure storage.'),
      findsNothing,
    );
    expect(find.text('Retry secure storage check'), findsNothing);
  });

  testWidgets(
    'late preferred provider cannot replace an explicit user selection',
    (tester) async {
      final preferred = Completer<String?>();
      final runtime =
          _RecordingRuntime()..readPreferred = () => preferred.future;
      await showCard(tester, runtime);
      await selectProvider(tester, 'Gemini');
      preferred.complete('openai');
      await tester.pumpAndSettle();
      expect(
        find.text('Gemini API key is saved in secure storage.'),
        findsOneWidget,
      );
      expect(runtime.presenceCalls, ['gemini']);
    },
  );

  testWidgets('leaving Analyst safely discards a pending status completion', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final runtime = _RecordingRuntime(preferredProviderId: 'gemini')
      ..readPresence = (_) => pending.future;
    await showCard(tester, runtime);
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('late storage failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(runtime.operations, isEmpty);
  });

  testWidgets(
    'saved model returns after reopening and is used without re-entering credentials',
    (tester) async {
      final runtime = _RecordingRuntime(preferredProviderId: 'gemini');
      await showCard(tester, runtime);
      await tester.pumpAndSettle();
      final modelField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Model',
      );
      await tester.ensureVisible(modelField);
      await tester.enterText(modelField, 'gemini-user-selected');
      final save = find.text('Save / replace provider settings');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(runtime.models['gemini'], 'gemini-user-selected');
      expect(runtime.configuration, ['preferred:gemini']);
      expect(find.byType(FilterChip), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await showCard(tester, runtime);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(modelField).controller!.text,
        'gemini-user-selected',
      );
      final ask = find.text('Ask AI Analyst');
      await tester.ensureVisible(ask);
      await tester.tap(ask);
      await tester.pumpAndSettle();
      expect(runtime.request!.model, 'gemini-user-selected');
      expect(runtime.request!.disclosedSectionIds, contains('plugin_summary'));
      expect(runtime.operations, ['unlock:gemini', 'infer']);
    },
  );

  testWidgets('saving a local model does not overwrite its existing endpoint', (
    tester,
  ) async {
    final runtime = _RecordingRuntime(
      preferredProviderId: 'local_openai_compatible',
    );
    await showCard(tester, runtime);
    await tester.pumpAndSettle();
    final modelField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Model',
    );
    await tester.ensureVisible(modelField);
    await tester.enterText(modelField, 'another-local-model');
    final save = find.text('Save / replace provider settings');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(runtime.models['local_openai_compatible'], 'another-local-model');
    expect(runtime.configuration, ['preferred:local_openai_compatible']);
  });

  group('AiDoctorChatService', () {
    test('routes all technical modules through Capsule AI Runtime', () async {
      final runtime = _RecordingRuntime();
      final service = AiDoctorChatService(runtime: runtime);

      final result = await service.ask(
        snapshot: _snapshot(),
        userQuery: 'Why is consensus blocked?',
        providerId: 'gemini',
        model: 'gemini-test',
      );

      expect(result.text, contains('Finding'));
      expect(result.providerId, 'gemini');
      expect(runtime.operations, <String>['unlock:gemini', 'infer']);
      final request = runtime.request!;
      expect(request.capabilityId, AiDoctorChatService.capabilityId);
      expect(request.proposalSchemaId, AiDoctorChatService.proposalSchemaId);
      expect(request.providerPolicy, CapsuleInferenceProviderPolicyV1.explicit);
      expect(request.providerId, 'gemini');
      expect(request.modelPolicy, CapsuleInferenceModelPolicyV1.explicit);
      expect(request.model, 'gemini-test');
      expect(
        request.disclosedSectionIds,
        containsAll(<String>[
          'consensus_summary',
          'transport_summary',
          'ledger_summary',
          'invitation_summary',
          'relationship_summary',
          'plugin_summary',
          'bootstrap_summary',
          'trace_summary',
          'capsule',
          'user_query',
        ]),
      );
      expect(request.inputJson, contains('scoped_ai_capsule_analyst_chat'));
      expect(request.inputJson, contains('transport_summary'));
      expect(request.inputJson, contains('consensus_summary'));
      expect(request.inputJson, contains('ledger_summary'));
      expect(request.inputJson, isNot(contains('seed phrase')));
      expect(result.preview.payloadBytes, request.disclosureByteCount);
      expect(result.preview.secretsRedacted, isTrue);
    });

    test(
      'delegates provider configuration only to Capsule AI Runtime',
      () async {
        final runtime = _RecordingRuntime(preferredProviderId: 'openai');
        final service = AiDoctorChatService(runtime: runtime);

        expect(await service.loadPreferredProviderId(), 'openai');
        await service.savePreferredProviderId('gemini');
        await service.saveProviderApiKey('gemini', 'secret');
        await service.saveProviderBaseUrl(
          'local_openai_compatible',
          'http://127.0.0.1:11434',
        );
        await service.clearProviderApiKey('gemini');
        await service.clearProviderBaseUrl('local_openai_compatible');

        expect(runtime.configuration, <String>[
          'preferred:gemini',
          'save-key:gemini:secret',
          'save-url:local_openai_compatible:http://127.0.0.1:11434',
          'clear-key:gemini',
          'clear-url:local_openai_compatible',
        ]);
      },
    );

    test('empty model delegates to the selected provider default', () async {
      final runtime = _RecordingRuntime();
      final service = AiDoctorChatService(runtime: runtime);

      await service.ask(snapshot: _snapshot(), userQuery: 'check', model: ' ');

      expect(
        runtime.request!.modelPolicy,
        CapsuleInferenceModelPolicyV1.providerDefault,
      );
      expect(runtime.request!.model, isNull);
    });

    test('invalid disclosure fails before credential unlock', () async {
      final runtime = _RecordingRuntime();
      final service = AiDoctorChatService(runtime: runtime);

      await expectLater(
        service.ask(snapshot: _snapshot(), userQuery: ' '),
        throwsA(isA<ArgumentError>()),
      );
      expect(runtime.operations, isEmpty);
      expect(runtime.request, isNull);
    });

    test('runtime failure remains visible and creates no fallback', () async {
      final error = StateError('AI provider request failed: rate limit');
      final runtime = _RecordingRuntime(error: error);
      final service = AiDoctorChatService(runtime: runtime);

      await expectLater(
        service.ask(snapshot: _snapshot(), userQuery: 'check'),
        throwsA(same(error)),
      );
      expect(runtime.operations, <String>['unlock:openai', 'infer']);
    });
  });
}

const _capsuleRoot =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _NoopUiLog extends UiEventLogService {
  const _NoopUiLog();
  @override
  Future<void> log(String source, String message) async {}
}

class _RecordingRuntime implements CapsuleInferenceRuntime {
  String? preferredProviderId;
  final Map<String, String> models = {};
  final Object? error;
  Future<bool> Function(String)? readPresence;
  Future<String?> Function()? readPreferred;
  final presenceCalls = <String>[];
  final List<String> operations = <String>[];
  final List<String> configuration = <String>[];
  CapsuleInferenceRequestV1? request;

  @override
  bool get isProviderSessionUnlocked => true;

  @override
  String? get sessionProviderLabel => 'OpenAI';

  @override
  String? get sessionProviderId => 'openai';

  _RecordingRuntime({this.preferredProviderId, this.error});

  @override
  String requireActiveCapsuleRootHex() => _capsuleRoot;

  @override
  Future<String?> loadPreferredProviderId() async =>
      readPreferred != null ? await readPreferred!() : preferredProviderId;

  @override
  Future<void> savePreferredProviderId(
    String providerId, {
    String? model,
  }) async {
    preferredProviderId = providerId;
    if (model != null) models[providerId] = model;
    configuration.add('preferred:$providerId');
  }

  @override
  Future<String> loadPreferredModel(String providerId) async =>
      models[providerId] ??
      InferenceProviderKind.values
          .firstWhere((p) => p.id == providerId)
          .defaultModel;

  @override
  Future<void> saveProviderApiKey(String providerId, String apiKey) async {
    configuration.add('save-key:$providerId:$apiKey');
  }

  @override
  Future<bool> hasProviderApiKey(String providerId) async {
    presenceCalls.add(providerId);
    return readPresence != null ? await readPresence!(providerId) : true;
  }

  @override
  Future<void> clearProviderApiKey(String providerId) async {
    configuration.add('clear-key:$providerId');
  }

  @override
  Future<void> saveProviderBaseUrl(String providerId, String baseUrl) async {
    configuration.add('save-url:$providerId:$baseUrl');
  }

  @override
  Future<void> clearProviderBaseUrl(String providerId) async {
    configuration.add('clear-url:$providerId');
  }

  @override
  Future<void> unlockPreferredProviderSession() async {
    operations.add('unlock:preferred');
  }

  @override
  Future<void> unlockProviderSession(String providerId) async {
    preferredProviderId = providerId;
    operations.add('unlock:$providerId');
  }

  @override
  void lockProviderSession() {}

  @override
  Future<CapsuleInferenceResultV1> infer(
    CapsuleInferenceRequestV1 request,
  ) async {
    this.request = request;
    operations.add('infer');
    if (error != null) throw error!;
    return CapsuleInferenceResultV1(
      requestId: request.requestId,
      capsuleRootHex: request.capsuleRootHex,
      capabilityId: request.capabilityId,
      disclosureHashHex: request.disclosureHashHex,
      proposalSchemaId: request.proposalSchemaId,
      proposalSchemaVersion: request.proposalSchemaVersion,
      proposalText: 'Finding: inspect local consensus evidence.',
      providerId: request.providerId ?? 'openai',
      providerLabel: request.providerId == 'gemini' ? 'Gemini' : 'OpenAI',
      model: request.model ?? 'test-model',
      responseHashHex:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      elapsedMilliseconds: 1,
    );
  }
}

AiCapsuleInspectionSnapshot _snapshot() {
  return const AiCapsuleInspectionSnapshot(
    schemaVersion: 1,
    mode: 'capsule_diagnostics_local',
    capsule: <String, dynamic>{'root_preview': 'h1abc...xyz'},
    ledgerSummary: <String, dynamic>{'version': 7},
    invitationSummary: <String, dynamic>{'pending_total': 0},
    relationshipSummary: <String, dynamic>{'active_peer_group_count': 1},
    transportSummary: <String, dynamic>{'pending_count': 2},
    consensusSummary: <String, dynamic>{'blocked_count': 1},
    pluginSummary: <String, dynamic>{'installed_count': 1},
    bootstrapSummary: <String, dynamic>{'issue': 'none'},
    traceSummary: <String, dynamic>{'issue_count': 0},
    redaction: <String, dynamic>{
      'secrets_redacted': true,
      'raw_seed_included': false,
      'private_keys_included': false,
    },
    snapshotHashHex: 'abc123',
  );
}
