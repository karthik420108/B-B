import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/medication_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

/// Prescription -> reminder review flow.
///
/// Reads candidate medications from a prescription document, shows exactly
/// where each came from and which fields are uncertain, and **never** creates a
/// schedule until the patient edits (if needed) and explicitly confirms.
class PrescriptionExtractScreen extends ConsumerStatefulWidget {
  const PrescriptionExtractScreen({super.key, this.documentId});
  final String? documentId;

  @override
  ConsumerState<PrescriptionExtractScreen> createState() => _PrescriptionExtractScreenState();
}

class _PrescriptionExtractScreenState extends ConsumerState<PrescriptionExtractScreen> {
  String? _documentId;
  PrescriptionExtraction? _extraction;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _documentId = widget.documentId;
    if (_documentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _extract());
    }
  }

  Future<void> _extract() async {
    final id = _documentId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _extraction = null;
    });
    try {
      final result = await ref.read(medicationRepositoryProvider).extractFromDocument(id);
      if (mounted) setState(() => _extraction = result);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(ExtractionCandidate candidate) async {
    final extraction = _extraction;
    if (extraction == null) return;
    final medication = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _CandidateForm(candidate: candidate),
    );
    if (medication == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(medicationRepositoryProvider).confirmExtraction(
            documentId: extraction.documentId,
            medication: medication,
            snippet: candidate.sourceSnippet,
            clientRequestId: 'rx-${DateTime.now().microsecondsSinceEpoch}',
          );
      ref.invalidate(schedulesProvider);
      ref.invalidate(todayDosesProvider);
      ref.invalidate(upcomingDosesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder created from your prescription.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add from prescription')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_busy && _extraction == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ErrorPanel(error: _error!, onRetry: _documentId != null ? _extract : null),
          const SizedBox(height: 12),
          if (_documentId != null)
            OutlinedButton(
              onPressed: () => setState(() {
                _documentId = null;
                _error = null;
              }),
              child: const Text('Choose a different document'),
            ),
        ],
      );
    }
    if (_extraction != null) return _resultView(_extraction!);
    return _documentPicker();
  }

  Widget _documentPicker() {
    final docsAsync = ref.watch(documentsProvider);
    return AsyncView<List<DocumentSummary>>(
      value: docsAsync,
      onRetry: () => ref.refresh(documentsProvider.future),
      onReady: (docs) {
        final prescriptions = docs.where((d) => d.category == 'prescription').toList();
        if (prescriptions.isEmpty) {
          return ListView(
            children: [
              const SizedBox(height: 60),
              EmptyState(
                icon: Icons.medication_outlined,
                title: 'No prescriptions found',
                subtitle: 'Upload a prescription document first, then extract the medicines from it.',
                action: FilledButton.icon(
                  onPressed: () => context.push('/documents/upload'),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload a prescription'),
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Choose a prescription to read. Extraction is a suggestion only — you review and confirm every medicine.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final doc in prescriptions) ...[
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(categoryIcon(doc.category)),
                  ),
                  title: Text(doc.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatDate(doc.eventDate)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    setState(() => _documentId = doc.id);
                    _extract();
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _resultView(PrescriptionExtraction extraction) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(extraction.documentName,
                          style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Read from: ${extraction.textSource}'
                  '${extraction.ocrConfidence != null ? ' (OCR confidence ${(extraction.ocrConfidence! * 100).round()}%)' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(extraction.note, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Detected medicines', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (extraction.candidates.isEmpty)
          const EmptyState(
            icon: Icons.search_off,
            title: 'Nothing detected',
            subtitle: 'No medication information was detected. You can add the medicine manually.',
          )
        else
          for (final candidate in extraction.candidates) ...[
            _CandidateCard(candidate: candidate, onReview: _busy ? null : () => _review(candidate)),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => setState(() => _extraction = null),
          child: const Text('Choose a different document'),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.onReview});
  final ExtractionCandidate candidate;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = [candidate.strength, candidate.dose, candidate.frequency, candidate.route]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' • ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(candidate.name, style: theme.textTheme.titleSmall)),
                if (candidate.confidence > 0)
                  Text('${(candidate.confidence * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
            if (parts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(parts, style: theme.textTheme.bodySmall),
            ],
            if (candidate.hasUncertainty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final field in candidate.uncertainFields)
                    Chip(
                      avatar: const Icon(Icons.help_outline, size: 14),
                      label: Text('$field unclear'),
                      labelStyle: theme.textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: theme.colorScheme.tertiary.withValues(alpha: 0.5)),
                    ),
                ],
              ),
            ],
            if (candidate.sourceSnippet != null && candidate.sourceSnippet!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('“${candidate.sourceSnippet}”',
                    style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onReview,
                icon: const Icon(Icons.edit_note_outlined, size: 18),
                label: const Text('Review & add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prefilled editor for one candidate. Returns the medication map only when the
/// patient confirms; the source document id is bound at call time.
class _CandidateForm extends StatefulWidget {
  const _CandidateForm({required this.candidate});
  final ExtractionCandidate candidate;

  @override
  State<_CandidateForm> createState() => _CandidateFormState();
}

class _CandidateFormState extends State<_CandidateForm> {
  late final TextEditingController _name = TextEditingController(text: widget.candidate.name);
  late final TextEditingController _strength = TextEditingController(text: widget.candidate.strength ?? '');
  late final TextEditingController _dose = TextEditingController(text: widget.candidate.dose ?? '');
  late String _frequency = _frequencyFromLabel(widget.candidate.frequency);
  late List<String> _times = _timesFor(_frequency);
  DateTime _startDate = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    super.dispose();
  }

  static String _frequencyFromLabel(String? label) {
    final v = (label ?? '').toLowerCase();
    if (v.contains('three')) return 'three_times_daily';
    if (v.contains('twice') || v.contains('two')) return 'twice_daily';
    if (v.contains('once') || v.contains('daily') || v.contains('day')) return 'once_daily';
    return 'custom';
  }

  static List<String> _timesFor(String frequency) {
    switch (frequency) {
      case 'twice_daily':
        return ['08:00', '20:00'];
      case 'three_times_daily':
        return ['08:00', '13:00', '20:00'];
      case 'once_daily':
      default:
        return ['08:00'];
    }
  }

  void _onFrequencyChanged(String? value) {
    if (value == null) return;
    setState(() {
      _frequency = value;
      final required = frequencyRequiredTimes(value);
      if (required != null) {
        final defaults = _timesFor(value);
        _times = [for (var i = 0; i < required; i++) i < _times.length ? _times[i] : defaults[i % defaults.length]];
        _times = _times.toSet().toList();
      }
    });
  }

  Future<void> _pickTime(int index) async {
    final parts = _times[index].split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    setState(() => _times[index] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  void _confirm() {
    final validation = validateScheduleDraft(
      name: _name.text,
      times: _times,
      frequency: _frequency,
      startDate: _startDate,
      endDate: null,
    );
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    Navigator.of(context).pop({
      'name': _name.text.trim(),
      if (_strength.text.trim().isNotEmpty) 'strength': _strength.text.trim(),
      if (_dose.text.trim().isNotEmpty) 'doseInstructions': _dose.text.trim(),
      'frequency': _frequency,
      'reminderTimes': _times,
      'startDate': toIsoDate(_startDate),
      'sourceType': 'PRESCRIPTION',
    });
  }

  @override
  Widget build(BuildContext context) {
    final required = frequencyRequiredTimes(_frequency);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm the medicine', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Fill in anything marked unclear. This is saved only for you, and only after you confirm.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Medicine name *')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _strength, decoration: const InputDecoration(labelText: 'Strength'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _dose, decoration: const InputDecoration(labelText: 'Dose'))),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: medicationFrequencies
                  .map((f) => DropdownMenuItem(value: f, child: Text(frequencyLabel(f))))
                  .toList(),
              onChanged: _onFrequencyChanged,
            ),
            const SizedBox(height: 12),
            Text('Reminder times', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _times.length; i++)
                  InputChip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text(formatTime12h(_times[i])),
                    onPressed: () => _pickTime(i),
                    onDeleted: required == null && _times.length > 1
                        ? () => setState(() => _times = [..._times]..removeAt(i))
                        : null,
                  ),
                if (required == null && _times.length < 8)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    onPressed: () => setState(() => _times = [..._times, '12:00']),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _startDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Start date'),
                child: Text(formatDate(_startDate)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: _confirm, child: const Text('Confirm & add')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
