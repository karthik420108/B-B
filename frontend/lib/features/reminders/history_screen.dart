import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';
import 'dose_tile.dart';

/// Medication history: Taken, Skipped and Missed entries with an explicit
/// disclaimer that "Missed" is derived from missing app actions, not proof.
class MedicationHistoryScreen extends ConsumerStatefulWidget {
  const MedicationHistoryScreen({super.key});

  @override
  ConsumerState<MedicationHistoryScreen> createState() => _MedicationHistoryScreenState();
}

class _MedicationHistoryScreenState extends ConsumerState<MedicationHistoryScreen> {
  int _days = 90;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(medicationHistoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Medication history')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final d in const [7, 30, 90, 0])
                  ChoiceChip(
                    label: Text(d == 0 ? 'All' : 'Last ${d}d'),
                    selected: _days == d,
                    onSelected: (_) => setState(() => _days = d),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(medicationHistoryProvider.future),
              child: AsyncView<DoseHistory>(
                value: async,
                padding: EdgeInsets.zero,
                onRetry: () => ref.refresh(medicationHistoryProvider.future),
                onReady: (history) {
                  final cutoff = _days == 0 ? null : DateTime.now().subtract(Duration(days: _days));
                  final items = cutoff == null
                      ? history.items
                      : history.items.where((d) => (d.scheduledFor ?? DateTime.now()).isAfter(cutoff)).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (history.disclaimer.isNotEmpty)
                        Card(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Expanded(child: Text(history.disclaimer, style: theme.textTheme.bodySmall)),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: EmptyState(
                            icon: Icons.history,
                            title: 'No history yet',
                            subtitle: 'Doses you mark as taken or skipped will appear here.',
                          ),
                        )
                      else
                        for (final dose in items) ...[
                          DoseTile(dose: dose, showDate: true),
                          const SizedBox(height: 8),
                        ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
