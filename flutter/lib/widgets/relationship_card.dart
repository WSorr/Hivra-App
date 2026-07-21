import 'package:flutter/material.dart';
import '../models/relationship.dart';

class RelationshipCard extends StatelessWidget {
  final Relationship relationship;
  final VoidCallback? onTap;
  final VoidCallback? onBreak;

  const RelationshipCard({
    super.key,
    required this.relationship,
    this.onTap,
    this.onBreak,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = relationship.isActive;
    const brokenSurface = Color(0xFF21191D);
    const brokenBorder = Color(0xFF633038);
    const brokenAccent = Color(0xFFFF6B63);

    return Card(
      elevation: isActive ? 2 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isActive ? null : brokenSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isActive ? Colors.transparent : brokenBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Color indicator for starter kind
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: relationship.kind.color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    relationship.kind.displayName[0],
                    style: TextStyle(
                      color: relationship.kind.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Relationship info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          relationship.peerDisplayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: relationship.kind.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          relationship.kind.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: relationship.kind.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Since ${_formatDate(relationship.establishedAt)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (!relationship.isActive) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: brokenAccent.withAlpha(28),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: brokenAccent.withAlpha(72)),
                        ),
                        child: const Text(
                          'Broken',
                          style: TextStyle(
                            fontSize: 10,
                            color: brokenAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Actions
              if (relationship.isActive && onBreak != null)
                IconButton(
                  icon: const Icon(Icons.link_off, color: Colors.red),
                  onPressed: onBreak,
                  tooltip: 'Break relationship',
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30} months';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours';
    } else {
      return 'Just now';
    }
  }
}
