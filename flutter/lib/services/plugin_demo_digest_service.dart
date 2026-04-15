import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'plugin_demo_contract_runner_service.dart';

class PluginDemoDigestReport {
  final String guardCanonicalJson;
  final String runCanonicalJson;
  final String guardDigestHex;
  final String runDigestHex;

  const PluginDemoDigestReport({
    required this.guardCanonicalJson,
    required this.runCanonicalJson,
    required this.guardDigestHex,
    required this.runDigestHex,
  });
}

class PluginDemoDigestService {
  const PluginDemoDigestService();

  PluginDemoDigestReport build(PluginDemoRunResult result) {
    final guardRows = result.pairResults.map(_guardRow).toList()
      ..sort(_compareRowsByPeer);
    final runRows = result.pairResults.map(_runRow).toList()
      ..sort(_compareRowsByPeer);

    final guardCanonicalJson = jsonEncode({
      'state': result.state.name,
      'ready_pairs': result.readyPairCount,
      'blocked_pairs': result.blockedPairCount,
      'pairs': guardRows,
    });
    final runCanonicalJson = jsonEncode({
      'state': result.state.name,
      'ready_pairs': result.readyPairCount,
      'blocked_pairs': result.blockedPairCount,
      'pairs': runRows,
    });

    return PluginDemoDigestReport(
      guardCanonicalJson: guardCanonicalJson,
      runCanonicalJson: runCanonicalJson,
      guardDigestHex:
          sha256.convert(utf8.encode(guardCanonicalJson)).toString(),
      runDigestHex: sha256.convert(utf8.encode(runCanonicalJson)).toString(),
    );
  }

  Map<String, dynamic> _guardRow(PluginDemoPairRunResult pair) {
    final facts = pair.blockingFacts.map((fact) => fact.key).toList()..sort();
    return <String, dynamic>{
      'peer_hex': pair.peerHex,
      'status': pair.isExecuted ? 'signable' : 'blocked',
      'consensus_hash_hex': pair.consensusHashHex ?? '-',
      'blocking_facts': facts,
    };
  }

  Map<String, dynamic> _runRow(PluginDemoPairRunResult pair) {
    final row = _guardRow(pair);
    row['outcome'] = pair.settlement?.outcome.name ?? '-';
    row['settlement_hash_hex'] = pair.settlement?.settlementHashHex ?? '-';
    return row;
  }

  int _compareRowsByPeer(Map<String, dynamic> a, Map<String, dynamic> b) {
    final peerA = a['peer_hex'] as String? ?? '';
    final peerB = b['peer_hex'] as String? ?? '';
    final byPeer = peerA.compareTo(peerB);
    if (byPeer != 0) return byPeer;
    final statusA = a['status'] as String? ?? '';
    final statusB = b['status'] as String? ?? '';
    final byStatus = statusA.compareTo(statusB);
    if (byStatus != 0) return byStatus;
    final hashA = a['consensus_hash_hex'] as String? ?? '';
    final hashB = b['consensus_hash_hex'] as String? ?? '';
    return hashA.compareTo(hashB);
  }
}
