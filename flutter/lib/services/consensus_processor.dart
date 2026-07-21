import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/consensus_models.dart';
import '../utils/hivra_id_format.dart';
import 'ledger_view_support.dart';

class ConsensusProcessor {
  final LedgerViewSupport _support;

  const ConsensusProcessor({
    LedgerViewSupport support = const LedgerViewSupport(),
  }) : _support = support;

  ConsensusAttestationCommitment? buildAttestationCommitment({
    required String localRootHex,
    required String peerRootHex,
    required String snapshotHashHex,
  }) {
    final local = _normalizedHex(localRootHex);
    final peer = _normalizedHex(peerRootHex);
    final snapshot = _normalizedHex(snapshotHashHex);
    if (local == null ||
        peer == null ||
        snapshot == null ||
        local.length != 64 ||
        peer.length != 64 ||
        snapshot.length != 64 ||
        local == peer) {
      return null;
    }
    final roots = <String>[local, peer]..sort();
    final canonicalJson = jsonEncode(<String, dynamic>{
      'domain': 'hivra.pair_consensus.attestation',
      'schema_version': 1,
      'pair_roots_sorted': roots,
      'snapshot_hash': snapshot,
    });
    return ConsensusAttestationCommitment(
      pairRootsSorted: List<String>.unmodifiable(roots),
      snapshotHashHex: snapshot,
      canonicalJson: canonicalJson,
      commitmentHashHex: sha256.convert(utf8.encode(canonicalJson)).toString(),
    );
  }

