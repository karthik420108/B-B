import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/medication_utils.dart';
import '../../providers/providers.dart';

/// Manual medication entry. Validates locally, shows a confirmation summary,
/// and only then creates the schedule (which generates the dose occurrences).
class AddMedicationScreen extends ConsumerStatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  ConsumerState<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

const List<String> _defaultTimes = ['08:00', '13:00', '20:00'];
const List<String> _routes = ['oral', 'topical', 'inhalation', 'injection', 'other'];

class _AddMedicationScreenState extends ConsumerState<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();
  final _notes = TextEditingController();

  String _frequency = 'once_daily';
  String? _route;
  List<String> _times = ['08:00'];
  final Set<int> _weekdays = {};
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    _instructions.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onFrequencyChanged(String? value) {
    if (value == null) return;
    setState(() {
      _frequency = value;
      final required = frequencyRequiredTimes(value);
      if (required != null) {
        final next = <String>[];
        for (var i = 0; i < required; i++) {
          next.add(i < _times.length && isValidTime(_times[i]) ? _times[i] : _defaultTimes[i % _defaultTimes.length]);
        }
        _times = next.toSet().toList();
      }
    });
  }

  Future<void> _pickTime(int index) async {
    final parts = _times[index].split(':');
    final initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _times[index] = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _startDate : (_endDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  String? _validate() {
    final base = validateScheduleDraft(
      name: _name.text,
      times: _times,
      frequency: _frequency,
      startDate: _startDate,
      endDate: _endDate,
    );
    if (base != null) return base;
    return null;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final message = _validate();
    if (message != null) {
      setState(() => _error = message);
      return;
    }

    final confirmed = await _confirmSummary();
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(medicationRepositoryProvider).createSchedule({
        'name': _name.text.trim(),
        if (_strength.text.trim().isNotEmpty) 'strength': _strength.text.trim(),
        if (_dose.text.trim().isNotEmpty) 'doseInstructions': _dose.text.trim(),
        if (_route != null) 'route': _route,
        'frequency': _frequency,
        'reminderTimes': _times,
        if (_weekdays.isNotEmpty) 'weekdays': _weekdays.toList()..sort(),
        'startDate': toIsoDate(_startDate),
        if (_endDate != null) 'endDate': toIsoDate(_endDate!),
        if (_instructions.text.trim().isNotEmpty) 'instructions': _instructions.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'sourceType': 'MANUAL',
        'clientRequestId': 'manual-${DateTime.now().microsecondsSinceEpoch}',
      });
      ref.invalidate(schedulesProvider);
      ref.invalidate(todayDosesProvider);
      ref.invalidate(upcomingDosesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication reminder saved.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmSummary() {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm medication'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Check these details before saving. Nothing is scheduled until you confirm.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              _SummaryRow(label: 'Medicine', value: _name.text.trim()),
              if (_strength.text.trim().isNotEmpty) _SummaryRow(label: 'Strength', value: _strength.text.trim()),
              if (_dose.text.trim().isNotEmpty) _SummaryRow(label: 'Dose', value: _dose.text.trim()),
              if (_route != null) _SummaryRow(label: 'Route', value: titleCase(_route!)),
              _SummaryRow(label: 'Frequency', value: frequencyLabel(_frequency)),
              _SummaryRow(label: 'Reminders', value: scheduleTimesLabel(_times)),
              _SummaryRow(label: 'Days', value: weekdaysLabel(_weekdays.toList())),
              _SummaryRow(label: 'Start', value: formatDate(_startDate)),
              if (_endDate != null) _SummaryRow(label: 'End', value: formatDate(_endDate)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Edit')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm & save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final required = frequencyRequiredTimes(_frequency);
    return Scaffold(
      appBar: AppBar(title: const Text('Add medication')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Medicine name *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Medicine name is required.' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _strength,
                    decoration: const InputDecoration(labelText: 'Strength', hintText: 'e.g. 500 mg'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _dose,
                    decoration: const InputDecoration(labelText: 'Dose', hintText: 'e.g. 1 tablet'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _route,
              decoration: const InputDecoration(labelText: 'Route'),
              items: _routes.map((r) => DropdownMenuItem(value: r, child: Text(titleCase(r)))).toList(),
              onChanged: (v) => setState(() => _route = v),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Reminder times', style: Theme.of(context).textTheme.titleSmall),
                ),
                if (required == null)
                  TextButton.icon(
                    onPressed: _times.length >= 8
                        ? null
                        : () => setState(() => _times = [..._times, '12:00']),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
              ],
            ),
            if (required != null)
              Text('${frequencyLabel(_frequency)} uses exactly $required time${required == 1 ? '' : 's'}.',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
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
              ],
            ),
            const SizedBox(height: 16),
            Text('Days', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                    label: Text(const ['S', 'M', 'T', 'W', 'T', 'F', 'S'][d]),
                    selected: _weekdays.contains(d),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _weekdays.add(d);
                      } else {
                        _weekdays.remove(d);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _weekdays.isEmpty ? 'Every day' : weekdaysLabel(_weekdays.toList()),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _DateField(label: 'Start date', date: _startDate, onTap: () => _pickDate(start: true))),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'End date (optional)',
                    date: _endDate,
                    onTap: () => _pickDate(start: false),
                    onClear: _endDate == null ? null : () => setState(() => _endDate = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructions,
              decoration: const InputDecoration(labelText: 'Instructions', hintText: 'e.g. take with food'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Saving…' : 'Review & save'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap, this.onClear});
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: onClear) : const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(date == null ? 'Not set' : formatDate(date)),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
