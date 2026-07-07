import 'package:flutter/material.dart';

import '../../services/ai_plugin_audit_service.dart';

Color aiPluginAuditStatusColor(String status) {
  return switch (status) {
    'Critical' => Colors.red,
    'Needs attention' => Colors.orange,
    _ => Colors.green,
  };
}

class AiPluginAuditEntryTile extends StatelessWidget {
  final AiPluginAuditEntry entry;

  const AiPluginAuditEntryTile({
    super.key,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Text(entry.pluginLabel),
      subtitle: Text(
        '${entry.pluginVersion ?? 'no version'} · ${entry.packageKind} · '
        '${entry.findings.length} finding(s)',
      ),
      children: [
        ListTile(
          dense: true,
          title: const Text('Package digest'),
          subtitle: SelectableText(entry.packageDigestHex),
        ),
        ListTile(
          dense: true,
          title: const Text('Capabilities'),
          subtitle: Text(
            entry.capabilities.isEmpty ? 'none' : entry.capabilities.join(', '),
          ),
        ),
        if (entry.findings.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No findings'),
          )
        else
          ...entry.findings.map(
            (finding) => ListTile(
              dense: true,
              leading: Icon(
                finding.severity == 'critical'
                    ? Icons.error_outline
                    : Icons.warning_amber,
                color:
                    finding.severity == 'critical' ? Colors.red : Colors.orange,
              ),
              title: Text(finding.title),
              subtitle: Text(
                '${finding.detail}\nAction: ${finding.recommendedAction}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}
