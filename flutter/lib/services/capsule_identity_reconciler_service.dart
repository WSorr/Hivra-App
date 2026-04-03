import 'capsule_index_store.dart';
import 'capsule_persistence_models.dart';

class CapsuleIdentityBinding {
  final String? seedFingerprint;
  final String? rootPubKeyHex;
  final String? nostrPubKeyHex;

  const CapsuleIdentityBinding({
    required this.seedFingerprint,
    required this.rootPubKeyHex,
    required this.nostrPubKeyHex,
  });
}

class CapsuleIdentityReconcileResult {
  final CapsulesIndex index;
  final Map<String, String> seedAliasToCanonical;

  const CapsuleIdentityReconcileResult({
    required this.index,
    required this.seedAliasToCanonical,
  });

  bool get changed => seedAliasToCanonical.isNotEmpty;
}

class CapsuleIdentityReconcilerService {
  const CapsuleIdentityReconcilerService();

  CapsuleIdentityReconcileResult reconcile({
    required CapsulesIndex index,
    required Map<String, CapsuleIdentityBinding> bindingsByPubKey,
  }) {
    final capsules = Map<String, CapsuleIndexEntry>.from(index.capsules);
    final aliasToCanonical = <String, String>{};
    var activePubKeyHex = index.activePubKeyHex;

    final bySeed = <String, List<String>>{};
    for (final entry in capsules.entries) {
      final binding = bindingsByPubKey[entry.key];
      final seedFingerprint = binding?.seedFingerprint;
      if (seedFingerprint == null || seedFingerprint.isEmpty) continue;
      bySeed.putIfAbsent(seedFingerprint, () => <String>[]).add(entry.key);
    }

    final groupedKeys = bySeed.values.where((keys) => keys.length > 1);
    for (final group in groupedKeys) {
      final canonicalPubKeyHex = _chooseCanonicalPubKeyHex(
        group,
        activePubKeyHex: activePubKeyHex,
        capsules: capsules,
        bindingsByPubKey: bindingsByPubKey,
      );

      final merged = _mergeEntryGroup(
        group,
        canonicalPubKeyHex: canonicalPubKeyHex,
        capsules: capsules,
        bindingsByPubKey: bindingsByPubKey,
      );
      capsules[canonicalPubKeyHex] = merged;

      for (final pubKeyHex in group) {
        if (pubKeyHex == canonicalPubKeyHex) continue;
        capsules.remove(pubKeyHex);
        aliasToCanonical[pubKeyHex] = canonicalPubKeyHex;
        if (activePubKeyHex == pubKeyHex) {
          activePubKeyHex = canonicalPubKeyHex;
        }
      }
    }

    for (final entry in capsules.entries.toList()) {
      final binding = bindingsByPubKey[entry.key];
      if (binding == null) continue;
      final expectedMode = _identityModeForBinding(entry.key, binding);
      if (expectedMode == null || expectedMode == entry.value.identityMode) {
        continue;
      }
      capsules[entry.key] = CapsuleIndexEntry(
        pubKeyHex: entry.value.pubKeyHex,
        createdAt: entry.value.createdAt,
        lastActive: entry.value.lastActive,
        isGenesis: entry.value.isGenesis,
        isNeste: entry.value.isNeste,
        identityMode: expectedMode,
      );
    }

    if (activePubKeyHex != null && !capsules.containsKey(activePubKeyHex)) {
      activePubKeyHex = null;
    }

    return CapsuleIdentityReconcileResult(
      index: CapsulesIndex(
        activePubKeyHex: activePubKeyHex,
        capsules: capsules,
      ),
      seedAliasToCanonical: aliasToCanonical,
    );
  }

  String _chooseCanonicalPubKeyHex(
    List<String> group, {
    required String? activePubKeyHex,
    required Map<String, CapsuleIndexEntry> capsules,
    required Map<String, CapsuleIdentityBinding> bindingsByPubKey,
  }) {
    final rootMatches = group
        .where((pubKeyHex) => bindingsByPubKey[pubKeyHex]?.rootPubKeyHex == pubKeyHex)
        .toList()
      ..sort();
    if (rootMatches.isNotEmpty) {
      return rootMatches.first;
    }

    if (activePubKeyHex != null && group.contains(activePubKeyHex)) {
      return activePubKeyHex;
    }

    final ranked = group.toList()
      ..sort((a, b) {
        final aEntry = capsules[a]!;
        final bEntry = capsules[b]!;
        final byLastActive = bEntry.lastActive.compareTo(aEntry.lastActive);
        if (byLastActive != 0) return byLastActive;
        final byCreatedAt = aEntry.createdAt.compareTo(bEntry.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return a.compareTo(b);
      });
    return ranked.first;
  }

  CapsuleIndexEntry _mergeEntryGroup(
    List<String> group, {
    required String canonicalPubKeyHex,
    required Map<String, CapsuleIndexEntry> capsules,
    required Map<String, CapsuleIdentityBinding> bindingsByPubKey,
  }) {
    final canonical = capsules[canonicalPubKeyHex]!;
    var createdAt = canonical.createdAt;
    var lastActive = canonical.lastActive;
    var isGenesis = canonical.isGenesis;

    for (final pubKeyHex in group) {
      final entry = capsules[pubKeyHex];
      if (entry == null) continue;
      if (entry.createdAt.isBefore(createdAt)) {
        createdAt = entry.createdAt;
      }
      if (entry.lastActive.isAfter(lastActive)) {
        lastActive = entry.lastActive;
      }
      if (entry.isGenesis) {
        isGenesis = true;
      }
    }

    return CapsuleIndexEntry(
      pubKeyHex: canonical.pubKeyHex,
      createdAt: createdAt,
      lastActive: lastActive,
      isGenesis: isGenesis,
      isNeste: canonical.isNeste,
      identityMode: _identityModeForBinding(
            canonicalPubKeyHex,
            bindingsByPubKey[canonicalPubKeyHex],
          ) ??
          canonical.identityMode,
    );
  }

  String? _identityModeForBinding(
    String pubKeyHex,
    CapsuleIdentityBinding? binding,
  ) {
    if (binding == null) return null;
    if (binding.rootPubKeyHex == pubKeyHex) {
      return 'root_owner';
    }
    if (binding.nostrPubKeyHex == pubKeyHex) {
      return 'legacy_nostr_owner';
    }
    return null;
  }
}
