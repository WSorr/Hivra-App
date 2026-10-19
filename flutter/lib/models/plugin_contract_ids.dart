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
const String capsuleChatContractKind = 'capsule_chat';
const String postCapsuleChatMethod = 'post_capsule_chat_message';
const String moltbookAmbassadorPluginId =
    'hivra.contract.moltbook-ambassador.v1';
const String moltbookAmbassadorContractKind = 'moltbook_ambassador_draft';
const String prepareMoltbookDraftMethod = 'prepare_moltbook_draft';
const String planMoltbookHeartbeatMethod = 'plan_moltbook_heartbeat';
const String planMoltbookEngagementMethod = 'plan_moltbook_engagement';
const String prepareMoltbookReplyMethod = 'prepare_moltbook_reply';
const String authorizeMoltbookDelegatedReplyMethod =
    'authorize_moltbook_delegated_reply';
