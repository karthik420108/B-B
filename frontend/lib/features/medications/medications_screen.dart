import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class MedicationsScreen extends ConsumerWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meds = ref.watch(medicationsProvider);
    final safety = ref.watch(medicationSafetyProvider);
    final alertCount = safety.value == null
        ? 0
        : safety.value!.interactions.length + safety.value!.duplicates.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: AsyncView<List<Medication>>(
        value: meds,
        onRetry: () => ref.refresh(medicationsProvider.future),
        onReady: (items) => RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.refresh(medicationsProvider.future),
              ref.refresh(medicationSafetyProvider.future),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (alertCount > 0)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.6),
                  child: ListTile(
                    title: Text('$alertCount ${alertCount == 1 ? 'safety alert' : 'safety alerts'} need review'),
                    subtitle: const Text('Interactions and duplicate medications'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/medications/safety'),
                  ),
                ),
              if (alertCount > 0) const SizedBox(height: 16),
              if (items.isEmpty)
                const EmptyState(
                  icon: Icons.medication_outlined,
                  title: 'No medications recorded',
                  subtitle: 'Medications from your documents will appear here after extraction and review.',
                )
              else
                for (final section in _sections(items)) ...[
                  Text(section.$1, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: section.$2.map((m) => _MedicationTile(med: m)).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
            ],
          ),
        ),
      ),
    );
  }

  List<(String, List<Medication>)> _sections(List<Medication> items) {
    final active = items.where((m) => m.isActive).toList();
    final past = items.where((m) => !m.isActive).toList();
    final result = <(String, List<Medication>)>[];
    if (active.isNotEmpty) result.add(('Active', active));
    if (past.isNotEmpty) result.add(('Past / completed', past));
    return result;
  }
}

class _MedicationTile extends StatelessWidget {
  const _MedicationTile({required this.med});
  final Medication med;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      med.strength,
      med.frequency,
      med.form,
      med.route,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' • ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: const Icon(Icons.medication_outlined, size: 20),
      ),
      title: Text(med.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty) Text(details, style: theme.textTheme.bodySmall),
          MetaLine(
            provider: med.providerName,
            date: _dateRange(med),
          ),
        ],
      ),
      trailing: med.verification == 'verified'
          ? Icon(Icons.verified, size: 18, color: theme.colorScheme.primary)
          : null,
      isThreeLine: true,
    );
  }

  String? _dateRange(Medication m) {
    final start = m.startDate == null ? null : formatDate(m.startDate);
    final end = m.endDate == null ? null : formatDate(m.endDate);
    if (start == null && end == null) return null;
    return '${start ?? '?'} – ${end ?? 'now'}';
  }
}