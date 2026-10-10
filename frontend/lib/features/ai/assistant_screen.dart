import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _busy = false;

  static const _suggestions = [
    'What is my latest HbA1c and how does it compare to before?',
    'Which medications am I currently taking?',
    'Are any of my recent test results outside the normal range?',
    'Summarize my care over the last 6 months.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _busy = true;
      _messages.add(_ChatMessage.user(trimmed));
    });
    _scrollToEnd();
    try {
      final answer = await ref.read(aiRepositoryProvider).ask(trimmed);
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage.ai(answer)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage.aiError(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final aiInfo = ref.watch(aiProviderInfo);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask your health wallet'),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _messages.isEmpty ? null : () => setState(() => _messages.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _EmptyChat(suggestions: _suggestions, onAsk: _ask, aiInfo: aiInfo.value)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (c, i) => _ChatBubble(message: _messages[i]),
                  ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Searching your records…'),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(_controller.text),
                      decoration: InputDecoration(
                        hintText: 'Ask about your records…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _busy ? null : () => _ask(_controller.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.suggestions, required this.onAsk, this.aiInfo});

  final List<String> suggestions;
  final void Function(String) onAsk;
  final Map<String, dynamic>? aiInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = aiInfo;
    final provider = info?['provider'] ?? 'local';
    final model = info?['modelOffline'] ?? info?['model'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ask anything about your own health file.', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Answers are grounded only in your records and include a citation to the source document for every claim. If your file does not contain the answer, the assistant says so instead of guessing.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (info != null) ...[
          const SizedBox(height: 10),
          Chip(
            avatar: Icon(info['allowExternalDataTransfer'] == true ? Icons.cloud_outlined : Icons.offline_bolt_outlined, size: 16),
            label: Text('AI: ${provider.toString().toUpperCase()}${model != null ? '  •  $model' : ''}'),
          ),
        ],
        const SizedBox(height: 24),
        Text('Try asking', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 10),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ActionChip(
              avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis),
              onPressed: () => onAsk(s),
            ),
          ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isUser ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                ),
              ),
              if (message.answer != null) ...[
                const SizedBox(height: 8),
                if (message.answer!.grounded)
                  Row(
                    children: [
                      Icon(Icons.gpp_good_outlined, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('Grounded in your records', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                    ],
                  ),
                if (message.answer!.uncertainty != null && message.answer!.uncertainty!.missing)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Some information is missing from your file: ${message.answer!.uncertainty!.reason ?? ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
                    ),
                  ),
                if (message.answer!.citations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Sources', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  for (final c in message.answer!.citations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${c.documentName ?? c.label ?? 'record'}${c.date != null ? ' (${formatDate(c.date)})' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
                if (message.answer!.disclaimer != null && message.answer!.disclaimer!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(message.answer!.disclaimer!, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage.user(this.text) : role = 'user', answer = null;
  const _ChatMessage.ai(this.answer) : role = 'ai', text = '';
  const _ChatMessage.aiError(String error) : role = 'error', text = error, answer = null;

  final String role;
  final String text;
  final AiAnswer? answer;
}