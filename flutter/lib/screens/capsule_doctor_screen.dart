import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_capsule_inspection_service.dart';
import '../services/ai_doctor_chat_service.dart';
import '../services/ai_plugin_audit_service.dart';
import '../services/ai_tooling_module_service.dart';
import '../services/app_runtime_service.dart';
import '../widgets/ai_diagnostics/plugin_audit_widgets.dart';
import '../widgets/ai_diagnostics/provider_widgets.dart';
import '../widgets/ai_diagnostics/report_widgets.dart';

class CapsuleDoctorScreen extends StatefulWidget {
  final AppRuntimeService runtime;

  const CapsuleDoctorScreen({super.key, required this.runtime});

  @override
  State<CapsuleDoctorScreen> createState() => _CapsuleDoctorScreenState();
}

class _CapsuleDoctorScreenState extends State<CapsuleDoctorScreen> {
  late final AiToolingModule _aiTooling;
  Future<AiCapsuleInspectionReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _aiTooling = AiToolingModuleService(runtime: widget.runtime).buildModule();
    _reportFuture = _aiTooling.capsuleInspection.inspect();
  }

  void _refresh() {
    setState(() {
      _reportFuture = _aiTooling.capsuleInspection.inspect();
    });
  }

  Future<void> _copySnapshot(AiCapsuleInspectionReport report) async {
    await Clipboard.setData(
      ClipboardData(text: report.snapshot.toPrettyJson()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Capsule diagnostics snapshot copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capsule Analyst'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh local diagnostics',
          ),
        ],
      ),
      body: FutureBuilder<AiCapsuleInspectionReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return AiCapsuleErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final report = snapshot.data;
          if (report == null) {
            return AiCapsuleErrorState(
              error: 'No diagnosis report',
              onRetry: _refresh,
            );
          }
          return _ReportView(
            report: report,
            chatService: _aiTooling.capsuleAnalystChat,
            pluginAuditService: _aiTooling.pluginAudit,
            onCopySnapshot: () => _copySnapshot(report),
          );
        },
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final AiCapsuleInspectionReport report;
  final AiDoctorChatService chatService;
  final AiPluginAuditService pluginAuditService;
  final VoidCallback onCopySnapshot;

  const _ReportView({
    required this.report,
    required this.chatService,
    required this.pluginAuditService,
    required this.onCopySnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AiCapsuleReportHeaderCard(
          statusLabel: report.statusLabel,
          snapshotHashHex: report.snapshot.snapshotHashHex,
          onCopySnapshot: onCopySnapshot,
        ),
        const SizedBox(height: 12),
        ...report.findings.map(
          (finding) => AiCapsuleFindingCard(finding: finding),
        ),
        const SizedBox(height: 12),
        AiDoctorChatCard(snapshot: report.snapshot, chatService: chatService),
        const SizedBox(height: 12),
        _PluginAuditCard(service: pluginAuditService),
        const SizedBox(height: 12),
        AiCapsuleSectionCard(
          title: 'Ledger',
          rows: report.snapshot.ledgerSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Invitations',
          rows: report.snapshot.invitationSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Relationships',
          rows: report.snapshot.relationshipSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Transport Outbox',
          rows: report.snapshot.transportSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Consensus',
          rows: report.snapshot.consensusSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Bootstrap',
          rows: report.snapshot.bootstrapSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Filesystem Trace',
          rows: report.snapshot.traceSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Plugins',
          rows: report.snapshot.pluginSummary,
        ),
      ],
    );
  }
}

class _PluginAuditCard extends StatefulWidget {
  final AiPluginAuditService service;

  const _PluginAuditCard({required this.service});

  @override
  State<_PluginAuditCard> createState() => _PluginAuditCardState();
}

class _PluginAuditCardState extends State<_PluginAuditCard> {
  Future<AiPluginAuditReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = widget.service.auditInstalledPlugins();
  }

  void _refresh() {
    setState(() {
      _reportFuture = widget.service.auditInstalledPlugins();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<AiPluginAuditReport>(
          future: _reportFuture,
          builder: (context, snapshot) {
            final report = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.extension,
                      color:
                          report == null
                              ? null
                              : aiPluginAuditStatusColor(report.statusLabel),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Plugin Auditor',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh plugin audit',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Read-only audit of installed plugin packages, ABI, entry export, declared capabilities, and package digest.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  Text(
                    snapshot.error.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.redAccent,
                    ),
                  )
                else if (report == null)
                  const Text('No plugin audit report')
                else ...[
                  SelectableText('Audit ${report.reportHashHex}'),
                  const SizedBox(height: 6),
                  Text(
                    '${report.entries.length} plugin(s) · ${report.statusLabel}',
                  ),
                  const SizedBox(height: 8),
                  if (report.entries.isEmpty)
                    const Text('No installed plugins.')
                  else
                    ...report.entries.map(
                      (entry) => AiPluginAuditEntryTile(entry: entry),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
