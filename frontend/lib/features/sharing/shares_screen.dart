import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class SharesScreen extends ConsumerWidget {
  const SharesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(sharesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Share with a doctor')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/share/create'),
        icon: const Icon(Icons.add_link_outlined),
        label: const Text('New share'),
      ),
      body: AsyncView<List<ShareGrant>>(
        value: shares,
        onRetry: () => ref.refresh(sharesProvider.future),
        onReady: (items) => RefreshIndicator(
          onRefresh: () async => ref.refresh(sharesProvider.future),
          child: items.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 60),
                    EmptyState(
                      icon: Icons.qr_code_2_outlined,
                      title: 'No shares yet',
                      subtitle: 'Create a time-limited, revocable share so a doctor can view exactly the records you consent to.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final s = items[i];
                    final color = s.status == 'active' ? theme.colorScheme.primary : theme.colorScheme.outline;
                    return Card(
                      child: ListTile(
                        onTap: () => context.push('/share/${s.id}'),
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          foregroundColor: color,
                          child: Icon(s.status == 'active' ? Icons.link : Icons.link_off),
                        ),
                        title: Text(s.label ?? 'Records bundle'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s.doctorName != null)
                              Text('For: ${s.doctorName!}${s.doctorEmail != null ? ' (${s.doctorEmail})' : ''}'),
                            Text(
                              '${s.expiresAt == null ? 'No expiry' : 'Expires ${formatDateTime(s.expiresAt)}'}  •  ${s.accessCount} access${s.accessCount == 1 ? '' : 'es'}',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (s.isActive && s.tokenPreview != null)
                              Text('Token: ${s.tokenPreview}', style: theme.textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.5)),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          titleCase(s.status),
                          style: TextStyle(color: color, fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}