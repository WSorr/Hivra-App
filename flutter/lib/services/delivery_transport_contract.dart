/// Host delivery contract shared by app services.
///
/// This is intentionally transport-neutral: `nostr` is the currently mounted
/// host adapter, not a domain concept and not a WASM drone identity.
abstract final class DeliveryTransportId {
  static const String nostr = 'nostr';
}

abstract final class DeliveryOutboxKind {
  static const String invitationSent = 'InvitationSent';
  static const String invitationTerminal = 'InvitationTerminal';
  static const String relationshipBroken = 'RelationshipBroken';
}

abstract final class DeliveryOutboxReason {
  static const String sendInvitationRetry = 'send_invitation_retry';
  static const String invitationTerminalRetry = 'invitation_terminal_retry';
  static const String localRelationshipBreak = 'local_relationship_break';
}
