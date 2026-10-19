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
  'state.plugin.read_write',
};
const String capsuleChatContractKind = 'capsule_chat';
const Set<String> capsuleChatRequiredCapabilities = <String>{
  'consensus_guard.read',
};
const String postCapsuleChatMethod = 'post_capsule_chat_message';
const String moltbookAmbassadorPluginId =
    'hivra.contract.moltbook-ambassador.v1';
const String moltbookAmbassadorContractKind = 'moltbook_ambassador_draft';
const Set<String> moltbookAmbassadorRequiredCapabilities = <String>{
  'content.draft.prepare',
  'content.engagement.plan',
  'content.feed.plan',
  'content.reply.delegate',
  'content.reply.prepare',
};

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
  if (normalizedPluginId == moltbookAmbassadorPluginId &&
      normalizedContractKind == moltbookAmbassadorContractKind) {
    return moltbookAmbassadorRequiredCapabilities;
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

const String prepareMoltbookDraftMethod = 'prepare_moltbook_draft';
const String planMoltbookHeartbeatMethod = 'plan_moltbook_heartbeat';
const String planMoltbookEngagementMethod = 'plan_moltbook_engagement';
const String prepareMoltbookReplyMethod = 'prepare_moltbook_reply';
const String authorizeMoltbookDelegatedReplyMethod =
    'authorize_moltbook_delegated_reply';
