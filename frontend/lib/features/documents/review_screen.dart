import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';
import 'document_detail_screen.dart' show documentDetailProvider;

/// Review-and-verify workflow for records proposed by OCR/AI extraction.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

String _isoDate(DateTime? d) => d == null ? '' : d.toIso8601String().split('T').first;

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final Set<String> _handled = {}; // "kind:id" entries already reviewed
  bool _busy = false;

  void _mark(String key) => setState(() => _handled.add(key));

  Future<void> _submit({
    required String kind,
    required String recordId,
    required String verification,
    Map<String, dynamic>? corrections,
  }) async {
    setState(() => _busy = true);
    try {
      await ref.read(documentsRepositoryProvider).verifyRecord(
            kind: kind,
            id: recordId,
            verification: verification,
            corrections: corrections,
          );
      _mark('$kind:$recordId');
      ref.invalidate(documentDetailProvider(widget.id));
      ref.invalidate(timelineProvider);
      ref.invalidate(observationsProvider);
      ref.invalidate(medicationsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(verification == 'verified' ? 'Verified & saved.' : 'Record rejected.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(documentDetailProvider(widget.id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Review & verify')),
      body: AsyncView<DocumentDetail>(
        value: detail,
        onRetry: () => ref.invalidate(documentDetailProvider(widget.id)),
        onReady: (d) {
          final x = d.extracted ?? ExtractedBundle();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Each record below was proposed from your document. Correct any field and verify, or reject records that don’t belong. Nothing is saved until you confirm it.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _ReviewGroup(
                title: 'Lab results',
                icon: Icons.science_outlined,
                busy: _busy,
                entries: x.observations.map((o) => _ReviewEntry(
                      key_: 'observation:${o.id}',
                      id: o.id,
                      kind: 'observation',
                      title: o.testName,
                      subtitle: '${o.displayValue}  •  ${o.referenceRange ?? 'range n/a'}',
                      handled: _handled.contains('observation:${o.id}'),
                      initialValues: {
                        'testName': o.testName,
                        'value': o.value.isFinite ? o.value.toString() : (o.valueString ?? ''),
                        'unit': o.unit ?? '',
                        'referenceRange': o.referenceRange ?? '',
                        'date': _isoDate(o.date),
                      },
                      fields: const [
                        (key: 'testName', label: 'Test name'),
                        (key: 'value', label: 'Value'),
                        (key: 'unit', label: 'Unit'),
                        (key: 'referenceRange', label: 'Reference range'),
                        (key: 'date', label: 'Date (YYYY-MM-DD)'),
                      ],
                    )).toList(),
                onVerify: (e, c) => _submit(kind: 'observation', recordId: e.id, verification: 'verified', corrections: c),
                onReject: (e, _) => _submit(kind: 'observation', recordId: e.id, verification: 'rejected'),
              ),
              _ReviewGroup(
                title: 'Medications',
                icon: Icons.medication_outlined,
                busy: _busy,
                entries: x.medications.map((m) => _ReviewEntry(
                      key_: 'medication:${m.id}',
                      id: m.id,
                      kind: 'medication',
                      title: m.name,
                      subtitle: [m.strength, m.frequency, m.route].whereType<String>().join(' • '),
                      handled: _handled.contains('medication:${m.id}'),
                      initialValues: {
                        'name': m.name,
                        'strength': m.strength ?? '',
                        'frequency': m.frequency ?? '',
                        'form': m.form ?? '',
                        'route': m.route ?? '',
                        'startDate': _isoDate(m.startDate),
                        'endDate': _isoDate(m.endDate),
                      },
                      fields: const [
                        (key: 'name', label: 'Name'),
                        (key: 'strength', label: 'Strength'),
                        (key: 'frequency', label: 'Frequency'),
                        (key: 'form', label: 'Form'),
                        (key: 'route', label: 'Route'),
                        (key: 'startDate', label: 'Start date (YYYY-MM-DD)'),
                        (key: 'endDate', label: 'End date (YYYY-MM-DD)'),
                      ],
                    )).toList(),
                onVerify: (e, c) => _submit(kind: 'medication', recordId: e.id, verification: 'verified', corrections: c),
                onReject: (e, _) => _submit(kind: 'medication', recordId: e.id, verification: 'rejected'),
              ),
              _ReviewGroup(
                title: 'Conditions',
                icon: Icons.health_and_safety_outlined,
                busy: _busy,
                entries: x.conditions.map((c) => _ReviewEntry(
                      key_: 'condition:${c.id}',
                      id: c.id,
                      kind: 'condition',
                      title: c.name,
                      subtitle: [c.status, formatDate(c.onsetDate)].whereType<String>().where((s) => s.isNotEmpty && s != 'Date unknown').join(' • '),
                      handled: _handled.contains('condition:${c.id}'),
                      initialValues: {
                        'name': c.name,
                        'status': c.status ?? '',
                        'onsetDate': _isoDate(c.onsetDate),
                      },
                      fields: const [
                        (key: 'name', label: 'Name'),
                        (key: 'status', label: 'Status'),
                        (key: 'onsetDate', label: 'Onset date (YYYY-MM-DD)'),
                      ],
                    )).toList(),
                onVerify: (e, c) => _submit(kind: 'condition', recordId: e.id, verification: 'verified', corrections: c),
                onReject: (e, _) => _submit(kind: 'condition', recordId: e.id, verification: 'rejected'),
              ),
              _ReviewGroup(
                title: 'Allergies',
                icon: Icons.report_problem_outlined,
                busy: _busy,
                entries: x.allergies.map((a) => _ReviewEntry(
                      key_: 'allergy:${a.id}',
                      id: a.id,
                      kind: 'allergy',
                      title: a.substance,
                      subtitle: [a.severity, a.reaction].whereType<String>().join(' • '),
                      handled: _handled.contains('allergy:${a.id}'),
                      initialValues: {
                        'substance': a.substance,
                        'reaction': a.reaction ?? '',
                        'severity': a.severity ?? '',
                      },
                      fields: const [
                        (key: 'substance', label: 'Substance'),
                        (key: 'reaction', label: 'Reaction'),
                        (key: 'severity', label: 'Severity'),
                      ],
                    )).toList(),
                onVerify: (e, c) => _submit(kind: 'allergy', recordId: e.id, verification: 'verified', corrections: c),
                onReject: (e, _) => _submit(kind: 'allergy', recordId: e.id, verification: 'rejected'),
              ),
              _ReviewGroup(
                title: 'Visits',
                icon: Icons.event_note_outlined,
                busy: _busy,
                entries: x.encounters.map((e) => _ReviewEntry(
                      key_: 'encounter:${e.id}',
                      id: e.id,
                      kind: 'encounter',
                      title: e.type,
                      subtitle: [e.providerName, formatDate(e.date)].whereType<String>().where((s) => s.isNotEmpty && s != 'Date unknown').join(' • '),
                      handled: _handled.contains('encounter:${e.id}'),
                      initialValues: {
                        'type': e.type,
                        'providerName': e.providerName ?? '',
                        'date': _isoDate(e.date),
                        'diagnosis': e.diagnosis.join(', '),
                      },
                      fields: const [
                        (key: 'type', label: 'Type'),
                        (key: 'providerName', label: 'Provider'),
                        (key: 'date', label: 'Date (YYYY-MM-DD)'),
                        (key: 'diagnosis', label: 'Diagnosis (comma separated)'),
                      ],
                    )).toList(),
                onVerify: (e, c) => _submit(kind: 'encounter', recordId: e.id, verification: 'verified', corrections: c),
                onReject: (e, _) => _submit(kind: 'encounter', recordId: e.id, verification: 'rejected'),
              ),
            ],
          );
        },
      ),
    );
  }
}

