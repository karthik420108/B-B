import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:health_wallet/core/network/api_client.dart';
import 'package:health_wallet/core/storage/token_storage.dart';
import 'package:health_wallet/features/doctor/doctor_bundle_screen.dart';
import 'package:health_wallet/features/doctor/doctor_document_view_screen.dart';
import 'package:health_wallet/models/models.dart';
import 'package:health_wallet/providers/providers.dart';
import 'package:health_wallet/services/doctor_repository.dart';

class _FakeDoctorRepo extends DoctorRepository {
  _FakeDoctorRepo() : super(ApiClient(TokenStorage()));

  @override
  Future<List<int>> downloadDocumentBytes(String shareIdOrToken, String docId) async {
    return 'Patient clinical blood test report: RBC normal, WBC normal'.codeUnits;
  }
}

DocumentSummary _testDoc() => DocumentSummary(
      id: 'doc-123',
      originalName: 'blood_test_report.txt',
      category: 'laboratory',
      mimeType: 'text/plain',
      size: 1024,
      extractionStatus: 'extracted',
      providerName: 'City Hospital Lab',
    );

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('DoctorDocumentViewScreen renders document details, back button, and download options', (tester) async {
    _useTallViewport(tester);
    final router = GoRouter(
      initialLocation: '/doctor/tok123/document/doc-123',
      routes: [
        GoRoute(
          path: '/doctor/:token',
          builder: (c, s) => const Scaffold(body: Text('doctor bundle page')),
        ),
        GoRoute(
          path: '/doctor/:token/document/:docId',
          builder: (c, s) => DoctorDocumentViewScreen(
            token: s.pathParameters['token']!,
            docId: s.pathParameters['docId']!,
            initialDoc: _testDoc(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          doctorRepositoryProvider.overrideWithValue(_FakeDoctorRepo()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify document details are rendered
    expect(find.text('blood_test_report.txt'), findsWidgets);
    expect(find.textContaining('City Hospital Lab'), findsOneWidget);
    expect(find.text('Download Document'), findsOneWidget);
    expect(find.text('Patient clinical blood test report: RBC normal, WBC normal'), findsOneWidget);

    // Verify back button takes doctor back to bundle page
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('doctor bundle page'), findsOneWidget);
  });

  testWidgets('DoctorBundleScreen navigates to DoctorDocumentViewScreen on document tap', (tester) async {
    _useTallViewport(tester);
    final testBundle = DoctorBundle(
      shareId: 'tok123',
      patientName: 'Jane Doe',
      permissions: {'documents': true},
      documents: [_testDoc()],
      observations: [],
      medications: [],
      allergies: [],
      conditions: [],
      duplicateAlerts: [],
      medicationAlerts: null,
    );

    final router = GoRouter(
      initialLocation: '/doctor/tok123',
      routes: [
        GoRoute(
          path: '/doctor/:token',
          builder: (c, s) => const DoctorBundleScreen(token: 'tok123'),
        ),
        GoRoute(
          path: '/doctor/:token/document/:docId',
          builder: (c, s) => DoctorDocumentViewScreen(
            token: s.pathParameters['token']!,
            docId: s.pathParameters['docId']!,
            initialDoc: s.extra as DocumentSummary?,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          doctorRepositoryProvider.overrideWithValue(_FakeDoctorRepo()),
          doctorBundleProvider('tok123').overrideWith((ref) async => testBundle),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify document appears with "View / Download" button
    expect(find.text('blood_test_report.txt'), findsWidgets);
    expect(find.text('View / Download'), findsOneWidget);

    // Tap "View / Download"
    await tester.tap(find.text('View / Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify we arrived on the new page
    expect(find.text('Download Document'), findsOneWidget);
  });
}
