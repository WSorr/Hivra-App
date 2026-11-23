import 'dart:convert';

import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import 'plugin_host_contract_handler.dart';
import 'plugin_capability_dispatcher.dart';

class PluginWorkspaceContractHandler implements PluginHostContractHandler {
  @override
  final String pluginId;
  final Set<String> capabilities;

  const PluginWorkspaceContractHandler({
    required this.pluginId,
    this.capabilities = const {},
  });

  @override
  String get contractKind => pluginWorkspaceContractKind;
  @override
  Set<String> get methods => const {pluginWorkspaceMethod};
  @override
  bool get requiresExternalRuntime => true;
  @override
  Set<String> requiredCapabilities(String method) =>
      pluginWorkspaceRequiredCapabilities;
  @override
  PluginHostContractResult? preflight(PluginHostApiRequest request) => null;
  @override
  Future<PluginHostContractResult?> preflightAsync(
    PluginHostApiRequest request,
  ) async => null;

  @override
  PluginHostContractResult execute(
    PluginHostApiRequest request, {
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  }) {
    if (runtimeInvoke == null) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_invoke_unavailable',
        message: 'Installed WASM is required',
      );
    }
    if (runtimeInvoke.semanticStatus != PluginHostApiStatus.executed) {
      return PluginHostContractResult.rejected(
        code: runtimeInvoke.semanticErrorCode ?? 'plugin_rejected',
        message:
            runtimeInvoke.semanticErrorMessage ?? 'Plugin rejected the action',
      );
    }
    final result = runtimeInvoke.semanticResult;
    try {
      if (result == null ||
          (result['state'] != null && result['state'] is! Map) ||
          utf8.encode(jsonEncode(result['state'])).length > 32 * 1024) {
        throw const FormatException('Invalid bounded plugin state');
      }
      validateView(
        Map<String, dynamic>.from(result['view'] as Map),
        capabilities: capabilities,
      );
      if (utf8.encode(jsonEncode(result['context'])).length > 16 * 1024) {
        throw const FormatException('Continuation context exceeds its bound');
      }
      final requests = result['requests'] as List;
      if (requests.length > 1 || requests.any((r) => r is! Map)) {
        throw const FormatException('Invalid bounded plugin requests');
      }
      if (result['resume_action'] != null || result['retired_entry'] != null) {
        throw const FormatException(
          'Legacy host continuations are not executable',
        );
      }
      for (final raw in requests) {
        final r = raw as Map;
        final descriptor = PluginCapabilityDispatcher.catalog[r['kind']];
        if (descriptor == null ||
            !PluginCapabilityDispatcher.safeId(r['id']) ||
            r['continuation'] is! String ||
            !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(r['continuation'])) {
          throw const FormatException('Unknown capability request');
        }
        final permission = descriptor['permission'];
        if (permission != null && !capabilities.contains(permission)) {
          throw const FormatException('Capability request is not granted');
        }
      }
      return PluginHostContractResult.executed(result);
    } catch (_) {
      return const PluginHostContractResult.rejected(
        code: 'invalid_workspace',
        message: 'Plugin returned an invalid workspace',
      );
    }
  }

  static void validateView(
    Map<String, dynamic> view, {
    required Set<String> capabilities,
  }) {
    void requireGrants(Set<String> required) {
      if (!capabilities.containsAll(required)) {
        throw const FormatException('Workspace control is not granted');
      }
    }

    if (utf8.encode(jsonEncode(view)).length > 64 * 1024 ||
        view['title'] is! String ||
        (view['title'] as String).isEmpty ||
        view['message'] is! String ||
        (view['summary'] != null && view['summary'] is! String) ||
        (view['details_title'] != null &&
            (view['details_title'] is! String ||
                (view['details_title'] as String).isEmpty ||
                (view['details_title'] as String).length > 128)) ||
        view['details'] is! String) {
      throw const FormatException('Invalid workspace text');
    }
    final fields = view['fields'] as List;
    if (view['access'] != null) {
      PluginCapabilityDispatcher.validateAccess(view['access']);
    }
    if (view['schedule'] != null) requireGrants({'workspace.schedule'});
    final actions = view['actions'] as List;
    final columns = view['columns'] as List;
    final rows = view['rows'] as List;
    if (fields.length > 8 ||
        actions.length > 4 ||
        columns.length > 6 ||
        (rows.isNotEmpty && columns.isEmpty) ||
        rows.length > 64 ||
        columns.any((c) => c is! String) ||
        rows.any(
          (r) =>
              r is! List ||
              r.length != columns.length ||
              r.any((c) => c is! String),
        )) {
      throw const FormatException('Invalid workspace size or table');
    }
    final ids = <String>{};
    for (final field in fields) {
      if (field is! Map ||
          field['id'] is! String ||
          field['label'] is! String ||
          !ids.add(field['id'] as String) ||
          (field['advanced'] != null && field['advanced'] is! bool) ||
          !const {
            'text',
            'integer',
            'number',
            'choice',
          }.contains(field['type']) ||
          !(field['value'] is String || field['value'] is num)) {
        throw const FormatException('Invalid workspace field');
      }
      if (field['type'] == 'choice' &&
          (field['value'] is! String ||
              field['source'] is! Map ||
              (field['source'] as Map)['action'] is! String ||
              !RegExp(
                r'^[a-z][a-z0-9_]{0,63}$',
              ).hasMatch((field['source'] as Map)['action']))) {
        throw const FormatException('Invalid package option action');
      }
      if (field['type'] == 'choice' && field['source']['access'] != null) {
        PluginCapabilityDispatcher.validateAccess(field['source']['access']);
      }
    }
    ids.clear();
    for (final action in actions) {
      if (action is! Map ||
          action['id'] is! String ||
          action['label'] is! String ||
          (action['settings'] != null && action['settings'] is! bool) ||
          (action['host'] != null &&
              !const {
                'workspace.authorize',
                'workspace.start',
                'workspace.stop',
              }.contains(action['host'])) ||
          !ids.add(action['id'] as String)) {
        throw const FormatException('Invalid workspace action');
      }
      if (action['access'] != null) {
        throw const FormatException('Access is configured once by the owner');
      }
      switch (action['host']) {
        case 'workspace.authorize':
          if (view['access'] == null) {
            throw const FormatException('Credential access scope missing');
          }
        case 'workspace.start':
        case 'workspace.stop':
          requireGrants({'workspace.schedule'});
      }
    }
  }
}
