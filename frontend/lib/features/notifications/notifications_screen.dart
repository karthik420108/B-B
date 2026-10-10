import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  return ref.watch(patientRepositoryProvider).getNotifications();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              try {
                await ref.read(patientRepositoryProvider).markAllRead();
                ref.invalidate(notificationsProvider);
              } catch (_) {}
            },
            icon: const Icon(Icons.done_all_outlined),
            label: const Text('Mark all read'),
          ),
        ],
      ),
      body: AsyncView<List<AppNotification>>(
        value: notifications,
        onRetry: () => ref.invalidate(notificationsProvider),
        onReady: (items) => items.isEmpty
            ? const EmptyState(icon: Icons.notifications_none, title: 'No notifications', subtitle: 'Activity related to your wallet will appear here.')
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final n = items[i];
                    final unread = !n.read;
                    return Card(
                      color: unread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
                      child: ListTile(
                        leading: Icon(
                          unread ? Icons.circle : Icons.notifications_outlined,
                          size: unread ? 12 : 22,
                          color: unread ? theme.colorScheme.primary : theme.colorScheme.outline,
                        ),
                        title: Text(n.title, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.body),
                            if (n.createdAt != null)
                              Text(formatDateTime(n.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                          ],
                        ),
                        isThreeLine: true,
                        onTap: unread
                            ? () async {
                                await ref.read(patientRepositoryProvider).markNotificationRead(n.id);
                                ref.invalidate(notificationsProvider);
                              }
                            : null,
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}