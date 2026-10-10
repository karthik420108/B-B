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
        title: Text('home', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28, letterSpacing: -1.2, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black,
              child: Icon(Icons.person_outline, color: Colors.white, size: 20),
            ),
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(width: 8),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OVERVIEW', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('hello, ${userName.toLowerCase()} ', style: theme.textTheme.headlineLarge?.copyWith(fontSize: 32)),
                      const Text('👋', style: TextStyle(fontSize: 28)),
                      const Spacer(),
                      IconButton(
                        style: IconButton.styleFrom(backgroundColor: theme.colorScheme.surfaceContainerLow, shape: const CircleBorder()),
                        icon: const Icon(Icons.notifications_none, color: Colors.black),
                        onPressed: () => context.push('/notifications'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _QuickActions(
                onCounts: data.counts,
                reminderCount: schedules.value?.where((s) => s.isActive).length ?? 0,
              ),
              const SizedBox(height: 24),

              _UpcomingAppointmentsCard(appointments: data.upcomingAppointments),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('recent records', style: theme.textTheme.titleMedium?.copyWith(fontSize: 20)),
                  TextButton(onPressed: () => context.go('/documents'), child: Text('see all', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.black))),
                ],
              ),
              const SizedBox(height: 12),
              if (data.recentDocuments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No recent records found')),
                )
              else
                Column(
                  children: data.recentDocuments.take(4).map((d) => _RecentRecordTile(document: d)).toList(),
                ),
              const SizedBox(height: 24),
              _DailyClarityCard(),
              const SizedBox(height: 24),
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
            icon: Icons.description_outlined,
            label: 'records',
            value: '$reminderCount',
            onTap: () => context.go('/reminders'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.folder_open_outlined,
            label: 'documents',
            value: '$docs',
            onTap: () => context.go('/documents'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.share_outlined,
            label: 'shares',
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: Colors.black, size: 24),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingAppointmentsCard extends StatelessWidget {
  const _UpcomingAppointmentsCard({required this.appointments});
  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(32),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Text('SCHEDULE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Text('upcoming appointments', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontSize: 20)),
          const SizedBox(height: 8),
          if (appointments.isEmpty)
            Text('no appointments scheduled', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54, fontSize: 16))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: appointments.take(2).map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text('${a.title} - ${formatDateTime(a.dateTime)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70, fontSize: 15)),
              )).toList(),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('peace of mind for today', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54, fontWeight: FontWeight.w500)),
              const Spacer(),
              const CircleAvatar(radius: 4, backgroundColor: Color(0xFF8CD8A7)), // Light green dot
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentRecordTile extends StatelessWidget {
  const _RecentRecordTile({required this.document});
  final DocumentSummary document;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF9F8F4),
          child: Icon(categoryIcon(document.category), color: Colors.black87),
        ),
        title: Text(document.originalName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(formatDate(document.eventDate), style: const TextStyle(color: Colors.black54, fontSize: 13)),
        trailing: _StatusDot(status: document.extractionStatus),
        onTap: () => context.push('/documents/${document.id}'),
      ),
    );
  }
}

class _DailyClarityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F2EB), // Slightly darker than background
        borderRadius: BorderRadius.circular(32),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white,
            radius: 24,
            child: Icon(Icons.spa_outlined, color: Colors.black87),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DAILY CLARITY', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('take a deep breath. your documents are orderly and safe.', style: TextStyle(color: Colors.black87, height: 1.3)),
              ],
            ),
          ),
        ],
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