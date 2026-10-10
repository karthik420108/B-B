import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/formatters.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/qr_scanner_dialog.dart';

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

  Future<void> _inspectAndClaim([String? explicitToken]) async {
    String raw = (explicitToken ?? _token.text).trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter or scan a share token.')));
      return;
    }

    // Clean URL prefixes if a full link was passed
    if (raw.contains('/share/')) {
      final parts = raw.split('/share/');
      if (parts.length > 1 && parts.last.isNotEmpty) {
        raw = parts.last.split('?').first;
      }
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(doctorRepositoryProvider);
      final info = await repo.inspect(raw);
      if (!mounted) return;

      final status = (info['status'] ?? (info['valid'] == true ? 'active' : 'unknown')).toString();
      if (status != 'active') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('This share is not active: ${titleCase(status)}.')),
        );
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
              if (info['patientName'] != null)
                Text('Patient: ${info['patientName']}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
      ref.invalidate(doctorSharesProvider);
      if (!mounted) return;
      context.go('/doctor/$raw');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanPatientQr() async {
    final scanned = await QrScannerDialog.show(
      context,
      title: 'Scan Patient QR Code',
      hint: 'Paste share token or scan QR…',
      expectedType: 'patient-share',
    );
    if (scanned != null && scanned.trim().isNotEmpty) {
      _token.text = scanned.trim();
      await _inspectAndClaim(scanned.trim());
    }
  }

  Future<void> _showMyDoctorQr() async {
    try {
      final info = await ref.read(doctorRepositoryProvider).myDoctorQr();
      if (!mounted) return;
      final payload = jsonEncode(info);

      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.qr_code),
              SizedBox(width: 8),
              Text('My Doctor QR Code'),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: payload,
                    size: 200,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  info['name']?.toString() ?? 'Doctor Profile',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (info['specialty'] != null) Text(info['specialty'].toString()),
                if (info['clinicName'] != null) Text(info['clinicName'].toString()),
                const SizedBox(height: 8),
                Chip(
                  avatar: const Icon(Icons.verified, size: 16, color: Colors.green),
                  label: Text('Status: ${info['verification']}'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Patients can scan this QR to nominate you for record sharing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: payload));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Doctor QR payload copied to clipboard.')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy payload'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
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
        title: const Text('Doctor Dashboard'),
        actions: [
          IconButton(
            tooltip: 'My Doctor QR Code',
            icon: const Icon(Icons.qr_code_2),
            onPressed: _showMyDoctorQr,
          ),
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
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: Text((auth.user?.name ?? 'D').substring(0, 1).toUpperCase()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(auth.user?.name ?? '', style: theme.textTheme.titleMedium),
                                const SizedBox(width: 6),
                                const Icon(Icons.verified, size: 16, color: Colors.blue),
                              ],
                            ),
                            Text('Verified Doctor Account • Access is authorized per share and audited.', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _scanPatientQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan Patient QR'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showMyDoctorQr,
                        icon: const Icon(Icons.qr_code),
                        label: const Text('My Doctor QR'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Enter or scan a patient’s share token', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Scan the QR a patient displays, or type the secret token below.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _token,
                  decoration: const InputDecoration(
                    labelText: 'Share token',
                    hintText: 'e.g. 64-character token…',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  onSubmitted: (_) => _inspectAndClaim(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : () => _inspectAndClaim(),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Claim'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shares authorized to you', style: theme.textTheme.titleSmall),
              IconButton(
                tooltip: 'Refresh shares',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => ref.invalidate(doctorSharesProvider),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AsyncView<List<Map<String, dynamic>>>(
            value: shares,
            onRetry: () => ref.invalidate(doctorSharesProvider),
            onReady: (items) {
              if (items.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.folder_shared_outlined, size: 40, color: theme.colorScheme.outline),
                          const SizedBox(height: 8),
                          const Text('No active shares for your account yet.'),
                          const SizedBox(height: 4),
                          Text('When a patient nominates you or you claim a link, it will appear here.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final raw in items)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          child: const Icon(Icons.person_outline),
                        ),
                        title: Text(raw['patientName']?.toString() ?? (raw['label']?.toString() ?? 'Records bundle')),
                        subtitle: Text(
                          [
                            raw['label']?.toString(),
                            raw['expiresAt'] == null ? null : 'expires ${formatDateTime(DateTime.tryParse(raw['expiresAt'].toString()))}',
                            '${raw['accessCount'] ?? 0} access${(raw['accessCount'] ?? 0) == 1 ? '' : 'es'}',
                            '${raw['documentCount'] ?? 0} documents',
                          ].whereType<String>().join('  •  '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        isThreeLine: true,
                        onTap: () {
                          final shareId = raw['id']?.toString() ?? '';
                          if (shareId.isNotEmpty) {
                            context.go('/doctor/$shareId');
                          }
                        },
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'You only ever see what the patient consented to for this share. Every open, download, and AI query is re-validated and logged server-side.',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}