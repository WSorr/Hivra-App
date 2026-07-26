import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/external_effect_models.dart';
import '../models/moltbook_ambassador_models.dart';
import '../models/plugin_contract_ids.dart';
import 'external_effect_service.dart';
import 'moltbook_connection_service.dart';
import 'moltbook_external_effect_adapter.dart';

class MoltbookPublicationService {
  static const String defaultSubmolt = 'general';

  final MoltbookConnectionService _connection;
  final ExternalEffectService _effects;

  const MoltbookPublicationService({
    required MoltbookConnectionService connection,
    required ExternalEffectService effects,
  }) : _connection = connection,
       _effects = effects;

  Future<ExternalEffectOperation> prepare({
    required MoltbookDraftPreview draft,
    required String submoltName,
  }) async {
    final binding = await _connection.loadBinding();
    if (binding == null) {
      throw StateError('Connect a Moltbook account before publication');
    }
    if (!binding.isClaimed || !binding.isActive) {
      throw StateError('Moltbook account must be claimed and active');
    }
    final submolt = submoltName.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(submolt)) {
      throw const FormatException('Invalid Moltbook submolt name');
    }
    final semanticId =
        sha256
            .convert(
              utf8.encode(
                '${binding.accountId}\n$submolt\n${draft.draftHashHex}',
              ),
            )
            .toString();
    final operationId = 'moltbook-post-$semanticId';
    final marker = MoltbookPublicationContract.operationMarker(operationId);
    final attribution = MoltbookPublicationContract.attribution(operationId);
    final content = '${draft.body.trimRight()}\n\n$attribution';
    final canonicalPayload = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'account_name': binding.accountName,
      'submolt_name': submolt,
      'title': draft.title,
      'content': content,
      'operation_marker': marker,
      'source_draft_hash_hex': draft.draftHashHex,
    });
    return _effects.prepare(
      operationId: operationId,
      pluginId: moltbookAmbassadorPluginId,
      providerId: MoltbookConnectionService.providerId,
      accountBindingId: binding.accountId,
      effectKind: MoltbookExternalEffectAdapter.effectKind,
      canonicalPayloadJson: canonicalPayload,
    );
  }

  Future<ExternalEffectOperation> approveAndQueue(
    ExternalEffectOperation operation,
  ) async {
    _validateMoltbookOperation(operation);
    final evidenceHash =
        sha256
            .convert(
              utf8.encode(
                jsonEncode(<String, dynamic>{
                  'schema_version': 1,
                  'approval_kind': 'permanent_publication',
                  'operation_id': operation.operationId,
                  'provider_id': operation.providerId,
                  'account_binding_id': operation.accountBindingId,
                  'payload_hash_hex': operation.payloadHashHex,
                  'permanence_acknowledged': true,
                }),
              ),
            )
            .toString();
    await _effects.approve(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operation.operationId,
      approvalEvidenceHashHex: evidenceHash,
    );
    return _effects.enqueue(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operation.operationId,
    );
  }

  Future<ExternalEffectOperation> process(String operationId) {
    return _effects.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
    );
  }

  Future<ExternalEffectOperation> resolveVerification({
    required String operationId,
    required String answer,
  }) {
    return _effects.resolveRequiredAction(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
      response: answer,
    );
  }

  Future<List<ExternalEffectOperation>> list() {
    return _effects.list(pluginId: moltbookAmbassadorPluginId);
  }

  Future<ExternalEffectOperation> cancel(String operationId) {
    return _effects.cancel(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
    );
  }

  static Map<String, dynamic> decodePayload(ExternalEffectOperation operation) {
    _validateMoltbookOperation(operation);
    final decoded = jsonDecode(operation.canonicalPayloadJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid Moltbook publication payload');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static void _validateMoltbookOperation(ExternalEffectOperation operation) {
    operation.validate();
    if (operation.pluginId != moltbookAmbassadorPluginId ||
        operation.providerId != MoltbookConnectionService.providerId ||
        operation.effectKind != MoltbookExternalEffectAdapter.effectKind) {
      throw const FormatException('Operation is not a Moltbook publication');
    }
  }
}
