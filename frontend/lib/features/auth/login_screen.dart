import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../providers/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  /// UI-only role choice. The backend never trusts it — it returns the account's
  /// actual role and we show a message if the selection does not match.
  String _selectedRole = 'patient';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authProvider.notifier);
      await auth.login(email: _email.text, password: _password.text);
      final state = ref.read(authProvider);
      if (!mounted) return;
      // The server decides the real role. If the user picked the wrong side,
      // say so explicitly instead of silently landing on the other dashboard.
      if (_selectedRole == 'doctor' && !state.isDoctor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This email is registered as a patient account. You will enter the patient view.')),
        );
      } else if (_selectedRole == 'patient' && state.isDoctor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This email is registered as a doctor account. You will enter the doctor view.')),
        );
      }
      if (!mounted) return;
      if (state.isDoctor) {
        if (state.isDoctorPendingVerification) {
          context.go('/doctor/pending');
        } else {
          context.go('/doctor');
        }
      } else {
        context.go('/home');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo(String role) {
    _selectedRole = role;
    _email.text = role == 'patient' ? 'patient@demo.health' : 'doctor@demo.health';
    _password.text = 'DemoPass123!';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.health_and_safety_outlined, size: 34),
                    ),
                    const SizedBox(height: 16),
                    Text('Welcome back', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Sign in to your health wallet', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                      validator: (v) => (v == null || v.trim().isEmpty || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure)),
                      ),
                      validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?')),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : () => context.push('/register'),
                      child: const Text('Create an account'),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Signing in as', style: theme.textTheme.labelMedium),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'patient', label: Text('Patient'), icon: Icon(Icons.person_outline)),
                                ButtonSegment(value: 'doctor', label: Text('Doctor'), icon: Icon(Icons.medical_services_outlined)),
                              ],
                              selected: {_selectedRole},
                              onSelectionChanged: (s) => setState(() => _selectedRole = s.first),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _selectedRole == 'doctor'
                                  ? 'Doctor view is only for verified doctor accounts.'
                                  : 'Patients manage and share their own health records.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                            ),
                            const Divider(height: 24),
                            Text('Demo accounts (seeded)', style: theme.textTheme.labelMedium),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ActionChip(
                                  avatar: const Icon(Icons.person_outline, size: 16),
                                  label: const Text('Patient demo'),
                                  onPressed: () => _fillDemo('patient'),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.medical_services_outlined, size: 16),
                                  label: const Text('Doctor demo'),
                                  onPressed: () => _fillDemo('doctor'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Password: DemoPass123!', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}