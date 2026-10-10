import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'schedule_providers.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleState = ref.watch(scheduleProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () {
              // Stub: Add manual medication or upload prescription
            },
          )
        ],
      ),
      body: scheduleState.when(
        data: (doses) {
          if (doses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_month_rounded, size: 64, color: theme.colorScheme.outline.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text('No scheduled medications', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Upload a prescription to generate a schedule.', style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }

          final today = DateTime.now();
          final todayDoses = doses.where((d) => d.scheduledTime.day == today.day).toList();
          todayDoses.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

          final upcomingDoses = doses.where((d) => d.scheduledTime.day > today.day).toList();
          upcomingDoses.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              if (todayDoses.isNotEmpty) ...[
                Text('Today', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary.withOpacity(0.6))),
                const SizedBox(height: 12),
                ...todayDoses.map((d) => _DoseCard(dose: d)),
                const SizedBox(height: 24),
              ],
              if (upcomingDoses.isNotEmpty) ...[
                Text('Upcoming', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary.withOpacity(0.6))),
                const SizedBox(height: 12),
                ...upcomingDoses.map((d) => _DoseCard(dose: d)),
              ]
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load schedule: $err')),
      ),
    );
  }
}

class _DoseCard extends ConsumerStatefulWidget {
  final ScheduledDose dose;
  const _DoseCard({required this.dose});

  @override
  ConsumerState<_DoseCard> createState() => _DoseCardState();
}

class _DoseCardState extends ConsumerState<_DoseCard> {
  bool _isLoading = false;

  Future<void> _toggleTaken() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(scheduleProvider.notifier).markAsTaken(widget.dose.id, !widget.dose.isTaken);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.dose.isTaken ? 'Marked as untaken' : 'Marked as taken'),
            duration: const Duration(seconds: 1),
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status. Please try again.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat.jm();
    final isPast = widget.dose.scheduledTime.isBefore(DateTime.now()) && !widget.dose.isTaken;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: widget.dose.isTaken ? theme.colorScheme.surfaceContainerLow.withOpacity(0.5) : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isPast ? Colors.red.withOpacity(0.3) : (theme.cardTheme.shape as RoundedRectangleBorder).side.color,
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _toggleTaken,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: widget.dose.isTaken 
                      ? theme.colorScheme.primary.withOpacity(0.1) 
                      : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      timeFormat.format(widget.dose.scheduledTime),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: widget.dose.isTaken ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        decoration: widget.dose.isTaken ? TextDecoration.lineThrough : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.dose.medicationName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                decoration: widget.dose.isTaken ? TextDecoration.lineThrough : null,
                                color: widget.dose.isTaken ? theme.colorScheme.outline : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            widget.dose.strength,
                            style: theme.textTheme.labelMedium?.copyWith(
                               color: widget.dose.isTaken ? theme.colorScheme.outline : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.dose.instructions,
                        style: theme.textTheme.bodySmall?.copyWith(
                          decoration: widget.dose.isTaken ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                if (_isLoading)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(
                    widget.dose.isTaken ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: widget.dose.isTaken ? Colors.green : theme.colorScheme.outline.withOpacity(0.5),
                    size: 28,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
