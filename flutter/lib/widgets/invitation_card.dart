import 'package:flutter/material.dart';
import '../models/invitation.dart';

class InvitationCard extends StatelessWidget {
  final Invitation invitation;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final bool isLoading;
  final String? loadingAction;
  final String? peerDisplayOverride;
  final String? peerIdentityHint;

  const InvitationCard({
    super.key,
    required this.invitation,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.isLoading = false,
    this.loadingAction,
    this.peerDisplayOverride,
    this.peerIdentityHint,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: invitation.kind.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  invitation.kind.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: invitation.status.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    invitation.status.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: invitation.status.color,
                    ),
                  ),
                ),
                const Spacer(),
                if (invitation.isIncoming)
                  const Icon(Icons.arrow_downward, size: 16, color: Colors.grey)
                else
                  const Icon(Icons.arrow_upward, size: 16, color: Colors.grey),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2833),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF433F50)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tag, size: 16, color: Colors.grey.shade300),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade100,
                        ),
                        children: [
                          TextSpan(
                            text: 'Invite ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          TextSpan(
                            text: invitation.invitationIdDisplay,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  label: invitation.isIncoming ? 'From' : 'To',
                  value: peerDisplayOverride ?? invitation.peerKeyDisplay,
                ),
                if (invitation.starterSlot != null)
                  _chip(
                    label: 'Starter',
                    value: 'Slot ${invitation.starterSlot! + 1}',
                    foreground: Colors.blue.shade700,
                    background: Colors.blue.shade50,
                  ),
              ],
            ),

            if (peerIdentityHint != null && peerIdentityHint!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  peerIdentityHint!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),

            const SizedBox(height: 8),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _timeRow(
                  icon: Icons.schedule,
                  label: 'Sent',
                  value: _formatDate(invitation.sentAt),
                ),
                if (invitation.respondedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _timeRow(
                      icon: invitation.status == InvitationStatus.rejected
                          ? Icons.block
                          : Icons.check_circle_outline,
                      label: invitation.status == InvitationStatus.rejected
                          ? 'Rejected'
                          : 'Responded',
                      value: _formatDate(invitation.respondedAt!),
                    ),
                  ),
                if (invitation.expiresAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _timeRow(
                      icon: invitation.isExpired
                          ? Icons.warning_amber_rounded
                          : Icons.hourglass_empty,
                      label: 'Expires',
                      value: _formatDate(invitation.expiresAt!),
                      color: invitation.isExpired
                          ? Colors.orange
                          : Colors.grey.shade600,
                    ),
                  ),
              ],
            ),

            if (invitation.rejectionReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF31262A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4A353B)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      size: 16,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        invitation.rejectionReason!.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade200,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Actions
            if (invitation.status == InvitationStatus.pending &&
                !invitation.isExpired) ...[
              const SizedBox(height: 16),
              if (invitation.isIncoming)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading ? null : onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: isLoading && loadingAction == 'accept'
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isLoading ? null : onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: isLoading && loadingAction == 'reject'
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Reject'),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isLoading ? null : onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: isLoading && loadingAction == 'cancel'
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.isNegative) {
      final future = date.difference(now);
      if (future.inMinutes < 60) {
        return 'in ${future.inMinutes} minutes';
      } else if (future.inHours < 24) {
        return 'in ${future.inHours} hours';
      }
      return 'in ${future.inDays} days';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  Widget _chip({
    required String label,
    required String value,
    Color? foreground,
    Color? background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? Colors.grey.shade900,
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 12,
            color: foreground ?? Colors.grey.shade200,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: foreground ?? Colors.grey.shade400,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _timeRow({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final resolvedColor = color ?? Colors.grey.shade600;
    return Row(
      children: [
        Icon(icon, size: 14, color: resolvedColor),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: TextStyle(
            fontSize: 12,
            color: resolvedColor,
          ),
        ),
      ],
    );
  }
}
