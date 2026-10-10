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
      if (_selectedRole == 'doctor' && !state.isDoctor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This email is registered as a patient account.')),
        );
      } else if (_selectedRole == 'patient' && state.isDoctor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This email is registered as a doctor account.')),
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

  Future<void> _handleGoogleSignIn() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google Sign-In requires backend configuration and missing platform dependencies.'))
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'meet health.\nyour medical\ncompanion',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 36,
                        height: 1.1,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 48),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _handleGoogleSignIn,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('or', style: theme.textTheme.bodyMedium),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                      validator: (v) => (v == null || v.trim().isEmpty || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _obscure = !_obscure)),
                      ),
                      validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign in'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.push('/forgot-password'),
                      child: Text('Forgot password?', style: TextStyle(color: theme.colorScheme.onSurface)),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => context.push('/register'),
                      child: Text('Create an account', style: TextStyle(color: theme.colorScheme.onSurface)),
                    ),
                    const SizedBox(height: 32),
                    Text('Demo accounts (seeded)', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.person_outline_rounded, size: 16),
                          label: const Text('Patient'),
                          onPressed: () => _fillDemo('patient'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.medical_services_outlined, size: 16),
                          label: const Text('Doctor'),
                          onPressed: () => _fillDemo('doctor'),
                        ),
                      ],
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