import 'package:flutter/material.dart';

import '../services/ai_capsule_inspection_service.dart';

class AiCapsuleReportHeaderCard extends StatelessWidget {
  final String statusLabel;
  final String snapshotHashHex;
  final VoidCallback onCopySnapshot;

  const AiCapsuleReportHeaderCard({
    super.key,
    required this.statusLabel,
    required this.snapshotHashHex,
    required this.onCopySnapshot,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.health_and_safety,
                  color: aiCapsuleStatusColor(statusLabel),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusLabel,
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
              'Snapshot $snapshotHashHex',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class AiCapsuleFindingCard extends StatelessWidget {
  final AiCapsuleInspectionFinding finding;

  const AiCapsuleFindingCard({
    super.key,
    required this.finding,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          _icon(finding.severity),
          color: _color(finding.severity),
        ),
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

class AiCapsuleSectionCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> rows;

  const AiCapsuleSectionCard({
    super.key,
    required this.title,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final labels = rows.keys.toList()..sort();
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: labels
            .map(
              (label) => ListTile(
                dense: true,
                title: Text(label),
                subtitle: SelectableText(_displayValue(rows[label])),
              ),
            )
            .toList(growable: false),
      ),
    );
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
}

class AiCapsuleErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const AiCapsuleErrorState({
    super.key,
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

Color aiCapsuleStatusColor(String status) {
  return switch (status) {
    'Critical' => Colors.red,
    'Needs attention' => Colors.orange,
    _ => Colors.green,
  };
}
