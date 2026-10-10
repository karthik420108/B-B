import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

final documentDetailProvider = FutureProvider.family<DocumentDetail, String>((ref, id) {
  return ref.watch(documentsRepositoryProvider).get(id);
});

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref.read(documentsRepositoryProvider).retryExtraction(widget.id);
      if (!mounted) return;
      ref.invalidate(documentDetailProvider(widget.id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Re-extraction started.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(documentDetailProvider(widget.id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document'),
        // Explicit back: `AppBar` only implies one when there is history to pop,
        // which is not the case when this screen is reached via `context.go`.
        leading: BackButton(
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              context.go('/documents');
            }
          },
        ),
      ),
      // Explicit way out: this screen is reached with `context.go`, so there is
      // often no history to pop and no implied back arrow.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Done viewing?',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => context.go('/documents'),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to documents'),
            ),
          ],
        ),
      ),
      body: AsyncView<DocumentDetail>(
        value: detail,
        onRetry: () => ref.invalidate(documentDetailProvider(widget.id)),
        onReady: (d) {
          final doc = d.document;
          final extracted = d.extracted ?? ExtractedBundle();
          final totals = [
            ('Obs', extracted.observations.length),
            ('Meds', extracted.medications.length),
            ('Conditions', extracted.conditions.length),
            ('Allergies', extracted.allergies.length),
            ('Visits', extracted.encounters.length),
          ].where((e) => e.$2 > 0).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(documentDetailProvider(widget.id)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  icon: categoryIcon(doc.category),
                  title: doc.originalName,
                  subtitle: '${titleCase(doc.category)}  •  ${formatBigBytes(doc.size)}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MetaLine(
                        provider: doc.providerName,
                        date: doc.eventDate == null ? null : formatDate(doc.eventDate),
                        extra: doc.pageCount > 0 ? '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}' : null,
                      ),
                      const SizedBox(height: 10),
                      Text('Extraction: ${titleCase(doc.extractionStatus)}', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (doc.extractionStatus != 'extracted')
                            OutlinedButton.icon(
                              onPressed: _retrying ? null : _retry,
                              icon: const Icon(Icons.refresh),
                              label: Text(_retrying ? 'Extracting…' : 'Re-extract'),
                            ),
                          if (totals.isNotEmpty)
                            FilledButton.icon(
                              onPressed: () => context.push('/documents/${widget.id}/review'),
                              icon: const Icon(Icons.verified_outlined),
                              label: const Text('Review & verify'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (totals.isEmpty)
                  const SectionCard(
                    icon: Icons.search_outlined,
                    title: 'Nothing extracted yet',
                    child: Text('No structured records were proposed for this document. You can re-extract or view the raw text below.'),
                  )
                else ...[
                  _RecordSection(title: 'Lab results', observations: extracted.observations),
                  _RecordSection(title: 'Medications', medications: extracted.medications),
                  _RecordSection(title: 'Conditions', conditions: extracted.conditions),
                  _RecordSection(title: 'Allergies', allergies: extracted.allergies),
                  _RecordSection(title: 'Visits', encounters: extracted.encounters),
                ],
                if (d.rawText != null && d.rawText!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.subject_outlined,
                    title: 'Raw text used by extraction',
                    child: Text(
                      d.rawText!,
                      maxLines: 12,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RecordSection extends StatelessWidget {
  const _RecordSection({
    required this.title,
    this.observations = const [],
    this.medications = const [],
    this.conditions = const [],
    this.allergies = const [],
    this.encounters = const [],
  });

  final String title;
  final List<Observation> observations;
  final List<Medication> medications;
  final List<ConditionRecord> conditions;
  final List<Allergy> allergies;
  final List<EncounterRecord> encounters;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final o in observations) {
      children.add(_Line(title: o.testName, value: '${o.displayValue}  •  ${o.referenceRange ?? 'range n/a'}'));
    }
    for (final m in medications) {
      children.add(_Line(title: m.name, value: [m.strength, m.frequency, m.route].whereType<String>().join(' • ')));
    }
    for (final c in conditions) {
      children.add(_Line(title: c.name, value: [c.status, formatDate(c.onsetDate)].whereType<String>().where((x) => x.isNotEmpty && x != 'Date unknown').join(' • ')));
    }
    for (final a in allergies) {
      children.add(_Line(title: a.substance, value: [a.severity, a.reaction].whereType<String>().join(' • ')));
    }
    for (final e in encounters) {
      children.add(_Line(title: e.type, value: [e.providerName, formatDate(e.date)].whereType<String>().where((x) => x.isNotEmpty && x != 'Date unknown').join(' • ')));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    final icon = observations.isNotEmpty
        ? Icons.science_outlined
        : medications.isNotEmpty
            ? Icons.medication_outlined
            : conditions.isNotEmpty
                ? Icons.health_and_safety_outlined
                : allergies.isNotEmpty
                    ? Icons.report_problem_outlined
                    : Icons.event_note_outlined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(icon: icon, title: title, child: Column(children: children)),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (value.isNotEmpty)
            Text(value, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}