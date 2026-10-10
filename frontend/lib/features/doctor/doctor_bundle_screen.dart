import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common_widgets.dart';
import 'doctor_ai_panel.dart';

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
        title: const Text('Patient Records'),
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

/// Dedicated denied/expired/revoked presentation.
class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = friendlyError(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_person_outlined, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Access denied or expired', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Check again')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.go('/doctor'), child: const Text('Back to doctor dashboard')),
          ],
        ),
      ),
    );
  }
}

class RefView extends ConsumerStatefulWidget {
  const RefView({super.key, required this.bundle, required this.token});
  final DoctorBundle bundle;
  final String token;

  @override
  ConsumerState<RefView> createState() => _RefViewState();
}

class _RefViewState extends ConsumerState<RefView> {
  void _viewDocument(DocumentSummary doc) {
    context.push('/doctor/${widget.token}/document/${doc.id}', extra: doc);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = widget.bundle.permissions;

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(doctorBundleProvider(widget.token).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Patient Identity & Authorization Header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: Text(widget.bundle.patientName.substring(0, 1).toUpperCase()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.bundle.patientName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            if (widget.bundle.patientDateOfBirth != null)
                              Text('DOB: ${formatDate(widget.bundle.patientDateOfBirth)}', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.shield_outlined, size: 16),
                        label: const Text('Authorized Share'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Viewing records within the scope explicitly consented by the patient. Every request and document retrieval is verified server-side.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // DOCTOR AI ASSISTANT SECTION (patient-history aware, multi-turn)
          DoctorAiPanel(shareIdOrToken: widget.token, bundle: widget.bundle),
          const SizedBox(height: 16),

          // DOCUMENTS SECTION (INTERACTIVE)
          if (widget.bundle.documents.isNotEmpty)
            _SectionCard(
              icon: Icons.folder_outlined,
              title: 'Documents (${widget.bundle.documents.length})',
              child: Column(
                children: [
                  for (final d in widget.bundle.documents)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(categoryIcon(d.category), size: 18),
                      ),
                      title: Text(d.originalName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${formatDate(d.eventDate)} • ${titleCase(d.category)} • ${formatBigBytes(d.size)}', style: theme.textTheme.bodySmall),
                      trailing: FilledButton.tonal(
                        onPressed: () => _viewDocument(d),
                        child: const Text('View / Download'),
                      ),
                      onTap: () => _viewDocument(d),
                    ),
                ],
              ),
            ),

          // LAB RESULTS SECTION
          if (permissions['observations'] == true && widget.bundle.observations.isNotEmpty)
            _SectionCard(
              icon: Icons.science_outlined,
              title: 'Lab Results (${widget.bundle.observations.length})',
              child: Column(
                children: [
                  for (final o in widget.bundle.observations)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.testName, style: TextStyle(fontWeight: o.abnormal == true ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text('${o.providerName ?? 'Clinical lab'} • ${formatDate(o.date)}', style: theme.textTheme.bodySmall),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (o.abnormal == true) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(4)),
                              child: Text('Abnormal', style: TextStyle(fontSize: 10, color: theme.colorScheme.onErrorContainer)),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(o.displayValue, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // MEDICATIONS SECTION
          if (permissions['medications'] == true && widget.bundle.medications.isNotEmpty)
            _SectionCard(
              icon: Icons.medication_outlined,
              title: 'Medications (${widget.bundle.medications.length})',
              child: Column(
                children: [
                  for (final m in widget.bundle.medications)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([m.strength, m.frequency, m.route, m.status].whereType<String>().join(' • '), style: theme.textTheme.bodySmall),
                      trailing: Icon(m.isActive ? Icons.check_circle : Icons.circle_outlined, size: 16, color: m.isActive ? Colors.green : Colors.grey),
                    ),
                ],
              ),
            ),

          // ALLERGIES SECTION
          if (permissions['allergies'] == true && widget.bundle.allergies.isNotEmpty)
            _SectionCard(
              icon: Icons.report_problem_outlined,
              title: 'Allergies (${widget.bundle.allergies.length})',
              child: Column(
                children: [
                  for (final a in widget.bundle.allergies)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.substance, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([a.severity, a.reaction].whereType<String>().join(' • '), style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),

          // CONDITIONS SECTION
          if (permissions['timeline'] == true && widget.bundle.conditions.isNotEmpty)
            _SectionCard(
              icon: Icons.health_and_safety_outlined,
              title: 'Conditions (${widget.bundle.conditions.length})',
              child: Column(
                children: [
                  for (final c in widget.bundle.conditions)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(c.status ?? '', style: theme.textTheme.bodySmall),
                      trailing: Text(formatDate(c.onsetDate), style: theme.textTheme.labelSmall),
                    ),
                ],
              ),
            ),

          // DUPLICATE-TEST ALERTS SECTION
          if (permissions['duplicateAlerts'] == true && widget.bundle.duplicateAlerts.isNotEmpty)
            _SectionCard(
              icon: Icons.content_copy_outlined,
              title: 'Duplicate-Test Alerts (${widget.bundle.duplicateAlerts.length})',
              child: Column(
                children: [
                  for (final f in widget.bundle.duplicateAlerts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${f.normalizedTestName}: ${f.reason}', style: theme.textTheme.bodySmall)),
                          if (f.gapDays != null) Text('${f.gapDays}d apart', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // MEDICATION SAFETY ALERTS
          if (widget.bundle.medicationAlerts != null &&
              (widget.bundle.medicationAlerts!.interactions.isNotEmpty || widget.bundle.medicationAlerts!.duplicates.isNotEmpty))
            _SectionCard(
              icon: Icons.warning_amber_outlined,
              title: 'Medication Safety Alerts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final i in widget.bundle.medicationAlerts!.interactions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• ${i.title} — ${i.effect}', style: theme.textTheme.bodySmall),
                    ),
                  for (final d in widget.bundle.medicationAlerts!.duplicates)
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

          const SizedBox(height: 16),
          Text(
            'Authorized access only. Every action is logged in the patient\'s audit history.',
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