  List<ConsensusPreview> preview(
    List<Map<String, dynamic>> events,
    Uint8List localTransportKey, {
    Uint8List? localRootKey,
  }) {
    final localTransportHex =
        localTransportKey.length == 32 ? _hex(localTransportKey) : null;
    final localRootHex = localRootKey != null && localRootKey.length == 32
        ? _hex(localRootKey)
        : null;
    if (localTransportHex == null && localRootHex == null) {
      return const <ConsensusPreview>[];
    }

    final inviteFactsById = <String, _PairwiseInviteFact>{};
    final inviteTransportPeerById = <String, String>{};
    final inviteRootPeerById = <String, String>{};
    final transportPeerToRootPeer = <String, String>{};
    final rootAnchoredPeers = <String>{};
    final relationshipFactsByPeer = <String, List<_PairwiseRelationshipFact>>{};
    final pendingInvitationIdsByPeer = <String, Set<String>>{};
    final brokenRelationshipIdsByPeer = <String, Set<String>>{};
    final pendingRemoteBreakIdsByPeer = <String, Set<String>>{};
    final unresolvedLegacyBreaks = <_PendingLegacyBreakFact>[];
    void remapTransportPeerToRoot({
      required String transportPeerHex,
      required String rootedPeerHex,
    }) {
      if (transportPeerHex.isEmpty || rootedPeerHex.isEmpty) {
        return;
      }
      transportPeerToRootPeer[transportPeerHex] = rootedPeerHex;
      if (transportPeerHex == rootedPeerHex) {
        return;
      }
      rootAnchoredPeers.add(rootedPeerHex);
      final relationshipFacts =
          relationshipFactsByPeer.remove(transportPeerHex);
      if (relationshipFacts != null && relationshipFacts.isNotEmpty) {
        relationshipFactsByPeer
            .putIfAbsent(rootedPeerHex, () => <_PairwiseRelationshipFact>[])
            .addAll(relationshipFacts);
      }
      final brokenRelationshipIds =
          brokenRelationshipIdsByPeer.remove(transportPeerHex);
      if (brokenRelationshipIds != null && brokenRelationshipIds.isNotEmpty) {
        brokenRelationshipIdsByPeer
            .putIfAbsent(rootedPeerHex, () => <String>{})
            .addAll(brokenRelationshipIds);
      }
      final pendingRemoteBreakIds =
          pendingRemoteBreakIdsByPeer.remove(transportPeerHex);
      if (pendingRemoteBreakIds != null && pendingRemoteBreakIds.isNotEmpty) {
        pendingRemoteBreakIdsByPeer
            .putIfAbsent(rootedPeerHex, () => <String>{})
            .addAll(pendingRemoteBreakIds);
      }
    }

    void applyBreakForPeer({
      required String peerRootHex,
      required String ownStarterId,
      required int breakEventIndex,
    }) {
      if (peerRootHex.isEmpty || ownStarterId.isEmpty) {
        return;
      }
      final relationships = relationshipFactsByPeer[peerRootHex];
      final hasLaterRelationship = relationships?.any(
            (relationship) =>
                relationship.ownStarterId == ownStarterId &&
                relationship.eventIndex > breakEventIndex,
          ) ??
          false;
      if (hasLaterRelationship) {
        return;
      }
      if (relationships != null && relationships.isNotEmpty) {
        relationships.removeWhere(
          (relationship) => relationship.ownStarterId == ownStarterId,
        );
        if (relationships.isEmpty) {
          relationshipFactsByPeer.remove(peerRootHex);
        }
      }
      brokenRelationshipIdsByPeer
          .putIfAbsent(peerRootHex, () => <String>{})
          .add(ownStarterId);
      final pendingRemote = pendingRemoteBreakIdsByPeer[peerRootHex];
      if (pendingRemote != null) {
        pendingRemote.remove(ownStarterId);
        if (pendingRemote.isEmpty) {
          pendingRemoteBreakIdsByPeer.remove(peerRootHex);
        }
      }
    }

    for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
      final event = events[eventIndex];
      final kind = _support.kindLabel(event['kind']);
      final payload = _payloadBytes(event['payload']);
      final signer = _bytes32(event['signer']);

      if ((kind == 'InvitationSent' || kind == 'InvitationReceived') &&
          payload.length >= 96) {
        final toPubkeyHex = _hex(payload.sublist(64, 96));
        final signerHex = signer == null ? null : _hex(signer);
        final isIncomingByAddress =
            toPubkeyHex == localTransportHex || toPubkeyHex == localRootHex;
        final signerIsSelf = signerHex != null &&
            (signerHex == localTransportHex || signerHex == localRootHex);
        if (kind == 'InvitationReceived') {
          if (signerHex == null || !isIncomingByAddress || signerIsSelf) {
            continue;
          }
        } else {
          if (signerHex != null) {
            if (!signerIsSelf && !isIncomingByAddress) {
              continue;
            }
          } else if (isIncomingByAddress) {
            // Legacy signer-less InvitationSent rows addressed to local identity
            // are ambiguous; skip to avoid self-loop/foreign drift.
            continue;
          }
        }

        final isIncoming = kind == 'InvitationReceived' ||
            (signerHex != null && isIncomingByAddress && !signerIsSelf);
        if (!isIncoming && signerIsSelf && isIncomingByAddress) {
          // Ignore self-loop outgoing offers in pairwise consensus.
          continue;
        }
        final invitationId = _hex(payload.sublist(0, 32));
        final fact = inviteFactsById.putIfAbsent(
          invitationId,
          () => _PairwiseInviteFact(
            invitationId,
            offerEventIndex: eventIndex,
          ),
        );
        final transportPeerHex = isIncoming ? signerHex : toPubkeyHex;
        if (transportPeerHex != null && transportPeerHex.isNotEmpty) {
          inviteTransportPeerById[invitationId] = transportPeerHex;
        }
        final starterKind = switch (payload.length) {
          97 => payload[96],
          129 || 161 => payload[128],
          _ => null,
        };
        if (starterKind != null) {
          fact.starterKinds.add(starterKind);
        }
        if (kind == 'InvitationReceived' &&
            isIncoming &&
            payload.length >= 128 &&
            toPubkeyHex == localTransportHex) {
          final rootedPeerHex = _hex(payload.sublist(96, 128));
          inviteRootPeerById[invitationId] = rootedPeerHex;
          if (transportPeerHex != null && transportPeerHex.isNotEmpty) {
            remapTransportPeerToRoot(
              transportPeerHex: transportPeerHex,
              rootedPeerHex: rootedPeerHex,
            );
          }
          rootAnchoredPeers.add(rootedPeerHex);
        }
      } else if (kind == 'RelationshipEstablished' && payload.length >= 194) {
        final peerTransportHex = _hex(payload.sublist(0, 32));
        final senderTransportHex =
            payload.length >= 161 ? _hex(payload.sublist(129, 161)) : null;
        final peerRootHex = payload.length >= 226
            ? _hex(payload.sublist(194, 226))
            : peerTransportHex;
        final senderRootHex =
            payload.length >= 258 ? _hex(payload.sublist(226, 258)) : null;
        final mirroredToLocalByRoot = localRootHex != null &&
            senderRootHex != null &&
            peerRootHex == localRootHex &&
            senderRootHex != localRootHex;
        final mirroredToLocalByTransport = localTransportHex != null &&
            senderTransportHex != null &&
            peerTransportHex == localTransportHex &&
            senderTransportHex != localTransportHex;
        final effectivePeerRootHex =
            mirroredToLocalByRoot ? senderRootHex : peerRootHex;
        final effectivePeerTransportHex =
            mirroredToLocalByTransport ? senderTransportHex : peerTransportHex;
        final invitationId = _hex(payload.sublist(97, 129));
        final lineagePeerRootHex = inviteRootPeerById[invitationId];
        final hasLineageRootAnchor =
            lineagePeerRootHex != null && lineagePeerRootHex.isNotEmpty;
        final hasRelationshipRootAnchor = payload.length >= 226;
        final resolvedPeerRootHex = hasRelationshipRootAnchor
            ? effectivePeerRootHex
            : (hasLineageRootAnchor
                ? lineagePeerRootHex
                : effectivePeerRootHex);
        if (localRootHex != null && resolvedPeerRootHex == localRootHex) {
          // Ignore mirrored self-looking records from remote payload orientation.
          continue;
        }
        if (hasRelationshipRootAnchor ||
            (hasLineageRootAnchor &&
                lineagePeerRootHex != effectivePeerTransportHex)) {
          rootAnchoredPeers.add(resolvedPeerRootHex);
        }
        if (hasRelationshipRootAnchor) {
          inviteRootPeerById[invitationId] = resolvedPeerRootHex;
        } else {
          inviteRootPeerById.putIfAbsent(
              invitationId, () => resolvedPeerRootHex);
        }
        transportPeerToRootPeer[effectivePeerTransportHex] =
            resolvedPeerRootHex;
        final transportPeerHexFromInvite =
            inviteTransportPeerById[invitationId];
        if (transportPeerHexFromInvite != null) {
          transportPeerToRootPeer[transportPeerHexFromInvite] =
              resolvedPeerRootHex;
        }
        final ownStarterId = mirroredToLocalByRoot || mirroredToLocalByTransport
            ? _hex(payload.sublist(64, 96))
            : _hex(payload.sublist(32, 64));
        relationshipFactsByPeer
            .putIfAbsent(
                resolvedPeerRootHex, () => <_PairwiseRelationshipFact>[])
            .add(
              _PairwiseRelationshipFact(
                invitationId: invitationId,
                relationshipKind: payload[96],
                ownStarterId: ownStarterId,
                eventIndex: eventIndex,
                starterPair: <String>[
                  _hex(payload.sublist(32, 64)),
                  _hex(payload.sublist(64, 96)),
                ]..sort(),
              ),
            );
        final brokenForPeer = brokenRelationshipIdsByPeer[resolvedPeerRootHex];
        if (brokenForPeer != null) {
          brokenForPeer.remove(ownStarterId);
          if (brokenForPeer.isEmpty) {
            brokenRelationshipIdsByPeer.remove(resolvedPeerRootHex);
          }
        }
        final pendingRemoteForPeer =
            pendingRemoteBreakIdsByPeer[resolvedPeerRootHex];
        if (pendingRemoteForPeer != null) {
          pendingRemoteForPeer.remove(ownStarterId);
          if (pendingRemoteForPeer.isEmpty) {
            pendingRemoteBreakIdsByPeer.remove(resolvedPeerRootHex);
          }
        }
      } else if (kind == 'RelationshipBroken' && payload.length >= 64) {
        final peerRootHex = payload.length >= 96
            ? _hex(payload.sublist(64, 96))
            : transportPeerToRootPeer[_hex(payload.sublist(0, 32))];
        if (peerRootHex != null && peerRootHex.isNotEmpty) {
          final ownStarterId = _hex(payload.sublist(32, 64));
          final signerHex = signer == null ? null : _hex(signer);
          if (localRootHex != null && signerHex == null) {
            // With known local root identity, unsigned/malformed break events
            // cannot be deterministically classified as local-finalized vs
            // remote-pending, so they must not mutate consensus state.
            continue;
          }
          final signerMatchesLocalTransport = signerHex != null &&
              localTransportHex != null &&
              signerHex == localTransportHex;
          final signerMatchesLocalRoot = signerHex != null &&
              localRootHex != null &&
              signerHex == localRootHex;
          final signerMatchesLocal =
              signerMatchesLocalTransport || signerMatchesLocalRoot;
          final classifyRemotePending =
              signerHex != null && localRootHex != null && !signerMatchesLocal;
          if (classifyRemotePending) {
            final localBrokenForPeer = brokenRelationshipIdsByPeer[peerRootHex];
            final isAlreadyLocallyBroken =
                localBrokenForPeer?.contains(ownStarterId) ?? false;
            if (!isAlreadyLocallyBroken) {
              pendingRemoteBreakIdsByPeer
                  .putIfAbsent(peerRootHex, () => <String>{})
                  .add(ownStarterId);
            }
            continue;
          }
          applyBreakForPeer(
            peerRootHex: peerRootHex,
            ownStarterId: ownStarterId,
            breakEventIndex: eventIndex,
          );
        } else {
          unresolvedLegacyBreaks.add(
            _PendingLegacyBreakFact(
              peerTransportHex: _hex(payload.sublist(0, 32)),
              ownStarterId: _hex(payload.sublist(32, 64)),
              eventIndex: eventIndex,
            ),
          );
        }
      }
    }

