import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final dashboard = ref.watch(dashboardProvider);
    final schedules = ref.watch(schedulesProvider);
    final userName = auth.user?.name.split(' ').first ?? 'there';

    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, $userName 👋'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dashboardProvider.future),
        child: AsyncView(
          value: dashboard,
          onRetry: () => ref.refresh(dashboardProvider.future),
          onReady: (data) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _QuickActions(
                onCounts: data.counts,
                reminderCount: schedules.value?.where((s) => s.isActive).length ?? 0,
              ),
              const SizedBox(height: 16),
              if (data.medicationAlerts != null && (data.medicationAlerts!.interactions.isNotEmpty || data.medicationAlerts!.duplicates.isNotEmpty)) ...[
                _MedicationAlertCard(
                  report: data.medicationAlerts!,
                  onTap: () => context.push('/medications/safety'),
                ),
                const SizedBox(height: 16),
              ],
              SectionCard(
                icon: Icons.event_outlined,
                title: 'Upcoming appointments',
                subtitle: data.upcomingAppointments.isEmpty ? 'No appointments scheduled' : null,
                child: data.upcomingAppointments.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: data.upcomingAppointments.take(3).map((a) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.event_available_outlined),
                              title: Text(a.title.isEmpty ? 'Appointment' : a.title),
                              subtitle: Text(a.providerName ?? ''),
                              trailing: Text(formatDateTime(a.dateTime), style: theme.textTheme.bodySmall),
                            )).toList(),
                      ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                icon: Icons.folder_open_outlined,
                title: 'Recent records',
                trailing: TextButton(onPressed: () => context.go('/documents'), child: const Text('See all')),
                child: data.recentDocuments.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: data.recentDocuments.take(4).map((d) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(categoryIcon(d.category)),
                              title: Text(d.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(formatDate(d.eventDate)),
                              trailing: _StatusDot(status: d.extractionStatus),
                              onTap: () => context.push('/documents/${d.id}'),
                            )).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onCounts, required this.reminderCount});
  final Map<String, int> onCounts;
  final int reminderCount;

  @override
  Widget build(BuildContext context) {
    final docs = onCounts['documents'] ?? 0;
    final shares = onCounts['shares'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.alarm_outlined,
            label: 'Reminders',
            value: '$reminderCount',
            onTap: () => context.go('/reminders'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.folder_outlined,
            label: 'Documents',
            value: '$docs',
            onTap: () => context.go('/documents'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.share_outlined,
            label: 'Shares',
            value: '$shares',
            onTap: () => context.push('/share'),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicationAlertCard extends StatelessWidget {
  const _MedicationAlertCard({required this.report, required this.onTap});
  final MedicationSafetyReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = report.interactions.length + report.duplicates.length;
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(Icons.warning_amber_outlined, color: theme.colorScheme.onErrorContainer),
        title: Text('$total medication ${total == 1 ? 'alert' : 'alerts'} need review'),
        subtitle: Text('Interactions & duplicates found in your medication list'),
        onTap: onTap,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'extracted' => Theme.of(context).colorScheme.primary,
      'failed' => Theme.of(context).colorScheme.error,
      'processing' => Colors.orange,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Tooltip(
      message: status,
      child: Icon(Icons.circle, size: 10, color: color),
    );
  }
}