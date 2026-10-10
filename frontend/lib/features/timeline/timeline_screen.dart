import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/test_chart.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  String? _selectedTest;

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider);
    final observations = ref.watch(observationsProvider);

    final tests = observations.value ?? const <Observation>[];
    final testNames = <String>{};
    for (final o in tests) {
      if (o.testName.isNotEmpty) testNames.add(o.testName);
    }
    final sorted = testNames.toList()..sort();
    String? chartTest;
    if (sorted.isNotEmpty) {
      chartTest = _selectedTest ?? sorted.first;
      if (!sorted.contains(_selectedTest)) _selectedTest = null;
      chartTest = _selectedTest ?? sorted.first;
    }

    final chartObs = sorted.isEmpty
        ? const <Observation>[]
        : tests.where((o) => o.testName == chartTest).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Health timeline')),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(timelineProvider.future),
            ref.refresh(observationsProvider.future),
          ]);
        },
        child: AsyncView<List<TimelineItem>>(
          padding: EdgeInsets.zero,
          value: timeline,
          onRetry: () => ref.refresh(timelineProvider.future),
          onReady: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.timeline_outlined,
                title: 'No records yet',
                subtitle: 'Upload a document to start building your timeline.',
              );
            }
            final grouped = _groupByMonth(items);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (sorted.isNotEmpty && chartObs.length >= 2) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.show_chart, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Lab trend', style: Theme.of(context).textTheme.titleSmall)),
                              DropdownButton<String>(
                                value: chartTest,
                                isDense: true,
                                underline: const SizedBox.shrink(),
                                items: sorted.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                onChanged: (v) => setState(() => _selectedTest = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ObservationTrendChart(observations: chartObs, height: 180),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final entry in grouped.entries) ...[
                  _MonthHeader(label: entry.key),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: entry.value.map((item) => _TimelineTile(item: item)).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Map<String, List<TimelineItem>> _groupByMonth(List<TimelineItem> items) {
    final unknown = <TimelineItem>[];
    final byMonth = <String, List<TimelineItem>>{};
    for (final item in items) {
      final date = item.date;
      if (date == null || item.dateUnknown) {
        unknown.add(item);
        continue;
      }
      final key = DateFormat('MMMM yyyy').format(date);
      byMonth.putIfAbsent(key, () => []).add(item);
    }
    final sortedKeys = byMonth.keys.toList()..sort((a, b) {
        final da = DateFormat('MMMM yyyy').parse(a);
        final db = DateFormat('MMMM yyyy').parse(b);
        return db.compareTo(da);
      });
    final result = <String, List<TimelineItem>>{};
    for (final k in sortedKeys) {
      result[k] = byMonth[k]!..sort((a, b) {
          final da = a.date;
          final db = b.date;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
    }
    if (unknown.isNotEmpty) {
      result['Date unknown'] = unknown;
    }
    return result;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700))),
        if (label == 'Date unknown')
          Icon(Icons.help_outline, size: 16, color: theme.colorScheme.outline),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.item});
  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: Icon(kindIcon(item.kind), size: 20),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.subtitle != null && item.subtitle!.isNotEmpty)
            Text(item.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          MetaLine(
            provider: item.providerName,
            date: item.dateUnknown || item.date == null ? 'Date unknown' : formatDate(item.date),
          ),
        ],
      ),
      trailing: item.verification == 'verified'
          ? Icon(Icons.verified, size: 18, color: theme.colorScheme.primary)
          : null,
      isThreeLine: item.subtitle != null && item.subtitle!.isNotEmpty,
      onTap: () {
        if (item.kind == 'document') {
          context.push('/documents/${item.id}');
        }
      },
    );
  }
}