    for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
      final event = events[eventIndex];
      final kind = _support.kindLabel(event['kind']);
      final payload = _payloadBytes(event['payload']);
      final signer = _bytes32(event['signer']);
      if (payload.length < 32) continue;

      final invitationId = _hex(payload.sublist(0, 32));
      final fact = inviteFactsById[invitationId];
      if (fact == null) continue;

      switch (kind) {
        case 'InvitationAccepted':
          if (!fact.resolveTerminal(
            status: 'accepted',
            eventIndex: eventIndex,
          )) {
            break;
          }
          final signerHex = signer == null ? null : _hex(signer);
          if (payload.length >= 128 &&
              localTransportHex != null &&
              _hex(payload.sublist(32, 64)) == localTransportHex &&
              signerHex != null &&
              signerHex != localTransportHex &&
              (localRootHex == null || signerHex != localRootHex)) {
            inviteRootPeerById[invitationId] = _hex(payload.sublist(96, 128));
          }
          break;
        case 'InvitationRejected':
          if (payload.length >= 33) {
            fact.resolveTerminal(
              status: 'rejected',
              eventIndex: eventIndex,
              rejectReason: payload[32],
            );
          }
          break;
        case 'InvitationExpired':
          final signerHex = signer == null ? null : _hex(signer);
          final senderTransportHex = inviteTransportPeerById[invitationId];
          final senderRootHex = inviteRootPeerById[invitationId];
          final senderRevocation = signerHex != null &&
              (signerHex == senderTransportHex || signerHex == senderRootHex);
          fact.resolveExpired(
            status: 'expired',
            eventIndex: eventIndex,
            senderRevocation: senderRevocation,
          );
          break;
      }
    }

    for (final entry in inviteTransportPeerById.entries) {
      final invitationId = entry.key;
      final transportPeerHex = entry.value;
      final rootedPeerHex = inviteRootPeerById[invitationId] ??
          transportPeerToRootPeer[transportPeerHex] ??
          '';
      if (rootedPeerHex.isEmpty) {
        continue;
      }
      inviteRootPeerById[invitationId] = rootedPeerHex;
      remapTransportPeerToRoot(
        transportPeerHex: transportPeerHex,
        rootedPeerHex: rootedPeerHex,
      );
    }
    for (final pendingBreak in unresolvedLegacyBreaks) {
      final peerRootHex =
          transportPeerToRootPeer[pendingBreak.peerTransportHex] ??
              pendingBreak.peerTransportHex;
      applyBreakForPeer(
        peerRootHex: peerRootHex,
        ownStarterId: pendingBreak.ownStarterId,
        breakEventIndex: pendingBreak.eventIndex,
      );
    }
    inviteRootPeerById.removeWhere((_, value) => value.isEmpty);

    final inviteFactsByPeer = <String, List<_PairwiseInviteFact>>{};
    for (final entry in inviteFactsById.entries) {
      final peerRootHex = inviteRootPeerById[entry.key];
      if (peerRootHex == null || peerRootHex.isEmpty) {
        continue;
      }
      if (entry.value.status == 'pending') {
        pendingInvitationIdsByPeer
            .putIfAbsent(peerRootHex, () => <String>{})
            .add(entry.key);
        continue;
      }
      inviteFactsByPeer
          .putIfAbsent(peerRootHex, () => <_PairwiseInviteFact>[])
          .add(entry.value);
    }

    final previews = <ConsensusPreview>[];
    final peers = <String>{
      ...inviteFactsByPeer.keys,
      ...relationshipFactsByPeer.keys,
      ...pendingInvitationIdsByPeer.keys,
      ...brokenRelationshipIdsByPeer.keys,
      ...pendingRemoteBreakIdsByPeer.keys,
    }.toList()
      ..sort();
    if (localRootHex != null) {
      peers.removeWhere((peer) => peer == localRootHex);
    }
    if (localTransportHex != null) {
      peers.removeWhere((peer) => peer == localTransportHex);
    }

    for (final peerRootHex in peers) {
      final useRootScopedLocalKey = rootAnchoredPeers.contains(peerRootHex);
      final localParticipantHex = useRootScopedLocalKey
          ? (localRootHex ?? localTransportHex)!
          : (localTransportHex ?? localRootHex)!;
      final pairRoots = <String>[localParticipantHex, peerRootHex]..sort();
      final finalizedInvitations = (inviteFactsByPeer[peerRootHex] ??
          <_PairwiseInviteFact>[])
        ..sort((a, b) => a.invitationId.compareTo(b.invitationId));
      final projectedRelationships =
          (relationshipFactsByPeer[peerRootHex] ??
                  <_PairwiseRelationshipFact>[])
              .where((relationship) {
        final terminalStatus =
            inviteFactsById[relationship.invitationId]?.status;
        return terminalStatus != 'rejected' && terminalStatus != 'expired';
      });
      final relationshipsByStateKey = <String, _PairwiseRelationshipFact>{};
      for (final relationship in projectedRelationships) {
        final stateKey =
            '${relationship.relationshipKind}:${relationship.starterPair.join(':')}';
        final existing = relationshipsByStateKey[stateKey];
        if (existing == null || relationship.eventIndex > existing.eventIndex) {
          relationshipsByStateKey[stateKey] = relationship;
        }
      }
      final relationships = relationshipsByStateKey.values.toList()
        ..sort((a, b) {
          final kindCmp = a.relationshipKind.compareTo(b.relationshipKind);
          if (kindCmp != 0) return kindCmp;
          return a.starterPair.join(':').compareTo(b.starterPair.join(':'));
        });
      final blockingFacts = <ConsensusBlockingFact>[
        ...((pendingInvitationIdsByPeer[peerRootHex] ?? const <String>{})
                .toList()
              ..sort())
            .map(
          (id) => ConsensusBlockingFact(
            code: 'pending_invitation',
            subjectId: id,
          ),
        ),
        ...((pendingRemoteBreakIdsByPeer[peerRootHex] ?? const <String>{})
                .toList()
              ..sort())
            .map(
          (starterId) => ConsensusBlockingFact(
            code: 'pending_remote_break',
            subjectId: starterId,
          ),
        ),
      ];
      if (relationships.isEmpty) {
        blockingFacts.addAll(
          ((brokenRelationshipIdsByPeer[peerRootHex] ?? const <String>{})
                  .toList()
                ..sort())
              .map(
            (starterId) => ConsensusBlockingFact(
              code: 'relationship_broken',
              subjectId: starterId,
            ),
          ),
        );
      }
      if (relationships.isEmpty) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'no_active_relationship',
            subjectId: peerRootHex,
          ),
        );
      }

      final snapshot = <String, dynamic>{
        // A pair attestation can only commit facts both participants can
        // independently reconstruct. Terminal invitation history is useful for
        // diagnostics, but delivery can be asymmetric after a relationship is
        // already established. Pending invitations still block signing above.
        'schema_version': 3,
        'pair_roots_sorted': pairRoots,
        'active_relationships': relationships
            .map((rel) => <String, dynamic>{
                  'relationship_kind': rel.relationshipKind,
                  'starter_pair': rel.starterPair,
                })
            .toList(growable: false),
      };

      final canonical = jsonEncode(snapshot);
      final digest = sha256.convert(utf8.encode(canonical)).toString();

      previews.add(
        ConsensusPreview(
          peerHex: peerRootHex,
          peerLabel: HivraIdFormat.short(
            HivraIdFormat.formatCapsuleKeyBytes(_bytesFromHex(peerRootHex)),
          ),
          invitationCount: finalizedInvitations.length,
          relationshipCount: relationships.length,
          hashHex: digest,
          canonicalJson: const JsonEncoder.withIndent('  ').convert(snapshot),
          blockingFacts:
              List<ConsensusBlockingFact>.unmodifiable(blockingFacts),
        ),
      );
    }

    return previews;
  }

  ConsensusSignableResult signable(
    List<Map<String, dynamic>> events,
    Uint8List localTransportKey, {
    required String peerHex,
    Uint8List? localRootKey,
  }) {
    final normalizedPeerHex = _normalizedHex(peerHex);
    if (normalizedPeerHex == null || normalizedPeerHex.length != 64) {
      return const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'invalid_peer_id'),
        ],
      );
    }

    final hasTransport = localTransportKey.length == 32;
    final hasRoot = localRootKey != null && localRootKey.length == 32;
    if (!hasTransport && !hasRoot) {
      return const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'invalid_local_transport_key'),
        ],
      );
    }

    final previewRow = preview(
      events,
      localTransportKey,
      localRootKey: localRootKey,
    ).firstWhere(
      (row) => row.peerHex == normalizedPeerHex,
      orElse: () => const ConsensusPreview(
        peerHex: '',
        peerLabel: '',
        invitationCount: 0,
        relationshipCount: 0,
        hashHex: '',
        canonicalJson: '',
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'consensus_peer_not_found'),
        ],
      ),
    );

    if (previewRow.peerHex.isEmpty) {
      return ConsensusSignableResult(
        preview: null,
        blockingFacts: previewRow.blockingFacts,
      );
    }

    return ConsensusSignableResult(
      preview: previewRow,
      blockingFacts: previewRow.blockingFacts,
    );
  }

  ConsensusVerifyResult verify({
    required String expectedHashHex,
    required List<ConsensusVerifyParticipant> participants,
    ConsensusSignatureVerifier? verifySignature,
  }) {
    final blockingFacts = <ConsensusBlockingFact>[];
    if (verifySignature == null) {
      blockingFacts.add(
        const ConsensusBlockingFact(
          code: 'signature_verifier_unavailable',
        ),
      );
    }
    final normalizedExpected = _normalizedHex(expectedHashHex);
    if (normalizedExpected == null || normalizedExpected.length != 64) {
      blockingFacts
          .add(const ConsensusBlockingFact(code: 'invalid_expected_hash'));
    }
    if (participants.isEmpty) {
      blockingFacts
          .add(const ConsensusBlockingFact(code: 'empty_signature_set'));
    }

    final seenParticipantIds = <String>{};
    for (final participant in participants) {
      final dedupeParticipantId =
          _normalizedParticipantIdForVerify(participant.participantId);
      if (!seenParticipantIds.add(dedupeParticipantId)) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'duplicate_participant',
            subjectId: dedupeParticipantId,
          ),
        );
      }

      final participantHash = _normalizedHex(participant.hashHex);
      if (participantHash == null || participantHash.length != 64) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'invalid_hash',
            subjectId: participant.participantId,
          ),
        );
      } else if (normalizedExpected != null &&
          participantHash != normalizedExpected) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'hash_mismatch',
            subjectId: participant.participantId,
          ),
        );
      }

      final signature = _normalizedHex(participant.signatureHex);
      if (signature == null || signature.isEmpty) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'missing_signature',
            subjectId: participant.participantId,
          ),
        );
      } else if (signature.length != 128) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'invalid_signature',
            subjectId: participant.participantId,
          ),
        );
      } else if (verifySignature != null &&
          normalizedExpected != null &&
          participantHash != null &&
          participantHash == normalizedExpected) {
        final participantIdHex = _normalizedHex(participant.participantId);
        if (participantIdHex == null || participantIdHex.length != 64) {
          blockingFacts.add(
            ConsensusBlockingFact(
              code: 'invalid_signature',
              subjectId: participant.participantId,
            ),
          );
        } else {
          final isValid = verifySignature(
            messageHashHex: normalizedExpected,
            participantIdHex: participantIdHex,
            signatureHex: signature,
          );
          if (!isValid) {
            blockingFacts.add(
              ConsensusBlockingFact(
                code: 'invalid_signature',
                subjectId: participant.participantId,
              ),
            );
          }
        }
      }
    }

    return ConsensusVerifyResult(
      state: blockingFacts.isEmpty
          ? ConsensusVerifyState.match
          : ConsensusVerifyState.mismatch,
      blockingFacts: List<ConsensusBlockingFact>.unmodifiable(blockingFacts),
    );
  }

  Uint8List _payloadBytes(dynamic payload) => _support.payloadBytes(payload);

  Uint8List? _bytes32(dynamic raw) {
    final bytes = _support.payloadBytes(raw);
    return bytes.length == 32 ? bytes : null;
  }

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _bytesFromHex(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(out);
  }

  String? _normalizedHex(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  String _normalizedParticipantIdForVerify(String value) {
    final trimmed = value.trim();
    final normalizedHex = _normalizedHex(trimmed);
    if (normalizedHex != null && normalizedHex.length == 64) {
      return normalizedHex;
    }
    return trimmed.toLowerCase();
  }
}

