import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/capsule_ai_runtime_service.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';

void main() {
  test('canonical request identity is stable across map and section order', () {
    final first = _request(
      input: <String, dynamic>{
        'z': 1,
        'a': <String, dynamic>{'y': true, 'b': false},
      },
      sections: const <String>['history', 'subject'],
    );
    final second = _request(
      input: <String, dynamic>{
        'a': <String, dynamic>{'b': false, 'y': true},
        'z': 1,
      },
      sections: const <String>['subject', 'history'],
    );

    expect(second.inputJson, first.inputJson);
    expect(second.disclosureHashHex, first.disclosureHashHex);
    expect(second.requestId, first.requestId);
  });

  test(
    'routes one bound request through the unlocked preferred provider',
    () async {
      final adapter = _RecordingAdapter();
      final runtime = CapsuleAiRuntimeService(
        credentialStore: _SessionCredentialStore(),
        readActiveCapsuleRootHex: () => _capsuleA,
        adapterFactory: (provider) {
          expect(provider, InferenceProviderKind.gemini);
          return adapter;
        },
      );
      final request = _request();

      final result = await runtime.infer(request);

      expect(adapter.apiKey, 'gemini-key');
      expect(adapter.prompt!.inputJson, request.inputJson);
      expect(result.requestId, request.requestId);
      expect(result.capsuleRootHex, _capsuleA);
      expect(result.providerId, 'gemini');
      expect(result.proposalText, 'Explained');
      expect(result.responseHashHex, hasLength(64));
    },
  );

  test('locked session fails before provider adapter creation', () async {
    var adapterCreated = false;
    final runtime = CapsuleAiRuntimeService(
      credentialStore: _SessionCredentialStore(unlocked: false),
      readActiveCapsuleRootHex: () => _capsuleA,
      adapterFactory: (_) {
        adapterCreated = true;
        return _RecordingAdapter();
      },
    );

    await expectLater(
      runtime.infer(_request()),
      throwsA(_failure(CapsuleInferenceFailureCode.sessionLocked)),
    );
    expect(adapterCreated, isFalse);
  });

  test('request for another Capsule fails before provider dispatch', () async {
    var adapterCreated = false;
    final runtime = CapsuleAiRuntimeService(
      credentialStore: _SessionCredentialStore(),
      readActiveCapsuleRootHex: () => _capsuleB,
      adapterFactory: (_) {
        adapterCreated = true;
        return _RecordingAdapter();
      },
    );

    await expectLater(
      runtime.infer(_request()),
      throwsA(_failure(CapsuleInferenceFailureCode.invalidRequest)),
    );
    expect(adapterCreated, isFalse);
  });

  test('late provider completion fails when active Capsule changes', () async {
    var activeCapsule = _capsuleA;
    final adapter = _RecordingAdapter(deferred: true);
    final runtime = CapsuleAiRuntimeService(
      credentialStore: _SessionCredentialStore(),
      readActiveCapsuleRootHex: () => activeCapsule,
      adapterFactory: (_) => adapter,
    );

    final pending = runtime.infer(_request());
    await adapter.started.future;
    activeCapsule = _capsuleB;
    adapter.complete();

    await expectLater(
      pending,
      throwsA(_failure(CapsuleInferenceFailureCode.capsuleChanged)),
    );
  });

  test(
    'new request supersedes an in-flight request in the same scope',
    () async {
      final first = _RecordingAdapter(deferred: true);
      final second = _RecordingAdapter();
      var adapterCall = 0;
      final runtime = CapsuleAiRuntimeService(
        credentialStore: _SessionCredentialStore(),
        readActiveCapsuleRootHex: () => _capsuleA,
        adapterFactory: (_) => adapterCall++ == 0 ? first : second,
      );

      final firstPending = runtime.infer(_request(input: const {'id': 1}));
      await first.started.future;
      final secondPending = runtime.infer(_request(input: const {'id': 2}));
      first.complete();

      await expectLater(
        firstPending,
        throwsA(_failure(CapsuleInferenceFailureCode.superseded)),
      );
      expect((await secondPending).proposalText, 'Explained');
    },
  );

  test('input and output budgets fail closed', () async {
    final runtime = CapsuleAiRuntimeService(
      credentialStore: _SessionCredentialStore(),
      readActiveCapsuleRootHex: () => _capsuleA,
      adapterFactory: (_) => _RecordingAdapter(text: 'too long'),
    );

    await expectLater(
      runtime.infer(_request(maxInputBytes: 1)),
      throwsA(_failure(CapsuleInferenceFailureCode.inputTooLarge)),
    );
    await expectLater(
      runtime.infer(_request(maxOutputBytes: 2)),
      throwsA(_failure(CapsuleInferenceFailureCode.outputTooLarge)),
    );
  });

  test('timeout and invalid provider evidence fail closed', () async {
    final timedOut = CapsuleAiRuntimeService(
      credentialStore: _SessionCredentialStore(),
      readActiveCapsuleRootHex: () => _capsuleA,
      adapterFactory: (_) => _RecordingAdapter(deferred: true),
    );
    final invalidEvidence = CapsuleAiRuntimeService(
      credentialStore: _SessionCredentialStore(),
      readActiveCapsuleRootHex: () => _capsuleA,
      adapterFactory:
          (_) =>
              _RecordingAdapter(responseProvider: InferenceProviderKind.openAi),
    );

    await expectLater(
      timedOut.infer(_request(timeoutMilliseconds: 1)),
      throwsA(_failure(CapsuleInferenceFailureCode.timeout)),
    );
    await expectLater(
      invalidEvidence.infer(_request()),
      throwsA(_failure(CapsuleInferenceFailureCode.invalidResponse)),
    );
  });

  test('adapter key confusion fails before credential disclosure', () async {
    final adapter = _RecordingAdapter(
      adapterProvider: InferenceProviderKind.openAi,
    );
    final runtime = CapsuleAiRuntimeService(
      credentialStore: _SessionCredentialStore(),
      readActiveCapsuleRootHex: () => _capsuleA,
      adapterFactory: (_) => adapter,
    );

    await expectLater(
      runtime.infer(_request()),
      throwsA(_failure(CapsuleInferenceFailureCode.invalidResponse)),
    );
    expect(adapter.callCount, 0);
    expect(adapter.apiKey, isNull);
  });

  test(
    'process scheduler serializes requests across runtime instances',
    () async {
      var activeCalls = 0;
      var maxActiveCalls = 0;
      final first = _RecordingAdapter(
        deferred: true,
        onStart: () {
          activeCalls += 1;
          maxActiveCalls =
              maxActiveCalls < activeCalls ? activeCalls : maxActiveCalls;
        },
        onComplete: () => activeCalls -= 1,
      );
      final second = _RecordingAdapter(
        deferred: true,
        onStart: () {
          activeCalls += 1;
          maxActiveCalls =
              maxActiveCalls < activeCalls ? activeCalls : maxActiveCalls;
        },
        onComplete: () => activeCalls -= 1,
      );
      final store = _SessionCredentialStore();
      final firstRuntime = CapsuleAiRuntimeService(
        credentialStore: store,
        readActiveCapsuleRootHex: () => _capsuleA,
        adapterFactory: (_) => first,
      );
      final secondRuntime = CapsuleAiRuntimeService(
        credentialStore: store,
        readActiveCapsuleRootHex: () => _capsuleA,
        adapterFactory: (_) => second,
      );

      final firstPending = firstRuntime.infer(
        _request(
          input: const {'id': 1},
          cancellationScope: 'hivra.test.first:$_capsuleA',
        ),
      );
      final secondPending = secondRuntime.infer(
        _request(
          input: const {'id': 2},
          cancellationScope: 'hivra.test.second:$_capsuleA',
        ),
      );
      await first.started.future;
      expect(second.started.isCompleted, isFalse);
      first.complete();
      await second.started.future;
      second.complete();
      await Future.wait(<Future<CapsuleInferenceResultV1>>[
        firstPending,
        secondPending,
      ]);

      expect(maxActiveCalls, 1);
    },
  );
}

