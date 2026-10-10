import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/medication_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';
import 'dose_tile.dart';

/// Patient hub for medication reminders: Today, Upcoming and the full list of
/// schedules. All data is patient-scoped on the backend.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _schedulerSupported = true;
  bool _permissionGranted = false;
  bool _enabling = false;
  bool _busyDose = false;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scheduler = ref.read(reminderSchedulerProvider);
      if (!mounted) return;
      setState(() {
        _schedulerSupported = scheduler.supportsScheduling;
        _permissionGranted = scheduler.permissionGranted;
      });
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _enableNotifications() async {
    setState(() => _enabling = true);
    try {
      final granted = await ref.read(reminderSyncProvider).enable();
      if (mounted) setState(() => _permissionGranted = granted);
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications were not enabled in your browser.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  Future<void> _record(DoseOccurrence dose, String action) async {
    setState(() => _busyDose = true);
    try {
      await ref.read(medicationRepositoryProvider).recordDose(dose.id, action);
      ref.invalidate(todayDosesProvider);
      ref.invalidate(upcomingDosesProvider);
      ref.invalidate(medicationHistoryProvider);
      ref.invalidate(schedulesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'TAKEN' ? 'Marked as taken.' : 'Marked as skipped.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busyDose = false);
    }
  }

  void _syncReminders(List<DoseOccurrence> upcoming) {
    if (_synced) return;
    _synced = true;
    ref.read(reminderSyncProvider).syncFromDoses(upcoming);
  }

  Future<void> _refreshAll() async {
    _synced = false;
    await Future.wait([
      ref.refresh(todayDosesProvider.future),
      ref.refresh(upcomingDosesProvider.future),
      ref.refresh(schedulesProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final upcomingAsync = ref.watch(upcomingDosesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication reminders'),
        actions: [
          IconButton(
            tooltip: 'Medication history',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/reminders/history'),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'prescription') context.push('/reminders/extract');
            },
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'prescription', child: Text('Add from prescription')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Today'), Tab(text: 'Upcoming'), Tab(text: 'Medications')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/reminders/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add medication'),
      ),
      body: Column(
        children: [
          _NotificationBanner(
            supported: _schedulerSupported,
            granted: _permissionGranted,
            busy: _enabling,
            onEnable: _enableNotifications,
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _DoseList(
                  value: ref.watch(todayDosesProvider),
                  emptyTitle: 'Nothing due today',
                  emptySubtitle: 'Doses scheduled for today will appear here.',
                  emptyIcon: Icons.check_circle_outline,
                  busyDose: _busyDose,
                  onRefresh: _refreshAll,
                  onRecord: _record,
                ),
                _DoseList(
                  value: upcomingAsync,
                  emptyTitle: 'No upcoming doses',
                  emptySubtitle: 'Add a medication to start receiving reminders.',
                  emptyIcon: Icons.upcoming_outlined,
                  busyDose: _busyDose,
                  showDate: true,
                  onRefresh: _refreshAll,
                  onRecord: _record,
                  onLoaded: _syncReminders,
                ),
                _ScheduleList(
                  value: ref.watch(schedulesProvider),
                  onRefresh: _refreshAll,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.supported,
    required this.granted,
    required this.busy,
    required this.onEnable,
  });

  final bool supported;
  final bool granted;
  final bool busy;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, text, action) = !supported
        ? (
            Icons.notifications_off_outlined,
            theme.colorScheme.outline,
            'In-app reminders only. This build targets the web; OS-level scheduled '
                'notifications are not available on this platform.',
            null,
          )
        : granted
            ? (
                Icons.notifications_active_outlined,
                theme.colorScheme.primary,
                'Browser reminders are on. They fire while this tab is open.',
                null,
              )
            : (
                Icons.notifications_outlined,
                Colors.orange.shade800,
                'Turn on browser notifications so dose reminders can appear.',
                TextButton(
                  onPressed: busy ? null : onEnable,
                  child: const Text('Enable'),
                ),
              );

    return Material(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _DoseList extends StatelessWidget {
  const _DoseList({
    required this.value,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.busyDose,
    required this.onRefresh,
    required this.onRecord,
    this.showDate = false,
    this.onLoaded,
  });

  final AsyncValue<List<DoseOccurrence>> value;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final bool busyDose;
  final bool showDate;
  final Future<void> Function() onRefresh;
  final Future<void> Function(DoseOccurrence dose, String action) onRecord;
  final void Function(List<DoseOccurrence> doses)? onLoaded;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AsyncView<List<DoseOccurrence>>(
        value: value,
        padding: EdgeInsets.zero,
        onRetry: onRefresh,
        onReady: (doses) {
          onLoaded?.call(doses);
          if (doses.isEmpty) {
            return ListView(
              children: [
                SizedBox(height: 80),
                EmptyState(icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: doses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (c, i) {
              final dose = doses[i];
              return DoseTile(
                dose: dose,
                showDate: showDate,
                busy: busyDose,
                onTaken: () => onRecord(dose, 'TAKEN'),
                onSkipped: () => onRecord(dose, 'SKIPPED'),
                onTap: () => context.push('/reminders/schedule/${dose.scheduleId}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _ScheduleList extends StatelessWidget {
  const _ScheduleList({required this.value, required this.onRefresh});
  final AsyncValue<List<MedicationSchedule>> value;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AsyncView<List<MedicationSchedule>>(
        value: value,
        padding: EdgeInsets.zero,
        onRetry: onRefresh,
        onReady: (schedules) {
          if (schedules.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.medication_outlined,
                  title: 'No medications yet',
                  subtitle: 'Add a medicine manually or extract one from a prescription.',
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: schedules.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (c, i) => _ScheduleCard(schedule: schedules[i]),
          );
        },
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule});
  final MedicationSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = scheduleStatusColor(context, schedule.status);
    return Card(
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => context.push('/reminders/schedule/${schedule.id}'),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: const Icon(Icons.medication_outlined),
        ),
        title: Text(
          [schedule.name, schedule.strength].whereType<String>().where((s) => s.isNotEmpty).join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(scheduleTimesLabel(schedule.reminderTimes), style: theme.textTheme.bodySmall),
            if (schedule.nextDoseAt != null)
              Text('Next: ${formatDateTime(schedule.nextDoseAt)}', style: theme.textTheme.bodySmall),
          ],
        ),
        isThreeLine: schedule.nextDoseAt != null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                scheduleStatusLabel(schedule.status),
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ),
            if (schedule.fromPrescription) ...[
              const SizedBox(height: 4),
              const Icon(Icons.description_outlined, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}
