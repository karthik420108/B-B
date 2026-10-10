import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

class HealthHubScreen extends ConsumerWidget {
  const HealthHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final safety = dashboard.value?.medicationAlerts;
    final alertCount =
        (safety == null ? 0 : safety.interactions.length + safety.duplicates.length);
    final duplicateCount = ref.watch(duplicateTestsProvider(180)).value?.findings.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Health hub')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dashboardProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            HubTile(
              icon: Icons.person_outline,
              title: 'My profile',
              subtitle: 'Personal details & medical information',
              onTap: () => context.push('/profile'),
            ),
            HubTile(
              icon: Icons.summarize_outlined,
              title: 'My summary',
              subtitle: 'Grounded source-linked care summary',
              onTap: () => context.push('/summary'),
            ),
            HubTile(
              icon: Icons.medication_outlined,
              title: 'Medications',
              subtitle: 'Active & past medications',
              onTap: () => context.push('/medications'),
            ),
            HubTile(
              icon: Icons.qr_code_2_outlined,
              title: 'Share with a doctor',
              subtitle: 'Time-limited, revocable access via QR / token',
              onTap: () => context.push('/share'),
            ),
            HubTile(
              icon: Icons.emergency_outlined,
              title: 'Emergency card',
              subtitle: 'Critical details for emergency care',
              onTap: () => context.push('/emergency'),
            ),
            HubTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Theme, sign out & app information',
              onTap: () => context.push('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}