import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_capsule_inspection_service.dart';
import '../services/app_runtime_service.dart';

class CapsuleDoctorScreen extends StatefulWidget {
  final AppRuntimeService runtime;

  const CapsuleDoctorScreen({
    super.key,
    required this.runtime,
  });

  @override
  State<CapsuleDoctorScreen> createState() => _CapsuleDoctorScreenState();
}

class _CapsuleDoctorScreenState extends State<CapsuleDoctorScreen> {
  late final AiCapsuleInspectionService _service;
  Future<AiCapsuleInspectionReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.runtime.buildAiCapsuleInspectionService();
    _reportFuture = _service.inspect();
  }

  void _refresh() {
    setState(() {
      _reportFuture = _service.inspect();
    });
  }

  Future<void> _copySnapshot(AiCapsuleInspectionReport report) async {
    await Clipboard.setData(
      ClipboardData(text: report.snapshot.toPrettyJson()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Capsule Doctor snapshot copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capsule Doctor'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh local diagnosis',
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
            return _ErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final report = snapshot.data;
          if (report == null) {
            return _ErrorState(
              error: 'No diagnosis report',
              onRetry: _refresh,
            );
          }
          return _ReportView(
            report: report,
            onCopySnapshot: () => _copySnapshot(report),
          );
        },
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final AiCapsuleInspectionReport report;
  final VoidCallback onCopySnapshot;

  const _ReportView({
    required this.report,
    required this.onCopySnapshot,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      color: _statusColor(report.statusLabel),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        report.statusLabel,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onCopySnapshot,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy snapshot'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Local deterministic diagnosis. No AI provider call, no upload, no secrets.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Snapshot ${report.snapshot.snapshotHashHex}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...report.findings.map(_FindingCard.new),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Ledger',
          rows: _rows(report.snapshot.ledgerSummary),
        ),
        _SectionCard(
          title: 'Invitations',
          rows: _rows(report.snapshot.invitationSummary),
        ),
        _SectionCard(
          title: 'Relationships',
          rows: _rows(report.snapshot.relationshipSummary),
        ),
        _SectionCard(
          title: 'Transport Outbox',
          rows: _rows(report.snapshot.transportSummary),
        ),
        _SectionCard(
          title: 'Consensus',
          rows: _rows(report.snapshot.consensusSummary),
        ),
        _SectionCard(
          title: 'Bootstrap',
          rows: _rows(report.snapshot.bootstrapSummary),
        ),
        _SectionCard(
          title: 'Filesystem Trace',
          rows: _rows(report.snapshot.traceSummary),
        ),
        _SectionCard(
          title: 'Plugins',
          rows: _rows(report.snapshot.pluginSummary),
        ),
      ],
    );
  }

  static List<_Row> _rows(Map<String, dynamic> map) {
    final keys = map.keys.toList()..sort();
    return keys
        .map((key) => _Row(key, _displayValue(map[key])))
        .toList(growable: false);
  }

  static String _displayValue(Object? value) {
    if (value is List) {
      if (value.isEmpty) return 'none';
      if (value.length > 5) {
        return '${value.take(5).join(', ')} +${value.length - 5}';
      }
      return value.join(', ');
    }
    return value?.toString() ?? 'null';
  }

  static Color _statusColor(String status) {
    return switch (status) {
      'Critical' => Colors.red,
      'Needs attention' => Colors.orange,
      _ => Colors.green,
    };
  }
}

class _FindingCard extends StatelessWidget {
  final AiCapsuleInspectionFinding finding;

  const _FindingCard(this.finding);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_icon(finding.severity), color: _color(finding.severity)),
        title: Text(finding.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${finding.area}: ${finding.detail}'),
            const SizedBox(height: 6),
            Text('Action: ${finding.recommendedAction}'),
          ],
        ),
      ),
    );
  }

  IconData _icon(String severity) {
    return switch (severity) {
      'critical' => Icons.error,
      'warning' => Icons.warning,
      _ => Icons.info,
    };
  }

  Color _color(String severity) {
    return switch (severity) {
      'critical' => Colors.red,
      'warning' => Colors.orange,
      _ => Colors.blue,
    };
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<_Row> rows;

  const _SectionCard({
    required this.title,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: rows
            .map(
              (row) => ListTile(
                dense: true,
                title: Text(row.label),
                subtitle: SelectableText(row.value),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;

  const _Row(this.label, this.value);
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
