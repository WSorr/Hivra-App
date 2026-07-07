import 'package:flutter/material.dart';

import '../../services/ai_doctor_prompt_service.dart';

class AiOutboundPreviewPanel extends StatelessWidget {
  final AiDoctorOutboundPreview preview;

  const AiOutboundPreviewPanel({
    super.key,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Outbound preview', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText('Snapshot ${preview.snapshotHashHex}'),
          Text('Sections: ${preview.sectionsLabel}'),
          Text('Payload: ${preview.payloadBytes} bytes'),
          Text('Query: ${preview.userQueryBytes} bytes'),
          Text('Secrets redacted: ${preview.secretsRedacted}'),
        ],
      ),
    );
  }
}

class AiStatusMessage extends StatelessWidget {
  final String message;

  const AiStatusMessage({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarning = _isProviderWarning(message);
    final color = isWarning ? Colors.amberAccent : Colors.redAccent;
    final icon = isWarning ? Icons.info_outline : Icons.error_outline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isProviderWarning(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('quota') ||
        normalized.contains('rate limit') ||
        normalized.contains('api key was rejected') ||
        normalized.contains('openai api') ||
        normalized.contains('ai provider') ||
        normalized.contains('billing') ||
        normalized.contains('provider request failed') ||
        normalized.contains('secure ai credential storage') ||
        normalized.contains('secure ai endpoint storage') ||
        normalized.contains('gemini api');
  }
}
