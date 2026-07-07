import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/invitation.dart';
import 'consensus_runtime_service.dart';
import 'capsule_diagnostics_service.dart';
import 'capsule_persistence_models.dart';
import 'delivery_outbox_store.dart';
import 'ledger_view_service.dart';
import 'wasm_plugin_registry_service.dart';

class AiCapsuleInspectionSnapshot {
  final int schemaVersion;
  final String mode;
  final Map<String, dynamic> capsule;
  final Map<String, dynamic> ledgerSummary;
  final Map<String, dynamic> invitationSummary;
  final Map<String, dynamic> relationshipSummary;
  final Map<String, dynamic> transportSummary;
  final Map<String, dynamic> consensusSummary;
  final Map<String, dynamic> pluginSummary;
  final Map<String, dynamic> bootstrapSummary;
  final Map<String, dynamic> traceSummary;
  final Map<String, dynamic> redaction;
  final String snapshotHashHex;

  const AiCapsuleInspectionSnapshot({
    required this.schemaVersion,
    required this.mode,
    required this.capsule,
    required this.ledgerSummary,
    required this.invitationSummary,
    required this.relationshipSummary,
    required this.transportSummary,
    required this.consensusSummary,
    required this.pluginSummary,
    required this.bootstrapSummary,
    required this.traceSummary,
    required this.redaction,
    required this.snapshotHashHex,
  });

