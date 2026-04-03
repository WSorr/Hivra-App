import 'dart:typed_data';

import 'ledger_view_service.dart';

class CapsuleState {
  final Uint8List publicKey;
  final int starterCount;
  final int relationshipCount;
  final int pendingInvitations;
  final int version;
  final String ledgerHashHex;
  final bool hasLedgerHistory;
  final bool isNeste;
  final List<Uint8List?> starterIds;
  final List<String?> starterKinds;
  final Set<int> lockedStarterSlots;

  CapsuleState({
    required this.publicKey,
    required this.starterCount,
    required this.relationshipCount,
    required this.pendingInvitations,
    required this.version,
    required this.ledgerHashHex,
    required this.hasLedgerHistory,
    required this.isNeste,
    required this.starterIds,
    required this.starterKinds,
    required this.lockedStarterSlots,
  });

  List<StarterSlotState> get starterSlots {
    return List<StarterSlotState>.generate(5, (i) {
      final id = i < starterIds.length ? starterIds[i] : null;
      final kind = i < starterKinds.length ? starterKinds[i] : null;
      return StarterSlotState(
        occupied: id != null,
        kind: kind ?? 'Unknown',
        starterId: id,
        locked: lockedStarterSlots.contains(i),
      );
    });
  }
}

class StarterSlotState {
  final bool occupied;
  final String kind;
  final Uint8List? starterId;
  final bool locked;

  const StarterSlotState({
    required this.occupied,
    required this.kind,
    required this.starterId,
    required this.locked,
  });
}

class CapsuleStateManager {
  final LedgerViewService _ledgerView;
  CapsuleState? _currentState;

  CapsuleStateManager(this._ledgerView);

  CapsuleState get state {
    _currentState ??= _loadState();
    return _currentState!;
  }

  void refresh() {
    _currentState = _loadState();
  }

  // Will be used by our new FFI function
  void refreshWithFullState() {
    refresh();
  }

  CapsuleState _loadState() {
    final snapshot = _ledgerView.loadCapsuleSnapshot();
    return CapsuleState(
      publicKey: snapshot.publicKey,
      starterCount: snapshot.starterCount,
      relationshipCount: snapshot.relationshipCount,
      pendingInvitations: snapshot.pendingInvitations,
      version: snapshot.version,
      ledgerHashHex: snapshot.ledgerHashHex,
      hasLedgerHistory: snapshot.hasLedgerHistory,
      isNeste: true, // Will come from settings
      starterIds: snapshot.starterIds,
      starterKinds: snapshot.starterKinds,
      lockedStarterSlots: snapshot.lockedStarterSlots,
    );
  }
}
