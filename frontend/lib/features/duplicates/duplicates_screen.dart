import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  int _windowDays = 180;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dupData = ref.watch(duplicateTestsProvider(_windowDays));
    final docDupes = ref.watch(_docDupesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Duplicate alerts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('Repeated tests within a window', style: theme.textTheme.titleSmall)),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 90, label: Text('90d')),
                  ButtonSegment(value: 180, label: Text('180d')),
                  ButtonSegment(value: 365, label: Text('365d')),
                ],
                selected: {_windowDays},
                onSelectionChanged: (s) => setState(() => _windowDays = s.first),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A wider window finds repeated tests over a longer period; only pairs inside the chosen window are reported.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          AsyncView<({List<DuplicateFinding> findings, int total})>(
            value: dupData,
            onRetry: () => ref.invalidate(duplicateTestsProvider(_windowDays)),
            onReady: (data) => data.findings.isEmpty
                ? const EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'No repeated tests found',
                    subtitle: 'No duplicate test results were detected in the selected window.',
                  )
                : Column(
                    children: [
                      Text('${data.total} ${data.total == 1 ? 'finding' : 'findings'}', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),
                      for (final f in data.findings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _FindingCard(finding: f),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Text('Possible duplicate document uploads', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AsyncView<List<DuplicateFinding>>(
            value: docDupes,
            onRetry: () => ref.invalidate(_docDupesProvider),
            onReady: (docFindings) => docFindings.isEmpty
                ? const Text('No duplicate uploads detected. Documents are matched by content hash and are never deleted automatically.')
                : Column(
                    children: [
                      for (final f in docFindings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _FindingCard(finding: f),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

final _docDupesProvider = FutureProvider<List<DuplicateFinding>>((ref) {
  return ref.watch(recordsRepositoryProvider).duplicateDocuments();
});

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding});
  final DuplicateFinding finding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  finding.isDuplicateUpload ? Icons.copy_outlined : Icons.science_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(finding.normalizedTestName, style: theme.textTheme.titleSmall)),
                if (finding.gapDays != null)
                  Chip(
                    label: Text('${finding.gapDays} days apart'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(finding.reason, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Recommendation: ${finding.recommendation}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (finding.date != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Most recent: ${formatDate(finding.date)}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ),
          ],
        ),
      ),
    );
  }
}