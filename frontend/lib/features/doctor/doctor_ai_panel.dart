import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

/// A single rendered turn in the doctor AI transcript.
class _ChatItem {
  _ChatItem.doctor(this.question) : answer = null, restored = null;

  _ChatItem.assistant(AiAnswer this.answer) : question = answer.question, restored = null;

  _ChatItem.restoredAssistant(ConversationMessage this.restored)
      : question = restored.content,
        answer = null;

  final String question;
  final AiAnswer? answer;
  final ConversationMessage? restored;
}

/// Patient-history-aware AI assistant for one authorized share.
///
/// The panel is deliberately scoped to a single [shareIdOrToken]: the backend
/// re-validates the grant on every request, so losing access mid-conversation
/// fails the next call rather than trusting this widget's state.
class DoctorAiPanel extends ConsumerStatefulWidget {
  const DoctorAiPanel({super.key, required this.shareIdOrToken, required this.bundle});

  final String shareIdOrToken;
  final DoctorBundle bundle;

  @override
  ConsumerState<DoctorAiPanel> createState() => _DoctorAiPanelState();
}

class _DoctorAiPanelState extends ConsumerState<DoctorAiPanel> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatItem> _items = [];
  final Set<String> _focusedDocIds = {};

  bool _busy = false;
  bool _loadingHistory = true;
  String? _error;
  String? _notice;

  /// Suggested questions covering the common clinical asks.
  static const _suggestions = [
    'Summarize this patient\'s medical history.',
    'How have the patient\'s blood sugar levels changed over time?',
    'Compare the latest blood report with previous reports.',
    'What medications has this patient previously been prescribed?',
    'Are there any documented allergies or medication-related concerns?',
    'What significant changes can you identify in the patient\'s reports?',
    'Are there any recurring abnormalities across the available reports?',
    'Summarize the patient\'s previous diagnoses and hospital visits.',
    'What relevant historical information should I consider before assessing the current complaint?',
    'Show me the timeline of the patient\'s important medical events.',
  ];

  @override
  void initState() {
    super.initState();
    _restoreConversation();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restoreConversation() async {
    setState(() => _loadingHistory = true);
    try {
      final messages = await ref
          .read(doctorRepositoryProvider)
          .doctorConversation(widget.shareIdOrToken);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(messages.map((m) => m.isDoctor
              ? _ChatItem.doctor(m.content)
              : _ChatItem.restoredAssistant(m)));
        _loadingHistory = false;
      });
    } catch (_) {
      // A failed restore is not fatal - the doctor can simply ask again.
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _ask(String raw) async {
    final question = raw.trim();
    if (question.isEmpty || _busy) return;
    _controller.clear();
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _items.add(_ChatItem.doctor(question));
    });
    _scrollToBottom();

    try {
      final answer = await ref.read(doctorRepositoryProvider).askDoctorAi(
            widget.shareIdOrToken,
            question,
            documentIds: _focusedDocIds.isEmpty ? null : _focusedDocIds.toList(),
          );
      if (!mounted) return;
      setState(() {
        _items.add(_ChatItem.assistant(answer));
        _busy = false;
        if (answer.coverage != null && answer.coverage!.hasUnreadable) {
          _notice = '${answer.coverage!.unreadable.length} file(s) could not be analyzed '
              'because no readable text could be recovered. Answers are based only on '
              'the ${answer.coverage!.documentsWithText} readable file(s).';
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _busy = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _resetConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
            'This removes the stored question-and-answer thread for this patient on this device and on the server. '
            'The patient\'s records are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(doctorRepositoryProvider).clearDoctorConversation(widget.shareIdOrToken);
      if (!mounted) return;
      setState(() {
        _items.clear();
        _error = null;
        _notice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversation cleared.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  void _toggleFocus(String docId) {
    setState(() {
      if (!_focusedDocIds.remove(docId)) _focusedDocIds.add(docId);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _openCitation(Citation c) {
    if (c.documentId != null) {
      final match = widget.bundle.documents
          .where((d) => d.id == c.documentId)
          .firstOrNull;
      if (match != null) {
        _viewDocument(match);
        return;
      }
    }
    if (c.documentName != null) {
      final match = widget.bundle.documents
          .where((d) => d.originalName.toLowerCase() == c.documentName!.toLowerCase())
          .firstOrNull;
      if (match != null) {
        _viewDocument(match);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Source: ${c.label ?? c.documentName ?? 'Record'} (${formatDate(c.date)})')),
    );
  }

  Future<void> _viewDocument(DocumentSummary doc) async {
    await showDialog<void>(
      context: context,
      builder: (c) => DoctorDocumentDialog(doc: doc, token: widget.shareIdOrToken),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patientName = widget.bundle.patientName;
    final docs = widget.bundle.documents;
    final unreadableIds = <String>{};

    return SectionCard(
      icon: Icons.auto_awesome,
      title: 'AI Medical History Assistant',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Who is being analyzed ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: Text(patientName.isEmpty ? '?' : patientName[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Analyzing records for: $patientName',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${docs.length} file(s) in scope • server re-checks access on every question',
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Clear conversation',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  onPressed: _busy ? null : _resetConversation,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- Files available to ask about ---
          if (docs.isNotEmpty) ...[
            Text('Files available under this share (tap to focus the AI):',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in docs)
                  FilterChip(
                    selected: _focusedDocIds.contains(d.id),
                    onSelected: _busy ? null : (_) => _toggleFocus(d.id),
                    avatar: Icon(
                      unreadableIds.contains(d.id)
                          ? Icons.broken_image_outlined
                          : categoryIcon(d.category),
                      size: 14,
                    ),
                    label: Text(
                      '${d.originalName}${d.eventDate != null ? ' • ${formatDate(d.eventDate)}' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
            if (_focusedDocIds.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Next question will be limited to ${_focusedDocIds.length} selected file(s).',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
            const SizedBox(height: 12),
          ],

          // --- Suggested questions ---
          Text('Suggested questions',
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 11)),
                  onPressed: _busy ? null : () => _ask(s),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // --- Transcript ---
          if (_loadingHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty && !_busy)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(Icons.forum_outlined, size: 34, color: theme.colorScheme.outline),
                  const SizedBox(height: 8),
                  Text(
                    'Ask a question about this patient\'s medical history.\n'
                    'Answers are grounded in the ${docs.length} file(s) you are authorized to see.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else ...[
            for (final item in _items) _buildItem(theme, item),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text('Reviewing authorized records…', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],

          if (_notice != null) ...[
            const SizedBox(height: 10),
            _Banner(
              color: Colors.amber.shade100,
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.orange,
              text: _notice!,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            _Banner(
              color: theme.colorScheme.errorContainer,
              icon: Icons.error_outline,
              iconColor: theme.colorScheme.onErrorContainer,
              text: _error!,
            ),
          ],
          const SizedBox(height: 14),

          // --- Input ---
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 3,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    hintText: 'Ask a follow-up about this patient…',
                    prefixIcon: Icon(Icons.chat_outlined),
                  ),
                  onSubmitted: _busy ? null : (v) => _ask(v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : () => _ask(_controller.text),
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Ask'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Clinical decision support only. Every answer cites the records it came from - verify before acting.',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(ThemeData theme, _ChatItem item) {
    if (item.answer != null || item.restored != null) {
      return _AssistantBubble(
        answer: item.answer,
        restored: item.restored,
        onOpenCitation: item.answer != null
            ? (c) => _openCitation(c)
            : null,
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(item.question, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

/// Renders one assistant answer: body, missing-information state, citations.
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.answer, required this.restored, this.onOpenCitation});

  final AiAnswer? answer;
  final ConversationMessage? restored;
  final void Function(Citation)? onOpenCitation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = answer?.answer ?? restored?.content ?? '';
    final citations = answer?.citations ?? const <Citation>[];
    final missing = answer?.uncertainty?.missing ?? false;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('AI Assistant',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              if (answer != null) ...[
                const Spacer(),
                Text(answer!.provider,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (missing)
            _Banner(
              color: Colors.blue.shade50,
              icon: Icons.info_outline,
              iconColor: Colors.blue.shade800,
              text: text,
            )
          else
            SelectableText(text, style: theme.textTheme.bodyMedium),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Sources (tap to open the document):',
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in citations)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 13),
                    label: Text(
                      '${c.documentName ?? c.label ?? 'Record'}${c.date != null ? ' (${formatDate(c.date)})' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: onOpenCitation == null ? null : () => onOpenCitation!(c),
                  ),
              ],
            ),
          ],
          if (answer?.disclaimer != null) ...[
            const SizedBox(height: 8),
            Text(answer!.disclaimer!,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.iconColor, required this.text});
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

/// Document preview dialog used when opening an AI citation.
class DoctorDocumentDialog extends ConsumerStatefulWidget {
  const DoctorDocumentDialog({super.key, required this.doc, required this.token});
  final DocumentSummary doc;
  final String token;

  @override
  ConsumerState<DoctorDocumentDialog> createState() => _DoctorDocumentDialogState();
}

class _DoctorDocumentDialogState extends ConsumerState<DoctorDocumentDialog> {
  bool _loading = false;
  List<int>? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await ref
          .read(doctorRepositoryProvider)
          .downloadDocumentBytes(widget.token, widget.doc.id);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isText = widget.doc.mimeType == 'text/plain' || widget.doc.originalName.endsWith('.txt');
    final isImage = widget.doc.mimeType.startsWith('image/');

    return AlertDialog(
      title: Row(
        children: [
          Icon(categoryIcon(widget.doc.category)),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(widget.doc.originalName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Category: ${titleCase(widget.doc.category)}'),
              if (widget.doc.providerName != null) Text('Provider: ${widget.doc.providerName}'),
              if (widget.doc.eventDate != null) Text('Date: ${formatDate(widget.doc.eventDate)}'),
              Text('Extraction status: ${titleCase(widget.doc.extractionStatus)}'),
              const Divider(height: 20),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error))
              else if (_bytes != null && isText)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(utf8.decode(_bytes!, allowMalformed: true)),
                )
              else if (_bytes != null && isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(Uint8List.fromList(_bytes!), fit: BoxFit.contain),
                )
              else if (_bytes != null)
                Text('Document retrieved (${_bytes!.length} bytes).'),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
