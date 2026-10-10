import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/features/auth/login_screen.dart';
import 'package:health_wallet/features/doctor/pending_verification_screen.dart';
import 'package:health_wallet/features/documents/documents_screen.dart';
import 'package:health_wallet/features/medications/medications_screen.dart';
import 'package:health_wallet/features/medications/safety_screen.dart';
import 'package:health_wallet/features/reminders/add_medication_screen.dart';
import 'package:health_wallet/features/reminders/reminders_screen.dart';
import 'package:health_wallet/models/models.dart';
import 'package:health_wallet/providers/providers.dart';

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('Login screen shows demo-account fill chips', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _host(const LoginScreen())));
    await tester.pump();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Demo accounts (seeded)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('Medications screen lists active medications', (tester) async {
    final med = Medication(
      id: 'm1',
      name: 'Metformin',
      status: 'active',
      verification: 'verified',
      strength: '500 mg',
      frequency: 'Twice daily',
    );
    final past = Medication(
      id: 'm2',
      name: 'Amoxicillin',
      status: 'completed',
      verification: 'unverified',
    );
    final report = MedicationSafetyReport(checkerAvailable: true);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        medicationsProvider.overrideWith((ref) async => [med, past]),
        medicationSafetyProvider.overrideWith((ref) async => report),
      ],
      child: _host(const MedicationsScreen()),
    ));
    await tester.pump(); // start async
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Past / completed'), findsOneWidget);
  });

  testWidgets('Safety screen renders interactions from the dataset', (tester) async {
    final report = MedicationSafetyReport(
      checkerAvailable: true,
      interactions: [
        InteractionAlert(
          title: 'Warfarin + Ibuprofen',
          severity: 'major',
          effect: 'Increased bleeding risk.',
          recommendation: 'Avoid combination; review with prescriber.',
          medications: const ['Warfarin', 'Ibuprofen'],
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        medicationSafetyProvider.overrideWith((ref) async => report),
      ],
      child: _host(const SafetyScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Warfarin + Ibuprofen'), findsWidgets);
    expect(find.text('Interactions'), findsOneWidget);
    expect(find.text('Increased bleeding risk.'), findsWidgets);
  });

  testWidgets('Safety screen explicitly states checker availability', (tester) async {
    final report = MedicationSafetyReport(
      checkerAvailable: false,
      interactions: const [],
      duplicates: const [],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        medicationSafetyProvider.overrideWith((ref) async => report),
      ],
      child: _host(const SafetyScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Safety checker unavailable'), findsOneWidget);
  });

  testWidgets('Documents screen lists uploaded documents', (tester) async {
    final doc = DocumentSummary(
      id: 'd1',
      originalName: 'blood_panel.pdf',
      category: 'laboratory',
      mimeType: 'application/pdf',
      size: 2048,
      extractionStatus: 'extracted',
      providerName: 'City Labs',
      eventDate: DateTime(2026, 1, 15),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        documentsProvider.overrideWith((ref) async => [doc]),
      ],
      child: _host(const DocumentsScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('blood_panel.pdf'), findsOneWidget);
    expect(find.text('Extracted'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('Documents screen shows an empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        documentsProvider.overrideWith((ref) async => []),
      ],
      child: _host(const DocumentsScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('Pending verification screen states that unverified doctors cannot access records', (tester) async {
    final unverified = User(id: 'd1', name: 'Dr. Maya Rao', email: 'doctor@demo.health', role: 'doctor', doctorVerification: 'unverified');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _PendingAuthNotifier(unverified)),
      ],
      child: MaterialApp(home: const PendingVerificationScreen()),
    ));
    await tester.pump();

    expect(find.text('Verification pending'), findsOneWidget);
    expect(find.textContaining('cannot view or claim patient records'), findsOneWidget);
  });

  testWidgets('Login screen tracks the selected role', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _host(const LoginScreen())));
    await tester.pump();

    // Default selection is Patient; switch to Doctor.
    expect(find.text('Signing in as'), findsOneWidget);
    await tester.tap(find.text('Doctor'));
    await tester.pump();
    expect(find.text('Doctor view is only for verified doctor accounts.'), findsOneWidget);
  });

  testWidgets('Reminders screen lists today doses with their derived status', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayDosesProvider.overrideWith((ref) async => [
              DoseOccurrence(id: 'd1', scheduleId: 's1', scheduledFor: now, status: 'TAKEN', scheduleName: 'Metformin'),
              DoseOccurrence(
                  id: 'd2',
                  scheduleId: 's1',
                  scheduledFor: now.add(const Duration(hours: 1)),
                  status: 'DUE',
                  scheduleName: 'Amlodipine'),
            ]),
        upcomingDosesProvider.overrideWith((ref) async => []),
        schedulesProvider.overrideWith((ref) async => []),
      ],
      child: _host(const RemindersScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Medication reminders'), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Amlodipine'), findsOneWidget);
    expect(find.text('Due now'), findsOneWidget);
  });

  testWidgets('Reminders screen shows an empty state when nothing is due', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayDosesProvider.overrideWith((ref) async => []),
        upcomingDosesProvider.overrideWith((ref) async => []),
        schedulesProvider.overrideWith((ref) async => []),
      ],
      child: _host(const RemindersScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Nothing due today'), findsOneWidget);
  });

  testWidgets('Add medication validates the medicine name before saving', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _host(const AddMedicationScreen())));
    await tester.pump();

    final label = find.text('Review & save');
    await tester.scrollUntilVisible(label, 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(label);
    await tester.pump();

    expect(find.text('Medicine name is required.'), findsOneWidget);
  });
}

/// Minimal auth notifier exposing an authenticated, unverified doctor.
class _PendingAuthNotifier extends AuthNotifier {
  _PendingAuthNotifier(this._user);

  final User _user;

  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated, user: _user);
}