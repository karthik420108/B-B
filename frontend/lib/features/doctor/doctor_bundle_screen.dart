import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';

final doctorBundleProvider = FutureProvider.family<DoctorBundle, String>((ref, token) {
  return ref.watch(doctorRepositoryProvider).bundle(token);
});

class DoctorBundleScreen extends ConsumerWidget {
  const DoctorBundleScreen({super.key, required this.token});
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(doctorBundleProvider(token));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient records'),
        actions: [
          IconButton(
            tooltip: 'Refresh (re-checks authorization server-side)',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(doctorBundleProvider(token).future),
          ),
        ],
      ),
      body: bundle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _AccessDenied(error: e, onRetry: () => ref.refresh(doctorBundleProvider(token).future)),
        data: (b) => RefView(bundle: b, token: token),
      ),
    );
  }
}

/// Dedicated denied/expired/revoked presentation (kept honest about why).
class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAuth = error is ApiException && (error as ApiException).isAuthorizationFailure;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isAuth ? Icons.lock_outline : Icons.link_off, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(isAuth ? 'Access denied' : 'Access no longer available', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              isAuth
                  ? 'This token is invalid, expired, revoked, or belongs to a different account. The server verifies authorization on every request — no records are shown without it.'
                  : friendlyError(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Check again')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.go('/doctor'), child: const Text('Back to doctor view')),
          ],
        ),
      ),
    );
  }
}

class RefView extends StatelessWidget {
  const RefView({super.key, required this.bundle, required this.token});
  final DoctorBundle bundle;
  final String token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = bundle.permissions;

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(radius: 22, child: Text(bundle.patientName.substring(0, 1).toUpperCase())),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bundle.patientName, style: theme.textTheme.titleMedium),
                            if (bundle.patientDateOfBirth != null)
                              Text('DOB: ${formatDate(bundle.patientDateOfBirth)}', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Viewing only the sections the patient authorized for this share.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (permissions['observations'] == true && bundle.observations.isNotEmpty)
            _SectionCard(
              icon: Icons.science_outlined,
              title: 'Lab results (${bundle.observations.length})',
              child: Column(
                children: [
                  for (final o in bundle.observations)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.testName),
                      subtitle: Text('${o.providerName ?? '—'}  •  ${formatDate(o.date)}', style: theme.textTheme.bodySmall),
                      trailing: Text(o.displayValue, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          if (permissions['medications'] == true && bundle.medications.isNotEmpty)
            _SectionCard(
              icon: Icons.medication_outlined,
              title: 'Medications (${bundle.medications.length})',
              child: Column(
                children: [
                  for (final m in bundle.medications)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.name),
                      subtitle: Text([m.strength, m.frequency, m.route].whereType<String>().join(' • '), style: theme.textTheme.bodySmall),
                      trailing: Icon(m.isActive ? Icons.circle : Icons.circle_outlined, size: 12, color: theme.colorScheme.primary),
                    ),
                ],
              ),
            ),
          if (permissions['allergies'] == true && bundle.allergies.isNotEmpty)
            _SectionCard(
              icon: Icons.report_problem_outlined,
              title: 'Allergies (${bundle.allergies.length})',
              child: Column(
                children: [
                  for (final a in bundle.allergies)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.substance),
                      subtitle: Text([a.severity, a.reaction].whereType<String>().join(' • '), style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          if (permissions['timeline'] == true && bundle.conditions.isNotEmpty)
            _SectionCard(
              icon: Icons.health_and_safety_outlined,
              title: 'Conditions (${bundle.conditions.length})',
              child: Column(
                children: [
                  for (final c in bundle.conditions)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name),
                      subtitle: Text(c.status ?? '', style: theme.textTheme.bodySmall),
                      trailing: Text(formatDate(c.onsetDate), style: theme.textTheme.labelSmall),
                    ),
                ],
              ),
            ),
          if (permissions['duplicateAlerts'] == true && bundle.duplicateAlerts.isNotEmpty)
            _SectionCard(
              icon: Icons.content_copy_outlined,
              title: 'Duplicate-test alerts (${bundle.duplicateAlerts.length})',
              child: Column(
                children: [
                  for (final f in bundle.duplicateAlerts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${f.normalizedTestName}: ${f.reason}', style: theme.textTheme.bodySmall)),
                          if (f.gapDays != null) Text('${f.gapDays}d apart', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (bundle.medicationAlerts != null &&
              (bundle.medicationAlerts!.interactions.isNotEmpty || bundle.medicationAlerts!.duplicates.isNotEmpty))
            _SectionCard(
              icon: Icons.warning_amber_outlined,
              title: 'Medication safety alerts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final i in bundle.medicationAlerts!.interactions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• ${i.title} — ${i.effect}', style: theme.textTheme.bodySmall),
                    ),
                  for (final d in bundle.medicationAlerts!.duplicates)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• Duplicate: ${d.normalizedTestName} — ${d.recommendation}', style: theme.textTheme.bodySmall),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Alerts come from a curated dataset and require clinical review; they do not change treatment.',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          if (permissions['summary'] == true && bundle.documents.isNotEmpty)
            _SectionCard(
              icon: Icons.folder_outlined,
              title: 'Documents (${bundle.documents.length})',
              child: Column(
                children: [
                  for (final d in bundle.documents)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(formatDate(d.eventDate), style: theme.textTheme.bodySmall),
                      trailing: Text(d.extractionStatus, style: theme.textTheme.labelSmall),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Authorized access only. This view can be revoked by the patient at any time; each request is re-checked against the current share status.',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(icon: icon, title: title, child: child),
    );
  }
}