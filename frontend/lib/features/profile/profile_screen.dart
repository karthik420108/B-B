import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            icon: Icons.person_outline,
            title: auth.user?.name ?? 'Patient',
            subtitle: auth.user?.email,
            child: AsyncView<PatientProfile>(
              value: profile,
              onRetry: () => ref.refresh(profileProvider.future),
              onReady: (p) {
                final rows = <(String, String)>[
                  ('Date of birth', p.dateOfBirth == null ? 'Not set' : formatDate(p.dateOfBirth)),
                  ('Sex', p.sex == null ? 'Not set' : titleCase(p.sex!)),
                  ('Blood group', p.bloodGroup ?? 'Not set'),
                  ('Address', p.address ?? 'Not set'),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 130, child: Text(r.$1, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))),
                            Expanded(child: Text(r.$2, style: theme.textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                    if (p.chronicConditions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Chronic conditions', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: p.chronicConditions.map((c) => Chip(label: Text(c))).toList()),
                    ],
                    if (p.allergies.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Allergies', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: p.allergies
                            .map((a) => Chip(
                                  avatar: Icon(a.severity == 'severe' ? Icons.warning_amber_outlined : Icons.info_outline, size: 16),
                                  label: Text(a.substance),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => context.push('/profile/medical'),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit medical profile'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/emergency'),
                          icon: const Icon(Icons.emergency_outlined),
                          label: const Text('Emergency card'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Settings & sign out'),
          ),
        ],
      ),
    );
  }
}