import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/models/moltbook_provider_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/moltbook_external_effect_adapter.dart';
import 'package:hivra_app/services/moltbook_publication_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  const postId = '20e1d392-5f55-4cae-b48a-af3192dc477b';

  test('publishedPostUri maps a verified receipt to its public post', () {
    final uri = MoltbookPublicationService.publishedPostUri(
      _operation(
        state: ExternalEffectState.succeeded,
        providerReceiptId: postId,
      ),
    );

    expect(uri, Uri.parse('https://www.moltbook.com/post/$postId'));
  });

  test('publishedPostUri rejects an unverified or malformed receipt', () {
    expect(
      MoltbookPublicationService.publishedPostUri(
        _operation(
          state: ExternalEffectState.unresolved,
          providerReceiptId: postId,
        ),
      ),
      isNull,
    );
    expect(
      MoltbookPublicationService.publishedPostUri(
        _operation(
          state: ExternalEffectState.succeeded,
          providerReceiptId: 'https://example.com/redirect',
        ),
      ),
      isNull,
    );
  });

  test('delegated authorization binds the exact reply effect', () {
    const authorization = MoltbookDelegatedReplyAuthorization(
      targetPostId: 'post-1',
      targetCommentId: 'comment-1',
      engagementPlanHashHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      replyDraftHashHex:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      policyVersion: 1,
      maxDailyWrites: 3,
      writesToday: 0,
      minIntervalMinutes: 30,
      observedAtUtc: '2026-07-31T18:00:00.000Z',
      safetyFlags: <String>['exact_reply_draft_bound', 'engagement_plan_bound'],
      authorizationHashHex:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      canonicalAuthorizationJson: '{}',
    );
    final operation = _replyOperation(
      sourceDraftHashHex: authorization.replyDraftHashHex,
    );

    expect(
      () => MoltbookPublicationService.validateDelegatedReplyBinding(
        operation,
        authorization,
      ),
      returnsNormally,
    );
    expect(
      () => MoltbookPublicationService.validateDelegatedReplyBinding(
        _replyOperation(
          sourceDraftHashHex:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        ),
        authorization,
      ),
      throwsFormatException,
    );
  });

  group('reply engagement identity', () {
    late Directory home;
    late CapsuleFileStore files;
    late String activeRoot;
    late ExternalEffectService effects;
    late MoltbookPublicationService publications;

    const binding = MoltbookConnectionBinding(
      accountId: 'account-test',
      accountName: 'agent',
      isClaimed: true,
      isActive: true,
      verifiedAtUtc: '2026-07-31T18:00:00.000Z',
    );

    setUp(() async {
      activeRoot = _ownerA;
      home = await Directory.systemTemp.createTemp(
        'hivra_moltbook_engagement_test_',
      );
      files = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
        atomicWrites: const AtomicFileWriteService(),
      );
      effects = _effects(files, () => activeRoot);
      publications = _publications(effects, binding);
    });

    tearDown(() async {
      if (await home.exists()) await home.delete(recursive: true);
    });

    test('engagement id excludes reply prose but includes Capsule target', () {
      final first = MoltbookPublicationService.replyEngagementId(
        ownerCapsuleHex: _ownerA,
        accountBindingId: binding.accountId,
        postId: 'post-1',
        parentCommentId: 'comment-1',
      );
      final same = MoltbookPublicationService.replyEngagementId(
        ownerCapsuleHex: _ownerA,
        accountBindingId: binding.accountId,
        postId: 'post-1',
        parentCommentId: 'comment-1',
      );
      final anotherCapsule = MoltbookPublicationService.replyEngagementId(
        ownerCapsuleHex: _ownerB,
        accountBindingId: binding.accountId,
        postId: 'post-1',
        parentCommentId: 'comment-1',
      );

      expect(first, same);
      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(first, isNot(anotherCapsule));
    });

    test('same draft resumes one active operation across restart', () async {
      final first = await publications.prepareReply(draft: _draft('first'));
      final repeated = await publications.prepareReply(draft: _draft('first'));

      final restarted = _publications(
        _effects(files, () => activeRoot),
        binding,
      );
      final restored = await restarted.prepareReply(draft: _draft('first'));

      expect(repeated.operationId, first.operationId);
      expect(restored.operationId, first.operationId);
      expect((await restarted.list()), hasLength(1));
      expect(
        MoltbookPublicationService.decodePayload(first)['engagement_id'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    });

    test('different prose cannot create a second active reply', () async {
      await publications.prepareReply(draft: _draft('first'));

      await expectLater(
        publications.prepareReply(draft: _draft('second')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('active immutable reply'),
          ),
        ),
      );
      expect(await publications.list(), hasLength(1));
    });

    test(
      'concurrent preparation creates one operation for one target',
      () async {
        final results = await Future.wait(<Future<ExternalEffectOperation>>[
          publications.prepareReply(draft: _draft('first')),
          publications.prepareReply(draft: _draft('first')),
          publications.prepareReply(draft: _draft('first')),
        ]);

        expect(
          results.map((operation) => operation.operationId).toSet(),
          hasLength(1),
        );
        expect(await publications.list(), hasLength(1));
      },
    );

    test('succeeded target remains closed to another draft', () async {
      final operation = await publications.prepareReply(draft: _draft('first'));
      await effects.approve(
        pluginId: moltbookAmbassadorPluginId,
        operationId: operation.operationId,
        approvalEvidenceHashHex: _approvalHash,
      );
      await effects.enqueue(
        pluginId: moltbookAmbassadorPluginId,
        operationId: operation.operationId,
      );
      await effects.process(
        pluginId: moltbookAmbassadorPluginId,
        operationId: operation.operationId,
      );

      await expectLater(
        publications.prepareReply(draft: _draft('second')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already published'),
          ),
        ),
      );
    });

    test(
      'legacy duplicate active replies freeze preparation and delivery',
      () async {
        await _prepareLegacy(effects, 'legacy-one', _draft('first'));
        await _prepareLegacy(effects, 'legacy-two', _draft('second'));

        await expectLater(
          publications.prepareReply(draft: _draft('third')),
          throwsStateError,
        );
        await expectLater(publications.process('legacy-one'), throwsStateError);
        expect(await publications.list(), hasLength(2));
      },
    );

    test('mismatched embedded engagement identity fails closed', () async {
      await effects.prepare(
        operationId: 'mismatched-engagement',
        pluginId: moltbookAmbassadorPluginId,
        providerId: 'moltbook',
        accountBindingId: binding.accountId,
        effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
        canonicalPayloadJson:
            '{"schema_version":2,"engagement_id":"${'f' * 64}",'
            '"account_name":"agent","post_id":"post-1",'
            '"parent_comment_id":"comment-1","content":"first",'
            '"operation_marker":"hivra-effect:mismatched-engagement",'
            '"source_draft_hash_hex":"${'1' * 64}",'
            '"engagement_plan_hash_hex":"${'1' * 64}"}',
      );

      await expectLater(
        publications.prepareReply(draft: _draft('first')),
        throwsFormatException,
      );
    });

    test('same remote target is isolated by active Capsule', () async {
      final first = await publications.prepareReply(draft: _draft('first'));
      activeRoot = _ownerB;
      final second = await publications.prepareReply(draft: _draft('first'));

      expect(first.ownerCapsuleHex, _ownerA);
      expect(second.ownerCapsuleHex, _ownerB);
      expect(
        MoltbookPublicationService.decodePayload(first)['engagement_id'],
        isNot(
          MoltbookPublicationService.decodePayload(second)['engagement_id'],
        ),
      );
    });
  });
}

