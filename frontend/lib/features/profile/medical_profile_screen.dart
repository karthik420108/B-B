import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class MedicalProfileScreen extends ConsumerStatefulWidget {
  const MedicalProfileScreen({super.key});

  @override
  ConsumerState<MedicalProfileScreen> createState() => _MedicalProfileScreenState();
}

class _MedicalProfileScreenState extends ConsumerState<MedicalProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dob = TextEditingController();
  final _sex = TextEditingController();
  final _bloodGroup = TextEditingController();
  final _address = TextEditingController();
  final _chronic = TextEditingController();
  final _history = TextEditingController();
  final _medsText = TextEditingController();
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  final _contactRelation = TextEditingController();
  bool _busy = false;
  bool _loaded = false;

  static const _sexes = ['female', 'male', 'intersex', 'unknown', 'prefer_not_to_say'];
  static const _blood = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown'];

  @override
  void dispose() {
    _dob.dispose();
    _sex.dispose();
    _bloodGroup.dispose();
    _address.dispose();
    _chronic.dispose();
    _history.dispose();
    _medsText.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    _contactRelation.dispose();
    super.dispose();
  }

  void _hydrate(PatientProfile p) {
    if (_loaded) return;
    _loaded = true;
    _dob.text = p.dateOfBirth == null ? '' : p.dateOfBirth!.toIso8601String().split('T').first;
    _sex.text = p.sex ?? 'unknown';
    _bloodGroup.text = p.bloodGroup ?? 'unknown';
    _address.text = p.address ?? '';
    _chronic.text = p.chronicConditions.join(', ');
    _history.text = p.medicalHistory.join(', ');
    _medsText.text = p.currentMedicationsText.join(', ');
    if (p.emergencyContacts.isNotEmpty) {
      _contactName.text = p.emergencyContacts.first.name;
      _contactPhone.text = p.emergencyContacts.first.phone ?? '';
      _contactRelation.text = p.emergencyContacts.first.relation ?? '';
    }
    setState(() {});
  }

  List<String> _split(String input) =>
      input.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'dateOfBirth': _dob.text.isEmpty ? null : _dob.text,
        'sex': _sex.text,
        'bloodGroup': _bloodGroup.text,
        if (_address.text.isNotEmpty) 'address': _address.text,
        'chronicConditions': _split(_chronic.text),
        'medicalHistory': _split(_history.text),
        'currentMedicationsText': _split(_medsText.text),
        if (_contactName.text.isNotEmpty)
          'emergencyContacts': [
            {'name': _contactName.text, if (_contactPhone.text.isNotEmpty) 'phone': _contactPhone.text, if (_contactRelation.text.isNotEmpty) 'relation': _contactRelation.text},
          ],
      };
      await ref.read(patientRepositoryProvider).updateProfile(patch);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Medical profile')),
      body: profile.when(
        data: (p) {
          _hydrate(p);
          return _form(context);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load profile: ${friendlyError(e)}')),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Personal & medical details shown to you and, only if you share them, to a doctor you have authorized.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dob,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Date of birth', prefixIcon: Icon(Icons.cake_outlined)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dob.text.isEmpty ? DateTime(1990) : DateTime.tryParse(_dob.text) ?? DateTime(1990),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _dob.text = picked.toIso8601String().split('T').first);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _sex.text,
              decoration: const InputDecoration(labelText: 'Sex', prefixIcon: Icon(Icons.person_outline)),
              items: _sexes.map((s) => DropdownMenuItem(value: s, child: Text(titleCase(s)))).toList(),
              onChanged: (v) => setState(() => _sex.text = v ?? 'unknown'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _bloodGroup.text,
              decoration: const InputDecoration(labelText: 'Blood group', prefixIcon: Icon(Icons.water_drop_outlined)),
              items: _blood.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
              onChanged: (v) => setState(() => _bloodGroup.text = v ?? 'unknown'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.home_outlined)),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            TextFormField(controller: _chronic, decoration: const InputDecoration(labelText: 'Chronic conditions (comma separated)', prefixIcon: Icon(Icons.health_and_safety_outlined))),
            const SizedBox(height: 14),
            TextFormField(controller: _history, decoration: const InputDecoration(labelText: 'Medical history (comma separated)', prefixIcon: Icon(Icons.history_outlined))),
            const SizedBox(height: 14),
            TextFormField(controller: _medsText, decoration: const InputDecoration(labelText: 'Current medications (comma separated)', prefixIcon: Icon(Icons.medication_outlined))),
            const SizedBox(height: 24),
            Text('Emergency contact', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            TextFormField(controller: _contactName, decoration: const InputDecoration(labelText: 'Name', isDense: true)),
            const SizedBox(height: 10),
            TextFormField(controller: _contactPhone, decoration: const InputDecoration(labelText: 'Phone', isDense: true), keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            TextFormField(controller: _contactRelation, decoration: const InputDecoration(labelText: 'Relation (e.g. spouse)', isDense: true)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save profile'),
            ),
          ],
        ),
      ),
    );
  }
}