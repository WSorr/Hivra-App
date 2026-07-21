import 'package:flutter/material.dart';

import '../services/capsule_history_ai_advisor_service.dart';
import '../services/capsule_history_projection_service.dart';

class CapsuleHistoryScreen extends StatefulWidget {
  final CapsuleHistorySubject subject;
  final CapsuleHistoryProjectionService history;
  final CapsuleHistoryAiAdvisorService? aiAdvisor;

  const CapsuleHistoryScreen({
    super.key,
    required this.subject,
    required this.history,
    this.aiAdvisor,
  });

  @override
  State<CapsuleHistoryScreen> createState() => _CapsuleHistoryScreenState();
}

class _CapsuleHistoryScreenState extends State<CapsuleHistoryScreen> {
  late CapsuleHistoryProjection _projection;
  CapsuleHistoryAiResult? _aiResult;
  String? _aiError;
  bool _isExplaining = false;

  @override
  void initState() {
    super.initState();
    _projection = widget.history.project(widget.subject);
  }

  void _refresh() {
    setState(() {
      _projection = widget.history.project(widget.subject);
      _aiResult = null;
      _aiError = null;
    });
  }

  Future<void> _explain() async {
    final advisor = widget.aiAdvisor;
    if (advisor == null || _isExplaining) return;
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Explain with AI?'),
            content: const Text(
              'Only this redacted ledger history will be sent to your selected AI '
              'provider. Raw payloads, signatures, keys, and credentials are excluded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Explain'),
              ),
            ],
          ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _isExplaining = true;
      _aiError = null;
    });
    try {
      final result = await advisor.explain(_projection);
      if (!mounted) return;
      setState(() => _aiResult = result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _aiError = error.toString().replaceFirst(
          RegExp(r'^(Bad state|Exception):\s*'),
          '',
        );
      });
    } finally {
      if (mounted) setState(() => _isExplaining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Rebuild from ledger',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HistoryHeader(projection: _projection),
          const SizedBox(height: 12),
          if (_projection.entries.isEmpty)
            const _EmptyHistory()
          else
            ..._projection.entries.map(
              (entry) => _HistoryEntryCard(entry: entry),
            ),
          if (_projection.entries.isNotEmpty && widget.aiAdvisor != null) ...[
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _isExplaining ? null : _explain,
              icon:
                  _isExplaining
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.auto_awesome_outlined),
              label: Text(_isExplaining ? 'Explaining...' : 'Explain with AI'),
            ),
          ],
          if (_aiError != null) ...[
            const SizedBox(height: 12),
            _MessageCard(
              icon: Icons.warning_amber_rounded,
              color: Colors.amber,
              text: _aiError!,
            ),
          ],
          if (_aiResult != null) ...[
            const SizedBox(height: 12),
            _AiExplanationCard(result: _aiResult!),
          ],
        ],
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  final CapsuleHistoryProjection projection;

  const _HistoryHeader({required this.projection});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              projection.subject.displayLabel,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${projection.entries.length} confirmed ledger event'
              '${projection.entries.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Reconstructed from the local Capsule ledger',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  final CapsuleHistoryEntry entry;

  const _HistoryEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _eventColor(entry.eventKind);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(_eventIcon(entry.eventKind), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.eventKind,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(entry.summary),
                  const SizedBox(height: 6),
                  Text(
                    '${entry.timeLabel} · ledger #${entry.ledgerIndex}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiExplanationCard extends StatelessWidget {
  final CapsuleHistoryAiResult result;

  const _AiExplanationCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1D2524),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  color: Colors.tealAccent,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI explanation',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  result.provider.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(result.text),
            const SizedBox(height: 10),
            Text(
              'Advisory only · ledger remains the source of truth',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _MessageCard({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const _MessageCard(
      icon: Icons.history_toggle_off,
      color: Colors.grey,
      text: 'No matching confirmed events were found in this Capsule ledger.',
    );
  }
}

Color _eventColor(String kind) {
  if (kind.contains('Broken') ||
      kind.contains('Rejected') ||
      kind.contains('Burned')) {
    return const Color(0xFFFF6B63);
  }
  if (kind.contains('Established') ||
      kind.contains('Accepted') ||
      kind.contains('Created')) {
    return Colors.greenAccent.shade400;
  }
  return Colors.orangeAccent;
}

IconData _eventIcon(String kind) {
  if (kind.contains('Broken')) return Icons.link_off;
  if (kind.contains('Established')) return Icons.link;
  if (kind.contains('Rejected')) return Icons.block;
  if (kind.contains('Accepted')) return Icons.check_circle_outline;
  if (kind.contains('Burned')) return Icons.local_fire_department_outlined;
  if (kind.contains('Starter')) return Icons.fingerprint;
  return Icons.mail_outline;
}
