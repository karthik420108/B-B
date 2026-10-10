import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            tooltip: 'Upload a record',
            icon: const Icon(Icons.add_outlined),
            onPressed: () => context.push('/documents/upload'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/documents/upload'),
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Upload'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(documentsProvider.future),
        child: AsyncView<List<DocumentSummary>>(
          value: docs,
          padding: EdgeInsets.zero,
          onRetry: () => ref.refresh(documentsProvider.future),
          onReady: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.folder_open_outlined,
                title: 'No documents yet',
                subtitle: 'Upload a PDF, image or text file and the wallet will extract structured records from it.',
                action: _UploadHint(),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final d = items[i];
                return _DocumentCard(doc: d, onTap: () => context.push('/documents/${d.id}'));
              },
            );
          },
        ),
      ),
    );
  }
}

class _UploadHint extends StatelessWidget {
  const _UploadHint();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Tap “Upload” below to add your first record.',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc, required this.onTap});
  final DocumentSummary doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (doc.extractionStatus) {
      'extracted' => 'Extracted',
      'processing' => 'Processing…',
      'failed' => 'Extraction failed',
      'needs_review' => 'Needs review',
      _ => 'Pending',
    };
    final statusColor = switch (doc.extractionStatus) {
      'extracted' => theme.colorScheme.primary,
      'failed' => theme.colorScheme.error,
      'processing' => Colors.orange.shade700,
      _ => theme.colorScheme.outline,
    };
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Icon(categoryIcon(doc.category)),
        ),
        title: Text(doc.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MetaLine(
              provider: doc.providerName,
              date: doc.eventDate == null ? null : formatDate(doc.eventDate),
              extra: '${formatBigBytes(doc.size)}  •  ${titleCase(doc.category)}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusLabel, style: theme.textTheme.labelSmall?.copyWith(color: statusColor)),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}