typedef _RecordAction = Future<void> Function(_ReviewEntry entry, Map<String, dynamic>? corrections);

class _ReviewGroup extends StatelessWidget {
  const _ReviewGroup({
    required this.title,
    required this.icon,
    required this.entries,
    required this.onVerify,
    required this.onReject,
    required this.busy,
  });

  final String title;
  final IconData icon;
  final List<_ReviewEntry> entries;
  final _RecordAction onVerify;
  final _RecordAction onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
        icon: icon,
        title: title,
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(),
              _ReviewItemTile(entry: entries[i], busy: busy, onVerify: onVerify, onReject: onReject),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewItemTile extends StatelessWidget {
  const _ReviewItemTile({required this.entry, required this.busy, required this.onVerify, required this.onReject});

  final _ReviewEntry entry;
  final bool busy;
  final _RecordAction onVerify;
  final _RecordAction onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entry.handled) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.task_alt, color: theme.colorScheme.primary),
        title: Text(entry.title, style: const TextStyle(decoration: TextDecoration.lineThrough)),
        subtitle: Text('Reviewed', style: theme.textTheme.bodySmall),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (entry.subtitle.isNotEmpty)
            Text(entry.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : () async {
                  final corrections = await _editDialog(context, entry);
                  if (corrections != null) await onVerify(entry, corrections);
                },
                icon: const Icon(Icons.edit_note_outlined, size: 18),
                label: const Text('Correct & verify'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => onReject(entry, null),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<Map<String, dynamic>?> _editDialog(BuildContext context, _ReviewEntry entry) async {
  final controllers = <String, TextEditingController>{};
  final initial = entry.initialValues;
  for (final field in entry.fields) {
    controllers[field.key] = TextEditingController(text: initial[field.key] ?? '');
  }
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Correct details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final field in entry.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  controller: controllers[field.key],
                  decoration: InputDecoration(labelText: field.label, isDense: true),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final corrections = <String, dynamic>{};
            for (final field in entry.fields) {
              final value = controllers[field.key]!.text.trim();
              if (value.isNotEmpty) corrections[field.key] = value;
            }
            Navigator.pop(c, corrections);
          },
          child: const Text('Save & verify'),
        ),
      ],
    ),
  );
  for (final controller in controllers.values) {
    controller.dispose();
  }
  return result;
}

class _ReviewEntry {
  const _ReviewEntry({
    required this.key_,
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.handled,
    required this.fields,
    this.initialValues = const {},
  });

  final String key_;
  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final bool handled;
  final List<({String key, String label})> fields;
  final Map<String, dynamic> initialValues;
}