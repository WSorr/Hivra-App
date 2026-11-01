const String capsuleChatPluginId = 'hivra.contract.capsule-chat.v1';

/// Canonical identity for package admission, registry records and state paths.
String? canonicalPluginId(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return null;
  if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(normalized) ||
      normalized == '.' ||
      normalized == '..') {
    throw const FormatException('Plugin id must be a safe identity segment');
  }
  return normalized;
}

const String pluginWorkspaceContractKind = 'plugin_workspace_v1';
const String pluginWorkspaceMethod = 'workspace';
const Set<String> pluginWorkspaceRequiredCapabilities = <String>{
  'workspace.render',
  'workspace.continue',
};
const String capsuleChatContractKind = 'capsule_chat';
const Set<String> capsuleChatRequiredCapabilities = <String>{
  'consensus_guard.read',
};
const String postCapsuleChatMethod = 'post_capsule_chat_message';
Set<String>? requiredCapabilitiesForPlugin({
  required String? pluginId,
  required String? contractKind,
}) {
  final normalizedPluginId = canonicalPluginId(pluginId);
  final normalizedContractKind = contractKind?.trim();
  if (normalizedContractKind == pluginWorkspaceContractKind) {
    return pluginWorkspaceRequiredCapabilities;
  }
  if (normalizedPluginId == capsuleChatPluginId &&
      normalizedContractKind == capsuleChatContractKind) {
    return capsuleChatRequiredCapabilities;
  }
  return null;
}

bool pluginCapabilitiesSatisfyContract({
  required String? pluginId,
  required String? contractKind,
  required List<String> capabilities,
}) {
  final required = requiredCapabilitiesForPlugin(
    pluginId: pluginId,
    contractKind: contractKind,
  );
  return required == null || capabilities.toSet().containsAll(required);
}
