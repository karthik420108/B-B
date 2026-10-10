import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:health_wallet/features/documents/document_detail_screen.dart';
import 'package:health_wallet/models/models.dart';

DocumentDetail _detail() => DocumentDetail(
      document: DocumentSummary(
        id: 'd1',
        originalName: 'lab.pdf',
        category: 'laboratory',
        mimeType: 'application/pdf',
        size: 1024,
        extractionStatus: 'extracted',
      ),
      extracted: ExtractedBundle(),
    );

void main() {
  testWidgets('Document screen offers a back control even when it opened a fresh stack', (tester) async {
    // `initialLocation` means nothing to pop - exactly the state the upload
    // success sheet used to leave the user in, with no back arrow at all.
    final router = GoRouter(
      initialLocation: '/documents/d1',
      routes: [
        GoRoute(path: '/documents', builder: (c, s) => const Scaffold(body: Text('documents list'))),
        GoRoute(path: '/documents/:id', builder: (c, s) => const DocumentDetailScreen(id: 'd1')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [documentDetailProvider('d1').overrideWith((ref) async => _detail())],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('documents list'), findsOneWidget,
        reason: 'back should return to the documents list rather than doing nothing');
  });
}