ExternalEffectService _effects(
  CapsuleFileStore files,
  String Function() activeRoot,
) {
  return ExternalEffectService(
    readActiveCapsuleRootHex: activeRoot,
    resolveAdapter: (_) => const _SuccessAdapter(),
    fileStore: files,
  );
}

MoltbookPublicationService _publications(
  ExternalEffectService effects,
  MoltbookConnectionBinding binding,
) {
  return MoltbookPublicationService.withBindingLoader(
    effects: effects,
    loadBinding: () async => binding,
  );
}

MoltbookReplyDraftPreview _draft(String body) {
  final suffix =
      body == 'first'
          ? '1'
          : body == 'second'
          ? '2'
          : '3';
  return MoltbookReplyDraftPreview(
    targetPostId: 'post-1',
    targetCommentId: 'comment-1',
    engagementPlanHashHex: suffix * 64,
    body: body,
    approvalRequired: true,
    safetyFlags: const <String>['reviewed'],
    draftHashHex: suffix * 64,
    canonicalDraftJson: '{}',
  );
}

Future<void> _prepareLegacy(
  ExternalEffectService effects,
  String operationId,
  MoltbookReplyDraftPreview draft,
) {
  return effects
      .prepare(
        operationId: operationId,
        pluginId: moltbookAmbassadorPluginId,
        providerId: 'moltbook',
        accountBindingId: 'account-test',
        effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
        canonicalPayloadJson:
            '{"schema_version":1,"account_name":"agent",'
            '"post_id":"post-1","parent_comment_id":"comment-1",'
            '"content":"${draft.body}","operation_marker":'
            '"hivra-effect:$operationId","source_draft_hash_hex":'
            '"${draft.draftHashHex}","engagement_plan_hash_hex":'
            '"${draft.engagementPlanHashHex}"}',
      )
      .then((_) {});
}

