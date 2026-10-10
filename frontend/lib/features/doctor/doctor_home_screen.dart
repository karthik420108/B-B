import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class DoctorHomeScreen extends ConsumerStatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  ConsumerState<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends ConsumerState<DoctorHomeScreen> {
  final _token = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _inspectAndClaim() async {
    final raw = _token.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the share token.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(doctorRepositoryProvider);
      final info = await repo.inspect(raw);
      if (!mounted) return;
      final status = (info['status'] ?? 'unknown').toString();
      if (status != 'active') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('This token is not active: ${titleCase(status)}.')));
        return;
      }
      final proceed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Share found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${titleCase(status)}'),
              if (info['label'] != null) Text('Label: ${info['label']}'),
              if (info['expiresAt'] != null)
                Text('Expires: ${formatDateTime(DateTime.tryParse(info['expiresAt'].toString()))}'),
              const SizedBox(height: 8),
              const Text('Claiming links this share to your account. Access is logged for the patient and is revocable by them at any time.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Claim & view')),
          ],
        ),
      );
      if (proceed != true) return;
      await repo.claim(raw);
      if (!mounted) return;
      context.go('/doctor/$raw');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The share lists do not carry the secret token or claim status, so a
  /// doctor re-enters the token they already claimed to open the bundle.
  Future<void> _showBundleHint(Map<String, dynamic> raw) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Authorized bundle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient: ${raw['patientName'] ?? 'Patient'}'),
            if (raw['label'] != null) Text('Label: ${raw['label']}'),
            const SizedBox(height: 8),
            const Text(
              'To open the records, enter the secret token you claimed (shown when you first claimed this share) in the field above. Tokens are never displayed again after they are claimed.',
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Got it'))],
      ),
    );
  }

  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final shares = ref.watch(doctorSharesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor view'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(child: Text((auth.user?.name ?? 'D').substring(0, 1).toUpperCase())),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(auth.user?.name ?? '', style: theme.textTheme.titleMedium),
                            Text('Access is authorized per share and fully audited.', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Enter a patient’s share token', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Scan the QR a patient shows you, or type the secret token here.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _token,
                  decoration: const InputDecoration(
                    labelText: 'Share token',
                    hintText: 'e.g. HW-abc-123…',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  onSubmitted: (_) => _inspectAndClaim(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : _inspectAndClaim,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Claim'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Shares authorized to you', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AsyncView<List<Map<String, dynamic>>>(
            value: shares,
            onRetry: () => ref.invalidate(doctorSharesProvider),
            onReady: (items) {
              if (items.isEmpty) {
                return const Text('No active shares for your account yet.');
              }
              return Card(
                child: Column(
                  children: [
                    for (final raw in items)
                      ListTile(
                        title: Text(raw['patientName']?.toString() ?? (raw['label']?.toString() ?? 'Records bundle')),
                        subtitle: Text(
                          [
                            raw['label']?.toString(),
                            raw['expiresAt'] == null ? null : 'expires ${formatDateTime(DateTime.tryParse(raw['expiresAt'].toString()))}',
                            '${raw['accessCount'] ?? 0} access${(raw['accessCount'] ?? 0) == 1 ? '' : 'es'}',
                            '${raw['documentCount'] ?? 0} documents',
                          ].whereType<String>().join('  •  '),
                        ),
                        isThreeLine: true,
                        onTap: () => _showBundleHint(raw),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'You only ever see what the patient consented to for this share. Every open, download and revoke is logged.',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}