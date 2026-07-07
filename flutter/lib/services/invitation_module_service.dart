import 'app_runtime_service.dart';
import 'capsule_address_service.dart';
import 'invitation_delivery_service.dart';
import 'invitation_intent_handler.dart';
import 'relationship_service.dart';
import 'ui_event_log_service.dart';

class InvitationModule {
  final InvitationDeliveryService delivery;
  final InvitationIntentHandler intents;
  final RelationshipService relationships;
  final CapsuleAddressService addressBook;
  final UiEventLogService uiLog;

  const InvitationModule({
    required this.delivery,
    required this.intents,
    required this.relationships,
    required this.addressBook,
    required this.uiLog,
  });
}

class InvitationModuleService {
  final AppRuntimeService runtime;

  const InvitationModuleService({
    required this.runtime,
  });

  InvitationModule build() {
    return InvitationModule(
      delivery: const InvitationDeliveryService(),
      intents: runtime.invitationIntents,
      relationships: runtime.buildRelationshipService(),
      addressBook: runtime.buildCapsuleAddressService(),
      uiLog: const UiEventLogService(),
    );
  }
}
