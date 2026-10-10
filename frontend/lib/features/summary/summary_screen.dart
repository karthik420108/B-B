import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

final summaryProvider = FutureProvider<MedicalSummary>((ref) {
  return ref.watch(aiRepositoryProvider).summary();
});

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('My health summary')),
      body: AsyncView<MedicalSummary>(
        value: summary,
        onRetry: () => ref.refresh(summaryProvider.future),
        onReady: (s) => RefreshIndicator(
          onRefresh: () async => ref.refresh(summaryProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Grounded summary', style: theme.textTheme.titleSmall)),
                          Text(formatDateTime(DateTime.tryParse(s.generatedAt)), style: theme.textTheme.labelSmall),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(s.narrative, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    ],
                  ),
                ),
              ),
              if (s.counts.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  icon: Icons.assessment_outlined,
                  title: 'Records in your file',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: s.counts.entries.map((e) => Chip(
                          avatar: Icon(kindIcon(e.key), size: 16),
                          label: Text('${e.key}: ${e.value}'),
                        )).toList(),
                  ),
                ),
              ],
              if (s.missing.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  icon: Icons.help_center_outlined,
                  title: 'Information not in your file',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in s.missing) Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $m', style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ],
              if (s.citations.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  icon: Icons.format_quote_outlined,
                  title: 'Source documents',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in s.citations)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '• ${c.documentName ?? c.label ?? 'record'}${c.date != null ? ' (${formatDate(c.date)})' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (s.disclaimer.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(s.disclaimer, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}