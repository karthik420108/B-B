import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../providers/providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phone = TextEditingController();
  final _dob = TextEditingController();
  final _license = TextEditingController();
  final _specialty = TextEditingController();
  final _clinic = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  /// UI-only role choice. The server validates it against the account on every request.
  String _role = 'patient';
  String _bloodGroup = 'unknown';
  String _sex = 'unknown';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _phone.dispose();
    _dob.dispose();
    _license.dispose();
    _specialty.dispose();
    _clinic.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 30)),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) {
      _dob.text = picked.toIso8601String().split('T').first;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final patientProfile = _role == 'patient'
          ? {
              'dateOfBirth': _dob.text.isEmpty ? null : _dob.text,
              'bloodGroup': _bloodGroup,
              'sex': _sex,
            }
          : null;
      final doctorProfile = _role == 'doctor'
          ? {
              'licenseNumber': _license.text.trim(),
              'specialty': _specialty.text.trim(),
              'clinicName': _clinic.text.trim(),
            }
          : null;
      await ref.read(authProvider.notifier).register(
            email: _email.text,
            password: _password.text,
            name: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            role: _role,
            doctorProfile: doctorProfile,
            patientProfile: patientProfile,
          );
      if (!mounted) return;
      // The server decides the real role; route accordingly.
      final state = ref.read(authProvider);
      context.go(state.isDoctor ? '/doctor' : '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your personal health wallet', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'patient', label: Text('Patient'), icon: Icon(Icons.person_outline)),
                    ButtonSegment(value: 'doctor', label: Text('Doctor'), icon: Icon(Icons.medical_services_outlined)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _role == 'doctor'
                      ? 'Doctor accounts require verification before they can access patient records.'
                      : 'Patients manage and share their own health records.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure)),
                    helperText: 'At least 8 characters.',
                  ),
                  validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 20),
                // Role-specific fields.
                if (_role == 'patient') ...[
                  Text('Basic health details', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Optional, but helps doctors understand your records. You can edit these later in Profile.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _dob,
                    readOnly: true,
                    onTap: _pickDob,
                    decoration: const InputDecoration(
                      labelText: 'Date of birth',
                      prefixIcon: Icon(Icons.cake_outlined),
                      hintText: 'Select date',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      final d = DateTime.tryParse(v);
                      if (d == null || d.isAfter(DateTime.now())) return 'Enter a valid date';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _bloodGroup,
                    decoration: const InputDecoration(labelText: 'Blood group', prefixIcon: Icon(Icons.bloodtype_outlined)),
                    items: const [
                      DropdownMenuItem(value: 'A+', child: Text('A+')),
                      DropdownMenuItem(value: 'A-', child: Text('A-')),
                      DropdownMenuItem(value: 'B+', child: Text('B+')),
                      DropdownMenuItem(value: 'B-', child: Text('B-')),
                      DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                      DropdownMenuItem(value: 'AB-', child: Text('AB-')),
                      DropdownMenuItem(value: 'O+', child: Text('O+')),
                      DropdownMenuItem(value: 'O-', child: Text('O-')),
                      DropdownMenuItem(value: 'unknown', child: Text('Prefer not to say')),
                    ],
                    onChanged: (v) => setState(() => _bloodGroup = v ?? 'unknown'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _sex,
                    decoration: const InputDecoration(labelText: 'Biological sex', prefixIcon: Icon(Icons.transgender_outlined)),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'intersex', child: Text('Intersex')),
                      DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                      DropdownMenuItem(value: 'prefer_not_to_say', child: Text('Prefer not to say')),
                    ],
                    onChanged: (v) => setState(() => _sex = v ?? 'unknown'),
                  ),
                ] else ...[
                  Text('Professional details', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Your identity will be verified before you can access patient records.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _license,
                    decoration: const InputDecoration(
                      labelText: 'License / registration number',
                      prefixIcon: Icon(Icons.badge_outlined),
                      helperText: 'e.g. state medical council registration',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your license number' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _specialty,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Specialty', prefixIcon: Icon(Icons.local_hospital_outlined), hintText: 'e.g. Cardiology'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _clinic,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Clinic / institution', prefixIcon: Icon(Icons.apartment_outlined), hintText: 'Optional'),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create account'),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account?', style: theme.textTheme.bodySmall),
                    TextButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'By creating an account you agree that demo data used here is fictional and for demonstration only.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