class _PairwiseInviteFact {
  final String invitationId;
  final int offerEventIndex;
  final Set<int> starterKinds = <int>{};
  final Set<int> rejectReasons = <int>{};
  String? _terminalStatus;

  _PairwiseInviteFact(
    this.invitationId, {
    required this.offerEventIndex,
  });

  bool resolveTerminal({
    required String status,
    required int eventIndex,
    int? rejectReason,
  }) {
    if (eventIndex <= offerEventIndex || _terminalStatus != null) {
      return false;
    }
    _terminalStatus = status;
    if (rejectReason != null) {
      rejectReasons.add(rejectReason);
    }
    return true;
  }

  bool resolveExpired({
    required String status,
    required int eventIndex,
    required bool senderRevocation,
  }) {
    if (eventIndex <= offerEventIndex) return false;
    if (_terminalStatus != null && !senderRevocation) return false;
    _terminalStatus = status;
    return true;
  }

  String get status => _terminalStatus ?? 'pending';
}

class _PairwiseRelationshipFact {
  final String invitationId;
  final int relationshipKind;
  final String ownStarterId;
  final int eventIndex;
  final List<String> starterPair;

  const _PairwiseRelationshipFact({
    required this.invitationId,
    required this.relationshipKind,
    required this.ownStarterId,
    required this.eventIndex,
    required this.starterPair,
  });
}

class _PendingLegacyBreakFact {
  final String peerTransportHex;
  final String ownStarterId;
  final int eventIndex;

  const _PendingLegacyBreakFact({
    required this.peerTransportHex,
    required this.ownStarterId,
    required this.eventIndex,
  });
}
