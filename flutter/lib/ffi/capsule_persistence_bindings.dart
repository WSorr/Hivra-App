import 'hivra_bindings.dart';

typedef CapsulePersistenceBindings = HivraBindings;

abstract final class CapsulePersistenceOwnerMode {
  static const int legacyNostrOwnerMode = HivraBindings.legacyNostrOwnerMode;
  static const int rootOwnerMode = HivraBindings.rootOwnerMode;
}