class _SuccessAdapter implements ExternalEffectAdapter {
  const _SuccessAdapter();

  @override
  Future<ExternalEffectAdapterResult> deliver(
    ExternalEffectAdapterRequest request,
  ) async => _success(request);

  @override
  Future<ExternalEffectAdapterResult> reconcile(
    ExternalEffectAdapterRequest request,
  ) async => _success(request);

  @override
  Future<ExternalEffectAdapterResult> resolveRequiredAction(
    ExternalEffectAdapterRequest request,
    ExternalEffectRequiredAction action,
    String response,
  ) async => _success(request);

  ExternalEffectAdapterResult _success(ExternalEffectAdapterRequest request) {
    return ExternalEffectAdapterResult(
      status: ExternalEffectAdapterStatus.succeeded,
      receipt: ExternalEffectReceipt(
        operationId: request.operationId,
        providerId: request.providerId,
        providerReceiptId: 'receipt-1',
        evidenceHashHex: _receiptHash,
        receivedAtUtc: '2026-07-31T18:00:00.000Z',
      ),
    );
  }
}

const String _ownerA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _ownerB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _approvalHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const String _receiptHash =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

ExternalEffectOperation _replyOperation({required String sourceDraftHashHex}) {
  return ExternalEffectOperation(
    ownerCapsuleHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    operationId: 'moltbook-comment-test',
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountBindingId: 'account-test',
    effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
    canonicalPayloadJson:
        '{"schema_version":1,"account_name":"agent",'
        '"post_id":"post-1","parent_comment_id":"comment-1",'
        '"content":"Bound reply.","operation_marker":"marker",'
        '"source_draft_hash_hex":"$sourceDraftHashHex",'
        '"engagement_plan_hash_hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}',
    payloadHashHex:
        'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    state: ExternalEffectState.prepared,
    approvalEvidenceHashHex: null,
    attemptCount: 0,
    revision: 0,
    createdAtUtc: '2026-07-31T18:00:00.000Z',
    updatedAtUtc: '2026-07-31T18:00:00.000Z',
    lastErrorCode: null,
    lastErrorMessage: null,
    requiredAction: null,
    receipt: null,
  );
}

ExternalEffectOperation _operation({
  required ExternalEffectState state,
  required String providerReceiptId,
}) {
  const operationId = 'moltbook-post-test';
  return ExternalEffectOperation(
    ownerCapsuleHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    operationId: operationId,
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountBindingId: 'account-test',
    effectKind: MoltbookExternalEffectAdapter.effectKind,
    canonicalPayloadJson: '{}',
    payloadHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    state: state,
    approvalEvidenceHashHex:
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    attemptCount: 1,
    revision: 1,
    createdAtUtc: '2026-07-27T00:00:00.000Z',
    updatedAtUtc: '2026-07-27T00:00:01.000Z',
    lastErrorCode: null,
    lastErrorMessage: null,
    requiredAction: null,
    receipt: ExternalEffectReceipt(
      operationId: operationId,
      providerId: 'moltbook',
      providerReceiptId: providerReceiptId,
      evidenceHashHex:
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      receivedAtUtc: '2026-07-27T00:00:01.000Z',
    ),
  );
}
