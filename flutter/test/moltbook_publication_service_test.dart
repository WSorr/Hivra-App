import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/moltbook_external_effect_adapter.dart';
import 'package:hivra_app/services/moltbook_publication_service.dart';

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
