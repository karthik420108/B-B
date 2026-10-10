import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/file_saver.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import 'doctor_bundle_screen.dart';

/// Full-page document viewer and downloader for doctors viewing a patient's consented records.
class DoctorDocumentViewScreen extends ConsumerStatefulWidget {
  const DoctorDocumentViewScreen({
    super.key,
    required this.token,
    required this.docId,
    this.initialDoc,
  });

  final String token;
  final String docId;
  final DocumentSummary? initialDoc;

  @override
  ConsumerState<DoctorDocumentViewScreen> createState() =>
      _DoctorDocumentViewScreenState();
}

class _DoctorDocumentViewScreenState
    extends ConsumerState<DoctorDocumentViewScreen> {
  bool _loading = false;
  List<int>? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDocumentBytes();
  }

  Future<void> _fetchDocumentBytes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bytes = await ref
          .read(doctorRepositoryProvider)
          .downloadDocumentBytes(widget.token, widget.docId);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  DocumentSummary? _resolveDoc() {
    if (widget.initialDoc != null) return widget.initialDoc;
    final bundleAsync = ref.watch(doctorBundleProvider(widget.token));
    return bundleAsync.asData?.value.documents
        .where((d) => d.id == widget.docId)
        .firstOrNull;
  }

  void _download(DocumentSummary doc) {
    if (_bytes == null || _bytes!.isEmpty) return;
    downloadFile(_bytes!, doc.originalName, doc.mimeType);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading ${doc.originalName}…'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openInNewTab(DocumentSummary doc) {
    if (_bytes == null || _bytes!.isEmpty) return;
    openInNewTab(_bytes!, doc.mimeType);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = _resolveDoc() ??
        DocumentSummary(
          id: widget.docId,
          originalName: 'Document ${widget.docId}',
          mimeType: 'application/octet-stream',
          size: 0,
          category: 'other',
          extractionStatus: 'extracted',
        );

    final isText = doc.mimeType == 'text/plain' ||
        doc.originalName.toLowerCase().endsWith('.txt');
    final isImage = doc.mimeType.startsWith('image/');
    final isPdf = doc.mimeType == 'application/pdf' ||
        doc.originalName.toLowerCase().endsWith('.pdf');

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.originalName),
        leading: BackButton(
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              context.go('/doctor/${widget.token}');
            }
          },
        ),
        actions: [
          if (_bytes != null && _bytes!.isNotEmpty) ...[
            FilledButton.icon(
              onPressed: () => _download(doc),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
            const SizedBox(width: 8),
            if (isPdf || isImage)
              IconButton(
                tooltip: 'Open in new browser tab',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openInNewTab(doc),
              ),
          ],
          IconButton(
            tooltip: 'Refresh document',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchDocumentBytes,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Document Metadata Card
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: Icon(categoryIcon(doc.category), size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.originalName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${titleCase(doc.category)} • ${formatBigBytes(doc.size)} • ${doc.mimeType}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            if (doc.providerName != null || doc.eventDate != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                [
                                  if (doc.providerName != null) 'Provider: ${doc.providerName}',
                                  if (doc.eventDate != null) 'Date: ${formatDate(doc.eventDate)}',
                                ].join(' • '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: (_loading || _bytes == null || _bytes!.isEmpty)
                            ? null
                            : () => _download(doc),
                        icon: const Icon(Icons.download),
                        label: const Text('Download Document'),
                      ),
                      if (isPdf || isImage)
                        OutlinedButton.icon(
                          onPressed: (_loading || _bytes == null || _bytes!.isEmpty)
                              ? null
                              : () => _openInNewTab(doc),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open in New Tab'),
                        ),
                      Chip(
                        avatar: const Icon(Icons.security, size: 16),
                        label: const Text('Authorized Scope'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.verified_outlined, size: 16),
                        label: Text('Status: ${titleCase(doc.extractionStatus)}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Main Viewer Container
          if (_loading)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Retrieving secure document from patient records…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load document',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _fetchDocumentBytes,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_bytes != null && _bytes!.isNotEmpty) ...[
            if (isImage)
              _ImageViewerCard(
                bytes: _bytes!,
                doc: doc,
                onDownload: () => _download(doc),
                onOpenNewTab: () => _openInNewTab(doc),
              )
            else if (isText)
              _TextViewerCard(
                bytes: _bytes!,
                doc: doc,
                onDownload: () => _download(doc),
              )
            else if (isPdf)
              _PdfViewerCard(
                bytes: _bytes!,
                doc: doc,
                onDownload: () => _download(doc),
                onOpenNewTab: () => _openInNewTab(doc),
              )
            else
              _GenericFileViewerCard(
                bytes: _bytes!,
                doc: doc,
                onDownload: () => _download(doc),
              ),
          ],

          const SizedBox(height: 20),
          Center(
            child: Text(
              'Authorized doctor access • Every document retrieval and download is verified against patient consent and logged in the audit trail.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Image viewer with zoom and interactive controls.
class _ImageViewerCard extends StatelessWidget {
  const _ImageViewerCard({
    required this.bytes,
    required this.doc,
    required this.onDownload,
    required this.onOpenNewTab,
  });

  final List<int> bytes;
  final DocumentSummary doc;
  final VoidCallback onDownload;
  final VoidCallback onOpenNewTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uint8List = Uint8List.fromList(bytes);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.image_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Image Preview (${formatBigBytes(bytes.length)})',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  'Scroll or pinch to zoom',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 300, maxHeight: 650),
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.04),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.memory(
                    uint8List,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, size: 48, color: theme.colorScheme.error),
                          const SizedBox(height: 8),
                          const Text('Unable to display image preview'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain text document viewer with copy action.
class _TextViewerCard extends StatelessWidget {
  const _TextViewerCard({
    required this.bytes,
    required this.doc,
    required this.onDownload,
  });

  final List<int> bytes;
  final DocumentSummary doc;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textContent = utf8.decode(bytes, allowMalformed: true);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Document Text Content',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: textContent));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Document text copied to clipboard.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy text'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              textContent,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// PDF viewer card with direct open & download actions.
class _PdfViewerCard extends StatelessWidget {
  const _PdfViewerCard({
    required this.bytes,
    required this.doc,
    required this.onDownload,
    required this.onOpenNewTab,
  });

  final List<int> bytes;
  final DocumentSummary doc;
  final VoidCallback onDownload;
  final VoidCallback onOpenNewTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.picture_as_pdf, size: 56, color: Colors.red),
              ),
              const SizedBox(height: 20),
              Text(
                doc.originalName,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'PDF Document • ${formatBigBytes(bytes.length)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download),
                    label: const Text('Download PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenNewTab,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in Browser PDF Viewer'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Click "Open in Browser PDF Viewer" to read with full page navigation, search, and printing.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Generic file card for binary / unrecognized file types.
class _GenericFileViewerCard extends StatelessWidget {
  const _GenericFileViewerCard({
    required this.bytes,
    required this.doc,
    required this.onDownload,
  });

  final List<int> bytes;
  final DocumentSummary doc;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                doc.originalName,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'File type: ${doc.mimeType} • ${formatBigBytes(bytes.length)}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download),
                label: const Text('Download File to View'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