  Map<String, dynamic> toJson({bool includeHash = true}) {
    final json = <String, dynamic>{
      'schema_version': schemaVersion,
      'mode': mode,
      'capsule': capsule,
      'ledger_summary': ledgerSummary,
      'invitation_summary': invitationSummary,
      'relationship_summary': relationshipSummary,
      'transport_summary': transportSummary,
      'consensus_summary': consensusSummary,
      'plugin_summary': pluginSummary,
      'bootstrap_summary': bootstrapSummary,
      'trace_summary': traceSummary,
      'redaction': redaction,
    };
    if (includeHash) {
      json['snapshot_hash_hex'] = snapshotHashHex;
    }
    return json;
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class AiCapsuleInspectionFinding {
  final String severity;
  final String area;
  final String title;
  final String detail;
  final String recommendedAction;

  const AiCapsuleInspectionFinding({
    required this.severity,
    required this.area,
    required this.title,
    required this.detail,
    required this.recommendedAction,
  });
}

class AiCapsuleInspectionReport {
  final AiCapsuleInspectionSnapshot snapshot;
  final List<AiCapsuleInspectionFinding> findings;

  const AiCapsuleInspectionReport({
    required this.snapshot,
    required this.findings,
  });

  String get statusLabel {
    if (findings.any((finding) => finding.severity == 'critical')) {
      return 'Critical';
    }
    if (findings.any((finding) => finding.severity == 'warning')) {
      return 'Needs attention';
    }
    return 'Healthy';
  }
}

class AiCapsuleInspectionService {
  final LedgerViewService _ledgerView;
  final ConsensusRuntimeService _consensus;
  final CapsuleDiagnosticsService? _diagnostics;
  final DeliveryOutboxStore _outbox;
  final WasmPluginRegistryService _plugins;
  final String? Function() _readActiveCapsuleHex;

  const AiCapsuleInspectionService({
    required LedgerViewService ledgerView,
    required ConsensusRuntimeService consensus,
    CapsuleDiagnosticsService? diagnostics,
    DeliveryOutboxStore outbox = const DeliveryOutboxStore(),
    WasmPluginRegistryService plugins = const WasmPluginRegistryService(),
    required String? Function() readActiveCapsuleHex,
  })  : _ledgerView = ledgerView,
        _consensus = consensus,
        _diagnostics = diagnostics,
        _outbox = outbox,
        _plugins = plugins,
        _readActiveCapsuleHex = readActiveCapsuleHex;

  Future<AiCapsuleInspectionReport> inspect() async {
    final capsuleHex = _readActiveCapsuleHex()?.trim().toLowerCase();
    final capsuleSnapshot = _ledgerView.loadCapsuleSnapshot();
    final invitations = _ledgerView.loadInvitations();
    final relationshipGroups = _ledgerView.loadRelationshipGroups();
    final consensusChecks = _consensus.checks();
    final diagnosticsReport = await _tryDiagnosticsReport();
    final bootstrapReport = diagnosticsReport.bootstrap;
    final traceReport = diagnosticsReport.trace;
    final outboxItems = capsuleHex == null || capsuleHex.isEmpty
        ? const <DeliveryOutboxItem>[]
        : await _outbox.load(capsuleHex);
    final plugins = await _plugins.loadPlugins();

    final capsule = <String, dynamic>{
      'root_hex': capsuleHex ?? '',
      'root_preview': _short(capsuleHex),
      'has_runtime_key': capsuleSnapshot.publicKey.length == 32,
      'network': 'unknown',
    };
    final ledgerSummary = <String, dynamic>{
      'has_history': capsuleSnapshot.hasLedgerHistory,
      'version': capsuleSnapshot.version,
      'hash_hex': capsuleSnapshot.ledgerHashHex,
      'starter_count': capsuleSnapshot.starterCount,
      'relationship_count': capsuleSnapshot.relationshipCount,
      'pending_invitation_count': capsuleSnapshot.pendingInvitations,
      'locked_starter_slots': capsuleSnapshot.lockedStarterSlots.toList()
        ..sort(),
      'starter_kinds': capsuleSnapshot.starterKinds,
    };
    final invitationSummary = _invitationSummary(invitations);
    final relationshipSummary = <String, dynamic>{
      'peer_group_count': relationshipGroups.length,
      'active_peer_group_count':
          relationshipGroups.where((group) => group.isActive).length,
      'active_relationship_count': relationshipGroups.fold<int>(
        0,
        (sum, group) => sum + group.activeRelationships.length,
      ),
      'broken_relationship_count': relationshipGroups.fold<int>(
        0,
        (sum, group) => sum + group.brokenRelationships.length,
      ),
      'pending_remote_break_count': relationshipGroups.fold<int>(
        0,
        (sum, group) => sum + group.pendingRemoteBreakRelationships.length,
      ),
    };
    final transportSummary = _transportSummary(outboxItems);
    final consensusSummary = _consensusSummary(consensusChecks);
    final bootstrapSummary = _bootstrapSummary(bootstrapReport);
    final traceSummary = _traceSummary(traceReport);
    final pluginSummary = <String, dynamic>{
      'installed_count': plugins.length,
      'plugin_ids': plugins
          .map((plugin) => plugin.pluginId ?? plugin.displayName)
          .toSet()
          .toList()
        ..sort(),
      'capabilities':
          plugins.expand((plugin) => plugin.capabilities).toSet().toList()
            ..sort(),
    };
    final redaction = <String, dynamic>{
      'policy_version': 1,
      'secrets_redacted': true,
      'raw_seed_included': false,
      'private_keys_included': false,
      'provider_upload': false,
      'mode': 'local_only',
    };

    final snapshotWithoutHash = <String, dynamic>{
      'schema_version': 1,
      'mode': 'capsule_diagnostics_local',
      'capsule': capsule,
      'ledger_summary': ledgerSummary,
      'invitation_summary': invitationSummary,
      'relationship_summary': relationshipSummary,
      'transport_summary': transportSummary,
      'consensus_summary': consensusSummary,
      'plugin_summary': pluginSummary,
      'bootstrap_summary': bootstrapSummary,
      'trace_summary': traceSummary,
      'redaction': redaction,
    };
    final snapshotHashHex = _hashCanonical(snapshotWithoutHash);
    final snapshot = AiCapsuleInspectionSnapshot(
      schemaVersion: 1,
      mode: 'capsule_diagnostics_local',
      capsule: capsule,
      ledgerSummary: ledgerSummary,
      invitationSummary: invitationSummary,
      relationshipSummary: relationshipSummary,
      transportSummary: transportSummary,
      consensusSummary: consensusSummary,
      pluginSummary: pluginSummary,
      bootstrapSummary: bootstrapSummary,
      traceSummary: traceSummary,
      redaction: redaction,
      snapshotHashHex: snapshotHashHex,
    );

    return AiCapsuleInspectionReport(
      snapshot: snapshot,
      findings: _findings(
        snapshot: snapshot,
        pendingInvitations: invitationSummary['pending_total'] as int,
        pendingOutbox: transportSummary['pending_count'] as int,
        blockedConsensus: consensusSummary['blocked_count'] as int,
        pluginCount: pluginSummary['installed_count'] as int,
        bootstrapIssue: bootstrapSummary['issue'] as String?,
        traceIssueCount: traceSummary['issue_count'] as int,
      ),
    );
  }

  Future<CapsuleDiagnosticsReport> _tryDiagnosticsReport() async {
    final diagnostics = _diagnostics;
    if (diagnostics == null) {
      return CapsuleDiagnosticsReport(
        bootstrap: _fallbackBootstrapReport('diagnostics unavailable'),
        trace: _fallbackTraceReport(),
      );
    }
    try {
      return await diagnostics.inspect();
    } catch (error) {
      return CapsuleDiagnosticsReport(
        bootstrap: _fallbackBootstrapReport('diagnostic_error: $error'),
        trace: _fallbackTraceReport(),
      );
    }
  }

  CapsuleBootstrapReport _fallbackBootstrapReport(String issue) {
    return CapsuleBootstrapReport(
      activePubKeyHex: null,
      runtimePubKeyHex: null,
      rootPubKeyHex: null,
      nostrPubKeyHex: null,
      identityMode: 'unknown',
      bootstrapSource: 'error',
      seedAvailable: false,
      seedMatchesActiveCapsule: false,
      rootMatchesActiveCapsule: false,
      nostrMatchesActiveCapsule: false,
      runtimeMatchesRoot: false,
      runtimeMatchesNostr: false,
      stateFileExists: false,
      ledgerFileExists: false,
      backupFileExists: false,
      workerBootstrapAvailable: false,
      ledgerImportable: false,
      issue: issue,
    );
  }

  CapsuleTraceReport _fallbackTraceReport() {
    return CapsuleTraceReport(
      activePubKeyHex: null,
      runtimePubKeyHex: null,
      runtimeSeedExists: false,
      indexHasEntry: false,
      secureSeedExists: false,
      fallbackSeedExists: false,
      capsuleDirPath: '',
      capsuleDirExists: false,
      ledgerFileExists: false,
      stateFileExists: false,
      backupFileExists: false,
      legacyDocsPath: '',
      legacyLedgerExists: false,
      legacyStateExists: false,
      legacyBackupExists: false,
    );
  }

  Map<String, dynamic> _invitationSummary(List<Invitation> invitations) {
    int count(InvitationStatus status) =>
        invitations.where((invitation) => invitation.status == status).length;

    return <String, dynamic>{
      'total': invitations.length,
      'pending_total': count(InvitationStatus.pending),
      'pending_incoming': invitations
          .where((invitation) =>
              invitation.status == InvitationStatus.pending &&
              invitation.isIncoming)
          .length,
      'pending_outgoing': invitations
          .where((invitation) =>
              invitation.status == InvitationStatus.pending &&
              invitation.isOutgoing)
          .length,
      'accepted': count(InvitationStatus.accepted),
      'rejected': count(InvitationStatus.rejected),
      'expired': count(InvitationStatus.expired),
    };
  }

  Map<String, dynamic> _transportSummary(List<DeliveryOutboxItem> items) {
    int count(DeliveryOutboxStatus status) =>
        items.where((item) => item.status == status).length;
    final kinds = items.map((item) => item.kind).toSet().toList()..sort();
    final lastErrors = items
        .map((item) => item.lastError)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return <String, dynamic>{
      'outbox_count': items.length,
      'pending_count': count(DeliveryOutboxStatus.pending),
      'delivered_count': count(DeliveryOutboxStatus.delivered),
      'dead_count': count(DeliveryOutboxStatus.dead),
      'max_attempts': items.fold<int>(
        0,
        (max, item) => item.attempts > max ? item.attempts : max,
      ),
      'kinds': kinds,
      'last_errors': lastErrors.take(5).toList(growable: false),
    };
  }

  Map<String, dynamic> _bootstrapSummary(CapsuleBootstrapReport? report) {
    if (report == null) {
      return <String, dynamic>{
        'available': false,
        'issue': null,
      };
    }
    return <String, dynamic>{
      'available': true,
      'active_root_preview': _short(report.activePubKeyHex),
      'runtime_root_preview': _short(report.runtimePubKeyHex),
      'root_preview': _short(report.rootPubKeyHex),
      'nostr_preview': _short(report.nostrPubKeyHex),
      'identity_mode': report.identityMode,
      'bootstrap_source': report.bootstrapSource,
      'seed_available': report.seedAvailable,
      'seed_matches_active_capsule': report.seedMatchesActiveCapsule,
      'root_matches_active_capsule': report.rootMatchesActiveCapsule,
      'nostr_matches_active_capsule': report.nostrMatchesActiveCapsule,
      'runtime_matches_root': report.runtimeMatchesRoot,
      'runtime_matches_nostr': report.runtimeMatchesNostr,
      'state_file_exists': report.stateFileExists,
      'ledger_file_exists': report.ledgerFileExists,
      'backup_file_exists': report.backupFileExists,
      'worker_bootstrap_available': report.workerBootstrapAvailable,
      'ledger_importable': report.ledgerImportable,
      'issue': report.issue,
    };
  }

  Map<String, dynamic> _traceSummary(CapsuleTraceReport? report) {
    if (report == null) {
      return <String, dynamic>{
        'available': false,
        'issue_count': 0,
      };
    }
    final issueCount = <bool>[
      !report.runtimeSeedExists,
      !report.indexHasEntry,
      !report.secureSeedExists,
      report.fallbackSeedExists,
      !report.capsuleDirExists,
      !report.ledgerFileExists,
      report.legacyLedgerExists,
      report.legacyStateExists,
      report.legacyBackupExists,
    ].where((issue) => issue).length;
    return <String, dynamic>{
      'available': true,
      'active_root_preview': _short(report.activePubKeyHex),
      'runtime_root_preview': _short(report.runtimePubKeyHex),
      'runtime_seed_exists': report.runtimeSeedExists,
      'index_has_entry': report.indexHasEntry,
      'secure_seed_exists': report.secureSeedExists,
      'fallback_seed_exists': report.fallbackSeedExists,
      'capsule_dir_path': report.capsuleDirPath,
      'capsule_dir_exists': report.capsuleDirExists,
      'ledger_file_exists': report.ledgerFileExists,
      'state_file_exists': report.stateFileExists,
      'backup_file_exists': report.backupFileExists,
      'legacy_docs_path': report.legacyDocsPath,
      'legacy_ledger_exists': report.legacyLedgerExists,
      'legacy_state_exists': report.legacyStateExists,
      'legacy_backup_exists': report.legacyBackupExists,
      'issue_count': issueCount,
    };
  }

  Map<String, dynamic> _consensusSummary(List<ConsensusCheck> checks) {
    final blocked = checks.where((check) => !check.isSignable).toList();
    final blockingCodes = blocked
        .expand((check) => check.blockingFacts)
        .map((fact) => fact.code)
        .toSet()
        .toList()
      ..sort();
    return <String, dynamic>{
      'peer_count': checks.length,
      'signable_count': checks.where((check) => check.isSignable).length,
      'blocked_count': blocked.length,
      'blocking_codes': blockingCodes,
      'hashes': checks
          .map((check) => <String, dynamic>{
                'peer': check.peerLabel,
                'hash_hex': check.hashHex,
                'is_signable': check.isSignable,
              })
          .toList(growable: false),
    };
  }

  List<AiCapsuleInspectionFinding> _findings({
    required AiCapsuleInspectionSnapshot snapshot,
    required int pendingInvitations,
    required int pendingOutbox,
    required int blockedConsensus,
    required int pluginCount,
    required String? bootstrapIssue,
    required int traceIssueCount,
  }) {
    final findings = <AiCapsuleInspectionFinding>[];
    if (snapshot.ledgerSummary['has_history'] != true) {
      findings.add(const AiCapsuleInspectionFinding(
        severity: 'warning',
        area: 'ledger',
        title: 'Capsule has no ledger history',
        detail: 'The UI is in awaiting-history mode. Domain truth cannot be '
            'projected until ledger events are present.',
        recommendedAction:
            'Create/recover a capsule with history, import a ledger, or receive trusted events.',
      ));
    }
    if (pendingInvitations > 0) {
      findings.add(AiCapsuleInspectionFinding(
        severity: 'info',
        area: 'invitations',
        title: 'Pending invitations present',
        detail: '$pendingInvitations invitation(s) are still pending in '
            'ledger projection.',
        recommendedAction:
            'Open Invitations and accept, reject, cancel, or wait for transport retry.',
      ));
    }
    if (pendingOutbox > 0) {
      findings.add(AiCapsuleInspectionFinding(
        severity: 'warning',
        area: 'transport',
        title: 'Delivery outbox has pending work',
        detail:
            '$pendingOutbox delivery item(s) are waiting for retry or peer confirmation.',
        recommendedAction:
            'Check internet/VPN and use refresh/sync paths; local ledger state is preserved.',
      ));
    }
    if (blockedConsensus > 0) {
      findings.add(AiCapsuleInspectionFinding(
        severity: 'warning',
        area: 'consensus',
        title: 'Some peers are not signable',
        detail: '$blockedConsensus pair consensus snapshot(s) are blocked.',
        recommendedAction:
            'Inspect Relationships/Plugins consensus details before running pair-scoped drones.',
      ));
    }
    if (bootstrapIssue != null && bootstrapIssue != 'none') {
      findings.add(
        AiCapsuleInspectionFinding(
          severity: 'warning',
          area: 'bootstrap',
          title: 'Bootstrap diagnostic reports an issue',
          detail: bootstrapIssue,
          recommendedAction:
              'Open Bootstrap section and verify seed/runtime/ledger binding.',
        ),
      );
    }
    if (traceIssueCount > 0) {
      findings.add(
        AiCapsuleInspectionFinding(
          severity: 'warning',
          area: 'trace',
          title: 'Local capsule trace has warnings',
          detail: '$traceIssueCount trace check(s) require attention.',
          recommendedAction:
              'Open Filesystem Trace section and remove legacy/orphan traces only after confirming ledger truth.',
        ),
      );
    }
    if (pluginCount == 0) {
      findings.add(const AiCapsuleInspectionFinding(
        severity: 'info',
        area: 'plugins',
        title: 'No plugins installed',
        detail:
            'The capsule can operate without drones, but no WASM plugin package is installed.',
        recommendedAction:
            'Install plugins only when you need drone capabilities.',
      ));
    }
    if (findings.isEmpty) {
      findings.add(const AiCapsuleInspectionFinding(
        severity: 'info',
        area: 'capsule',
        title: 'No local issues detected',
        detail:
            'Ledger projection, transport outbox, consensus and plugin summaries have no local blockers.',
        recommendedAction:
            'Continue normal use. This is a local deterministic diagnosis, not remote proof.',
      ));
    }
    return findings;
  }

  String _hashCanonical(Object? value) {
    return sha256.convert(utf8.encode(_canonicalJson(value))).toString();
  }

  String _canonicalJson(Object? value) {
    if (value == null) return 'null';
    if (value is String) return jsonEncode(value);
    if (value is num || value is bool) return jsonEncode(value);
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    return jsonEncode(value.toString());
  }

  String _short(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 8)}';
  }
}
