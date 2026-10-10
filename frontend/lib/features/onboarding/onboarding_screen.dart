import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _PageData(
      icon: Icons.upload_file_outlined,
      title: 'Import your records',
      body: 'Upload PDFs, images or plain text. Real OCR and PDF text extraction run locally — nothing leaves your private wallet.',
    ),
    _PageData(
      icon: Icons.auto_awesome_outlined,
      title: 'AI extracts & you verify',
      body: 'Structured lab results, medications and diagnoses are extracted from your records. Review, correct and verify every field before it becomes part of your file.',
    ),
    _PageData(
      icon: Icons.alarm_outlined,
      title: 'Never miss a dose',
      body: 'Turn a prescription into reminders you control. Confirm every extracted medicine, mark doses taken or skipped, and keep an honest history.',
    ),
    _PageData(
      icon: Icons.shield_outlined,
      title: 'You control sharing',
      body: 'Share a time-limited, revocable bundle with a doctor using a QR code or secret token. Revoke it any time — access is stopped server-side immediately.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _skip,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (c, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p.icon, size: 64, color: theme.colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 32),
                        Text(p.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        Text(p.body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: active ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _page == _pages.length - 1 ? _finish : _next,
                  child: Text(_page == _pages.length - 1 ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() => _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  Future<void> _finish() async {
    await ref.read(onboardingProvider.notifier).complete();
    if (mounted) context.go('/login');
  }

  Future<void> _skip() async {
    await ref.read(onboardingProvider.notifier).complete();
    if (mounted) context.go('/login');
  }
}

class _PageData {
  const _PageData({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}