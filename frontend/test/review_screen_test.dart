import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/features/documents/document_detail_screen.dart'
    show documentDetailProvider;
import 'package:health_wallet/features/documents/review_screen.dart';
import 'package:health_wallet/models/models.dart';

Widget _host(Widget child) => MaterialApp(home: child);

DocumentDetail _detail(List<Observation> observations) => DocumentDetail(
      document: DocumentSummary(
        id: 'd1',
        originalName: 'panel.pdf',
        category: 'laboratory',
        mimeType: 'application/pdf',
        size: 1024,
        extractionStatus: 'extracted',
      ),
      extracted: ExtractedBundle(observations: observations),
    );

Future<void> _pump(WidgetTester tester, DocumentDetail detail) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [documentDetailProvider('d1').overrideWith((ref) async => detail)],
    child: _host(const ReviewScreen(id: 'd1')),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Observation _obs(String id, String name, String verification) =>
    Observation(id: id, testName: name, verification: verification, value: 6.1);

void main() {
  testWidgets('shows a way back while records are still unreviewed', (tester) async {
    await _pump(tester, _detail([
      _obs('o1', 'HbA1c', 'unverified'),
      _obs('o2', 'Hemoglobin', 'unverified'),
    ]));

    expect(find.text('0 of 2 reviewed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Back to document'), findsOneWidget);

    // Leaving with records outstanding asks for confirmation first.
    await tester.tap(find.widgetWithText(FilledButton, 'Back to document'));
    await tester.pumpAndSettle();
    expect(find.text('Leave review?'), findsOneWidget);
    expect(find.textContaining('2 records are still unreviewed'), findsOneWidget);

    await tester.tap(find.text('Keep reviewing'));
    await tester.pumpAndSettle();
    expect(find.text('Leave review?'), findsNothing);
    expect(find.text('0 of 2 reviewed'), findsOneWidget);
  });

  testWidgets('counts records verified earlier (server state) as reviewed', (tester) async {
    await _pump(tester, _detail([
      _obs('o1', 'HbA1c', 'verified'),
      _obs('o2', 'Hemoglobin', 'unverified'),
    ]));

    expect(find.text('1 of 2 reviewed'), findsOneWidget);
    // The reviewed one is struck through with no action buttons left on it.
    expect(find.text('HbA1c'), findsOneWidget);
    expect(find.text('Reviewed'), findsOneWidget);
  });

  testWidgets('offers a Done action and a completion card once everything is reviewed', (tester) async {
    await _pump(tester, _detail([
      _obs('o1', 'HbA1c', 'verified'),
      _obs('o2', 'Hemoglobin', 'rejected'),
    ]));

    expect(find.text('All 2 records reviewed'), findsNWidgets(2)); // footer + card
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'View document'), findsOneWidget);
    expect(find.text('Everything is saved to your file.'), findsOneWidget);
  });

  testWidgets('says so when the document proposed nothing to review', (tester) async {
    await _pump(tester, _detail([]));

    expect(find.text('Nothing to review'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Back to document'), findsOneWidget);
    expect(find.text('Leave review?'), findsNothing);
  });
}
