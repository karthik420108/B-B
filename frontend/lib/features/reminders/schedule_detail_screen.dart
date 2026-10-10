import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/medication_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

/// Detail + lifecycle management for one reminder schedule.
class ScheduleDetailScreen extends ConsumerStatefulWidget {
  const ScheduleDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ScheduleDetailScreen> createState() => _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends ConsumerState<ScheduleDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      _invalidate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidate() {
    ref.invalidate(scheduleDetailProvider(widget.id));
    ref.invalidate(schedulesProvider);
    ref.invalidate(todayDosesProvider);
    ref.invalidate(upcomingDosesProvider);
    ref.invalidate(medicationHistoryProvider);
  }

  Future<bool> _confirm(String title, String message, {String confirmLabel = 'Confirm'}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(confirmLabel)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _edit(MedicationSchedule schedule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => _EditScheduleDialog(schedule: schedule),
    );
    if (result == null) return;
    await _run(
      () => ref.read(medicationRepositoryProvider).updateSchedule(schedule.id, result),
      'Schedule updated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(scheduleDetailProvider(widget.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication'),
        actions: [
          AsyncView<MedicationSchedule>(
            value: async,
            onReady: (s) => IconButton(
              tooltip: 'Edit schedule',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : () => _edit(s),
            ),
          ),
        ],
      ),
      body: AsyncView<MedicationSchedule>(
        value: async,
        onRetry: () => ref.invalidate(scheduleDetailProvider(widget.id)),
        onReady: (schedule) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              icon: Icons.medication_outlined,
              title: [schedule.name, schedule.strength].whereType<String>().where((s) => s.isNotEmpty).join(' • '),
              subtitle: scheduleStatusLabel(schedule.status),
              trailing: _StatusPill(schedule: schedule),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Frequency', value: frequencyLabel(schedule.frequency)),
                  _InfoRow(label: 'Reminders', value: scheduleTimesLabel(schedule.reminderTimes)),
                  _InfoRow(label: 'Days', value: weekdaysLabel(schedule.weekdays)),
                  if (schedule.doseInstructions != null)
                    _InfoRow(label: 'Dose', value: schedule.doseInstructions!),
                  if (schedule.route != null) _InfoRow(label: 'Route', value: titleCase(schedule.route!)),
                  _InfoRow(label: 'Start', value: formatDate(schedule.startDate)),
                  if (schedule.endDate != null) _InfoRow(label: 'End', value: formatDate(schedule.endDate)),
                  if (schedule.nextDoseAt != null)
                    _InfoRow(label: 'Next dose', value: formatDateTime(schedule.nextDoseAt)),
                  if (schedule.instructions != null) _InfoRow(label: 'Instructions', value: schedule.instructions!),
                  if (schedule.notes != null) _InfoRow(label: 'Notes', value: schedule.notes!),
                  if (schedule.fromPrescription)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.description_outlined, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Created from a confirmed prescription extraction.',
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _LifecycleActions(
              schedule: schedule,
              busy: _busy,
              onPause: () => _run(
                () => ref.read(medicationRepositoryProvider).pauseSchedule(schedule.id),
                'Reminders paused.',
              ),
              onResume: () => _resume(schedule),
              onDiscontinue: () => _discontinue(schedule),
            ),
            const SizedBox(height: 16),
            SectionCard(
              icon: Icons.receipt_long_outlined,
              title: 'Recent activity',
              subtitle: 'Taken, skipped and missed entries',
              child: schedule.recentHistory.isEmpty
                  ? const Text('No recorded doses yet.')
                  : Column(
                      children: [
                        for (var i = 0; i < schedule.recentHistory.length; i++) ...[
                          if (i > 0) const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(doseStatusIcon(schedule.recentHistory[i].status),
                                    size: 18, color: doseStatusColor(context, schedule.recentHistory[i].status)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    formatDateTime(schedule.recentHistory[i].scheduledFor),
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                                Text(
                                  doseStatusLabel(schedule.recentHistory[i].status),
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: doseStatusColor(context, schedule.recentHistory[i].status),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resume(MedicationSchedule schedule) async {
    final needsConfirm = schedule.isStopped || schedule.isCompleted;
    if (needsConfirm) {
      final ok = await _confirm(
        'Reopen reminders?',
        'This medication was stopped or completed. Reopening restarts future reminders and keeps the past history.',
        confirmLabel: 'Reopen',
      );
      if (!ok) return;
    }
    await _run(
      () => ref.read(medicationRepositoryProvider).resumeSchedule(schedule.id, confirmReopen: needsConfirm),
      'Reminders resumed.',
    );
  }

  Future<void> _discontinue(MedicationSchedule schedule) async {
    final ok = await _confirm(
      'Stop reminders?',
      'Future reminders will be cancelled. Past Taken/Skipped/Missed history is kept.',
      confirmLabel: 'Stop',
    );
    if (!ok) return;
    await _run(
      () => ref.read(medicationRepositoryProvider).discontinueSchedule(schedule.id),
      'Reminders stopped.',
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.schedule});
  final MedicationSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final color = scheduleStatusColor(context, schedule.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        scheduleStatusLabel(schedule.status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LifecycleActions extends StatelessWidget {
  const _LifecycleActions({
    required this.schedule,
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onDiscontinue,
  });

  final MedicationSchedule schedule;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onDiscontinue;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (schedule.isActive) {
      children.add(OutlinedButton.icon(
        onPressed: busy ? null : onPause,
        icon: const Icon(Icons.pause_outlined),
        label: const Text('Pause'),
      ));
    }
    if (schedule.isPaused || schedule.isStopped || schedule.isCompleted) {
      children.add(FilledButton.tonalIcon(
        onPressed: busy ? null : onResume,
        icon: const Icon(Icons.play_arrow_outlined),
        label: Text(schedule.isStopped || schedule.isCompleted ? 'Reopen reminders' : 'Resume'),
      ));
    }
    if (!schedule.isStopped) {
      children.add(OutlinedButton.icon(
        onPressed: busy ? null : onDiscontinue,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Stop'),
      ));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _EditScheduleDialog extends StatefulWidget {
  const _EditScheduleDialog({required this.schedule});
  final MedicationSchedule schedule;

  @override
  State<_EditScheduleDialog> createState() => _EditScheduleDialogState();
}

class _EditScheduleDialogState extends State<_EditScheduleDialog> {
  late String _frequency = widget.schedule.frequency;
  late List<String> _times = [...widget.schedule.reminderTimes];
  late final TextEditingController _strength = TextEditingController(text: widget.schedule.strength ?? '');
  late final TextEditingController _instructions = TextEditingController(text: widget.schedule.instructions ?? '');

  @override
  void dispose() {
    _strength.dispose();
    _instructions.dispose();
    super.dispose();
  }

  void _onFrequencyChanged(String? value) {
    if (value == null) return;
    setState(() {
      _frequency = value;
      final required = frequencyRequiredTimes(value);
      if (required != null) {
        final next = <String>[];
        for (var i = 0; i < required; i++) {
          next.add(i < _times.length ? _times[i] : ['08:00', '13:00', '20:00'][i % 3]);
        }
        _times = next.toSet().toList();
      }
    });
  }

  Future<void> _pickTime(int index) async {
    final parts = _times[index].split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    setState(() => _times[index] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final required = frequencyRequiredTimes(_frequency);
    final valid = validateScheduleDraft(
      name: widget.schedule.name,
      times: _times,
      frequency: _frequency,
      startDate: widget.schedule.startDate,
      endDate: widget.schedule.endDate,
    );
    return AlertDialog(
      title: const Text('Edit schedule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: medicationFrequencies
                  .map((f) => DropdownMenuItem(value: f, child: Text(frequencyLabel(f))))
                  .toList(),
              onChanged: _onFrequencyChanged,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _times.length; i++)
                  InputChip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text(formatTime12h(_times[i])),
                    onPressed: () => _pickTime(i),
                    onDeleted: required == null && _times.length > 1
                        ? () => setState(() => _times = [..._times]..removeAt(i))
                        : null,
                  ),
                if (required == null && _times.length < 8)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    onPressed: () => setState(() => _times = [..._times, '12:00']),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _strength,
              decoration: const InputDecoration(labelText: 'Strength'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instructions,
              decoration: const InputDecoration(labelText: 'Instructions'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: valid != null
              ? null
              : () => Navigator.pop(context, {
                    'frequency': _frequency,
                    'reminderTimes': _times,
                    'strength': _strength.text.trim(),
                    'instructions': _instructions.text.trim(),
                  }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
