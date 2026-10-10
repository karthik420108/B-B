import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

final shareDetailProvider = FutureProvider.family<ShareDetail, String>((ref, id) {
  return ref.watch(shareRepositoryProvider).get(id);
});

class ShareDetailScreen extends ConsumerWidget {
  const ShareDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(shareDetailProvider(id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Share details')),
      body: AsyncView<ShareDetail>(
        value: detail,
        onRetry: () => ref.invalidate(shareDetailProvider(id)),
        onReady: (s) {
          final active = s.status == 'active' && s.isActive;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: active
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : theme.colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(active ? Icons.link : Icons.link_off, color: active ? theme.colorScheme.primary : theme.colorScheme.outline),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              active ? 'Active' : titleCase(s.status),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      MetaLine(
                        provider: s.doctorName,
                        extra: s.doctorEmail,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Created ${formatDateTime(s.createdAt)}  •  Expires ${s.expiresAt == null ? 'never' : formatDateTime(s.expiresAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text('${s.documentCount} documents  •  ${s.accessCount} access${s.accessCount == 1 ? '' : 'es'}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                icon: Icons.tune_outlined,
                title: 'Permissions',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: s.permissions.entries
                      .map((e) => Chip(
                            avatar: Icon(e.value == true ? Icons.check : Icons.close, size: 16),
                            label: Text(titleCase(e.key)),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                icon: Icons.receipt_long_outlined,
                title: 'Access log',
                subtitle: 'Every access is recorded server-side.',
                child: s.accessLog.isEmpty
                    ? Text('No accesses yet.', style: theme.textTheme.bodySmall)
                    : Column(
                        children: [
                          for (final a in s.accessLog)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(_actionIcon(a.action), size: 20),
                              title: Text(titleCase(a.action)),
                              subtitle: Text(a.detail ?? ''),
                              trailing: Text(formatDateTime(a.at), style: theme.textTheme.labelSmall),
                            ),
                        ],
                      ),
              ),
              if (active) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
                  onPressed: () => _confirmRevoke(context, ref),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Revoke access now'),
                ),
                const SizedBox(height: 8),
                Text('Revoking stops all further access server-side immediately. Already-downloaded copies in the doctor’s possession cannot be technically recalled.', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ],
          );
        },
      ),
    );
  }

  IconData _actionIcon(String action) => switch (action) {
        'share.claimed' => Icons.link_outlined,
        'share.viewed' => Icons.visibility_outlined,
        'share.downloaded' => Icons.download_outlined,
        'share.revoked' => Icons.link_off_outlined,
        _ => Icons.history,
      };

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Revoke this share?'),
        content: const Text(
          'The doctor will no longer be able to open or refresh this view. Access history is preserved for the audit log.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(shareRepositoryProvider).revoke(id);
      ref.invalidate(shareDetailProvider(id));
      ref.invalidate(sharesProvider);
      ref.invalidate(dashboardProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access revoked.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}