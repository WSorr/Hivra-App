import 'package:flutter/material.dart';

import '../models/external_effect_models.dart';
import '../services/moltbook_publication_service.dart';

Future<bool> showMoltbookPersonFirstRuntimeCommunityApproval(
  BuildContext context,
) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: const Text('Create a permanent Moltbook community?'),
              content: const SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'm/${MoltbookPublicationService.personFirstRuntimeSubmoltName}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        MoltbookPublicationService
                            .personFirstRuntimeSubmoltDisplayName,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 12),
                      SelectableText(
                        MoltbookPublicationService
                            .personFirstRuntimeSubmoltDescription,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'This is a permanent public external effect. The exact name, description, Capsule, and Moltbook account are fixed before approval. Existing communities owned by another account are never adopted.',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create exact community'),
                ),
              ],
            ),
      ) ??
      false;
}

class MoltbookPersonFirstRuntimeCommunityCard extends StatelessWidget {
  final ExternalEffectOperation? operation;
  final bool busy;
  final bool connected;
  final VoidCallback onCreate;

  const MoltbookPersonFirstRuntimeCommunityCard({
    super.key,
    required this.operation,
    required this.busy,
    required this.connected,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final current = operation;
    final verified = current?.state == ExternalEffectState.succeeded;
    final status =
        verified
            ? 'Owned by the connected Moltbook account and verified by receipt.'
            : current == null
            ? 'Not created by this Capsule account.'
            : 'Creation state: ${current.state.wireName} '
                '(${current.lastErrorCode ?? "no receipt"}).';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'm/${MoltbookPublicationService.personFirstRuntimeSubmoltName}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              MoltbookPublicationService.personFirstRuntimeSubmoltDescription,
              style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
            ),
            const SizedBox(height: 10),
            Text(status),
            if (!verified) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !connected || busy ? null : onCreate,
                icon: const Icon(Icons.add_circle_outline),
                label: Text(
                  current == null
                      ? 'Review community creation'
                      : 'Resume exact creation',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
