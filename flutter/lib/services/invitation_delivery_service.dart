import 'dart:typed_data';

import 'capsule_address_service.dart';

class InvitationRecipientResolution {
  final Uint8List? transportRecipient;
  final String? errorMessage;

  const InvitationRecipientResolution._({
    required this.transportRecipient,
    required this.errorMessage,
  });

  factory InvitationRecipientResolution.success(Uint8List recipient) =>
      InvitationRecipientResolution._(
        transportRecipient: recipient,
        errorMessage: null,
      );

  factory InvitationRecipientResolution.failure(String message) =>
      InvitationRecipientResolution._(
        transportRecipient: null,
        errorMessage: message,
      );

  bool get isSuccess => transportRecipient != null;
}

class InvitationDeliveryService {
  const InvitationDeliveryService({
    CapsuleAddressService contactCards = const CapsuleAddressService(),
  }) : _contactCards = contactCards;

  final CapsuleAddressService _contactCards;

  Future<InvitationRecipientResolution> resolveRecipientAddress(
    String input,
  ) async {
    final value = input.trim();
    if (value.isEmpty) {
      return InvitationRecipientResolution.failure(
        'Please enter a capsule address',
      );
    }

    final recipient = await _contactCards.resolveTransportEndpoint(
      value,
      transport: 'nostr',
    );
    if (recipient != null) {
      return InvitationRecipientResolution.success(recipient);
    }

    final missingEndpoint = value.startsWith('h1') &&
        !await _contactCards.hasKnownNostrEndpoint(value);
    if (missingEndpoint) {
      return InvitationRecipientResolution.failure(
        'No known delivery endpoint for this capsule. Import its contact card first.',
      );
    }

    return InvitationRecipientResolution.failure(
      'Use a capsule key (h...) with an imported contact card, or a supported delivery address.',
    );
  }

  String sendFailureMessage(int code) {
    switch (code) {
      case -1:
        return 'Invalid invitation arguments';
      case -2:
        return 'Seed not found';
      case -3:
        return 'Sender key derivation failed';
      case -4:
        return 'Capsule is not initialized';
      case -5:
        return 'Delivery transport is unavailable';
      case -6:
        return 'Failed to prepare local invitation state';
      case -7:
        return 'Failed to deliver invitation';
      case -11:
        return 'No connected delivery relays available';
      case -12:
        return 'Invitation delivery timed out';
      case -13:
        return 'Delivery relay rejected the invitation';
      case -14:
        return 'Delivery relay requires or rejected authentication';
      case -1002:
        return 'Invitation delivery API is not available';
      case -1003:
        return 'Invitation delivery timed out. Pull to refresh and check status.';
      case -1004:
        return 'Active capsule bootstrap failed';
      default:
        return 'Failed to deliver invitation (code $code)';
    }
  }

  String receiveFailureMessage(int code) {
    switch (code) {
      case -1:
        return 'Seed not found on receiver';
      case -2:
        return 'Receiver key derivation failed';
      case -3:
        return 'Capsule is not initialized';
      case -4:
        return 'Delivery transport is unavailable';
      case -5:
        return 'Failed to fetch invitation deliveries';
      case -1002:
        return 'Delivery receive API is not available';
      case -1003:
        return 'Fetch timed out';
      case -1004:
        return 'Active capsule bootstrap failed';
      default:
        return 'Delivery fetch failed (code $code)';
    }
  }

  String acceptFailureMessage(int code) {
    switch (code) {
      case -1:
        return 'Invalid acceptance arguments';
      case -2:
        return 'Seed not found';
      case -3:
        return 'Failed to append InvitationAccepted';
      case -4:
        return 'Sender key derivation failed';
      case -5:
        return 'Capsule is not initialized';
      case -6:
        return 'Delivery transport is unavailable';
      case -7:
        return 'Failed to deliver InvitationAccepted';
      case -11:
        return 'No connected delivery relays available';
      case -12:
        return 'InvitationAccepted delivery timed out';
      case -13:
        return 'Delivery relay rejected InvitationAccepted';
      case -14:
        return 'Delivery relay requires or rejected authentication';
      case -8:
        return 'Matching incoming invitation not found in ledger';
      case -9:
        return 'No capacity to accept this invitation';
      case -10:
        return 'Failed to finalize local acceptance';
      case -1002:
        return 'Accept API is not available in FFI';
      case -1003:
        return 'Accept timed out';
      case -1004:
        return 'Active capsule bootstrap failed';
      default:
        return 'Failed to accept invitation (code $code)';
    }
  }

  String fetchSuccessMessage(int count) =>
      'Fetched invitation deliveries: $count new event(s)';

  String invitationSentMessage() => 'Invitation sent';
}
