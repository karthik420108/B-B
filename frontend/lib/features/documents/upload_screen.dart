import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../providers/providers.dart';
import '../../services/documents_repository.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  static const _categories = ['laboratory', 'prescription', 'imaging', 'consultation_note', 'discharge_summary', 'vaccination', 'other'];

  String? _fileName;
  Uint8List? _bytes;
  int _fileSize = 0;
  String _category = 'laboratory';
  String? _providerName;
  DateTime? _eventDate;
  bool _busy = false;
  String? _error;
  bool _extracting = false;

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: DocumentsRepository.allowedExtensions,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final size = await file.length() ?? bytes.length;
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _bytes = bytes;
        _fileSize = size;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open the file picker: $e');
    }
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    final fileName = _fileName;
    if (bytes == null || fileName == null) {
      setState(() => _error = 'Choose a file first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _extracting = true;
    });
    try {
      final repo = ref.read(documentsRepositoryProvider);
      final data = await repo.upload(
        bytes: bytes,
        filename: fileName,
        category: _category,
        providerName: _providerName,
        eventDate: _eventDate?.toIso8601String().split('T').first,
      );
      final doc = data['document'] as Map<String, dynamic>? ?? const {};
      final id = doc['id']?.toString() ?? '';
      // Extraction runs inline; refresh the list now so the new doc shows up.
      ref.invalidate(documentsProvider);
      if (!mounted) return;
      final extraction = data['extraction'];
      final extracted = proposedRecordCount(extraction);
      final extractionError = extractionFailure(extraction);
      setState(() {
        _extracting = false;
        _busy = false;
      });
      if (extractionError != null) {
        // The upload itself succeeded; extraction can be retried later.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document uploaded, but extraction failed: $extractionError')),
        );
        if (id.isNotEmpty) context.push('/documents/$id');
      } else if (extracted > 0) {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (c) => _SuccessSheet(id: id, count: extracted),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document uploaded${id.isEmpty ? '' : ' — no structured data extracted'}.' )),
        );
        if (id.isNotEmpty) context.push('/documents/$id');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _extracting = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Upload a record')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('The wallet reads the text with local OCR / PDF extraction and proposes structured records. You stay in control: everything is reviewed before it is saved.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            Card(
              child: InkWell(
                onTap: _busy ? null : _pickFile,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        _bytes == null ? Icons.add_circle_outline : Icons.insert_drive_file_outlined,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _fileName ?? 'Choose a PDF, image or text file',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_bytes != null && _fileSize > 0) ...[
                        const SizedBox(height: 4),
                        Text(formatBytes(_fileSize), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.label_outline)),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(titleCase(c)))).toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 14),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Provider / facility (optional)', prefixIcon: Icon(Icons.local_hospital_outlined)),
              onChanged: (v) => setState(() => _providerName = v),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _eventDate ?? DateTime.now(),
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _eventDate = picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(_eventDate == null ? 'Date of the visit (optional)' : 'Visit date: ${formatDate(_eventDate)}'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _upload,
              child: _busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        const Text('Extracting…'),
                      ],
                    )
                  : const Text('Upload & extract'),
            ),
            if (_extracting) ...[
              const SizedBox(height: 12),
              Text('Running local OCR/text extraction. Larger documents take longer.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            Text(
              'Supported: PDF, PNG, JPG, WEBP, TIFF, BMP, TXT. Images are scanned with OCR so even a photo of a lab result works.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessSheet extends StatelessWidget {
  const _SuccessSheet({required this.id, required this.count});
  final String id;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Extraction complete', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('$count records were proposed. Review and verify them now to make them part of your file.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.go('/documents/$id/review'),
              child: const Text('Review & verify'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/documents/$id'),
              child: const Text('View document'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.pop(), child: const Text('Done')),
        ],
      ),
    );
  }
}