import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/medication_utils.dart';
import '../../models/models.dart';

/// A single dose row with its derived status and Taken/Skipped actions.
class DoseTile extends StatelessWidget {
  const DoseTile({
    super.key,
    required this.dose,
    this.onTaken,
    this.onSkipped,
    this.onTap,
    this.busy = false,
    this.showDate = false,
  });

  final DoseOccurrence dose;
  final VoidCallback? onTaken;
  final VoidCallback? onSkipped;
  final VoidCallback? onTap;
  final bool busy;

  /// Show the calendar date next to the time (used in history and upcoming).
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = doseStatusColor(context, dose.status);
    final when = dose.scheduledFor;
    final timeText = when == null
        ? 'Time not set'
        : (showDate ? formatDateTime(when) : clockLabel(when));
    final subtitle = [
      if (dose.strength != null && dose.strength!.isNotEmpty) dose.strength!,
      if (dose.doseInstructions != null && dose.doseInstructions!.isNotEmpty) dose.doseInstructions!,
    ].join(' • ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: statusColor.withValues(alpha: 0.14),
                    foregroundColor: statusColor,
                    child: Icon(doseStatusIcon(dose.status), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dose.scheduleName ?? 'Medication',
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle.isEmpty ? timeText : '$timeText  •  $subtitle',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (!dose.isRecorded && dose.isMissed)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'No Taken/Skipped action was recorded in the app.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: dose.status),
                ],
              ),
            ),
            if (dose.canAct && (onTaken != null || onSkipped != null)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 48),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onTaken,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Taken'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onSkipped,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Skipped'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = doseStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        doseStatusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
