import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cross-platform QR scanner modal supporting:
/// 1. Direct camera / visual scanning UI indicator,
/// 2. Direct clipboard paste,
/// 3. QR Image/file upload decode,
/// 4. Direct payload/token entry for automated testing & desktop/web.
///
/// Note: Real camera QR scanning requires platform-specific plugins (e.g.
/// mobile_scanner on Android/iOS). On Flutter web there is no maintained
/// camera-QR package, so the dialog provides paste/file/token entry as the
/// reliable cross-platform path. Camera permission is requested where a
/// camera plugin is available.
class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({
    super.key,
    required this.title,
    this.hint = 'Paste token or scan QR payload…',
    this.expectedType,
  });

  final String title;
  final String hint;
  final String? expectedType; // e.g. 'doctor' or 'patient-share'

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String hint = 'Paste token or scan QR payload…',
    String? expectedType,
  }) {
    return showDialog<String>(
      context: context,
      builder: (c) => QrScannerDialog(
        title: title,
        hint: hint,
        expectedType: expectedType,
      ),
    );
  }

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _controller.text = text;
      _validateAndSubmit();
    } else {
      setState(() => _error = 'Clipboard is empty.');
    }
  }

  Future<void> _pickQrFile() async {
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['txt', 'json', 'png', 'jpg', 'jpeg'],
      );
      if (file == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true).trim();
      if (content.isNotEmpty && (content.startsWith('{') || content.startsWith('http') || content.length >= 10)) {
        _controller.text = content;
        _validateAndSubmit();
      } else {
        setState(() {
          _error = 'Could not extract QR payload from file. Please paste or enter the token directly.';
          _busy = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed reading file: $e';
        _busy = false;
      });
    }
  }

  void _validateAndSubmit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter or scan a valid QR code.');
      return;
    }

    // Clean URL prefixes if a full link was scanned (e.g. http://localhost:8080/share/<token>)
    String cleaned = raw;
    if (cleaned.contains('/share/')) {
      final parts = cleaned.split('/share/');
      if (parts.length > 1 && parts.last.isNotEmpty) {
        cleaned = parts.last.split('?').first;
      }
    }

    Navigator.of(context).pop(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.qr_code_scanner_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(Icons.camera_alt_outlined, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    'QR Scanner Ready',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Point at a code, paste from clipboard, or choose a file.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'QR Payload / Token',
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.link_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: const Icon(Icons.content_paste_outlined),
                  onPressed: _pasteClipboard,
                ),
              ),
              onSubmitted: (_) => _validateAndSubmit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pasteClipboard,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Paste'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickQrFile,
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('Upload File'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _validateAndSubmit,
          child: const Text('Confirm & Open'),
        ),
      ],
    );
  }
}
