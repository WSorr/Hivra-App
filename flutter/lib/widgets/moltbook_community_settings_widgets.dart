import 'package:flutter/material.dart';

Future<bool> showMoltbookCommunityCreationApproval(
  BuildContext context, {
  required String name,
  required String displayName,
  required String description,
  required bool allowCrypto,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Create a permanent Moltbook community?'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'm/$name',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(description),
                      const SizedBox(height: 12),
                      Text(
                        allowCrypto
                            ? 'Crypto-related posts are allowed.'
                            : 'Crypto-related posts will be blocked by Moltbook.',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'The connected Moltbook account becomes the owner and is responsible for moderation. Moltbook limits community creation to one per hour and applies stricter limits during the first 24 hours. The exact name, description, crypto policy, Capsule, and account are fixed before approval. Existing communities are never adopted or recreated.',
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
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Create exact community'),
                ),
              ],
            ),
      ) ??
      false;
}

class MoltbookCommunitySettingsCard extends StatelessWidget {
  final TextEditingController primaryCommunityController;
  final TextEditingController displayNameController;
  final TextEditingController descriptionController;
  final bool allowCrypto;
  final bool ownershipVerified;
  final bool connected;
  final bool busy;
  final ValueChanged<String> onPrimaryCommunityChanged;
  final ValueChanged<bool> onAllowCryptoChanged;
  final VoidCallback onCreate;

  const MoltbookCommunitySettingsCard({
    super.key,
    required this.primaryCommunityController,
    required this.displayNameController,
    required this.descriptionController,
    required this.allowCrypto,
    required this.ownershipVerified,
    required this.connected,
    required this.busy,
    required this.onPrimaryCommunityChanged,
    required this.onAllowCryptoChanged,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Publishing community',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Choose where this Capsule publishes. Ownership is required only when creating a new community.',
            style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: primaryCommunityController,
          onChanged: onPrimaryCommunityChanged,
          decoration: const InputDecoration(
            labelText: 'Primary community',
            prefixText: 'm/',
            helperText:
                'Use person-first-runtime, another existing community, or a new name you will create.',
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            ownershipVerified
                ? 'Created by this connected account and verified.'
                : 'Existing communities can be used without being their owner.',
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: const Text('Create a new community'),
          subtitle: const Text('Permanent Moltbook owner action'),
          children: [
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow crypto content'),
              subtitle: const Text(
                'Moltbook removes crypto-related posts when this is off.',
              ),
              value: allowCrypto,
              onChanged: onAllowCryptoChanged,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: !connected || busy ? null : onCreate,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Review permanent creation'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
