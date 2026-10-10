import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

final emergencyCardProvider = FutureProvider<EmergencyCardData?>((ref) {
  return ref.watch(patientRepositoryProvider).getEmergencyCard().then((map) {
    if (map.isEmpty) return null;
    return EmergencyCardData.fromJson(map);
  });
});

class EmergencyCardScreen extends ConsumerStatefulWidget {
  const EmergencyCardScreen({super.key});

  @override
  ConsumerState<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends ConsumerState<EmergencyCardScreen> {
  bool _busy = false;

  static const _keys = [
    ('enabled', 'Enable emergency card'),
    ('shareConditions', 'Share conditions'),
    ('shareAllergies', 'Share allergies'),
    ('shareMedications', 'Share medications'),
    ('shareEmergencyContact', 'Share emergency contact'),
    ('shareRecentResults', 'Share recent results'),
  ];

  Future<void> _save(EmergencyCardData data, String key, bool value) async {
    setState(() => _busy = true);
    try {
      final next = {...data.settings, key: value};
      await ref.read(patientRepositoryProvider).updateEmergencyCard(next);
      ref.invalidate(emergencyCardProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = ref.watch(emergencyCardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency card')),
      body: AsyncView<EmergencyCardData?>(
        value: card,
        onRetry: () => ref.invalidate(emergencyCardProvider),
        onReady: (data) {
          if (data == null) {
            return const EmptyState(
              icon: Icons.emergency_outlined,
              title: 'Profile not set up yet',
              subtitle: 'Add your medical profile and the emergency card will be available here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(emergencyCardProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.emergency, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Emergency card', style: theme.textTheme.titleMedium)),
                            Switch(
                              value: data.enabled,
                              onChanged: _busy ? null : (v) => _save(data, 'enabled', v),
                            ),
                          ],
                        ),
                        Text(
                          'When enabled, the sections below are compiled for emergency responders from verified records only — on your terms. No permanent public QR code is generated; a card is only ever shared through your explicit, time-limited share.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  icon: Icons.tune_outlined,
                  title: 'What to include',
                  child: Column(
                    children: [
                      for (final (key, label) in _keys.skip(1))
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(label),
                          value: data.settings[key] == true,
                          onChanged: _busy ? null : (v) => _save(data, key, v),
                        ),
                    ],
                  ),
                ),
                if (data.bloodGroup != null) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.water_drop_outlined,
                    title: 'Blood group',
                    child: Text(data.bloodGroup!, style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
                if (data.emergencyContacts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.contacts_outlined,
                    title: 'Emergency contacts',
                    child: Column(
                      children: [
                        for (final c in data.emergencyContacts)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(c.name),
                            subtitle: Text([c.relation, c.phone].whereType<String>().join(' • ')),
                          ),
                      ],
                    ),
                  ),
                ],
                if (data.conditions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Conditions',
                    child: Column(
                      children: [
                        for (final c in data.conditions)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(child: Text(c.name)),
                                if (c.verification == 'verified')
                                  Icon(Icons.verified, size: 16, color: theme.colorScheme.primary),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (data.allergies.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.report_problem_outlined,
                    title: 'Allergies',
                    child: Column(
                      children: [
                        for (final a in data.allergies)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(a.substance),
                            subtitle: Text([a.severity, a.reaction].whereType<String>().join(' • ')),
                          ),
                      ],
                    ),
                  ),
                ],
                if (data.medications.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.medication_outlined,
                    title: 'Current medications',
                    child: Column(
                      children: [
                        for (final m in data.medications)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(m.name),
                            subtitle: Text([m.strength, m.frequency].whereType<String>().join(' • ')),
                          ),
                      ],
                    ),
                  ),
                ],
                if (data.recentResults.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.science_outlined,
                    title: 'Recent results',
                    child: Column(
                      children: [
                        for (final o in data.recentResults)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(o.testName),
                            subtitle: Text(formatDate(o.date)),
                            trailing: Text(o.displayValue),
                          ),
                      ],
                    ),
                  ),
                ],
                if (data.missing.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    icon: Icons.help_center_outlined,
                    title: 'What is missing',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final m in data.missing)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• $m', style: theme.textTheme.bodySmall),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(data.disclaimer, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          );
        },
      ),
    );
  }
}