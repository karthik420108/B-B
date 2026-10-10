import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/api_config.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await ref.read(authProvider.notifier).logout();
    if (mounted) {
      context.go('/login');
      setState(() => _busy = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your wallet stays on this device; you can sign back in with the same account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) await _signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeProvider);
    final aiInfo = ref.watch(aiProviderInfo);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            icon: Icons.palette_outlined,
            title: 'Theme',
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) => ref.read(themeProvider.notifier).setMode(s.first),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            icon: Icons.security_outlined,
            title: 'AI & privacy',
            child: aiInfo.maybeWhen(
              data: (info) {
                final offline = info['allowExternalDataTransfer'] != true;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(offline ? Icons.offline_bolt_outlined : Icons.cloud_outlined, color: offline ? theme.colorScheme.primary : theme.colorScheme.tertiary),
                      title: Text(offline ? 'Offline AI (no external data transfer)' : 'Cloud AI enabled'),
                      subtitle: Text('Provider: ${info['provider'] ?? 'local'}${info['model'] != null ? '  •  ${info['model']}' : ''}'),
                    ),
                    const SizedBox(height: 6),
                    Text('The assistant only ever answers from your own records with citations.', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('Server: ${ApiConfig.baseUrl}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                );
              },
              orElse: () => Text('Loading AI status…', style: theme.textTheme.bodySmall),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            icon: Icons.info_outline,
            title: 'About',
            child: Text(
              'AI-Powered Personal Health Wallet — a demonstration build. Medication alerts come from a small curated dataset and are informational only. The system does not diagnose, prescribe, or replace professional care.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            icon: Icons.account_circle_outlined,
            title: 'Signed in as',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(auth.user?.name ?? '', style: theme.textTheme.bodyMedium),
                Text(auth.user?.email ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: _busy ? null : _confirmSignOut,
            icon: const Icon(Icons.logout),
            label: Text(_busy ? 'Signing out…' : 'Sign out'),
          ),
        ],
      ),
    );
  }
}