const _capsuleA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _capsuleB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

CapsuleInferenceRequestV1 _request({
  Object input = const <String, dynamic>{'history': 'bounded'},
  List<String> sections = const <String>['history'],
  int maxInputBytes = 1024,
  int maxOutputBytes = 1024,
  int timeoutMilliseconds = 60000,
  String cancellationScope = 'hivra.test.capability:$_capsuleA',
}) {
  return CapsuleInferenceRequestV1.create(
    capsuleRootHex: _capsuleA,
    capabilityId: 'hivra.test.capability',
    disclosureSchemaVersion: 1,
    disclosedSectionIds: sections,
    proposalSchemaId: 'hivra.test.proposal.v1',
    proposalSchemaVersion: 1,
    cancellationScope: cancellationScope,
    instructions: 'Return one bounded advisory proposal.',
    input: input,
    maxInputBytes: maxInputBytes,
    maxOutputBytes: maxOutputBytes,
    timeoutMilliseconds: timeoutMilliseconds,
  );
}

Matcher _failure(CapsuleInferenceFailureCode code) {
  return isA<CapsuleInferenceFailure>().having(
    (failure) => failure.code,
    'code',
    code,
  );
}

class _SessionCredentialStore extends AiDoctorCredentialStore {
  bool unlocked;

  _SessionCredentialStore({this.unlocked = true});

  @override
  InferenceProviderKind? get sessionPreferredProvider =>
      unlocked ? InferenceProviderKind.gemini : null;

  @override
  bool get isPreferredProviderUnlocked => unlocked;

  @override
  String? sessionApiKey(InferenceProviderKind provider) =>
      unlocked ? 'gemini-key' : null;

  @override
  String? sessionBaseUrl(InferenceProviderKind provider) => null;

  @override
  Future<InferenceProviderKind> unlockPreferredProviderSession() async {
    unlocked = true;
    return InferenceProviderKind.gemini;
  }
}

class _RecordingAdapter implements InferenceProviderAdapter {
  final String text;
  final bool deferred;
  final void Function()? onStart;
  final void Function()? onComplete;
  final InferenceProviderKind adapterProvider;
  final InferenceProviderKind responseProvider;
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();
  String? apiKey;
  InferencePrompt? prompt;
  int callCount = 0;

  _RecordingAdapter({
    this.text = 'Explained',
    this.deferred = false,
    this.onStart,
    this.onComplete,
    this.adapterProvider = InferenceProviderKind.gemini,
    this.responseProvider = InferenceProviderKind.gemini,
  });

  @override
  InferenceProviderKind get provider => adapterProvider;

  @override
  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  }) async {
    callCount += 1;
    this.apiKey = apiKey;
    this.prompt = prompt;
    onStart?.call();
    if (!started.isCompleted) started.complete();
    if (deferred) await _release.future;
    onComplete?.call();
    return InferenceProviderResponse(
      text: text,
      model: model,
      provider: responseProvider,
    );
  }

  void complete() {
    if (!_release.isCompleted) _release.complete();
  }
}
