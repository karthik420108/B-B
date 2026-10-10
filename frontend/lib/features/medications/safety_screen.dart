import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class SafetyScreen extends ConsumerWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(medicationSafetyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Medication safety')),
      body: AsyncView<MedicationSafetyReport>(
        value: report,
        onRetry: () => ref.refresh(medicationSafetyProvider.future),
        onReady: (r) => RefreshIndicator(
          onRefresh: () async => ref.refresh(medicationSafetyProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!r.checkerAvailable)
                SectionCard(
                  icon: Icons.warning_amber_outlined,
                  title: 'Safety checker unavailable',
                  child: Text(
                    'The validated medication dataset could not be loaded, so alerts cannot be computed. Patient records are still fully available.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              _AlertSection(
                icon: Icons.sync_problem_outlined,
                title: 'Duplicate medications',
                color: theme.colorScheme.primary,
                emptyText: 'No duplicate medications detected in the current list.',
                alerts: r.duplicates.map((d) => _AlertCard(
                      title: d.normalizedTestName,
                      severity: 'duplicate',
                      effect: d.reason,
                      recommendation: d.recommendation,
                    )),
              ),
              const SizedBox(height: 16),
              _AlertSection(
                icon: Icons.report_gmailerrorred_outlined,
                title: 'Interactions',
                color: theme.colorScheme.error,
                emptyText: 'No interactions found in the validated dataset for your current medications.',
                alerts: r.interactions.map((i) => _AlertCard(
                      title: i.title,
                      severity: i.severity,
                      effect: i.effect,
                      recommendation: i.recommendation,
                      medications: i.medications,
                    )),
              ),
              const SizedBox(height: 12),
              Text(
                'Alerts are computed from a curated, evidence-based dataset and are informational only. They never change or stop a medicine and always require review by a qualified professional.',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertSection extends StatelessWidget {
  const _AlertSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.emptyText,
    required this.alerts,
  });

  final IconData icon;
  final String title;
  final Color color;
  final String emptyText;
  final Iterable<Widget> alerts;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: icon,
      title: title,
      child: alerts.isEmpty
          ? Text(emptyText, style: Theme.of(context).textTheme.bodySmall)
          : Column(children: alerts.toList()),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.title,
    required this.severity,
    required this.effect,
    required this.recommendation,
    this.medications = const [],
  });

  final String title;
  final String severity;
  final String effect;
  final String recommendation;
  final List<String> medications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHigh = severity == 'major' || severity == 'contraindicated';
    final color = isHigh ? theme.colorScheme.error : theme.colorScheme.tertiary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (medications.isNotEmpty)
                Chip(label: Text(medications.join(' + ')), visualDensity: VisualDensity.compact),
            ],
          ),
          const SizedBox(height: 6),
          Text(effect, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text('Recommendation: $recommendation', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}