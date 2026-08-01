import 'dart:typed_data';

import 'hivra_bindings.dart';

abstract class LedgerViewRuntime {
  String? exportLedger();

  String? exportCapsuleStateJson();

  String? projectInvitationCurrentViewV1(String ledgerJson);

  String? projectRelationshipCurrentViewV1(
    String ledgerJson, {
    Uint8List? localTransportPublicKey,
  });

  String? projectPairViewV1(
    String ledgerJson, {
    Uint8List? localTransportPublicKey,
  });

  Uint8List? capsuleRuntimeOwnerPublicKey();

  Uint8List? capsuleRuntimeTransportPublicKey();
}

class HivraLedgerViewRuntime implements LedgerViewRuntime {
  final HivraBindings _hivra;

  HivraLedgerViewRuntime([HivraBindings? hivra])
    : _hivra = hivra ?? HivraBindings();

  @override
  String? exportLedger() => _hivra.exportLedger();

  @override
  String? exportCapsuleStateJson() => _hivra.exportCapsuleStateJson();

  @override
  String? projectInvitationCurrentViewV1(String ledgerJson) =>
      _hivra.projectInvitationCurrentViewV1(ledgerJson);

  @override
  String? projectRelationshipCurrentViewV1(
    String ledgerJson, {
    Uint8List? localTransportPublicKey,
  }) => _hivra.projectRelationshipCurrentViewV1(
    ledgerJson,
    localTransportPublicKey: localTransportPublicKey,
  );

  @override
  String? projectPairViewV1(
    String ledgerJson, {
    Uint8List? localTransportPublicKey,
  }) => _hivra.projectPairViewV1(
    ledgerJson,
    localTransportPublicKey: localTransportPublicKey,
  );

  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() =>
      _hivra.capsuleRuntimeOwnerPublicKey();

  @override
  Uint8List? capsuleRuntimeTransportPublicKey() =>
      _hivra.capsuleNostrPublicKey();
}
